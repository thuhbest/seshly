import test from "node:test";
import assert from "node:assert/strict";
import {
  buildMockPaystackWebhookPayload,
  mapMockPaystackWebhookPayloadToPaymentEvent,
} from "../mockPaystackWebhookSimulator.js";

test("mock webhook payloads are deterministic for the same scenario and seed", async () => {
  const first = await buildMockPaystackWebhookPayload({
    scenario: "capture_success",
    seed: "session_alpha",
    bookingId: "booking_123",
    paymentSessionId: "payment_123",
    sessionId: "session_123",
    authorizationId: "auth_123",
    captureId: "capture_123",
    amountZar: 72,
  });
  const second = await buildMockPaystackWebhookPayload({
    scenario: "capture_success",
    seed: "session_alpha",
    bookingId: "booking_123",
    paymentSessionId: "payment_123",
    sessionId: "session_123",
    authorizationId: "auth_123",
    captureId: "capture_123",
    amountZar: 72,
  });

  assert.deepEqual(first, second);
});

test("mock webhook mapper converts reserve failure payloads into generic payment events", async () => {
  const payload = await buildMockPaystackWebhookPayload({
    scenario: "reserve_preauthorization_failure",
    seed: "session_beta",
    bookingId: "booking_123",
    paymentSessionId: "payment_123",
    sessionId: "session_123",
    authorizationId: "auth_topup_123",
    amountZar: 24,
    reason: "insufficient_available_funds",
  });
  const event = mapMockPaystackWebhookPayloadToPaymentEvent(payload);

  assert.equal(event.provider, "MOCK_PAYSTACK");
  assert.equal(event.eventType, "authorization_reserve_failed");
  assert.equal(event.paymentRail, "TUTORING");
  assert.equal(event.authorizationId, "auth_topup_123");
  assert.equal(event.sessionId, "session_123");
  assert.equal(event.reason, "insufficient_available_funds");
});

test("mock webhook mapper preserves transfer failure recipient and payout ids", async () => {
  const payload = await buildMockPaystackWebhookPayload({
    scenario: "transfer_failure",
    seed: "payout_gamma",
    payoutId: "payout_123",
    payoutBatchId: "batch_123",
    tutorId: "tutor_123",
    recipientCode: "RCP_123",
    amountZar: 480,
  });
  const event = mapMockPaystackWebhookPayloadToPaymentEvent(payload);

  assert.equal(event.eventType, "transfer_failed");
  assert.equal(event.payoutId, "payout_123");
  assert.equal(event.payoutBatchId, "batch_123");
  assert.equal(event.recipientCode, "RCP_123");
  assert.equal(event.amountZar, 480);
});
