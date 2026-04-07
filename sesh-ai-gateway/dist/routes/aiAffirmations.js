"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const node_fs_1 = __importDefault(require("node:fs"));
const node_path_1 = __importDefault(require("node:path"));
const firestore_1 = require("firebase-admin/firestore");
const firestoreService_1 = require("../services/firestoreService");
const router = (0, express_1.Router)();
let cachedAffirmations = null;
function loadAffirmations() {
    if (cachedAffirmations)
        return cachedAffirmations;
    const filePath = node_path_1.default.join(__dirname, '..', 'data', 'affirmations.json');
    const raw = node_fs_1.default.readFileSync(filePath, 'utf8');
    const parsed = JSON.parse(raw);
    cachedAffirmations = Array.isArray(parsed) ? parsed : [];
    return cachedAffirmations;
}
function pickRandom(items) {
    if (!items.length)
        return null;
    const idx = Math.floor(Math.random() * items.length);
    return items[idx];
}
const DEFAULTS = {
    affirmationsEnabled: true,
    frequencyMin: 15,
    tone: 'supportive',
};
function randomBetween(min, max) {
    return Math.floor(Math.random() * (max - min + 1)) + min;
}
router.post('/ai/affirmations/toggle', async (req, res) => {
    const body = (req.body ?? {});
    if (typeof body.enabled !== 'boolean') {
        res.status(400).json({ error: 'invalid_request', message: 'enabled must be boolean.' });
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
    const settingsRef = (0, firestoreService_1.userSettingsDoc)(userId);
    const snap = await settingsRef.get();
    const current = (snap.data() ?? {});
    const settings = {
        affirmationsEnabled: body.enabled,
        frequencyMin: typeof current.frequencyMin === 'number' ? current.frequencyMin : DEFAULTS.frequencyMin,
        tone: typeof current.tone === 'string' && current.tone.trim().length > 0 ? current.tone : DEFAULTS.tone,
    };
    await settingsRef.set({
        affirmationsEnabled: settings.affirmationsEnabled,
        frequencyMin: settings.frequencyMin,
        tone: settings.tone,
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
        ...(snap.exists ? {} : { createdAt: firestore_1.FieldValue.serverTimestamp() }),
    }, { merge: true });
    const delayMin = randomBetween(12, 20);
    const scheduleAt = new Date(Date.now() + delayMin * 60 * 1000).toISOString();
    const response = {
        ok: true,
        settings,
        scheduleGuidance: {
            randomWindowMin: 12,
            randomWindowMax: 20,
            suggestedDelayMin: delayMin,
            suggestedScheduleAt: scheduleAt,
            payloadTemplate: {
                title: 'Seshly Affirmation',
                body: '{affirmation}',
                data: {
                    type: 'affirmation',
                    tone: settings.tone,
                },
            },
        },
    };
    try {
        await (0, firestoreService_1.aiLogsCollection)().add({
            type: 'affirmations_toggle',
            userId,
            enabled: settings.affirmationsEnabled,
            frequencyMin: settings.frequencyMin,
            tone: settings.tone,
            requestId: req.requestId || null,
            createdAt: firestore_1.FieldValue.serverTimestamp(),
        });
    }
    catch (error) {
        console.error('Failed to log affirmations toggle', error);
    }
    res.json(response);
});
exports.default = router;
