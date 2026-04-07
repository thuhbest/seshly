import { NextFunction, Request, Response } from 'express';

import { admitInFlightRequest, releaseInFlightRequest } from '../services/inFlightLimiter';
import { config } from '../utils/env';

export async function backpressure(
  req: Request,
  res: Response,
  next: NextFunction,
): Promise<void> {
  const userId = req.user?.uid;
  if (!userId) {
    res.status(401).json({ error: 'missing_user', message: 'User not found for concurrency control.' });
    return;
  }

  const admission = admitInFlightRequest({
    userId,
    maxPerUser: config.maxInFlightPerUser,
    maxGlobal: config.maxInFlightGlobal,
  });

  if (!admission.allowed) {
    console.warn('AI backpressure rejection', {
      requestId: req.requestId || null,
      userId,
      globalInFlight: admission.globalInFlight,
      userInFlight: admission.userInFlight,
    });
    res.status(503).json({
      error: 'temporarily_busy',
      message: 'Sesh is handling a lot right now. Please try again in a moment.',
      retryable: true,
    });
    return;
  }

  let released = false;
  const release = () => {
    if (released) return;
    released = true;
    releaseInFlightRequest(admission.token);
  };

  res.on('finish', release);
  res.on('close', release);
  res.on('error', release);

  next();
}
