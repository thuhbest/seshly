import { Timestamp } from 'firebase-admin/firestore';

import { getFirestore } from './firebase';
import { config } from '../utils/env';

export type RateLimitResult = {
  allowed: boolean;
  remaining: number;
  resetAt: number;
  limit: number;
};

export async function checkRateLimit(userId: string): Promise<RateLimitResult> {
  const limit = Math.max(config.rateLimit.max, 0);
  const windowMs = Math.max(config.rateLimit.windowSeconds, 1) * 1000;
  const now = Date.now();

  if (limit === 0) {
    return { allowed: true, remaining: 0, resetAt: now + windowMs, limit };
  }

  const db = getFirestore();
  const docRef = db.collection(config.rateLimitCollection).doc(userId);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(docRef);
    const data = snap.data();
    const eventsRaw = Array.isArray(data?.events) ? data?.events : [];
    const cutoff = now - windowMs;

    const recent = eventsRaw
      .map((value: unknown) => Number(value))
      .filter((value) => Number.isFinite(value) && value >= cutoff)
      .sort((a, b) => a - b);

    if (recent.length >= limit) {
      const resetAt = recent[0] + windowMs;
      return { allowed: false, remaining: 0, resetAt, limit };
    }

    recent.push(now);
    recent.sort((a, b) => a - b);
    const trimmed = recent.slice(-limit);

    tx.set(
      docRef,
      {
        events: trimmed,
        updatedAt: Timestamp.fromMillis(now),
      },
      { merge: true },
    );

    const resetAt = trimmed[0] + windowMs;
    return {
      allowed: true,
      remaining: Math.max(limit - trimmed.length, 0),
      resetAt,
      limit,
    };
  });
}
