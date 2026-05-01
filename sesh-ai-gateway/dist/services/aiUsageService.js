"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.consumeTokens = consumeTokens;
const firestore_1 = require("firebase-admin/firestore");
const firestoreService_1 = require("./firestoreService");
const firebase_1 = require("./firebase");
function getDayId(date = new Date()) {
    return date.toISOString().slice(0, 10);
}
async function consumeTokens(userId, tokens, dailyBudget) {
    const db = (0, firebase_1.getFirestore)();
    const dayId = getDayId();
    const docRef = (0, firestoreService_1.aiUsageDayDoc)(userId, dayId);
    const safeTokens = Math.max(Math.floor(tokens), 0);
    return db.runTransaction(async (tx) => {
        const snap = await tx.get(docRef);
        const data = snap.data();
        const used = Number(data?.tokenCount ?? 0);
        const nextUsed = used + safeTokens;
        if (dailyBudget > 0 && nextUsed > dailyBudget) {
            return {
                allowed: false,
                used,
                remaining: Math.max(dailyBudget - used, 0),
                dayId,
            };
        }
        const requestCount = Number(data?.requestCount ?? 0) + 1;
        tx.set(docRef, {
            tokenCount: nextUsed,
            requestCount,
            lastUsedAt: firestore_1.FieldValue.serverTimestamp(),
        }, { merge: true });
        return {
            allowed: true,
            used: nextUsed,
            remaining: Math.max(dailyBudget - nextUsed, 0),
            dayId,
        };
    });
}
