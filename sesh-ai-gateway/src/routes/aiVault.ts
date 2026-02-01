import crypto from 'node:crypto';

import { Router, Request } from 'express';
import { FieldValue } from 'firebase-admin/firestore';

import { extractTextFromImage, extractTextFromPdf } from '../services/docExtract';
import { getFirestore } from '../services/firebase';
import { aiLogsCollection, vaultCollection } from '../services/firestoreService';
import { callEmbeddingModel, callTextModel } from '../services/modelRouter';
import { downloadFileFromSignedUrl } from '../services/storageService';
import { config } from '../utils/env';

type VaultCheckRequest = {
  userId?: string;
  fileSignedUrl: string;
  claimedName: string;
};

type VaultCheckMatch = {
  docId: string;
  similarity: number;
  reason: string;
};

type VaultCheckResponse = {
  duplicateExact: boolean;
  duplicateLikely: boolean;
  matches: VaultCheckMatch[];
  recommendedName: string;
  action: 'merge' | 'addNew' | 'addAlias';
};

type PolicyGateInput = {
  userId?: string;
  text: string;
  contextType: 'vault';
  contentHint?: string;
};

type PolicyGateResponse = {
  allowed: boolean;
  category: 'school' | 'non_school' | 'unknown';
  intent: 'socratic_help' | 'answer_seeking' | 'content_generation' | 'other';
  recommendTutor: boolean;
  reason?: 'school_only' | 'rate_limited' | 'blocked';
  nextStep?: string;
};

type VaultMetadata = {
  institution?: string;
  courseCode?: string;
  courseName?: string;
  year?: string;
  term?: string;
  docType?: string;
  variant?: string;
};

type LlmMetadataResponse = {
  institution?: string;
  courseCode?: string;
  courseName?: string;
  year?: string;
  term?: string;
  docType?: string;
  variant?: string;
};

const router = Router();
const SIMILARITY_LOOKBACK = 200;
const SIMILARITY_THRESHOLD = 0.82;
const MERGE_THRESHOLD = 0.9;

function sha256(buffer: Buffer): string {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

function safeJsonParse(text: string): Record<string, unknown> | null {
  try {
    return JSON.parse(text);
  } catch {
    const match = text.match(/\{[\s\S]*\}/);
    if (!match) return null;
    try {
      return JSON.parse(match[0]);
    } catch {
      return null;
    }
  }
}

function normalizeString(value: unknown): string {
  return String(value ?? '').trim();
}

function normalizeMetadata(raw: Record<string, unknown>): VaultMetadata {
  const metadata: VaultMetadata = {
    institution: normalizeString(raw.institution),
    courseCode: normalizeString(raw.courseCode),
    courseName: normalizeString(raw.courseName),
    year: normalizeString(raw.year),
    term: normalizeString(raw.term),
    docType: normalizeString(raw.docType),
    variant: normalizeString(raw.variant),
  };

  Object.keys(metadata).forEach((key) => {
    const value = metadata[key as keyof VaultMetadata];
    if (!value) {
      delete metadata[key as keyof VaultMetadata];
    }
  });

  return metadata;
}

function buildCanonicalString(metadata: VaultMetadata, claimedName: string): string {
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

function recommendedName(metadata: VaultMetadata, claimedName: string): string {
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

function cosineSimilarity(a: number[], b: number[]): number {
  if (!a.length || !b.length || a.length !== b.length) return 0;
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
  if (!denom) return 0;
  return dot / denom;
}

function buildReason(metadata: VaultMetadata, candidate: Record<string, unknown>): string {
  const candidateMeta = (candidate.metadata as VaultMetadata | undefined) ?? {};
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

async function callPolicyGate(req: Request, payload: PolicyGateInput): Promise<PolicyGateResponse> {
  const authHeader = req.header('authorization') || '';
  const response = await fetch(`http://127.0.0.1:${config.port}/ai/policy/gate/vault`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: authHeader,
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Policy gate failed ${response.status}: ${text}`);
  }

  return (await response.json()) as PolicyGateResponse;
}

async function logDecision(payload: Record<string, unknown>): Promise<void> {
  try {
    await aiLogsCollection().add({
      ...payload,
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (error) {
    console.error('Failed to log vault duplicate check', error);
  }
}

async function extractTextSummary(buffer: Buffer): Promise<string> {
  try {
    const pdf = await extractTextFromPdf(buffer);
    return pdf.fullText.slice(0, 2000);
  } catch (error) {
    console.error('PDF extract failed, trying image OCR', error);
    const image = await extractTextFromImage(buffer);
    return image.text.slice(0, 2000);
  }
}

router.post('/ai/vault/checkDuplicate', async (req, res) => {
  const body = (req.body ?? {}) as VaultCheckRequest;
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

  let fileBuffer: Buffer;
  try {
    fileBuffer = await downloadFileFromSignedUrl(fileSignedUrl);
  } catch (error) {
    console.error('Download failed', error);
    res.status(502).json({ error: 'download_failed' });
    return;
  }

  const hash = sha256(fileBuffer);
  const vaultSnap = await vaultCollection().where('sha256', '==', hash).limit(5).get();
  const exactMatches = vaultSnap.docs.map((doc) => ({
    docId: doc.id,
    similarity: 1,
    reason: 'sha256',
    data: doc.data(),
  }));

  if (exactMatches.length > 0) {
    const top = exactMatches[0];
    const recommended =
      (top.data?.claimedName as string | undefined) ||
      (top.data?.subject as string | undefined) ||
      claimedName;

    const response: VaultCheckResponse = {
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
  } catch (error) {
    console.error('Text extraction failed', error);
    res.status(502).json({ error: 'doc_extract_failed' });
    return;
  }

  let policy: PolicyGateResponse;
  try {
    policy = await callPolicyGate(req, {
      userId,
      text: textSummary.slice(0, 1200) || claimedName,
      contextType: 'vault',
      contentHint: claimedName,
    });
  } catch (error) {
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

  const provider = config.model.provider;
  const model = provider === 'openai' ? config.model.openai.model : config.model.google.model;
  const maxTokens = config.maxTokensPerEndpoint['POST /ai/vault/checkDuplicate'];
  const systemPrompt = [
    'Extract metadata from a study document summary.',
    'Return JSON only with keys: institution, courseCode, courseName, year, term, docType, variant.',
    'Leave fields empty if unknown.',
  ].join('\n');

  const metadataOutput = await callTextModel({
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
  const metadata = normalizeMetadata(metadataParsed as LlmMetadataResponse);
  const canonical = buildCanonicalString(metadata, claimedName);

  let embedding: number[] = [];
  try {
    embedding = await callEmbeddingModel({
      provider,
      model: provider === 'openai' ? config.model.openai.embedModel : config.model.google.embedModel,
      input: canonical,
    });
  } catch (error) {
    console.error('Embedding failed', error);
    res.status(502).json({ error: 'embedding_failed' });
    return;
  }

  const db = getFirestore();
  await db.collection('vault_checks').add({
    userId,
    claimedName,
    sha256: hash,
    canonical,
    metadata,
    textSummary,
    embedding,
    embeddingModel: provider === 'openai' ? config.model.openai.embedModel : config.model.google.embedModel,
    createdAt: FieldValue.serverTimestamp(),
  });

  let similarityCandidates: VaultCheckMatch[] = [];
  try {
    const candidateSnap = await vaultCollection()
      .orderBy('createdAt', 'desc')
      .limit(SIMILARITY_LOOKBACK)
      .get();

    similarityCandidates = candidateSnap.docs
      .map((doc) => {
        const data = doc.data() as Record<string, unknown>;
        const candidateEmbedding = Array.isArray(data.embedding) ? data.embedding : [];
        if (!Array.isArray(candidateEmbedding) || candidateEmbedding.length === 0) return null;
        const similarity = cosineSimilarity(embedding, candidateEmbedding as number[]);
        if (!Number.isFinite(similarity)) return null;
        return {
          docId: doc.id,
          similarity: Number(similarity.toFixed(3)),
          reason: buildReason(metadata, data),
        } as VaultCheckMatch;
      })
      .filter((item): item is VaultCheckMatch => Boolean(item))
      .sort((a, b) => b.similarity - a.similarity)
      .slice(0, 5);
  } catch (error) {
    console.error('Similarity search failed', error);
  }

  const topMatch = similarityCandidates[0];
  const duplicateLikely = Boolean(topMatch && topMatch.similarity >= SIMILARITY_THRESHOLD);
  const action: VaultCheckResponse['action'] = topMatch
    ? topMatch.similarity >= MERGE_THRESHOLD
      ? 'merge'
      : duplicateLikely
      ? 'addAlias'
      : 'addNew'
    : 'addNew';

  const response: VaultCheckResponse = {
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

export default router;
