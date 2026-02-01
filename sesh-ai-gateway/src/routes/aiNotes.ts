import fs from 'node:fs';
import path from 'node:path';

import { Router, Request } from 'express';
import { FieldValue } from 'firebase-admin/firestore';

import { extractTextFromPdf } from '../services/docExtract';
import { extractImagesFromPdf } from '../services/pdfImageExtract';
import { renderPdfFromHtml } from '../services/pdfRenderer';
import { callTextModel } from '../services/modelRouter';
import { aiLogsCollection } from '../services/firestoreService';
import { generateSignedReadUrl, uploadBufferToStorage } from '../services/storageService';
import { config } from '../utils/env';

type PolicyGateInput = {
  userId?: string;
  text: string;
  contextType: 'notes';
  contentHint?: string;
};

type PolicyGateResponse = {
  allowed: boolean;
  category: 'school' | 'non_school' | 'unknown';
  intent: 'socratic_help' | 'answer_seeking' | 'content_generation' | 'other';
  recommendTutor: boolean;
  reason?: 'school_only' | 'rate_limited' | 'blocked';
  nextStep?: string;
};

type NotesEnhanceRequest = {
  userId?: string;
  pdfSignedUrl: string;
  subject?: string;
};

type SmartNotesSection = {
  heading: string;
  bullets: string[];
  keyTakeaways: string[];
  commonMistakes: string[];
  miniQuiz: { q: string; hint: string }[];
};

type SmartNotes = {
  title: string;
  subject: string;
  sections: SmartNotesSection[];
  diagramCaptions: { pageNumber: number; caption: string }[];
};

type NotesEnhanceResponse = {
  smartNotesPdfUrl: string;
  extractedTopics: string[];
  confidence: number;
};

const router = Router();

function getTemplatePath(): string {
  return path.join(__dirname, '..', 'templates', 'smart-notes.html');
}

function renderTemplate(template: string, vars: Record<string, string>): string {
  let html = template;
  for (const [key, value] of Object.entries(vars)) {
    const pattern = new RegExp(`{{\\s*${key}\\s*}}`, 'g');
    html = html.replace(pattern, value);
  }
  return html;
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/\"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

function buildSectionsHtml(sections: SmartNotesSection[]): string {
  return sections
    .map((section) => {
      const bullets = section.bullets.map((item) => `<li>${escapeHtml(item)}</li>`).join('');
      const takeaways = section.keyTakeaways
        .map((item) => `<li>${escapeHtml(item)}</li>`)
        .join('');
      const mistakes = section.commonMistakes
        .map((item) => `<li>${escapeHtml(item)}</li>`)
        .join('');
      const quiz = section.miniQuiz
        .map(
          (item) =>
            `<div><strong>Q:</strong> ${escapeHtml(item.q)}<br /><em>Hint:</em> ${escapeHtml(item.hint)}</div>`,
        )
        .join('');

      return `
        <section class="section">
          <h2>${escapeHtml(section.heading)}</h2>
          <ul class="bullets">${bullets}</ul>
          <div class="callout">
            <strong>Key takeaways</strong>
            <ul class="bullets">${takeaways}</ul>
          </div>
          <div class="mistakes">
            <strong>Common mistakes</strong>
            <ul class="bullets">${mistakes}</ul>
          </div>
          <div class="mini-quiz">
            <strong>Mini quiz</strong>
            ${quiz}
          </div>
        </section>
      `;
    })
    .join('\n');
}

function buildDiagramHtml(diagrams: SmartNotes['diagramCaptions']): string {
  if (!diagrams.length) return '';
  const items = diagrams
    .map(
      (diagram) =>
        `<div class="diagram"><strong>Diagram (page ${diagram.pageNumber})</strong><br />${escapeHtml(diagram.caption)}</div>`,
    )
    .join('');
  return `<section class="section"><h2>Diagram Captions</h2>${items}</section>`;
}

function safeJsonParse(text: string): Record<string, unknown> | null {
  try {
    return JSON.parse(text);
  } catch {
    const match = text.match(/\{[\s\S]*\}/);
    if (!match) return null;
    try {
      return JSON.parse(match[0]);
    } catch {
      return null;
    }
  }
}

function normalizeStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.map((item) => String(item)).filter((item) => item.trim().length > 0);
}

function normalizeSmartNotes(raw: Record<string, unknown>, fallbackSubject: string): SmartNotes {
  const sectionsRaw = Array.isArray(raw.sections) ? raw.sections : [];
  const sections: SmartNotesSection[] = sectionsRaw.map((section) => ({
    heading: String((section as SmartNotesSection).heading ?? 'Topic'),
    bullets: normalizeStringArray((section as SmartNotesSection).bullets),
    keyTakeaways: normalizeStringArray((section as SmartNotesSection).keyTakeaways),
    commonMistakes: normalizeStringArray((section as SmartNotesSection).commonMistakes),
    miniQuiz: Array.isArray((section as SmartNotesSection).miniQuiz)
      ? (section as SmartNotesSection).miniQuiz.map((item) => ({
          q: String(item.q ?? ''),
          hint: String(item.hint ?? ''),
        }))
      : [],
  }));

  return {
    title: String(raw.title ?? 'Smart Notes'),
    subject: String(raw.subject ?? fallbackSubject ?? 'Study Notes'),
    sections: sections.length ? sections : [],
    diagramCaptions: Array.isArray(raw.diagramCaptions)
      ? raw.diagramCaptions.map((item) => ({
          pageNumber: Number(item.pageNumber ?? 0) || 0,
          caption: String(item.caption ?? ''),
        }))
      : [],
  };
}

function buildExtractedTopics(sections: SmartNotesSection[], subject?: string): string[] {
  const topics = new Set<string>();
  if (subject) topics.add(subject);
  sections.forEach((section) => {
    if (section.heading) topics.add(section.heading);
  });
  return Array.from(topics).slice(0, 8);
}

function calculateConfidence(fullText: string, isScanned: boolean, topics: string[]): number {
  const lengthScore = Math.min(1, fullText.length / 5000);
  let confidence = 0.4 + lengthScore * 0.5;
  if (isScanned) confidence -= 0.1;
  if (topics.length < 2) confidence -= 0.1;
  return Math.max(0.2, Math.min(confidence, 0.95));
}

async function callPolicyGate(req: Request, payload: PolicyGateInput): Promise<PolicyGateResponse> {
  const authHeader = req.header('authorization') || '';
  const response = await fetch(`http://127.0.0.1:${config.port}/ai/policy/gate/notes`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: authHeader,
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Policy gate failed ${response.status}: ${text}`);
  }

  return (await response.json()) as PolicyGateResponse;
}

async function downloadBuffer(url: string): Promise<Buffer> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to download PDF: ${response.status} ${response.statusText}`);
  }
  const arrayBuffer = await response.arrayBuffer();
  return Buffer.from(arrayBuffer);
}

async function generateSmartNotes(
  textSnippet: string,
  subject: string,
  diagrams: { pageNumber: number; count: number }[],
): Promise<SmartNotes> {
  const provider = config.model.provider;
  const model = provider === 'openai' ? config.model.openai.model : config.model.google.model;
  const maxTokens = config.maxTokensPerEndpoint['POST /ai/notes/enhance'];
  const system = [
    'You are a study coach creating Smart Notes for students.',
    'Return JSON only with keys: title, subject, sections, diagramCaptions.',
    'Each section: heading, bullets[], keyTakeaways[], commonMistakes[], miniQuiz[{q,hint}].',
    'School-only. No full solutions. Keep it engaging and concise.',
    'If you see diagrams, provide captions by page number.',
  ].join('\n');

  const payload = {
    subject,
    snippet: textSnippet,
    diagramPages: diagrams,
  };

  const output = await callTextModel({
    provider,
    model,
    jsonOnly: true,
    temperature: 0.3,
    maxTokens,
    messages: [
      { role: 'system', content: system },
      { role: 'user', content: JSON.stringify(payload) },
    ],
  });

  const parsed = safeJsonParse(output);
  return normalizeSmartNotes(parsed ?? {}, subject);
}

async function logDecision(payload: Record<string, unknown>): Promise<void> {
  try {
    await aiLogsCollection().add({
      ...payload,
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (error) {
    console.error('Failed to log notes enhance decision', error);
  }
}

router.post('/ai/notes/enhance', async (req, res) => {
  const body = (req.body ?? {}) as NotesEnhanceRequest;
  const pdfSignedUrl = body.pdfSignedUrl?.trim();
  const subject = body.subject?.trim() || 'Study Notes';

  if (!pdfSignedUrl) {
    res.status(400).json({ error: 'invalid_request', message: 'pdfSignedUrl is required.' });
    return;
  }

  const authedUserId = req.user?.uid;
  if (authedUserId && body.userId && body.userId !== authedUserId) {
    res.status(403).json({ error: 'user_mismatch' });
    return;
  }

  const userId = authedUserId || body.userId;
  if (!userId) {
    res.status(401).json({ error: 'missing_user' });
    return;
  }

  const pdfBuffer = await downloadBuffer(pdfSignedUrl);
  const extracted = await extractTextFromPdf(pdfBuffer);
  const snippet = extracted.fullText.slice(0, 1200);

  let policy: PolicyGateResponse;
  try {
    policy = await callPolicyGate(req, {
      userId,
      text: `${subject}\n${snippet}`,
      contextType: 'notes',
      contentHint: subject,
    });
  } catch (error) {
    console.error('Policy gate error', error);
    res.status(502).json({ error: 'policy_gate_unavailable' });
    return;
  }

  if (!policy.allowed) {
    await logDecision({
      type: 'notes_enhance',
      userId,
      allowed: false,
      reason: policy.reason ?? 'school_only',
      subject,
      requestId: req.requestId || null,
    });
    res.status(403).json({
      error: 'policy_blocked',
      message:
        policy.nextStep ||
        'I can only generate smart notes for school-related material.',
    });
    return;
  }

  let diagramPages: { pageNumber: number; count: number }[] = [];
  try {
    const pageImages = await extractImagesFromPdf(pdfBuffer);
    diagramPages = pageImages
      .filter((page) => page.images.length > 0)
      .map((page) => ({ pageNumber: page.pageNumber, count: page.images.length }));
  } catch (error) {
    console.error('PDF image extraction failed', error);
  }

  const smartNotes = await generateSmartNotes(snippet, subject, diagramPages);
  const sectionsHtml = buildSectionsHtml(smartNotes.sections);
  const diagramsHtml = buildDiagramHtml(smartNotes.diagramCaptions);

  const template = fs.readFileSync(getTemplatePath(), 'utf8');
  const html = renderTemplate(template, {
    TITLE: escapeHtml(smartNotes.title),
    SUBJECT: escapeHtml(smartNotes.subject),
    SECTIONS: sectionsHtml,
    DIAGRAMS: diagramsHtml,
    GENERATED_AT: new Date().toISOString(),
  });

  const pdfOut = await renderPdfFromHtml(html);
  const gsPath = `users/${userId}/ai/notes/${Date.now()}.pdf`;
  const storedPath = await uploadBufferToStorage(pdfOut, gsPath, 'application/pdf');
  const signedUrl = await generateSignedReadUrl(storedPath, 60);

  const extractedTopics = buildExtractedTopics(smartNotes.sections, subject);
  const confidence = calculateConfidence(extracted.fullText, extracted.isScanned, extractedTopics);

  await logDecision({
    type: 'notes_enhance',
    userId,
    allowed: true,
    subject,
    extractedTopics,
    confidence,
    requestId: req.requestId || null,
  });

  const response: NotesEnhanceResponse = {
    smartNotesPdfUrl: signedUrl,
    extractedTopics,
    confidence,
  };

  res.json(response);
});

export default router;
