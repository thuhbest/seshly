import * as admin from "firebase-admin";
import {
  deriveTutoringBookingState,
  deriveTutoringSessionState,
} from "./tutoringStateMachine";
import {
  deriveTutorPayoutVerificationStatus,
  findSupportedTutorPayoutBank,
  isVerifiedTutorPayoutProfile,
  toTrimmedString as payoutTrimmedString,
} from "./tutorPayoutProfileState";

export const TUTORING_PAYMENT_SCHEMA_VERSION = 2;
export const TUTORING_PAYMENT_SCHEMA_DOMAIN = "tutoring_payment";
export const TUTORING_PAYMENT_TIME_ZONE = "Africa/Johannesburg";
export const TUTORING_PAYOUT_LOCAL_TIME = "Monday 06:00";

export const TUTORING_LOGICAL_COLLECTIONS = {
  bookings: "bookings",
  sessions: "sessions",
  paymentSessions: "payment_sessions",
  paymentAuthorizations: "payment_authorizations",
  captureRecords: "capture_records",
  settlementRecords: "settlement_records",
  tutorPayables: "tutor_payables",
  payoutBatches: "payout_batches",
  payoutRecords: "payout_records",
  tutorPayoutProfiles: "tutor_payout_profiles",
  tutorPayoutDashboards: "tutor_payout_dashboards",
  guestTutoringCustomers: "guest_tutoring_customers",
  disputes: "disputes",
  ratings: "ratings",
} as const;

export const TUTORING_PHYSICAL_COLLECTIONS = {
  bookings: "tutor_requests",
  sessions: "tutoring_sessions",
  paymentSessions: "session_payment_intents",
  paymentAuthorizations: "payment_authorizations",
  captureRecords: "payment_captures",
  settlementRecords: "tutor_session_settlements",
  tutorPayables: "tutor_payables",
  payoutBatches: "tutor_payout_batches",
  payoutRecords: "tutor_payouts",
  tutorPayoutProfiles: "tutor_payout_accounts",
  tutorPayoutDashboards: "tutor_payout_dashboards",
  guestTutoringCustomers: "guest_tutoring_customers",
  disputes: "disputes",
  ratings: "tutor_session_reviews",
} as const;

export type TutoringLogicalCollection =
  typeof TUTORING_LOGICAL_COLLECTIONS[keyof typeof TUTORING_LOGICAL_COLLECTIONS];

function toTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function nullableTrimmedString(value: unknown): string | null {
  const trimmed = toTrimmedString(value);
  return trimmed || null;
}

function deriveFirstName(data: Record<string, unknown>): string {
  const explicit = toTrimmedString(data.firstName);
  if (explicit) return explicit;

  const fullName = toTrimmedString(data.fullName || data.displayName);
  if (!fullName) return "Guest";
  return fullName.split(/\s+/)[0] || "Guest";
}

function toMoney(value: number): number {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

function asMoney(value: unknown, fallback = 0): number {
  if (typeof value === "number" && Number.isFinite(value)) {
    return toMoney(value);
  }
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return toMoney(parsed);
    }
  }
  return fallback;
}

function asWholeMinutes(value: unknown, fallback = 0): number {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.max(0, Math.floor(value));
  }
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return Math.max(0, Math.floor(parsed));
    }
  }
  return fallback;
}

function toJSONObject(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value) ?
    value as Record<string, unknown> :
    {};
}

function timestampToDate(value: unknown): Date | null {
  if (value instanceof admin.firestore.Timestamp) {
    return value.toDate();
  }
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return value;
  }
  if (typeof value === "string" || typeof value === "number") {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  return null;
}

function isGuestTutoringMode(data: Record<string, unknown>): boolean {
  const accessTier = toTrimmedString(data.studentAccessTier || data.accessTier)
    .toLowerCase();
  const accountType = toTrimmedString(data.studentAccountType || data.accountType)
    .toLowerCase();
  return data.guestTutoringMode === true ||
    data.isGuest === true ||
    data.instantTutorAccess === true ||
    accessTier === "instant_tutor" ||
    accountType === "instant_tutor";
}

function baseSchemaFields(
  logicalCollection: TutoringLogicalCollection,
  physicalCollection: string
): Record<string, unknown> {
  return {
    tutoringSchemaVersion: TUTORING_PAYMENT_SCHEMA_VERSION,
    tutoringSchemaDomain: TUTORING_PAYMENT_SCHEMA_DOMAIN,
    tutoringSchemaCollection: logicalCollection,
    tutoringSchemaPhysicalCollection: physicalCollection,
    tutoringSchemaNormalizedAt: admin.firestore.FieldValue.serverTimestamp(),
    tutoringPaymentRail: "TUTORING",
  };
}

function resolvePricingSnapshot(data: Record<string, unknown>): Record<string, unknown> {
  const explicitSnapshot = toJSONObject(data.pricingSnapshot);
  if (Object.keys(explicitSnapshot).length > 0) {
    return {
      tutorBaseRateZar: asMoney(
        explicitSnapshot.tutorBaseRateZar ?? explicitSnapshot.tutorRatePerMinute,
        0
      ),
      platformFeeZar: asMoney(
        explicitSnapshot.platformFeeZar ?? explicitSnapshot.platformFeePerMinute,
        0
      ),
      studentRateZar: asMoney(
        explicitSnapshot.studentRateZar ?? explicitSnapshot.totalRatePerMinute,
        0
      ),
    };
  }

  const pricing = toJSONObject(data.pricing);
  return {
    tutorBaseRateZar: asMoney(
      data.tutorRatePerMinute ?? pricing.tutorRatePerMinute,
      0
    ),
    platformFeeZar: asMoney(
      data.platformFeePerMinute ?? pricing.platformFeePerMinute,
      0
    ),
    studentRateZar: asMoney(
      data.totalRatePerMinute ?? pricing.totalRatePerMinute,
      0
    ),
  };
}

function resolveAuthorizationBufferMinutes(data: Record<string, unknown>): number {
  const explicit = Number(
    data.authorizationBufferMinutes ??
      data.estimatedHoldMinutes ??
      data.estimatedSessionMinutes ??
      0
  );
  if (Number.isFinite(explicit) && explicit > 0) {
    return Math.max(1, Math.round(explicit));
  }

  const holdAmountZar = asMoney(
    data.initialBufferAmountZar ?? data.holdAmountZar,
    0
  );
  const pricing = resolvePricingSnapshot(data);
  const studentRate = asMoney(pricing.studentRateZar, 0);
  if (holdAmountZar > 0 && studentRate > 0) {
    return Math.max(1, Math.round(holdAmountZar / studentRate));
  }

  return 20;
}

function formatDateKey(date: Date, timeZone = TUTORING_PAYMENT_TIME_ZONE): string {
  return new Intl.DateTimeFormat("sv-SE", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

function weekdayShort(date: Date, timeZone = TUTORING_PAYMENT_TIME_ZONE): string {
  return new Intl.DateTimeFormat("en-US", {
    timeZone,
    weekday: "short",
  }).format(date);
}

function nextMondayDateKey(
  input: Date | null,
  timeZone = TUTORING_PAYMENT_TIME_ZONE
): string | null {
  if (!input) return null;
  const cursor = new Date(input.getTime());
  for (let offset = 0; offset < 8; offset += 1) {
    if (weekdayShort(cursor, timeZone) === "Mon") {
      return formatDateKey(cursor, timeZone);
    }
    cursor.setUTCDate(cursor.getUTCDate() + 1);
  }
  return formatDateKey(input, timeZone);
}

function resolveSettlementScheduleFields(
  data: Record<string, unknown>
): {payoutWeekKey: string | null; scheduledPayoutDateKey: string | null} {
  const settledAt =
    timestampToDate(data.settledAt) ??
    timestampToDate(data.createdAt) ??
    null;
  const scheduledPayoutDateKey = nextMondayDateKey(settledAt);
  return {
    payoutWeekKey: toTrimmedString(data.payoutWeekKey) || scheduledPayoutDateKey,
    scheduledPayoutDateKey,
  };
}

function deriveTutorPayableStatus(data: Record<string, unknown>): string {
  const eligibility = toTrimmedString(data.payoutEligibilityStatus).toUpperCase();
  const payoutState = toTrimmedString(data.payoutState).toUpperCase();
  const availableAmountZar = asMoney(data.availableForPayoutZar, 0);

  if (eligibility === "HELD" || payoutState === "HELD") {
    return "blocked";
  }
  if (eligibility === "INELIGIBLE") {
    return "ineligible";
  }
  if (payoutState === "PAID") {
    return "paid";
  }
  if (payoutState === "PARTIALLY_PAID") {
    return "partially_paid";
  }
  if (payoutState === "RESERVED") {
    return "reserved";
  }
  if (availableAmountZar <= 0) {
    return "settled_zero";
  }
  return "available";
}

function deriveAvailableTutorPayoutAmount(data: Record<string, unknown>): number {
  const explicit = asMoney(data.availableForPayoutZar ?? data.availableAmountZar, -1);
  if (explicit >= 0) {
    return explicit;
  }
  return toMoney(
    Math.max(
      0,
      asMoney(data.tutorEarningZar ?? data.grossTutorEarningZar, 0) -
        asMoney(data.payoutReservedAmountZar ?? data.reservedAmountZar, 0) -
        asMoney(data.payoutPaidAmountZar ?? data.paidAmountZar, 0) -
        asMoney(data.disputeHeldAmountZar ?? data.blockedAmountZar, 0)
    )
  );
}

export function buildBookingSchemaFields(
  bookingId: string,
  data: Record<string, unknown>
): Record<string, unknown> {
  const pricingSnapshot = resolvePricingSnapshot(data);
  const guestTutoringMode = isGuestTutoringMode(data);

  return {
    ...baseSchemaFields(
      TUTORING_LOGICAL_COLLECTIONS.bookings,
      TUTORING_PHYSICAL_COLLECTIONS.bookings
    ),
    bookingId,
    sessionId: toTrimmedString(data.tutorSessionId) || bookingId,
    paymentSessionId: toTrimmedString(data.paymentIntentId) || bookingId,
    bookingStatus: toTrimmedString(data.status) || "pending",
    bookingState: deriveTutoringBookingState(data),
    scheduledStartAt: data.scheduledAt ?? null,
    sessionOpenEnded: data.sessionOpenEnded !== false,
    protectedPrepaidMinutesOnly:
      data.protectedPrepaidMinutesOnly === true ||
      data.noFreeLearningPastAuthorizedMinutes === true ||
      data.protectedTutoringMinutesOnly === true,
    guestTutoringMode,
    guestTutoringCustomerId: guestTutoringMode ?
      (toTrimmedString(data.studentId) || null) :
      null,
    studentRatePerMinZar: asMoney(pricingSnapshot.studentRateZar, 0),
    tutorRatePerMinZar: asMoney(pricingSnapshot.tutorBaseRateZar, 0),
    platformFeePerMinZar: asMoney(pricingSnapshot.platformFeeZar, 0),
    protectedMinutesPurchased: asWholeMinutes(data.protectedMinutesPurchased, 0),
    protectedMinutesRemaining: asWholeMinutes(data.protectedMinutesRemaining, 0),
    consumedMinutes: asWholeMinutes(data.consumedMinutes, 0),
    refillAttemptCount: asWholeMinutes(data.refillAttemptCount, 0),
    lowFundsAt: data.lowFundsAt ?? null,
    pricingSnapshot,
    authorizationBufferMinutes: resolveAuthorizationBufferMinutes(data),
  };
}

export function buildPaymentSessionSchemaFields(
  paymentSessionId: string,
  data: Record<string, unknown>
): Record<string, unknown> {
  const pricingSnapshot = resolvePricingSnapshot(data);
  const guestTutoringMode = isGuestTutoringMode(data);

  return {
    ...baseSchemaFields(
      TUTORING_LOGICAL_COLLECTIONS.paymentSessions,
      TUTORING_PHYSICAL_COLLECTIONS.paymentSessions
    ),
    paymentSessionId,
    bookingId: toTrimmedString(data.requestId) || paymentSessionId,
    sessionId: toTrimmedString(data.tutorSessionId) ||
      toTrimmedString(data.requestId) ||
      paymentSessionId,
    paymentSessionStatus: toTrimmedString(data.status) || "booking_created",
    guestTutoringMode,
    guestTutoringCustomerId: guestTutoringMode ?
      (toTrimmedString(data.studentId) || null) :
      null,
    studentRatePerMinZar: asMoney(pricingSnapshot.studentRateZar, 0),
    tutorRatePerMinZar: asMoney(pricingSnapshot.tutorBaseRateZar, 0),
    platformFeePerMinZar: asMoney(pricingSnapshot.platformFeeZar, 0),
    pricingSnapshot,
    authorizationBufferMinutes: resolveAuthorizationBufferMinutes(data),
    protectedPrepaidMinutesOnly:
      data.protectedPrepaidMinutesOnly === true ||
      data.noFreeLearningPastAuthorizedMinutes === true ||
      data.protectedTutoringMinutesOnly === true,
    latestAuthorizationId:
      toTrimmedString(data.latestAuthorizationId) ||
      toTrimmedString(data.paymentAuthorizationId) ||
      null,
    latestCaptureId: toTrimmedString(data.providerCaptureId) || null,
    latestReversalId: toTrimmedString(data.lastReversalId) || null,
  };
}

export function buildSessionSchemaFields(
  sessionId: string,
  data: Record<string, unknown>
): Record<string, unknown> {
  const pricingSnapshot = resolvePricingSnapshot(data);
  const lowFundsAt = timestampToDate(data.lowFundsAt);
  const guestTutoringMode = isGuestTutoringMode(data);

  return {
    ...baseSchemaFields(
      TUTORING_LOGICAL_COLLECTIONS.sessions,
      TUTORING_PHYSICAL_COLLECTIONS.sessions
    ),
    sessionId,
    bookingId: toTrimmedString(data.bookingId) || sessionId,
    paymentSessionId: toTrimmedString(data.paymentIntentId) ||
      toTrimmedString(data.bookingId) ||
      sessionId,
    sessionStatus: toTrimmedString(data.status) || "SCHEDULED",
    sessionLifecycleState: deriveTutoringSessionState(data),
    sessionTerminalState: toTrimmedString(data.sessionTerminalState) || null,
    sessionOpenEnded: data.sessionOpenEnded !== false,
    guestTutoringMode,
    guestTutoringCustomerId: guestTutoringMode ?
      (toTrimmedString(data.studentId) || null) :
      null,
    protectedPrepaidMinutesOnly:
      data.protectedPrepaidMinutesOnly === true ||
      data.noFreeLearningPastAuthorizedMinutes === true ||
      data.protectedTutoringMinutesOnly === true,
    studentRatePerMinZar: asMoney(pricingSnapshot.studentRateZar, 0),
    tutorRatePerMinZar: asMoney(pricingSnapshot.tutorBaseRateZar, 0),
    platformFeePerMinZar: asMoney(pricingSnapshot.platformFeeZar, 0),
    protectedMinutesPurchased: asWholeMinutes(data.protectedMinutesPurchased, 0),
    protectedMinutesRemaining: asWholeMinutes(data.protectedMinutesRemaining, 0),
    consumedMinutes: asWholeMinutes(data.consumedMinutes, 0),
    refillAttemptCount: asWholeMinutes(data.refillAttemptCount, 0),
    lowFundsAt: data.lowFundsAt ?? null,
    pricingSnapshot,
    authorizationBufferMinutes: resolveAuthorizationBufferMinutes(data),
    lowFundsGraceEndsAt: lowFundsAt ?
      admin.firestore.Timestamp.fromDate(
        new Date(lowFundsAt.getTime() + 60 * 1000)
      ) :
      null,
  };
}

export function buildPaymentAuthorizationSchemaFields(
  authorizationId: string,
  data: Record<string, unknown>
): Record<string, unknown> {
  const amountZar = asMoney(data.amountZar, 0);
  const capturedAmountZar = asMoney(data.capturedAmountZar, 0);
  const pendingCaptureAmountZar = asMoney(data.pendingCaptureAmountZar, 0);
  const reversedAmountZar = asMoney(data.reversedAmountZar, 0);
  const pendingReversalAmountZar = asMoney(data.pendingReversalAmountZar, 0);

  return {
    ...baseSchemaFields(
      TUTORING_LOGICAL_COLLECTIONS.paymentAuthorizations,
      TUTORING_PHYSICAL_COLLECTIONS.paymentAuthorizations
    ),
    paymentAuthorizationId: authorizationId,
    bookingId: toTrimmedString(data.bookingId),
    sessionId: toTrimmedString(data.sessionId) ||
      toTrimmedString(data.bookingId) ||
      null,
    paymentSessionId: toTrimmedString(data.paymentIntentId) ||
      toTrimmedString(data.bookingId) ||
      null,
    authorizationStatus: toTrimmedString(data.status) || "INITIATING",
    authorizationKind: toTrimmedString(data.type) || "PREAUTH",
    authorizedAmountZar: amountZar,
    remainingAuthorizedAmountZar: toMoney(
      Math.max(
        0,
        amountZar -
          capturedAmountZar -
          pendingCaptureAmountZar -
          reversedAmountZar -
          pendingReversalAmountZar
      )
    ),
  };
}

export function buildCaptureSchemaFields(
  captureId: string,
  data: Record<string, unknown>
): Record<string, unknown> {
  return {
    ...baseSchemaFields(
      TUTORING_LOGICAL_COLLECTIONS.captureRecords,
      TUTORING_PHYSICAL_COLLECTIONS.captureRecords
    ),
    captureRecordId: captureId,
    bookingId: toTrimmedString(data.bookingId),
    sessionId: toTrimmedString(data.sessionId) ||
      toTrimmedString(data.bookingId) ||
      null,
    paymentSessionId: toTrimmedString(data.paymentIntentId) ||
      toTrimmedString(data.bookingId) ||
      null,
    paymentAuthorizationId: toTrimmedString(data.authorizationId),
    captureStatus: toTrimmedString(data.status) || "PENDING_PROVIDER",
    capturedAmountZar: asMoney(
      data.accountedAmountZar ?? data.amountZar,
      0
    ),
  };
}

export function buildSettlementSchemaFields(
  settlementId: string,
  data: Record<string, unknown>
): Record<string, unknown> {
  const schedule = resolveSettlementScheduleFields(data);
  const capturedAmountZar = asMoney(
    data.capturedAmountZar ?? data.capturedTotalZar,
    0
  );
  const pendingCaptureAmountZar = asMoney(
    data.pendingCaptureAmountZar ?? data.pendingCaptureTotalZar,
    0
  );
  const finalAmountDueZar = asMoney(data.finalAmountDueZar, 0);
  const disputeHeldAmountZar = asMoney(data.disputeHeldAmountZar, 0);
  const availableForPayoutZar = deriveAvailableTutorPayoutAmount(data);

  return {
    ...baseSchemaFields(
      TUTORING_LOGICAL_COLLECTIONS.settlementRecords,
      TUTORING_PHYSICAL_COLLECTIONS.settlementRecords
    ),
    settlementRecordId: settlementId,
    settlementId,
    bookingId: toTrimmedString(data.bookingId),
    sessionId: toTrimmedString(data.sessionId) || settlementId,
    paymentSessionId: toTrimmedString(data.paymentIntentId) ||
      toTrimmedString(data.bookingId) ||
      null,
    tutorPayableId: settlementId,
    settlementRecordStatus: toTrimmedString(data.settlementStatus) ||
      toTrimmedString(data.status) ||
      "completed",
    payoutFundingSource:
      toTrimmedString(data.payoutFundingSource) ||
      "captured_tutoring_funds_only",
    payableFundingSource:
      toTrimmedString(data.payableFundingSource) ||
      "captured_tutoring_funds_only",
    capturedFundsOnly: data.capturedFundsOnly !== false,
    settlementSource: toTrimmedString(data.settlementSource) || "mock_capture_events",
    capturedAmountZar,
    pendingCaptureAmountZar,
    uncapturedAmountZar: asMoney(
      data.uncapturedAmountZar,
      toMoney(Math.max(0, finalAmountDueZar - capturedAmountZar))
    ),
    tutorEarningZar: asMoney(data.tutorEarningZar, 0),
    platformFeeZar: asMoney(data.platformFeeZar, 0),
    availableForPayoutZar,
    disputeHeldAmountZar,
    payoutDisputedAmountZar: asMoney(data.payoutDisputedAmountZar, disputeHeldAmountZar),
    payoutExcludedUncapturedAmountZar: asMoney(
      data.payoutExcludedUncapturedAmountZar,
      toMoney(Math.max(0, finalAmountDueZar - capturedAmountZar))
    ),
    disputeStatus:
      toTrimmedString(data.disputeStatus) ||
      (disputeHeldAmountZar > 0 ? "open" : "none"),
    activeDisputeId: toTrimmedString(data.activeDisputeId) || null,
    payoutWeekKey: schedule.payoutWeekKey,
    scheduledPayoutDateKey: schedule.scheduledPayoutDateKey,
    scheduledPayoutLocalTime: TUTORING_PAYOUT_LOCAL_TIME,
  };
}

export function buildTutorPayableDoc(
  payableId: string,
  data: Record<string, unknown>
): Record<string, unknown> {
  const schedule = resolveSettlementScheduleFields(data);
  const blockedAmountZar = asMoney(data.disputeHeldAmountZar ?? data.blockedAmountZar, 0);
  const availableAmountZar = deriveAvailableTutorPayoutAmount(data);
  return {
    ...baseSchemaFields(
      TUTORING_LOGICAL_COLLECTIONS.tutorPayables,
      TUTORING_PHYSICAL_COLLECTIONS.tutorPayables
    ),
    payableId,
    settlementId: toTrimmedString(data.settlementId) || payableId,
    bookingId: toTrimmedString(data.bookingId),
    sessionId: toTrimmedString(data.sessionId) || payableId,
    paymentSessionId: toTrimmedString(data.paymentIntentId) ||
      toTrimmedString(data.bookingId) ||
      null,
    tutorId: toTrimmedString(data.tutorId),
    studentId: toTrimmedString(data.studentId),
    payableStatus: deriveTutorPayableStatus(data),
    payoutEligibilityStatus: toTrimmedString(data.payoutEligibilityStatus) ||
      "ELIGIBLE",
    payoutState: toTrimmedString(data.payoutState) || "UNPAID",
    grossTutorEarningZar: asMoney(data.tutorEarningZar, 0),
    capturedFundsOnly: data.capturedFundsOnly !== false,
    payableFundingSource:
      toTrimmedString(data.payableFundingSource) ||
      "captured_tutoring_funds_only",
    capturedAmountZar: asMoney(
      data.capturedAmountZar ?? data.capturedTotalZar,
      0
    ),
    uncapturedAmountZar: asMoney(data.uncapturedAmountZar, 0),
    availableAmountZar,
    reservedAmountZar: asMoney(data.payoutReservedAmountZar, 0),
    paidAmountZar: asMoney(data.payoutPaidAmountZar, 0),
    blockedAmountZar,
    currency: toTrimmedString(data.currency) || "ZAR",
    settledAt: data.settledAt ?? null,
    payableFrozenAt: data.payableFrozenAt ?? null,
    payableReleasedAt: data.payableReleasedAt ?? null,
    disputeStatus:
      toTrimmedString(data.disputeStatus) ||
      (blockedAmountZar > 0 ? "open" : "none"),
    payoutWeekKey: schedule.payoutWeekKey,
    scheduledPayoutDateKey: schedule.scheduledPayoutDateKey,
    scheduledPayoutLocalTime: TUTORING_PAYOUT_LOCAL_TIME,
    sourceCollection: TUTORING_PHYSICAL_COLLECTIONS.settlementRecords,
    lastPayoutBatchId: toTrimmedString(
      data.lastPayoutBatchId ?? data.lastDraftPayoutBatchId
    ) || null,
    lastPayoutRecordId: toTrimmedString(data.lastPayoutRecordId) || null,
    disputeId:
      blockedAmountZar > 0 ||
        toTrimmedString(data.payoutEligibilityStatus).toUpperCase() === "HELD" ?
        (
          toTrimmedString(data.activeDisputeId ?? data.disputeId) || payableId
        ) :
        null,
  };
}

export function buildPayoutBatchSchemaFields(
  batchId: string,
  data: Record<string, unknown>
): Record<string, unknown> {
  return {
    ...baseSchemaFields(
      TUTORING_LOGICAL_COLLECTIONS.payoutBatches,
      TUTORING_PHYSICAL_COLLECTIONS.payoutBatches
    ),
    payoutBatchId: batchId,
    payoutWeekKey: toTrimmedString(data.batchDateKey) || batchId,
    scheduledPayoutDateKey: toTrimmedString(data.batchDateKey) || null,
    scheduledPayoutLocalTime:
      toTrimmedString(data.scheduledForLocalTime) || TUTORING_PAYOUT_LOCAL_TIME,
    payoutBatchStatus: toTrimmedString(data.status) || "DRAFT",
    payoutBatchSource:
      toTrimmedString(data.payoutBatchSource) || "weekly_tutor_payables",
  };
}

export function buildPayoutRecordSchemaFields(
  payoutId: string,
  data: Record<string, unknown>
): Record<string, unknown> {
  const requestedAt = timestampToDate(data.requestedAt) ??
    timestampToDate(data.createdAt) ??
    null;
  return {
    ...baseSchemaFields(
      TUTORING_LOGICAL_COLLECTIONS.payoutRecords,
      TUTORING_PHYSICAL_COLLECTIONS.payoutRecords
    ),
    payoutRecordId: payoutId,
    payoutBatchId: toTrimmedString(data.payoutBatchId) || null,
    payoutProfileId: toTrimmedString(data.payoutAccountId) || null,
    payoutWeekKey:
      toTrimmedString(data.payoutWeekKey) ||
      nextMondayDateKey(requestedAt),
    payoutDateKey: requestedAt ? formatDateKey(requestedAt) : null,
    payoutRecordStatus: toTrimmedString(data.status) || "REQUESTED",
    payoutRecordType:
      toTrimmedString(data.payoutKind) || "manual_request",
  };
}

export function buildPayoutProfileSchemaFields(
  payoutProfileId: string,
  data: Record<string, unknown>
): Record<string, unknown> {
  const verificationStatus = deriveTutorPayoutVerificationStatus(data);
  const bankCode =
    toTrimmedString(data.bankCode) ||
    toTrimmedString(data.branchCode);
  const supportedBank = findSupportedTutorPayoutBank(bankCode);
  const bankName =
    toTrimmedString(data.bankName) ||
    supportedBank?.bankName ||
    "";
  const accountNumberMasked =
    toTrimmedString(data.accountNumberMasked) ||
    toTrimmedString(data.maskedAccountNumber);
  const recipientCode =
    payoutTrimmedString(data.recipientCode) ||
    payoutTrimmedString(data.providerBeneficiaryId) ||
    null;
  const payoutEnabled =
    data.payoutEnabled === true ||
    isVerifiedTutorPayoutProfile(toTrimmedString(data.tutorId), {
      ...data,
      bankName,
      bankCode,
      accountNumberMasked,
      recipientCode,
      verificationStatus,
    });
  const payoutBlockedReason =
    toTrimmedString(data.payoutBlockedReason) ||
    (
      verificationStatus === "verified" ?
        "" :
        verificationStatus === "blocked" ?
          "payout_profile_blocked" :
          "verification_required"
    );
  const payoutOnboardingStatus =
    verificationStatus === "verified" ? "verified" :
    verificationStatus === "blocked" ? "blocked" :
    verificationStatus === "not_started" ? "not_started" :
    "pending";
  const status =
    verificationStatus === "verified" ?
      "ACTIVE" :
      verificationStatus === "blocked" ?
        "DISABLED" :
        "PENDING_VERIFICATION";
  return {
    ...baseSchemaFields(
      TUTORING_LOGICAL_COLLECTIONS.tutorPayoutProfiles,
      TUTORING_PHYSICAL_COLLECTIONS.tutorPayoutProfiles
    ),
    payoutProfileId,
    tutorId: toTrimmedString(data.tutorId),
    payoutProfileStatus: status,
    provider: toTrimmedString(data.provider) || "MOCK_PAYSTACK",
    verificationStatus,
    bankCode: bankCode || null,
    bankName: bankName || null,
    accountNumberMasked: accountNumberMasked || null,
    accountHolderName: toTrimmedString(data.accountHolderName) || null,
    recipientCode,
    payoutEnabled,
    payoutBlockedReason: payoutBlockedReason || null,
    payoutOnboardingStatus,
    countryCode: toTrimmedString(data.countryCode) || "ZA",
    currency: toTrimmedString(data.currency) || "ZAR",
    status,
    maskedAccountNumber: accountNumberMasked || null,
    branchCode: bankCode || null,
    providerBeneficiaryId: recipientCode,
    providerExecutionReady: false,
  };
}

export function buildTutorPayoutDashboardDoc(
  tutorId: string,
  data: Record<string, unknown>
): Record<string, unknown> {
  const nextPayoutDateKey = toTrimmedString(data.nextPayoutDateKey) || null;
  return {
    ...baseSchemaFields(
      TUTORING_LOGICAL_COLLECTIONS.tutorPayoutDashboards,
      TUTORING_PHYSICAL_COLLECTIONS.tutorPayoutDashboards
    ),
    tutorId,
    currency: toTrimmedString(data.currency) || "ZAR",
    onboardingStatus:
      toTrimmedString(data.onboardingStatus) || "not_started",
    payoutEnabled: data.payoutEnabled === true,
    payoutMode: toTrimmedString(data.payoutMode) || "MANUAL",
    payoutProfileId: toTrimmedString(data.payoutProfileId) || null,
    payoutProfileVerificationStatus:
      toTrimmedString(data.payoutProfileVerificationStatus) || "not_started",
    payoutProfileBankName:
      toTrimmedString(data.payoutProfileBankName) || null,
    payoutProfileAccountNumberMasked:
      toTrimmedString(data.payoutProfileAccountNumberMasked) || null,
    availableNextPayoutAmountZar: asMoney(
      data.availableNextPayoutAmountZar,
      0
    ),
    pendingWeeklyAmountZar: asMoney(data.pendingWeeklyAmountZar, 0),
    blockedPayoutReasonCode:
      toTrimmedString(data.blockedPayoutReasonCode) || null,
    blockedPayoutReasonMessage:
      toTrimmedString(data.blockedPayoutReasonMessage) || null,
    nextPayoutDateKey,
    nextPayoutDisplayLabel:
      toTrimmedString(data.nextPayoutDisplayLabel) || null,
    nextPayoutLocalTime:
      nextPayoutDateKey ?
        (toTrimmedString(data.nextPayoutLocalTime) || TUTORING_PAYOUT_LOCAL_TIME) :
        null,
    failedPayoutNoticeCount: Math.max(
      0,
      Math.round(Number(data.failedPayoutNoticeCount ?? 0))
    ),
    hasFailedPayoutNotices: data.hasFailedPayoutNotices === true,
    availableBalanceZar: asMoney(data.availableBalanceZar, 0),
    reservedForPayoutZar: asMoney(data.reservedForPayoutZar, 0),
    heldForDisputesZar: asMoney(data.heldForDisputesZar, 0),
    lifetimePaidOutZar: asMoney(data.lifetimePaidOutZar, 0),
    lastPayoutAt: data.lastPayoutAt ?? null,
    payoutHistoryPreview:
      Array.isArray(data.payoutHistoryPreview) ?
        data.payoutHistoryPreview :
        [],
    failedPayoutNotices:
      Array.isArray(data.failedPayoutNotices) ?
        data.failedPayoutNotices :
        [],
  };
}

export function buildGuestTutoringCustomerDoc(params: {
  customerId: string;
  userData?: Record<string, unknown>;
  bookingData?: Record<string, unknown>;
  temporaryPaymentData?: Record<string, unknown>;
  tutoringBookingCount?: number;
  lastBookingId?: string | null;
  lastBookingAt?: unknown;
  lastUsedAt?: unknown;
}): Record<string, unknown> {
  const userData = params.userData ?? {};
  const bookingData = params.bookingData ?? {};
  const temporaryPaymentData = params.temporaryPaymentData ?? {};
  const guestActive = isGuestTutoringMode({
    ...userData,
    ...bookingData,
  });

  return {
    ...baseSchemaFields(
      TUTORING_LOGICAL_COLLECTIONS.guestTutoringCustomers,
      TUTORING_PHYSICAL_COLLECTIONS.guestTutoringCustomers
    ),
    guestId: params.customerId,
    guestTutoringCustomerId: params.customerId,
    studentId: params.customerId,
    firstName: deriveFirstName({
      ...userData,
      ...bookingData,
    }),
    email: nullableTrimmedString(userData.email),
    phone: nullableTrimmedString(userData.phone),
    paystackCustomerCode:
      nullableTrimmedString(
        temporaryPaymentData.paystackCustomerCode ||
        temporaryPaymentData.mockCustomerCode ||
        userData.paystackCustomerCode ||
        userData.temporaryPaymentCustomerCode
      ),
    reusableAuthorizationCode:
      nullableTrimmedString(
        temporaryPaymentData.reusableAuthorizationCode ||
        userData.reusableAuthorizationCode ||
        userData.temporaryPaymentReusableAuthorizationCode
      ),
    isGuest: true,
    guestTutoringMode: guestActive,
    status: guestActive ? "active" : "inactive",
    accountType: toTrimmedString(userData.accountType),
    accessTier: toTrimmedString(userData.accessTier),
    accessMode: toTrimmedString(userData.accessMode),
    temporaryPaymentProvider:
      toTrimmedString(temporaryPaymentData.provider) ||
      toTrimmedString(userData.temporaryPaymentProvider) ||
      null,
    temporaryPaymentMethodId:
      toTrimmedString(temporaryPaymentData.paymentMethodId) ||
      toTrimmedString(userData.temporaryPaymentMethodId) ||
      null,
    temporaryPaymentRegistrationId:
      toTrimmedString(temporaryPaymentData.registrationId) ||
      toTrimmedString(userData.temporaryPaymentRegistrationId) ||
      null,
    temporaryPaymentProviderReference:
      toTrimmedString(temporaryPaymentData.providerReference) ||
      toTrimmedString(userData.temporaryPaymentProviderReference) ||
      null,
    temporaryPaymentAuthorizationCode:
      toTrimmedString(temporaryPaymentData.mockAuthorizationCode) ||
      toTrimmedString(userData.temporaryPaymentAuthorizationCode) ||
      null,
    temporaryPaymentAuthorizationReference:
      toTrimmedString(temporaryPaymentData.mockAuthorizationReference) ||
      toTrimmedString(userData.temporaryPaymentAuthorizationReference) ||
      null,
    temporaryPaymentPreauthReference:
      toTrimmedString(temporaryPaymentData.mockPreauthReference) ||
      toTrimmedString(userData.temporaryPaymentPreauthReference) ||
      null,
    temporaryPaymentCustomerCode:
      toTrimmedString(temporaryPaymentData.mockCustomerCode) ||
      toTrimmedString(userData.temporaryPaymentCustomerCode) ||
      null,
    temporaryPaymentReusableAuthorizationCode:
      toTrimmedString(temporaryPaymentData.reusableAuthorizationCode) ||
      toTrimmedString(userData.temporaryPaymentReusableAuthorizationCode) ||
      null,
    temporaryPaymentSetupStatus:
      toTrimmedString(temporaryPaymentData.status) ||
      toTrimmedString(userData.temporaryPaymentSetupStatus) ||
      "missing",
    temporaryCardBrand:
      toTrimmedString(temporaryPaymentData.brand) ||
      toTrimmedString(userData.temporaryCardBrand) ||
      null,
    temporaryCardLast4:
      toTrimmedString(temporaryPaymentData.last4) ||
      toTrimmedString(userData.temporaryCardLast4) ||
      null,
    temporaryCardExpMonth:
      Number(
        temporaryPaymentData.expMonth ??
        userData.temporaryCardExpMonth ??
        0
      ) || 0,
    temporaryCardExpYear:
      Number(
        temporaryPaymentData.expYear ??
        userData.temporaryCardExpYear ??
        0
      ) || 0,
    temporaryCardHolder:
      toTrimmedString(temporaryPaymentData.holder) ||
      toTrimmedString(userData.temporaryCardHolder) ||
      deriveFirstName(userData),
    paymentProfileType:
      toTrimmedString(bookingData.paymentProfileType) ||
      (guestActive ? "temporary_instant_tutor_card" : ""),
    tutoringBookingCount: Math.max(0, params.tutoringBookingCount ?? 0),
    lastBookingId: params.lastBookingId ?? null,
    lastBookingAt: params.lastBookingAt ?? null,
    lastUsedAt:
      params.lastUsedAt ??
      userData.lastUsedAt ??
      admin.firestore.FieldValue.serverTimestamp(),
    createdAt: userData.createdAt ?? admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

export function buildDisputeDoc(
  disputeId: string,
  data: Record<string, unknown>
): Record<string, unknown> {
  const heldAmountZar = asMoney(data.disputeHeldAmountZar, 0);
  return {
    ...baseSchemaFields(
      TUTORING_LOGICAL_COLLECTIONS.disputes,
      TUTORING_PHYSICAL_COLLECTIONS.disputes
    ),
    disputeId,
    settlementId: toTrimmedString(data.settlementId) || disputeId,
    bookingId: toTrimmedString(data.bookingId),
    sessionId: toTrimmedString(data.sessionId) || disputeId,
    paymentSessionId: toTrimmedString(data.paymentIntentId) ||
      toTrimmedString(data.bookingId) ||
      null,
    tutorId: toTrimmedString(data.tutorId),
    studentId: toTrimmedString(data.studentId),
    tutorPayableId: toTrimmedString(data.tutorPayableId) || disputeId,
    status: heldAmountZar > 0 ? "open" : "resolved",
    heldAmountZar,
    currency: toTrimmedString(data.currency) || "ZAR",
    disputeReason: toTrimmedString(data.reason || data.disputeReason) || null,
    disputeResolution:
      toTrimmedString(data.resolution || data.disputeResolution) || null,
    sourceCollection: TUTORING_PHYSICAL_COLLECTIONS.settlementRecords,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

export function buildRatingSchemaFields(
  ratingId: string,
  data: Record<string, unknown>
): Record<string, unknown> {
  const payerType = toTrimmedString(data.payerType).toLowerCase() === "guest" ?
    "guest" :
    "student";
  const payerId =
    toTrimmedString(data.payerId) ||
    toTrimmedString(data.raterId) ||
    toTrimmedString(data.studentId);
  const raterType = toTrimmedString(data.raterType).toLowerCase() === "guest" ?
    "guest" :
    payerType;
  const raterId =
    toTrimmedString(data.raterId) ||
    payerId ||
    toTrimmedString(data.studentId);
  const guestId = raterType === "guest" || payerType === "guest" ?
    (
      toTrimmedString(data.guestId) ||
      toTrimmedString(data.studentId) ||
      raterId ||
      null
    ) :
    null;
  return {
    ...baseSchemaFields(
      TUTORING_LOGICAL_COLLECTIONS.ratings,
      TUTORING_PHYSICAL_COLLECTIONS.ratings
    ),
    ratingId,
    bookingId:
      toTrimmedString(data.bookingId) ||
      toTrimmedString(data.requestId),
    sessionId: toTrimmedString(data.sessionId) ||
      toTrimmedString(data.bookingId) ||
      toTrimmedString(data.requestId) ||
      null,
    paymentSessionId: toTrimmedString(data.paymentIntentId) ||
      toTrimmedString(data.bookingId) ||
      toTrimmedString(data.requestId) ||
      null,
    paymentIntentId: toTrimmedString(data.paymentIntentId) ||
      toTrimmedString(data.requestId) ||
      null,
    requestId: toTrimmedString(data.requestId) ||
      toTrimmedString(data.bookingId),
    tutorId: toTrimmedString(data.tutorId) || null,
    studentId: toTrimmedString(data.studentId) || payerId || null,
    payerType,
    payerId: payerId || null,
    raterType,
    raterId: raterId || null,
    guestTutoringMode:
      data.guestTutoringMode === true ||
      payerType === "guest" ||
      raterType === "guest",
    guestTutoringCustomerId: guestId,
    guestId,
    ratingStatus: toTrimmedString(data.status) || "submitted",
    status: toTrimmedString(data.status) || "submitted",
  };
}
