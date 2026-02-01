"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const firestore_1 = require("firebase-admin/firestore");
const modelRouter_1 = require("../services/modelRouter");
const firestoreService_1 = require("../services/firestoreService");
const env_1 = require("../utils/env");
const router = (0, express_1.Router)();
const systemPrompt = [
    'You are a classifier for Seshly, an education-focused app.',
    'Return JSON only.',
    'Classify category: school | non_school | unknown.',
    'Classify intent: socratic_help | answer_seeking | content_generation | other.',
    'Definitions:',
    '- school: academic help, coursework, studying, tutoring, campus learning.',
    '- non_school: entertainment, personal life, shopping, unrelated topics.',
    '- unknown: unclear or mixed.',
    '- answer_seeking: asks for final answers/solutions.',
    '- socratic_help: wants hints/explanations/step-by-step learning.',
    '- content_generation: asks to draft essays, posts, long-form text.',
    '- other: anything else.',
].join('\n');
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
function normalizeCategory(value) {
    const raw = String(value || '').toLowerCase();
    if (raw === 'school')
        return 'school';
    if (raw === 'non_school' || raw === 'nonschool' || raw === 'non-school')
        return 'non_school';
    return 'unknown';
}
function normalizeIntent(value) {
    const raw = String(value || '').toLowerCase();
    if (raw === 'socratic_help' || raw === 'socratic')
        return 'socratic_help';
    if (raw === 'answer_seeking' || raw === 'answer')
        return 'answer_seeking';
    if (raw === 'content_generation' || raw === 'generation' || raw === 'content')
        return 'content_generation';
    return 'other';
}
function detectFullAnswerRequest(text) {
    const patterns = [
        /\bjust the answer\b/i,
        /\banswer only\b/i,
        /\bfinal answer\b/i,
        /\bgive me the answer\b/i,
        /\bwhat'?s the answer\b/i,
        /\bsolve (it|this) for me\b/i,
        /\bdo it for me\b/i,
        /\bno explanation\b/i,
        /\bfull answer\b/i,
    ];
    return patterns.some((pattern) => pattern.test(text));
}
function detectRepeatRequest(text, contentHint) {
    const haystack = `${text} ${contentHint ?? ''}`.toLowerCase();
    return [
        'again',
        'repeat',
        'already asked',
        'as i said',
        'same question',
        'told you',
        'still',
    ].some((token) => haystack.includes(token));
}
function parseTurnCount(contentHint) {
    if (!contentHint)
        return null;
    try {
        const parsed = JSON.parse(contentHint);
        if (typeof parsed?.turnCount === 'number')
            return parsed.turnCount;
    }
    catch {
        const match = contentHint.match(/turns?\s*[:=]\s*(\d+)/i);
        if (match)
            return Number.parseInt(match[1], 10);
    }
    return null;
}
async function classifyText(text, contextType, contentHint) {
    const provider = env_1.config.model.provider;
    const model = provider === 'openai' ? env_1.config.model.openai.model : env_1.config.model.google.model;
    const messages = [
        { role: 'system', content: systemPrompt },
        {
            role: 'user',
            content: JSON.stringify({
                text,
                contextType,
                contentHint: contentHint || null,
            }),
        },
    ];
    const output = await (0, modelRouter_1.callTextModel)({
        provider,
        model,
        messages,
        jsonOnly: true,
        temperature: 0,
    });
    const parsed = safeJsonParse(output);
    return {
        category: normalizeCategory(parsed?.category),
        intent: normalizeIntent(parsed?.intent),
    };
}
async function logDecision(payload) {
    try {
        await (0, firestoreService_1.aiLogsCollection)().add({
            ...payload,
            createdAt: firestore_1.FieldValue.serverTimestamp(),
        });
    }
    catch (error) {
        console.error('Failed to log policy decision', error);
    }
}
router.post('/ai/policy/gate', async (req, res) => {
    const body = (req.body ?? {});
    const text = typeof body.text === 'string' ? body.text.trim() : '';
    const contextType = body.contextType;
    const allowedContextTypes = [
        'comment',
        'sesh_screen',
        'practice',
        'notes',
        'session',
        'calendar',
        'vault',
        'snap',
    ];
    if (!text || !contextType || !allowedContextTypes.includes(contextType)) {
        res.status(400).json({ error: 'invalid_request', message: 'text and contextType are required.' });
        return;
    }
    const authedUserId = req.user?.uid;
    if (authedUserId && body.userId && body.userId !== authedUserId) {
        res.status(403).json({ error: 'user_mismatch' });
        return;
    }
    const userId = authedUserId || body.userId || null;
    if (req.rateLimitExceeded) {
        const response = {
            allowed: false,
            category: 'unknown',
            intent: 'other',
            recommendTutor: false,
            reason: 'rate_limited',
            nextStep: 'You’re sending requests too fast. Please wait a bit and try again.',
        };
        await logDecision({
            type: 'policy_gate',
            userId,
            contextType,
            textSnippet: text.slice(0, 200),
            ...response,
            requestId: req.requestId || null,
            rateLimit: req.rateLimitResult ?? null,
        });
        res.json(response);
        return;
    }
    let category = 'unknown';
    let intent = 'other';
    try {
        const classified = await classifyText(text, contextType, body.contentHint);
        category = classified.category;
        intent = classified.intent;
    }
    catch (error) {
        console.error('Policy classification failed', error);
    }
    const isPracticeContext = ['practice', 'comment', 'sesh_screen'].includes(contextType);
    const wantsFullAnswer = detectFullAnswerRequest(text);
    const isRepeat = detectRepeatRequest(text, body.contentHint);
    const turnCount = parseTurnCount(body.contentHint);
    const exceededTurns = turnCount !== null && turnCount >= env_1.config.maxChatTurnsPerThread;
    const shouldRecommendTutor = wantsFullAnswer || isRepeat || exceededTurns;
    if (intent === 'answer_seeking' && isPracticeContext) {
        intent = 'socratic_help';
    }
    let response = {
        allowed: true,
        category,
        intent,
        recommendTutor: false,
    };
    if (category === 'non_school') {
        response = {
            allowed: false,
            category,
            intent,
            recommendTutor: false,
            reason: 'school_only',
            nextStep: 'I’m here to help with school-related questions. Try rephrasing with your class, assignment, or study topic.',
        };
    }
    else if (intent === 'socratic_help' && isPracticeContext) {
        response.recommendTutor = shouldRecommendTutor;
        if (response.recommendTutor) {
            response.nextStep = 'If you want a full walkthrough, a tutor can help you get unstuck quickly.';
        }
        else if (env_1.config.strictExamMode && wantsFullAnswer) {
            response.nextStep = 'Exam mode is on, so I can guide you step-by-step instead of giving full answers.';
        }
    }
    await logDecision({
        type: 'policy_gate',
        userId,
        contextType,
        textSnippet: text.slice(0, 200),
        ...response,
        requestId: req.requestId || null,
        strictExamMode: env_1.config.strictExamMode,
    });
    res.json(response);
});
exports.default = router;
