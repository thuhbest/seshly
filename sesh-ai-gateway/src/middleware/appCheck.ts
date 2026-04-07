import { NextFunction, Request, Response } from 'express';

import { getFirebaseApp } from '../services/firebase';
import { config } from '../utils/env';

export async function appCheck(
  req: Request,
  res: Response,
  next: NextFunction,
): Promise<void> {
  const token = req.header('x-firebase-appcheck') || req.header('x-firebase-app-check') || '';
  if (!token) {
    if (config.requireAppCheck) {
      res.status(401).json({
        error: 'app_check_required',
        message: 'App integrity verification is required for this request.',
      });
      return;
    }
    next();
    return;
  }

  try {
    await getFirebaseApp().appCheck().verifyToken(token);
    req.appCheckVerified = true;
    next();
  } catch (error) {
    console.error('App Check verification failed', error);
    res.status(401).json({
      error: 'invalid_app_check',
      message: 'App integrity verification failed.',
    });
  }
}
