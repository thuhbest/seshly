import { FieldValue } from 'firebase-admin/firestore';

import { aiUsageDayDoc } from './firestoreService';
import { getFirestore } from './firebase';

export type TokenUsageResult = {
  allowed: boolean;
  used: number;
  remaining: number;
  dayId: string;
};

function getDayId(date = new Date()): string {
  return date.toISOString().slice(0, 10);
}

export async function consumeTokens(
  userId: string,
  tokens: number,
  dailyBudget: number,
): Promise<TokenUsageResult> {
  const db = getFirestore();
  const dayId = getDayId();
  const docRef = aiUsageDayDoc(userId, dayId);
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

    tx.set(
      docRef,
      {
        tokenCount: nextUsed,
        requestCount,
        lastUsedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return {
      allowed: true,
      used: nextUsed,
      remaining: Math.max(dailyBudget - nextUsed, 0),
      dayId,
    };
  });
}
