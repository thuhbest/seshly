"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const modelRouter_1 = require("../services/modelRouter");
const env_1 = require("../utils/env");
const router = (0, express_1.Router)();
function trim(value) {
    return typeof value === 'string' ? value.trim() : '';
}
function safeObject(value) {
    return value && typeof value === 'object' && !Array.isArray(value)
        ? value
        : {};
}
function asArray(value) {
    return Array.isArray(value) ? value : [];
}
function strings(value, limit = 8) {
    return asArray(value)
        .map((item) => String(item).trim())
        .filter((item) => item.length > 0)
        .slice(0, limit);
}
function frameToLine(frame) {
    const payload = safeObject(frame.payload);
    const parts = [
        `type=${trim(frame.frameType) || 'unknown'}`,
        frame.studentId ? `student=${trim(frame.studentId)}` : '',
        frame.boardId ? `board=${trim(frame.boardId)}` : '',
        frame.taskId ? `task=${trim(frame.taskId)}` : '',
        frame.importance ? `importance=${trim(frame.importance)}` : '',
        frame.spotlightMode ? `spotlight=${trim(frame.spotlightMode)}` : '',
        trim(payload.markerType) ? `marker=${trim(payload.markerType)}` : '',
        trim(payload.label) ? `label=${trim(payload.label)}` : '',
        trim(payload.note) ? `note=${trim(payload.note)}` : '',
        trim(payload.summary) ? `summary=${trim(payload.summary)}` : '',
        trim(payload.responseText) ? `submission=${trim(payload.responseText)}` : '',
        trim(payload.annotationText) ? `annotation=${trim(payload.annotationText)}` : '',
        trim(payload.message) ? `message=${trim(payload.message)}` : '',
    ].filter(Boolean);
    return parts.join(' | ').slice(0, 420);
}
function buildPrompt(body) {
    const participants = asArray(body.participants)
        .map((participant) => {
        const name = trim(participant.displayName) || participant.userId;
        return `${name} (${trim(participant.role) || 'student'})`;
    })
        .join(', ');
    const frames = asArray(body.frames)
        .slice(-180)
        .map((frame, index) => `${index + 1}. ${frameToLine(frame)}`)
        .join('\n');
    const priorSnapshot = JSON.stringify(body.priorSnapshot ?? {}).slice(0, 4000);
    return [
        `sessionId: ${trim(body.sessionId)}`,
        `strategy: ${trim(body.strategy) || 'cheap_live'}`,
        `participants: ${participants || '[unknown participants]'}`,
        'priorSnapshot:',
        priorSnapshot || '{}',
        'frames:',
        frames || '[no frames]',
    ].join('\n');
}
function defaultStudentState() {
    return {
        approach: [],
        mistakes: [],
        corrections: [],
        stuckPoints: [],
        nextFocusArea: [],
    };
}
function normalizeResponse(raw, modelTier, model) {
    const lessonSegments = asArray(raw.lessonSegments).slice(0, 12).map((item) => ({
        label: trim(item.label) || 'Lesson segment',
        summary: trim(item.summary) || 'Classroom memory segment.',
        startedAt: trim(item.startedAt) || null,
        endedAt: trim(item.endedAt) || null,
        markerType: trim(item.markerType) || null,
    }));
    const misconceptionClusters = asArray(raw.misconceptionClusters).slice(0, 8).map((item) => ({
        title: trim(item.title) || 'Misconception',
        misconception: trim(item.misconception) || 'Potential misconception detected.',
        evidence: strings(item.evidence, 4),
        reteachAction: trim(item.reteachAction) || 'Reteach the step with a worked example and a student redo.',
    }));
    const interventionMoments = asArray(raw.interventionMoments).slice(0, 10).map((item) => ({
        studentId: trim(item.studentId) || null,
        title: trim(item.title) || 'Intervention moment',
        summary: trim(item.summary) || 'Tutor intervened during live work.',
        tutorAction: trim(item.tutorAction) || 'Guided correction',
        followUp: trim(item.followUp) || 'Check the same skill again next session.',
    }));
    const exemplarMoments = asArray(raw.exemplarMoments).slice(0, 6).map((item) => ({
        studentId: trim(item.studentId) || null,
        title: trim(item.title) || 'Exemplar moment',
        whyItMatters: trim(item.whyItMatters) || 'Useful work to discuss with the class.',
        boardId: trim(item.boardId) || null,
    }));
    const studentLearningStatesRaw = safeObject(raw.studentLearningStates);
    const studentLearningStates = {};
    for (const [studentId, value] of Object.entries(studentLearningStatesRaw)) {
        const item = safeObject(value);
        studentLearningStates[studentId] = {
            approach: strings(item.approach, 6),
            mistakes: strings(item.mistakes, 6),
            corrections: strings(item.corrections, 6),
            stuckPoints: strings(item.stuckPoints, 6),
            nextFocusArea: strings(item.nextFocusArea, 6),
        };
    }
    return {
        status: 'ready',
        modelTier,
        provider: env_1.config.model.provider,
        model,
        groupLessonMemory: {
            whatWasTaught: strings(safeObject(raw.groupLessonMemory).whatWasTaught, 8),
            keyMisconceptions: strings(safeObject(raw.groupLessonMemory).keyMisconceptions, 8),
            importantExamples: strings(safeObject(raw.groupLessonMemory).importantExamples, 6),
            reteachMoments: strings(safeObject(raw.groupLessonMemory).reteachMoments, 6),
        },
        lessonSegments,
        misconceptionClusters,
        interventionMoments,
        exemplarMoments,
        studentLearningStates,
        sessionContinuityNotes: {
            nextTutorShouldKnow: strings(safeObject(raw.sessionContinuityNotes).nextTutorShouldKnow, 6),
            reviseNextTime: strings(safeObject(raw.sessionContinuityNotes).reviseNextTime, 6),
            carryForwardTasks: strings(safeObject(raw.sessionContinuityNotes).carryForwardTasks, 6),
            atRiskStudentIds: strings(safeObject(raw.sessionContinuityNotes).atRiskStudentIds, 8),
        },
    };
}
function chooseModel(strategy) {
    const provider = env_1.config.model.provider;
    if (strategy === 'cheap_live') {
        return {
            model: provider === 'openai' ? env_1.config.model.openai.cheapModel : env_1.config.model.google.cheapModel,
            tier: 'cheap',
        };
    }
    return {
        model: provider === 'openai' ? env_1.config.model.openai.expensiveModel : env_1.config.model.google.expensiveModel,
        tier: 'expensive',
    };
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
router.post('/ai/classroom/memory/build', async (req, res) => {
    const body = (req.body ?? {});
    const sessionId = trim(body.sessionId);
    const frames = asArray(body.frames).filter((frame) => trim(frame.frameId).length > 0);
    const strategy = (trim(body.strategy) || 'cheap_live');
    if (!sessionId) {
        res.status(400).json({ error: 'invalid_request', message: 'sessionId is required.' });
        return;
    }
    if (!frames.length) {
        res.json({
            status: 'ready',
            modelTier: 'fallback',
            provider: 'fallback',
            model: 'empty-classroom-memory',
            groupLessonMemory: {
                whatWasTaught: [],
                keyMisconceptions: [],
                importantExamples: [],
                reteachMoments: [],
            },
            lessonSegments: [],
            misconceptionClusters: [],
            interventionMoments: [],
            exemplarMoments: [],
            studentLearningStates: {},
            sessionContinuityNotes: {
                nextTutorShouldKnow: [],
                reviseNextTime: [],
                carryForwardTasks: [],
                atRiskStudentIds: [],
            },
        });
        return;
    }
    const { model, tier } = chooseModel(strategy);
    const maxTokens = env_1.config.maxTokensPerEndpoint['POST /ai/classroom/memory/build'];
    const systemPrompt = [
        'You are Seshly classroom memory.',
        'Return JSON only.',
        'Be educational, exam-oriented, and concise.',
        'Do not act like a chatbot. Build memory from teaching flow.',
        'Use these exact top-level keys: groupLessonMemory, lessonSegments, misconceptionClusters, interventionMoments, exemplarMoments, studentLearningStates, sessionContinuityNotes.',
        'groupLessonMemory must contain: whatWasTaught, keyMisconceptions, importantExamples, reteachMoments.',
        'studentLearningStates must be an object keyed by studentId, each with: approach, mistakes, corrections, stuckPoints, nextFocusArea.',
        'sessionContinuityNotes must contain: nextTutorShouldKnow, reviseNextTime, carryForwardTasks, atRiskStudentIds.',
        'Favor grounded statements from the frames. If uncertain, omit rather than invent.',
    ].join('\n');
    const output = await (0, modelRouter_1.callTextModel)({
        provider: env_1.config.model.provider,
        model,
        jsonOnly: true,
        temperature: tier === 'cheap' ? 0.1 : 0.2,
        maxTokens,
        messages: [
            { role: 'system', content: systemPrompt },
            { role: 'user', content: buildPrompt(body).slice(0, 12000) },
        ],
    });
    const parsed = safeJsonParse(output) ?? {};
    const normalized = normalizeResponse(parsed, tier, model);
    res.json(normalized);
});
exports.default = router;
