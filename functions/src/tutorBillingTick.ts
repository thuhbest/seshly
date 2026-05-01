import {createHash} from "node:crypto";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {
  MOCK_TUTORING_PROVIDER_NAME,
  type TutoringPaymentProvider,
} from "./payments/tutoringPaymentProvider";
import {getActiveTutoringPaymentProvider} from "./payments/tutorPaymentProviderSelector";
import {forceEndRoom} from "./tutorRoomControl";
import {
  buildCaptureSchemaFields,
  buildPaymentAuthorizationSchemaFields,
} from "./tutoringFirestoreSchema";
import {
  buildLowFundsNotificationPayload,
  shouldForceEndForProtectionExhaustion,
} from "./tutoringLowFunds";
import {
  assertBookingTransition,
  assertSessionTransition,
  deriveTutoringBookingState,
  deriveTutoringSessionState,
  TutoringBookingState,
  TutoringSessionState,
  TutoringStateTransitionError,
  TutoringTransitionActor,
} from "./tutoringStateMachine";

const db = admin.firestore();

const REGION = "europe-west1";
const SCHEDULE = "* * * * *";
const EFFECTIVE_SWEEP_INTERVAL_MS = 30 * 1000;
const CURRENCY = "ZAR";
const PAYMENT_PROVIDER = MOCK_TUTORING_PROVIDER_NAME;
const AUTH_STATUS_INITIATING = "INITIATING";
const AUTH_STATUS_PENDING_PROVIDER = "PENDING_PROVIDER";
const AUTH_STATUS_AUTHORIZED = "AUTHORIZED";
const AUTH_STATUS_FAILED = "FAILED";
const SESSION_ACTIVE = "ACTIVE";
const SESSION_LOW_FUNDS = "LOW_FUNDS";
const SESSION_ENDED_INSUFFICIENT_FUNDS = "ENDED_INSUFFICIENT_FUNDS";
const INITIAL_BUFFER_MINUTES = 20;
const REFILL_THRESHOLD_MINUTES = 5;
const REFILL_CHUNK_MINUTES = 20;
const BILLING_LOCK_MS = 55 * 1000;

type AuthorizationOutcome = "AUTHORIZED" | "PENDING_PROVIDER" | "FAILED";
type CaptureOutcome = "CAPTURED" | "PENDING_PROVIDER" | "FAILED";

interface PaymentProviderContext {
  provider: TutoringPaymentProvider;
}

interface PeachApiResult {
  id?: string;
  ndc?: string;
  registrationId?: string;
  merchantTransactionId?: string;
  timestamp?: string;
  result?: {
    code?: string;
    description?: string;
  };
  [key: string]: unknown;
}

interface SessionTickPreparation {
  sessionId: string;
  tickId: string;
  billableMinutes: number;
  amountDueZar: number;
  studentRatePerMinZar: number;
  paymentIntentId: string;
  bookingId: string;
  studentId: string;
  tutorId: string;
  roomName: string;
  sessionStatus: string;
  sessionStartAt: Date | null;
  lowFundsAt: Date | null;
  protectedMinutesPurchased: number;
  protectedMinutesRemaining: number;
  consumedMinutes: number;
  refillAttemptCount: number;
  capturedTotalZar: number;
  pendingCaptureTotalZar: number;
  currency: string;
}

interface AuthorizationState {
  ref: admin.firestore.DocumentReference;
  id: string;
  data: Record<string, unknown>;
  amountZar: number;
  capturedAmountZar: number;
  pendingCaptureAmountZar: number;
  remainingAuthorizedZar: number;
  status: string;
  providerPaymentId: string;
  registrationId: string;
  paymentMethodId: string;
  paymentMethodType: string;
  paymentMethodSummary: string;
}

interface CaptureExecutionResult {
  captureId: string;
  status: CaptureOutcome;
  accountedAmountZar: number;
}

interface TopUpAuthorizationResult {
  authorizationId: string;
  status: AuthorizationOutcome | "SKIPPED";
  newlyAvailableAmountZar: number;
}

interface ProtectedTimeState {
  protectedMinutesPurchased: number;
  protectedMinutesRemaining: number;
  consumedMinutes: number;
  refillAttemptCount: number;
  lowFundsAt: Date | null;
}

function assertBookingState(params: {
  current: TutoringBookingState | null | undefined;
  next: TutoringBookingState;
  actor: TutoringTransitionActor;
  isGuestSession?: boolean;
  guestAccessValidated?: boolean;
  reason?: "cancel" | "no_show" | "normal_end" | "insufficient_funds";
}): void {
  try {
    assertBookingTransition(params.current, params.next, {
      actor: params.actor,
      isGuestSession: params.isGuestSession,
      guestAccessValidated: params.guestAccessValidated,
      reason: params.reason,
    });
  } catch (error) {
    if (error instanceof TutoringStateTransitionError) {
      throw new Error(error.message);
    }
    throw error;
  }
}

function assertSessionState(params: {
  current: TutoringSessionState | null | undefined;
  next: TutoringSessionState;
  actor: TutoringTransitionActor;
  isGuestSession?: boolean;
  guestAccessValidated?: boolean;
  reason?: "cancel" | "no_show" | "normal_end" | "insufficient_funds";
}): void {
  try {
    assertSessionTransition(params.current, params.next, {
      actor: params.actor,
      isGuestSession: params.isGuestSession,
      guestAccessValidated: params.guestAccessValidated,
      reason: params.reason,
    });
  } catch (error) {
    if (error instanceof TutoringStateTransitionError) {
      throw new Error(error.message);
    }
    throw error;
  }
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

export type ProtectionAuthorizationOutcome = AuthorizationOutcome;

export function deriveProtectedTimeState(
  sessionData: Record<string, unknown>,
  paymentIntentData: Record<string, unknown>
): ProtectedTimeState {
  const protectedMinutesPurchased = Math.max(
    asWholeMinutes(sessionData.protectedMinutesPurchased, -1),
    asWholeMinutes(paymentIntentData.protectedMinutesPurchased, 0)
  );
  const consumedMinutes = Math.max(
    asWholeMinutes(sessionData.consumedMinutes, -1),
    asWholeMinutes(paymentIntentData.consumedMinutes, 0)
  );
  const protectedMinutesRemaining = Math.max(
    0,
    Math.max(
      asWholeMinutes(sessionData.protectedMinutesRemaining, -1),
      asWholeMinutes(paymentIntentData.protectedMinutesRemaining, 0),
      protectedMinutesPurchased - consumedMinutes
    )
  );
  return {
    protectedMinutesPurchased: Math.max(0, protectedMinutesPurchased),
    protectedMinutesRemaining,
    consumedMinutes: Math.max(0, consumedMinutes),
    refillAttemptCount: Math.max(
      asWholeMinutes(sessionData.refillAttemptCount, -1),
      asWholeMinutes(paymentIntentData.refillAttemptCount, 0)
    ),
    lowFundsAt: timestampToDate(
      sessionData.lowFundsAt ?? paymentIntentData.lowFundsAt
    ),
  };
}

export function computeProtectedTimeProgress(params: {
  sessionStartAt: Date;
  now: Date;
  protectedMinutesPurchased: number;
}): {
  elapsedMinutes: number;
  billableMinutes: number;
  consumedMinutes: number;
  protectedMinutesRemaining: number;
  tickId: string;
} {
  const elapsedMs = Math.max(0, params.now.getTime() - params.sessionStartAt.getTime());
  const elapsedMinutes = Math.max(1, Math.ceil(elapsedMs / 60000));
  const billableMinutes = params.protectedMinutesPurchased > 0 ?
    Math.min(elapsedMinutes, params.protectedMinutesPurchased) :
    elapsedMinutes;
  return {
    elapsedMinutes,
    billableMinutes,
    consumedMinutes: billableMinutes,
    protectedMinutesRemaining: Math.max(
      0,
      params.protectedMinutesPurchased - billableMinutes
    ),
    tickId: buildTickId(billableMinutes),
  };
}

export function deriveProtectedStateAfterReserveOutcome(params: {
  currentState: ProtectedTimeState;
  outcome: ProtectionAuthorizationOutcome;
  attemptNumber?: number;
}): ProtectedTimeState {
  const attemptNumber = Math.max(
    params.currentState.refillAttemptCount + 1,
    params.attemptNumber ?? 0
  );
  if (params.outcome === "AUTHORIZED") {
    return {
      protectedMinutesPurchased:
        params.currentState.protectedMinutesPurchased + REFILL_CHUNK_MINUTES,
      protectedMinutesRemaining:
        params.currentState.protectedMinutesRemaining + REFILL_CHUNK_MINUTES,
      consumedMinutes: params.currentState.consumedMinutes,
      refillAttemptCount: attemptNumber,
      lowFundsAt: null,
    };
  }

  return {
    protectedMinutesPurchased: params.currentState.protectedMinutesPurchased,
    protectedMinutesRemaining: params.currentState.protectedMinutesRemaining,
    consumedMinutes: params.currentState.consumedMinutes,
    refillAttemptCount: attemptNumber,
    lowFundsAt: params.currentState.lowFundsAt,
  };
}

function protectionPatch(
  state: ProtectedTimeState
): Record<string, unknown> {
  return {
    protectedMinutesPurchased: state.protectedMinutesPurchased,
    protectedMinutesRemaining: state.protectedMinutesRemaining,
    consumedMinutes: state.consumedMinutes,
    refillAttemptCount: state.refillAttemptCount,
    lowFundsAt: state.lowFundsAt ?
      admin.firestore.Timestamp.fromDate(state.lowFundsAt) :
      null,
  };
}

function classifyPeachResult(resultCode: string): AuthorizationOutcome {
  if (/^000\.200\./.test(resultCode)) {
    return "PENDING_PROVIDER";
  }
  if (/^(000\.000\.|000\.100\.1|000\.[36])/.test(resultCode)) {
    return "AUTHORIZED";
  }
  return "FAILED";
}

function classifyCaptureResult(resultCode: string): CaptureOutcome {
  const base = classifyPeachResult(resultCode);
  if (base === "AUTHORIZED") return "CAPTURED";
  if (base === "PENDING_PROVIDER") return "PENDING_PROVIDER";
  return "FAILED";
}

function buildTickId(billableMinutes: number): string {
  return `minute_${billableMinutes}`;
}

function buildCaptureId(params: {
  sessionId: string;
  billableMinutes: number;
  authorizationId: string;
  index: number;
}): string {
  const material = [
    params.sessionId,
    params.billableMinutes,
    params.authorizationId,
    params.index,
  ].join("|");
  return `pc_${createHash("sha256").update(material).digest("hex").slice(0, 32)}`;
}

function buildTopUpAuthorizationId(params: {
  sessionId: string;
  billableMinutes: number;
}): string {
  return `pa_${params.sessionId}_buffer_${params.billableMinutes}`;
}

function mapStoredAuthorizationStatusToOutcome(
  status: string
): AuthorizationOutcome | "SKIPPED" {
  if (status === AUTH_STATUS_AUTHORIZED) {
    return "AUTHORIZED";
  }
  if (status === AUTH_STATUS_PENDING_PROVIDER || status === AUTH_STATUS_INITIATING) {
    return "PENDING_PROVIDER";
  }
  if (status === AUTH_STATUS_FAILED) {
    return "FAILED";
  }
  return "SKIPPED";
}

function buildProviderResponseSnapshot(
  providerResponse: PeachApiResult | Record<string, unknown>,
  merchantTransactionId: string
): Record<string, unknown> {
  const response = providerResponse as PeachApiResult;
  return {
    paymentId: toTrimmedString(response.id),
    ndc: toTrimmedString(response.ndc),
    resultCode: toTrimmedString(response.result?.code),
    resultDescription: toTrimmedString(response.result?.description),
    merchantTransactionId:
      toTrimmedString(response.merchantTransactionId) || merchantTransactionId,
    timestamp: toTrimmedString(response.timestamp),
    registrationId: toTrimmedString(response.registrationId),
    raw: providerResponse,
  };
}

function getPaymentProviderContext(): PaymentProviderContext {
  return {
    provider: getActiveTutoringPaymentProvider(),
  };
}

async function createPeachCapture(params: {
  config: PaymentProviderContext;
  authorizationPaymentId: string;
  amountZar: number;
  merchantTransactionId: string;
  bookingId: string;
  paymentIntentId: string;
  sessionId: string;
}): Promise<PeachApiResult> {
  return params.config.provider.capture({
    authorizationId: "",
    bookingId: params.bookingId,
    paymentIntentId: params.paymentIntentId,
    sessionId: params.sessionId,
    amountZar: params.amountZar,
    currency: CURRENCY,
    merchantTransactionId: params.merchantTransactionId,
    authorizationProviderPaymentId: params.authorizationPaymentId,
  });
}

async function createPeachPreauthorization(params: {
  config: PaymentProviderContext;
  amountZar: number;
  registrationId: string;
  merchantTransactionId: string;
  bookingId: string;
  paymentIntentId: string;
  sessionId: string;
  studentId: string;
  tutorId: string;
}): Promise<PeachApiResult> {
  return params.config.provider.authorizeReserve({
    authorizationId: params.merchantTransactionId,
    bookingId: params.bookingId,
    paymentIntentId: params.paymentIntentId,
    sessionId: params.sessionId,
    studentId: params.studentId,
    tutorId: params.tutorId,
    amountZar: params.amountZar,
    currency: CURRENCY,
    merchantTransactionId: params.merchantTransactionId,
    paymentMethod: {
      paymentMethodId: "",
      paymentMethodType: "card",
      paymentMethodSummary: "Card",
      registrationId: params.registrationId,
      providerReference: params.registrationId,
      provider: PAYMENT_PROVIDER,
      isTemporary: false,
      brand: "Card",
      last4: "",
      holder: "Student",
      expMonth: 0,
      expYear: 0,
      mockCustomerCode: "",
      mockAuthorizationCode: "",
      mockAuthorizationReference: "",
      mockPreauthReference: "",
      reusableAuthorizationCode: "",
      reusable: true,
      status: "ready",
    },
  });
}

async function listTargetSessions(): Promise<admin.firestore.QueryDocumentSnapshot[]> {
  const [activeSnap, lowFundsSnap] = await Promise.all([
    db.collection("tutoring_sessions").where("status", "==", SESSION_ACTIVE).get(),
    db.collection("tutoring_sessions").where("status", "==", SESSION_LOW_FUNDS).get(),
  ]);

  const byId = new Map<string, admin.firestore.QueryDocumentSnapshot>();
  for (const doc of activeSnap.docs) byId.set(doc.id, doc);
  for (const doc of lowFundsSnap.docs) byId.set(doc.id, doc);
  return Array.from(byId.values());
}

async function prepareTick(
  sessionRef: admin.firestore.DocumentReference,
  now: Date
): Promise<SessionTickPreparation | null> {
  return db.runTransaction(async (tx) => {
    const sessionSnap = await tx.get(sessionRef);
    if (!sessionSnap.exists) return null;

    const sessionData = sessionSnap.data() ?? {};
    const status = toTrimmedString(sessionData.status);
    if (status !== SESSION_ACTIVE && status !== SESSION_LOW_FUNDS) {
      return null;
    }

    const sessionStartAt = timestampToDate(sessionData.sessionStartAt);
    if (!sessionStartAt) {
      return null;
    }

    const protectionState = deriveProtectedTimeState(
      sessionData as Record<string, unknown>,
      {} as Record<string, unknown>
    );
    const elapsedMs = Math.max(0, now.getTime() - sessionStartAt.getTime());
    const elapsedMinutes = Math.max(1, Math.ceil(elapsedMs / 60000));
    const billableMinutes = protectionState.protectedMinutesPurchased > 0 ?
      Math.min(elapsedMinutes, protectionState.protectedMinutesPurchased) :
      elapsedMinutes;
    const tickId = buildTickId(billableMinutes);
    const tickRef = sessionRef.collection("billing_ticks").doc(tickId);
    const bookingId = toTrimmedString(sessionData.bookingId) || sessionRef.id;
    const paymentIntentId =
      toTrimmedString(sessionData.paymentIntentId) || bookingId;
    const bookingRef = db.collection("tutor_requests").doc(bookingId);
    const paymentIntentRef = db
      .collection("session_payment_intents")
      .doc(paymentIntentId);

    const [tickSnap, bookingSnap, paymentIntentSnap] = await Promise.all([
      tx.get(tickRef),
      tx.get(bookingRef),
      tx.get(paymentIntentRef),
    ]);

    if (!bookingSnap.exists || !paymentIntentSnap.exists) {
      tx.set(tickRef, {
        tickId,
        billableMinutes,
        status: "SKIPPED_MISSING_REFERENCES",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      return null;
    }

    const tickData = tickSnap.data() ?? {};
    const tickStatus = toTrimmedString(tickData.status);
    if (["COMPLETED", "LOW_FUNDS", "ENDED", "SKIPPED"].includes(tickStatus)) {
      return null;
    }

    const lockUntil = timestampToDate(sessionData.billingLockExpiresAt);
    const lockTickId = toTrimmedString(sessionData.billingLockTickId);
    if (
      lockUntil &&
      lockUntil.getTime() > now.getTime() &&
      lockTickId &&
      lockTickId !== tickId
    ) {
      return null;
    }

    const bookingData = bookingSnap.data() ?? {};
    const paymentIntentData = paymentIntentSnap.data() ?? {};
    const mergedProtectionState = deriveProtectedTimeState(
      sessionData as Record<string, unknown>,
      paymentIntentData as Record<string, unknown>
    );
    const studentRatePerMinZar = asMoney(
      sessionData.studentRatePerMinZar,
      asMoney(
        bookingData.totalRatePerMinute,
        asMoney(paymentIntentData.totalRatePerMinute, 0)
      )
    );
    if (studentRatePerMinZar <= 0) {
      tx.set(tickRef, {
        tickId,
        billableMinutes,
        status: "SKIPPED_INVALID_RATE",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      return null;
    }

    const amountDueZar = toMoney(billableMinutes * studentRatePerMinZar);
    const lockExpiry = admin.firestore.Timestamp.fromDate(
      new Date(now.getTime() + BILLING_LOCK_MS)
    );

    tx.set(tickRef, {
      tickId,
      sessionId: sessionRef.id,
      bookingId,
      paymentIntentId,
      billableMinutes,
      amountDueZar,
      studentRatePerMinZar,
      status: "PROCESSING",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    tx.set(sessionRef, {
      billingLockTickId: tickId,
      billingLockExpiresAt: lockExpiry,
      lastBillingAttemptAt: admin.firestore.FieldValue.serverTimestamp(),
      billedMinutes: billableMinutes,
      amountDueZar,
      currency:
        toTrimmedString(sessionData.currency) ||
        toTrimmedString(bookingData.currency) ||
        toTrimmedString(paymentIntentData.currency) ||
        CURRENCY,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    return {
      sessionId: sessionRef.id,
      tickId,
      billableMinutes,
      amountDueZar,
      studentRatePerMinZar,
      paymentIntentId,
      bookingId,
      studentId: toTrimmedString(bookingData.studentId),
      tutorId: toTrimmedString(bookingData.tutorId),
      roomName:
        toTrimmedString(sessionData.roomName) ||
        toTrimmedString(bookingData.sessionRoomName),
      sessionStatus: status,
      sessionStartAt,
      lowFundsAt: mergedProtectionState.lowFundsAt,
      protectedMinutesPurchased: mergedProtectionState.protectedMinutesPurchased,
      protectedMinutesRemaining: mergedProtectionState.protectedMinutesRemaining,
      consumedMinutes: mergedProtectionState.consumedMinutes,
      refillAttemptCount: mergedProtectionState.refillAttemptCount,
      capturedTotalZar: asMoney(
        sessionData.capturedTotalZar,
        asMoney(paymentIntentData.capturedAmountZar, 0)
      ),
      pendingCaptureTotalZar: asMoney(
        sessionData.pendingCaptureTotalZar,
        asMoney(paymentIntentData.pendingCaptureTotalZar, 0)
      ),
      currency:
        toTrimmedString(sessionData.currency) ||
        toTrimmedString(bookingData.currency) ||
        toTrimmedString(paymentIntentData.currency) ||
        CURRENCY,
    };
  });
}

async function loadAuthorizations(
  bookingId: string
): Promise<AuthorizationState[]> {
  const snap = await db
    .collection("payment_authorizations")
    .where("bookingId", "==", bookingId)
    .get();

  return snap.docs.map((doc) => {
    const data = doc.data() ?? {};
    const amountZar = asMoney(data.amountZar, 0);
    const capturedAmountZar = asMoney(data.capturedAmountZar, 0);
    const pendingCaptureAmountZar = asMoney(data.pendingCaptureAmountZar, 0);
    return {
      ref: doc.ref,
      id: doc.id,
      data,
      amountZar,
      capturedAmountZar,
      pendingCaptureAmountZar,
      remainingAuthorizedZar: toMoney(
        Math.max(0, amountZar - capturedAmountZar - pendingCaptureAmountZar)
      ),
      status: toTrimmedString(data.status),
      providerPaymentId: toTrimmedString(toJSONObject(data.provider).paymentId),
      registrationId: toTrimmedString(toJSONObject(data.provider).registrationId),
      paymentMethodId: toTrimmedString(data.paymentMethodId),
      paymentMethodType: toTrimmedString(data.paymentMethodType) || "card",
      paymentMethodSummary: toTrimmedString(data.paymentMethodSummary),
    };
  }).sort((left, right) => left.id.localeCompare(right.id));
}

export async function createInitialProtection(
  sessionId: string
): Promise<ProtectedTimeState> {
  const sessionRef = db.collection("tutoring_sessions").doc(sessionId);
  const bookingRef = db.collection("tutor_requests").doc(sessionId);
  const paymentIntentRef = db.collection("session_payment_intents").doc(sessionId);

  return db.runTransaction(async (tx) => {
    const [sessionSnap, bookingSnap, paymentIntentSnap] = await Promise.all([
      tx.get(sessionRef),
      tx.get(bookingRef),
      tx.get(paymentIntentRef),
    ]);
    if (!sessionSnap.exists || !bookingSnap.exists || !paymentIntentSnap.exists) {
      throw new Error("Cannot create initial tutoring protection without session references.");
    }

    const sessionData = sessionSnap.data() ?? {};
    const paymentIntentData = paymentIntentSnap.data() ?? {};
    const existingState = deriveProtectedTimeState(
      sessionData as Record<string, unknown>,
      paymentIntentData as Record<string, unknown>
    );
    if (existingState.protectedMinutesPurchased > 0) {
      return existingState;
    }

    const initialState: ProtectedTimeState = {
      protectedMinutesPurchased: INITIAL_BUFFER_MINUTES,
      protectedMinutesRemaining: INITIAL_BUFFER_MINUTES,
      consumedMinutes: 0,
      refillAttemptCount: 0,
      lowFundsAt: null,
    };
    tx.set(sessionRef, {
      ...protectionPatch(initialState),
      initialProtectionMinutes: INITIAL_BUFFER_MINUTES,
      protectionRefillThresholdMinutes: REFILL_THRESHOLD_MINUTES,
      protectionRefillChunkMinutes: REFILL_CHUNK_MINUTES,
      protectionInitializedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    tx.set(paymentIntentRef, {
      ...protectionPatch(initialState),
      initialProtectionMinutes: INITIAL_BUFFER_MINUTES,
      protectionRefillThresholdMinutes: REFILL_THRESHOLD_MINUTES,
      protectionRefillChunkMinutes: REFILL_CHUNK_MINUTES,
      protectionInitializedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    tx.set(bookingRef, {
      protectedMinutesPurchased: initialState.protectedMinutesPurchased,
      protectedMinutesRemaining: initialState.protectedMinutesRemaining,
      consumedMinutes: initialState.consumedMinutes,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    return initialState;
  });
}

export async function consumeProtectionTick(
  sessionId: string,
  now: Date = new Date()
): Promise<ProtectedTimeState> {
  await createInitialProtection(sessionId);
  const sessionRef = db.collection("tutoring_sessions").doc(sessionId);
  const paymentIntentRef = db.collection("session_payment_intents").doc(sessionId);
  const bookingRef = db.collection("tutor_requests").doc(sessionId);

  return db.runTransaction(async (tx) => {
    const [sessionSnap, paymentIntentSnap, bookingSnap] = await Promise.all([
      tx.get(sessionRef),
      tx.get(paymentIntentRef),
      tx.get(bookingRef),
    ]);
    if (!sessionSnap.exists || !paymentIntentSnap.exists || !bookingSnap.exists) {
      throw new Error("Cannot consume tutoring protection without session references.");
    }

    const sessionData = sessionSnap.data() ?? {};
    const paymentIntentData = paymentIntentSnap.data() ?? {};
    const currentState = deriveProtectedTimeState(
      sessionData as Record<string, unknown>,
      paymentIntentData as Record<string, unknown>
    );
    const sessionStartAt = timestampToDate(
      sessionData.sessionStartAt ?? paymentIntentData.sessionStartAt
    );
    if (!sessionStartAt) {
      return currentState;
    }

    const elapsedMinutes = Math.max(
      1,
      Math.ceil(Math.max(0, now.getTime() - sessionStartAt.getTime()) / 60000)
    );
    const nextConsumedMinutes = Math.min(
      currentState.protectedMinutesPurchased,
      elapsedMinutes
    );
    if (nextConsumedMinutes <= currentState.consumedMinutes) {
      return currentState;
    }

    const nextState: ProtectedTimeState = {
      ...currentState,
      consumedMinutes: nextConsumedMinutes,
      protectedMinutesRemaining: Math.max(
        0,
        currentState.protectedMinutesPurchased - nextConsumedMinutes
      ),
    };
    tx.set(sessionRef, {
      ...protectionPatch(nextState),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    tx.set(paymentIntentRef, {
      ...protectionPatch(nextState),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    tx.set(bookingRef, {
      protectedMinutesPurchased: nextState.protectedMinutesPurchased,
      protectedMinutesRemaining: nextState.protectedMinutesRemaining,
      consumedMinutes: nextState.consumedMinutes,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    return nextState;
  });
}

export async function reserveMoreProtection(
  sessionId: string
): Promise<TopUpAuthorizationResult & ProtectedTimeState> {
  await createInitialProtection(sessionId);
  const sessionRef = db.collection("tutoring_sessions").doc(sessionId);
  const bookingRef = db.collection("tutor_requests").doc(sessionId);
  const paymentIntentRef = db.collection("session_payment_intents").doc(sessionId);
  const [sessionSnap, bookingSnap, paymentIntentSnap] = await Promise.all([
    sessionRef.get(),
    bookingRef.get(),
    paymentIntentRef.get(),
  ]);
  if (!sessionSnap.exists || !bookingSnap.exists || !paymentIntentSnap.exists) {
    throw new Error("Cannot reserve tutoring protection without session references.");
  }

  const sessionData = sessionSnap.data() ?? {};
  const bookingData = bookingSnap.data() ?? {};
  const paymentIntentData = paymentIntentSnap.data() ?? {};
  const currentState = deriveProtectedTimeState(
    sessionData as Record<string, unknown>,
    paymentIntentData as Record<string, unknown>
  );
  if (currentState.protectedMinutesRemaining > REFILL_THRESHOLD_MINUTES) {
    return {
      ...currentState,
      authorizationId: "",
      status: "SKIPPED",
      newlyAvailableAmountZar: 0,
    };
  }

  const authorizations = await loadAuthorizations(bookingRef.id);
  const protectionSourceConsumedMinutes = Math.max(1, currentState.consumedMinutes);
  const authorizationId = buildTopUpAuthorizationId({
    sessionId,
    billableMinutes: protectionSourceConsumedMinutes,
  });
  const authorizationRef = db.collection("payment_authorizations").doc(authorizationId);
  const existingTopUpAuthorization = authorizations.find((authorization) =>
    authorization.id === authorizationId
  );
  if (existingTopUpAuthorization) {
    return {
      ...currentState,
      authorizationId: existingTopUpAuthorization.id,
      status: mapStoredAuthorizationStatusToOutcome(existingTopUpAuthorization.status),
      newlyAvailableAmountZar:
        existingTopUpAuthorization.status === AUTH_STATUS_AUTHORIZED ?
          asMoney(existingTopUpAuthorization.data.amountZar, 0) :
          0,
    };
  }
  const sourceAuthorization = authorizations.find((authorization) =>
    authorization.registrationId && authorization.paymentMethodId
  );
  const studentRatePerMinZar = asMoney(
    sessionData.studentRatePerMinZar,
    asMoney(
      bookingData.totalRatePerMinute,
      asMoney(paymentIntentData.totalRatePerMinute, 0)
    )
  );
  const attemptNumber = currentState.refillAttemptCount + 1;
  if (!sourceAuthorization || studentRatePerMinZar <= 0) {
    const failedState: ProtectedTimeState = {
      ...currentState,
      refillAttemptCount: attemptNumber,
    };
    const failedAuthorizationBase = {
      authorizationId,
      bookingId: bookingRef.id,
      paymentIntentId: paymentIntentRef.id,
      sessionId,
      studentId: toTrimmedString(bookingData.studentId),
      tutorId: toTrimmedString(bookingData.tutorId),
      amountZar: 0,
      amountCents: 0,
      currency: CURRENCY,
      status: AUTH_STATUS_FAILED,
      type: "PREAUTH_TOP_UP",
      reason: "BUFFER_TOP_UP_UNAVAILABLE",
      protectionMinutesGranted: 0,
      protectionSourceConsumedMinutes,
      protectionRefillAttemptNumber: attemptNumber,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      failedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    await db.runTransaction(async (tx) => {
      tx.set(authorizationRef, {
        ...failedAuthorizationBase,
        ...buildPaymentAuthorizationSchemaFields(
          authorizationId,
          failedAuthorizationBase
        ),
      }, {merge: true});
      tx.set(sessionRef, {
        ...protectionPatch(failedState),
        latestProtectionAuthorizationId: authorizationId,
        latestProtectionAuthorizationStatus: AUTH_STATUS_FAILED,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      tx.set(paymentIntentRef, {
        ...protectionPatch(failedState),
        latestProtectionAuthorizationId: authorizationId,
        latestProtectionAuthorizationStatus: AUTH_STATUS_FAILED,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      tx.set(bookingRef, {
        protectedMinutesPurchased: failedState.protectedMinutesPurchased,
        protectedMinutesRemaining: failedState.protectedMinutesRemaining,
        consumedMinutes: failedState.consumedMinutes,
        latestProtectionAuthorizationId: authorizationId,
        latestProtectionAuthorizationStatus: AUTH_STATUS_FAILED,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    });
    return {
      ...failedState,
      authorizationId,
      status: "FAILED",
      newlyAvailableAmountZar: 0,
    };
  }
  const topUpAmountZar = toMoney(REFILL_CHUNK_MINUTES * studentRatePerMinZar);
  await authorizationRef.set({
    ...(() => {
      const authorizationBase = {
        authorizationId,
        bookingId: bookingRef.id,
        paymentIntentId: paymentIntentRef.id,
        sessionId,
        studentId: toTrimmedString(bookingData.studentId),
        tutorId: toTrimmedString(bookingData.tutorId),
        amountZar: topUpAmountZar,
        amountCents: Math.round(topUpAmountZar * 100),
        currency: CURRENCY,
        status: AUTH_STATUS_INITIATING,
        type: "PREAUTH_TOP_UP",
        reason: "BUFFER_TOP_UP",
        paymentMethodId: sourceAuthorization.paymentMethodId,
        paymentMethodType: sourceAuthorization.paymentMethodType,
        paymentMethodSummary: sourceAuthorization.paymentMethodSummary,
        protectionMinutesGranted: 0,
        protectionSourceConsumedMinutes,
        protectionRefillAttemptNumber: attemptNumber,
        provider: {
          ...toJSONObject(sourceAuthorization.data.provider),
          name: PAYMENT_PROVIDER,
          registrationId: sourceAuthorization.registrationId,
          merchantTransactionId: authorizationId,
        },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      return {
        ...authorizationBase,
        ...buildPaymentAuthorizationSchemaFields(authorizationId, authorizationBase),
      };
    })(),
  }, {merge: true});
  const providerResponse = await createPeachPreauthorization({
    config: getPaymentProviderContext(),
    amountZar: topUpAmountZar,
    registrationId: sourceAuthorization.registrationId,
    merchantTransactionId: authorizationId,
    bookingId: bookingRef.id,
    paymentIntentId: paymentIntentRef.id,
    sessionId,
    studentId: toTrimmedString(bookingData.studentId),
    tutorId: toTrimmedString(bookingData.tutorId),
  });
  const providerSnapshot = buildProviderResponseSnapshot(
    providerResponse,
    authorizationId
  );
  const outcome = classifyPeachResult(toTrimmedString(providerSnapshot.resultCode));
  const storedStatus = outcome === "AUTHORIZED" ?
    AUTH_STATUS_AUTHORIZED :
    outcome === "PENDING_PROVIDER" ?
      AUTH_STATUS_PENDING_PROVIDER :
      AUTH_STATUS_FAILED;
  const nextState: ProtectedTimeState = {
    protectedMinutesPurchased: currentState.protectedMinutesPurchased +
      (outcome === "AUTHORIZED" ? REFILL_CHUNK_MINUTES : 0),
    protectedMinutesRemaining: currentState.protectedMinutesRemaining +
      (outcome === "AUTHORIZED" ? REFILL_CHUNK_MINUTES : 0),
    consumedMinutes: currentState.consumedMinutes,
    refillAttemptCount: attemptNumber,
    lowFundsAt: outcome === "AUTHORIZED" ? null : currentState.lowFundsAt,
  };
  const authorizationBase = {
    authorizationId,
    bookingId: bookingRef.id,
    paymentIntentId: paymentIntentRef.id,
    sessionId,
    studentId: toTrimmedString(bookingData.studentId),
    tutorId: toTrimmedString(bookingData.tutorId),
    amountZar: topUpAmountZar,
    amountCents: Math.round(topUpAmountZar * 100),
    currency: CURRENCY,
    status: storedStatus,
    type: "PREAUTH_TOP_UP",
    reason: "BUFFER_TOP_UP",
    paymentMethodId: sourceAuthorization.paymentMethodId,
    paymentMethodType: sourceAuthorization.paymentMethodType,
    paymentMethodSummary: sourceAuthorization.paymentMethodSummary,
    protectionMinutesGranted: outcome === "AUTHORIZED" ? REFILL_CHUNK_MINUTES : 0,
    protectionSourceConsumedMinutes,
    protectionRefillAttemptNumber: attemptNumber,
    provider: {
      ...toJSONObject(sourceAuthorization.data.provider),
      name: PAYMENT_PROVIDER,
      registrationId: sourceAuthorization.registrationId,
      merchantTransactionId: authorizationId,
      ...providerSnapshot,
    },
    authorizedAt: outcome === "AUTHORIZED" ?
      admin.firestore.FieldValue.serverTimestamp() : undefined,
    failedAt: outcome === "FAILED" ?
      admin.firestore.FieldValue.serverTimestamp() : undefined,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  await db.runTransaction(async (tx) => {
    tx.set(authorizationRef, {
      ...authorizationBase,
      ...buildPaymentAuthorizationSchemaFields(authorizationId, authorizationBase),
    }, {merge: true});
    tx.set(sessionRef, {
      ...protectionPatch(nextState),
      latestProtectionAuthorizationId: authorizationId,
      latestProtectionAuthorizationStatus: storedStatus,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    tx.set(paymentIntentRef, {
      ...protectionPatch(nextState),
      latestProtectionAuthorizationId: authorizationId,
      latestProtectionAuthorizationStatus: storedStatus,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    tx.set(bookingRef, {
      protectedMinutesPurchased: nextState.protectedMinutesPurchased,
      protectedMinutesRemaining: nextState.protectedMinutesRemaining,
      consumedMinutes: nextState.consumedMinutes,
      latestProtectionAuthorizationId: authorizationId,
      latestProtectionAuthorizationStatus: storedStatus,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  });

  return {
    ...nextState,
    authorizationId,
    status: outcome,
    newlyAvailableAmountZar: outcome === "AUTHORIZED" ? topUpAmountZar : 0,
  };
}

export async function enterLowFundsState(
  sessionId: string,
  now: Date = new Date()
): Promise<ProtectedTimeState> {
  const sessionRef = db.collection("tutoring_sessions").doc(sessionId);
  const bookingRef = db.collection("tutor_requests").doc(sessionId);
  const paymentIntentRef = db.collection("session_payment_intents").doc(sessionId);

  return db.runTransaction(async (tx) => {
    const [sessionSnap, bookingSnap, paymentIntentSnap] = await Promise.all([
      tx.get(sessionRef),
      tx.get(bookingRef),
      tx.get(paymentIntentRef),
    ]);
    if (!sessionSnap.exists || !bookingSnap.exists || !paymentIntentSnap.exists) {
      throw new Error("Cannot enter low funds without session references.");
    }

    const sessionData = sessionSnap.data() ?? {};
    const bookingData = bookingSnap.data() ?? {};
    const paymentIntentData = paymentIntentSnap.data() ?? {};
    const currentState = deriveProtectedTimeState(
      sessionData as Record<string, unknown>,
      paymentIntentData as Record<string, unknown>
    );
    const nextLowFundsAt = currentState.lowFundsAt ?? now;
    const sessionStartAt = timestampToDate(
      sessionData.sessionStartAt ?? paymentIntentData.sessionStartAt
    );
    const lowFundsNotification = buildLowFundsNotificationPayload({
      now,
      sessionStartAt,
      protectedMinutesPurchased: currentState.protectedMinutesPurchased,
      protectedMinutesRemaining: currentState.protectedMinutesRemaining,
      consumedMinutes: currentState.consumedMinutes,
      refillAttemptCount: currentState.refillAttemptCount,
      lowFundsAt: nextLowFundsAt,
      state: "low_funds",
      reason: "reserve_refill_failed",
    });
    const exhaustionAt = lowFundsNotification.countdownEndsAtIso ?
      new Date(lowFundsNotification.countdownEndsAtIso) :
      nextLowFundsAt;
    const guestTutoringMode =
      bookingData.guestTutoringMode === true ||
      bookingData.payerType === "guest" ||
      sessionData.guestTutoringMode === true;
    assertSessionState({
      current: deriveTutoringSessionState(sessionData as Record<string, unknown>),
      next: TutoringSessionState.LOW_FUNDS,
      actor: TutoringTransitionActor.BILLING,
      isGuestSession: guestTutoringMode,
    });
    assertBookingState({
      current: deriveTutoringBookingState(bookingData as Record<string, unknown>),
      next: TutoringBookingState.IN_PROGRESS,
      actor: TutoringTransitionActor.SYSTEM,
      isGuestSession: guestTutoringMode,
    });

    const nextState: ProtectedTimeState = {
      ...currentState,
      lowFundsAt: nextLowFundsAt,
    };
    tx.set(sessionRef, {
      ...protectionPatch(nextState),
      status: SESSION_LOW_FUNDS,
      sessionLifecycleState: TutoringSessionState.LOW_FUNDS,
      lowFundsNotification,
      lowFundsGraceEndsAt: admin.firestore.Timestamp.fromDate(exhaustionAt),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    tx.set(paymentIntentRef, {
      ...protectionPatch(nextState),
      sessionStatus: SESSION_LOW_FUNDS,
      sessionLifecycleState: TutoringSessionState.LOW_FUNDS,
      lowFundsNotification,
      lowFundsGraceEndsAt: admin.firestore.Timestamp.fromDate(exhaustionAt),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    tx.set(bookingRef, {
      protectedMinutesPurchased: nextState.protectedMinutesPurchased,
      protectedMinutesRemaining: nextState.protectedMinutesRemaining,
      consumedMinutes: nextState.consumedMinutes,
      lowFundsAt: admin.firestore.Timestamp.fromDate(nextLowFundsAt),
      lowFundsNotification,
      sessionState: "low_funds",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    return nextState;
  });
}

export async function endSessionForInsufficientFunds(
  sessionId: string,
  now: Date = new Date()
): Promise<ProtectedTimeState> {
  await forceEndRoom(sessionId);
  const sessionRef = db.collection("tutoring_sessions").doc(sessionId);
  const bookingRef = db.collection("tutor_requests").doc(sessionId);
  const paymentIntentRef = db.collection("session_payment_intents").doc(sessionId);

  return db.runTransaction(async (tx) => {
    const [sessionSnap, bookingSnap, paymentIntentSnap] = await Promise.all([
      tx.get(sessionRef),
      tx.get(bookingRef),
      tx.get(paymentIntentRef),
    ]);
    if (!sessionSnap.exists || !bookingSnap.exists || !paymentIntentSnap.exists) {
      throw new Error("Cannot end session for insufficient funds without session references.");
    }

    const sessionData = sessionSnap.data() ?? {};
    const bookingData = bookingSnap.data() ?? {};
    const paymentIntentData = paymentIntentSnap.data() ?? {};
    const currentState = deriveProtectedTimeState(
      sessionData as Record<string, unknown>,
      paymentIntentData as Record<string, unknown>
    );
    const guestTutoringMode =
      bookingData.guestTutoringMode === true ||
      bookingData.payerType === "guest" ||
      sessionData.guestTutoringMode === true;
    const nextState: ProtectedTimeState = {
      ...currentState,
      protectedMinutesRemaining: 0,
      lowFundsAt: currentState.lowFundsAt ?? now,
    };
    const sessionStartAt = timestampToDate(
      sessionData.sessionStartAt ?? paymentIntentData.sessionStartAt
    );
    const lowFundsNotification = buildLowFundsNotificationPayload({
      now,
      sessionStartAt,
      protectedMinutesPurchased: nextState.protectedMinutesPurchased,
      protectedMinutesRemaining: 0,
      consumedMinutes: nextState.consumedMinutes,
      refillAttemptCount: nextState.refillAttemptCount,
      lowFundsAt: nextState.lowFundsAt,
      state: "ended_insufficient_funds",
      reason: "protected_time_exhausted",
    });
    assertSessionState({
      current: deriveTutoringSessionState(sessionData as Record<string, unknown>),
      next: TutoringSessionState.ENDED_INSUFFICIENT_FUNDS,
      actor: TutoringTransitionActor.BILLING,
      isGuestSession: guestTutoringMode,
      reason: "insufficient_funds",
    });
    assertBookingState({
      current: deriveTutoringBookingState(bookingData as Record<string, unknown>),
      next: TutoringBookingState.ENDED_INSUFFICIENT_FUNDS,
      actor: TutoringTransitionActor.BILLING,
      isGuestSession: guestTutoringMode,
      reason: "insufficient_funds",
    });

    tx.set(sessionRef, {
      ...protectionPatch(nextState),
      status: SESSION_ENDED_INSUFFICIENT_FUNDS,
      sessionLifecycleState: TutoringSessionState.ENDED_INSUFFICIENT_FUNDS,
      sessionTerminalState: TutoringSessionState.ENDED_INSUFFICIENT_FUNDS,
      lowFundsNotification,
      endedAt: admin.firestore.FieldValue.serverTimestamp(),
      endedReason: "insufficient_funds",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    tx.set(paymentIntentRef, {
      ...protectionPatch(nextState),
      sessionStatus: SESSION_ENDED_INSUFFICIENT_FUNDS,
      sessionLifecycleState: TutoringSessionState.ENDED_INSUFFICIENT_FUNDS,
      sessionTerminalState: TutoringSessionState.ENDED_INSUFFICIENT_FUNDS,
      lowFundsNotification,
      endedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    tx.set(bookingRef, {
      protectedMinutesPurchased: nextState.protectedMinutesPurchased,
      protectedMinutesRemaining: nextState.protectedMinutesRemaining,
      consumedMinutes: nextState.consumedMinutes,
      bookingState: TutoringBookingState.ENDED_INSUFFICIENT_FUNDS,
      sessionState: "ended_insufficient_funds",
      lowFundsAt: admin.firestore.Timestamp.fromDate(nextState.lowFundsAt ?? new Date()),
      lowFundsNotification,
      endedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    return nextState;
  });
}

async function recordCaptureOutcome(params: {
  sessionRef: admin.firestore.DocumentReference;
  bookingRef: admin.firestore.DocumentReference;
  paymentIntentRef: admin.firestore.DocumentReference;
  authorization: AuthorizationState;
  captureId: string;
  amountZar: number;
  providerSnapshot: Record<string, unknown>;
  outcome: CaptureOutcome;
  tickId: string;
}): Promise<CaptureExecutionResult> {
  const captureRef = db.collection("payment_captures").doc(params.captureId);
  const accountedAmountZar =
    params.outcome === "FAILED" ? 0 : params.amountZar;

  return db.runTransaction(async (tx) => {
    const captureSnap = await tx.get(captureRef);
    if (captureSnap.exists) {
      const existing = captureSnap.data() ?? {};
      const existingStatus = toTrimmedString(existing.status);
      if (["CAPTURED", "PENDING_PROVIDER", "FAILED"].includes(existingStatus)) {
        return {
          captureId: params.captureId,
          status: existingStatus as CaptureOutcome,
          accountedAmountZar: asMoney(existing.accountedAmountZar, 0),
        };
      }
    }

    const captureBase = {
      captureId: params.captureId,
      tutoringPaymentRail: "TUTORING",
      authorizationId: params.authorization.id,
      bookingId: params.bookingRef.id,
      paymentIntentId: params.paymentIntentRef.id,
      sessionId: params.sessionRef.id,
      tickId: params.tickId,
      amountZar: params.amountZar,
      accountedAmountZar,
      status: params.outcome,
      provider: params.providerSnapshot,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(params.outcome === "CAPTURED" ? {
        capturedAt: admin.firestore.FieldValue.serverTimestamp(),
      } : {}),
      ...(params.outcome === "FAILED" ? {
        failedAt: admin.firestore.FieldValue.serverTimestamp(),
      } : {}),
    };

    tx.set(captureRef, {
      ...captureBase,
      ...buildCaptureSchemaFields(params.captureId, captureBase),
    }, {merge: true});

    tx.set(params.authorization.ref, {
      capturedAmountZar: admin.firestore.FieldValue.increment(
        params.outcome === "CAPTURED" ? params.amountZar : 0
      ),
      pendingCaptureAmountZar: admin.firestore.FieldValue.increment(
        params.outcome === "PENDING_PROVIDER" ? params.amountZar : 0
      ),
      lastCaptureId: params.captureId,
      lastCaptureStatus: params.outcome,
      lastCaptureAmountZar: params.amountZar,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    tx.set(params.sessionRef, {
      capturedTotalZar: admin.firestore.FieldValue.increment(
        params.outcome === "CAPTURED" ? params.amountZar : 0
      ),
      pendingCaptureTotalZar: admin.firestore.FieldValue.increment(
        params.outcome === "PENDING_PROVIDER" ? params.amountZar : 0
      ),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    tx.set(params.bookingRef, {
      capturedAmountZar: admin.firestore.FieldValue.increment(
        params.outcome === "CAPTURED" ? params.amountZar : 0
      ),
      pendingCaptureTotalZar: admin.firestore.FieldValue.increment(
        params.outcome === "PENDING_PROVIDER" ? params.amountZar : 0
      ),
      providerCaptureId: params.captureId,
      providerCaptureStatus: params.outcome,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    tx.set(params.paymentIntentRef, {
      capturedAmountZar: admin.firestore.FieldValue.increment(
        params.outcome === "CAPTURED" ? params.amountZar : 0
      ),
      pendingCaptureTotalZar: admin.firestore.FieldValue.increment(
        params.outcome === "PENDING_PROVIDER" ? params.amountZar : 0
      ),
      providerCaptureId: params.captureId,
      providerCaptureStatus: params.outcome,
      latestCaptureId: params.captureId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    return {
      captureId: params.captureId,
      status: params.outcome,
      accountedAmountZar,
    };
  });
}

async function captureAgainstAuthorization(params: {
  config: PaymentProviderContext;
  sessionRef: admin.firestore.DocumentReference;
  bookingRef: admin.firestore.DocumentReference;
  paymentIntentRef: admin.firestore.DocumentReference;
  authorization: AuthorizationState;
  billableMinutes: number;
  captureIndex: number;
  amountZar: number;
  tickId: string;
}): Promise<CaptureExecutionResult> {
  const captureId = buildCaptureId({
    sessionId: params.sessionRef.id,
    billableMinutes: params.billableMinutes,
    authorizationId: params.authorization.id,
    index: params.captureIndex,
  });

  if (!params.authorization.providerPaymentId) {
    return recordCaptureOutcome({
      sessionRef: params.sessionRef,
      bookingRef: params.bookingRef,
      paymentIntentRef: params.paymentIntentRef,
      authorization: params.authorization,
      captureId,
      amountZar: params.amountZar,
      providerSnapshot: {
        resultCode: "missing_authorization_payment_id",
        resultDescription: "Authorization is missing a Peach payment identifier.",
      },
      outcome: "FAILED",
      tickId: params.tickId,
    });
  }

  try {
    const providerResponse = await createPeachCapture({
      config: params.config,
      authorizationPaymentId: params.authorization.providerPaymentId,
      amountZar: params.amountZar,
      merchantTransactionId: captureId,
      bookingId: params.bookingRef.id,
      paymentIntentId: params.paymentIntentRef.id,
      sessionId: params.sessionRef.id,
    });

    const snapshot = buildProviderResponseSnapshot(providerResponse, captureId);
    const outcome = classifyCaptureResult(toTrimmedString(snapshot.resultCode));
    return recordCaptureOutcome({
      sessionRef: params.sessionRef,
      bookingRef: params.bookingRef,
      paymentIntentRef: params.paymentIntentRef,
      authorization: params.authorization,
      captureId,
      amountZar: params.amountZar,
      providerSnapshot: snapshot,
      outcome,
      tickId: params.tickId,
    });
  } catch (error) {
    const snapshot = buildProviderResponseSnapshot({}, captureId);
    const outcome: CaptureOutcome = "FAILED";

    return recordCaptureOutcome({
      sessionRef: params.sessionRef,
      bookingRef: params.bookingRef,
      paymentIntentRef: params.paymentIntentRef,
      authorization: params.authorization,
      captureId,
      amountZar: params.amountZar,
      providerSnapshot: {
        ...snapshot,
        resultCode: toTrimmedString(snapshot.resultCode) || "provider_error",
        resultDescription: toTrimmedString(snapshot.resultDescription) ||
          (error instanceof Error ? error.message : "Capture failed."),
      },
      outcome,
      tickId: params.tickId,
    });
  }
}

async function recordTopUpAuthorization(params: {
  sessionRef: admin.firestore.DocumentReference;
  bookingRef: admin.firestore.DocumentReference;
  paymentIntentRef: admin.firestore.DocumentReference;
  authorizationRef: admin.firestore.DocumentReference;
  studentId: string;
  tutorId: string;
  registrationId: string;
  paymentMethodId: string;
  paymentMethodType: string;
  paymentMethodSummary: string;
  amountZar: number;
  outcome: AuthorizationOutcome;
  providerSnapshot: Record<string, unknown>;
  tickId: string;
}): Promise<TopUpAuthorizationResult> {
  return db.runTransaction(async (tx) => {
    const authSnap = await tx.get(params.authorizationRef);
    const existing = authSnap.data() ?? {};
    const existingStatus = toTrimmedString(existing.status);
    if ([AUTH_STATUS_AUTHORIZED, AUTH_STATUS_PENDING_PROVIDER, AUTH_STATUS_FAILED].includes(existingStatus)) {
      return {
        authorizationId: params.authorizationRef.id,
        status: existingStatus as AuthorizationOutcome,
        newlyAvailableAmountZar: existingStatus === AUTH_STATUS_AUTHORIZED ?
          asMoney(existing.amountZar, 0) : 0,
      };
    }

    const providerData = {
      ...toJSONObject(existing.provider),
      ...params.providerSnapshot,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    const storedStatus = params.outcome === "AUTHORIZED" ?
      AUTH_STATUS_AUTHORIZED :
      params.outcome === "PENDING_PROVIDER" ?
        AUTH_STATUS_PENDING_PROVIDER :
        AUTH_STATUS_FAILED;

    const authorizationBase = {
      authorizationId: params.authorizationRef.id,
      tutoringPaymentRail: "TUTORING",
      bookingId: params.bookingRef.id,
      paymentIntentId: params.paymentIntentRef.id,
      studentId: params.studentId,
      tutorId: params.tutorId,
      amountZar: params.amountZar,
      amountCents: Math.round(params.amountZar * 100),
      currency: CURRENCY,
      status: storedStatus,
      type: "PREAUTH_TOP_UP",
      reason: "BUFFER_TOP_UP",
      paymentMethodId: params.paymentMethodId,
      paymentMethodType: params.paymentMethodType,
      paymentMethodSummary: params.paymentMethodSummary,
      provider: {
        name: PAYMENT_PROVIDER,
        registrationId: params.registrationId,
        ...providerData,
      },
      createdFromTickId: params.tickId,
      authorizedAt: params.outcome === "AUTHORIZED" ?
        admin.firestore.FieldValue.serverTimestamp() : undefined,
      failedAt: params.outcome === "FAILED" ?
        admin.firestore.FieldValue.serverTimestamp() : undefined,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    tx.set(params.authorizationRef, {
      ...authorizationBase,
      ...buildPaymentAuthorizationSchemaFields(
        params.authorizationRef.id,
        authorizationBase
      ),
    }, {merge: true});

    tx.set(params.sessionRef, {
      latestTopUpAuthorizationId: params.authorizationRef.id,
      latestTopUpAuthorizationStatus: storedStatus,
      authorizationBufferPendingZar: admin.firestore.FieldValue.increment(
        params.outcome === "PENDING_PROVIDER" ? params.amountZar : 0
      ),
      authorizationBufferAuthorizedZar: admin.firestore.FieldValue.increment(
        params.outcome === "AUTHORIZED" ? params.amountZar : 0
      ),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    tx.set(params.bookingRef, {
      latestTopUpAuthorizationId: params.authorizationRef.id,
      latestTopUpAuthorizationStatus: storedStatus,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    tx.set(params.paymentIntentRef, {
      latestTopUpAuthorizationId: params.authorizationRef.id,
      latestTopUpAuthorizationStatus: storedStatus,
      latestAuthorizationId: params.authorizationRef.id,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    return {
      authorizationId: params.authorizationRef.id,
      status: params.outcome,
      newlyAvailableAmountZar: params.outcome === "AUTHORIZED" ?
        params.amountZar : 0,
    };
  });
}

export async function ensureBufferAuthorization(params: {
  config: PaymentProviderContext;
  sessionRef: admin.firestore.DocumentReference;
  bookingRef: admin.firestore.DocumentReference;
  paymentIntentRef: admin.firestore.DocumentReference;
  tickId: string;
  billableMinutes: number;
  studentRatePerMinZar: number;
  studentId: string;
  tutorId: string;
  authorizations: AuthorizationState[];
}): Promise<TopUpAuthorizationResult> {
  const existingTopUp = params.authorizations.find((authorization) => {
    const type = toTrimmedString(authorization.data.type);
    return type === "PREAUTH_TOP_UP" &&
      [AUTH_STATUS_INITIATING, AUTH_STATUS_PENDING_PROVIDER, AUTH_STATUS_AUTHORIZED].includes(authorization.status);
  });
  if (existingTopUp) {
    return {
      authorizationId: existingTopUp.id,
      status: "SKIPPED",
      newlyAvailableAmountZar: 0,
    };
  }

  const sourceAuthorization = params.authorizations.find((authorization) =>
    authorization.registrationId && authorization.paymentMethodId
  );
  if (!sourceAuthorization) {
    return {
      authorizationId: "",
      status: "FAILED",
      newlyAvailableAmountZar: 0,
    };
  }

  const topUpAmountZar = toMoney(
    REFILL_CHUNK_MINUTES * params.studentRatePerMinZar
  );
  const authorizationId = buildTopUpAuthorizationId({
    sessionId: params.sessionRef.id,
    billableMinutes: params.billableMinutes,
  });
  const authorizationRef = db.collection("payment_authorizations").doc(authorizationId);

  await authorizationRef.set({
    ...(() => {
      const authorizationBase = {
        authorizationId,
        bookingId: params.bookingRef.id,
        paymentIntentId: params.paymentIntentRef.id,
        studentId: params.studentId,
        tutorId: params.tutorId,
        amountZar: topUpAmountZar,
        amountCents: Math.round(topUpAmountZar * 100),
        currency: CURRENCY,
        status: AUTH_STATUS_INITIATING,
        type: "PREAUTH_TOP_UP",
        reason: "BUFFER_TOP_UP",
        paymentMethodId: sourceAuthorization.paymentMethodId,
        paymentMethodType: sourceAuthorization.paymentMethodType,
        paymentMethodSummary: sourceAuthorization.paymentMethodSummary,
        provider: {
          ...toJSONObject(sourceAuthorization.data.provider),
          name: PAYMENT_PROVIDER,
          registrationId: sourceAuthorization.registrationId,
          merchantTransactionId: authorizationId,
        },
        createdFromTickId: params.tickId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      return {
        ...authorizationBase,
        ...buildPaymentAuthorizationSchemaFields(authorizationId, authorizationBase),
      };
    })(),
  }, {merge: true});

  try {
    const providerResponse = await createPeachPreauthorization({
      config: params.config,
      amountZar: topUpAmountZar,
      registrationId: sourceAuthorization.registrationId,
      merchantTransactionId: authorizationId,
      bookingId: params.bookingRef.id,
      paymentIntentId: params.paymentIntentRef.id,
      sessionId: params.sessionRef.id,
      studentId: params.studentId,
      tutorId: params.tutorId,
    });
    const snapshot = buildProviderResponseSnapshot(providerResponse, authorizationId);
    const outcome = classifyPeachResult(toTrimmedString(snapshot.resultCode));
    return recordTopUpAuthorization({
      sessionRef: params.sessionRef,
      bookingRef: params.bookingRef,
      paymentIntentRef: params.paymentIntentRef,
      authorizationRef,
      studentId: params.studentId,
      tutorId: params.tutorId,
      registrationId: sourceAuthorization.registrationId,
      paymentMethodId: sourceAuthorization.paymentMethodId,
      paymentMethodType: sourceAuthorization.paymentMethodType,
      paymentMethodSummary: sourceAuthorization.paymentMethodSummary,
      amountZar: topUpAmountZar,
      outcome,
      providerSnapshot: snapshot,
      tickId: params.tickId,
    });
  } catch (error) {
    const snapshot = buildProviderResponseSnapshot({}, authorizationId);
    const outcome: AuthorizationOutcome = "FAILED";

    return recordTopUpAuthorization({
      sessionRef: params.sessionRef,
      bookingRef: params.bookingRef,
      paymentIntentRef: params.paymentIntentRef,
      authorizationRef,
      studentId: params.studentId,
      tutorId: params.tutorId,
      registrationId: sourceAuthorization.registrationId,
      paymentMethodId: sourceAuthorization.paymentMethodId,
      paymentMethodType: sourceAuthorization.paymentMethodType,
      paymentMethodSummary: sourceAuthorization.paymentMethodSummary,
      amountZar: topUpAmountZar,
      outcome,
      providerSnapshot: {
        ...snapshot,
        resultCode: toTrimmedString(snapshot.resultCode) || "provider_error",
        resultDescription: toTrimmedString(snapshot.resultDescription) ||
          (error instanceof Error ? error.message : "Top-up preauthorisation failed."),
      },
      tickId: params.tickId,
    });
  }
}

async function finalizeTick(params: {
  preparation: SessionTickPreparation;
  finalStatus: "COMPLETED" | "LOW_FUNDS" | "ENDED" | "SKIPPED";
  deltaAfterZar: number;
  accountedTotalZar: number;
  pendingCaptureTotalZar: number;
  lowFundsAt: Date | null;
  topUpAuthorizationId?: string;
  topUpStatus?: string;
  captureCount: number;
  forcedEnded: boolean;
}): Promise<void> {
  const now = new Date();
  const sessionRef = db.collection("tutoring_sessions").doc(params.preparation.sessionId);
  const bookingRef = db.collection("tutor_requests").doc(params.preparation.bookingId);
  const paymentIntentRef = db
    .collection("session_payment_intents")
    .doc(params.preparation.paymentIntentId);
  const tickRef = sessionRef.collection("billing_ticks").doc(params.preparation.tickId);

  await db.runTransaction(async (tx) => {
    const [sessionSnap, bookingSnap] = await Promise.all([
      tx.get(sessionRef),
      tx.get(bookingRef),
    ]);
    const sessionData = sessionSnap.data() ?? {};
    const bookingData = bookingSnap.data() ?? {};
    const guestTutoringMode =
      bookingData.guestTutoringMode === true ||
      bookingData.payerType === "guest" ||
      sessionData.guestTutoringMode === true;
    const currentSessionState = deriveTutoringSessionState(
      sessionData as Record<string, unknown>
    );
    const currentBookingState = deriveTutoringBookingState(
      bookingData as Record<string, unknown>
    );
    const nextSessionLifecycleState = params.finalStatus === "ENDED" ?
      TutoringSessionState.ENDED_INSUFFICIENT_FUNDS :
      params.finalStatus === "LOW_FUNDS" ?
        TutoringSessionState.LOW_FUNDS :
        TutoringSessionState.ACTIVE;
    assertSessionState({
      current: currentSessionState,
      next: nextSessionLifecycleState,
      actor: TutoringTransitionActor.BILLING,
      isGuestSession: guestTutoringMode,
      reason: params.finalStatus === "ENDED" ? "insufficient_funds" : undefined,
    });
    if (params.finalStatus === "ENDED") {
      assertBookingState({
        current: currentBookingState,
        next: TutoringBookingState.ENDED_INSUFFICIENT_FUNDS,
        actor: TutoringTransitionActor.BILLING,
        isGuestSession: guestTutoringMode,
        reason: "insufficient_funds",
      });
    } else {
      assertBookingState({
        current: currentBookingState,
        next: TutoringBookingState.IN_PROGRESS,
        actor: TutoringTransitionActor.SYSTEM,
        isGuestSession: guestTutoringMode,
      });
    }

    tx.set(tickRef, {
      status: params.finalStatus,
      billableMinutes: params.preparation.billableMinutes,
      amountDueZar: params.preparation.amountDueZar,
      accountedTotalZar: params.accountedTotalZar,
      pendingCaptureTotalZar: params.pendingCaptureTotalZar,
      deltaAfterZar: params.deltaAfterZar,
      topUpAuthorizationId: params.topUpAuthorizationId || null,
      topUpStatus: params.topUpStatus || null,
      captureCount: params.captureCount,
      forcedEnded: params.forcedEnded,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    const sessionUpdate: Record<string, unknown> = {
      billingLockTickId: admin.firestore.FieldValue.delete(),
      billingLockExpiresAt: admin.firestore.FieldValue.delete(),
      billedMinutes: params.preparation.billableMinutes,
      amountDueZar: params.preparation.amountDueZar,
      outstandingDueZar: params.deltaAfterZar,
      protectedMinutesPurchased: params.preparation.protectedMinutesPurchased,
      protectedMinutesRemaining: params.preparation.protectedMinutesRemaining,
      consumedMinutes: params.preparation.consumedMinutes,
      refillAttemptCount: params.preparation.refillAttemptCount,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    const lowFundsNotification = params.finalStatus === "LOW_FUNDS" ?
      buildLowFundsNotificationPayload({
        now,
        sessionStartAt: params.preparation.sessionStartAt,
        protectedMinutesPurchased: params.preparation.protectedMinutesPurchased,
        protectedMinutesRemaining: params.preparation.protectedMinutesRemaining,
        consumedMinutes: params.preparation.consumedMinutes,
        refillAttemptCount: params.preparation.refillAttemptCount,
        lowFundsAt: params.lowFundsAt,
        state: "low_funds",
        reason: "reserve_refill_failed",
      }) :
      params.finalStatus === "ENDED" ?
        buildLowFundsNotificationPayload({
          now,
          sessionStartAt: params.preparation.sessionStartAt,
          protectedMinutesPurchased: params.preparation.protectedMinutesPurchased,
          protectedMinutesRemaining: 0,
          consumedMinutes: params.preparation.consumedMinutes,
          refillAttemptCount: params.preparation.refillAttemptCount,
          lowFundsAt: params.lowFundsAt,
          state: "ended_insufficient_funds",
          reason: "protected_time_exhausted",
        }) :
        null;

    if (params.finalStatus === "LOW_FUNDS") {
      sessionUpdate.status = SESSION_LOW_FUNDS;
      sessionUpdate.sessionLifecycleState = TutoringSessionState.LOW_FUNDS;
      sessionUpdate.lowFundsNotification = lowFundsNotification;
      sessionUpdate.lowFundsAt = params.lowFundsAt ?
        admin.firestore.Timestamp.fromDate(params.lowFundsAt) :
        admin.firestore.FieldValue.serverTimestamp();
      sessionUpdate.lowFundsGraceEndsAt = lowFundsNotification?.countdownEndsAtIso ?
        admin.firestore.Timestamp.fromDate(
          new Date(lowFundsNotification.countdownEndsAtIso)
        ) :
        admin.firestore.FieldValue.delete();
    } else if (params.finalStatus === "ENDED") {
      sessionUpdate.status = SESSION_ENDED_INSUFFICIENT_FUNDS;
      sessionUpdate.sessionLifecycleState =
        TutoringSessionState.ENDED_INSUFFICIENT_FUNDS;
      sessionUpdate.sessionTerminalState =
        TutoringSessionState.ENDED_INSUFFICIENT_FUNDS;
      sessionUpdate.lowFundsNotification = lowFundsNotification;
      sessionUpdate.lowFundsAt = params.lowFundsAt ?
        admin.firestore.Timestamp.fromDate(params.lowFundsAt) :
        admin.firestore.FieldValue.serverTimestamp();
      sessionUpdate.lowFundsGraceEndsAt = lowFundsNotification?.countdownEndsAtIso ?
        admin.firestore.Timestamp.fromDate(
          new Date(lowFundsNotification.countdownEndsAtIso)
        ) :
        admin.firestore.FieldValue.delete();
      sessionUpdate.endedAt = admin.firestore.FieldValue.serverTimestamp();
      sessionUpdate.endedReason = "insufficient_funds";
    } else {
      sessionUpdate.status = SESSION_ACTIVE;
      sessionUpdate.sessionLifecycleState = TutoringSessionState.ACTIVE;
      sessionUpdate.lowFundsAt = null;
      sessionUpdate.lowFundsNotification = admin.firestore.FieldValue.delete();
      sessionUpdate.lowFundsGraceEndsAt = admin.firestore.FieldValue.delete();
    }

    tx.set(sessionRef, sessionUpdate, {merge: true});

    tx.set(bookingRef, {
      protectedMinutesPurchased: params.preparation.protectedMinutesPurchased,
      protectedMinutesRemaining: params.preparation.protectedMinutesRemaining,
      consumedMinutes: params.preparation.consumedMinutes,
      refillAttemptCount: params.preparation.refillAttemptCount,
      bookingState: params.finalStatus === "ENDED" ?
        TutoringBookingState.ENDED_INSUFFICIENT_FUNDS :
        TutoringBookingState.IN_PROGRESS,
      sessionState: params.finalStatus === "ENDED" ?
        "ended_insufficient_funds" :
        params.finalStatus === "LOW_FUNDS" ?
          "low_funds" :
          "active",
      lowFundsNotification: params.finalStatus === "LOW_FUNDS" || params.finalStatus === "ENDED" ?
        lowFundsNotification :
        admin.firestore.FieldValue.delete(),
      lowFundsAt: params.finalStatus === "LOW_FUNDS" || params.finalStatus === "ENDED" ?
        (params.lowFundsAt ? admin.firestore.Timestamp.fromDate(params.lowFundsAt) :
          admin.firestore.FieldValue.serverTimestamp()) :
        null,
      endedAt: params.finalStatus === "ENDED" ?
        admin.firestore.FieldValue.serverTimestamp() : undefined,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    tx.set(paymentIntentRef, {
      protectedMinutesPurchased: params.preparation.protectedMinutesPurchased,
      protectedMinutesRemaining: params.preparation.protectedMinutesRemaining,
      consumedMinutes: params.preparation.consumedMinutes,
      refillAttemptCount: params.preparation.refillAttemptCount,
      sessionStatus: params.finalStatus === "ENDED" ?
        SESSION_ENDED_INSUFFICIENT_FUNDS :
        params.finalStatus === "LOW_FUNDS" ?
          SESSION_LOW_FUNDS :
          SESSION_ACTIVE,
      sessionLifecycleState: params.finalStatus === "ENDED" ?
        TutoringSessionState.ENDED_INSUFFICIENT_FUNDS :
        params.finalStatus === "LOW_FUNDS" ?
          TutoringSessionState.LOW_FUNDS :
          TutoringSessionState.ACTIVE,
      lowFundsNotification: params.finalStatus === "LOW_FUNDS" || params.finalStatus === "ENDED" ?
        lowFundsNotification :
        admin.firestore.FieldValue.delete(),
      sessionTerminalState: params.finalStatus === "ENDED" ?
        TutoringSessionState.ENDED_INSUFFICIENT_FUNDS :
        admin.firestore.FieldValue.delete(),
      lowFundsAt: params.finalStatus === "LOW_FUNDS" || params.finalStatus === "ENDED" ?
        (params.lowFundsAt ? admin.firestore.Timestamp.fromDate(params.lowFundsAt) :
          admin.firestore.FieldValue.serverTimestamp()) :
        null,
      endedAt: params.finalStatus === "ENDED" ?
        admin.firestore.FieldValue.serverTimestamp() : undefined,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  });
}

async function processSessionTick(
  sessionDoc: admin.firestore.QueryDocumentSnapshot,
  now: Date
): Promise<void> {
  await createInitialProtection(sessionDoc.id);
  const preparation = await prepareTick(sessionDoc.ref, now);
  if (!preparation) return;

  const sessionRef = db.collection("tutoring_sessions").doc(preparation.sessionId);
  const bookingRef = db.collection("tutor_requests").doc(preparation.bookingId);
  const paymentIntentRef = db
    .collection("session_payment_intents")
    .doc(preparation.paymentIntentId);
  const config = getPaymentProviderContext();
  const protectionState = await consumeProtectionTick(preparation.sessionId, now);
  preparation.billableMinutes = protectionState.consumedMinutes;
  preparation.amountDueZar = toMoney(
    protectionState.consumedMinutes * preparation.studentRatePerMinZar
  );
  preparation.protectedMinutesPurchased = protectionState.protectedMinutesPurchased;
  preparation.protectedMinutesRemaining = protectionState.protectedMinutesRemaining;
  preparation.consumedMinutes = protectionState.consumedMinutes;
  preparation.refillAttemptCount = protectionState.refillAttemptCount;
  preparation.lowFundsAt = protectionState.lowFundsAt;

  let authorizations = await loadAuthorizations(preparation.bookingId);
  let accountedTotalZar = toMoney(
    preparation.capturedTotalZar + preparation.pendingCaptureTotalZar
  );
  let deltaZar = toMoney(
    Math.max(0, preparation.amountDueZar - accountedTotalZar)
  );
  let captureCount = 0;
  const availableAuthorizations = () => authorizations.filter((authorization) =>
    authorization.status === AUTH_STATUS_AUTHORIZED &&
    authorization.remainingAuthorizedZar > 0 &&
    authorization.providerPaymentId
  );

  let captureIndex = 0;
  for (const authorization of availableAuthorizations()) {
    if (deltaZar <= 0) break;
    const captureAmountZar = toMoney(
      Math.min(deltaZar, authorization.remainingAuthorizedZar)
    );
    if (captureAmountZar <= 0) continue;

    const captureResult = await captureAgainstAuthorization({
      config,
      sessionRef,
      bookingRef,
      paymentIntentRef,
      authorization,
      billableMinutes: preparation.billableMinutes,
      captureIndex,
      amountZar: captureAmountZar,
      tickId: preparation.tickId,
    });
    captureIndex += 1;
    captureCount += 1;
    if (captureResult.accountedAmountZar > 0) {
      accountedTotalZar = toMoney(accountedTotalZar + captureResult.accountedAmountZar);
      deltaZar = toMoney(Math.max(0, preparation.amountDueZar - accountedTotalZar));
      authorization.remainingAuthorizedZar = toMoney(
        Math.max(0, authorization.remainingAuthorizedZar - captureResult.accountedAmountZar)
      );
      if (captureResult.status === "CAPTURED") {
        authorization.capturedAmountZar = toMoney(
          authorization.capturedAmountZar + captureResult.accountedAmountZar
        );
      } else if (captureResult.status === "PENDING_PROVIDER") {
        authorization.pendingCaptureAmountZar = toMoney(
          authorization.pendingCaptureAmountZar + captureResult.accountedAmountZar
        );
      }
    }
  }

  let topUpAuthorizationId = "";
  let topUpStatus = "";
  let lowFundsTriggered = false;

  if (preparation.protectedMinutesRemaining <= REFILL_THRESHOLD_MINUTES) {
    const topUp = await reserveMoreProtection(preparation.sessionId);
    topUpAuthorizationId = topUp.authorizationId;
    topUpStatus = topUp.status;
    preparation.protectedMinutesPurchased = topUp.protectedMinutesPurchased;
    preparation.protectedMinutesRemaining = topUp.protectedMinutesRemaining;
    preparation.consumedMinutes = topUp.consumedMinutes;
    preparation.refillAttemptCount = topUp.refillAttemptCount;
    preparation.lowFundsAt = topUp.lowFundsAt;

    if (topUp.status === "AUTHORIZED") {
      authorizations = await loadAuthorizations(preparation.bookingId);
      const topUpAuthorization = authorizations.find((authorization) =>
        authorization.id === topUp.authorizationId
      );
      if (topUpAuthorization && deltaZar > 0 && topUpAuthorization.remainingAuthorizedZar > 0) {
        const captureAmountZar = toMoney(
          Math.min(deltaZar, topUpAuthorization.remainingAuthorizedZar)
        );
        if (captureAmountZar > 0) {
          const captureResult = await captureAgainstAuthorization({
            config,
            sessionRef,
            bookingRef,
            paymentIntentRef,
            authorization: topUpAuthorization,
            billableMinutes: preparation.billableMinutes,
            captureIndex,
            amountZar: captureAmountZar,
            tickId: preparation.tickId,
          });
          captureIndex += 1;
          captureCount += 1;
          if (captureResult.accountedAmountZar > 0) {
            accountedTotalZar = toMoney(accountedTotalZar + captureResult.accountedAmountZar);
            deltaZar = toMoney(Math.max(0, preparation.amountDueZar - accountedTotalZar));
          }
        }
      }
    } else if (topUp.status === "FAILED") {
      lowFundsTriggered = true;
    }
  }

  let finalStatus: "COMPLETED" | "LOW_FUNDS" | "ENDED" = "COMPLETED";
  let lowFundsAt = preparation.lowFundsAt;
  let forcedEnded = false;
  const protectionExpired = shouldForceEndForProtectionExhaustion({
    now,
    sessionStartAt: preparation.sessionStartAt,
    protectedMinutesPurchased: preparation.protectedMinutesPurchased,
    protectedMinutesRemaining: preparation.protectedMinutesRemaining,
    lowFundsAt: preparation.lowFundsAt,
  });

  if (preparation.protectedMinutesRemaining <= 0 || protectionExpired) {
    const endedState = await endSessionForInsufficientFunds(preparation.sessionId, now);
    lowFundsAt = endedState.lowFundsAt;
    preparation.lowFundsAt = endedState.lowFundsAt;
    preparation.protectedMinutesRemaining = endedState.protectedMinutesRemaining;
    finalStatus = "ENDED";
    forcedEnded = true;
  } else if (
    lowFundsTriggered ||
    (preparation.sessionStatus === SESSION_LOW_FUNDS && topUpStatus !== "AUTHORIZED")
  ) {
    const lowFundsState = await enterLowFundsState(preparation.sessionId, now);
    lowFundsAt = lowFundsState.lowFundsAt;
    preparation.lowFundsAt = lowFundsState.lowFundsAt;
    finalStatus = "LOW_FUNDS";
  }

  const finalSessionSnap = await sessionRef.get();
  const finalSessionData = finalSessionSnap.data() ?? {};
  const pendingCaptureTotalZar = asMoney(finalSessionData.pendingCaptureTotalZar, 0);
  const committedCapturedTotalZar = asMoney(finalSessionData.capturedTotalZar, 0);
  const finalAccountedTotalZar = toMoney(
    committedCapturedTotalZar + pendingCaptureTotalZar
  );
  const finalDeltaZar = toMoney(
    Math.max(0, preparation.amountDueZar - finalAccountedTotalZar)
  );

  if (!lowFundsTriggered && preparation.sessionStatus === SESSION_LOW_FUNDS) {
    lowFundsAt = null;
  }

  await finalizeTick({
    preparation,
    finalStatus,
    deltaAfterZar: finalDeltaZar,
    accountedTotalZar: finalAccountedTotalZar,
    pendingCaptureTotalZar,
    lowFundsAt,
    topUpAuthorizationId,
    topUpStatus,
    captureCount,
    forcedEnded,
  });
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

async function runTutoringProtectionSweep(passLabel: string): Promise<void> {
  const now = new Date();
  const sessions = await listTargetSessions();

  logger.info("Running tutoring protection sweep", {
    passLabel,
    sessionCount: sessions.length,
    nowIso: now.toISOString(),
  });

  for (const sessionDoc of sessions) {
    try {
      await processSessionTick(sessionDoc, now);
    } catch (error) {
      logger.error("Tutoring protection sweep failed for session", {
        passLabel,
        sessionId: sessionDoc.id,
        error,
      });
    }
  }
}

export const billingTick = onSchedule(
  {
    schedule: SCHEDULE,
    region: REGION,
    timeZone: "Africa/Johannesburg",
  },
  async () => {
    // Firebase scheduled functions are minute-granular, so run a second
    // in-process sweep 30 seconds later to enforce an effective 30 second cadence.
    await runTutoringProtectionSweep("t0");
    await delay(EFFECTIVE_SWEEP_INTERVAL_MS);
    await runTutoringProtectionSweep("t30");
  }
);
