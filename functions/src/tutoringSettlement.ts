import * as admin from "firebase-admin";
import {HttpsError} from "firebase-functions/v2/https";
import {
  buildDisputeDoc,
  buildSettlementSchemaFields,
  buildTutorPayableDoc,
} from "./tutoringFirestoreSchema";

const PLATFORM_MARKUP_MULTIPLIER = 1.2;
const CURRENCY = "ZAR";

export interface TutoringSettlementComputation {
  capturedAmountZar: number;
  pendingCaptureAmountZar: number;
  finalAmountDueZar: number;
  uncapturedAmountZar: number;
  tutorEarningZar: number;
  platformFeeZar: number;
  payoutReservedAmountZar: number;
  payoutPaidAmountZar: number;
  disputeHeldAmountZar: number;
  availableForPayoutZar: number;
  payoutEligibilityStatus: "ELIGIBLE" | "HELD";
  payoutState: "UNPAID" | "RESERVED" | "PARTIALLY_PAID" | "PAID" | "HELD";
  settlementStatus: "completed" | "partial";
}

export interface TutoringSettlementArtifacts {
  settlementBase: Record<string, unknown>;
  tutorPayableBase: Record<string, unknown>;
  metrics: TutoringSettlementComputation;
}

export interface TutorPayableDisputeMutationResult {
  sessionId: string;
  settlementId: string;
  tutorPayableId: string;
  disputeId: string;
  heldAmountZar: number;
  availableForPayoutZar: number;
  payoutEligibilityStatus: "ELIGIBLE" | "HELD";
}

function nowServerTs() {
  return admin.firestore.FieldValue.serverTimestamp();
}

function getDb() {
  return admin.firestore();
}

function toTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
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

function positiveMoneyOrNull(value: unknown): number | null {
  const amount = asMoney(value, -1);
  return amount > 0 ? amount : null;
}

function payoutStateAfterHold(params: {
  earning: number;
  reserved: number;
  paid: number;
  held: number;
}): "UNPAID" | "RESERVED" | "PARTIALLY_PAID" | "PAID" | "HELD" {
  const available = toMoney(
    Math.max(0, params.earning - params.reserved - params.paid - params.held)
  );
  if (params.held > 0 && params.paid <= 0 && params.reserved <= 0) {
    return "HELD";
  }
  if (available <= 0 && params.paid >= params.earning - params.held - 0.0001) {
    return "PAID";
  }
  if (params.reserved > 0) {
    return "RESERVED";
  }
  if (params.paid > 0) {
    return "PARTIALLY_PAID";
  }
  return "UNPAID";
}

export function computeTutoringSettlementComputation(params: {
  capturedAmountZar: number;
  pendingCaptureAmountZar?: number;
  finalAmountDueZar: number;
  payoutReservedAmountZar?: number;
  payoutPaidAmountZar?: number;
  disputeHeldAmountZar?: number;
}): TutoringSettlementComputation {
  const capturedAmountZar = toMoney(Math.max(0, params.capturedAmountZar));
  const pendingCaptureAmountZar = toMoney(
    Math.max(0, params.pendingCaptureAmountZar ?? 0)
  );
  const finalAmountDueZar = toMoney(Math.max(0, params.finalAmountDueZar));
  const payoutReservedAmountZar = toMoney(
    Math.max(0, params.payoutReservedAmountZar ?? 0)
  );
  const payoutPaidAmountZar = toMoney(
    Math.max(0, params.payoutPaidAmountZar ?? 0)
  );
  const disputeHeldAmountZar = toMoney(
    Math.max(0, params.disputeHeldAmountZar ?? 0)
  );
  const tutorEarningZar = toMoney(capturedAmountZar / PLATFORM_MARKUP_MULTIPLIER);
  const platformFeeZar = toMoney(capturedAmountZar - tutorEarningZar);
  const uncapturedAmountZar = toMoney(
    Math.max(0, finalAmountDueZar - capturedAmountZar)
  );
  const availableForPayoutZar = toMoney(
    Math.max(
      0,
      tutorEarningZar -
        payoutReservedAmountZar -
        payoutPaidAmountZar -
        disputeHeldAmountZar
    )
  );
  const payoutEligibilityStatus = disputeHeldAmountZar > 0 ? "HELD" : "ELIGIBLE";
  return {
    capturedAmountZar,
    pendingCaptureAmountZar,
    finalAmountDueZar,
    uncapturedAmountZar,
    tutorEarningZar,
    platformFeeZar,
    payoutReservedAmountZar,
    payoutPaidAmountZar,
    disputeHeldAmountZar,
    availableForPayoutZar,
    payoutEligibilityStatus,
    payoutState: payoutStateAfterHold({
      earning: tutorEarningZar,
      reserved: payoutReservedAmountZar,
      paid: payoutPaidAmountZar,
      held: disputeHeldAmountZar,
    }),
    settlementStatus: uncapturedAmountZar <= 0.0001 ? "completed" : "partial",
  };
}

export function buildTutoringSettlementArtifacts(params: {
  settlementId: string;
  sessionId: string;
  bookingId: string;
  paymentIntentId: string;
  studentId: string;
  tutorId: string;
  status: string;
  billableMinutes: number;
  finalAmountDueZar: number;
  capturedAmountZar: number;
  pendingCaptureAmountZar?: number;
  releasedAuthorizationAmountZar?: number;
  pendingReleasedAuthorizationAmountZar?: number;
  ratingRequired?: boolean;
  currency?: string;
  createdAt?: unknown;
  updatedAt?: unknown;
  settledAt?: unknown;
  payoutReservedAmountZar?: number;
  payoutPaidAmountZar?: number;
  disputeHeldAmountZar?: number;
  existingDisputeId?: string | null;
}): TutoringSettlementArtifacts {
  const metrics = computeTutoringSettlementComputation({
    capturedAmountZar: params.capturedAmountZar,
    pendingCaptureAmountZar: params.pendingCaptureAmountZar,
    finalAmountDueZar: params.finalAmountDueZar,
    payoutReservedAmountZar: params.payoutReservedAmountZar,
    payoutPaidAmountZar: params.payoutPaidAmountZar,
    disputeHeldAmountZar: params.disputeHeldAmountZar,
  });
  const settlementBase: Record<string, unknown> = {
    settlementId: params.settlementId,
    sessionId: params.sessionId,
    bookingId: params.bookingId,
    paymentIntentId: params.paymentIntentId,
    tutoringPaymentRail: "TUTORING",
    settlementEngineVersion: 1,
    settlementSource: "mock_capture_events",
    payoutFundingSource: "captured_tutoring_funds_only",
    payableFundingSource: "captured_tutoring_funds_only",
    capturedFundsOnly: true,
    studentId: params.studentId,
    tutorId: params.tutorId,
    status: params.status,
    settlementStatus: metrics.settlementStatus,
    billableMinutes: Math.max(0, Math.round(params.billableMinutes)),
    finalAmountDueZar: metrics.finalAmountDueZar,
    capturedTotalZar: metrics.capturedAmountZar,
    capturedAmountZar: metrics.capturedAmountZar,
    pendingCaptureTotalZar: metrics.pendingCaptureAmountZar,
    pendingCaptureAmountZar: metrics.pendingCaptureAmountZar,
    uncapturedAmountZar: metrics.uncapturedAmountZar,
    tutorEarningZar: metrics.tutorEarningZar,
    platformFeeZar: metrics.platformFeeZar,
    payoutEligibilityStatus: metrics.payoutEligibilityStatus,
    payoutReservedAmountZar: metrics.payoutReservedAmountZar,
    payoutPaidAmountZar: metrics.payoutPaidAmountZar,
    disputeHeldAmountZar: metrics.disputeHeldAmountZar,
    availableForPayoutZar: metrics.availableForPayoutZar,
    payoutState: metrics.payoutState,
    payoutDisputedAmountZar: metrics.disputeHeldAmountZar,
    payoutExcludedUncapturedAmountZar: metrics.uncapturedAmountZar,
    disputeStatus: metrics.disputeHeldAmountZar > 0 ? "open" : "none",
    activeDisputeId:
      metrics.disputeHeldAmountZar > 0 ?
        (params.existingDisputeId || params.sessionId) :
        null,
    releasedAuthorizationAmountZar: asMoney(
      params.releasedAuthorizationAmountZar,
      0
    ),
    pendingReleasedAuthorizationAmountZar: asMoney(
      params.pendingReleasedAuthorizationAmountZar,
      0
    ),
    ratingRequired: params.ratingRequired === true,
    currency: toTrimmedString(params.currency) || CURRENCY,
    createdAt: params.createdAt ?? nowServerTs(),
    updatedAt: params.updatedAt ?? nowServerTs(),
    settledAt: params.settledAt ?? nowServerTs(),
  };
  const tutorPayableBase: Record<string, unknown> = {
    ...settlementBase,
    payableId: params.settlementId,
    tutorPayableId: params.settlementId,
    payableStatus:
      metrics.availableForPayoutZar > 0 ?
        metrics.payoutEligibilityStatus === "HELD" ? "blocked" : "available" :
        metrics.disputeHeldAmountZar > 0 ? "blocked" : "settled_zero",
    grossTutorEarningZar: metrics.tutorEarningZar,
    blockedAmountZar: metrics.disputeHeldAmountZar,
    reservedAmountZar: metrics.payoutReservedAmountZar,
    paidAmountZar: metrics.payoutPaidAmountZar,
    availableAmountZar: metrics.availableForPayoutZar,
    capturedAmountZar: metrics.capturedAmountZar,
    uncapturedAmountZar: metrics.uncapturedAmountZar,
    disputeId:
      metrics.disputeHeldAmountZar > 0 ?
        (params.existingDisputeId || params.sessionId) :
        null,
  };
  return {
    settlementBase,
    tutorPayableBase,
    metrics,
  };
}

async function loadSettlementContext(params: {
  tx: admin.firestore.Transaction;
  sessionId: string;
}) {
  const db = getDb();
  const sessionRef = db.collection("tutoring_sessions").doc(params.sessionId);
  const settlementRef = db.collection("tutor_session_settlements").doc(params.sessionId);
  const payableRef = db.collection("tutor_payables").doc(params.sessionId);
  const disputeRef = db.collection("disputes").doc(params.sessionId);
  const sessionSnap = await params.tx.get(sessionRef);
  if (!sessionSnap.exists) {
    throw new HttpsError("not-found", "Tutoring session not found.");
  }
  const sessionData = sessionSnap.data() ?? {};
  const bookingId = toTrimmedString(sessionData.bookingId) || params.sessionId;
  const paymentIntentId =
    toTrimmedString(sessionData.paymentIntentId) || bookingId;
  const bookingRef = db.collection("tutor_requests").doc(bookingId);
  const paymentIntentRef = db.collection("session_payment_intents").doc(paymentIntentId);
  const [bookingSnap, paymentIntentSnap, settlementSnap, payableSnap, disputeSnap] =
    await Promise.all([
      params.tx.get(bookingRef),
      params.tx.get(paymentIntentRef),
      params.tx.get(settlementRef),
      params.tx.get(payableRef),
      params.tx.get(disputeRef),
    ]);
  if (!bookingSnap.exists || !paymentIntentSnap.exists) {
    throw new HttpsError(
      "failed-precondition",
      "Booking or payment session is missing for this tutoring settlement."
    );
  }
  return {
    sessionRef,
    sessionSnap,
    sessionData,
    bookingRef,
    bookingSnap,
    bookingData: bookingSnap.data() ?? {},
    paymentIntentRef,
    paymentIntentSnap,
    paymentIntentData: paymentIntentSnap.data() ?? {},
    settlementRef,
    settlementSnap,
    payableRef,
    payableSnap,
    disputeRef,
    disputeSnap,
  };
}

export async function createSettlementForSession(
  sessionId: string
): Promise<Record<string, unknown>> {
  const trimmedSessionId = toTrimmedString(sessionId);
  if (!trimmedSessionId) {
    throw new HttpsError("invalid-argument", "sessionId is required.");
  }

  const db = getDb();
  return db.runTransaction(async (tx) => {
    const settledAt = new Date();
    const context = await loadSettlementContext({
      tx,
      sessionId: trimmedSessionId,
    });
    if (context.settlementSnap.exists) {
      return {
        settlementId: context.settlementRef.id,
        ...(context.settlementSnap.data() ?? {}),
      };
    }

    const sessionData = context.sessionData;
    const bookingData = context.bookingData;
    const paymentIntentData = context.paymentIntentData;
    const artifacts = buildTutoringSettlementArtifacts({
      settlementId: context.settlementRef.id,
      sessionId: trimmedSessionId,
      bookingId: context.bookingRef.id,
      paymentIntentId: context.paymentIntentRef.id,
      studentId:
        toTrimmedString(sessionData.studentId) ||
        toTrimmedString(bookingData.studentId),
      tutorId:
        toTrimmedString(sessionData.tutorId) ||
        toTrimmedString(bookingData.tutorId),
      status:
        toTrimmedString(sessionData.status) ||
        toTrimmedString(bookingData.status) ||
        "completed",
      billableMinutes: Math.max(
        0,
        Math.round(
          Number(
            sessionData.billableMinutes ??
              sessionData.closingBillableMinutes ??
              bookingData.billableMinutes ??
              0
          )
        )
      ),
      finalAmountDueZar: asMoney(
        sessionData.amountDueZar ?? sessionData.closingAmountDueZar,
        asMoney(
          paymentIntentData.chargeAmountZar,
          asMoney(bookingData.chargeAmountZar, 0)
        )
      ),
      capturedAmountZar: asMoney(
        sessionData.capturedTotalZar,
        asMoney(paymentIntentData.capturedAmountZar, 0)
      ),
      pendingCaptureAmountZar: asMoney(
        sessionData.pendingCaptureTotalZar,
        asMoney(paymentIntentData.pendingCaptureTotalZar, 0)
      ),
      releasedAuthorizationAmountZar: asMoney(
        sessionData.releasedAuthorizationAmountZar,
        asMoney(paymentIntentData.releasedAmountZar, 0)
      ),
      pendingReleasedAuthorizationAmountZar: asMoney(
        sessionData.pendingReleasedAuthorizationAmountZar,
        asMoney(paymentIntentData.pendingReleasedAmountZar, 0)
      ),
      ratingRequired:
        sessionData.ratingRequired === true ||
        bookingData.ratingRequired === true,
      currency:
        toTrimmedString(sessionData.currency) ||
        toTrimmedString(paymentIntentData.currency) ||
        toTrimmedString(bookingData.currency) ||
        CURRENCY,
      createdAt: settledAt,
      updatedAt: nowServerTs(),
      settledAt,
      payoutReservedAmountZar: 0,
      payoutPaidAmountZar: 0,
      disputeHeldAmountZar: 0,
      existingDisputeId: null,
    });

    tx.set(context.settlementRef, {
      ...artifacts.settlementBase,
      ...buildSettlementSchemaFields(
        context.settlementRef.id,
        artifacts.settlementBase
      ),
    }, {merge: true});

    tx.set(context.sessionRef, {
      settlementId: context.settlementRef.id,
      settlementStatus: artifacts.metrics.settlementStatus,
      capturedAmountZar: artifacts.metrics.capturedAmountZar,
      pendingCaptureTotalZar: artifacts.metrics.pendingCaptureAmountZar,
      tutorPayoutZar: artifacts.metrics.tutorEarningZar,
      platformRevenueZar: artifacts.metrics.platformFeeZar,
      updatedAt: nowServerTs(),
    }, {merge: true});
    tx.set(context.bookingRef, {
      settlementId: context.settlementRef.id,
      settlementStatus: artifacts.metrics.settlementStatus,
      capturedAmountZar: artifacts.metrics.capturedAmountZar,
      pendingCaptureTotalZar: artifacts.metrics.pendingCaptureAmountZar,
      tutorPayoutZar: artifacts.metrics.tutorEarningZar,
      platformRevenueZar: artifacts.metrics.platformFeeZar,
      updatedAt: nowServerTs(),
    }, {merge: true});
    tx.set(context.paymentIntentRef, {
      settlementId: context.settlementRef.id,
      settlementStatus: artifacts.metrics.settlementStatus,
      capturedAmountZar: artifacts.metrics.capturedAmountZar,
      pendingCaptureTotalZar: artifacts.metrics.pendingCaptureAmountZar,
      tutorPayoutZar: artifacts.metrics.tutorEarningZar,
      platformRevenueZar: artifacts.metrics.platformFeeZar,
      updatedAt: nowServerTs(),
    }, {merge: true});

    return {
      settlementId: context.settlementRef.id,
      ...artifacts.settlementBase,
    };
  });
}

export async function createTutorPayableEntries(
  sessionId: string
): Promise<Record<string, unknown>> {
  const trimmedSessionId = toTrimmedString(sessionId);
  if (!trimmedSessionId) {
    throw new HttpsError("invalid-argument", "sessionId is required.");
  }

  await createSettlementForSession(trimmedSessionId);

  const db = getDb();
  return db.runTransaction(async (tx) => {
    const context = await loadSettlementContext({
      tx,
      sessionId: trimmedSessionId,
    });
    const settlementData = context.settlementSnap.data() ?? {};
    const payableBase = {
      settlementId: context.settlementRef.id,
      ...settlementData,
    };
    tx.set(context.payableRef, {
      ...payableBase,
      ...buildTutorPayableDoc(context.payableRef.id, payableBase),
      updatedAt: nowServerTs(),
    }, {merge: true});
    tx.set(context.settlementRef, {
      tutorPayableId: context.payableRef.id,
      updatedAt: nowServerTs(),
    }, {merge: true});
    return {
      tutorPayableId: context.payableRef.id,
      ...payableBase,
    };
  });
}

export function deriveDisputeHoldMutation(params: {
  tutorEarningZar: number;
  payoutReservedAmountZar?: number;
  payoutPaidAmountZar?: number;
  disputeHeldAmountZar?: number;
  holdAmountZar?: number | null;
}): {
  appliedHoldAmountZar: number;
  disputeHeldAmountZar: number;
  availableForPayoutZar: number;
  payoutEligibilityStatus: "ELIGIBLE" | "HELD";
  payoutState: "UNPAID" | "RESERVED" | "PARTIALLY_PAID" | "PAID" | "HELD";
} {
  const current = computeTutoringSettlementComputation({
    capturedAmountZar: params.tutorEarningZar * PLATFORM_MARKUP_MULTIPLIER,
    finalAmountDueZar: params.tutorEarningZar * PLATFORM_MARKUP_MULTIPLIER,
    payoutReservedAmountZar: params.payoutReservedAmountZar,
    payoutPaidAmountZar: params.payoutPaidAmountZar,
    disputeHeldAmountZar: params.disputeHeldAmountZar,
  });
  const maxHoldable = toMoney(
    Math.max(0, current.tutorEarningZar - current.payoutReservedAmountZar -
      current.payoutPaidAmountZar - current.disputeHeldAmountZar)
  );
  const requestedHold = params.holdAmountZar == null ?
    maxHoldable :
    toMoney(Math.max(0, params.holdAmountZar));
  const appliedHoldAmountZar = toMoney(Math.min(maxHoldable, requestedHold));
  const nextHeld = toMoney(current.disputeHeldAmountZar + appliedHoldAmountZar);
  const nextAvailable = toMoney(
    Math.max(
      0,
      current.tutorEarningZar - current.payoutReservedAmountZar -
        current.payoutPaidAmountZar - nextHeld
    )
  );
  return {
    appliedHoldAmountZar,
    disputeHeldAmountZar: nextHeld,
    availableForPayoutZar: nextAvailable,
    payoutEligibilityStatus: nextHeld > 0 ? "HELD" : "ELIGIBLE",
    payoutState: payoutStateAfterHold({
      earning: current.tutorEarningZar,
      reserved: current.payoutReservedAmountZar,
      paid: current.payoutPaidAmountZar,
      held: nextHeld,
    }),
  };
}

export function deriveDisputeReleaseMutation(params: {
  tutorEarningZar: number;
  payoutReservedAmountZar?: number;
  payoutPaidAmountZar?: number;
  disputeHeldAmountZar?: number;
  releaseAmountZar?: number | null;
}): {
  appliedReleaseAmountZar: number;
  disputeHeldAmountZar: number;
  availableForPayoutZar: number;
  payoutEligibilityStatus: "ELIGIBLE" | "HELD";
  payoutState: "UNPAID" | "RESERVED" | "PARTIALLY_PAID" | "PAID" | "HELD";
} {
  const currentHeld = toMoney(Math.max(0, params.disputeHeldAmountZar ?? 0));
  const requestedRelease = params.releaseAmountZar == null ?
    currentHeld :
    toMoney(Math.max(0, params.releaseAmountZar));
  const appliedReleaseAmountZar = toMoney(Math.min(currentHeld, requestedRelease));
  const nextHeld = toMoney(Math.max(0, currentHeld - appliedReleaseAmountZar));
  const tutorEarningZar = toMoney(Math.max(0, params.tutorEarningZar));
  const reserved = toMoney(Math.max(0, params.payoutReservedAmountZar ?? 0));
  const paid = toMoney(Math.max(0, params.payoutPaidAmountZar ?? 0));
  const availableForPayoutZar = toMoney(
    Math.max(0, tutorEarningZar - reserved - paid - nextHeld)
  );
  return {
    appliedReleaseAmountZar,
    disputeHeldAmountZar: nextHeld,
    availableForPayoutZar,
    payoutEligibilityStatus: nextHeld > 0 ? "HELD" : "ELIGIBLE",
    payoutState: payoutStateAfterHold({
      earning: tutorEarningZar,
      reserved,
      paid,
      held: nextHeld,
    }),
  };
}

export async function freezeTutorPayablesForDispute(
  sessionId: string,
  options: {
    disputeId?: string;
    heldAmountZar?: number;
    reason?: string;
  } = {}
): Promise<TutorPayableDisputeMutationResult> {
  const trimmedSessionId = toTrimmedString(sessionId);
  if (!trimmedSessionId) {
    throw new HttpsError("invalid-argument", "sessionId is required.");
  }

  await createTutorPayableEntries(trimmedSessionId);

  const db = getDb();
  return db.runTransaction(async (tx) => {
    const context = await loadSettlementContext({
      tx,
      sessionId: trimmedSessionId,
    });
    const settlementData = context.settlementSnap.data() ?? {};
    const tutorId = toTrimmedString(settlementData.tutorId);
    const hold = deriveDisputeHoldMutation({
      tutorEarningZar: asMoney(settlementData.tutorEarningZar, 0),
      payoutReservedAmountZar: asMoney(settlementData.payoutReservedAmountZar, 0),
      payoutPaidAmountZar: asMoney(settlementData.payoutPaidAmountZar, 0),
      disputeHeldAmountZar: asMoney(settlementData.disputeHeldAmountZar, 0),
      holdAmountZar: positiveMoneyOrNull(options.heldAmountZar),
    });
    const disputeId = toTrimmedString(options.disputeId) || trimmedSessionId;
    const reason = toTrimmedString(options.reason) || "session_dispute";
    const nextSettlement = {
      ...settlementData,
      disputeHeldAmountZar: hold.disputeHeldAmountZar,
      payoutEligibilityStatus: hold.payoutEligibilityStatus,
      availableForPayoutZar: hold.availableForPayoutZar,
      payoutState: hold.payoutState,
      payoutDisputedAmountZar: hold.disputeHeldAmountZar,
      disputeStatus: hold.disputeHeldAmountZar > 0 ? "open" : "none",
      activeDisputeId: hold.disputeHeldAmountZar > 0 ? disputeId : null,
      updatedAt: nowServerTs(),
      ...(hold.appliedHoldAmountZar > 0 ? {
        payableFrozenAt: nowServerTs(),
      } : {}),
    };
    const nextPayable = {
      settlementId: context.settlementRef.id,
      ...nextSettlement,
      payableId: context.payableRef.id,
      tutorPayableId: context.payableRef.id,
      grossTutorEarningZar: asMoney(settlementData.tutorEarningZar, 0),
      blockedAmountZar: hold.disputeHeldAmountZar,
      availableAmountZar: hold.availableForPayoutZar,
      disputeId: hold.disputeHeldAmountZar > 0 ? disputeId : null,
      payableStatus:
        hold.disputeHeldAmountZar > 0 ? "blocked" :
        hold.availableForPayoutZar > 0 ? "available" : "settled_zero",
    };
    const nextDispute = {
      disputeId,
      settlementId: context.settlementRef.id,
      sessionId: trimmedSessionId,
      bookingId: toTrimmedString(settlementData.bookingId),
      paymentIntentId: toTrimmedString(settlementData.paymentIntentId),
      tutorId,
      studentId: toTrimmedString(settlementData.studentId),
      disputeHeldAmountZar: hold.disputeHeldAmountZar,
      status: hold.disputeHeldAmountZar > 0 ? "open" : "resolved",
      reason,
      updatedAt: nowServerTs(),
      openedAt:
        context.disputeSnap.exists &&
        context.disputeSnap.data()?.openedAt instanceof admin.firestore.Timestamp ?
          context.disputeSnap.data()?.openedAt :
          nowServerTs(),
    };

    tx.set(context.settlementRef, {
      ...nextSettlement,
      ...buildSettlementSchemaFields(context.settlementRef.id, nextSettlement),
    }, {merge: true});
    tx.set(context.payableRef, {
      ...nextPayable,
      ...buildTutorPayableDoc(context.payableRef.id, nextPayable),
    }, {merge: true});
    tx.set(context.disputeRef, {
      ...nextDispute,
      ...buildDisputeDoc(disputeId, nextDispute),
    }, {merge: true});
    if (hold.appliedHoldAmountZar > 0 && tutorId) {
      tx.set(db.collection("users").doc(tutorId), {
        walletPayoutPendingZar: admin.firestore.FieldValue.increment(
          -hold.appliedHoldAmountZar
        ),
        walletPayoutHeldForDisputesZar: admin.firestore.FieldValue.increment(
          hold.appliedHoldAmountZar
        ),
        walletUpdatedAt: nowServerTs(),
      }, {merge: true});
      tx.set(db.collection("platform_finance").doc("overview"), {
        tutorPayoutPendingZar: admin.firestore.FieldValue.increment(
          -hold.appliedHoldAmountZar
        ),
        tutorPayoutHeldForDisputesZar: admin.firestore.FieldValue.increment(
          hold.appliedHoldAmountZar
        ),
        updatedAt: nowServerTs(),
      }, {merge: true});
    }

    return {
      sessionId: trimmedSessionId,
      settlementId: context.settlementRef.id,
      tutorPayableId: context.payableRef.id,
      disputeId,
      heldAmountZar: hold.disputeHeldAmountZar,
      availableForPayoutZar: hold.availableForPayoutZar,
      payoutEligibilityStatus: hold.payoutEligibilityStatus,
    };
  });
}

export async function releaseTutorPayablesAfterDisputeResolution(
  sessionId: string,
  options: {
    disputeId?: string;
    releaseAmountZar?: number;
    resolution?: string;
  } = {}
): Promise<TutorPayableDisputeMutationResult> {
  const trimmedSessionId = toTrimmedString(sessionId);
  if (!trimmedSessionId) {
    throw new HttpsError("invalid-argument", "sessionId is required.");
  }

  await createTutorPayableEntries(trimmedSessionId);

  const db = getDb();
  return db.runTransaction(async (tx) => {
    const context = await loadSettlementContext({
      tx,
      sessionId: trimmedSessionId,
    });
    const settlementData = context.settlementSnap.data() ?? {};
    const tutorId = toTrimmedString(settlementData.tutorId);
    const release = deriveDisputeReleaseMutation({
      tutorEarningZar: asMoney(settlementData.tutorEarningZar, 0),
      payoutReservedAmountZar: asMoney(settlementData.payoutReservedAmountZar, 0),
      payoutPaidAmountZar: asMoney(settlementData.payoutPaidAmountZar, 0),
      disputeHeldAmountZar: asMoney(settlementData.disputeHeldAmountZar, 0),
      releaseAmountZar: positiveMoneyOrNull(options.releaseAmountZar),
    });
    const disputeId = toTrimmedString(options.disputeId) || trimmedSessionId;
    const resolution = toTrimmedString(options.resolution) || "released";
    const nextSettlement = {
      ...settlementData,
      disputeHeldAmountZar: release.disputeHeldAmountZar,
      payoutEligibilityStatus: release.payoutEligibilityStatus,
      availableForPayoutZar: release.availableForPayoutZar,
      payoutState: release.payoutState,
      payoutDisputedAmountZar: release.disputeHeldAmountZar,
      disputeStatus: release.disputeHeldAmountZar > 0 ? "open" : "resolved",
      activeDisputeId: release.disputeHeldAmountZar > 0 ? disputeId : null,
      updatedAt: nowServerTs(),
      ...(release.appliedReleaseAmountZar > 0 ? {
        payableReleasedAt: nowServerTs(),
      } : {}),
    };
    const nextPayable = {
      settlementId: context.settlementRef.id,
      ...nextSettlement,
      payableId: context.payableRef.id,
      tutorPayableId: context.payableRef.id,
      grossTutorEarningZar: asMoney(settlementData.tutorEarningZar, 0),
      blockedAmountZar: release.disputeHeldAmountZar,
      availableAmountZar: release.availableForPayoutZar,
      disputeId: release.disputeHeldAmountZar > 0 ? disputeId : null,
      payableStatus:
        release.disputeHeldAmountZar > 0 ? "blocked" :
        release.availableForPayoutZar > 0 ? "available" : "settled_zero",
    };
    const nextDispute = {
      disputeId,
      settlementId: context.settlementRef.id,
      sessionId: trimmedSessionId,
      bookingId: toTrimmedString(settlementData.bookingId),
      paymentIntentId: toTrimmedString(settlementData.paymentIntentId),
      tutorId,
      studentId: toTrimmedString(settlementData.studentId),
      disputeHeldAmountZar: release.disputeHeldAmountZar,
      status: release.disputeHeldAmountZar > 0 ? "open" : "resolved",
      resolution,
      updatedAt: nowServerTs(),
      ...(release.disputeHeldAmountZar > 0 ? {} : {
        resolvedAt: nowServerTs(),
      }),
    };

    tx.set(context.settlementRef, {
      ...nextSettlement,
      ...buildSettlementSchemaFields(context.settlementRef.id, nextSettlement),
    }, {merge: true});
    tx.set(context.payableRef, {
      ...nextPayable,
      ...buildTutorPayableDoc(context.payableRef.id, nextPayable),
    }, {merge: true});
    tx.set(context.disputeRef, {
      ...nextDispute,
      ...buildDisputeDoc(disputeId, nextDispute),
    }, {merge: true});
    if (release.appliedReleaseAmountZar > 0 && tutorId) {
      tx.set(db.collection("users").doc(tutorId), {
        walletPayoutPendingZar: admin.firestore.FieldValue.increment(
          release.appliedReleaseAmountZar
        ),
        walletPayoutHeldForDisputesZar: admin.firestore.FieldValue.increment(
          -release.appliedReleaseAmountZar
        ),
        walletUpdatedAt: nowServerTs(),
      }, {merge: true});
      tx.set(db.collection("platform_finance").doc("overview"), {
        tutorPayoutPendingZar: admin.firestore.FieldValue.increment(
          release.appliedReleaseAmountZar
        ),
        tutorPayoutHeldForDisputesZar: admin.firestore.FieldValue.increment(
          -release.appliedReleaseAmountZar
        ),
        updatedAt: nowServerTs(),
      }, {merge: true});
    }

    return {
      sessionId: trimmedSessionId,
      settlementId: context.settlementRef.id,
      tutorPayableId: context.payableRef.id,
      disputeId,
      heldAmountZar: release.disputeHeldAmountZar,
      availableForPayoutZar: release.availableForPayoutZar,
      payoutEligibilityStatus: release.payoutEligibilityStatus,
    };
  });
}
