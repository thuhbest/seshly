import { Router } from 'express';
import { FieldValue } from 'firebase-admin/firestore';

import { aiLogsCollection, tutorsCollection } from '../services/firestoreService';

type TutorMatchRequest = {
  userId?: string;
  request: {
    subject: string;
    courseCode?: string;
    topic?: string;
    level?: string;
    budgetPerMin?: number;
    urgency?: 'low' | 'medium' | 'high';
    preferredLanguage?: string;
  };
};

type TutorMatch = {
  tutorId: string;
  score: number;
  reasons: string[];
  pricePerMin: number;
  nextAvailableSlot?: string;
};

type TutorMatchResponse = {
  matches: TutorMatch[];
};

type TutorDoc = {
  userId?: string;
  subjects?: string[];
  courseCodes?: string[];
  languages?: string[];
  levels?: string[];
  pricePerMin?: number;
  ratingAvg?: number;
  ratingCount?: number;
  nextAvailableSlot?: string;
};

const router = Router();

function normalizeString(value: unknown): string {
  return String(value ?? '').trim();
}

function normalizeLower(value: unknown): string {
  return normalizeString(value).toLowerCase();
}

function normalizeArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.map((item) => normalizeLower(item)).filter((item) => item.length > 0);
}


function containsMatch(values: string[], needle: string): boolean {
  if (!needle) return false;
  return values.some((value) => value.includes(needle));
}

function containsLooseMatch(values: string[], needle: string): boolean {
  if (!needle) return false;
  const tokens = needle.split(/\s+/).filter(Boolean);
  return values.some((value) => tokens.every((token) => value.includes(token)));
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function computeScore(
  tutor: TutorDoc,
  request: TutorMatchRequest['request'],
): { score: number; reasons: string[] } {
  const reasons: string[] = [];
  let score = 0;

  const subject = normalizeLower(request.subject);
  const courseCode = normalizeLower(request.courseCode);
  const preferredLanguage = normalizeLower(request.preferredLanguage);
  const level = normalizeLower(request.level);

  const tutorSubjects = normalizeArray(tutor.subjects);
  const tutorCourses = normalizeArray(tutor.courseCodes);
  const tutorLanguages = normalizeArray(tutor.languages);
  const tutorLevels = normalizeArray(tutor.levels);

  if (subject && tutorSubjects.includes(subject)) {
    score += 0.4;
    reasons.push(`Subject match: ${request.subject}`);
  }

  if (subject && !tutorSubjects.includes(subject) && containsLooseMatch(tutorSubjects, subject)) {
    score += 0.2;
    reasons.push(`Subject match (fuzzy): ${request.subject}`);
  }

  if (courseCode && tutorCourses.includes(courseCode)) {
    score += 0.2;
    reasons.push(`Course match: ${request.courseCode}`);
  }

  if (preferredLanguage && tutorLanguages.includes(preferredLanguage)) {
    score += 0.1;
    reasons.push(`Language: ${request.preferredLanguage}`);
  }

  if (level && tutorLevels.includes(level)) {
    score += 0.1;
    reasons.push(`Level: ${request.level}`);
  }

  const price = typeof tutor.pricePerMin === 'number' ? tutor.pricePerMin : null;
  if (price !== null && typeof request.budgetPerMin === 'number') {
    if (price <= request.budgetPerMin) {
      score += 0.1;
      reasons.push('Within budget');
    } else {
      score -= 0.05;
      reasons.push('Above budget');
    }
  }

  const rating = typeof tutor.ratingAvg === 'number' ? tutor.ratingAvg : 0;
  const ratingCount = typeof tutor.ratingCount === 'number' ? tutor.ratingCount : 0;
  if (rating > 0 && ratingCount > 0) {
    const normalizedRating = clamp(rating / 5, 0, 1);
    score += normalizedRating * 0.1;
    reasons.push(`Rated ${rating.toFixed(1)}`);
  }

  if (request.urgency === 'high' && tutor.nextAvailableSlot) {
    score += 0.05;
    reasons.push('Has availability soon');
  }

  return { score: clamp(score, 0, 1), reasons };
}

router.post('/ai/tutors/match', async (req, res) => {
  const body = (req.body ?? {}) as TutorMatchRequest;
  const request = body.request;
  if (!request || !request.subject) {
    res.status(400).json({ error: 'invalid_request', message: 'request.subject is required.' });
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

  const subject = normalizeLower(request.subject);
  const courseCode = normalizeLower(request.courseCode);
  const preferredLanguage = normalizeLower(request.preferredLanguage);

  let query = tutorsCollection()
    .where('subjects', 'array-contains', subject)
    .where('isActive', '==', true);

  if (courseCode) {
    query = query.where('courseCodes', 'array-contains', courseCode);
  }

  if (preferredLanguage) {
    query = query.where('languages', 'array-contains', preferredLanguage);
  }

  const snapshot = await query.limit(50).get();

  let docs = snapshot.docs;
  if (docs.length < 10) {
    const fallbackSnap = await tutorsCollection()
      .where('isActive', '==', true)
      .limit(200)
      .get();
    docs = fallbackSnap.docs;
  }

  const matches: TutorMatch[] = docs
    .map((doc) => {
      const data = doc.data() as TutorDoc;
      const { score, reasons } = computeScore(data, request);
      return {
        tutorId: doc.id,
        score: Number(score.toFixed(3)),
        reasons,
        pricePerMin: typeof data.pricePerMin === 'number' ? data.pricePerMin : 0,
        nextAvailableSlot: data.nextAvailableSlot,
      };
    })
    .filter((match) => match.score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, 10);

  try {
    await aiLogsCollection().add({
      type: 'tutor_match',
      userId,
      subject: request.subject,
      courseCode: request.courseCode ?? null,
      preferredLanguage: request.preferredLanguage ?? null,
      matchCount: matches.length,
      requestId: req.requestId || null,
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (error) {
    console.error('Failed to log tutor match', error);
  }

  const response: TutorMatchResponse = { matches };
  res.json(response);
});

export default router;