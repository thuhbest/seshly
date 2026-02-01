"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.checkRateLimit = checkRateLimit;
const firestore_1 = require("firebase-admin/firestore");
const firebase_1 = require("./firebase");
const env_1 = require("../utils/env");
async function checkRateLimit(userId, options) {
    const limit = Math.max(options?.max ?? env_1.config.rateLimit.max, 0);
    const windowMs = Math.max(options?.windowSeconds ?? env_1.config.rateLimit.windowSeconds, 1) * 1000;
    const now = Date.now();
    const key = options?.keySuffix ? `${userId}:${options.keySuffix}` : userId;
    if (limit === 0) {
        return { allowed: true, remaining: 0, resetAt: now + windowMs, limit };
    }
    const db = (0, firebase_1.getFirestore)();
    const docRef = db.collection(env_1.config.rateLimitCollection).doc(key);
    return db.runTransaction(async (tx) => {
        const snap = await tx.get(docRef);
        const data = snap.data();
        const eventsRaw = Array.isArray(data?.events) ? data?.events : [];
        const cutoff = now - windowMs;
        const recent = eventsRaw
            .map((value) => Number(value))
            .filter((value) => Number.isFinite(value) && value >= cutoff)
            .sort((a, b) => a - b);
        if (recent.length >= limit) {
            const resetAt = recent[0] + windowMs;
            return { allowed: false, remaining: 0, resetAt, limit };
        }
        recent.push(now);
        recent.sort((a, b) => a - b);
        const trimmed = recent.slice(-limit);
        tx.set(docRef, {
            events: trimmed,
            updatedAt: firestore_1.Timestamp.fromMillis(now),
        }, { merge: true });
        const resetAt = trimmed[0] + windowMs;
        return {
            allowed: true,
            remaining: Math.max(limit - trimmed.length, 0),
            resetAt,
            limit,
        };
    });
}
