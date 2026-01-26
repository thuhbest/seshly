import express, { NextFunction, Request, Response } from 'express';

import { authVerifyFirebaseIdToken } from './middleware/authVerifyFirebaseIdToken';
import { rateLimit } from './middleware/rateLimit';
import { requestId } from './middleware/requestId';
import { requestLogger } from './middleware/requestLogger';
import { healthRouter } from './routes/health';
import { config } from './utils/env';

const app = express();
app.disable('x-powered-by');

app.use(express.json({ limit: '1mb' }));
app.use(requestId);
app.use(requestLogger);

app.use(healthRouter);

app.use(authVerifyFirebaseIdToken);
app.use(rateLimit);

app.get('/', (req: Request, res: Response) => {
  res.json({ ok: true, message: 'sesh-ai-gateway ready', requestId: req.requestId });
});

app.use((req: Request, res: Response) => {
  res.status(404).json({ error: 'not_found' });
});

app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
  console.error('Unhandled error', err);
  res.status(500).json({ error: 'internal_error' });
});

app.listen(config.port, () => {
  console.log(`[sesh-ai-gateway] listening on ${config.port}`);
});
