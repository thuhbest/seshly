import test from "node:test";
import assert from "node:assert/strict";
import {
  buildLowFundsNotificationPayload,
  computeLowFundsCountdown,
  shouldForceEndForProtectionExhaustion,
} from "../tutoringLowFunds.js";

test("low-funds countdown uses the full protected-time deadline", () => {
  const now = new Date("2026-03-31T10:15:00.000Z");
  const sessionStartAt = new Date("2026-03-31T10:00:00.000Z");
  const countdown = computeLowFundsCountdown({
    now,
    sessionStartAt,
    protectedMinutesPurchased: 20,
    protectedMinutesRemaining: 5,
    lowFundsAt: new Date("2026-03-31T10:15:00.000Z"),
  });

  assert.equal(
    countdown.countdownEndsAt?.toISOString(),
    "2026-03-31T10:20:00.000Z"
  );
  assert.equal(countdown.countdownSecondsRemaining, 300);
});

test("low-funds payload keeps a stable countdown as whole minutes shrink", () => {
  const payload = buildLowFundsNotificationPayload({
    now: new Date("2026-03-31T10:16:00.000Z"),
    sessionStartAt: new Date("2026-03-31T10:00:00.000Z"),
    protectedMinutesPurchased: 20,
    protectedMinutesRemaining: 4,
    consumedMinutes: 16,
    refillAttemptCount: 2,
    lowFundsAt: new Date("2026-03-31T10:15:00.000Z"),
    state: "low_funds",
    reason: "reserve_refill_failed",
  });

  assert.equal(payload.countdownEndsAtIso, "2026-03-31T10:20:00.000Z");
  assert.equal(payload.countdownSecondsRemaining, 240);
  assert.equal(payload.roomTerminationRequired, true);
});

test("force-end guard trips exactly at the protected-time deadline", () => {
  const sessionStartAt = new Date("2026-03-31T10:00:00.000Z");

  assert.equal(
    shouldForceEndForProtectionExhaustion({
      now: new Date("2026-03-31T10:19:59.000Z"),
      sessionStartAt,
      protectedMinutesPurchased: 20,
      protectedMinutesRemaining: 1,
      lowFundsAt: new Date("2026-03-31T10:15:00.000Z"),
    }),
    false
  );
  assert.equal(
    shouldForceEndForProtectionExhaustion({
      now: new Date("2026-03-31T10:20:00.000Z"),
      sessionStartAt,
      protectedMinutesPurchased: 20,
      protectedMinutesRemaining: 0,
      lowFundsAt: new Date("2026-03-31T10:15:00.000Z"),
    }),
    true
  );
});
