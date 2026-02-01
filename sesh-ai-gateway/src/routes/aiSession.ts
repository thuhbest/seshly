import fs from 'node:fs';
import path from 'node:path';

import { Router, Request } from 'express';
import { FieldValue } from 'firebase-admin/firestore';

import { extractTextFromImage } from '../services/docExtract';
import { callTextModel } from '../services/modelRouter';
import { aiLogsCollection } from '../services/firestoreService';
import { uploadBufferToStorage, generateSignedReadUrl } from '../services/storageService';
import { renderPdfFromHtml } from '../services/pdfRenderer';
import { config } from '../utils/env';

type ChatLogEntry = {
  senderId: string;
  text: string;
  ts?: string | number;
};

type Participant = {
  userId: string;
  role: 'tutor' | 'student';
};

type SessionSummarizeRequest = {
  userId?: string;
  sessionId: string;
  boardSnapshotSignedUrls: string[];
  chatLog: ChatLogEntry[];
  subject?: string;
  participants: Participant[];
};

type SessionSummarizeResponse = {
  pdfUrlsByStudent: Record<string, string>;
  topics: string[];
  actionItems: string[];
};

type PolicyGateInput = {
  userId?: string;
  text: string;
  contextType: 'session';
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

type SmartSessionNotes = {
  title: string;
  subject: string;
  topics: string[];
  keyPoints: string[];
  definitions: string[];
  diagramCaptions: { pageNumber: number; caption: string }[];
  exampleQuestions: string[];
  practiceQuestions: string[];
  actionPlan: string[];
};

const router = Router();

function getTemplatePath(): string {
  return path.join(__dirname, '..', 'templates', 'session-summary.html');
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
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

function buildListItems(items: string[], emptyFallback = ''): string {
  if (!items.length) return emptyFallback ? `<li>${escapeHtml(emptyFallback)}</li>` : '';
  return items.map((item) => `<li>${escapeHtml(item)}</li>`).join('');
}

function buildDiagramItems(diagrams: SmartSessionNotes['diagramCaptions']): string {
  if (!diagrams.length) return '';
  return diagrams
    .map(
      (diagram) =>
        `<li><strong>Page ${diagram.pageNumber || 0}</strong>: ${escapeHtml(diagram.caption)}</li>`,
    )
    .join('');
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
  return value.map((item) => String(item)).map((item) => item.trim()).filter((item) => item.length > 0);
}

function normalizeSessionNotes(raw: Record<string, unknown>, subject: string): SmartSessionNotes {
  return {
    title: String(raw.title ?? 'Session Summary'),
    subject: String(raw.subject ?? subject),
    topics: normalizeStringArray(raw.topics).slice(0, 10),
    keyPoints: normalizeStringArray(raw.keyPoints).slice(0, 12),
    definitions: normalizeStringArray(raw.definitions).slice(0, 12),
    diagramCaptions: Array.isArray(raw.diagramCaptions)
      ? raw.diagramCaptions.map((item) => ({
          pageNumber: Number((item as Record<string, unknown>).pageNumber ?? 0) || 0,
          caption: String((item as Record<string, unknown>).caption ?? ''),
        }))
      : [],
    exampleQuestions: normalizeStringArray(raw.exampleQuestions).slice(0, 8),
    practiceQuestions: normalizeStringArray(raw.practiceQuestions).slice(0, 8),
    actionPlan: normalizeStringArray(raw.actionPlan).slice(0, 8),
  };
}

function buildSessionRepresentation(ocrResults: string[], chatLog: ChatLogEntry[], subject: string): string {
  const ocrText = ocrResults
    .map((text, index) => `Board ${index + 1}: ${text}`)
    .join('\n')
    .slice(0, 6000);

  const chatText = chatLog
    .slice(-120)
    .map((entry) => `${entry.senderId}: ${entry.text}`)
    .join('\n')
    .slice(0, 6000);

  return [
    `Subject: ${subject}`,
    'Board OCR:',
    ocrText || '[no board text]',
    'Chat log:',
    chatText || '[no chat log]',
  ].join('\n');
}

async function callPolicyGate(req: Request, payload: PolicyGateInput): Promise<PolicyGateResponse> {
  const authHeader = req.header('authorization') || '';
  const response = await fetch(`http://127.0.0.1:${config.port}/ai/policy/gate/session`, {
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

async function logDecision(payload: Record<string, unknown>): Promise<void> {
  try {
    await aiLogsCollection().add({
      ...payload,
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (error) {
    console.error('Failed to log session summary event', error);
  }
}

async function downloadBuffer(url: string): Promise<Buffer> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to download snapshot: ${response.status} ${response.statusText}`);
  }
  const arrayBuffer = await response.arrayBuffer();
  return Buffer.from(arrayBuffer);
}

router.post('/ai/session/summarize', async (req, res) => {
  const body = (req.body ?? {}) as SessionSummarizeRequest;
  const sessionId = body.sessionId?.trim();
  const subject = body.subject?.trim() || 'Study Session';
  const boardSnapshotSignedUrls = Array.isArray(body.boardSnapshotSignedUrls)
    ? body.boardSnapshotSignedUrls.map((url) => String(url).trim()).filter((url) => url.length > 0)
    : [];
  const chatLog = Array.isArray(body.chatLog)
    ? body.chatLog
        .map((entry) => ({
          senderId: String(entry.senderId ?? '').trim(),
          text: String(entry.text ?? '').trim(),
          ts: entry.ts,
        }))
        .filter((entry) => entry.senderId && entry.text)
    : [];
  const participants = Array.isArray(body.participants) ? body.participants : [];

  if (!sessionId) {
    res.status(400).json({ error: 'invalid_request', message: 'sessionId is required.' });
    return;
  }

  if (!participants.length) {
    res.status(400).json({ error: 'invalid_request', message: 'participants are required.' });
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

  const studentIds = participants
    .filter((participant) => participant?.role === 'student' && participant.userId)
    .map((participant) => participant.userId);

  if (!studentIds.length) {
    res.status(400).json({ error: 'no_students', message: 'No student participants provided.' });
    return;
  }

  const ocrResults: string[] = [];
  for (const url of boardSnapshotSignedUrls) {
    try {
      const buffer = await downloadBuffer(url);
      const result = await extractTextFromImage(buffer);
      if (result.text) ocrResults.push(result.text);
    } catch (error) {
      console.error('Board snapshot OCR failed', error);
    }
  }

  const sessionRepresentation = buildSessionRepresentation(ocrResults, chatLog, subject);
  const policySnippet = sessionRepresentation.slice(0, 1200);

  let policy: PolicyGateResponse;
  try {
    policy = await callPolicyGate(req, {
      userId,
      text: policySnippet,
      contextType: 'session',
      contentHint: JSON.stringify({ sessionId, participants: studentIds.length }),
    });
  } catch (error) {
    console.error('Policy gate error', error);
    res.status(502).json({ error: 'policy_gate_unavailable' });
    return;
  }

  if (!policy.allowed) {
    await logDecision({
      type: 'session_summarize',
      userId,
      allowed: false,
      reason: policy.reason ?? 'school_only',
      sessionId,
      requestId: req.requestId || null,
    });
    res.status(403).json({
      error: 'policy_blocked',
      message: policy.nextStep || 'I can only summarize school-related sessions.',
    });
    return;
  }

  const provider = config.model.provider;
  const model = provider === 'openai' ? config.model.openai.model : config.model.google.model;
  const maxTokens = config.maxTokensPerEndpoint['POST /ai/session/summarize'];
  const systemPrompt = [
    'You summarize tutoring sessions for students.',
    'Return JSON only with keys: title, subject, topics, keyPoints, definitions, diagramCaptions, exampleQuestions, practiceQuestions, actionPlan.',
    'No full worked solutions or final answers.',
    'Use diagramCaptions as [{pageNumber, caption}].',
    'Keep responses concise and student-friendly.',
  ].join('\n');

  const output = await callTextModel({
    provider,
    model,
    jsonOnly: true,
    temperature: 0.2,
    maxTokens,
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: sessionRepresentation.slice(0, 8000) },
    ],
  });

  const parsed = safeJsonParse(output) ?? {};
  const notes = normalizeSessionNotes(parsed, subject);
  const topics = notes.topics.length ? notes.topics : [notes.subject];
  const actionItems = notes.actionPlan;

  const template = fs.readFileSync(getTemplatePath(), 'utf8');
  const html = renderTemplate(template, {
    TITLE: escapeHtml(notes.title),
    SUBJECT: escapeHtml(notes.subject),
    TOPICS: buildListItems(topics),
    KEY_POINTS: buildListItems(notes.keyPoints),
    DEFINITIONS: buildListItems(notes.definitions),
    DIAGRAMS: buildDiagramItems(notes.diagramCaptions),
    EXAMPLES: buildListItems(notes.exampleQuestions),
    PRACTICE: buildListItems(notes.practiceQuestions),
    ACTION_PLAN: buildListItems(notes.actionPlan),
    GENERATED_AT: new Date().toISOString(),
  });

  const pdfBuffer = await renderPdfFromHtml(html);
  const pdfUrlsByStudent: Record<string, string> = {};

  for (const studentId of studentIds) {
    const gsPath = `users/${studentId}/ai/sessions/${sessionId}.pdf`;
    const storedPath = await uploadBufferToStorage(pdfBuffer, gsPath, 'application/pdf');
    const signedUrl = await generateSignedReadUrl(storedPath, 60);
    pdfUrlsByStudent[studentId] = signedUrl;
  }

  await logDecision({
    type: 'session_summarize',
    userId,
    allowed: true,
    sessionId,
    studentCount: studentIds.length,
    topics,
    requestId: req.requestId || null,
  });

  const response: SessionSummarizeResponse = {
    pdfUrlsByStudent,
    topics,
    actionItems,
  };

  res.json(response);
});

export default router;
