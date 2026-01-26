import { Router } from 'express';

import { config } from '../utils/env';
import { getVersionInfo } from '../utils/version';

export const healthRouter = Router();

healthRouter.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: config.serviceName, time: new Date().toISOString() });
});

healthRouter.get('/version', (_req, res) => {
  res.json(getVersionInfo());
});
