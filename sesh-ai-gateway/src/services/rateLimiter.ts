import { createHash } from 'node:crypto';
import { Timestamp } from 'firebase-admin/firestore';

import { getFirestore } from './firebase';
import { config } from '../utils/env';

export type RateLimitRule = {
  windowSeconds: number;
  max: number;
};

export type RateLimitScope = 'user' | 'ip';

export type RateLimitOptions = Partial<RateLimitRule> & {
  keySuffix?: string;
  scope?: RateLimitScope;
  blockSeconds?: number;
  violationWindowSeconds?: number;
  violationThreshold?: number;
};

export type RateLimitResult = {
  allowed: boolean;
  remaining: number;
  resetAt: number;
  limit: number;
  blockedUntil: number | null;
  scope: RateLimitScope;
};

function hashValue(value: string): string {
  return createHash('sha256').update(value).digest('hex');
}

export async function checkRateLimit(
  subject: string,
  options?: RateLimitOptions,
): Promise<RateLimitResult> {
  const limit = Math.max(options?.max ?? config.rateLimit.max, 0);
  const windowMs =
    Math.max(options?.windowSeconds ?? config.rateLimit.windowSeconds, 1) * 1000;
  const blockMs = Math.max(options?.blockSeconds ?? 15 * 60, 60) * 1000;
  const violationWindowMs =
    Math.max(options?.violationWindowSeconds ?? 15 * 60, 60) * 1000;
  const violationThreshold = Math.max(options?.violationThreshold ?? 3, 1);
  const scope = options?.scope ?? 'user';
  const now = Date.now();
  const trimmedSubject = subject.trim();
  const rawKey = options?.keySuffix
    ? `${scope}:${trimmedSubject}:${options.keySuffix}`
    : `${scope}:${trimmedSubject}`;
  const key = Buffer.from(rawKey).toString('base64url');

  if (limit === 0) {
    return {
      allowed: true,
      remaining: 0,
      resetAt: now + windowMs,
      limit,
      blockedUntil: null,
      scope,
    };
  }

  const db = getFirestore();
  const docRef = db.collection(config.rateLimitCollection).doc(key);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(docRef);
    const data = snap.data();
    const eventsRaw = Array.isArray(data?.events) ? data?.events : [];
    const violationsRaw = Array.isArray(data?.violations) ? data?.violations : [];
    const blockedUntil = Number(data?.blockedUntil ?? 0);
    const cutoff = now - windowMs;
    const violationCutoff = now - violationWindowMs;

    if (Number.isFinite(blockedUntil) && blockedUntil > now) {
      return {
        allowed: false,
        remaining: 0,
        resetAt: blockedUntil,
        limit,
        blockedUntil,
        scope,
      };
    }

    const recent = eventsRaw
      .map((value: unknown) => Number(value))
      .filter((value) => Number.isFinite(value) && value >= cutoff)
      .sort((a, b) => a - b);
    const recentViolations = violationsRaw
      .map((value: unknown) => Number(value))
      .filter((value) => Number.isFinite(value) && value >= violationCutoff)
      .sort((a, b) => a - b);

    if (recent.length >= limit) {
      const nextViolations = [...recentViolations, now].slice(-violationThreshold);
      const nextBlockedUntil =
        nextViolations.length >= violationThreshold ? now + blockMs : 0;
      tx.set(
        docRef,
        {
          events: recent.slice(-limit),
          violations: nextViolations,
          scope,
          subjectHash: hashValue(trimmedSubject),
          blockedUntil: nextBlockedUntil,
          updatedAt: Timestamp.fromMillis(now),
        },
        { merge: true },
      );

      return {
        allowed: false,
        remaining: 0,
        resetAt: nextBlockedUntil || recent[0] + windowMs,
        limit,
        blockedUntil: nextBlockedUntil || null,
        scope,
      };
    }

    const nextEvents = [...recent, now].slice(-limit);
    tx.set(
      docRef,
      {
        events: nextEvents,
        violations: recentViolations.slice(-violationThreshold),
        scope,
        subjectHash: hashValue(trimmedSubject),
        blockedUntil: 0,
        updatedAt: Timestamp.fromMillis(now),
      },
      { merge: true },
    );

    return {
      allowed: true,
      remaining: Math.max(limit - nextEvents.length, 0),
      resetAt: nextEvents[0] + windowMs,
      limit,
      blockedUntil: null,
      scope,
    };
  });
}
