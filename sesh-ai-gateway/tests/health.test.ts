import request from 'supertest';
import Ajv from 'ajv';

jest.mock('../src/middleware/authVerifyFirebaseIdToken', () => ({
  authVerifyFirebaseIdToken: (req: any, _res: any, next: any) => {
    req.user = { uid: 'test-user' };
    next();
  },
}));

jest.mock('../src/middleware/rateLimit', () => ({
  rateLimit: (_req: any, _res: any, next: any) => next(),
}));

jest.mock('../src/middleware/costControl', () => ({
  costControl: (_req: any, _res: any, next: any) => next(),
}));

jest.mock('../src/middleware/logging', () => ({
  logging: (_req: any, _res: any, next: any) => next(),
}));

jest.mock('../src/services/modelRouter', () => ({
  callTextModel: jest.fn().mockResolvedValue('{"category":"school","intent":"socratic_help"}'),
}));

jest.mock('../src/services/firestoreService', () => {
  const actual = jest.requireActual('../src/services/firestoreService');
  return {
    ...actual,
    aiLogsCollection: () => ({ add: jest.fn().mockResolvedValue(null) }),
  };
});

import app from '../src/app';

const ajv = new Ajv();

describe('sesh-ai-gateway integration', () => {
  it('GET /health returns expected schema', async () => {
    const res = await request(app).get('/health');
    expect(res.status).toBe(200);

    const schema = {
      type: 'object',
      properties: {
        status: { type: 'string' },
        service: { type: 'string' },
        time: { type: 'string' },
      },
      required: ['status', 'service', 'time'],
      additionalProperties: true,
    };

    const valid = ajv.validate(schema, res.body);
    expect(valid).toBe(true);
  });

  it('POST /ai/policy/gate returns expected schema', async () => {
    const res = await request(app)
      .post('/ai/policy/gate')
      .send({ userId: 'test-user', text: 'Explain quadratic formula', contextType: 'practice' });
    expect(res.status).toBe(200);

    const schema = {
      type: 'object',
      properties: {
        allowed: { type: 'boolean' },
        category: { type: 'string' },
        intent: { type: 'string' },
        recommendTutor: { type: 'boolean' },
        reason: { type: 'string', nullable: true },
        nextStep: { type: 'string', nullable: true },
      },
      required: ['allowed', 'category', 'intent', 'recommendTutor'],
      additionalProperties: true,
    };

    const valid = ajv.validate(schema, res.body);
    expect(valid).toBe(true);
  });
});
