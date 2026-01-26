import { NextFunction, Request, Response } from 'express';

import { checkRateLimit } from '../services/rateLimiter';

export async function rateLimit(req: Request, res: Response, next: NextFunction): Promise<void> {
  const userId = req.user?.uid;
  if (!userId) {
    res.status(401).json({ error: 'missing_user', message: 'User not found for rate limiting.' });
    return;
  }

  try {
    const result = await checkRateLimit(userId);
    res.setHeader('x-rate-limit-limit', result.limit.toString());
    res.setHeader('x-rate-limit-remaining', result.remaining.toString());
    res.setHeader('x-rate-limit-reset', Math.ceil(result.resetAt / 1000).toString());

    if (!result.allowed) {
      res.setHeader('retry-after', Math.max(Math.ceil((result.resetAt - Date.now()) / 1000), 1).toString());
      res.status(429).json({ error: 'rate_limited', message: 'Too many requests.' });
      return;
    }

    next();
  } catch (error) {
    console.error('Rate limit check failed', error);
    res.status(503).json({ error: 'rate_limit_unavailable' });
  }
}
