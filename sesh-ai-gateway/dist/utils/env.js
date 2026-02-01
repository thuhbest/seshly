"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.config = void 0;
function getNumberEnv(name, fallback) {
    const raw = process.env[name];
    if (!raw)
        return fallback;
    const parsed = Number.parseInt(raw, 10);
    return Number.isFinite(parsed) ? parsed : fallback;
}
function getBooleanEnv(name, fallback) {
    const raw = process.env[name];
    if (!raw)
        return fallback;
    return ['1', 'true', 'yes', 'on'].includes(raw.toLowerCase());
}
function parseRateLimits() {
    const raw = process.env.RATE_LIMITS || process.env.RATE_LIMITS_JSON;
    if (!raw)
        return {};
    try {
        const parsed = JSON.parse(raw);
        const out = {};
        for (const [key, value] of Object.entries(parsed)) {
            if (!value)
                continue;
            const windowSeconds = Number.parseInt(String(value.windowSeconds ?? value.windowSec ?? ''), 10);
            const max = Number.parseInt(String(value.max ?? ''), 10);
            if (!Number.isFinite(windowSeconds) || !Number.isFinite(max))
                continue;
            out[key] = { windowSeconds, max };
        }
        return out;
    }
    catch {
        return {};
    }
}
const defaultRateLimits = {
    'POST /ai/policy/gate': { windowSeconds: 60, max: 30 },
};
function getModelProvider() {
    const raw = (process.env.MODEL_PROVIDER || 'openai').toLowerCase();
    return raw === 'google' ? 'google' : 'openai';
}
exports.config = {
    port: getNumberEnv('PORT', 8080),
    serviceName: process.env.SERVICE_NAME || 'sesh-ai-gateway',
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
    maxChatTurnsPerThread: getNumberEnv('MAX_CHAT_TURNS_PER_THREAD', 6),
    strictExamMode: getBooleanEnv('STRICT_EXAM_MODE', false),
    model: {
        provider: getModelProvider(),
        openai: {
            apiKey: process.env.OPENAI_API_KEY || '',
            baseUrl: process.env.OPENAI_BASE_URL || 'https://api.openai.com/v1',
            model: process.env.OPENAI_MODEL || 'gpt-4o-mini',
        },
        google: {
            apiKey: process.env.GOOGLE_API_KEY || '',
            model: process.env.GOOGLE_MODEL || 'gemini-1.5-flash',
        },
    },
};
