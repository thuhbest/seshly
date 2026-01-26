import { NextFunction, Request, Response } from 'express';

import { getAuth } from '../services/firebase';

export async function authVerifyFirebaseIdToken(
  req: Request,
  res: Response,
  next: NextFunction,
): Promise<void> {
  const header = req.header('authorization') || '';
  const match = header.match(/^Bearer\s+(.+)$/i);

  if (!match) {
    res.status(401).json({ error: 'missing_auth', message: 'Missing Authorization bearer token.' });
    return;
  }

  try {
    const decoded = await getAuth().verifyIdToken(match[1]);
    req.user = decoded;
    next();
  } catch (error) {
    console.error('Auth verification failed', error);
    res.status(401).json({ error: 'invalid_token', message: 'Invalid or expired token.' });
  }
}
