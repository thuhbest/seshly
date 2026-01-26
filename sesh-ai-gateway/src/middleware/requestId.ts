import { randomUUID } from 'node:crypto';
import { NextFunction, Request, Response } from 'express';

export function requestId(req: Request, res: Response, next: NextFunction): void {
  const inbound = req.header('x-request-id') || req.header('x-correlation-id');
  const id = inbound && inbound.trim().length > 0 ? inbound.trim() : randomUUID();
  req.requestId = id;
  res.setHeader('x-request-id', id);
  next();
}
