import { FieldValue } from 'firebase-admin/firestore';

import { aiThreadDoc } from './firestoreService';

export type ThreadState = {
  threadId: string;
  userId: string;
  turnsUsed: number;
};

export async function incrementThreadTurns(
  threadId: string,
  userId: string,
  messageSnippet?: string,
): Promise<ThreadState> {
  const ref = aiThreadDoc(threadId);

  return ref.firestore.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const currentTurns = (snap.data()?.turnsUsed as number | undefined) ?? 0;
    const nextTurns = currentTurns + 1;

    tx.set(
      ref,
      {
        threadId,
        userId,
        turnsUsed: nextTurns,
        lastMessageAt: FieldValue.serverTimestamp(),
        lastMessageSnippet: messageSnippet || undefined,
        createdAt: snap.exists ? snap.data()?.createdAt : FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return { threadId, userId, turnsUsed: nextTurns };
  });
}

export async function getThreadTurns(threadId: string): Promise<number> {
  const snap = await aiThreadDoc(threadId).get();
  return (snap.data()?.turnsUsed as number | undefined) ?? 0;
}
