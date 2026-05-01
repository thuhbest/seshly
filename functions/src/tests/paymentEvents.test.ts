import test from "node:test";
import assert from "node:assert/strict";
import {
  mapAuthorizationCreatedEvent,
  mapAuthorizationReserveFailedEvent,
  mapCaptureSucceededEvent,
  mapTransferFailedEvent,
  normalizePaymentEventInput,
  paymentEventDocumentId,
} from "../paymentEvents.js";

test("payment event document ids deduplicate by provider and external event id", () => {
  const first = paymentEventDocumentId("MOCK_PAYSTACK", "evt_123");
  const second = paymentEventDocumentId("MOCK_PAYSTACK", "evt_123");
  const third = paymentEventDocumentId("MOCK_PAYSTACK", "evt_456");

  assert.equal(first, second);
  assert.notEqual(first, third);
});

test("authorization mapper normalizes tutoring authorization targets", () => {
  const event = normalizePaymentEventInput({
    provider: "MOCK_PAYSTACK",
    externalEventId: "evt_auth_123",
    eventType: "authorization_created",
    paymentRail: "TUTORING",
    authorizationId: "auth_123",
    bookingId: "booking_123",
    paymentSessionId: "payment_123",
    amountZar: 48,
    currency: "zar",
  });
  const mapped = mapAuthorizationCreatedEvent(event);

  assert.equal(mapped.primaryTargetCollection, "payment_authorizations");
  assert.equal(mapped.primaryTargetId, "auth_123");
  assert.equal(mapped.secondaryTargetCollection, "session_payment_intents");
  assert.equal(mapped.secondaryTargetId, "payment_123");
  assert.equal(mapped.resultingStatus, "AUTHORIZED");
  assert.equal(mapped.currency, "ZAR");
});

test("capture mapper requires authorization-backed capture targets", () => {
  const event = normalizePaymentEventInput({
    provider: "MOCK_PAYSTACK",
    externalEventId: "evt_cap_123",
    eventType: "capture_succeeded",
    paymentRail: "TUTORING",
    authorizationId: "auth_123",
    captureReference: "cap_ref_123",
    amountZar: 24,
    currency: "ZAR",
  });
  const mapped = mapCaptureSucceededEvent(event);

  assert.equal(mapped.primaryTargetCollection, "payment_captures");
  assert.equal(mapped.primaryTargetId, "cap_ref_123");
  assert.equal(mapped.secondaryTargetCollection, "payment_authorizations");
  assert.equal(mapped.secondaryTargetId, "auth_123");
  assert.equal(mapped.resultingStatus, "CAPTURED");
});

test("reserve failure mapper targets a failed top-up authorization", () => {
  const event = normalizePaymentEventInput({
    provider: "MOCK_PAYSTACK",
    externalEventId: "evt_reserve_failed_123",
    eventType: "authorization_reserve_failed",
    paymentRail: "TUTORING",
    authorizationId: "auth_topup_123",
    bookingId: "booking_123",
    paymentSessionId: "payment_123",
    sessionId: "session_123",
    amountZar: 24,
    currency: "ZAR",
  });
  const mapped = mapAuthorizationReserveFailedEvent(event);

  assert.equal(mapped.primaryTargetCollection, "payment_authorizations");
  assert.equal(mapped.primaryTargetId, "auth_topup_123");
  assert.equal(mapped.secondaryTargetCollection, "tutoring_sessions");
  assert.equal(mapped.secondaryTargetId, "session_123");
  assert.equal(mapped.resultingStatus, "FAILED");
});

test("transfer failure mapper targets payout records", () => {
  const event = normalizePaymentEventInput({
    provider: "MOCK_PAYSTACK",
    externalEventId: "evt_trf_123",
    eventType: "transfer_failed",
    paymentRail: "TUTORING",
    payoutId: "payout_123",
    payoutBatchId: "batch_123",
    amountZar: 250,
    currency: "ZAR",
  });
  const mapped = mapTransferFailedEvent(event);

  assert.equal(mapped.primaryTargetCollection, "tutor_payouts");
  assert.equal(mapped.primaryTargetId, "payout_123");
  assert.equal(mapped.secondaryTargetCollection, "tutor_payout_batches");
  assert.equal(mapped.secondaryTargetId, "batch_123");
  assert.equal(mapped.resultingStatus, "FAILED");
});

test("normalization rejects non-tutoring payment rails to preserve seshcredits separation", () => {
  assert.throws(
    () => normalizePaymentEventInput({
      provider: "MOCK_PAYSTACK",
      externalEventId: "evt_bad_123",
      eventType: "capture_succeeded",
      paymentRail: "SESHCREDITS",
      authorizationId: "auth_123",
      captureId: "cap_123",
      amountZar: 24,
      currency: "ZAR",
    }),
    (error: unknown) =>
      error instanceof Error &&
      error.message.includes("Tutoring events must stay separate from SeshCredits"),
  );
});
