import { NextFunction, Request, Response } from 'express';

import { config } from '../utils/env';

type PayloadStats = {
  totalChars: number;
  maxStringChars: number;
  arrayItemsExceeded: boolean;
  objectKeysExceeded: boolean;
  attachmentArrayExceeded: boolean;
};

function inspectPayload(value: unknown, stats: PayloadStats, keyHint = ''): void {
  if (typeof value === 'string') {
    const trimmed = value.trim();
    stats.totalChars += trimmed.length;
    stats.maxStringChars = Math.max(stats.maxStringChars, trimmed.length);
    return;
  }

  if (Array.isArray(value)) {
    if (value.length > config.request.maxArrayItems) {
      stats.arrayItemsExceeded = true;
    }
    if (keyHint.toLowerCase().includes('attachment') && value.length > config.request.maxAttachments) {
      stats.attachmentArrayExceeded = true;
    }
    for (const item of value) {
      inspectPayload(item, stats, keyHint);
    }
    return;
  }

  if (value && typeof value === 'object') {
    const entries = Object.entries(value as Record<string, unknown>);
    if (entries.length > config.request.maxObjectKeys) {
      stats.objectKeysExceeded = true;
    }
    for (const [key, child] of entries) {
      inspectPayload(child, stats, key);
    }
  }
}

export async function payloadGuard(
  req: Request,
  res: Response,
  next: NextFunction,
): Promise<void> {
  if (!req.body || typeof req.body !== 'object') {
    next();
    return;
  }

  const stats: PayloadStats = {
    totalChars: 0,
    maxStringChars: 0,
    arrayItemsExceeded: false,
    objectKeysExceeded: false,
    attachmentArrayExceeded: false,
  };

  inspectPayload(req.body, stats);

  if (stats.maxStringChars > config.request.maxStringChars) {
    res.status(400).json({
      error: 'payload_too_large',
      message: 'One of the text fields is too long. Shorten the request and try again.',
    });
    return;
  }

  if (stats.totalChars > config.request.maxTotalChars) {
    res.status(400).json({
      error: 'payload_too_large',
      message: 'This request is too large. Shorten the content and try again.',
    });
    return;
  }

  if (stats.arrayItemsExceeded || stats.attachmentArrayExceeded) {
    res.status(400).json({
      error: 'too_many_items',
      message: 'Too many attachments or list items were included in one request.',
    });
    return;
  }

  if (stats.objectKeysExceeded) {
    res.status(400).json({
      error: 'payload_shape_invalid',
      message: 'This request contains too many fields.',
    });
    return;
  }

  next();
}
