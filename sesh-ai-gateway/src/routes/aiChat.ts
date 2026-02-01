import { Router, Request } from 'express';

import { callTextModel } from '../services/modelRouter';
import { getThreadTurns, incrementThreadTurns } from '../services/aiThreadService';
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

type ChatRequest = {
  userId?: string;
  threadId: string;
  message: string;
  context?: {
    postText?: string;
    subject?: string;
    attachments?: string[];
  };
};

type ChatResponse = {
  replyText: string;
  suggestedNextActions: string[];
  recommendTutor: boolean;
  tutorSearchQuery?: { subject?: string; topic?: string; level?: string };
  turnsUsed: number;
  turnsRemaining: number;
};

type SocraticModelOutput = {
  clarificationQuestion: string;
  hint: string;
  tryStep: string;
  suggestedNextActions?: string[];
  tutorSearchQuery?: { subject?: string; topic?: string; level?: string };
};

const router = Router();

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

function normalizeArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.map((item) => String(item)).filter((item) => item.trim().length > 0);
}

function ensureQuestion(text: string): string {
  const trimmed = text.trim();
  if (!trimmed) return 'What part of the problem is confusing or unclear right now?';
  return trimmed.endsWith('?') ? trimmed : `${trimmed}?`;
}

function buildReplyText(output: SocraticModelOutput): string {
  const question = ensureQuestion(output.clarificationQuestion);
  const hint = output.hint?.trim() || 'Try to identify the key concept and restate it in your own words.';
  const tryStep = output.tryStep?.trim() || 'Work out the first small step and share what you get.';
  return `Quick question: ${question}\nHint: ${hint}\nTry this step: ${tryStep}`;
}

function buildDefaultActions(subject?: string): string[] {
  const base = [
    'Tell me where you got stuck.',
    'Show your last attempted step.',
    'Share any relevant formulas or notes.',
  ];
  if (subject) {
    base.unshift(`Confirm the topic/subject is ${subject}.`);
  }
  return base.slice(0, 3);
}

function parseModelOutput(raw: string): SocraticModelOutput {
  const parsed = safeJsonParse(raw) ?? {};
  return {
    clarificationQuestion: String(parsed.clarificationQuestion ?? ''),
    hint: String(parsed.hint ?? ''),
    tryStep: String(parsed.tryStep ?? ''),
    suggestedNextActions: normalizeArray(parsed.suggestedNextActions),
    tutorSearchQuery: parsed.tutorSearchQuery as SocraticModelOutput['tutorSearchQuery'],
  };
}

async function callPolicyGate(req: Request, payload: PolicyGateInput): Promise<PolicyGateResponse> {
  const authHeader = req.header('authorization') || '';
  const response = await fetch(`http://127.0.0.1:${config.port}/ai/policy/gate/practice`, {
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

async function buildSocraticResponse(
  message: string,
  context: ChatRequest['context'],
): Promise<SocraticModelOutput> {
  const provider = config.model.provider;
  const model = provider === 'openai' ? config.model.openai.model : config.model.google.model;
  const maxTokens = config.maxTokensPerEndpoint['POST /ai/chat/socratic'];
  const system = [
    'You are a Socratic tutor for students.',
    'Return JSON only with keys:',
    'clarificationQuestion, hint, tryStep, suggestedNextActions, tutorSearchQuery.',
    'Never give final answers or full solutions.',
    'Use exactly one clarification question, one hint, and one tryStep instruction.',
    'Keep each field concise.',
  ].join('\n');

  const userPayload = {
    message,
    context: context ?? null,
  };

  const output = await callTextModel({
    provider,
    model,
    jsonOnly: true,
    temperature: 0.2,
    maxTokens,
    messages: [
      { role: 'system', content: system },
      { role: 'user', content: JSON.stringify(userPayload) },
    ],
  });

  return parseModelOutput(output);
}

router.post('/ai/chat/socratic', async (req, res) => {
  const body = (req.body ?? {}) as ChatRequest;
  const message = typeof body.message === 'string' ? body.message.trim() : '';
  const threadId = body.threadId?.trim();

  if (!message || !threadId) {
    res.status(400).json({ error: 'invalid_request', message: 'threadId and message are required.' });
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

  const currentTurns = await getThreadTurns(threadId);
  const contentHint = JSON.stringify({
    subject: body.context?.subject ?? null,
    attachments: body.context?.attachments?.length ?? 0,
    turnCount: currentTurns,
  });

  let policy: PolicyGateResponse;
  try {
    policy = await callPolicyGate(req, {
      userId,
      text: message,
      contextType: 'practice',
      contentHint,
    });
  } catch (error) {
    console.error('Policy gate error', error);
    res.status(502).json({ error: 'policy_gate_unavailable' });
    return;
  }

  if (!policy.allowed) {
    const refusal: ChatResponse = {
      replyText:
        policy.nextStep ||
        'I can only help with school-related questions. Please share a study topic or assignment.',
      suggestedNextActions: policy.nextStep ? [policy.nextStep] : [],
      recommendTutor: policy.recommendTutor,
      turnsUsed: currentTurns,
      turnsRemaining: Math.max(config.maxChatTurnsPerThread - currentTurns, 0),
    };
    res.json(refusal);
    return;
  }

  const threadState = await incrementThreadTurns(threadId, userId, message.slice(0, 120));
  const turnsUsed = threadState.turnsUsed;
  const turnsRemaining = Math.max(config.maxChatTurnsPerThread - turnsUsed, 0);

  if (turnsUsed > config.maxChatTurnsPerThread) {
    const cta: ChatResponse = {
      replyText:
        'You’ve hit the max number of turns for this thread. A tutor can take you the rest of the way with a full walkthrough.',
      suggestedNextActions: ['Request a tutor', 'Share the exact topic or course code'],
      recommendTutor: true,
      tutorSearchQuery: {
        subject: body.context?.subject,
      },
      turnsUsed,
      turnsRemaining: 0,
    };
    res.json(cta);
    return;
  }

  const modelOutput = await buildSocraticResponse(message, body.context);
  const replyText = buildReplyText(modelOutput);
  const suggestedNextActions =
    modelOutput.suggestedNextActions && modelOutput.suggestedNextActions.length > 0
      ? modelOutput.suggestedNextActions
      : buildDefaultActions(body.context?.subject);

  const response: ChatResponse = {
    replyText,
    suggestedNextActions,
    recommendTutor: policy.recommendTutor,
    tutorSearchQuery: modelOutput.tutorSearchQuery ?? (body.context?.subject ? { subject: body.context.subject } : undefined),
    turnsUsed,
    turnsRemaining,
  };

  res.json(response);
});

export default router;
