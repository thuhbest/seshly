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
    if (routeKey.startsWith('/ai/policy/gate')) {
        const baseMethodKey = `${req.method.toUpperCase()} /ai/policy/gate`;
        if (env_1.config.rateLimits[baseMethodKey])
            return { key: baseMethodKey, rule: env_1.config.rateLimits[baseMethodKey] };
        if (env_1.config.rateLimits['/ai/policy/gate'])
            return { key: '/ai/policy/gate', rule: env_1.config.rateLimits['/ai/policy/gate'] };
    }
    if (routeKey.startsWith('/ai/practice/coach')) {
        const baseMethodKey = `${req.method.toUpperCase()} /ai/practice/coach`;
        if (env_1.config.rateLimits[baseMethodKey])
            return { key: baseMethodKey, rule: env_1.config.rateLimits[baseMethodKey] };
        if (env_1.config.rateLimits['/ai/practice/coach'])
            return { key: '/ai/practice/coach', rule: env_1.config.rateLimits['/ai/practice/coach'] };
    }
    if (env_1.config.rateLimits.default)
        return { key: 'default', rule: env_1.config.rateLimits.default };
    return null;
}
function isPolicyGateRequest(req) {
    return req.method.toUpperCase() === 'POST' && getRouteKey(req).startsWith('/ai/policy/gate');
}
function ipRule(rule) {
    return {
        windowSeconds: rule.windowSeconds,
        max: Math.max(rule.max * 2, rule.max + 10),
    };
}
async function rateLimit(req, res, next) {
    const userId = req.user?.uid;
    if (!userId) {
        res.status(401).json({ error: 'missing_user', message: 'User not found for rate limiting.' });
        return;
    }
    try {
        const ruleEntry = findRateLimitRule(req);
        const userRule = ruleEntry?.rule ?? env_1.config.rateLimits.default ?? env_1.config.rateLimit;
        const routeKey = ruleEntry?.key || getRouteKey(req);
        const results = [
            await (0, rateLimiter_1.checkRateLimit)(userId, {
                max: userRule.max,
                windowSeconds: userRule.windowSeconds,
                keySuffix: routeKey,
                scope: 'user',
            }),
        ];
        const requestIp = (req.ip || '').trim();
        if (requestIp.length > 0) {
            const derivedIpRule = ipRule(userRule);
            results.push(await (0, rateLimiter_1.checkRateLimit)(requestIp, {
                max: derivedIpRule.max,
                windowSeconds: derivedIpRule.windowSeconds,
                keySuffix: routeKey,
                scope: 'ip',
            }));
        }
        const primaryResult = results[0];
        const blockedResult = results.find((result) => !result.allowed);
        res.setHeader('x-rate-limit-limit', primaryResult.limit.toString());
        res.setHeader('x-rate-limit-remaining', primaryResult.remaining.toString());
        res.setHeader('x-rate-limit-reset', Math.ceil(primaryResult.resetAt / 1000).toString());
        if (blockedResult) {
            console.warn('AI rate limit exceeded', {
                requestId: req.requestId || null,
                userId,
                routeKey,
                scope: blockedResult.scope,
                resetAt: blockedResult.resetAt,
                blockedUntil: blockedResult.blockedUntil,
            });
            const retryAt = blockedResult.blockedUntil ?? blockedResult.resetAt;
            res.setHeader('retry-after', Math.max(Math.ceil((retryAt - Date.now()) / 1000), 1).toString());
            if (isPolicyGateRequest(req)) {
                req.rateLimitExceeded = true;
                req.rateLimitResult = blockedResult;
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
