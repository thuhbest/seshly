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
const modelRouter_1 = require("../services/modelRouter");
const firestoreService_1 = require("../services/firestoreService");
const storageService_1 = require("../services/storageService");
const pdfRenderer_1 = require("../services/pdfRenderer");
const env_1 = require("../utils/env");
const router = (0, express_1.Router)();
function getTemplatePath() {
    return node_path_1.default.join(__dirname, '..', 'templates', 'session-summary.html');
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
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}
function buildListItems(items, emptyFallback = '') {
    if (!items.length)
        return emptyFallback ? `<li>${escapeHtml(emptyFallback)}</li>` : '';
    return items.map((item) => `<li>${escapeHtml(item)}</li>`).join('');
}
function buildDiagramItems(diagrams) {
    if (!diagrams.length)
        return '';
    return diagrams
        .map((diagram) => `<li><strong>Page ${diagram.pageNumber || 0}</strong>: ${escapeHtml(diagram.caption)}</li>`)
        .join('');
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
    return value.map((item) => String(item)).map((item) => item.trim()).filter((item) => item.length > 0);
}
function normalizeSessionNotes(raw, subject) {
    return {
        title: String(raw.title ?? 'Session Summary'),
        subject: String(raw.subject ?? subject),
        topics: normalizeStringArray(raw.topics).slice(0, 10),
        keyPoints: normalizeStringArray(raw.keyPoints).slice(0, 12),
        definitions: normalizeStringArray(raw.definitions).slice(0, 12),
        diagramCaptions: Array.isArray(raw.diagramCaptions)
            ? raw.diagramCaptions.map((item) => ({
                pageNumber: Number(item.pageNumber ?? 0) || 0,
                caption: String(item.caption ?? ''),
            }))
            : [],
        exampleQuestions: normalizeStringArray(raw.exampleQuestions).slice(0, 8),
        practiceQuestions: normalizeStringArray(raw.practiceQuestions).slice(0, 8),
        actionPlan: normalizeStringArray(raw.actionPlan).slice(0, 8),
    };
}
function buildSessionRepresentation(ocrResults, chatLog, subject) {
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
async function callPolicyGate(req, payload) {
    const authHeader = req.header('authorization') || '';
    const response = await fetch(`http://127.0.0.1:${env_1.config.port}/ai/policy/gate/session`, {
        method: 'POST',
        headers: {
            'content-type': 'application/json',
            authorization: authHeader,
            'x-firebase-appcheck': req.header('x-firebase-appcheck') || req.header('x-firebase-app-check') || '',
        },
        body: JSON.stringify(payload),
    });
    if (!response.ok) {
        const text = await response.text();
        throw new Error(`Policy gate failed ${response.status}: ${text}`);
    }
    return (await response.json());
}
async function logDecision(payload) {
    try {
        await (0, firestoreService_1.aiLogsCollection)().add({
            ...payload,
            createdAt: firestore_1.FieldValue.serverTimestamp(),
        });
    }
    catch (error) {
        console.error('Failed to log session summary event', error);
    }
}
async function downloadBuffer(url) {
    const response = await fetch(url);
    if (!response.ok) {
        throw new Error(`Failed to download snapshot: ${response.status} ${response.statusText}`);
    }
    const arrayBuffer = await response.arrayBuffer();
    return Buffer.from(arrayBuffer);
}
router.post('/ai/session/summarize', async (req, res) => {
    const body = (req.body ?? {});
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
    const ocrResults = [];
    for (const url of boardSnapshotSignedUrls) {
        try {
            const buffer = await downloadBuffer(url);
            const result = await (0, docExtract_1.extractTextFromImage)(buffer);
            if (result.text)
                ocrResults.push(result.text);
        }
        catch (error) {
            console.error('Board snapshot OCR failed', error);
        }
    }
    const sessionRepresentation = buildSessionRepresentation(ocrResults, chatLog, subject);
    const policySnippet = sessionRepresentation.slice(0, 1200);
    let policy;
    try {
        policy = await callPolicyGate(req, {
            userId,
            text: policySnippet,
            contextType: 'session',
            contentHint: JSON.stringify({ sessionId, participants: studentIds.length }),
        });
    }
    catch (error) {
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
    const provider = env_1.config.model.provider;
    const model = provider === 'openai' ? env_1.config.model.openai.model : env_1.config.model.google.model;
    const maxTokens = env_1.config.maxTokensPerEndpoint['POST /ai/session/summarize'];
    const systemPrompt = [
        'You summarize tutoring sessions for students.',
        'Return JSON only with keys: title, subject, topics, keyPoints, definitions, diagramCaptions, exampleQuestions, practiceQuestions, actionPlan.',
        'No full worked solutions or final answers.',
        'Use diagramCaptions as [{pageNumber, caption}].',
        'Keep responses concise and student-friendly.',
    ].join('\n');
    const output = await (0, modelRouter_1.callTextModel)({
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
    const template = node_fs_1.default.readFileSync(getTemplatePath(), 'utf8');
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
    const pdfBuffer = await (0, pdfRenderer_1.renderPdfFromHtml)(html);
    const pdfUrlsByStudent = {};
    for (const studentId of studentIds) {
        const gsPath = `users/${studentId}/ai/sessions/${sessionId}.pdf`;
        const storedPath = await (0, storageService_1.uploadBufferToStorage)(pdfBuffer, gsPath, 'application/pdf');
        const signedUrl = await (0, storageService_1.generateSignedReadUrl)(storedPath, 60);
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
    const response = {
        pdfUrlsByStudent,
        topics,
        actionItems,
    };
    res.json(response);
});
exports.default = router;
