"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_crypto_1 = __importDefault(require("node:crypto"));
const express_1 = require("express");
const firestore_1 = require("firebase-admin/firestore");
const docExtract_1 = require("../services/docExtract");
const firebase_1 = require("../services/firebase");
const firestoreService_1 = require("../services/firestoreService");
const modelRouter_1 = require("../services/modelRouter");
const storageService_1 = require("../services/storageService");
const env_1 = require("../utils/env");
const router = (0, express_1.Router)();
const SIMILARITY_LOOKBACK = 200;
const SIMILARITY_THRESHOLD = 0.82;
const MERGE_THRESHOLD = 0.9;
function sha256(buffer) {
    return node_crypto_1.default.createHash('sha256').update(buffer).digest('hex');
}
function safeJsonParse(text) {
    try {
        return JSON.parse(text);
    }
    catch {
        const match = text.match(/\{[\s\S]*\}/);
        if (!match)
            return null;
        try {
            return JSON.parse(match[0]);
        }
        catch {
            return null;
        }
    }
}
function normalizeString(value) {
    return String(value ?? '').trim();
}
function normalizeMetadata(raw) {
    const metadata = {
        institution: normalizeString(raw.institution),
        courseCode: normalizeString(raw.courseCode),
        courseName: normalizeString(raw.courseName),
        year: normalizeString(raw.year),
        term: normalizeString(raw.term),
        docType: normalizeString(raw.docType),
        variant: normalizeString(raw.variant),
    };
    Object.keys(metadata).forEach((key) => {
        const value = metadata[key];
        if (!value) {
            delete metadata[key];
        }
    });
    return metadata;
}
function buildCanonicalString(metadata, claimedName) {
    const parts = [
        claimedName,
        metadata.institution,
        metadata.courseCode,
        metadata.courseName,
        metadata.year,
        metadata.term,
        metadata.docType,
        metadata.variant,
    ]
        .map((value) => (value ? value.trim() : ''))
        .filter((value) => value.length > 0);
    return parts.join(' | ');
}
function recommendedName(metadata, claimedName) {
    const parts = [
        metadata.courseCode,
        metadata.courseName,
        metadata.term,
        metadata.year,
        metadata.docType,
        metadata.variant,
    ]
        .map((value) => (value ? value.trim() : ''))
        .filter((value) => value.length > 0);
    const derived = parts.join(' - ');
    return derived || claimedName;
}
function cosineSimilarity(a, b) {
    if (!a.length || !b.length || a.length !== b.length)
        return 0;
    let dot = 0;
    let normA = 0;
    let normB = 0;
    for (let i = 0; i < a.length; i += 1) {
        const av = a[i];
        const bv = b[i];
        dot += av * bv;
        normA += av * av;
        normB += bv * bv;
    }
    const denom = Math.sqrt(normA) * Math.sqrt(normB);
    if (!denom)
        return 0;
    return dot / denom;
}
function buildReason(metadata, candidate) {
    const candidateMeta = candidate.metadata ?? {};
    if (metadata.courseCode && candidateMeta.courseCode && metadata.courseCode === candidateMeta.courseCode) {
        return 'courseCode';
    }
    if (metadata.courseName && candidateMeta.courseName && metadata.courseName === candidateMeta.courseName) {
        return 'courseName';
    }
    if (metadata.docType && candidateMeta.docType && metadata.docType === candidateMeta.docType) {
        return 'docType';
    }
    return 'embedding';
}
async function callPolicyGate(req, payload) {
    const authHeader = req.header('authorization') || '';
    const response = await fetch(`http://127.0.0.1:${env_1.config.port}/ai/policy/gate/vault`, {
        method: 'POST',
        headers: {
            'content-type': 'application/json',
            authorization: authHeader,
            'x-firebase-appcheck': req.header('x-firebase-appcheck') || req.header('x-firebase-app-check') || '',
        },
        body: JSON.stringify(payload),
    });
    if (!response.ok) {
        const text = await response.text();
        throw new Error(`Policy gate failed ${response.status}: ${text}`);
    }
    return (await response.json());
}
async function logDecision(payload) {
    try {
        await (0, firestoreService_1.aiLogsCollection)().add({
            ...payload,
            createdAt: firestore_1.FieldValue.serverTimestamp(),
        });
    }
    catch (error) {
        console.error('Failed to log vault duplicate check', error);
    }
}
async function extractTextSummary(buffer) {
    try {
        const pdf = await (0, docExtract_1.extractTextFromPdf)(buffer);
        return pdf.fullText.slice(0, 2000);
    }
    catch (error) {
        console.error('PDF extract failed, trying image OCR', error);
        const image = await (0, docExtract_1.extractTextFromImage)(buffer);
        return image.text.slice(0, 2000);
    }
}
router.post('/ai/vault/checkDuplicate', async (req, res) => {
    const body = (req.body ?? {});
    const fileSignedUrl = body.fileSignedUrl?.trim();
    const claimedName = body.claimedName?.trim();
    if (!fileSignedUrl || !claimedName) {
        res.status(400).json({ error: 'invalid_request', message: 'fileSignedUrl and claimedName are required.' });
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
    let fileBuffer;
    try {
        fileBuffer = await (0, storageService_1.downloadFileFromSignedUrl)(fileSignedUrl);
    }
    catch (error) {
        console.error('Download failed', error);
        res.status(502).json({ error: 'download_failed' });
        return;
    }
    const hash = sha256(fileBuffer);
    const vaultSnap = await (0, firestoreService_1.vaultCollection)().where('sha256', '==', hash).limit(5).get();
    const exactMatches = vaultSnap.docs.map((doc) => ({
        docId: doc.id,
        similarity: 1,
        reason: 'sha256',
        data: doc.data(),
    }));
    if (exactMatches.length > 0) {
        const top = exactMatches[0];
        const recommended = top.data?.claimedName ||
            top.data?.subject ||
            claimedName;
        const response = {
            duplicateExact: true,
            duplicateLikely: true,
            matches: exactMatches.map(({ docId, similarity, reason }) => ({ docId, similarity, reason })),
            recommendedName: recommended,
            action: 'addAlias',
        };
        await logDecision({
            type: 'vault_check',
            userId,
            sha256: hash,
            duplicateExact: true,
            matches: response.matches,
            requestId: req.requestId || null,
        });
        res.json(response);
        return;
    }
    let textSummary = '';
    try {
        textSummary = await extractTextSummary(fileBuffer);
    }
    catch (error) {
        console.error('Text extraction failed', error);
        res.status(502).json({ error: 'doc_extract_failed' });
        return;
    }
    let policy;
    try {
        policy = await callPolicyGate(req, {
            userId,
            text: textSummary.slice(0, 1200) || claimedName,
            contextType: 'vault',
            contentHint: claimedName,
        });
    }
    catch (error) {
        console.error('Policy gate error', error);
        res.status(502).json({ error: 'policy_gate_unavailable' });
        return;
    }
    if (!policy.allowed) {
        await logDecision({
            type: 'vault_check',
            userId,
            allowed: false,
            reason: policy.reason ?? 'school_only',
            requestId: req.requestId || null,
        });
        res.status(403).json({
            error: 'policy_blocked',
            message: policy.nextStep || 'I can only check duplicates for school-related materials.',
        });
        return;
    }
    const provider = env_1.config.model.provider;
    const model = provider === 'openai' ? env_1.config.model.openai.model : env_1.config.model.google.model;
    const maxTokens = env_1.config.maxTokensPerEndpoint['POST /ai/vault/checkDuplicate'];
    const systemPrompt = [
        'Extract metadata from a study document summary.',
        'Return JSON only with keys: institution, courseCode, courseName, year, term, docType, variant.',
        'Leave fields empty if unknown.',
    ].join('\n');
    const metadataOutput = await (0, modelRouter_1.callTextModel)({
        provider,
        model,
        jsonOnly: true,
        temperature: 0,
        maxTokens,
        messages: [
            { role: 'system', content: systemPrompt },
            { role: 'user', content: JSON.stringify({ claimedName, textSummary }) },
        ],
    });
    const metadataParsed = safeJsonParse(metadataOutput) ?? {};
    const metadata = normalizeMetadata(metadataParsed);
    const canonical = buildCanonicalString(metadata, claimedName);
    let embedding = [];
    try {
        embedding = await (0, modelRouter_1.callEmbeddingModel)({
            provider,
            model: provider === 'openai' ? env_1.config.model.openai.embedModel : env_1.config.model.google.embedModel,
            input: canonical,
        });
    }
    catch (error) {
        console.error('Embedding failed', error);
        res.status(502).json({ error: 'embedding_failed' });
        return;
    }
    const db = (0, firebase_1.getFirestore)();
    await db.collection('vault_checks').add({
        userId,
        claimedName,
        sha256: hash,
        canonical,
        metadata,
        textSummary,
        embedding,
        embeddingModel: provider === 'openai' ? env_1.config.model.openai.embedModel : env_1.config.model.google.embedModel,
        createdAt: firestore_1.FieldValue.serverTimestamp(),
    });
    let similarityCandidates = [];
    try {
        const candidateSnap = await (0, firestoreService_1.vaultCollection)()
            .orderBy('createdAt', 'desc')
            .limit(SIMILARITY_LOOKBACK)
            .get();
        similarityCandidates = candidateSnap.docs
            .map((doc) => {
            const data = doc.data();
            const candidateEmbedding = Array.isArray(data.embedding) ? data.embedding : [];
            if (!Array.isArray(candidateEmbedding) || candidateEmbedding.length === 0)
                return null;
            const similarity = cosineSimilarity(embedding, candidateEmbedding);
            if (!Number.isFinite(similarity))
                return null;
            return {
                docId: doc.id,
                similarity: Number(similarity.toFixed(3)),
                reason: buildReason(metadata, data),
            };
        })
            .filter((item) => Boolean(item))
            .sort((a, b) => b.similarity - a.similarity)
            .slice(0, 5);
    }
    catch (error) {
        console.error('Similarity search failed', error);
    }
    const topMatch = similarityCandidates[0];
    const duplicateLikely = Boolean(topMatch && topMatch.similarity >= SIMILARITY_THRESHOLD);
    const action = topMatch
        ? topMatch.similarity >= MERGE_THRESHOLD
            ? 'merge'
            : duplicateLikely
                ? 'addAlias'
                : 'addNew'
        : 'addNew';
    const response = {
        duplicateExact: false,
        duplicateLikely,
        matches: similarityCandidates,
        recommendedName: recommendedName(metadata, claimedName),
        action,
    };
    await logDecision({
        type: 'vault_check',
        userId,
        sha256: hash,
        duplicateExact: false,
        duplicateLikely,
        matches: response.matches,
        requestId: req.requestId || null,
    });
    res.json(response);
});
exports.default = router;
