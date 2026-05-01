import test, {after} from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";

if (admin.apps.length === 0) {
  admin.initializeApp();
}

import {resolveTutoringBookingQuote} from "../tutorBookings.js";
import {
  buildBookingSchemaFields,
  buildGuestTutoringCustomerDoc,
  buildPaymentSessionSchemaFields,
} from "../tutoringFirestoreSchema.js";
import {getMockPaystackProvider} from "../payments/mockPaystack.js";
import {
  buildMockPaystackWebhookPayload,
  mapMockPaystackWebhookPayloadToPaymentEvent,
} from "../mockPaystackWebhookSimulator.js";
import {evaluateSessionStartReadiness} from "../tutoringSessionReadiness.js";
import {
  computeProtectedTimeProgress,
  deriveProtectedStateAfterReserveOutcome,
} from "../tutorBillingTick.js";
import {
  buildLowFundsNotificationPayload,
  shouldForceEndForProtectionExhaustion,
} from "../tutoringLowFunds.js";
import {
  assertSessionTransition,
  TutoringSessionState,
  TutoringTransitionActor,
} from "../tutoringStateMachine.js";
import {
  buildTutoringSettlementArtifacts,
  deriveDisputeHoldMutation,
} from "../tutoringSettlement.js";
import {shouldIncludeTutorPayableInBatch} from "../tutorPayouts.js";
import {
  deriveTutorPayoutBlockedReason,
  nextTutorPayoutMondayDateKey,
} from "../tutorPayoutDashboard.js";
import {isVerifiedTutorPayoutProfile} from "../tutorPayoutProfileState.js";
import {resolveTutoringRatingSubmission} from "../tutorRatings.js";

const provider = getMockPaystackProvider();

function fixedTimestamp(seconds: number) {
  return admin.firestore.Timestamp.fromMillis(seconds * 1000);
}

after(async () => {
  await Promise.all(
    admin.apps
      .filter((app): app is admin.app.App => app !== null)
      .map((app) => app.delete())
  );
});

test("authenticated student first tutoring booking uses mock provider and mock webhook simulator", async () => {
  const quote = resolveTutoringBookingQuote({
    authIsAnonymous: false,
    studentId: "student_123",
    tutorId: "tutor_123",
    requestType: "INSTANT",
    tutorRatePerMinZar: 10,
    paymentProfileType: "saved_student_card",
    studentAccessTier: "student",
    studentAccountType: "student",
    now: new Date("2026-04-01T10:00:00.000Z"),
  });

  const providerResult = await provider.initializeFirstPreauth({
    bookingId: "booking_123",
    paymentSessionId: "payment_123",
    amountZar: quote.initialBufferAmountZar,
    currency: "ZAR",
    customerEmail: "student@example.com",
    idempotencyKey: "integration_first_booking_auth",
    environment: "test",
  });
  const webhookPayload = await buildMockPaystackWebhookPayload({
    scenario: "initial_preauthorization_success",
    seed: "first_booking",
    bookingId: "booking_123",
    paymentSessionId: "payment_123",
    authorizationId: "auth_123",
    amountZar: quote.initialBufferAmountZar,
  });
  const paymentEvent = mapMockPaystackWebhookPayloadToPaymentEvent(webhookPayload);
  const bookingDoc = buildBookingSchemaFields("booking_123", {
    requestId: "booking_123",
    tutorSessionId: "booking_123",
    paymentIntentId: "payment_123",
    studentId: "student_123",
    tutorId: "tutor_123",
    status: "pending",
    paymentStatus: quote.paymentStatus,
    requestType: quote.requestType,
    paymentMode: quote.paymentMode,
    paymentSystem: "TUTORING",
    tutoringPaymentRail: "TUTORING",
    sessionOpenEnded: true,
    noFreeLearningPastAuthorizedMinutes: true,
    scheduledAt: admin.firestore.Timestamp.fromDate(quote.scheduledAt),
    tutorRatePerMinZar: quote.tutorRatePerMinZar,
    studentRatePerMinZar: quote.studentRatePerMinZar,
    platformFeePerMinute: quote.platformFeePerMinute,
    pricingSnapshot: {
      tutorBaseRateZar: quote.tutorRatePerMinZar,
      platformFeeZar: quote.platformFeePerMinute,
      studentRateZar: quote.studentRatePerMinZar,
    },
  });
  const paymentSessionDoc = buildPaymentSessionSchemaFields("payment_123", {
    requestId: "booking_123",
    tutorSessionId: "booking_123",
    studentId: "student_123",
    tutorId: "tutor_123",
    status: quote.paymentSessionStatus,
    paymentMode: quote.paymentMode,
    tutoringPaymentRail: "TUTORING",
    sessionOpenEnded: true,
    noFreeLearningPastAuthorizedMinutes: true,
    tutorRatePerMinZar: quote.tutorRatePerMinZar,
    studentRatePerMinZar: quote.studentRatePerMinZar,
    platformFeePerMinute: quote.platformFeePerMinute,
    pricingSnapshot: {
      tutorBaseRateZar: quote.tutorRatePerMinZar,
      platformFeeZar: quote.platformFeePerMinute,
      studentRateZar: quote.studentRatePerMinZar,
    },
  });

  assert.equal(quote.payerType, "student");
  assert.equal(quote.studentRatePerMinZar, 12);
  assert.equal(quote.initialBufferAmountZar, 240);
  assert.equal(providerResult.status, "authorized");
  assert.equal(paymentEvent.eventType, "authorization_created");
  assert.equal(bookingDoc.bookingState, "awaiting_payment_authorization");
  assert.equal(paymentSessionDoc.paymentSessionStatus, "booking_created");
});

test("guest tutoring booking uses a lightweight guest customer identity", () => {
  const quote = resolveTutoringBookingQuote({
    authIsAnonymous: true,
    studentId: "guest_123",
    tutorId: "tutor_123",
    requestType: "IN_5",
    tutorRatePerMinZar: 15,
    paymentProfileType: "temporary_instant_tutor_card",
    studentAccessTier: "instant_tutor",
    studentAccountType: "instant_tutor",
    now: new Date("2026-04-01T10:00:00.000Z"),
  });
  const guestDoc = buildGuestTutoringCustomerDoc({
    customerId: "guest_123",
    userData: {
      firstName: "Nadia",
      email: "nadia@example.com",
      phone: "+27123456789",
      accountType: "instant_tutor",
      accessTier: "instant_tutor",
    },
    bookingData: {
      studentId: "guest_123",
      payerType: quote.payerType,
      guestTutoringMode: quote.guestTutoringMode,
    },
    tutoringBookingCount: 1,
    lastBookingId: "booking_guest_123",
    lastUsedAt: fixedTimestamp(1),
  });

  assert.equal(quote.payerType, "guest");
  assert.equal(quote.guestTutoringMode, true);
  assert.equal(quote.paymentProfileType, "temporary_instant_tutor_card");
  assert.equal(guestDoc.guestId, "guest_123");
  assert.equal(guestDoc.isGuest, true);
  assert.equal(guestDoc.status, "active");
});

test("session starts only after protected time exists", () => {
  const bookingData = {
    bookingState: "payment_authorized",
    paymentStatus: "PAYMENT_AUTHORIZED",
    authorizationStatus: "PAYMENT_AUTHORIZED",
  };
  const paymentIntentWithoutProtection = {
    paymentAuthorizationStatus: "PAYMENT_AUTHORIZED",
    protectedMinutesPurchased: 0,
    protectedMinutesRemaining: 0,
    consumedMinutes: 0,
  };
  const authorizationData = {
    status: "AUTHORIZED",
  };

  const blocked = evaluateSessionStartReadiness({
    bookingData,
    paymentIntentData: paymentIntentWithoutProtection,
    authorizationData,
  });
  const allowed = evaluateSessionStartReadiness({
    bookingData,
    paymentIntentData: {
      ...paymentIntentWithoutProtection,
      protectedMinutesPurchased: 20,
      protectedMinutesRemaining: 20,
    },
    authorizationData,
  });

  assert.equal(blocked.allowed, false);
  assert.equal(blocked.errorCode, "START_SESSION_PROTECTION_REQUIRED");
  assert.equal(allowed.allowed, true);
  assert.equal(allowed.errorCode, null);
});

test("protection decreases correctly over time", () => {
  const progress = computeProtectedTimeProgress({
    sessionStartAt: new Date("2026-04-01T10:00:00.000Z"),
    now: new Date("2026-04-01T10:01:01.000Z"),
    protectedMinutesPurchased: 20,
  });

  assert.equal(progress.elapsedMinutes, 2);
  assert.equal(progress.billableMinutes, 2);
  assert.equal(progress.protectedMinutesRemaining, 18);
  assert.equal(progress.tickId, "minute_2");
});

test("reserve refill success keeps session alive", async () => {
  const reserveResult = await provider.reservePreauth({
    bookingId: "booking_123",
    paymentSessionId: "payment_123",
    sessionId: "session_123",
    authorizationCode: "AUTH_existing",
    authorizationReference: "PAUTH_existing",
    amountZar: 240,
    currency: "ZAR",
    idempotencyKey: "integration_reserve_success",
    environment: "test",
  });
  const payload = await buildMockPaystackWebhookPayload({
    scenario: "reserve_preauthorization_success",
    seed: "reserve_success",
    bookingId: "booking_123",
    paymentSessionId: "payment_123",
    sessionId: "session_123",
    authorizationId: "auth_topup_123",
    amountZar: 240,
  });
  const event = mapMockPaystackWebhookPayloadToPaymentEvent(payload);
  const nextState = deriveProtectedStateAfterReserveOutcome({
    currentState: {
      protectedMinutesPurchased: 20,
      protectedMinutesRemaining: 4,
      consumedMinutes: 16,
      refillAttemptCount: 0,
      lowFundsAt: null,
    },
    outcome: "AUTHORIZED",
  });

  assert.equal(reserveResult.status, "reserved");
  assert.equal(event.eventType, "authorization_reserved");
  assert.equal(nextState.protectedMinutesPurchased, 40);
  assert.equal(nextState.protectedMinutesRemaining, 24);
  assert.equal(nextState.lowFundsAt, null);
});

test("reserve refill failure triggers low_funds", async () => {
  const reserveResult = await provider.reservePreauth({
    bookingId: "booking_123",
    paymentSessionId: "payment_123",
    sessionId: "session_123",
    authorizationCode: "AUTH_existing",
    authorizationReference: "PAUTH_existing",
    amountZar: 240,
    currency: "ZAR",
    idempotencyKey: "integration_reserve_fail",
    reason: "reserve_fail",
    environment: "test",
  });
  const payload = await buildMockPaystackWebhookPayload({
    scenario: "reserve_preauthorization_failure",
    seed: "reserve_failure",
    bookingId: "booking_123",
    paymentSessionId: "payment_123",
    sessionId: "session_123",
    authorizationId: "auth_topup_123",
    amountZar: 240,
    reason: "insufficient_available_funds",
  });
  const event = mapMockPaystackWebhookPayloadToPaymentEvent(payload);
  const lowFundsAt = new Date("2026-04-01T10:16:00.000Z");
  const nextState = deriveProtectedStateAfterReserveOutcome({
    currentState: {
      protectedMinutesPurchased: 20,
      protectedMinutesRemaining: 4,
      consumedMinutes: 16,
      refillAttemptCount: 0,
      lowFundsAt: null,
    },
    outcome: "FAILED",
  });
  const notification = buildLowFundsNotificationPayload({
    now: lowFundsAt,
    sessionStartAt: new Date("2026-04-01T10:00:00.000Z"),
    protectedMinutesPurchased: nextState.protectedMinutesPurchased,
    protectedMinutesRemaining: nextState.protectedMinutesRemaining,
    consumedMinutes: nextState.consumedMinutes,
    refillAttemptCount: nextState.refillAttemptCount,
    lowFundsAt,
    state: "low_funds",
    reason: "reserve_refill_failed",
  });

  assertSessionTransition(
    TutoringSessionState.ACTIVE,
    TutoringSessionState.LOW_FUNDS,
    {actor: TutoringTransitionActor.BILLING}
  );
  assert.equal(reserveResult.status, "failed");
  assert.equal(event.eventType, "authorization_reserve_failed");
  assert.equal(nextState.protectedMinutesRemaining, 4);
  assert.equal(nextState.refillAttemptCount, 1);
  assert.equal(notification.state, "low_funds");
  assert.equal(notification.reason, "reserve_refill_failed");
  assert.equal(notification.roomTerminationRequired, true);
});

test("room ends exactly when protected time runs out", () => {
  const sessionStartAt = new Date("2026-04-01T10:00:00.000Z");
  const lowFundsAt = new Date("2026-04-01T10:16:00.000Z");

  assert.equal(
    shouldForceEndForProtectionExhaustion({
      now: new Date("2026-04-01T10:19:59.000Z"),
      sessionStartAt,
      protectedMinutesPurchased: 20,
      protectedMinutesRemaining: 1,
      lowFundsAt,
    }),
    false,
  );
  assert.equal(
    shouldForceEndForProtectionExhaustion({
      now: new Date("2026-04-01T10:20:00.000Z"),
      sessionStartAt,
      protectedMinutesPurchased: 20,
      protectedMinutesRemaining: 0,
      lowFundsAt,
    }),
    true,
  );
});

test("normal session end creates settlement and tutor payable from captured funds", async () => {
  const captureResult = await provider.capturePreauth({
    bookingId: "booking_123",
    paymentSessionId: "payment_123",
    sessionId: "session_123",
    authorizationReference: "PAUTH_existing",
    amountZar: 240,
    currency: "ZAR",
    idempotencyKey: "integration_capture_success",
    environment: "test",
  });
  const payload = await buildMockPaystackWebhookPayload({
    scenario: "capture_success",
    seed: "capture_success",
    bookingId: "booking_123",
    paymentSessionId: "payment_123",
    sessionId: "session_123",
    authorizationId: "auth_123",
    captureId: "capture_123",
    amountZar: 240,
  });
  const event = mapMockPaystackWebhookPayloadToPaymentEvent(payload);
  const artifacts = buildTutoringSettlementArtifacts({
    settlementId: "session_123",
    sessionId: "session_123",
    bookingId: "booking_123",
    paymentIntentId: "payment_123",
    studentId: "student_123",
    tutorId: "tutor_123",
    status: "COMPLETED",
    billableMinutes: 20,
    finalAmountDueZar: 240,
    capturedAmountZar: 240,
    ratingRequired: true,
  });

  assert.equal(captureResult.status, "captured");
  assert.equal(event.eventType, "capture_succeeded");
  assert.equal(artifacts.metrics.tutorEarningZar, 200);
  assert.equal(artifacts.metrics.platformFeeZar, 40);
  assert.equal(artifacts.settlementBase.capturedFundsOnly, true);
  assert.equal(artifacts.tutorPayableBase.availableAmountZar, 200);
  assert.equal(artifacts.tutorPayableBase.payableStatus, "available");
});

test("disputed session freezes tutor payable", () => {
  const hold = deriveDisputeHoldMutation({
    tutorEarningZar: 200,
    payoutReservedAmountZar: 0,
    payoutPaidAmountZar: 0,
    disputeHeldAmountZar: 0,
    holdAmountZar: 200,
  });

  assert.equal(hold.appliedHoldAmountZar, 200);
  assert.equal(hold.disputeHeldAmountZar, 200);
  assert.equal(hold.availableForPayoutZar, 0);
  assert.equal(hold.payoutEligibilityStatus, "HELD");
});

test("Monday payout batch includes only eligible tutors", () => {
  const mondayKey = nextTutorPayoutMondayDateKey(
    new Date("2026-04-01T10:00:00.000Z")
  );
  const eligiblePayable = {
    payableId: "payable_1",
    settlementId: "settlement_1",
    tutorId: "tutor_eligible",
    availableAmountZar: 200,
    reservedAmountZar: 0,
    paidAmountZar: 0,
    blockedAmountZar: 0,
    grossTutorEarningZar: 200,
    payableStatus: "available",
    payoutEligibilityStatus: "ELIGIBLE",
    payoutState: "UNPAID",
    disputeStatus: "none",
    scheduledPayoutDateKey: mondayKey,
    lastPayoutBatchId: null,
    lastPayoutRecordId: null,
    settledAt: fixedTimestamp(1),
  };
  const disputedPayable = {
    ...eligiblePayable,
    payableId: "payable_2",
    tutorId: "tutor_disputed",
    blockedAmountZar: 50,
    payoutEligibilityStatus: "HELD",
    payoutState: "HELD",
    disputeStatus: "open",
  };

  assert.equal(
    shouldIncludeTutorPayableInBatch(eligiblePayable, {
      allowRebatchedPayables: false,
      batchDateKey: mondayKey,
    }),
    true,
  );
  assert.equal(
    shouldIncludeTutorPayableInBatch(disputedPayable, {
      allowRebatchedPayables: false,
      batchDateKey: mondayKey,
    }),
    false,
  );
});

test("blocked tutor payout profile excludes tutor from payout batching eligibility", () => {
  const userData = {
    accountType: "tutor",
    accessTier: "tutor",
    tutorApplicationStatus: "approved",
    tutoringEligibilityStatus: "eligible",
    payoutOnboardingStatus: "verified",
    adminApproval: true,
    tutorStatus: "approved",
  };
  const blockedProfile = {
    payoutProfileId: "profile_123",
    tutorId: "tutor_123",
    provider: "MOCK_PAYSTACK",
    accountHolderName: "Tutor Example",
    bankCode: "632005",
    bankName: "ABSA",
    accountNumberMasked: "******1234",
    payoutEnabled: false,
    verificationStatus: "blocked",
    status: "DISABLED",
    payoutBlockedReason: "compliance_hold",
    isDefault: true,
    recipientCode: null,
  };
  const blockedReason = deriveTutorPayoutBlockedReason({
    userData,
    payoutProfile: blockedProfile,
  });

  assert.equal(isVerifiedTutorPayoutProfile("tutor_123", blockedProfile), false);
  assert.equal(blockedReason.code, "payout_profile_blocked");
  assert.equal(blockedReason.message, "compliance_hold");
});

test("guest can rate after session end", () => {
  const resolved = resolveTutoringRatingSubmission({
    requesterId: "guest_123",
    bookingId: "booking_123",
    bookingData: {
      paymentIntentId: "payment_123",
      studentId: "guest_123",
      tutorId: "tutor_123",
      tutorName: "Tutor Z",
      studentName: "Guest Learner",
      subject: "Maths",
      topic: "Algebra",
      bookingState: "ended_insufficient_funds",
      reviewStatus: "pending",
      reviewEligible: true,
      payerType: "guest",
    },
    paymentIntentData: {
      sessionTerminalState: "ended_insufficient_funds",
      reviewStatus: "pending",
      reviewEligible: true,
    },
    guestCustomerData: {
      guestId: "guest_123",
      firstName: "Nadia",
      email: "nadia@example.com",
      phone: "+27123456789",
      status: "active",
    },
  });

  assert.equal(resolved.reviewId, "booking_123");
  assert.equal(resolved.payerType, "guest");
  assert.equal(resolved.raterType, "guest");
  assert.equal(resolved.guestId, "guest_123");
});
