import {
  admitInFlightRequest,
  releaseInFlightRequest,
  resetInFlightLimiter,
} from '../src/services/inFlightLimiter';

describe('inFlightLimiter', () => {
  beforeEach(() => {
    resetInFlightLimiter();
  });

  test('caps concurrent requests per user', () => {
    const first = admitInFlightRequest({ userId: 'user_1', maxPerUser: 2, maxGlobal: 10 });
    const second = admitInFlightRequest({ userId: 'user_1', maxPerUser: 2, maxGlobal: 10 });
    const third = admitInFlightRequest({ userId: 'user_1', maxPerUser: 2, maxGlobal: 10 });

    expect(first.allowed).toBe(true);
    expect(second.allowed).toBe(true);
    expect(third.allowed).toBe(false);

    releaseInFlightRequest(first.token);
    const fourth = admitInFlightRequest({ userId: 'user_1', maxPerUser: 2, maxGlobal: 10 });
    expect(fourth.allowed).toBe(true);
  });

  test('caps global concurrent requests', () => {
    const admissions = Array.from({ length: 3 }, (_, index) =>
      admitInFlightRequest({ userId: `user_${index}`, maxPerUser: 5, maxGlobal: 3 }),
    );
    const blocked = admitInFlightRequest({ userId: 'user_4', maxPerUser: 5, maxGlobal: 3 });

    expect(admissions.every((entry) => entry.allowed)).toBe(true);
    expect(blocked.allowed).toBe(false);
  });
});
