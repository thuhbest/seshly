type RateLimitRule = {
  windowSeconds: number;
  max: number;
};

type MaxTokenRule = {
  maxTokens: number;
};

type ModelProvider = 'openai' | 'google';

function getNumberEnv(name: string, fallback: number): number {
  const raw = process.env[name];
  if (!raw) return fallback;
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function getBooleanEnv(name: string, fallback: boolean): boolean {
  const raw = process.env[name];
  if (!raw) return fallback;
  return ['1', 'true', 'yes', 'on'].includes(raw.toLowerCase());
}

function parseRateLimits(): Record<string, RateLimitRule> {
  const raw = process.env.RATE_LIMITS || process.env.RATE_LIMITS_JSON;
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw) as Record<string, Partial<RateLimitRule>>;
    const out: Record<string, RateLimitRule> = {};
    for (const [key, value] of Object.entries(parsed)) {
      if (!value) continue;
      const windowSeconds = Number.parseInt(
        String((value as Record<string, unknown>).windowSeconds ?? (value as Record<string, unknown>).windowSec ?? ''),
        10,
      );
      const max = Number.parseInt(String(value.max ?? ''), 10);
      if (!Number.isFinite(windowSeconds) || !Number.isFinite(max)) continue;
      out[key] = { windowSeconds, max };
    }
    return out;
  } catch {
    return {};
  }
}

function parseMaxTokens(): Record<string, number> {
  const raw = process.env.MAX_TOKENS_PER_ENDPOINT || process.env.MAX_TOKENS_JSON;
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw) as Record<string, Partial<MaxTokenRule>>;
    const out: Record<string, number> = {};
    for (const [key, value] of Object.entries(parsed)) {
      if (!value) continue;
      const maxTokens = Number.parseInt(String((value as Record<string, unknown>).maxTokens ?? ''), 10);
      if (!Number.isFinite(maxTokens)) continue;
      out[key] = maxTokens;
    }
    return out;
  } catch {
    return {};
  }
}

const defaultRateLimits: Record<string, RateLimitRule> = {
  'POST /ai/policy/gate': { windowSeconds: 60, max: 30 },
  'POST /ai/chat/socratic': { windowSeconds: 3600, max: 20 },
  'POST /ai/classroom/memory/build': { windowSeconds: 3600, max: 12 },
  'POST /ai/notes/enhance': { windowSeconds: 3600, max: 8 },
  'POST /ai/practice/generate': { windowSeconds: 3600, max: 8 },
  'POST /ai/practice/coach': { windowSeconds: 3600, max: 60 },
  'POST /ai/session/summarize': { windowSeconds: 3600, max: 10 },
  'POST /ai/calendar/importTimetable': { windowSeconds: 3600, max: 6 },
  'POST /ai/vault/checkDuplicate': { windowSeconds: 3600, max: 20 },
  'POST /ai/affirmations/toggle': { windowSeconds: 3600, max: 30 },
  'POST /ai/tutors/match': { windowSeconds: 3600, max: 60 },
};

const defaultMaxTokens: Record<string, number> = {
  'POST /ai/policy/gate': 256,
  'POST /ai/chat/socratic': 600,
  'POST /ai/classroom/memory/build': 1600,
  'POST /ai/notes/enhance': 1200,
  'POST /ai/practice/generate': 1200,
  'POST /ai/practice/coach': 500,
  'POST /ai/session/summarize': 1200,
  'POST /ai/calendar/importTimetable': 1000,
  'POST /ai/vault/checkDuplicate': 600,
};

function getModelProvider(): ModelProvider {
  const raw = (process.env.MODEL_PROVIDER || 'openai').toLowerCase();
  return raw === 'google' ? 'google' : 'openai';
}

export const config = {
  port: getNumberEnv('PORT', 8080),
  serviceName: process.env.SERVICE_NAME || 'sesh-ai-gateway',
  requireAppCheck: getBooleanEnv('REQUIRE_APP_CHECK', false),
  logCollection: process.env.LOG_COLLECTION || 'ai_logs',
  rateLimitCollection: process.env.RATE_LIMIT_COLLECTION || 'ai_rate_limits',
  rateLimit: {
    windowSeconds: getNumberEnv('RATE_LIMIT_WINDOW_SECONDS', 60),
    max: getNumberEnv('RATE_LIMIT_MAX', 60),
  },
  rateLimits: {
    ...defaultRateLimits,
    ...parseRateLimits(),
  },
  maxTokensPerEndpoint: {
    ...defaultMaxTokens,
    ...parseMaxTokens(),
  },
  request: {
    maxBodyKilobytes: getNumberEnv('MAX_REQUEST_BODY_KB', 512),
    maxTotalChars: getNumberEnv('MAX_REQUEST_TOTAL_CHARS', 12000),
    maxStringChars: getNumberEnv('MAX_REQUEST_STRING_CHARS', 5000),
    maxArrayItems: getNumberEnv('MAX_REQUEST_ARRAY_ITEMS', 20),
    maxObjectKeys: getNumberEnv('MAX_REQUEST_OBJECT_KEYS', 80),
    maxAttachments: getNumberEnv('MAX_REQUEST_ATTACHMENTS', 6),
    timeoutMs: getNumberEnv('MODEL_REQUEST_TIMEOUT_MS', 20000),
  },
  maxInFlightPerUser: getNumberEnv('MAX_IN_FLIGHT_PER_USER', 2),
  maxInFlightGlobal: getNumberEnv('MAX_IN_FLIGHT_GLOBAL', 80),
  dailyTokenBudget: getNumberEnv(process.env.TOKEN_BUDGET_DAILY ? 'TOKEN_BUDGET_DAILY' : 'DAILY_TOKEN_BUDGET', 20000),
  maxChatTurnsPerThread: getNumberEnv('MAX_CHAT_TURNS_PER_THREAD', 6),
  strictExamMode: getBooleanEnv('STRICT_EXAM_MODE', false),
  model: {
    provider: getModelProvider(),
    openai: {
      apiKey: process.env.OPENAI_API_KEY || '',
      baseUrl: process.env.OPENAI_BASE_URL || 'https://api.openai.com/v1',
      model: process.env.OPENAI_MODEL || 'gpt-4o-mini',
      cheapModel: process.env.OPENAI_CHEAP_MODEL || 'gpt-4o-mini',
      expensiveModel: process.env.OPENAI_EXPENSIVE_MODEL || process.env.OPENAI_MODEL || 'gpt-4.1',
      embedModel: process.env.OPENAI_EMBED_MODEL || 'text-embedding-3-small',
    },
    google: {
      apiKey: process.env.GOOGLE_API_KEY || '',
      model: process.env.GOOGLE_MODEL || 'gemini-1.5-flash',
      cheapModel: process.env.GOOGLE_CHEAP_MODEL || 'gemini-1.5-flash',
      expensiveModel: process.env.GOOGLE_EXPENSIVE_MODEL || process.env.GOOGLE_MODEL || 'gemini-1.5-pro',
      embedModel: process.env.GOOGLE_EMBED_MODEL || 'text-embedding-004',
    },
  },
};

export type { RateLimitRule, ModelProvider };
