import { Router, Request, Response } from 'express';
import { FieldValue } from 'firebase-admin/firestore';

import { extractTextFromImage, extractTextFromPdf } from '../services/docExtract';
import { callTextModel } from '../services/modelRouter';
import { aiLogsCollection, userPracticeSetsCollection } from '../services/firestoreService';
import { config } from '../utils/env';

type Difficulty = 'weak' | 'medium' | 'hard' | 'impossible';

type DifficultyCounts = {
  weak: number;
  medium: number;
  hard: number;
  impossible: number;
};

type PracticeQuestion = {
  id: string;
  difficulty: Difficulty;
  question: string;
  allowedHelp: 'hint_only';
  markingGuide?: string;
};

type PracticeSetResponse = {
  setId: string;
  topic: string;
  prerequisites: string[];
  questions: PracticeQuestion[];
};

type PracticeGenerateRequest = {
  userId?: string;
  sourceFileSignedUrl: string;
  subject?: string;
  difficultyCounts: DifficultyCounts;
};

type PracticeCoachRequest = {
  userId?: string;
  questionId: string;
  questionText: string;
  studentAttemptText: string;
};

type PracticeCoachResponse = {
  feedback: string;
  nextHint: string;
  nextQuestionToAskStudent: string;
  recommendTutor: boolean;
};

type PolicyGateInput = {
  userId?: string;
  text: string;
  contextType: ContextType;
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

type PracticeCoachModelOutput = {
  feedback: string;
  nextHint: string;
  nextQuestionToAskStudent: string;
  recommendTutor?: boolean;
};

type ContextType =
  | 'comment'
  | 'sesh_screen'
  | 'practice'
  | 'notes'
  | 'session'
  | 'calendar'
  | 'vault'
  | 'snap';

const router = Router();

const allowedContextTypes: ContextType[] = [
  'comment',
  'sesh_screen',
  'practice',
  'notes',
  'session',
  'calendar',
  'vault',
  'snap',
];

function parseDifficultyCounts(value: unknown): DifficultyCounts | null {
  if (!value || typeof value !== 'object') return null;
  const record = value as Record<string, unknown>;
  const toNumber = (key: keyof DifficultyCounts) => {
    const raw = record[key];
    const parsed = Number.parseInt(String(raw ?? ''), 10);
    if (!Number.isFinite(parsed) || parsed < 0) return null;
    return parsed;
  };
  const weak = toNumber('weak');
  const medium = toNumber('medium');
  const hard = toNumber('hard');
  const impossible = toNumber('impossible');
  if (weak === null || medium === null || hard === null || impossible === null) return null;
  if (weak + medium + hard + impossible <= 0) return null;
  return { weak, medium, hard, impossible };
}

function buildDifficultyList(counts: DifficultyCounts): Difficulty[] {
  const list: Difficulty[] = [];
  const add = (difficulty: Difficulty, count: number) => {
    for (let i = 0; i < count; i += 1) list.push(difficulty);
  };
  add('weak', counts.weak);
  add('medium', counts.medium);
  add('hard', counts.hard);
  add('impossible', counts.impossible);
  return list;
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

function normalizeStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.map((item) => String(item)).map((item) => item.trim()).filter((item) => item.length > 0);
}

function sanitizeMarkingGuide(value: string): string {
  const trimmed = value.trim().replace(/^\s*(answer|solution)\s*:\s*/i, '');
  if (trimmed.length <= 800) return trimmed;
  return `${trimmed.slice(0, 780).trim()}...`;
}

function buildFallbackQuestion(topic: string, difficulty: Difficulty, index: number): string {
  const prefix = topic ? `Based on ${topic},` : 'Based on the material,';
  const variants: Record<Difficulty, string[]> = {
    weak: [
      `${prefix} define a key term introduced in the notes.`,
      `${prefix} summarize the main idea in one or two sentences.`,
    ],
    medium: [
      `${prefix} explain how two concepts from the notes relate.`,
      `${prefix} apply the main concept to a simple example.`,
    ],
    hard: [
      `${prefix} analyze a tricky case and explain the reasoning.`,
      `${prefix} compare two approaches and justify which is better.`,
    ],
    impossible: [
      `${prefix} synthesize the concepts into a new scenario and reason through it.`,
      `${prefix} identify hidden assumptions and discuss their impact.`,
    ],
  };
  const options = variants[difficulty];
  return options[index % options.length];
}

function normalizeQuestions(
  rawQuestions: unknown,
  targetDifficulties: Difficulty[],
  topic: string,
): PracticeQuestion[] {
  const questionsArray = Array.isArray(rawQuestions) ? rawQuestions : [];
  const usedIds = new Set<string>();
  return targetDifficulties.map((difficulty, index) => {
    const raw = (questionsArray[index] ?? {}) as Record<string, unknown>;
    const questionText = String(raw.question ?? '').trim();
    let id = String(raw.id ?? '').trim() || `q${index + 1}`;
    if (usedIds.has(id)) id = `q${index + 1}`;
    usedIds.add(id);
    const markingGuideRaw = raw.markingGuide ? String(raw.markingGuide) : '';
    const markingGuide = markingGuideRaw ? sanitizeMarkingGuide(markingGuideRaw) : undefined;
    return {
      id,
      difficulty,
      question: questionText || buildFallbackQuestion(topic, difficulty, index),
      allowedHelp: 'hint_only',
      ...(markingGuide ? { markingGuide } : {}),
    };
  });
}

async function callPolicyGate(req: Request, payload: PolicyGateInput): Promise<PolicyGateResponse> {
  const authHeader = req.header('authorization') || '';
  const response = await fetch(`http://127.0.0.1:${config.port}/ai/policy/gate/${payload.contextType}`, {
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
    console.error('Failed to log practice event', error);
  }
}

function detectSourceType(contentType: string | null, url: string): 'pdf' | 'image' | 'unknown' {
  const lowerType = (contentType || '').toLowerCase();
  if (lowerType.startsWith('image/')) return 'image';
  if (lowerType.includes('pdf')) return 'pdf';
  if (url.toLowerCase().includes('.pdf')) return 'pdf';
  if (url.match(/\.(png|jpe?g|gif|bmp|webp)(\?|$)/i)) return 'image';
  return 'unknown';
}

async function downloadBuffer(url: string): Promise<{ buffer: Buffer; contentType: string | null }> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to download source: ${response.status} ${response.statusText}`);
  }
  const contentType = response.headers.get('content-type');
  const arrayBuffer = await response.arrayBuffer();
  return { buffer: Buffer.from(arrayBuffer), contentType };
}

async function extractSourceText(
  sourceFileSignedUrl: string,
): Promise<{ fullText: string; isScanned: boolean; sourceType: 'pdf' | 'image' | 'unknown' }> {
  const { buffer, contentType } = await downloadBuffer(sourceFileSignedUrl);
  const sourceType = detectSourceType(contentType, sourceFileSignedUrl);

  if (sourceType === 'image') {
    const image = await extractTextFromImage(buffer);
    return { fullText: image.text, isScanned: true, sourceType };
  }

  try {
    const pdf = await extractTextFromPdf(buffer);
    return { fullText: pdf.fullText, isScanned: pdf.isScanned, sourceType };
  } catch (error) {
    console.error('PDF extraction failed, attempting image OCR', error);
    const image = await extractTextFromImage(buffer);
    return { fullText: image.text, isScanned: true, sourceType: 'image' };
  }
}

function defaultString(value: unknown, fallback: string): string {
  const text = String(value ?? '').trim();
  return text.length ? text : fallback;
}

function resolveContextType(raw?: string): ContextType | null {
  if (!raw) return null;
  const normalized = raw.toLowerCase();
  return allowedContextTypes.find((value) => value === normalized) ?? null;
}

router.post('/ai/practice/generate', async (req, res) => {
  const body = (req.body ?? {}) as PracticeGenerateRequest;
  const sourceFileSignedUrl = body.sourceFileSignedUrl?.trim();
  const subject = body.subject?.trim() || 'Practice';
  const difficultyCounts = parseDifficultyCounts(body.difficultyCounts);

  if (!sourceFileSignedUrl || !difficultyCounts) {
    res
      .status(400)
      .json({ error: 'invalid_request', message: 'sourceFileSignedUrl and difficultyCounts are required.' });
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

  let extracted;
  try {
    extracted = await extractSourceText(sourceFileSignedUrl);
  } catch (error) {
    console.error('Source extraction failed', error);
    res.status(502).json({ error: 'source_extract_failed' });
    return;
  }

  const snippet = extracted.fullText.slice(0, 1500);
  let policy: PolicyGateResponse;

  try {
    policy = await callPolicyGate(req, {
      userId,
      text: `${subject}\n${snippet}`,
      contextType: 'practice',
      contentHint: JSON.stringify({ subject, difficultyCounts }),
    });
  } catch (error) {
    console.error('Policy gate error', error);
    res.status(502).json({ error: 'policy_gate_unavailable' });
    return;
  }

  if (!policy.allowed) {
    await logDecision({
      type: 'practice_generate',
      userId,
      allowed: false,
      reason: policy.reason ?? 'school_only',
      subject,
      requestId: req.requestId || null,
    });
    res.status(403).json({
      error: 'policy_blocked',
      message: policy.nextStep || 'I can only generate school-related practice questions.',
    });
    return;
  }

  const targetDifficulties = buildDifficultyList(difficultyCounts);
  const totalQuestions = targetDifficulties.length;

  const provider = config.model.provider;
  const model = provider === 'openai' ? config.model.openai.model : config.model.google.model;
  const maxTokensGenerate = config.maxTokensPerEndpoint['POST /ai/practice/generate'];
  const systemPrompt = [
    'You generate practice questions for students.',
    'Return JSON only with keys: topic, prerequisites, questions.',
    'questions is an array of length N with objects: id, difficulty, question, allowedHelp, markingGuide.',
    'Use allowedHelp="hint_only" for every question.',
    'Use difficulty labels: weak, medium, hard, impossible.',
    'No full worked solutions or final answers. Marking guide is a brief checklist, not a solution.',
  ].join('\n');

  const userPayload = {
    subject,
    difficultyCounts,
    totalQuestions,
    sourceSnippet: snippet,
  };

  const output = await callTextModel({
    provider,
    model,
    jsonOnly: true,
    temperature: 0.3,
    maxTokens: maxTokensGenerate,
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: JSON.stringify(userPayload) },
    ],
  });

  const parsed = safeJsonParse(output) ?? {};
  const topic = defaultString(parsed.topic, subject);
  const prerequisites = normalizeStringArray(parsed.prerequisites).slice(0, 8);
  const questions = normalizeQuestions(parsed.questions, targetDifficulties, topic);

  const setRef = userPracticeSetsCollection(userId).doc();
  const setId = setRef.id;
  await setRef.set({
    setId,
    userId,
    subject,
    topic,
    prerequisites,
    questions,
    difficultyCounts,
    sourceType: extracted.sourceType,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  await logDecision({
    type: 'practice_generate',
    userId,
    allowed: true,
    subject,
    topic,
    questionCount: questions.length,
    requestId: req.requestId || null,
  });

  const response: PracticeSetResponse = {
    setId,
    topic,
    prerequisites,
    questions,
  };

  res.json(response);
});

async function handlePracticeCoach(
  req: Request,
  res: Response,
  forcedContextType: ContextType = 'practice',
): Promise<void> {
  const body = (req.body ?? {}) as PracticeCoachRequest;
  const questionId = body.questionId?.trim();
  const questionText = body.questionText?.trim();
  const studentAttemptText = body.studentAttemptText?.trim();

  if (!questionId || !questionText || !studentAttemptText) {
    res.status(400).json({
      error: 'invalid_request',
      message: 'questionId, questionText, and studentAttemptText are required.',
    });
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

  let policy: PolicyGateResponse;
  try {
    policy = await callPolicyGate(req, {
      userId,
      text: `${questionText}\n${studentAttemptText}`,
      contextType: forcedContextType,
      contentHint: JSON.stringify({ questionId }),
    });
  } catch (error) {
    console.error('Policy gate error', error);
    res.status(502).json({ error: 'policy_gate_unavailable' });
    return;
  }

  if (!policy.allowed) {
    await logDecision({
      type: 'practice_coach',
      userId,
      allowed: false,
      reason: policy.reason ?? 'school_only',
      questionId,
      requestId: req.requestId || null,
    });
    res.status(403).json({
      error: 'policy_blocked',
      message: policy.nextStep || 'I can only help with school-related practice coaching.',
    });
    return;
  }

  const provider = config.model.provider;
  const model = provider === 'openai' ? config.model.openai.model : config.model.google.model;
  const maxTokensCoach = config.maxTokensPerEndpoint['POST /ai/practice/coach'];
  const systemPrompt = [
    'You are a Socratic practice coach for students.',
    'Return JSON only with keys: feedback, nextHint, nextQuestionToAskStudent, recommendTutor.',
    'Never give final answers or full solutions.',
    'Keep feedback encouraging and actionable.',
  ].join('\n');

  const userPayload = {
    questionId,
    questionText,
    studentAttemptText,
  };

  const output = await callTextModel({
    provider,
    model,
    jsonOnly: true,
    temperature: 0.2,
    maxTokens: maxTokensCoach,
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: JSON.stringify(userPayload) },
    ],
  });

  const parsed = safeJsonParse(output) ?? {};
  const feedback = defaultString(parsed.feedback, 'Nice start. Let\'s tighten the reasoning step-by-step.');
  const nextHint = defaultString(parsed.nextHint, 'Re-check the key concept and try rewriting the first step.');
  const nextQuestionToAskStudent = defaultString(
    parsed.nextQuestionToAskStudent,
    'What is the first principle or formula you would apply here?',
  );
  const recommendTutor = Boolean(parsed.recommendTutor) || policy.recommendTutor;

  await logDecision({
    type: 'practice_coach',
    userId,
    allowed: true,
    questionId,
    recommendTutor,
    requestId: req.requestId || null,
  });

  const response: PracticeCoachResponse = {
    feedback,
    nextHint,
    nextQuestionToAskStudent,
    recommendTutor,
  };

  res.json(response);
}

router.post('/ai/practice/coach', async (req, res) => {
  await handlePracticeCoach(req, res, 'practice');
});

router.post('/ai/practice/coach/:contextType', async (req, res) => {
  const contextType = resolveContextType(req.params.contextType);
  if (!contextType) {
    res.status(400).json({ error: 'invalid_context', message: 'Unknown context type.' });
    return;
  }
  await handlePracticeCoach(req, res, contextType);
});

export default router;
