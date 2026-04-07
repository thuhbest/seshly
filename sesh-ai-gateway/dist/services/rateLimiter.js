"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.checkRateLimit = checkRateLimit;
const node_crypto_1 = require("node:crypto");
const firestore_1 = require("firebase-admin/firestore");
const firebase_1 = require("./firebase");
const env_1 = require("../utils/env");
function hashValue(value) {
    return (0, node_crypto_1.createHash)('sha256').update(value).digest('hex');
}
async function checkRateLimit(subject, options) {
    const limit = Math.max(options?.max ?? env_1.config.rateLimit.max, 0);
    const windowMs = Math.max(options?.windowSeconds ?? env_1.config.rateLimit.windowSeconds, 1) * 1000;
    const blockMs = Math.max(options?.blockSeconds ?? 15 * 60, 60) * 1000;
    const violationWindowMs = Math.max(options?.violationWindowSeconds ?? 15 * 60, 60) * 1000;
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
    const db = (0, firebase_1.getFirestore)();
    const docRef = db.collection(env_1.config.rateLimitCollection).doc(key);
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
            .map((value) => Number(value))
            .filter((value) => Number.isFinite(value) && value >= cutoff)
            .sort((a, b) => a - b);
        const recentViolations = violationsRaw
            .map((value) => Number(value))
            .filter((value) => Number.isFinite(value) && value >= violationCutoff)
            .sort((a, b) => a - b);
        if (recent.length >= limit) {
            const nextViolations = [...recentViolations, now].slice(-violationThreshold);
            const nextBlockedUntil = nextViolations.length >= violationThreshold ? now + blockMs : 0;
            tx.set(docRef, {
                events: recent.slice(-limit),
                violations: nextViolations,
                scope,
                subjectHash: hashValue(trimmedSubject),
                blockedUntil: nextBlockedUntil,
                updatedAt: firestore_1.Timestamp.fromMillis(now),
            }, { merge: true });
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
        tx.set(docRef, {
            events: nextEvents,
            violations: recentViolations.slice(-violationThreshold),
            scope,
            subjectHash: hashValue(trimmedSubject),
            blockedUntil: 0,
            updatedAt: firestore_1.Timestamp.fromMillis(now),
        }, { merge: true });
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
