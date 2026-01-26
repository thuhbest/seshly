import { NextFunction, Request, Response } from 'express';
import admin from 'firebase-admin';

import { getFirestore } from '../services/firebase';
import { config } from '../utils/env';

export function requestLogger(req: Request, res: Response, next: NextFunction): void {
  const start = Date.now();

  res.on('finish', () => {
    const durationMs = Date.now() - start;
    const payload = {
      requestId: req.requestId || null,
      path: req.originalUrl,
      method: req.method,
      status: res.statusCode,
      durationMs,
      userId: req.user?.uid || null,
      ip: req.ip,
      userAgent: req.header('user-agent') || null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    void getFirestore()
      .collection(config.logCollection)
      .add(payload)
      .catch((error) => {
        console.error('Failed to log request', error);
      });
  });

  next();
}
