import { Request, Response, Router } from 'express';
import { FieldValue } from 'firebase-admin/firestore';

import { callTextModel } from '../services/modelRouter';
import { aiLogsCollection } from '../services/firestoreService';
import { buildSchoolOnlyMessage, evaluateAcademicGuard } from '../services/academicGuard';
import { config } from '../utils/env';

type ContextType =
  | 'comment'
  | 'sesh_screen'
  | 'practice'
  | 'notes'
  | 'session'
  | 'calendar'
  | 'vault'
  | 'snap';

type Category = 'school' | 'non_school' | 'unknown';
type Intent = 'socratic_help' | 'answer_seeking' | 'content_generation' | 'other';

type PolicyGateRequest = {
  userId?: string;
  text: string;
  contextType?: ContextType;
  contentHint?: string;
};

type PolicyGateResponse = {
  allowed: boolean;
  category: Category;
  intent: Intent;
  recommendTutor: boolean;
  reason?: 'school_only' | 'rate_limited' | 'blocked';
  nextStep?: string;
};

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

const systemPrompt = [
  'You are a classifier for Seshly, an education-focused app.',
  'Return JSON only.',
  'Classify category: school | non_school | unknown.',
  'Classify intent: socratic_help | answer_seeking | content_generation | other.',
  'Definitions:',
  '- school: academic help, coursework, studying, tutoring, campus learning.',
  '- non_school: entertainment, personal life, shopping, unrelated topics.',
  '- unknown: unclear or mixed.',
  '- answer_seeking: asks for final answers/solutions.',
  '- socratic_help: wants hints/explanations/step-by-step learning.',
  '- content_generation: asks to draft essays, posts, long-form text.',
  '- other: anything else.',
].join('\n');

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

function normalizeCategory(value: unknown): Category {
  const raw = String(value || '').toLowerCase();
  if (raw === 'school') return 'school';
  if (raw === 'non_school' || raw === 'nonschool' || raw === 'non-school') return 'non_school';
  return 'unknown';
}

function normalizeIntent(value: unknown): Intent {
  const raw = String(value || '').toLowerCase();
  if (raw === 'socratic_help' || raw === 'socratic') return 'socratic_help';
  if (raw === 'answer_seeking' || raw === 'answer') return 'answer_seeking';
  if (raw === 'content_generation' || raw === 'generation' || raw === 'content') return 'content_generation';
  return 'other';
}

function detectFullAnswerRequest(text: string): boolean {
  const patterns = [
    /\bjust the answer\b/i,
    /\banswer only\b/i,
    /\bfinal answer\b/i,
    /\bgive me the answer\b/i,
    /\bwhat'?s the answer\b/i,
    /\bsolve (it|this) for me\b/i,
    /\bdo it for me\b/i,
    /\bno explanation\b/i,
    /\bfull answer\b/i,
  ];
  return patterns.some((pattern) => pattern.test(text));
}

function detectRepeatRequest(text: string, contentHint?: string): boolean {
  const haystack = `${text} ${contentHint ?? ''}`.toLowerCase();
  return [
    'again',
    'repeat',
    'already asked',
    'as i said',
    'same question',
    'told you',
    'still',
  ].some((token) => haystack.includes(token));
}

function parseTurnCount(contentHint?: string): number | null {
  if (!contentHint) return null;
  try {
    const parsed = JSON.parse(contentHint);
    if (typeof parsed?.turnCount === 'number') return parsed.turnCount;
  } catch {
    const match = contentHint.match(/turns?\s*[:=]\s*(\d+)/i);
    if (match) return Number.parseInt(match[1], 10);
  }
  return null;
}

async function classifyText(
  text: string,
  contextType: ContextType,
  contentHint?: string,
): Promise<{ category: Category; intent: Intent }> {
  const provider = config.model.provider;
  const model = provider === 'openai' ? config.model.openai.model : config.model.google.model;
  const maxTokens = config.maxTokensPerEndpoint['POST /ai/policy/gate'];

  const messages = [
    { role: 'system' as const, content: systemPrompt },
    {
      role: 'user' as const,
      content: JSON.stringify({
        text,
        contextType,
        contentHint: contentHint || null,
      }),
    },
  ];

  const output = await callTextModel({
    provider,
    model,
    messages,
    jsonOnly: true,
    temperature: 0,
    maxTokens,
  });

  const parsed = safeJsonParse(output);
  return {
    category: normalizeCategory(parsed?.category),
    intent: normalizeIntent(parsed?.intent),
  };
}

async function logDecision(payload: Record<string, unknown>): Promise<void> {
  try {
    await aiLogsCollection().add({
      ...payload,
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (error) {
    console.error('Failed to log policy decision', error);
  }
}

async function handlePolicyGate(
  req: Request,
  res: Response,
  forcedContextType?: ContextType,
): Promise<void> {
  const body = (req.body ?? {}) as PolicyGateRequest;
  const text = typeof body.text === 'string' ? body.text.trim() : '';
  const contextType = forcedContextType ?? body.contextType;

  if (forcedContextType && body.contextType && body.contextType !== forcedContextType) {
    res.status(400).json({
      error: 'context_mismatch',
      message: `Context type must be ${forcedContextType} for this endpoint.`,
    });
    return;
  }

  if (!text || !contextType || !allowedContextTypes.includes(contextType)) {
    res.status(400).json({ error: 'invalid_request', message: 'text and contextType are required.' });
    return;
  }

  const authedUserId = req.user?.uid;
  if (authedUserId && body.userId && body.userId !== authedUserId) {
    res.status(403).json({ error: 'user_mismatch' });
    return;
  }

  const userId = authedUserId || body.userId || null;

  if (req.rateLimitExceeded) {
    const response: PolicyGateResponse = {
      allowed: false,
      category: 'unknown',
      intent: 'other',
      recommendTutor: false,
      reason: 'rate_limited',
      nextStep: "You're sending requests too fast. Please wait a bit and try again.",
    };
    await logDecision({
      type: 'policy_gate',
      userId,
      contextType,
      textSnippet: text.slice(0, 200),
      ...response,
      requestId: req.requestId || null,
      rateLimit: req.rateLimitResult ?? null,
    });
    res.json(response);
    return;
  }

  let category: Category = 'unknown';
  let intent: Intent = 'other';
  const academicGuard = evaluateAcademicGuard(text);

  if (academicGuard.outcome === 'block') {
    const response: PolicyGateResponse = {
      allowed: false,
      category: academicGuard.category,
      intent: 'other',
      recommendTutor: false,
      reason: 'school_only',
      nextStep: academicGuard.message,
    };
    await logDecision({
      type: 'policy_gate',
      userId,
      contextType,
      textSnippet: text.slice(0, 200),
      academicGuardReason: academicGuard.reason,
      ...response,
      requestId: req.requestId || null,
      strictExamMode: config.strictExamMode,
    });
    res.json(response);
    return;
  }

  if (academicGuard.category === 'school') {
    category = 'school';
  }

  if (academicGuard.reason === 'needs_model_review') {
    try {
      const classified = await classifyText(text, contextType, body.contentHint);
      category = classified.category;
      intent = classified.intent;
    } catch (error) {
      console.error('Policy classification failed', error);
    }
  }

  const isPracticeContext = ['practice', 'comment', 'sesh_screen'].includes(contextType);
  const wantsFullAnswer = detectFullAnswerRequest(text);
  const isRepeat = detectRepeatRequest(text, body.contentHint);
  const turnCount = parseTurnCount(body.contentHint);
  const exceededTurns = turnCount !== null && turnCount >= config.maxChatTurnsPerThread;
  const shouldRecommendTutor = wantsFullAnswer || isRepeat || exceededTurns;

  if (intent === 'answer_seeking' && isPracticeContext) {
    intent = 'socratic_help';
  }

  let response: PolicyGateResponse = {
    allowed: true,
    category,
    intent,
    recommendTutor: false,
  };

  if (category === 'non_school') {
    response = {
      allowed: false,
      category,
      intent,
      recommendTutor: false,
      reason: 'school_only',
      nextStep: buildSchoolOnlyMessage(false),
    };
  } else if (category === 'unknown') {
    response = {
      allowed: false,
      category,
      intent,
      recommendTutor: false,
      reason: 'school_only',
      nextStep: buildSchoolOnlyMessage(true),
    };
  } else if (intent === 'socratic_help' && isPracticeContext) {
    response.recommendTutor = shouldRecommendTutor;
    if (response.recommendTutor) {
      response.nextStep = 'If you want a full walkthrough, a tutor can help you get unstuck quickly.';
    } else if (config.strictExamMode && wantsFullAnswer) {
      response.nextStep = 'Exam mode is on, so I can guide you step-by-step instead of giving full answers.';
    }
  }

  await logDecision({
    type: 'policy_gate',
    userId,
    contextType,
    textSnippet: text.slice(0, 200),
    ...response,
    requestId: req.requestId || null,
    strictExamMode: config.strictExamMode,
  });

  res.json(response);
}

router.post('/ai/policy/gate', async (req, res) => {
  await handlePolicyGate(req, res);
});

router.post('/ai/policy/gate/:contextType', async (req, res) => {
  const raw = String(req.params.contextType || '').toLowerCase();
  const contextType = allowedContextTypes.find((value) => value === raw) as ContextType | undefined;
  if (!contextType) {
    res.status(400).json({ error: 'invalid_context', message: 'Unknown context type.' });
    return;
  }
  await handlePolicyGate(req, res, contextType);
});

export default router;
