import { Router } from 'express';
import fs from 'node:fs';
import path from 'node:path';
import { FieldValue } from 'firebase-admin/firestore';

import { aiLogsCollection, userSettingsDoc } from '../services/firestoreService';

const router = Router();


let cachedAffirmations: { id: string; text: string; tags: string[] }[] | null = null;

function loadAffirmations() {
  if (cachedAffirmations) return cachedAffirmations;
  const filePath = path.join(__dirname, '..', 'data', 'affirmations.json');
  const raw = fs.readFileSync(filePath, 'utf8');
  const parsed = JSON.parse(raw);
  cachedAffirmations = Array.isArray(parsed) ? parsed : [];
  return cachedAffirmations;
}

function pickRandom<T>(items: T[]): T | null {
  if (!items.length) return null;
  const idx = Math.floor(Math.random() * items.length);
  return items[idx];
}

type AffirmationsToggleRequest = {
  userId?: string;
  enabled: boolean;
};

type AffirmationsSettings = {
  affirmationsEnabled: boolean;
  frequencyMin: number;
  tone: string;
};

type ScheduleGuidance = {
  randomWindowMin: number;
  randomWindowMax: number;
  suggestedDelayMin: number;
  suggestedScheduleAt: string;
  payloadTemplate: {
    title: string;
    body: string;
    data: Record<string, string>;
  };
};

type AffirmationsToggleResponse = {
  ok: true;
  settings: AffirmationsSettings;
  scheduleGuidance: ScheduleGuidance;
};

const DEFAULTS: AffirmationsSettings = {
  affirmationsEnabled: true,
  frequencyMin: 15,
  tone: 'supportive',
};

function randomBetween(min: number, max: number): number {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

router.post('/ai/affirmations/toggle', async (req, res) => {
  const body = (req.body ?? {}) as AffirmationsToggleRequest;

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

  const settingsRef = userSettingsDoc(userId);
  const snap = await settingsRef.get();
  const current = (snap.data() ?? {}) as Partial<AffirmationsSettings>;

  const settings: AffirmationsSettings = {
    affirmationsEnabled: body.enabled,
    frequencyMin: typeof current.frequencyMin === 'number' ? current.frequencyMin : DEFAULTS.frequencyMin,
    tone: typeof current.tone === 'string' && current.tone.trim().length > 0 ? current.tone : DEFAULTS.tone,
  };

  await settingsRef.set(
    {
      affirmationsEnabled: settings.affirmationsEnabled,
      frequencyMin: settings.frequencyMin,
      tone: settings.tone,
      updatedAt: FieldValue.serverTimestamp(),
      ...(snap.exists ? {} : { createdAt: FieldValue.serverTimestamp() }),
    },
    { merge: true },
  );

  const delayMin = randomBetween(12, 20);
  const scheduleAt = new Date(Date.now() + delayMin * 60 * 1000).toISOString();

  const response: AffirmationsToggleResponse = {
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
    await aiLogsCollection().add({
      type: 'affirmations_toggle',
      userId,
      enabled: settings.affirmationsEnabled,
      frequencyMin: settings.frequencyMin,
      tone: settings.tone,
      requestId: req.requestId || null,
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (error) {
    console.error('Failed to log affirmations toggle', error);
  }

  res.json(response);
});

export default router;