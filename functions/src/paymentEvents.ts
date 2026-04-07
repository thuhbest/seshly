import {createHash} from "node:crypto";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {HttpsError, onCall} from "./callable";
import {
  buildCaptureSchemaFields,
  buildPaymentAuthorizationSchemaFields,
  buildPayoutRecordSchemaFields,
} from "./tutoringFirestoreSchema";
import {assertPlatformAdmin} from "./tutorApprovalState";
import {TutoringBookingState} from "./tutoringStateMachine";

const REGION = "europe-west1";
const PAYMENT_EVENTS_COLLECTION = "payment_events";
const MAX_FAILURE_ATTEMPTS = 3;
const TUTORING_RAIL = "TUTORING";

export type PaymentEventType =
  | "authorization_created"
  | "authorization_reserved"
  | "authorization_reserve_failed"
  | "capture_succeeded"
  | "capture_failed"
  | "release_succeeded"
  | "transfer_succeeded"
  | "transfer_failed";

export type PaymentEventStatus =
  | "received"
  | "processed"
  | "failed"
  | "dead_letter";

export interface PaymentEventInput {
  provider?: unknown;
  adapterKey?: unknown;
  externalEventId?: unknown;
  eventType?: unknown;
  paymentRail?: unknown;
  authorizationId?: unknown;
  authorizationReference?: unknown;
  captureId?: unknown;
  captureReference?: unknown;
  releaseId?: unknown;
  releaseReference?: unknown;
  payoutId?: unknown;
  payoutBatchId?: unknown;
  bookingId?: unknown;
  paymentSessionId?: unknown;
  sessionId?: unknown;
  tutorId?: unknown;
  recipientCode?: unknown;
  transferCode?: unknown;
  transferReference?: unknown;
  providerReference?: unknown;
  providerStatus?: unknown;
  amountZar?: unknown;
  currency?: unknown;
  reason?: unknown;
  metadata?: unknown;
  raw?: unknown;
}

interface NormalizedPaymentEvent {
  provider: string;
  adapterKey: string;
  externalEventId: string;
  eventType: PaymentEventType;
  paymentRail: string;
  authorizationId: string;
  authorizationReference: string | null;
  captureId: string;
  captureReference: string | null;
  releaseId: string;
  releaseReference: string | null;
  payoutId: string;
  payoutBatchId: string | null;
  bookingId: string;
  paymentSessionId: string;
  sessionId: string;
  tutorId: string;
  recipientCode: string | null;
  transferCode: string | null;
  transferReference: string | null;
  providerReference: string | null;
  providerStatus: string | null;
  amountZar: number;
  currency: string;
  reason: string | null;
  metadata: Record<string, unknown>;
  raw: Record<string, unknown>;
}

interface PaymentEventMapperResult {
  eventType: PaymentEventType;
  paymentRail: string;
  primaryTargetCollection: string;
  primaryTargetId: string;
  secondaryTargetCollection: string | null;
  secondaryTargetId: string | null;
  resultingStatus: string;
  amountZar: number;
  currency: string;
}

export interface PaymentEventProcessResult {
  paymentEventId: string;
  provider: string;
  externalEventId: string;
  eventType: string;
  status: PaymentEventStatus;
  deduplicated: boolean;
  attemptCount: number;
  paymentRail: string;
  primaryTargetCollection: string | null;
  primaryTargetId: string | null;
  secondaryTargetCollection: string | null;
  secondaryTargetId: string | null;
  errorCode: string | null;
  errorMessage: string | null;
}

class PaymentEventProcessingError extends Error {
  constructor(
    readonly errorCode: string,
    readonly finalStatus: Exclude<PaymentEventStatus, "processed" | "received">,
    message: string
  ) {
    super(message);
    this.name = "PaymentEventProcessingError";
  }
}

function getDb(): FirebaseFirestore.Firestore {
  return admin.firestore();
}

function nowServerTs() {
  return admin.firestore.FieldValue.serverTimestamp();
}

function toTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function toUpper(value: unknown): string {
  return toTrimmedString(value).toUpperCase();
}

function toLower(value: unknown): string {
  return toTrimmedString(value).toLowerCase();
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

function asPositiveMoney(value: unknown): number {
  const amount = asMoney(value, 0);
  if (amount <= 0) {
    throw new PaymentEventProcessingError(
      "PAYMENT_EVENT_AMOUNT_REQUIRED",
      "dead_letter",
      "payment event amountZar must be greater than zero."
    );
  }
  return amount;
}

function toRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value) ?
    value as Record<string, unknown> :
    {};
}

function asAttemptCount(value: unknown): number {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.max(0, Math.floor(value));
  }
  return 0;
}

function stableDigest(material: string): string {
  return createHash("sha256").update(material).digest("hex");
}

export function paymentEventDocumentId(
  provider: string,
  externalEventId: string
): string {
  return `pe_${stableDigest(`${provider}|${externalEventId}`).slice(0, 32)}`;
}

function fallbackEventTrace(input: PaymentEventInput): {
  provider: string;
  externalEventId: string;
  paymentEventId: string;
} {
  const provider = toTrimmedString(input.provider) || "UNKNOWN_PROVIDER";
  const externalEventId = toTrimmedString(input.externalEventId) ||
    `missing_${stableDigest(JSON.stringify(input)).slice(0, 24)}`;
  return {
    provider,
    externalEventId,
    paymentEventId: paymentEventDocumentId(provider, externalEventId),
  };
}

function requiredString(
  value: unknown,
  errorCode: string,
  message: string
): string {
  const trimmed = toTrimmedString(value);
  if (!trimmed) {
    throw new PaymentEventProcessingError(errorCode, "dead_letter", message);
  }
  return trimmed;
}

function normalizeCurrency(value: unknown): string {
  return toUpper(value) || "ZAR";
}

function normalizePaymentRail(value: unknown): string {
  return toUpper(value) || TUTORING_RAIL;
}

export function normalizePaymentEventInput(
  input: PaymentEventInput
): NormalizedPaymentEvent {
  const provider = requiredString(
    input.provider,
    "PAYMENT_EVENT_PROVIDER_REQUIRED",
    "payment event provider is required."
  );
  const externalEventId = requiredString(
    input.externalEventId,
    "PAYMENT_EVENT_EXTERNAL_ID_REQUIRED",
    "payment event externalEventId is required."
  );
  const eventType = requiredString(
    input.eventType,
    "PAYMENT_EVENT_TYPE_REQUIRED",
    "payment event eventType is required."
  ) as PaymentEventType;
  const paymentRail = normalizePaymentRail(input.paymentRail);
  if (paymentRail !== TUTORING_RAIL) {
    throw new PaymentEventProcessingError(
      "PAYMENT_EVENT_UNSUPPORTED_RAIL",
      "dead_letter",
      "payment event rail is unsupported. Tutoring events must stay separate from SeshCredits."
    );
  }

  return {
    provider,
    adapterKey: toTrimmedString(input.adapterKey) || provider.toLowerCase(),
    externalEventId,
    eventType,
    paymentRail,
    authorizationId: toTrimmedString(input.authorizationId),
    authorizationReference: toTrimmedString(input.authorizationReference) || null,
    captureId: toTrimmedString(input.captureId),
    captureReference: toTrimmedString(input.captureReference) || null,
    releaseId: toTrimmedString(input.releaseId),
    releaseReference: toTrimmedString(input.releaseReference) || null,
    payoutId: toTrimmedString(input.payoutId),
    payoutBatchId: toTrimmedString(input.payoutBatchId) || null,
    bookingId: toTrimmedString(input.bookingId),
    paymentSessionId: toTrimmedString(input.paymentSessionId),
    sessionId: toTrimmedString(input.sessionId),
    tutorId: toTrimmedString(input.tutorId),
    recipientCode: toTrimmedString(input.recipientCode) || null,
    transferCode: toTrimmedString(input.transferCode) || null,
    transferReference: toTrimmedString(input.transferReference) || null,
    providerReference: toTrimmedString(input.providerReference) || null,
    providerStatus: toTrimmedString(input.providerStatus) || null,
    amountZar: asMoney(input.amountZar, 0),
    currency: normalizeCurrency(input.currency),
    reason: toTrimmedString(input.reason) || null,
    metadata: toRecord(input.metadata),
    raw: toRecord(input.raw),
  };
}

export function mapAuthorizationCreatedEvent(
  event: NormalizedPaymentEvent
): PaymentEventMapperResult {
  return {
    eventType: "authorization_created",
    paymentRail: event.paymentRail,
    primaryTargetCollection: "payment_authorizations",
    primaryTargetId: requiredString(
      event.authorizationId,
      "PAYMENT_EVENT_AUTHORIZATION_ID_REQUIRED",
      "authorization_created requires authorizationId."
    ),
    secondaryTargetCollection: "session_payment_intents",
    secondaryTargetId: requiredString(
      event.paymentSessionId || event.bookingId,
      "PAYMENT_EVENT_PAYMENT_SESSION_REQUIRED",
      "authorization_created requires paymentSessionId."
    ),
    resultingStatus: "AUTHORIZED",
    amountZar: asPositiveMoney(event.amountZar),
    currency: event.currency,
  };
}

export function mapAuthorizationReservedEvent(
  event: NormalizedPaymentEvent
): PaymentEventMapperResult {
  return {
    eventType: "authorization_reserved",
    paymentRail: event.paymentRail,
    primaryTargetCollection: "payment_authorizations",
    primaryTargetId: requiredString(
      event.authorizationId,
      "PAYMENT_EVENT_AUTHORIZATION_ID_REQUIRED",
      "authorization_reserved requires authorizationId."
    ),
    secondaryTargetCollection: "tutoring_sessions",
    secondaryTargetId: requiredString(
      event.sessionId,
      "PAYMENT_EVENT_SESSION_ID_REQUIRED",
      "authorization_reserved requires sessionId."
    ),
    resultingStatus: "AUTHORIZED",
    amountZar: asPositiveMoney(event.amountZar),
    currency: event.currency,
  };
}

export function mapAuthorizationReserveFailedEvent(
  event: NormalizedPaymentEvent
): PaymentEventMapperResult {
  return {
    eventType: "authorization_reserve_failed",
    paymentRail: event.paymentRail,
    primaryTargetCollection: "payment_authorizations",
    primaryTargetId: requiredString(
      event.authorizationId,
      "PAYMENT_EVENT_AUTHORIZATION_ID_REQUIRED",
      "authorization_reserve_failed requires authorizationId."
    ),
    secondaryTargetCollection: "tutoring_sessions",
    secondaryTargetId: requiredString(
      event.sessionId,
      "PAYMENT_EVENT_SESSION_ID_REQUIRED",
      "authorization_reserve_failed requires sessionId."
    ),
    resultingStatus: "FAILED",
    amountZar: asPositiveMoney(event.amountZar),
    currency: event.currency,
  };
}

export function mapCaptureSucceededEvent(
  event: NormalizedPaymentEvent
): PaymentEventMapperResult {
  return {
    eventType: "capture_succeeded",
    paymentRail: event.paymentRail,
    primaryTargetCollection: "payment_captures",
    primaryTargetId: requiredString(
      event.captureId || event.captureReference || event.externalEventId,
      "PAYMENT_EVENT_CAPTURE_ID_REQUIRED",
      "capture_succeeded requires captureId or captureReference."
    ),
    secondaryTargetCollection: "payment_authorizations",
    secondaryTargetId: requiredString(
      event.authorizationId,
      "PAYMENT_EVENT_AUTHORIZATION_ID_REQUIRED",
      "capture_succeeded requires authorizationId."
    ),
    resultingStatus: "CAPTURED",
    amountZar: asPositiveMoney(event.amountZar),
    currency: event.currency,
  };
}

export function mapCaptureFailedEvent(
  event: NormalizedPaymentEvent
): PaymentEventMapperResult {
  return {
    eventType: "capture_failed",
    paymentRail: event.paymentRail,
    primaryTargetCollection: "payment_captures",
    primaryTargetId: requiredString(
      event.captureId || event.captureReference || event.externalEventId,
      "PAYMENT_EVENT_CAPTURE_ID_REQUIRED",
      "capture_failed requires captureId or captureReference."
    ),
    secondaryTargetCollection: "payment_authorizations",
    secondaryTargetId: requiredString(
      event.authorizationId,
      "PAYMENT_EVENT_AUTHORIZATION_ID_REQUIRED",
      "capture_failed requires authorizationId."
    ),
    resultingStatus: "FAILED",
    amountZar: asPositiveMoney(event.amountZar),
    currency: event.currency,
  };
}

export function mapReleaseSucceededEvent(
  event: NormalizedPaymentEvent
): PaymentEventMapperResult {
  return {
    eventType: "release_succeeded",
    paymentRail: event.paymentRail,
    primaryTargetCollection: "payment_reversals",
    primaryTargetId: requiredString(
      event.releaseId || event.releaseReference || event.externalEventId,
      "PAYMENT_EVENT_RELEASE_ID_REQUIRED",
      "release_succeeded requires releaseId or releaseReference."
    ),
    secondaryTargetCollection: "payment_authorizations",
    secondaryTargetId: requiredString(
      event.authorizationId,
      "PAYMENT_EVENT_AUTHORIZATION_ID_REQUIRED",
      "release_succeeded requires authorizationId."
    ),
    resultingStatus: "REVERSED",
    amountZar: asPositiveMoney(event.amountZar),
    currency: event.currency,
  };
}

export function mapTransferSucceededEvent(
  event: NormalizedPaymentEvent
): PaymentEventMapperResult {
  return {
    eventType: "transfer_succeeded",
    paymentRail: event.paymentRail,
    primaryTargetCollection: "tutor_payouts",
    primaryTargetId: requiredString(
      event.payoutId,
      "PAYMENT_EVENT_PAYOUT_ID_REQUIRED",
      "transfer_succeeded requires payoutId."
    ),
    secondaryTargetCollection: "tutor_payout_batches",
    secondaryTargetId: event.payoutBatchId,
    resultingStatus: "PAID",
    amountZar: asPositiveMoney(event.amountZar),
    currency: event.currency,
  };
}

export function mapTransferFailedEvent(
  event: NormalizedPaymentEvent
): PaymentEventMapperResult {
  return {
    eventType: "transfer_failed",
    paymentRail: event.paymentRail,
    primaryTargetCollection: "tutor_payouts",
    primaryTargetId: requiredString(
      event.payoutId,
      "PAYMENT_EVENT_PAYOUT_ID_REQUIRED",
      "transfer_failed requires payoutId."
    ),
    secondaryTargetCollection: "tutor_payout_batches",
    secondaryTargetId: event.payoutBatchId,
    resultingStatus: "FAILED",
    amountZar: asPositiveMoney(event.amountZar),
    currency: event.currency,
  };
}

function mapPaymentEvent(
  event: NormalizedPaymentEvent
): PaymentEventMapperResult {
  switch (event.eventType) {
  case "authorization_created":
    return mapAuthorizationCreatedEvent(event);
  case "authorization_reserved":
    return mapAuthorizationReservedEvent(event);
  case "authorization_reserve_failed":
    return mapAuthorizationReserveFailedEvent(event);
  case "capture_succeeded":
    return mapCaptureSucceededEvent(event);
  case "capture_failed":
    return mapCaptureFailedEvent(event);
  case "release_succeeded":
    return mapReleaseSucceededEvent(event);
  case "transfer_succeeded":
    return mapTransferSucceededEvent(event);
  case "transfer_failed":
    return mapTransferFailedEvent(event);
  default:
    throw new PaymentEventProcessingError(
      "PAYMENT_EVENT_UNSUPPORTED_TYPE",
      "dead_letter",
      `Unsupported payment event type: ${event.eventType}`
    );
  }
}

function buildProviderEventSnapshot(
  event: NormalizedPaymentEvent
): Record<string, unknown> {
  return {
    provider: event.provider,
    adapterKey: event.adapterKey,
    externalEventId: event.externalEventId,
    eventType: event.eventType,
    providerStatus: event.providerStatus,
    providerReference: event.providerReference,
    authorizationReference: event.authorizationReference,
    captureReference: event.captureReference,
    releaseReference: event.releaseReference,
    transferReference: event.transferReference,
    transferCode: event.transferCode,
    recipientCode: event.recipientCode,
    raw: event.raw,
  };
}

function mergeProviderSnapshot(
  existingProvider: Record<string, unknown>,
  event: NormalizedPaymentEvent
): Record<string, unknown> {
  return {
    ...existingProvider,
    lastEventId: event.externalEventId,
    lastEventType: event.eventType,
    lastEventProvider: event.provider,
    lastEventAdapterKey: event.adapterKey,
    lastEventStatus: event.providerStatus,
    lastEventReference: event.providerReference ||
      event.captureReference ||
      event.releaseReference ||
      event.transferReference ||
      event.authorizationReference,
    lastEventRaw: event.raw,
  };
}

function bookingPaymentAuthorizedPatch(
  currentBookingState: string
): Record<string, unknown> {
  const patch: Record<string, unknown> = {
    paymentStatus: "payment_authorized",
    authorizationStatus: "payment_authorized",
    updatedAt: nowServerTs(),
  };
  if (
    !currentBookingState ||
    currentBookingState === TutoringBookingState.CREATED ||
    currentBookingState === TutoringBookingState.AWAITING_PAYMENT_AUTHORIZATION
  ) {
    patch.bookingState = TutoringBookingState.PAYMENT_AUTHORIZED;
  }
  return patch;
}

async function applyAuthorizationEvent(params: {
  tx: admin.firestore.Transaction;
  event: NormalizedPaymentEvent;
  mapped: PaymentEventMapperResult;
}): Promise<void> {
  const db = getDb();
  const authorizationRef = db.collection("payment_authorizations")
    .doc(params.mapped.primaryTargetId);
  const bookingId = params.event.bookingId || params.event.paymentSessionId;
  const paymentSessionId = params.event.paymentSessionId || bookingId;
  if (!bookingId || !paymentSessionId) {
    throw new PaymentEventProcessingError(
      "PAYMENT_EVENT_BOOKING_CONTEXT_REQUIRED",
      "dead_letter",
      "authorization events require bookingId and paymentSessionId."
    );
  }

  const bookingRef = db.collection("tutor_requests").doc(bookingId);
  const paymentSessionRef = db.collection("session_payment_intents").doc(paymentSessionId);
  const sessionRef = params.event.sessionId ?
    db.collection("tutoring_sessions").doc(params.event.sessionId) :
    null;
  const [authorizationSnap, bookingSnap, paymentSessionSnap, sessionSnap] = await Promise.all([
    params.tx.get(authorizationRef),
    params.tx.get(bookingRef),
    params.tx.get(paymentSessionRef),
    sessionRef ? params.tx.get(sessionRef) : Promise.resolve(null),
  ]);

  if (!bookingSnap.exists || !paymentSessionSnap.exists) {
    throw new PaymentEventProcessingError(
      "PAYMENT_EVENT_AUTHORIZATION_CONTEXT_MISSING",
      "dead_letter",
      "authorization event is missing booking or payment session context."
    );
  }

  const existingAuthorization = authorizationSnap.data() ?? {};
  const bookingData = bookingSnap.data() ?? {};
  const currentStatus = toUpper(existingAuthorization.status);
  const desiredStatus = params.mapped.resultingStatus;
  const isInitialAuthorization = params.event.eventType === "authorization_created";
  const isProtectionAuthorization =
    params.event.eventType === "authorization_reserved" ||
    params.event.eventType === "authorization_reserve_failed";
  const provider = mergeProviderSnapshot(
    toRecord(existingAuthorization.provider),
    params.event
  );
  const authorizationBase = {
    authorizationId: params.mapped.primaryTargetId,
    bookingId,
    paymentIntentId: paymentSessionId,
    sessionId: params.event.sessionId || toTrimmedString(existingAuthorization.sessionId) || bookingId,
    studentId: toTrimmedString(existingAuthorization.studentId) || toTrimmedString(bookingData.studentId),
    tutorId: toTrimmedString(existingAuthorization.tutorId) || toTrimmedString(bookingData.tutorId),
    amountZar: params.mapped.amountZar,
    amountCents: Math.round(params.mapped.amountZar * 100),
    currency: params.mapped.currency,
    status: desiredStatus,
    type: isProtectionAuthorization ? "PREAUTH_TOP_UP" : "PREAUTH",
    paymentModel: "tutoring_metered",
    paymentMethodId: toTrimmedString(existingAuthorization.paymentMethodId) || null,
    paymentMethodType: toTrimmedString(existingAuthorization.paymentMethodType) || "card",
    paymentMethodSummary: toTrimmedString(existingAuthorization.paymentMethodSummary) || null,
    tutoringPaymentRail: TUTORING_RAIL,
    provider,
    authorizedAt:
      desiredStatus === "AUTHORIZED" && currentStatus === "AUTHORIZED" ?
        existingAuthorization.authorizedAt ?? nowServerTs() :
      desiredStatus === "AUTHORIZED" ? nowServerTs() : undefined,
    failedAt:
      desiredStatus === "FAILED" && currentStatus === "FAILED" ?
        existingAuthorization.failedAt ?? nowServerTs() :
      desiredStatus === "FAILED" ? nowServerTs() : undefined,
    updatedAt: nowServerTs(),
    createdAt: existingAuthorization.createdAt ?? nowServerTs(),
  };

  params.tx.set(authorizationRef, {
    ...authorizationBase,
    ...buildPaymentAuthorizationSchemaFields(
      params.mapped.primaryTargetId,
      authorizationBase
    ),
  }, {merge: true});

  if (isInitialAuthorization && desiredStatus === "AUTHORIZED") {
    params.tx.set(bookingRef, {
      ...bookingPaymentAuthorizedPatch(toLower(bookingData.bookingState)),
      paymentAuthorizationId: params.mapped.primaryTargetId,
      paymentAuthorizationProvider: params.event.provider,
    }, {merge: true});
  }

  const paymentSessionPatch: Record<string, unknown> = {
    latestAuthorizationId: params.mapped.primaryTargetId,
    latestAuthorizationProviderEventId: params.event.externalEventId,
    updatedAt: nowServerTs(),
  };
  if (isInitialAuthorization && desiredStatus === "AUTHORIZED") {
    paymentSessionPatch.paymentAuthorizationId = params.mapped.primaryTargetId;
    paymentSessionPatch.paymentAuthorizationStatus = "payment_authorized";
    paymentSessionPatch.paymentStatus = "payment_authorized";
  }
  if (isProtectionAuthorization) {
    paymentSessionPatch.latestProtectionAuthorizationId =
      params.mapped.primaryTargetId;
    paymentSessionPatch.latestProtectionAuthorizationStatus = desiredStatus;
    paymentSessionPatch.latestTopUpAuthorizationId =
      params.mapped.primaryTargetId;
    paymentSessionPatch.latestTopUpAuthorizationStatus = desiredStatus;

    params.tx.set(bookingRef, {
      latestProtectionAuthorizationId: params.mapped.primaryTargetId,
      latestProtectionAuthorizationStatus: desiredStatus,
      latestTopUpAuthorizationId: params.mapped.primaryTargetId,
      latestTopUpAuthorizationStatus: desiredStatus,
      updatedAt: nowServerTs(),
    }, {merge: true});
  }
  params.tx.set(paymentSessionRef, paymentSessionPatch, {merge: true});

  if (sessionRef && sessionSnap?.exists) {
    const sessionPatch: Record<string, unknown> = {
      updatedAt: nowServerTs(),
    };
    if (isProtectionAuthorization) {
      sessionPatch.latestProtectionAuthorizationId = params.mapped.primaryTargetId;
      sessionPatch.latestProtectionAuthorizationStatus = desiredStatus;
      sessionPatch.latestTopUpAuthorizationId = params.mapped.primaryTargetId;
      sessionPatch.latestTopUpAuthorizationStatus = desiredStatus;
    }
    params.tx.set(sessionRef, sessionPatch, {merge: true});
  }
}

async function applyCaptureEvent(params: {
  tx: admin.firestore.Transaction;
  event: NormalizedPaymentEvent;
  mapped: PaymentEventMapperResult;
}): Promise<void> {
  const db = getDb();
  const captureRef = db.collection("payment_captures").doc(params.mapped.primaryTargetId);
  const authorizationRef = db.collection("payment_authorizations")
    .doc(params.mapped.secondaryTargetId ?? "");
  const [captureSnap, authorizationSnap] = await Promise.all([
    params.tx.get(captureRef),
    params.tx.get(authorizationRef),
  ]);

  if (!authorizationSnap.exists) {
    throw new PaymentEventProcessingError(
      "PAYMENT_EVENT_AUTHORIZATION_NOT_FOUND",
      "dead_letter",
      "capture event authorization was not found."
    );
  }

  const captureData = captureSnap.data() ?? {};
  const authorizationData = authorizationSnap.data() ?? {};
  const bookingId = toTrimmedString(authorizationData.bookingId);
  const paymentSessionId =
    toTrimmedString(authorizationData.paymentIntentId) || bookingId;
  const sessionId =
    toTrimmedString(authorizationData.sessionId) || bookingId;
  const [bookingSnap, paymentSessionSnap, sessionSnap] = await Promise.all([
    params.tx.get(db.collection("tutor_requests").doc(bookingId)),
    params.tx.get(db.collection("session_payment_intents").doc(paymentSessionId)),
    params.tx.get(db.collection("tutoring_sessions").doc(sessionId)),
  ]);
  if (!bookingSnap.exists || !paymentSessionSnap.exists || !sessionSnap.exists) {
    throw new PaymentEventProcessingError(
      "PAYMENT_EVENT_CAPTURE_CONTEXT_MISSING",
      "dead_letter",
      "capture event is missing booking, session, or payment session context."
    );
  }

  const existingCaptureStatus = toUpper(captureData.status);
  const existingAuthLastCaptureStatus = toUpper(authorizationData.lastCaptureStatus);
  const existingAuthLastCaptureId = toTrimmedString(authorizationData.lastCaptureId);
  const desiredStatus = params.mapped.resultingStatus;

  if (
    existingCaptureStatus === desiredStatus ||
    (
      existingAuthLastCaptureId === params.mapped.primaryTargetId &&
      existingAuthLastCaptureStatus === desiredStatus
    )
  ) {
    params.tx.set(captureRef, {
      provider: mergeProviderSnapshot(toRecord(captureData.provider), params.event),
      updatedAt: nowServerTs(),
    }, {merge: true});
    return;
  }

  if (existingCaptureStatus === "CAPTURED" && desiredStatus === "FAILED") {
    throw new PaymentEventProcessingError(
      "PAYMENT_EVENT_CAPTURE_ALREADY_CAPTURED",
      "dead_letter",
      "capture_failed cannot override a captured payment capture."
    );
  }

  const currentAuthorizationCaptured = asMoney(authorizationData.capturedAmountZar, 0);
  const currentAuthorizationPending = asMoney(authorizationData.pendingCaptureAmountZar, 0);
  const currentSessionCaptured = asMoney(sessionSnap.data()?.capturedTotalZar, 0);
  const currentSessionPending = asMoney(sessionSnap.data()?.pendingCaptureTotalZar, 0);
  const currentBookingCaptured = asMoney(bookingSnap.data()?.capturedAmountZar, 0);
  const currentBookingPending = asMoney(bookingSnap.data()?.pendingCaptureTotalZar, 0);
  const currentPaymentCaptured = asMoney(paymentSessionSnap.data()?.capturedAmountZar, 0);
  const currentPaymentPending = asMoney(paymentSessionSnap.data()?.pendingCaptureTotalZar, 0);
  const pendingReduction = Math.min(currentAuthorizationPending, params.mapped.amountZar);

  const captureBase = {
    captureId: params.mapped.primaryTargetId,
    tutoringPaymentRail: TUTORING_RAIL,
    authorizationId: authorizationRef.id,
    bookingId,
    paymentIntentId: paymentSessionId,
    sessionId,
    amountZar: params.mapped.amountZar,
    accountedAmountZar: desiredStatus === "CAPTURED" ? params.mapped.amountZar : 0,
    amountCents: Math.round(params.mapped.amountZar * 100),
    currency: params.mapped.currency,
    status: desiredStatus,
    provider: buildProviderEventSnapshot(params.event),
    capturedAt: desiredStatus === "CAPTURED" ? nowServerTs() : captureData.capturedAt,
    failedAt: desiredStatus === "FAILED" ? nowServerTs() : captureData.failedAt,
    updatedAt: nowServerTs(),
    createdAt: captureData.createdAt ?? nowServerTs(),
  };
  params.tx.set(captureRef, {
    ...captureBase,
    ...buildCaptureSchemaFields(params.mapped.primaryTargetId, captureBase),
  }, {merge: true});

  const nextAuthorizationCaptured = desiredStatus === "CAPTURED" ?
    toMoney(currentAuthorizationCaptured + params.mapped.amountZar) :
    currentAuthorizationCaptured;
  const nextAuthorizationPending = desiredStatus === "CAPTURED" ||
      desiredStatus === "FAILED" ?
    toMoney(Math.max(0, currentAuthorizationPending - pendingReduction)) :
    currentAuthorizationPending;
  const authorizationPatch = {
    ...authorizationData,
    capturedAmountZar: nextAuthorizationCaptured,
    pendingCaptureAmountZar: nextAuthorizationPending,
    lastCaptureId: params.mapped.primaryTargetId,
    lastCaptureStatus: desiredStatus,
    lastCaptureAmountZar: params.mapped.amountZar,
    provider: mergeProviderSnapshot(toRecord(authorizationData.provider), params.event),
    updatedAt: nowServerTs(),
  };
  params.tx.set(authorizationRef, {
    ...authorizationPatch,
    ...buildPaymentAuthorizationSchemaFields(authorizationRef.id, authorizationPatch),
  }, {merge: true});

  const nextSessionCaptured = desiredStatus === "CAPTURED" ?
    toMoney(currentSessionCaptured + params.mapped.amountZar) :
    currentSessionCaptured;
  const nextSessionPending = desiredStatus === "CAPTURED" ||
      desiredStatus === "FAILED" ?
    toMoney(Math.max(0, currentSessionPending - pendingReduction)) :
    currentSessionPending;
  params.tx.set(sessionSnap.ref, {
    capturedTotalZar: nextSessionCaptured,
    pendingCaptureTotalZar: nextSessionPending,
    updatedAt: nowServerTs(),
  }, {merge: true});

  const nextBookingCaptured = desiredStatus === "CAPTURED" ?
    toMoney(currentBookingCaptured + params.mapped.amountZar) :
    currentBookingCaptured;
  const nextBookingPending = desiredStatus === "CAPTURED" ||
      desiredStatus === "FAILED" ?
    toMoney(Math.max(0, currentBookingPending - pendingReduction)) :
    currentBookingPending;
  params.tx.set(bookingSnap.ref, {
    capturedAmountZar: nextBookingCaptured,
    pendingCaptureTotalZar: nextBookingPending,
    providerCaptureId: params.mapped.primaryTargetId,
    providerCaptureStatus: desiredStatus,
    updatedAt: nowServerTs(),
  }, {merge: true});

  const nextPaymentCaptured = desiredStatus === "CAPTURED" ?
    toMoney(currentPaymentCaptured + params.mapped.amountZar) :
    currentPaymentCaptured;
  const nextPaymentPending = desiredStatus === "CAPTURED" ||
      desiredStatus === "FAILED" ?
    toMoney(Math.max(0, currentPaymentPending - pendingReduction)) :
    currentPaymentPending;
  params.tx.set(paymentSessionSnap.ref, {
    capturedAmountZar: nextPaymentCaptured,
    pendingCaptureTotalZar: nextPaymentPending,
    providerCaptureId: params.mapped.primaryTargetId,
    providerCaptureStatus: desiredStatus,
    latestCaptureId: params.mapped.primaryTargetId,
    updatedAt: nowServerTs(),
  }, {merge: true});
}

async function applyReleaseEvent(params: {
  tx: admin.firestore.Transaction;
  event: NormalizedPaymentEvent;
  mapped: PaymentEventMapperResult;
}): Promise<void> {
  const db = getDb();
  const reversalRef = db.collection("payment_reversals").doc(params.mapped.primaryTargetId);
  const authorizationRef = db.collection("payment_authorizations")
    .doc(params.mapped.secondaryTargetId ?? "");
  const [reversalSnap, authorizationSnap] = await Promise.all([
    params.tx.get(reversalRef),
    params.tx.get(authorizationRef),
  ]);

  if (!authorizationSnap.exists) {
    throw new PaymentEventProcessingError(
      "PAYMENT_EVENT_AUTHORIZATION_NOT_FOUND",
      "dead_letter",
      "release event authorization was not found."
    );
  }

  const reversalData = reversalSnap.data() ?? {};
  const authorizationData = authorizationSnap.data() ?? {};
  const bookingId = toTrimmedString(authorizationData.bookingId);
  const paymentSessionId =
    toTrimmedString(authorizationData.paymentIntentId) || bookingId;
  const sessionId =
    toTrimmedString(authorizationData.sessionId) || bookingId;
  const [bookingSnap, paymentSessionSnap, sessionSnap] = await Promise.all([
    params.tx.get(db.collection("tutor_requests").doc(bookingId)),
    params.tx.get(db.collection("session_payment_intents").doc(paymentSessionId)),
    params.tx.get(db.collection("tutoring_sessions").doc(sessionId)),
  ]);
  if (!bookingSnap.exists || !paymentSessionSnap.exists || !sessionSnap.exists) {
    throw new PaymentEventProcessingError(
      "PAYMENT_EVENT_RELEASE_CONTEXT_MISSING",
      "dead_letter",
      "release event is missing booking, session, or payment session context."
    );
  }

  const existingReversalStatus = toUpper(reversalData.status);
  if (existingReversalStatus === params.mapped.resultingStatus) {
    params.tx.set(reversalRef, {
      provider: mergeProviderSnapshot(toRecord(reversalData.provider), params.event),
      updatedAt: nowServerTs(),
    }, {merge: true});
    return;
  }

  const currentAuthorizationReversed = asMoney(authorizationData.reversedAmountZar, 0);
  const currentAuthorizationPending = asMoney(authorizationData.pendingReversalAmountZar, 0);
  const currentSessionReleased = asMoney(sessionSnap.data()?.releasedAuthorizationAmountZar, 0);
  const currentSessionPending = asMoney(
    sessionSnap.data()?.pendingReleasedAuthorizationAmountZar,
    0
  );
  const currentBookingReleased = asMoney(bookingSnap.data()?.releasedAmountZar, 0);
  const currentBookingPending = asMoney(bookingSnap.data()?.pendingReleasedAmountZar, 0);
  const currentPaymentReleased = asMoney(paymentSessionSnap.data()?.releasedAmountZar, 0);
  const currentPaymentPending = asMoney(paymentSessionSnap.data()?.pendingReleasedAmountZar, 0);
  const pendingReduction = Math.min(currentAuthorizationPending, params.mapped.amountZar);

  params.tx.set(reversalRef, {
    reversalId: params.mapped.primaryTargetId,
    tutoringPaymentRail: TUTORING_RAIL,
    authorizationId: authorizationRef.id,
    bookingId,
    paymentIntentId: paymentSessionId,
    sessionId,
    amountZar: params.mapped.amountZar,
    accountedAmountZar: params.mapped.amountZar,
    amountCents: Math.round(params.mapped.amountZar * 100),
    currency: params.mapped.currency,
    status: params.mapped.resultingStatus,
    provider: buildProviderEventSnapshot(params.event),
    reversedAt: nowServerTs(),
    updatedAt: nowServerTs(),
    createdAt: reversalData.createdAt ?? nowServerTs(),
  }, {merge: true});

  const nextAuthorizationReversed = toMoney(
    currentAuthorizationReversed + params.mapped.amountZar
  );
  const nextAuthorizationPending = toMoney(
    Math.max(0, currentAuthorizationPending - pendingReduction)
  );
  const authorizationPatch = {
    ...authorizationData,
    reversedAmountZar: nextAuthorizationReversed,
    pendingReversalAmountZar: nextAuthorizationPending,
    lastReversalId: params.mapped.primaryTargetId,
    lastReversalStatus: params.mapped.resultingStatus,
    lastReversalAmountZar: params.mapped.amountZar,
    provider: mergeProviderSnapshot(toRecord(authorizationData.provider), params.event),
    updatedAt: nowServerTs(),
  };
  params.tx.set(authorizationRef, {
    ...authorizationPatch,
    ...buildPaymentAuthorizationSchemaFields(authorizationRef.id, authorizationPatch),
  }, {merge: true});

  params.tx.set(sessionSnap.ref, {
    releasedAuthorizationAmountZar: toMoney(
      currentSessionReleased + params.mapped.amountZar
    ),
    pendingReleasedAuthorizationAmountZar: toMoney(
      Math.max(0, currentSessionPending - pendingReduction)
    ),
    updatedAt: nowServerTs(),
  }, {merge: true});
  params.tx.set(bookingSnap.ref, {
    releasedAmountZar: toMoney(currentBookingReleased + params.mapped.amountZar),
    pendingReleasedAmountZar: toMoney(
      Math.max(0, currentBookingPending - pendingReduction)
    ),
    latestReversalId: params.mapped.primaryTargetId,
    updatedAt: nowServerTs(),
  }, {merge: true});
  params.tx.set(paymentSessionSnap.ref, {
    releasedAmountZar: toMoney(currentPaymentReleased + params.mapped.amountZar),
    pendingReleasedAmountZar: toMoney(
      Math.max(0, currentPaymentPending - pendingReduction)
    ),
    latestReversalId: params.mapped.primaryTargetId,
    updatedAt: nowServerTs(),
  }, {merge: true});
}

async function createProviderPayoutEvent(params: {
  tx: admin.firestore.Transaction;
  payoutId: string;
  tutorId: string;
  eventType: string;
  metadata: Record<string, unknown>;
  note?: string | null;
}): Promise<void> {
  const db = getDb();
  const eventRef = db.collection("tutor_payout_events").doc();
  params.tx.set(eventRef, {
    eventId: eventRef.id,
    payoutId: params.payoutId,
    tutorId: params.tutorId,
    eventType: params.eventType,
    actorType: "PROVIDER",
    actorId: null,
    note: params.note ?? null,
    metadata: params.metadata,
    createdAt: nowServerTs(),
  });
}

async function markAllocationsPaidForProviderEvent(params: {
  tx: admin.firestore.Transaction;
  payoutRef: admin.firestore.DocumentReference;
}): Promise<number> {
  const db = getDb();
  const allocationsSnap = await params.tx.get(params.payoutRef.collection("allocations"));
  let paidTotal = 0;

  for (const allocationDoc of allocationsSnap.docs) {
    const allocationData = allocationDoc.data() ?? {};
    if (toUpper(allocationData.status) !== "RESERVED") {
      continue;
    }
    const settlementId = toTrimmedString(allocationData.settlementId);
    const allocatedAmountZar = asMoney(allocationData.allocatedAmountZar, 0);
    if (!settlementId || allocatedAmountZar <= 0) {
      continue;
    }

    const settlementRef = db.collection("tutor_session_settlements").doc(settlementId);
    const payableRef = db.collection("tutor_payables").doc(settlementId);
    const [settlementSnap, payableSnap] = await Promise.all([
      params.tx.get(settlementRef),
      params.tx.get(payableRef),
    ]);
    if (!settlementSnap.exists) {
      continue;
    }

    const settlementData = settlementSnap.data() ?? {};
    const payableData = payableSnap.data() ?? {};
    const nextReserved = toMoney(
      Math.max(
        0,
        asMoney(
          payableData.reservedAmountZar ?? settlementData.payoutReservedAmountZar,
          0
        ) - allocatedAmountZar
      )
    );
    const nextPaid = toMoney(
      asMoney(
        payableData.paidAmountZar ?? settlementData.payoutPaidAmountZar,
        0
      ) + allocatedAmountZar
    );
    const nextHeld = asMoney(
      payableData.blockedAmountZar ?? settlementData.disputeHeldAmountZar,
      0
    );
    const nextEarning = asMoney(
      payableData.grossTutorEarningZar ?? settlementData.tutorEarningZar,
      0
    );
    const nextAvailable = toMoney(
      Math.max(0, nextEarning - nextReserved - nextPaid - nextHeld)
    );
    const nextPayoutState =
      nextReserved > 0 ? "RESERVED" :
      nextPaid > 0 && nextAvailable > 0 ? "PARTIALLY_PAID" :
      nextPaid > 0 ? "PAID" :
      nextHeld > 0 ? "HELD" :
      "UNPAID";

    params.tx.set(settlementRef, {
      payoutReservedAmountZar: nextReserved,
      payoutPaidAmountZar: nextPaid,
      availableForPayoutZar: nextAvailable,
      payoutState: nextPayoutState,
      updatedAt: nowServerTs(),
    }, {merge: true});
    if (payableSnap.exists) {
      params.tx.set(payableRef, {
        reservedAmountZar: nextReserved,
        paidAmountZar: nextPaid,
        availableAmountZar: nextAvailable,
        payoutState: nextPayoutState,
        payableStatus:
          nextHeld > 0 ? "blocked" :
          nextPaid > 0 && nextAvailable > 0 ? "partially_paid" :
          nextPaid > 0 ? "paid" :
          nextReserved > 0 ? "reserved" :
          "settled_zero",
        updatedAt: nowServerTs(),
      }, {merge: true});
    }

    params.tx.set(allocationDoc.ref, {
      status: "PAID",
      updatedAt: nowServerTs(),
    }, {merge: true});
    paidTotal = toMoney(paidTotal + allocatedAmountZar);
  }

  return paidTotal;
}

async function releaseAllocationsForProviderEvent(params: {
  tx: admin.firestore.Transaction;
  payoutRef: admin.firestore.DocumentReference;
}): Promise<number> {
  const db = getDb();
  const allocationsSnap = await params.tx.get(params.payoutRef.collection("allocations"));
  let releasedTotal = 0;

  for (const allocationDoc of allocationsSnap.docs) {
    const allocationData = allocationDoc.data() ?? {};
    if (toUpper(allocationData.status) !== "RESERVED") {
      continue;
    }
    const settlementId = toTrimmedString(allocationData.settlementId);
    const allocatedAmountZar = asMoney(allocationData.allocatedAmountZar, 0);
    if (!settlementId || allocatedAmountZar <= 0) {
      continue;
    }

    const settlementRef = db.collection("tutor_session_settlements").doc(settlementId);
    const payableRef = db.collection("tutor_payables").doc(settlementId);
    const [settlementSnap, payableSnap] = await Promise.all([
      params.tx.get(settlementRef),
      params.tx.get(payableRef),
    ]);
    if (!settlementSnap.exists) {
      continue;
    }

    const settlementData = settlementSnap.data() ?? {};
    const payableData = payableSnap.data() ?? {};
    const nextReserved = toMoney(
      Math.max(
        0,
        asMoney(
          payableData.reservedAmountZar ?? settlementData.payoutReservedAmountZar,
          0
        ) - allocatedAmountZar
      )
    );
    const nextPaid = asMoney(
      payableData.paidAmountZar ?? settlementData.payoutPaidAmountZar,
      0
    );
    const nextHeld = asMoney(
      payableData.blockedAmountZar ?? settlementData.disputeHeldAmountZar,
      0
    );
    const nextEarning = asMoney(
      payableData.grossTutorEarningZar ?? settlementData.tutorEarningZar,
      0
    );
    const nextAvailable = toMoney(
      Math.max(0, nextEarning - nextReserved - nextPaid - nextHeld)
    );
    const nextPayoutState =
      nextHeld > 0 ? "HELD" :
      nextReserved > 0 ? "RESERVED" :
      nextPaid > 0 ? "PARTIALLY_PAID" :
      "UNPAID";

    params.tx.set(settlementRef, {
      payoutReservedAmountZar: nextReserved,
      availableForPayoutZar: nextAvailable,
      payoutState: nextPayoutState,
      updatedAt: nowServerTs(),
    }, {merge: true});
    if (payableSnap.exists) {
      params.tx.set(payableRef, {
        reservedAmountZar: nextReserved,
        availableAmountZar: nextAvailable,
        payoutState: nextPayoutState,
        payableStatus:
          nextHeld > 0 ? "blocked" :
          nextReserved > 0 ? "reserved" :
          nextAvailable > 0 ? "available" :
          nextPaid > 0 ? "partially_paid" :
          "settled_zero",
        updatedAt: nowServerTs(),
      }, {merge: true});
    }

    params.tx.set(allocationDoc.ref, {
      status: "RELEASED",
      updatedAt: nowServerTs(),
    }, {merge: true});
    releasedTotal = toMoney(releasedTotal + allocatedAmountZar);
  }

  return releasedTotal;
}

async function applyTransferSucceededEvent(params: {
  tx: admin.firestore.Transaction;
  event: NormalizedPaymentEvent;
  mapped: PaymentEventMapperResult;
}): Promise<void> {
  const db = getDb();
  const payoutRef = db.collection("tutor_payouts").doc(params.mapped.primaryTargetId);
  const payoutSnap = await params.tx.get(payoutRef);
  if (!payoutSnap.exists) {
    throw new PaymentEventProcessingError(
      "PAYMENT_EVENT_PAYOUT_NOT_FOUND",
      "dead_letter",
      "transfer event payout was not found."
    );
  }

  const payoutData = payoutSnap.data() ?? {};
  const status = toUpper(payoutData.status);
  if (status === "PAID") {
    params.tx.set(payoutRef, {
      externalTransferId:
        params.event.transferCode ||
        params.event.transferReference ||
        payoutData.externalTransferId ||
        null,
      providerStatus: "SETTLED",
      updatedAt: nowServerTs(),
    }, {merge: true});
    return;
  }
  if (["FAILED", "REJECTED", "CANCELLED"].includes(status)) {
    throw new PaymentEventProcessingError(
      "PAYMENT_EVENT_TRANSFER_CONFLICT",
      "dead_letter",
      "transfer_succeeded cannot auto-reconcile a payout that was already failed or cancelled."
    );
  }

  const tutorId = toTrimmedString(payoutData.tutorId);
  const balanceRef = db.collection("tutor_balances").doc(tutorId);
  const tutorRef = db.collection("users").doc(tutorId);
  const balanceSnap = await params.tx.get(balanceRef);
  const balanceData = balanceSnap.data() ?? {};
  const paidTotal = await markAllocationsPaidForProviderEvent({
    tx: params.tx,
    payoutRef,
  });

  const nextPayout = {
    ...payoutData,
    status: "PAID",
    providerStatus: "SETTLED",
    externalTransferId:
      params.event.transferCode ||
      params.event.transferReference ||
      toTrimmedString(payoutData.externalTransferId) ||
      null,
    externalBatchId:
      params.event.payoutBatchId ||
      toTrimmedString(payoutData.externalBatchId) ||
      null,
    paidAt: payoutData.paidAt ?? nowServerTs(),
    updatedAt: nowServerTs(),
  };
  params.tx.set(payoutRef, {
    ...nextPayout,
    ...buildPayoutRecordSchemaFields(payoutRef.id, nextPayout),
  }, {merge: true});

  params.tx.set(balanceRef, {
    reservedForPayoutZar: toMoney(
      Math.max(0, asMoney(balanceData.reservedForPayoutZar, 0) - paidTotal)
    ),
    paidOutZar: toMoney(asMoney(balanceData.paidOutZar, 0) + paidTotal),
    lastPayoutAt: nowServerTs(),
    updatedAt: nowServerTs(),
  }, {merge: true});
  params.tx.set(tutorRef, {
    walletPayoutPendingZar: admin.firestore.FieldValue.increment(-paidTotal),
    walletUpdatedAt: nowServerTs(),
  }, {merge: true});

  await createProviderPayoutEvent({
    tx: params.tx,
    payoutId: payoutRef.id,
    tutorId,
    eventType: "PROVIDER_TRANSFER_SUCCEEDED",
    metadata: {
      externalEventId: params.event.externalEventId,
      transferCode: params.event.transferCode,
      transferReference: params.event.transferReference,
      provider: params.event.provider,
    },
  });
}

async function applyTransferFailedEvent(params: {
  tx: admin.firestore.Transaction;
  event: NormalizedPaymentEvent;
  mapped: PaymentEventMapperResult;
}): Promise<void> {
  const db = getDb();
  const payoutRef = db.collection("tutor_payouts").doc(params.mapped.primaryTargetId);
  const payoutSnap = await params.tx.get(payoutRef);
  if (!payoutSnap.exists) {
    throw new PaymentEventProcessingError(
      "PAYMENT_EVENT_PAYOUT_NOT_FOUND",
      "dead_letter",
      "transfer event payout was not found."
    );
  }

  const payoutData = payoutSnap.data() ?? {};
  const status = toUpper(payoutData.status);
  if (status === "FAILED" || status === "REJECTED") {
    params.tx.set(payoutRef, {
      providerStatus: "FAILED",
      failureReason:
        params.event.reason ||
        toTrimmedString(payoutData.failureReason) ||
        "provider_transfer_failed",
      updatedAt: nowServerTs(),
    }, {merge: true});
    return;
  }
  if (status === "PAID") {
    throw new PaymentEventProcessingError(
      "PAYMENT_EVENT_TRANSFER_ALREADY_PAID",
      "dead_letter",
      "transfer_failed cannot reverse a payout that is already marked paid."
    );
  }

  const tutorId = toTrimmedString(payoutData.tutorId);
  const balanceRef = db.collection("tutor_balances").doc(tutorId);
  const balanceSnap = await params.tx.get(balanceRef);
  const balanceData = balanceSnap.data() ?? {};
  const releasedTotal = await releaseAllocationsForProviderEvent({
    tx: params.tx,
    payoutRef,
  });

  const nextPayout = {
    ...payoutData,
    status: "FAILED",
    providerStatus: "FAILED",
    failureReason:
      params.event.reason ||
      toTrimmedString(payoutData.failureReason) ||
      "provider_transfer_failed",
    failedAt: payoutData.failedAt ?? nowServerTs(),
    updatedAt: nowServerTs(),
  };
  params.tx.set(payoutRef, {
    ...nextPayout,
    ...buildPayoutRecordSchemaFields(payoutRef.id, nextPayout),
  }, {merge: true});
  params.tx.set(balanceRef, {
    reservedForPayoutZar: toMoney(
      Math.max(0, asMoney(balanceData.reservedForPayoutZar, 0) - releasedTotal)
    ),
    availableBalanceZar: toMoney(
      asMoney(balanceData.availableBalanceZar, 0) + releasedTotal
    ),
    updatedAt: nowServerTs(),
  }, {merge: true});

  await createProviderPayoutEvent({
    tx: params.tx,
    payoutId: payoutRef.id,
    tutorId,
    eventType: "PROVIDER_TRANSFER_FAILED",
    note: nextPayout.failureReason,
    metadata: {
      externalEventId: params.event.externalEventId,
      transferCode: params.event.transferCode,
      transferReference: params.event.transferReference,
      provider: params.event.provider,
    },
  });
}

async function applyPaymentEventMutation(params: {
  tx: admin.firestore.Transaction;
  event: NormalizedPaymentEvent;
  mapped: PaymentEventMapperResult;
}): Promise<void> {
  switch (params.event.eventType) {
  case "authorization_created":
  case "authorization_reserved":
  case "authorization_reserve_failed":
    await applyAuthorizationEvent(params);
    return;
  case "capture_succeeded":
  case "capture_failed":
    await applyCaptureEvent(params);
    return;
  case "release_succeeded":
    await applyReleaseEvent(params);
    return;
  case "transfer_succeeded":
    await applyTransferSucceededEvent(params);
    return;
  case "transfer_failed":
    await applyTransferFailedEvent(params);
    return;
  default:
    throw new PaymentEventProcessingError(
      "PAYMENT_EVENT_UNSUPPORTED_TYPE",
      "dead_letter",
      `Unsupported payment event type: ${params.event.eventType}`
    );
  }
}

function basePaymentEventDoc(
  paymentEventId: string,
  event: NormalizedPaymentEvent,
  mapped: PaymentEventMapperResult,
  attemptCount: number
): Record<string, unknown> {
  return {
    paymentEventId,
    provider: event.provider,
    adapterKey: event.adapterKey,
    externalEventId: event.externalEventId,
    providerEventUniqueKey: `${event.provider}|${event.externalEventId}`,
    eventType: event.eventType,
    paymentRail: event.paymentRail,
    status: "received",
    attemptCount,
    authorizationId:
      mapped.primaryTargetCollection === "payment_authorizations" ?
        mapped.primaryTargetId :
        (event.authorizationId || null),
    captureId:
      mapped.primaryTargetCollection === "payment_captures" ?
        mapped.primaryTargetId :
        (event.captureId || null),
    releaseId:
      mapped.primaryTargetCollection === "payment_reversals" ?
        mapped.primaryTargetId :
        (event.releaseId || null),
    payoutId:
      mapped.primaryTargetCollection === "tutor_payouts" ?
        mapped.primaryTargetId :
        (event.payoutId || null),
    payoutBatchId: event.payoutBatchId,
    bookingId: event.bookingId || null,
    paymentSessionId: event.paymentSessionId || null,
    sessionId: event.sessionId || null,
    tutorId: event.tutorId || null,
    amountZar: mapped.amountZar,
    currency: mapped.currency,
    providerReference: event.providerReference,
    authorizationReference: event.authorizationReference,
    captureReference: event.captureReference,
    releaseReference: event.releaseReference,
    transferReference: event.transferReference,
    transferCode: event.transferCode,
    recipientCode: event.recipientCode,
    providerStatus: event.providerStatus,
    reason: event.reason,
    primaryTargetCollection: mapped.primaryTargetCollection,
    primaryTargetId: mapped.primaryTargetId,
    secondaryTargetCollection: mapped.secondaryTargetCollection,
    secondaryTargetId: mapped.secondaryTargetId,
    metadata: event.metadata,
    raw: event.raw,
    updatedAt: nowServerTs(),
  };
}

function resultFromEventDoc(
  paymentEventId: string,
  event: NormalizedPaymentEvent,
  status: PaymentEventStatus,
  deduplicated: boolean,
  attemptCount: number,
  mapped: PaymentEventMapperResult | null,
  errorCode: string | null,
  errorMessage: string | null
): PaymentEventProcessResult {
  return {
    paymentEventId,
    provider: event.provider,
    externalEventId: event.externalEventId,
    eventType: event.eventType,
    status,
    deduplicated,
    attemptCount,
    paymentRail: event.paymentRail,
    primaryTargetCollection: mapped?.primaryTargetCollection ?? null,
    primaryTargetId: mapped?.primaryTargetId ?? null,
    secondaryTargetCollection: mapped?.secondaryTargetCollection ?? null,
    secondaryTargetId: mapped?.secondaryTargetId ?? null,
    errorCode,
    errorMessage,
  };
}

function failureStatusForError(
  error: unknown,
  attemptCount: number
): Exclude<PaymentEventStatus, "processed" | "received"> {
  if (error instanceof PaymentEventProcessingError &&
      error.finalStatus === "dead_letter") {
    return "dead_letter";
  }
  return attemptCount >= MAX_FAILURE_ATTEMPTS ? "dead_letter" : "failed";
}

function failureCode(error: unknown): string {
  if (error instanceof PaymentEventProcessingError) {
    return error.errorCode;
  }
  if (error instanceof Error && error.name) {
    return error.name;
  }
  return "PAYMENT_EVENT_UNKNOWN_ERROR";
}

function failureMessage(error: unknown): string {
  if (error instanceof Error && error.message) {
    return error.message;
  }
  return "Payment event processing failed.";
}

export async function processPaymentEventJob(
  eventInput: PaymentEventInput
): Promise<PaymentEventProcessResult> {
  const db = getDb();
  const trace = fallbackEventTrace(eventInput);
  let event: NormalizedPaymentEvent;
  let mapped: PaymentEventMapperResult;
  try {
    event = normalizePaymentEventInput(eventInput);
    mapped = mapPaymentEvent(event);
  } catch (error) {
    const eventRef = db.collection(PAYMENT_EVENTS_COLLECTION).doc(trace.paymentEventId);
    const preSnap = await eventRef.get();
    const preData = preSnap.data() ?? {};
    const attemptCount = Math.max(1, asAttemptCount(preData.attemptCount) + 1);
    const status = failureStatusForError(error, attemptCount);
    const errorCode = failureCode(error);
    const errorMessage = failureMessage(error);
    await eventRef.set({
      paymentEventId: trace.paymentEventId,
      provider: trace.provider,
      adapterKey: toTrimmedString(eventInput.adapterKey) || trace.provider.toLowerCase(),
      externalEventId: trace.externalEventId,
      providerEventUniqueKey: `${trace.provider}|${trace.externalEventId}`,
      eventType: toTrimmedString(eventInput.eventType) || null,
      paymentRail: normalizePaymentRail(eventInput.paymentRail),
      status,
      attemptCount,
      raw: toRecord(eventInput),
      lastErrorCode: errorCode,
      lastErrorMessage: errorMessage,
      receivedAt: preData.receivedAt ?? nowServerTs(),
      lastReceivedAt: nowServerTs(),
      failedAt: status === "failed" ? nowServerTs() : admin.firestore.FieldValue.delete(),
      deadLetteredAt:
        status === "dead_letter" ? nowServerTs() : admin.firestore.FieldValue.delete(),
      updatedAt: nowServerTs(),
      processingVersion: 1,
    }, {merge: true});

    logger.error("payments.processPaymentEvent.normalize_failed", {
      paymentEventId: trace.paymentEventId,
      provider: trace.provider,
      externalEventId: trace.externalEventId,
      status,
      errorCode,
      errorMessage,
    });

    return {
      paymentEventId: trace.paymentEventId,
      provider: trace.provider,
      externalEventId: trace.externalEventId,
      eventType: toTrimmedString(eventInput.eventType) || "unknown",
      status,
      deduplicated: false,
      attemptCount,
      paymentRail: normalizePaymentRail(eventInput.paymentRail),
      primaryTargetCollection: null,
      primaryTargetId: null,
      secondaryTargetCollection: null,
      secondaryTargetId: null,
      errorCode,
      errorMessage,
    };
  }

  const paymentEventId = paymentEventDocumentId(
    event.provider,
    event.externalEventId
  );
  const eventRef = db.collection(PAYMENT_EVENTS_COLLECTION).doc(paymentEventId);
  const preSnap = await eventRef.get();
  const preData = preSnap.data() ?? {};
  const preStatus = toLower(preData.status) as PaymentEventStatus;
  if (preStatus === "processed") {
    logger.info("payments.processPaymentEvent.deduplicated", {
      paymentEventId,
      provider: event.provider,
      externalEventId: event.externalEventId,
      eventType: event.eventType,
    });
    return resultFromEventDoc(
      paymentEventId,
      event,
      "processed",
      true,
      asAttemptCount(preData.attemptCount),
      mapped,
      null,
      null
    );
  }

  const nextAttemptCount = Math.max(1, asAttemptCount(preData.attemptCount) + 1);
  try {
    const result = await db.runTransaction(async (tx) => {
      const currentSnap = await tx.get(eventRef);
      const currentData = currentSnap.data() ?? {};
      if (toLower(currentData.status) === "processed") {
        return resultFromEventDoc(
          paymentEventId,
          event,
          "processed",
          true,
          asAttemptCount(currentData.attemptCount),
          mapped,
          null,
          null
        );
      }

      await applyPaymentEventMutation({
        tx,
        event,
        mapped,
      });

      tx.set(eventRef, {
        ...basePaymentEventDoc(paymentEventId, event, mapped, nextAttemptCount),
        status: "processed",
        receivedAt: currentData.receivedAt ?? nowServerTs(),
        lastReceivedAt: nowServerTs(),
        processedAt: nowServerTs(),
        failedAt: admin.firestore.FieldValue.delete(),
        deadLetteredAt: admin.firestore.FieldValue.delete(),
        lastErrorCode: admin.firestore.FieldValue.delete(),
        lastErrorMessage: admin.firestore.FieldValue.delete(),
        processingVersion: 1,
      }, {merge: true});

      return resultFromEventDoc(
        paymentEventId,
        event,
        "processed",
        false,
        nextAttemptCount,
        mapped,
        null,
        null
      );
    });

    logger.info("payments.processPaymentEvent.processed", {
      paymentEventId,
      provider: event.provider,
      externalEventId: event.externalEventId,
      eventType: event.eventType,
      primaryTargetCollection: mapped.primaryTargetCollection,
      primaryTargetId: mapped.primaryTargetId,
    });
    return result;
  } catch (error) {
    const status = failureStatusForError(error, nextAttemptCount);
    const errorCode = failureCode(error);
    const errorMessage = failureMessage(error);

    await eventRef.set({
      ...basePaymentEventDoc(paymentEventId, event, mapped, nextAttemptCount),
      status,
      receivedAt: preData.receivedAt ?? nowServerTs(),
      lastReceivedAt: nowServerTs(),
      failedAt: status === "failed" ? nowServerTs() : admin.firestore.FieldValue.delete(),
      deadLetteredAt:
        status === "dead_letter" ? nowServerTs() : admin.firestore.FieldValue.delete(),
      lastErrorCode: errorCode,
      lastErrorMessage: errorMessage,
      processingVersion: 1,
    }, {merge: true});

    logger.error("payments.processPaymentEvent.failed", {
      paymentEventId,
      provider: event.provider,
      externalEventId: event.externalEventId,
      eventType: event.eventType,
      status,
      errorCode,
      errorMessage,
    });

    return resultFromEventDoc(
      paymentEventId,
      event,
      status,
      false,
      nextAttemptCount,
      mapped,
      errorCode,
      errorMessage
    );
  }
}

export const processPaymentEvent = onCall(
  {region: REGION, timeoutSeconds: 120},
  async (request): Promise<PaymentEventProcessResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }
    assertPlatformAdmin(request.auth);

    const rawEvent = toRecord(request.data?.event);
    const payload = Object.keys(rawEvent).length > 0 ?
      rawEvent as PaymentEventInput :
      toRecord(request.data) as PaymentEventInput;
    return processPaymentEventJob(payload);
  }
);
