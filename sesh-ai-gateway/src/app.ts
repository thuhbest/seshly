import cors from 'cors';
import express, { NextFunction, Request, Response } from 'express';

import { authVerifyFirebaseIdToken } from './middleware/authVerifyFirebaseIdToken';
import { appCheck } from './middleware/appCheck';
import { payloadGuard } from './middleware/payloadGuard';
import { rateLimit } from './middleware/rateLimit';
import { backpressure } from './middleware/backpressure';
import { costControl } from './middleware/costControl';
import { requestId } from './middleware/requestId';
import { logging } from './middleware/logging';
import { config } from './utils/env';
import aiPolicyRouter from './routes/aiPolicy';
import aiChatRouter from './routes/aiChat';
import aiClassroomMemoryRouter from './routes/aiClassroomMemory';
import aiNotesRouter from './routes/aiNotes';
import aiPracticeRouter from './routes/aiPractice';
import aiSessionRouter from './routes/aiSession';
import aiCalendarRouter from './routes/aiCalendar';
import aiVaultRouter from './routes/aiVault';
import aiTutorsRouter from './routes/aiTutors';
import { healthRouter } from './routes/health';

const app = express();
app.disable('x-powered-by');
app.set('trust proxy', true);

app.use(
  cors({
    origin: true,
    credentials: true,
    allowedHeaders: ['content-type', 'authorization', 'x-request-id'],
    methods: ['GET', 'POST', 'OPTIONS'],
  })
);
app.options('*', cors());

app.use(express.json({ limit: `${config.request.maxBodyKilobytes}kb` }));
app.use(requestId);
app.use(logging);
app.use(payloadGuard);

app.use(healthRouter);

app.use(authVerifyFirebaseIdToken);
app.use(appCheck);
app.use(rateLimit);
app.use(backpressure);
app.use(costControl);
app.use(aiPolicyRouter);
app.use(aiChatRouter);
app.use(aiClassroomMemoryRouter);
app.use(aiNotesRouter);
app.use(aiPracticeRouter);
app.use(aiSessionRouter);
app.use(aiCalendarRouter);
app.use(aiVaultRouter);
app.use(aiTutorsRouter);

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

export default app;
