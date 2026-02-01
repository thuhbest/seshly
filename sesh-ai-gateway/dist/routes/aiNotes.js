"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_fs_1 = __importDefault(require("node:fs"));
const node_path_1 = __importDefault(require("node:path"));
const express_1 = require("express");
const firestore_1 = require("firebase-admin/firestore");
const docExtract_1 = require("../services/docExtract");
const pdfImageExtract_1 = require("../services/pdfImageExtract");
const pdfRenderer_1 = require("../services/pdfRenderer");
const modelRouter_1 = require("../services/modelRouter");
const firestoreService_1 = require("../services/firestoreService");
const storageService_1 = require("../services/storageService");
const env_1 = require("../utils/env");
const router = (0, express_1.Router)();
function getTemplatePath() {
    return node_path_1.default.join(__dirname, '..', 'templates', 'smart-notes.html');
}
function renderTemplate(template, vars) {
    let html = template;
    for (const [key, value] of Object.entries(vars)) {
        const pattern = new RegExp(`{{\\s*${key}\\s*}}`, 'g');
        html = html.replace(pattern, value);
    }
    return html;
}
function escapeHtml(value) {
    return value
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/\"/g, '&quot;')
        .replace(/'/g, '&#039;');
}
function buildSectionsHtml(sections) {
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
            .map((item) => `<div><strong>Q:</strong> ${escapeHtml(item.q)}<br /><em>Hint:</em> ${escapeHtml(item.hint)}</div>`)
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
function buildDiagramHtml(diagrams) {
    if (!diagrams.length)
        return '';
    const items = diagrams
        .map((diagram) => `<div class="diagram"><strong>Diagram (page ${diagram.pageNumber})</strong><br />${escapeHtml(diagram.caption)}</div>`)
        .join('');
    return `<section class="section"><h2>Diagram Captions</h2>${items}</section>`;
}
function safeJsonParse(text) {
    try {
        return JSON.parse(text);
    }
    catch {
        const match = text.match(/\{[\s\S]*\}/);
        if (!match)
            return null;
        try {
            return JSON.parse(match[0]);
        }
        catch {
            return null;
        }
    }
}
function normalizeStringArray(value) {
    if (!Array.isArray(value))
        return [];
    return value.map((item) => String(item)).filter((item) => item.trim().length > 0);
}
function normalizeSmartNotes(raw, fallbackSubject) {
    const sectionsRaw = Array.isArray(raw.sections) ? raw.sections : [];
    const sections = sectionsRaw.map((section) => ({
        heading: String(section.heading ?? 'Topic'),
        bullets: normalizeStringArray(section.bullets),
        keyTakeaways: normalizeStringArray(section.keyTakeaways),
        commonMistakes: normalizeStringArray(section.commonMistakes),
        miniQuiz: Array.isArray(section.miniQuiz)
            ? section.miniQuiz.map((item) => ({
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
function buildExtractedTopics(sections, subject) {
    const topics = new Set();
    if (subject)
        topics.add(subject);
    sections.forEach((section) => {
        if (section.heading)
            topics.add(section.heading);
    });
    return Array.from(topics).slice(0, 8);
}
function calculateConfidence(fullText, isScanned, topics) {
    const lengthScore = Math.min(1, fullText.length / 5000);
    let confidence = 0.4 + lengthScore * 0.5;
    if (isScanned)
        confidence -= 0.1;
    if (topics.length < 2)
        confidence -= 0.1;
    return Math.max(0.2, Math.min(confidence, 0.95));
}
async function callPolicyGate(req, payload) {
    const authHeader = req.header('authorization') || '';
    const response = await fetch(`http://127.0.0.1:${env_1.config.port}/ai/policy/gate`, {
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
    return (await response.json());
}
async function downloadBuffer(url) {
    const response = await fetch(url);
    if (!response.ok) {
        throw new Error(`Failed to download PDF: ${response.status} ${response.statusText}`);
    }
    const arrayBuffer = await response.arrayBuffer();
    return Buffer.from(arrayBuffer);
}
async function generateSmartNotes(textSnippet, subject, diagrams) {
    const provider = env_1.config.model.provider;
    const model = provider === 'openai' ? env_1.config.model.openai.model : env_1.config.model.google.model;
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
    const output = await (0, modelRouter_1.callTextModel)({
        provider,
        model,
        jsonOnly: true,
        temperature: 0.3,
        messages: [
            { role: 'system', content: system },
            { role: 'user', content: JSON.stringify(payload) },
        ],
    });
    const parsed = safeJsonParse(output);
    return normalizeSmartNotes(parsed ?? {}, subject);
}
async function logDecision(payload) {
    try {
        await (0, firestoreService_1.aiLogsCollection)().add({
            ...payload,
            createdAt: firestore_1.FieldValue.serverTimestamp(),
        });
    }
    catch (error) {
        console.error('Failed to log notes enhance decision', error);
    }
}
router.post('/ai/notes/enhance', async (req, res) => {
    const body = (req.body ?? {});
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
    const extracted = await (0, docExtract_1.extractTextFromPdf)(pdfBuffer);
    const snippet = extracted.fullText.slice(0, 1200);
    let policy;
    try {
        policy = await callPolicyGate(req, {
            userId,
            text: `${subject}\n${snippet}`,
            contextType: 'notes',
            contentHint: subject,
        });
    }
    catch (error) {
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
            message: policy.nextStep ||
                'I can only generate smart notes for school-related material.',
        });
        return;
    }
    let diagramPages = [];
    try {
        const pageImages = await (0, pdfImageExtract_1.extractImagesFromPdf)(pdfBuffer);
        diagramPages = pageImages
            .filter((page) => page.images.length > 0)
            .map((page) => ({ pageNumber: page.pageNumber, count: page.images.length }));
    }
    catch (error) {
        console.error('PDF image extraction failed', error);
    }
    const smartNotes = await generateSmartNotes(snippet, subject, diagramPages);
    const sectionsHtml = buildSectionsHtml(smartNotes.sections);
    const diagramsHtml = buildDiagramHtml(smartNotes.diagramCaptions);
    const template = node_fs_1.default.readFileSync(getTemplatePath(), 'utf8');
    const html = renderTemplate(template, {
        TITLE: escapeHtml(smartNotes.title),
        SUBJECT: escapeHtml(smartNotes.subject),
        SECTIONS: sectionsHtml,
        DIAGRAMS: diagramsHtml,
        GENERATED_AT: new Date().toISOString(),
    });
    const pdfOut = await (0, pdfRenderer_1.renderPdfFromHtml)(html);
    const gsPath = `users/${userId}/ai/notes/${Date.now()}.pdf`;
    const storedPath = await (0, storageService_1.uploadBufferToStorage)(pdfOut, gsPath, 'application/pdf');
    const signedUrl = await (0, storageService_1.generateSignedReadUrl)(storedPath, 60);
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
    const response = {
        smartNotesPdfUrl: signedUrl,
        extractedTopics,
        confidence,
    };
    res.json(response);
});
exports.default = router;
