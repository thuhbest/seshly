"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.incrementThreadTurns = incrementThreadTurns;
exports.getThreadTurns = getThreadTurns;
const firestore_1 = require("firebase-admin/firestore");
const firestoreService_1 = require("./firestoreService");
async function incrementThreadTurns(threadId, userId, messageSnippet) {
    const ref = (0, firestoreService_1.aiThreadDoc)(threadId);
    return ref.firestore.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const currentTurns = snap.data()?.turnsUsed ?? 0;
        const nextTurns = currentTurns + 1;
        tx.set(ref, {
            threadId,
            userId,
            turnsUsed: nextTurns,
            lastMessageAt: firestore_1.FieldValue.serverTimestamp(),
            lastMessageSnippet: messageSnippet || undefined,
            createdAt: snap.exists ? snap.data()?.createdAt : firestore_1.FieldValue.serverTimestamp(),
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        }, { merge: true });
        return { threadId, userId, turnsUsed: nextTurns };
    });
}
async function getThreadTurns(threadId) {
    const snap = await (0, firestoreService_1.aiThreadDoc)(threadId).get();
    return snap.data()?.turnsUsed ?? 0;
}
