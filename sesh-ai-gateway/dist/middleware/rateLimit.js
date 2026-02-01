"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.rateLimit = rateLimit;
const rateLimiter_1 = require("../services/rateLimiter");
const env_1 = require("../utils/env");
function getRouteKey(req) {
    if (req.baseUrl && req.path)
        return `${req.baseUrl}${req.path}`;
    return req.path || req.originalUrl || '';
}
function findRateLimitRule(req) {
    const routeKey = getRouteKey(req);
    const methodKey = `${req.method.toUpperCase()} ${routeKey}`;
    if (env_1.config.rateLimits[methodKey])
        return { key: methodKey, rule: env_1.config.rateLimits[methodKey] };
    if (env_1.config.rateLimits[routeKey])
        return { key: routeKey, rule: env_1.config.rateLimits[routeKey] };
    if (env_1.config.rateLimits.default)
        return { key: 'default', rule: env_1.config.rateLimits.default };
    return null;
}
function isPolicyGateRequest(req) {
    return req.method.toUpperCase() === 'POST' && getRouteKey(req) === '/ai/policy/gate';
}
async function rateLimit(req, res, next) {
    const userId = req.user?.uid;
    if (!userId) {
        res.status(401).json({ error: 'missing_user', message: 'User not found for rate limiting.' });
        return;
    }
    try {
        const ruleEntry = findRateLimitRule(req);
        const result = await (0, rateLimiter_1.checkRateLimit)(userId, {
            max: ruleEntry?.rule.max,
            windowSeconds: ruleEntry?.rule.windowSeconds,
            keySuffix: ruleEntry?.key,
        });
        res.setHeader('x-rate-limit-limit', result.limit.toString());
        res.setHeader('x-rate-limit-remaining', result.remaining.toString());
        res.setHeader('x-rate-limit-reset', Math.ceil(result.resetAt / 1000).toString());
        if (!result.allowed) {
            res.setHeader('retry-after', Math.max(Math.ceil((result.resetAt - Date.now()) / 1000), 1).toString());
            if (isPolicyGateRequest(req)) {
                req.rateLimitExceeded = true;
                req.rateLimitResult = result;
                next();
                return;
            }
            res.status(429).json({ error: 'rate_limited', message: 'Too many requests.' });
            return;
        }
        next();
    }
    catch (error) {
        console.error('Rate limit check failed', error);
        res.status(503).json({ error: 'rate_limit_unavailable' });
    }
}
