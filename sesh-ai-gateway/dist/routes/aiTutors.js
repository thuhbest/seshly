"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const firestore_1 = require("firebase-admin/firestore");
const firestoreService_1 = require("../services/firestoreService");
const router = (0, express_1.Router)();
function normalizeString(value) {
    return String(value ?? '').trim();
}
function normalizeLower(value) {
    return normalizeString(value).toLowerCase();
}
function normalizeArray(value) {
    if (!Array.isArray(value))
        return [];
    return value.map((item) => normalizeLower(item)).filter((item) => item.length > 0);
}
function containsMatch(values, needle) {
    if (!needle)
        return false;
    return values.some((value) => value.includes(needle));
}
function containsLooseMatch(values, needle) {
    if (!needle)
        return false;
    const tokens = needle.split(/\s+/).filter(Boolean);
    return values.some((value) => tokens.every((token) => value.includes(token)));
}
function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
}
function computeScore(tutor, request) {
    const reasons = [];
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
        }
        else {
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
    const body = (req.body ?? {});
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
    let query = (0, firestoreService_1.tutorsCollection)()
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
        const fallbackSnap = await (0, firestoreService_1.tutorsCollection)()
            .where('isActive', '==', true)
            .limit(200)
            .get();
        docs = fallbackSnap.docs;
    }
    const matches = docs
        .map((doc) => {
        const data = doc.data();
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
        await (0, firestoreService_1.aiLogsCollection)().add({
            type: 'tutor_match',
            userId,
            subject: request.subject,
            courseCode: request.courseCode ?? null,
            preferredLanguage: request.preferredLanguage ?? null,
            matchCount: matches.length,
            requestId: req.requestId || null,
            createdAt: firestore_1.FieldValue.serverTimestamp(),
        });
    }
    catch (error) {
        console.error('Failed to log tutor match', error);
    }
    const response = { matches };
    res.json(response);
});
exports.default = router;
