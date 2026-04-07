import { NextFunction, Request, Response } from 'express';

import { consumeTokens } from '../services/aiUsageService';
import { config } from '../utils/env';

function getRouteKey(req: Request): string {
  if (req.baseUrl && req.path) return `${req.baseUrl}${req.path}`;
  return req.path || req.originalUrl || '';
}

function normalizeRouteKey(routeKey: string): string {
  if (routeKey.startsWith('/ai/policy/gate')) return '/ai/policy/gate';
  if (routeKey.startsWith('/ai/practice/coach')) return '/ai/practice/coach';
  return routeKey;
}

function estimateTokensFromBody(body: unknown): number {
  if (!body) return 0;
  const payload = typeof body === 'string' ? body : JSON.stringify(body);
  const length = payload?.length ?? 0;
  return Math.max(1, Math.ceil(length / 4));
}

function findMaxTokens(req: Request): number | null {
  const routeKey = normalizeRouteKey(getRouteKey(req));
  const methodKey = `${req.method.toUpperCase()} ${routeKey}`;
  if (config.maxTokensPerEndpoint[methodKey]) return config.maxTokensPerEndpoint[methodKey];
  if (config.maxTokensPerEndpoint[routeKey]) return config.maxTokensPerEndpoint[routeKey];
  return null;
}

function buildBudgetResponse(res: Response): void {
  res.status(429).json({
    error: 'token_budget_exceeded',
    message:
      'You have reached your daily AI usage limit. Please try later or request a tutor for immediate help.',
    recommendTutor: true,
  });
}

export async function costControl(req: Request, res: Response, next: NextFunction): Promise<void> {
  const userId = req.user?.uid;
  if (!userId) {
    res.status(401).json({ error: 'missing_user', message: 'User not found for cost controls.' });
    return;
  }

  const maxTokens = findMaxTokens(req);
  if (maxTokens === null) {
    next();
    return;
  }

  const inputTokens = estimateTokensFromBody(req.body);
  const estimatedTotal = inputTokens + maxTokens;

  if (inputTokens > maxTokens) {
    console.warn('AI payload token limit exceeded', {
      requestId: req.requestId || null,
      userId,
      routeKey: getRouteKey(req),
      inputTokens,
      maxTokens,
    });
    res.status(400).json({
      error: 'token_limit_exceeded',
      message: 'Request is too large for this endpoint. Please shorten your input.',
      recommendTutor: true,
    });
    return;
  }

  try {
    const result = await consumeTokens(userId, estimatedTotal, config.dailyTokenBudget);
    if (!result.allowed) {
      console.warn('AI daily token budget exceeded', {
        requestId: req.requestId || null,
        userId,
        routeKey: getRouteKey(req),
        estimatedTotal,
        remaining: result.remaining,
      });
      buildBudgetResponse(res);
      return;
    }
  } catch (error) {
    console.error('Cost control check failed', error);
    res.status(503).json({ error: 'token_budget_unavailable' });
    return;
  }

  next();
}
