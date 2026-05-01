import {createHash} from "node:crypto";
import * as admin from "firebase-admin";
import {
  type FunctionsErrorCode,
  HttpsError,
  onCall,
} from "./callable";
import {SecretManagerServiceClient} from "@google-cloud/secret-manager";
import {AccessToken, RoomServiceClient} from "livekit-server-sdk";
import {type TutoringPaymentProvider} from "./payments/tutoringPaymentProvider";
import {getActiveTutoringPaymentProvider} from "./payments/tutorPaymentProviderSelector";
import {forceEndRoom} from "./tutorRoomControl";
import {assertTutorEligibleForTutoring} from "./tutorApprovalState";
import {
  assertGuestTutoringCustomerActive,
  guestTutoringCustomerRef,
  isAnonymousTutoringGuest,
  isGuestTutoringBooking,
  recordGuestTutoringSessionToken,
} from "./guestTutoring";
import {
  buildCaptureSchemaFields,
  buildSessionSchemaFields,
} from "./tutoringFirestoreSchema";
import {buildTutoringSettlementArtifacts} from "./tutoringSettlement";
import {
  assertBookingTransition,
  assertSessionTransition,
  deriveTutoringBookingState,
  deriveTutoringSessionState,
  resolveNoShowStateChange,
  toTutoringHttpsErrorCode,
  TutoringBookingState,
  TutoringSessionState,
  TutoringStateTransitionError,
  TutoringTransitionActor,
} from "./tutoringStateMachine";

const db = admin.firestore();
const secretClient = new SecretManagerServiceClient();

const REGION = "europe-west1";
const CURRENCY = "ZAR";
const PAYMENT_AUTHORIZED = "PAYMENT_AUTHORIZED";
const AUTH_STATUS_AUTHORIZED = "AUTHORIZED";
const SESSION_SCHEDULED = "SCHEDULED";
const SESSION_PREPARING = "PREPARING";
const SESSION_JOINABLE = "JOINABLE";
const SESSION_WAITING = "WAITING_FOR_PARTICIPANTS";
const SESSION_ACTIVE = "ACTIVE";
const SESSION_ENDING = "ENDING";
const SESSION_COMPLETED = "COMPLETED";
// @ts-ignore - May be used in future session lifecycle
const SESSION_CANCELLED = "CANCELLED";
const SESSION_MISSED = "MISSED";
// @ts-ignore - May be used in future session lifecycle
const SESSION_NO_SHOW = "NO_SHOW";
const SESSION_LOW_FUNDS = "LOW_FUNDS";
const SESSION_ENDED_INSUFFICIENT_FUNDS = "ENDED_INSUFFICIENT_FUNDS";
const LIVEKIT_ROOM_PREFIX = "tutor-";
const SESSION_JOIN_GRANT_TTL_MS = 2 * 60 * 60 * 1000;
const SESSION_JOIN_REPLAY_WINDOW_MS = 30 * 1000;
const SESSION_JOIN_LOCK_MS = 45 * 1000;

type SessionRole = "tutor" | "student";

function assertBookingStateOrThrow(params: {
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
      throw new HttpsError(toTutoringHttpsErrorCode(error), error.message);
    }
    throw error;
  }
}

function assertSessionStateOrThrow(params: {
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
      throw new HttpsError(toTutoringHttpsErrorCode(error), error.message);
    }
    throw error;
  }
}

async function isUserOnline(userId: string): Promise<boolean> {
  // TODO: Implement actual presence checking based on your presence system
  // For now, assume users are online for auto-start logic
  return true;
}
const END_SESSION_LOCK_MS = 2 * 60 * 1000;

type CaptureOutcome = "CAPTURED" | "PENDING_PROVIDER" | "FAILED";
type ReversalOutcome = "REVERSED" | "PENDING_PROVIDER" | "FAILED";

type SessionLifecycleState =
  | "SCHEDULED"
  | "PREPARING"
  | "JOINABLE"
  | "WAITING_FOR_PARTICIPANTS"
  | "ACTIVE"
  | "ENDING"
  | "COMPLETED"
  | "CANCELLED"
  | "MISSED"
  | "NO_SHOW"
  | "LOW_FUNDS"
  | "ENDED_INSUFFICIENT_FUNDS";

interface SessionRuntime {
  sessionId: string;
  bookingId: string;
  status: SessionLifecycleState;
  scheduledStartAt?: admin.firestore.Timestamp;
  actualStartAt?: admin.firestore.Timestamp;
  completedAt?: admin.firestore.Timestamp;
  tutorId: string;
  studentId: string;
  roomName: string;
  callMode: "P2P" | "SFU";
  pricingSnapshot: {
    tutorBaseRateZar: number;
    platformFeeZar: number;
    studentRateZar: number;
  };
  participants: {
    [userId: string]: {
      role: SessionRole;
      joinedAt?: admin.firestore.Timestamp;
      joinState: "PENDING" | "JOINED" | "LEFT";
    };
  };
  gracePeriodMinutes: number;
  autoStartEnabled: boolean;
}

interface StartSessionResult {
  bookingId: string;
  sessionId: string;
  room: string;
  status: string;
  participantRole: SessionRole;
  joinedParticipantCount: number;
  sessionStartAt: string | null;
  livekitUrl: string;
  token: string;
  joinGrantId: string;
  joinGrantExpiresAt: string;
  guestSessionTokenId?: string;
  guestSessionTokenExpiresAt?: string | null;
}

interface StartSessionGrantResult {
  bookingId: string;
  sessionId: string;
  room: string;
  participantRole: SessionRole;
  joinedParticipantCount: number;
  guestTutoringMode: boolean;
  joinGrantId: string;
  joinGrantExpiresAtIso: string;
}

interface EndSessionResult {
  sessionId: string;
  bookingId: string;
  paymentIntentId: string;
  settlementId: string;
  status: string;
  settlementStatus: string;
  billableMinutes: number;
  finalAmountDueZar: number;
  capturedTotalZar: number;
  pendingCaptureTotalZar: number;
  tutorEarningZar: number;
  platformFeeZar: number;
  releasedAuthorizationAmountZar: number;
  pendingReleasedAuthorizationAmountZar: number;
  ratingRequired: boolean;
}

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

interface AuthorizationState {
  ref: admin.firestore.DocumentReference;
  id: string;
  data: Record<string, unknown>;
  amountZar: number;
  capturedAmountZar: number;
  pendingCaptureAmountZar: number;
  reversedAmountZar: number;
  pendingReversalAmountZar: number;
  remainingAuthorizedZar: number;
  status: string;
  providerPaymentId: string;
}

interface CaptureExecutionResult {
  captureId: string;
  status: CaptureOutcome;
  accountedAmountZar: number;
}

interface ReversalExecutionResult {
  reversalId: string;
  status: ReversalOutcome;
  accountedAmountZar: number;
}

interface SessionClosePreparation {
  sessionId: string;
  bookingId: string;
  paymentIntentId: string;
  studentId: string;
  guestTutoringMode: boolean;
  tutorId: string;
  studentName: string;
  tutorName: string;
  roomName: string;
  billableMinutes: number;
  finalAmountDueZar: number;
  studentRatePerMinZar: number;
  tutorRatePerMinZar: number;
  currency: string;
  subject: string;
  topic: string;
  organizationId: string;
  organizationName: string;
  organizationLogoUrl: string;
  organizationMemberTitle: string;
}

function toTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function normalizeUpper(value: unknown): string {
  return toTrimmedString(value).toUpperCase();
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

function getPaymentProviderContext(): PaymentProviderContext {
  return {
    provider: getActiveTutoringPaymentProvider(),
  };
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

function classifyPeachResult(
  resultCode: string
): "AUTHORIZED" | "PENDING_PROVIDER" | "FAILED" {
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

function classifyReversalResult(resultCode: string): ReversalOutcome {
  const base = classifyPeachResult(resultCode);
  if (base === "AUTHORIZED") return "REVERSED";
  if (base === "PENDING_PROVIDER") return "PENDING_PROVIDER";
  return "FAILED";
}

function nowServerTs() {
  return admin.firestore.FieldValue.serverTimestamp();
}

function throwStartSessionError(
  code: FunctionsErrorCode,
  message: string,
  errorCode: string,
  details: Record<string, unknown> = {}
): never {
  throw new HttpsError(code, message, {
    errorCode,
    ...details,
  });
}

function asWholeNumber(value: unknown, fallback = 0): number {
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

function authorizationIdForBooking(bookingId: string): string {
  return `pa_${bookingId}_initial`;
}

function roomNameForSession(sessionId: string): string {
  return `${LIVEKIT_ROOM_PREFIX}${sessionId}`;
}

function buildSessionJoinGrantId(params: {
  bookingId: string;
  userId: string;
  role: SessionRole;
  sequence: number;
}): string {
  return createHash("sha256")
    .update([
      params.bookingId,
      params.userId,
      params.role,
      String(params.sequence),
    ].join("|"))
    .digest("hex")
    .slice(0, 24);
}

export function deriveProtectedSessionState(
  sessionData: Record<string, unknown>,
  paymentIntentData: Record<string, unknown>
): {
  protectedMinutesPurchased: number;
  protectedMinutesRemaining: number;
  consumedMinutes: number;
} {
  const protectedMinutesPurchased = Math.max(
    asWholeNumber(sessionData.protectedMinutesPurchased, -1),
    asWholeNumber(paymentIntentData.protectedMinutesPurchased, 0)
  );
  const consumedMinutes = Math.max(
    asWholeNumber(sessionData.consumedMinutes, -1),
    asWholeNumber(paymentIntentData.consumedMinutes, 0)
  );
  const protectedMinutesRemaining = Math.max(
    0,
    Math.max(
      asWholeNumber(sessionData.protectedMinutesRemaining, -1),
      asWholeNumber(paymentIntentData.protectedMinutesRemaining, 0),
      protectedMinutesPurchased - consumedMinutes
    )
  );
  return {
    protectedMinutesPurchased: Math.max(0, protectedMinutesPurchased),
    protectedMinutesRemaining,
    consumedMinutes: Math.max(0, consumedMinutes),
  };
}

export function bookingAllowsSessionStart(
  bookingData: Record<string, unknown>,
  paymentIntentData: Record<string, unknown>
): boolean {
  const states = [
    bookingData.paymentStatus,
    bookingData.authorizationStatus,
    bookingData.status,
    bookingData.sessionState,
    paymentIntentData.paymentAuthorizationStatus,
  ].map(normalizeUpper);

  return states.includes(PAYMENT_AUTHORIZED) || states.includes("CONFIRMED");
}

export function authorizationIsValid(
  authorizationData: Record<string, unknown>,
  bookingData: Record<string, unknown>,
  paymentIntentData: Record<string, unknown>
): boolean {
  const authorizationStatus = normalizeUpper(authorizationData.status);
  const bookingPaymentStatus = normalizeUpper(bookingData.paymentStatus);
  const bookingAuthorizationStatus = normalizeUpper(bookingData.authorizationStatus);
  const intentAuthorizationStatus = normalizeUpper(
    paymentIntentData.paymentAuthorizationStatus
  );

  return authorizationStatus === AUTH_STATUS_AUTHORIZED && (
    bookingPaymentStatus === PAYMENT_AUTHORIZED ||
    bookingAuthorizationStatus === PAYMENT_AUTHORIZED ||
    intentAuthorizationStatus === PAYMENT_AUTHORIZED
  );
}

export interface SessionStartReadiness {
  allowed: boolean;
  errorCode: string | null;
  bookingState: TutoringBookingState;
  protectionState: {
    protectedMinutesPurchased: number;
    protectedMinutesRemaining: number;
    consumedMinutes: number;
  };
}

export function evaluateSessionStartReadiness(params: {
  bookingData: Record<string, unknown>;
  paymentIntentData: Record<string, unknown>;
  authorizationData: Record<string, unknown> | null;
  existingSessionData?: Record<string, unknown>;
}): SessionStartReadiness {
  const bookingState = deriveTutoringBookingState(params.bookingData);
  const existingSessionData = params.existingSessionData ?? {};
  const currentSessionLifecycle =
    Object.keys(existingSessionData).length > 0 ?
      deriveTutoringSessionState(existingSessionData) :
      null;
  const sessionAlreadyActive =
    normalizeUpper(existingSessionData.status) === SESSION_ACTIVE ||
    currentSessionLifecycle === TutoringSessionState.ACTIVE;
  const protectionState = deriveProtectedSessionState(
    existingSessionData,
    params.paymentIntentData
  );

  if (
    !sessionAlreadyActive &&
    ![
      TutoringBookingState.PAYMENT_AUTHORIZED,
      TutoringBookingState.CONFIRMED,
    ].includes(bookingState)
  ) {
    return {
      allowed: false,
      errorCode: "START_SESSION_BOOKING_NOT_READY",
      bookingState,
      protectionState,
    };
  }
  if (
    sessionAlreadyActive &&
    !bookingAllowsSessionStart(params.bookingData, params.paymentIntentData)
  ) {
    return {
      allowed: false,
      errorCode: "START_SESSION_AUTHORIZATION_INVALID",
      bookingState,
      protectionState,
    };
  }
  if (!params.authorizationData) {
    return {
      allowed: false,
      errorCode: "START_SESSION_AUTHORIZATION_REQUIRED",
      bookingState,
      protectionState,
    };
  }
  if (
    !authorizationIsValid(
      params.authorizationData,
      params.bookingData,
      params.paymentIntentData
    )
  ) {
    return {
      allowed: false,
      errorCode: "START_SESSION_AUTHORIZATION_INVALID",
      bookingState,
      protectionState,
    };
  }
  if (protectionState.protectedMinutesPurchased <= 0) {
    return {
      allowed: false,
      errorCode: "START_SESSION_PROTECTION_REQUIRED",
      bookingState,
      protectionState,
    };
  }
  if (protectionState.protectedMinutesRemaining <= 0) {
    return {
      allowed: false,
      errorCode: "START_SESSION_PROTECTION_EXHAUSTED",
      bookingState,
      protectionState,
    };
  }

  return {
    allowed: true,
    errorCode: null,
    bookingState,
    protectionState,
  };
}

let liveKitEnvLoaded = false;

async function readSecretValue(name: string): Promise<string> {
  const projectId =
    process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "";
  if (!projectId) return "";

  const [version] = await secretClient.accessSecretVersion({
    name: `projects/${projectId}/secrets/${name}/versions/latest`,
  });
  return version.payload?.data?.toString() || "";
}

async function ensureLiveKitEnv(): Promise<void> {
  if (liveKitEnvLoaded) return;

  const [url, apiKey, apiSecret] = await Promise.all([
    process.env.LIVEKIT_URL || readSecretValue("livekit_url"),
    process.env.LIVEKIT_API_KEY || readSecretValue("livekit_api_key"),
    process.env.LIVEKIT_API_SECRET || readSecretValue("livekit_api_secret"),
  ]);

  if (url) process.env.LIVEKIT_URL = url;
  if (apiKey) process.env.LIVEKIT_API_KEY = apiKey;
  if (apiSecret) process.env.LIVEKIT_API_SECRET = apiSecret;
  liveKitEnvLoaded = true;
}

async function liveKitConfig() {
  await ensureLiveKitEnv();
  return {
    url: process.env.LIVEKIT_URL || "",
    apiKey: process.env.LIVEKIT_API_KEY || "",
    apiSecret: process.env.LIVEKIT_API_SECRET || "",
  };
}

async function ensureTutorRoom(roomName: string): Promise<string> {
  const {url, apiKey, apiSecret} = await liveKitConfig();
  if (!url || !apiKey || !apiSecret) {
    throw new HttpsError(
      "failed-precondition",
      "LiveKit is not configured for tutor sessions."
    );
  }

  const client = new RoomServiceClient(url, apiKey, apiSecret);
  try {
    await client.createRoom({name: roomName});
  } catch {
    // Ignore room-already-exists style errors so startSession stays idempotent.
  }
  return url;
}

async function buildTutorSessionToken(
  roomName: string,
  uid: string,
  role: SessionRole,
  metadataOverrides: Record<string, unknown> = {}
): Promise<{token: string; livekitUrl: string}> {
  const {url, apiKey, apiSecret} = await liveKitConfig();
  if (!url || !apiKey || !apiSecret) {
    throw new HttpsError(
      "failed-precondition",
      "LiveKit is not configured for tutor sessions."
    );
  }

  const token = new AccessToken(apiKey, apiSecret, {
    identity: uid,
    metadata: JSON.stringify({
      role,
      product: "tutoring",
      ...metadataOverrides,
    }),
    ttl: "2h",
  });
  token.addGrant({
    room: roomName,
    roomJoin: true,
    canPublish: true,
    canSubscribe: true,
    canPublishData: true,
  });

  return {
    token: await token.toJwt(),
    livekitUrl: url,
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

async function createPeachReversal(params: {
  config: PaymentProviderContext;
  authorizationPaymentId: string;
  amountZar: number;
  merchantTransactionId: string;
  bookingId: string;
  paymentIntentId: string;
  sessionId: string;
}): Promise<PeachApiResult> {
  return params.config.provider.reverse({
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

function buildEndCaptureId(params: {
  sessionId: string;
  billableMinutes: number;
  authorizationId: string;
  index: number;
}): string {
  return `pc_${params.sessionId}_end_${params.billableMinutes}_${params.index}_${params.authorizationId}`;
}

function buildEndReversalId(params: {
  sessionId: string;
  authorizationId: string;
}): string {
  return `rv_${params.sessionId}_${params.authorizationId}`;
}

function buildEndSessionResult(
  settlementId: string,
  data: Record<string, unknown>
): EndSessionResult {
  return {
    sessionId: toTrimmedString(data.sessionId) || settlementId,
    bookingId: toTrimmedString(data.bookingId) || settlementId,
    paymentIntentId: toTrimmedString(data.paymentIntentId) || settlementId,
    settlementId,
    status: toTrimmedString(data.status) || "completed",
    settlementStatus: toTrimmedString(data.settlementStatus) || "completed",
    billableMinutes: Math.max(0, Math.round(Number(data.billableMinutes ?? 0))),
    finalAmountDueZar: asMoney(data.finalAmountDueZar, 0),
    capturedTotalZar: asMoney(data.capturedTotalZar, 0),
    pendingCaptureTotalZar: asMoney(data.pendingCaptureTotalZar, 0),
    tutorEarningZar: asMoney(data.tutorEarningZar, 0),
    platformFeeZar: asMoney(data.platformFeeZar, 0),
    releasedAuthorizationAmountZar:
      asMoney(data.releasedAuthorizationAmountZar, 0),
    pendingReleasedAuthorizationAmountZar:
      asMoney(data.pendingReleasedAuthorizationAmountZar, 0),
    ratingRequired: data.ratingRequired === true,
  };
}

async function determineCallMode(participants: string[], tutorIds: string[]): Promise<"P2P" | "SFU"> {
  const participantCount = participants.length;
  const tutorCount = tutorIds.length;

  // 1 tutor + 1 student = FREE P2P WebRTC
  if (participantCount === 2 && tutorCount === 1) {
    return "P2P";
  }

  // 3+ participants OR 2+ tutors = SFU
  if (participantCount >= 3 || tutorCount >= 2) {
    return "SFU";
  }

  // Default to P2P for safety, only upgrade when justified
  return "P2P";
}

// @ts-ignore - Exported for use by scheduled functions
async function prepareSessionRuntime(sessionId: string): Promise<void> {
  const sessionRef = db.collection("tutoring_sessions").doc(sessionId);
  const bookingRef = db.collection("tutor_requests").doc(sessionId);

  await db.runTransaction(async (tx) => {
    const sessionSnap = await tx.get(sessionRef);
    const bookingSnap = await tx.get(bookingRef);

    if (!sessionSnap.exists || !bookingSnap.exists) {
      throw new Error("Session or booking not found");
    }

    const sessionData = sessionSnap.data()!;
    const bookingData = bookingSnap.data()!;

    if (sessionData.status !== SESSION_SCHEDULED) {
      return; // Already processed
    }

    const tutorId = bookingData.tutorId;
    const studentId = bookingData.studentId;
    const participants = [tutorId, studentId];
    const tutorIds = [tutorId];

    const callMode = await determineCallMode(participants, tutorIds);
    const roomName = roomNameForSession(sessionId);

    // Pre-create LiveKit room
    if (callMode === "SFU") {
      await ensureTutorRoom(roomName);
    }

    // Snapshot pricing
    const pricingSnapshot = {
      tutorBaseRateZar: bookingData.tutorRatePerMinute || 0,
      platformFeeZar: bookingData.platformFeePerMinute || 0,
      studentRateZar: bookingData.totalRatePerMinute || 0,
    };
    assertSessionStateOrThrow({
      current: deriveTutoringSessionState(sessionData as Record<string, unknown>),
      next: TutoringSessionState.READY,
      actor: TutoringTransitionActor.SYSTEM,
      isGuestSession: isGuestTutoringBooking(
        bookingData as Record<string, unknown>
      ),
    });

    const runtime: SessionRuntime = {
      sessionId,
      bookingId: sessionId,
      status: SESSION_PREPARING,
      scheduledStartAt: bookingData.scheduledAt,
      tutorId,
      studentId,
      roomName,
      callMode,
      pricingSnapshot,
      participants: {
        [tutorId]: { role: "tutor", joinState: "PENDING" },
        [studentId]: { role: "student", joinState: "PENDING" },
      },
      gracePeriodMinutes: 15, // 15 minute grace period
      autoStartEnabled: true,
    };

    tx.set(sessionRef, {
      ...runtime,
      status: SESSION_PREPARING,
      sessionLifecycleState: TutoringSessionState.READY,
      sessionTerminalState: admin.firestore.FieldValue.delete(),
      protectedMinutesPurchased: Number(sessionData.protectedMinutesPurchased ?? 0),
      protectedMinutesRemaining: Number(sessionData.protectedMinutesRemaining ?? 0),
      consumedMinutes: Number(sessionData.consumedMinutes ?? 0),
      refillAttemptCount: Number(sessionData.refillAttemptCount ?? 0),
      lowFundsAt: sessionData.lowFundsAt ?? null,
      preparedAt: nowServerTs(),
      updatedAt: nowServerTs(),
    }, { merge: true });

    tx.set(bookingRef, {
      sessionStatus: SESSION_PREPARING,
      sessionRoomName: roomName,
      sessionCallMode: callMode,
      pricingSnapshot,
      updatedAt: nowServerTs(),
    }, { merge: true });
  });
}
// @ts-ignore - Exported for use by scheduled functions

async function attemptAutoStart(sessionId: string): Promise<void> {
  const sessionRef = db.collection("tutoring_sessions").doc(sessionId);
  const bookingRef = db.collection("tutor_requests").doc(sessionId);

  await db.runTransaction(async (tx) => {
    const sessionSnap = await tx.get(sessionRef);
    const bookingSnap = await tx.get(bookingRef);

    if (!sessionSnap.exists || !bookingSnap.exists) {
      return;
    }

    const sessionData = sessionSnap.data()!;
    // @ts-ignore - May be used in future auto-start logic
    const bookingData = bookingSnap.data()!;

    if (sessionData.status !== SESSION_PREPARING && sessionData.status !== SESSION_SCHEDULED) {
      return; // Not ready for auto-start
    }

    const scheduledStart = sessionData.scheduledStartAt?.toDate();
    const now = new Date();

    if (!scheduledStart || now < scheduledStart) {
      return; // Not time yet
    }

    // Check if within grace period
    const gracePeriodEnd = new Date(scheduledStart.getTime() + (sessionData.gracePeriodMinutes || 15) * 60 * 1000);
    const isWithinGrace = now <= gracePeriodEnd;

    // Check participant availability
    const tutorOnline = await isUserOnline(sessionData.tutorId);
    const studentOnline = await isUserOnline(sessionData.studentId);

    let newStatus: SessionLifecycleState;

    if (tutorOnline && studentOnline) {
      // Both online - make joinable
      newStatus = SESSION_JOINABLE;
    } else if (isWithinGrace && (tutorOnline || studentOnline)) {
      // One online, within grace - keep preparing
      newStatus = SESSION_PREPARING;
    } else if (!isWithinGrace) {
      // Grace period expired
      newStatus = SESSION_MISSED;
    } else {
      // Neither online yet, still within grace
      newStatus = SESSION_PREPARING;
    }
    const guestTutoringMode = isGuestTutoringBooking(
      bookingData as Record<string, unknown>
    );
    const currentSessionLifecycle = deriveTutoringSessionState(
      sessionData as Record<string, unknown>
    );

    if (newStatus === SESSION_MISSED) {
      const noShowState = resolveNoShowStateChange({
        actor: TutoringTransitionActor.SCHEDULER,
        isGuestSession: guestTutoringMode,
        reason: "no_show",
      });
      assertSessionStateOrThrow({
        current: currentSessionLifecycle,
        next: noShowState.sessionState,
        actor: TutoringTransitionActor.SCHEDULER,
        isGuestSession: guestTutoringMode,
        reason: "no_show",
      });
      assertBookingStateOrThrow({
        current: deriveTutoringBookingState(bookingData as Record<string, unknown>),
        next: noShowState.bookingState,
        actor: TutoringTransitionActor.SCHEDULER,
        isGuestSession: guestTutoringMode,
        reason: "no_show",
      });

      tx.set(sessionRef, {
        status: newStatus,
        sessionLifecycleState: noShowState.sessionState,
        sessionTerminalState: noShowState.sessionState,
        endedReason: "no_show",
        noShowResolvedAt: nowServerTs(),
        lastAutoStartAttempt: nowServerTs(),
        updatedAt: nowServerTs(),
      }, { merge: true });

      tx.set(bookingRef, {
        bookingState: noShowState.bookingState,
        sessionStatus: newStatus,
        sessionState: "no_show",
        expiredAt: nowServerTs(),
        updatedAt: nowServerTs(),
      }, { merge: true });
      return;
    }

    assertSessionStateOrThrow({
      current: currentSessionLifecycle,
      next: TutoringSessionState.READY,
      actor: TutoringTransitionActor.SCHEDULER,
      isGuestSession: guestTutoringMode,
    });
    tx.set(sessionRef, {
      status: newStatus,
      sessionLifecycleState: TutoringSessionState.READY,
      lastAutoStartAttempt: nowServerTs(),
      updatedAt: nowServerTs(),
    }, { merge: true });

    tx.set(bookingRef, {
      sessionStatus: newStatus,
      updatedAt: nowServerTs(),
    }, { merge: true });
  });
}

// @ts-ignore - May be used in future validation logic
async function validateTutorPricing(tutorData: any): Promise<void> {
  const baseRate = tutorData.tutorRatePerMinute || 0;
  if (baseRate < 4) {
    throw new HttpsError("invalid-argument", "Tutor base rate must be at least R4 per minute");
  }

  const platformFee = baseRate * 0.2; // 20% markup
  const studentRate = baseRate * 1.2;

  if (Math.abs((tutorData.platformFeePerMinute || 0) - platformFee) > 0.01) {
    throw new HttpsError("invalid-argument", "Platform fee must be exactly 20% of base rate");
  }

  if (Math.abs((tutorData.totalRatePerMinute || 0) - studentRate) > 0.01) {
    throw new HttpsError("invalid-argument", "Student rate must equal base rate + 20% platform fee");
  }
}

async function validateSessionStartConditions(sessionData: any, bookingData: any, userId: string): Promise<void> {
  // Validate participant roles
  if (bookingData.studentId !== userId && bookingData.tutorId !== userId) {
    throwStartSessionError(
      "permission-denied",
      "Only session participants can start the session.",
      "START_SESSION_PARTICIPANT_MISMATCH"
    );
  }

  const guestTutoringMode = isGuestTutoringBooking(
    (bookingData ?? {}) as Record<string, unknown>
  );
  if (guestTutoringMode && bookingData.studentId === userId) {
    const guestSnap = await guestTutoringCustomerRef(String(userId)).get();
    if (!guestSnap.exists) {
      throwStartSessionError(
        "failed-precondition",
        "Guest tutoring identity is missing for this session.",
        "START_SESSION_GUEST_CUSTOMER_MISSING"
      );
    }
    try {
      assertGuestTutoringCustomerActive(
        guestSnap.data() as Record<string, unknown>,
        String(userId)
      );
    } catch (error) {
      if (error instanceof HttpsError) {
        throwStartSessionError(
          error.code,
          error.message,
          "START_SESSION_GUEST_CUSTOMER_INVALID"
        );
      }
      throw error;
    }
  }

  const tutorSnap = await db.collection("users").doc(String(bookingData.tutorId ?? "")).get();
  if (!tutorSnap.exists) {
    throwStartSessionError(
      "not-found",
      "Tutor not found.",
      "START_SESSION_TUTOR_NOT_FOUND"
    );
  }
  try {
    assertTutorEligibleForTutoring(
      tutorSnap.data() as Record<string, unknown>,
      String(bookingData.tutorId ?? "")
    );
  } catch (error) {
    if (error instanceof HttpsError) {
      throwStartSessionError(
        error.code,
        error.message,
        "START_SESSION_TUTOR_INELIGIBLE"
      );
    }
    throw error;
  }

  // Validate payment authorization exists and is valid
  const authorizationId = bookingData.paymentAuthorizationId || bookingData.authorizationId;
  if (!authorizationId) {
    throwStartSessionError(
      "failed-precondition",
      "Payment authorization required.",
      "START_SESSION_AUTHORIZATION_REQUIRED"
    );
  }

  const authorizationRef = db.collection("payment_authorizations").doc(authorizationId);
  const authorizationSnap = await authorizationRef.get();

  if (!authorizationSnap.exists) {
    throwStartSessionError(
      "failed-precondition",
      "Payment authorization not found.",
      "START_SESSION_AUTHORIZATION_REQUIRED"
    );
  }

  const authData = authorizationSnap.data()!;
  if (!authorizationIsValid(authData, bookingData, {})) {
    throwStartSessionError(
      "failed-precondition",
      "Payment authorization is invalid.",
      "START_SESSION_AUTHORIZATION_INVALID"
    );
  }

  // Validate pricing snapshot exists
  if (!bookingData.pricingSnapshot) {
    throwStartSessionError(
      "failed-precondition",
      "Session pricing must be snapshotted.",
      "START_SESSION_PRICING_SNAPSHOT_MISSING"
    );
  }

  // Validate scheduled vs instant session rules
  const isScheduled = bookingData.scheduledAt != null;
  // @ts-ignore - May be used in future instant session logic
  const isInstant = !isScheduled;

  if (isScheduled && sessionData.status === SESSION_SCHEDULED) {
    // For scheduled sessions, check if it's time to start
    const scheduledTime = bookingData.scheduledAt.toDate();
    const now = new Date();
    const gracePeriod = 15 * 60 * 1000; // 15 minutes

    if (now < new Date(scheduledTime.getTime() - gracePeriod)) {
      throwStartSessionError(
        "failed-precondition",
        "Scheduled session not ready to start yet.",
        "START_SESSION_TOO_EARLY"
      );
    }
  }

  // Validate no duplicate active sessions for tutor
  if (bookingData.tutorId === userId) {
    const currentSessionId =
      toTrimmedString(sessionData.sessionId) ||
      toTrimmedString(bookingData.tutorSessionId) ||
      toTrimmedString(bookingData.sessionId);
    const activeSessions = await db.collection("tutoring_sessions")
      .where("tutorId", "==", userId)
      .where("status", "in", [SESSION_ACTIVE, SESSION_JOINABLE, SESSION_WAITING])
      .get();
    const conflictingActiveSessions = activeSessions.docs.filter((doc) =>
      doc.id !== currentSessionId
    );

    if (conflictingActiveSessions.length > 0) {
      throwStartSessionError(
        "failed-precondition",
        "Tutor already has an active session.",
        "START_SESSION_TUTOR_BUSY"
      );
    }
  }

  // Validate call mode
  const participants = [bookingData.tutorId, bookingData.studentId];
  const tutorIds = [bookingData.tutorId];
  const expectedCallMode = await determineCallMode(participants, tutorIds);

  if (bookingData.callMode && bookingData.callMode !== expectedCallMode) {
    throwStartSessionError(
      "failed-precondition",
      "Call mode does not match participant count.",
      "START_SESSION_CALL_MODE_INVALID"
    );
  }
}

async function validateSessionBillingConditions(sessionData: any): Promise<void> {
  let resolvedSessionData = sessionData;
  const sessionId = toTrimmedString(sessionData.sessionId);
  if (
    sessionId &&
    (!sessionData.participants || !sessionData.pricingSnapshot || !sessionData.authorizationId)
  ) {
    const sessionRef = db.collection("tutoring_sessions").doc(sessionId);
    const [sessionSnap, participantsSnap] = await Promise.all([
      sessionRef.get(),
      sessionRef.collection("participants").get(),
    ]);
    if (!sessionSnap.exists) {
      throw new HttpsError("failed-precondition", "Tutoring session is missing.");
    }

    const participantMap: Record<string, {role: SessionRole; joinState: string; joinedAt?: admin.firestore.Timestamp}> = {};
    for (const participantDoc of participantsSnap.docs) {
      const participantData = participantDoc.data() ?? {};
      participantMap[participantDoc.id] = {
        role: normalizeUpper(participantData.role) === "TUTOR" ? "tutor" : "student",
        joinState: toTrimmedString(participantData.joinState) || "PENDING",
        joinedAt:
          participantData.joinedAt instanceof admin.firestore.Timestamp ?
            participantData.joinedAt :
            undefined,
      };
    }
    resolvedSessionData = {
      ...sessionSnap.data(),
      participants:
        (sessionSnap.data()?.participants as Record<string, unknown> | undefined) &&
          Object.keys(sessionSnap.data()?.participants ?? {}).length > 0 ?
          sessionSnap.data()?.participants :
          participantMap,
    };
  }

  // Only allow billing when both participants have joined
  const participants = resolvedSessionData.participants || {};
  const joinedCount = Object.values(participants).filter((p: any) => p.joinState === "JOINED").length;

  if (joinedCount < 2) {
    throw new HttpsError("failed-precondition", "Both participants must join before billing starts");
  }

  // Validate pricing snapshot
  if (!resolvedSessionData.pricingSnapshot) {
    throw new HttpsError("failed-precondition", "Session pricing snapshot required for billing");
  }

  // Validate payment authorization has sufficient funds
  const authorizationRef = db.collection("payment_authorizations").doc(resolvedSessionData.authorizationId);
  const authSnap = await authorizationRef.get();

  if (!authSnap.exists) {
    throw new HttpsError("failed-precondition", "Payment authorization missing");
  }

  const authData = authSnap.data()!;
  const remainingAuthorized = authData.remainingAuthorizedZar || 0;

  if (remainingAuthorized <= 0) {
    throw new HttpsError("failed-precondition", "Insufficient authorized funds");
  }
}

async function loadAuthorizations(bookingId: string): Promise<AuthorizationState[]> {
  const snap = await db
    .collection("payment_authorizations")
    .where("bookingId", "==", bookingId)
    .get();

  return snap.docs.map((doc) => {
    const data = doc.data() ?? {};
    const amountZar = asMoney(data.amountZar, 0);
    const capturedAmountZar = asMoney(data.capturedAmountZar, 0);
    const pendingCaptureAmountZar = asMoney(data.pendingCaptureAmountZar, 0);
    const reversedAmountZar = asMoney(
      data.reversedAmountZar ?? data.releasedAmountZar,
      0
    );
    const pendingReversalAmountZar = asMoney(
      data.pendingReversalAmountZar,
      0
    );
    return {
      ref: doc.ref,
      id: doc.id,
      data,
      amountZar,
      capturedAmountZar,
      pendingCaptureAmountZar,
      reversedAmountZar,
      pendingReversalAmountZar,
      remainingAuthorizedZar: toMoney(
        Math.max(
          0,
          amountZar -
            capturedAmountZar -
            pendingCaptureAmountZar -
            reversedAmountZar -
            pendingReversalAmountZar
        )
      ),
      status: toTrimmedString(data.status),
      providerPaymentId: toTrimmedString(toJSONObject(data.provider).paymentId),
    };
  }).sort((left, right) => left.id.localeCompare(right.id));
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
      amountZar: params.amountZar,
      accountedAmountZar,
      amountCents: Math.round(params.amountZar * 100),
      currency: CURRENCY,
      status: params.outcome,
      provider: params.providerSnapshot,
      createdAt: nowServerTs(),
      updatedAt: nowServerTs(),
      ...(params.outcome === "CAPTURED" ? {capturedAt: nowServerTs()} : {}),
      ...(params.outcome === "FAILED" ? {failedAt: nowServerTs()} : {}),
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
      updatedAt: nowServerTs(),
    }, {merge: true});

    tx.set(params.sessionRef, {
      capturedTotalZar: admin.firestore.FieldValue.increment(
        params.outcome === "CAPTURED" ? params.amountZar : 0
      ),
      pendingCaptureTotalZar: admin.firestore.FieldValue.increment(
        params.outcome === "PENDING_PROVIDER" ? params.amountZar : 0
      ),
      updatedAt: nowServerTs(),
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
      updatedAt: nowServerTs(),
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
      updatedAt: nowServerTs(),
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
}): Promise<CaptureExecutionResult> {
  const captureId = buildEndCaptureId({
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
    });
  }
}

async function recordReversalOutcome(params: {
  sessionRef: admin.firestore.DocumentReference;
  bookingRef: admin.firestore.DocumentReference;
  paymentIntentRef: admin.firestore.DocumentReference;
  authorization: AuthorizationState;
  reversalId: string;
  amountZar: number;
  providerSnapshot: Record<string, unknown>;
  outcome: ReversalOutcome;
}): Promise<ReversalExecutionResult> {
  const reversalRef = db.collection("payment_reversals").doc(params.reversalId);
  const accountedAmountZar =
    params.outcome === "FAILED" ? 0 : params.amountZar;

  return db.runTransaction(async (tx) => {
    const reversalSnap = await tx.get(reversalRef);
    if (reversalSnap.exists) {
      const existing = reversalSnap.data() ?? {};
      const existingStatus = toTrimmedString(existing.status);
      if (["REVERSED", "PENDING_PROVIDER", "FAILED"].includes(existingStatus)) {
        return {
          reversalId: params.reversalId,
          status: existingStatus as ReversalOutcome,
          accountedAmountZar: asMoney(existing.accountedAmountZar, 0),
        };
      }
    }

    tx.set(reversalRef, {
      reversalId: params.reversalId,
      tutoringPaymentRail: "TUTORING",
      authorizationId: params.authorization.id,
      bookingId: params.bookingRef.id,
      paymentIntentId: params.paymentIntentRef.id,
      sessionId: params.sessionRef.id,
      amountZar: params.amountZar,
      accountedAmountZar,
      amountCents: Math.round(params.amountZar * 100),
      currency: CURRENCY,
      status: params.outcome,
      provider: params.providerSnapshot,
      createdAt: nowServerTs(),
      updatedAt: nowServerTs(),
      ...(params.outcome === "REVERSED" ? {reversedAt: nowServerTs()} : {}),
      ...(params.outcome === "FAILED" ? {failedAt: nowServerTs()} : {}),
    }, {merge: true});

    tx.set(params.authorization.ref, {
      reversedAmountZar: admin.firestore.FieldValue.increment(
        params.outcome === "REVERSED" ? params.amountZar : 0
      ),
      pendingReversalAmountZar: admin.firestore.FieldValue.increment(
        params.outcome === "PENDING_PROVIDER" ? params.amountZar : 0
      ),
      lastReversalId: params.reversalId,
      lastReversalStatus: params.outcome,
      lastReversalAmountZar: params.amountZar,
      updatedAt: nowServerTs(),
    }, {merge: true});

    tx.set(params.sessionRef, {
      releasedAuthorizationAmountZar: admin.firestore.FieldValue.increment(
        params.outcome === "REVERSED" ? params.amountZar : 0
      ),
      pendingReleasedAuthorizationAmountZar: admin.firestore.FieldValue.increment(
        params.outcome === "PENDING_PROVIDER" ? params.amountZar : 0
      ),
      updatedAt: nowServerTs(),
    }, {merge: true});

    tx.set(params.bookingRef, {
      releasedAmountZar: admin.firestore.FieldValue.increment(
        params.outcome === "REVERSED" ? params.amountZar : 0
      ),
      pendingReleasedAmountZar: admin.firestore.FieldValue.increment(
        params.outcome === "PENDING_PROVIDER" ? params.amountZar : 0
      ),
      latestReversalId: params.reversalId,
      updatedAt: nowServerTs(),
    }, {merge: true});

    tx.set(params.paymentIntentRef, {
      releasedAmountZar: admin.firestore.FieldValue.increment(
        params.outcome === "REVERSED" ? params.amountZar : 0
      ),
      pendingReleasedAmountZar: admin.firestore.FieldValue.increment(
        params.outcome === "PENDING_PROVIDER" ? params.amountZar : 0
      ),
      latestReversalId: params.reversalId,
      updatedAt: nowServerTs(),
    }, {merge: true});

    return {
      reversalId: params.reversalId,
      status: params.outcome,
      accountedAmountZar,
    };
  });
}

async function reverseAuthorizationRemainder(params: {
  config: PaymentProviderContext;
  sessionRef: admin.firestore.DocumentReference;
  bookingRef: admin.firestore.DocumentReference;
  paymentIntentRef: admin.firestore.DocumentReference;
  authorization: AuthorizationState;
  amountZar: number;
}): Promise<ReversalExecutionResult> {
  const reversalId = buildEndReversalId({
    sessionId: params.sessionRef.id,
    authorizationId: params.authorization.id,
  });

  if (!params.authorization.providerPaymentId) {
    return recordReversalOutcome({
      sessionRef: params.sessionRef,
      bookingRef: params.bookingRef,
      paymentIntentRef: params.paymentIntentRef,
      authorization: params.authorization,
      reversalId,
      amountZar: params.amountZar,
      providerSnapshot: {
        resultCode: "missing_authorization_payment_id",
        resultDescription: "Authorization is missing a Peach payment identifier.",
      },
      outcome: "FAILED",
    });
  }

  try {
    const providerResponse = await createPeachReversal({
      config: params.config,
      authorizationPaymentId: params.authorization.providerPaymentId,
      amountZar: params.amountZar,
      merchantTransactionId: reversalId,
      bookingId: params.bookingRef.id,
      paymentIntentId: params.paymentIntentRef.id,
      sessionId: params.sessionRef.id,
    });
    const snapshot = buildProviderResponseSnapshot(providerResponse, reversalId);
    const outcome = classifyReversalResult(toTrimmedString(snapshot.resultCode));
    return recordReversalOutcome({
      sessionRef: params.sessionRef,
      bookingRef: params.bookingRef,
      paymentIntentRef: params.paymentIntentRef,
      authorization: params.authorization,
      reversalId,
      amountZar: params.amountZar,
      providerSnapshot: snapshot,
      outcome,
    });
  } catch (error) {
    const snapshot = buildProviderResponseSnapshot({}, reversalId);
    const outcome: ReversalOutcome = "FAILED";

    return recordReversalOutcome({
      sessionRef: params.sessionRef,
      bookingRef: params.bookingRef,
      paymentIntentRef: params.paymentIntentRef,
      authorization: params.authorization,
      reversalId,
      amountZar: params.amountZar,
      providerSnapshot: {
        ...snapshot,
        resultCode: toTrimmedString(snapshot.resultCode) || "provider_error",
        resultDescription: toTrimmedString(snapshot.resultDescription) ||
          (error instanceof Error ? error.message : "Authorization release failed."),
      },
      outcome,
    });
  }
}

export const startSession = onCall(
  {region: REGION},
  async (request): Promise<StartSessionResult> => {
    if (!request.auth) {
      throwStartSessionError(
        "unauthenticated",
        "User must be logged in.",
        "START_SESSION_UNAUTHENTICATED"
      );
    }

    const bookingId = toTrimmedString(request.data?.bookingId);
    if (!bookingId) {
      throwStartSessionError(
        "invalid-argument",
        "bookingId is required.",
        "START_SESSION_BOOKING_ID_REQUIRED"
      );
    }

    const callerUid = request.auth.uid;
    const bookingRef = db.collection("tutor_requests").doc(bookingId);
    const sessionRef = db.collection("tutoring_sessions").doc(bookingId);

    const sessionState = await db.runTransaction<StartSessionGrantResult>(async (tx) => {
      const bookingSnap = await tx.get(bookingRef);
      if (!bookingSnap.exists) {
        throwStartSessionError(
          "not-found",
          "Booking not found.",
          "START_SESSION_BOOKING_NOT_FOUND"
        );
      }

      const bookingData = bookingSnap.data() ?? {};
      const studentId = toTrimmedString(bookingData.studentId);
      const tutorId = toTrimmedString(bookingData.tutorId);
      if (!studentId || !tutorId) {
        throwStartSessionError(
          "failed-precondition",
          "Booking is missing participant references.",
          "START_SESSION_PARTICIPANTS_MISSING"
        );
      }
      if (callerUid !== studentId && callerUid !== tutorId) {
        throwStartSessionError(
          "permission-denied",
          "Only booking participants can start this tutoring session.",
          "START_SESSION_PARTICIPANT_MISMATCH"
        );
      }

      const participantRole: SessionRole = callerUid === tutorId ? "tutor" : "student";
      const guestTutoringMode = isGuestTutoringBooking(
        bookingData as Record<string, unknown>
      );
      const callerIsAnonymousGuest = isAnonymousTutoringGuest(request.auth);
      if (participantRole === "tutor" && callerIsAnonymousGuest) {
        throwStartSessionError(
          "permission-denied",
          "Tutors must be authenticated platform users.",
          "START_SESSION_TUTOR_AUTH_REQUIRED"
        );
      }
      if (participantRole === "student" && guestTutoringMode && !callerIsAnonymousGuest) {
        throwStartSessionError(
          "permission-denied",
          "Guest student join must use a guest tutoring identity.",
          "START_SESSION_GUEST_IDENTITY_REQUIRED"
        );
      }
      if (participantRole === "student" && !guestTutoringMode && callerIsAnonymousGuest) {
        throwStartSessionError(
          "permission-denied",
          "Authenticated student join is required for non-guest tutoring sessions.",
          "START_SESSION_STUDENT_AUTH_REQUIRED"
        );
      }

      // Validate session start conditions
      await validateSessionStartConditions({}, bookingData, callerUid);

      const paymentIntentId =
        toTrimmedString(bookingData.paymentIntentId) || bookingId;
      const paymentIntentRef = db
        .collection("session_payment_intents")
        .doc(paymentIntentId);

      const paymentIntentSnap = await tx.get(paymentIntentRef);
      if (!paymentIntentSnap.exists) {
        throwStartSessionError(
          "failed-precondition",
          "Booking payment intent is missing.",
          "START_SESSION_PAYMENT_SESSION_MISSING"
        );
      }
      const paymentIntentData = paymentIntentSnap.data() ?? {};
      const currentBookingState = deriveTutoringBookingState(
        bookingData as Record<string, unknown>
      );
      const existingSessionSnap = await tx.get(sessionRef);
      const existingSessionData = existingSessionSnap.data() ?? {};
      const currentSessionLifecycle = existingSessionSnap.exists ?
        deriveTutoringSessionState(existingSessionData as Record<string, unknown>) :
        null;
      const sessionAlreadyActive =
        normalizeUpper(existingSessionData.status) === SESSION_ACTIVE ||
        currentSessionLifecycle === TutoringSessionState.ACTIVE;

      if (
        !sessionAlreadyActive &&
        ![
          TutoringBookingState.PAYMENT_AUTHORIZED,
          TutoringBookingState.CONFIRMED,
        ].includes(currentBookingState)
      ) {
        throwStartSessionError(
          "failed-precondition",
          "Session can only start once the booking is payment-authorized or confirmed.",
          "START_SESSION_BOOKING_NOT_READY",
          {bookingState: currentBookingState}
        );
      }
      if (sessionAlreadyActive && !bookingAllowsSessionStart(bookingData, paymentIntentData)) {
        throwStartSessionError(
          "failed-precondition",
          "Session payment authorization is no longer valid.",
          "START_SESSION_AUTHORIZATION_INVALID"
        );
      }

      const authorizationId =
        toTrimmedString(bookingData.paymentAuthorizationId) ||
        toTrimmedString(paymentIntentData.paymentAuthorizationId) ||
        authorizationIdForBooking(bookingId);
      const authorizationRef = db
        .collection("payment_authorizations")
        .doc(authorizationId);
      const authorizationSnap = await tx.get(authorizationRef);
      if (!authorizationSnap.exists) {
        throwStartSessionError(
          "failed-precondition",
          "Session start is blocked because no valid payment authorization exists.",
          "START_SESSION_AUTHORIZATION_REQUIRED"
        );
      }
      const authorizationData = authorizationSnap.data() ?? {};
      if (!authorizationIsValid(authorizationData, bookingData, paymentIntentData)) {
        throwStartSessionError(
          "failed-precondition",
          "Session start is blocked because the payment authorization is not valid.",
          "START_SESSION_AUTHORIZATION_INVALID"
        );
      }
      const protectionState = deriveProtectedSessionState(
        existingSessionData as Record<string, unknown>,
        paymentIntentData as Record<string, unknown>
      );
      if (protectionState.protectedMinutesPurchased <= 0) {
        throwStartSessionError(
          "failed-precondition",
          "Protected tutoring time has not been initialized for this session.",
          "START_SESSION_PROTECTION_REQUIRED"
        );
      }
      if (protectionState.protectedMinutesRemaining <= 0) {
        throwStartSessionError(
          "failed-precondition",
          "Protected tutoring time has been exhausted for this session.",
          "START_SESSION_PROTECTION_EXHAUSTED"
        );
      }

      const roomName = roomNameForSession(bookingId);
      const studentParticipantRef = sessionRef.collection("participants").doc(studentId);
      const tutorParticipantRef = sessionRef.collection("participants").doc(tutorId);
      const callerParticipantRef = sessionRef.collection("participants").doc(callerUid);

      const [studentParticipantSnap, tutorParticipantSnap] = await Promise.all([
        tx.get(studentParticipantRef),
        tx.get(tutorParticipantRef),
      ]);
      const callerParticipantData = (
        participantRole === "student" ?
          studentParticipantSnap.data() :
          tutorParticipantSnap.data()
      ) ?? {};
      const tokenLockExpiresAt = timestampToDate(
        callerParticipantData.livekitJoinGrantLockExpiresAt
      );
      if (tokenLockExpiresAt && tokenLockExpiresAt.getTime() > Date.now()) {
        throwStartSessionError(
          "aborted",
          "A session join token is already being issued. Retry shortly.",
          "START_SESSION_JOIN_ISSUING"
        );
      }
      const replayWindowEndsAt = timestampToDate(
        callerParticipantData.livekitJoinReplayWindowEndsAt
      );
      if (
        toTrimmedString(callerParticipantData.livekitJoinGrantStatus) === "issued" &&
        replayWindowEndsAt &&
        replayWindowEndsAt.getTime() > Date.now()
      ) {
        throwStartSessionError(
          "aborted",
          "A recent session join token is still active. Retry after the replay window expires.",
          "START_SESSION_JOIN_REPLAY_BLOCKED",
          {
            retryAfterMs: replayWindowEndsAt.getTime() - Date.now(),
          }
        );
      }
      const joinGrantSequence =
        Number(callerParticipantData.livekitJoinGrantSequence ?? 0) + 1;
      const joinGrantId = buildSessionJoinGrantId({
        bookingId,
        userId: callerUid,
        role: participantRole,
        sequence: joinGrantSequence,
      });
      const joinGrantExpiresAt = new Date(Date.now() + SESSION_JOIN_GRANT_TTL_MS);
      const studentJoined = studentParticipantSnap.exists &&
        normalizeUpper(studentParticipantSnap.data()?.joinState) === "JOINED";
      const tutorJoined = tutorParticipantSnap.exists &&
        normalizeUpper(tutorParticipantSnap.data()?.joinState) === "JOINED";
      const nextStudentJoined = participantRole === "student" ? true : studentJoined;
      const nextTutorJoined = participantRole === "tutor" ? true : tutorJoined;
      const joinedParticipantCount =
        Number(nextStudentJoined) + Number(nextTutorJoined);
      const shouldActivate =
        joinedParticipantCount === 2 &&
        normalizeUpper(existingSessionData.status) !== SESSION_ACTIVE;
      const nextStatus = joinedParticipantCount === 2 ?
        SESSION_ACTIVE :
        SESSION_WAITING;
      const nextSessionLifecycleState = joinedParticipantCount === 2 ?
        TutoringSessionState.ACTIVE :
        TutoringSessionState.READY;
      assertSessionStateOrThrow({
        current: currentSessionLifecycle,
        next: nextSessionLifecycleState,
        actor: participantRole === "tutor" ?
          TutoringTransitionActor.TUTOR :
          TutoringTransitionActor.STUDENT,
        isGuestSession: guestTutoringMode,
        guestAccessValidated:
          !guestTutoringMode || participantRole !== "student" ? undefined : true,
      });
      if (joinedParticipantCount === 2) {
        assertBookingStateOrThrow({
          current: currentBookingState,
          next: TutoringBookingState.IN_PROGRESS,
          actor: participantRole === "tutor" ?
            TutoringTransitionActor.TUTOR :
            TutoringTransitionActor.STUDENT,
          isGuestSession: guestTutoringMode,
          guestAccessValidated:
            !guestTutoringMode || participantRole !== "student" ? undefined : true,
        });
      }
      const studentRatePerMinZar = Number(
        bookingData.totalRatePerMinute ??
        paymentIntentData.totalRatePerMinute ??
        0
      );
      const tutorRatePerMinZar = Number(
        bookingData.tutorRatePerMinute ??
        paymentIntentData.tutorRatePerMinute ??
        0
      );
      const platformFeePerMinZar = Number(
        bookingData.platformFeePerMinute ??
        paymentIntentData.platformFeePerMinute ??
        0
      );
      const pricingSnapshot = (
        bookingData.pricingSnapshot as Record<string, unknown> | undefined
      ) ?? (
        paymentIntentData.pricingSnapshot as Record<string, unknown> | undefined
      ) ?? {
        tutorBaseRateZar: tutorRatePerMinZar,
        platformFeeZar: platformFeePerMinZar,
        studentRateZar: studentRatePerMinZar,
      };
      const participantsSnapshot = {
        [studentId]: {
          role: "student" as const,
          joinState: nextStudentJoined ? "JOINED" : "PENDING",
          ...(studentParticipantSnap.data()?.joinedAt instanceof admin.firestore.Timestamp ? {
            joinedAt: studentParticipantSnap.data()?.joinedAt,
          } : {}),
        },
        [tutorId]: {
          role: "tutor" as const,
          joinState: nextTutorJoined ? "JOINED" : "PENDING",
          ...(tutorParticipantSnap.data()?.joinedAt instanceof admin.firestore.Timestamp ? {
            joinedAt: tutorParticipantSnap.data()?.joinedAt,
          } : {}),
        },
      };

      const sessionBase: Record<string, unknown> = {
        sessionId: sessionRef.id,
        bookingId,
        paymentIntentId,
        authorizationId,
        studentId,
        guestTutoringMode,
        tutorId,
        roomName,
        status: nextStatus,
        sessionLifecycleState: nextSessionLifecycleState,
        joinedParticipantCount,
        studentRatePerMinZar,
        tutorRatePerMinZar,
        platformFeePerMinZar,
        pricingSnapshot,
        participants: participantsSnapshot,
        protectedTutoringMinutesOnly: true,
        protectedMinutesPurchased: protectionState.protectedMinutesPurchased,
        protectedMinutesRemaining: protectionState.protectedMinutesRemaining,
        consumedMinutes: protectionState.consumedMinutes,
        refillAttemptCount: Number(
          existingSessionData.refillAttemptCount ??
            paymentIntentData.refillAttemptCount ??
            0
        ),
        lowFundsAt:
          existingSessionData.lowFundsAt ??
          paymentIntentData.lowFundsAt ??
          null,
        currency:
          toTrimmedString(bookingData.currency) ||
          toTrimmedString(paymentIntentData.currency) ||
          "ZAR",
        scheduledStartAt:
          bookingData.scheduledAt ??
          paymentIntentData.scheduledAt ??
          null,
        lastJoinAt: nowServerTs(),
        updatedAt: nowServerTs(),
      };
      const sessionSchemaPatch = buildSessionSchemaFields(
        sessionRef.id,
        sessionBase
      );

      if (!existingSessionSnap.exists) {
        tx.set(sessionRef, {
          ...sessionBase,
          ...sessionSchemaPatch,
          createdAt: nowServerTs(),
        }, {merge: true});
      } else {
        tx.set(sessionRef, {
          ...sessionBase,
          ...sessionSchemaPatch,
        }, {merge: true});
      }

      if (shouldActivate) {
        tx.set(sessionRef, {
          status: SESSION_ACTIVE,
          sessionLifecycleState: TutoringSessionState.ACTIVE,
          sessionStartAt: nowServerTs(),
          activatedAt: nowServerTs(),
        }, {merge: true});
      }

      if (!studentParticipantSnap.exists) {
        tx.set(studentParticipantRef, {
          userId: studentId,
          role: "student",
          joinState: nextStudentJoined ? "JOINED" : "PENDING",
          createdAt: nowServerTs(),
          updatedAt: nowServerTs(),
        }, {merge: true});
      }
      if (!tutorParticipantSnap.exists) {
        tx.set(tutorParticipantRef, {
          userId: tutorId,
          role: "tutor",
          joinState: nextTutorJoined ? "JOINED" : "PENDING",
          createdAt: nowServerTs(),
          updatedAt: nowServerTs(),
        }, {merge: true});
      }

      tx.set(callerParticipantRef, {
        userId: callerUid,
        role: participantRole,
        joinState: "JOINED",
        joinedAt: nowServerTs(),
        livekitJoinGrantId: joinGrantId,
        livekitJoinGrantSequence: joinGrantSequence,
        livekitJoinGrantStatus: "issuing",
        livekitJoinGrantIssuedForBookingId: bookingId,
        livekitJoinGrantIssuedForSessionId: sessionRef.id,
        livekitJoinGrantExpiresAt: admin.firestore.Timestamp.fromDate(
          joinGrantExpiresAt
        ),
        livekitJoinGrantLockExpiresAt: admin.firestore.Timestamp.fromDate(
          new Date(Date.now() + SESSION_JOIN_LOCK_MS)
        ),
        livekitJoinReplayWindowEndsAt: admin.firestore.Timestamp.fromDate(
          new Date(Date.now() + SESSION_JOIN_REPLAY_WINDOW_MS)
        ),
        updatedAt: nowServerTs(),
      }, {merge: true});

      tx.set(sessionRef, {
        participants: {
          ...participantsSnapshot,
          [callerUid]: {
            role: participantRole,
            joinState: "JOINED",
            joinedAt: nowServerTs(),
          },
        },
      }, {merge: true});

      tx.set(bookingRef, {
        tutorSessionId: sessionRef.id,
        ...(joinedParticipantCount === 2 ? {
          bookingState: TutoringBookingState.IN_PROGRESS,
        } : {}),
        sessionState: joinedParticipantCount === 2 ? "active" : "joining",
        sessionRoomName: roomName,
        sessionAuthorizationId: authorizationId,
        updatedAt: nowServerTs(),
      }, {merge: true});

      if (shouldActivate) {
        tx.set(bookingRef, {
          sessionStartAt: nowServerTs(),
        }, {merge: true});
      }

      tx.set(paymentIntentRef, {
        tutorSessionId: sessionRef.id,
        sessionRoomName: roomName,
        sessionStatus: nextStatus,
        updatedAt: nowServerTs(),
      }, {merge: true});

      if (shouldActivate) {
        tx.set(paymentIntentRef, {
          sessionStartAt: nowServerTs(),
        }, {merge: true});
      }

      return {
        bookingId,
        sessionId: sessionRef.id,
        room: roomName,
        participantRole,
        joinedParticipantCount,
        guestTutoringMode,
        joinGrantId,
        joinGrantExpiresAtIso: joinGrantExpiresAt.toISOString(),
      };
    });

    let tokenResult: Awaited<ReturnType<typeof buildTutorSessionToken>>;
    let guestSessionToken: {tokenId: string; expiresAtIso: string} | null = null;
    try {
      await ensureTutorRoom(sessionState.room);
      tokenResult = await buildTutorSessionToken(
        sessionState.room,
        callerUid,
        sessionState.participantRole,
        {
          bookingId,
          sessionId: sessionState.sessionId,
          joinGrantId: sessionState.joinGrantId,
          guestTutoringMode: sessionState.guestTutoringMode,
          participantRole: sessionState.participantRole,
        }
      );

      if (sessionState.guestTutoringMode && sessionState.participantRole === "student") {
        guestSessionToken = await recordGuestTutoringSessionToken({
          bookingId,
          sessionId: sessionState.sessionId,
          guestId: callerUid,
          participantRole: sessionState.participantRole,
          roomName: sessionState.room,
          livekitUrl: tokenResult.livekitUrl,
          token: tokenResult.token,
          joinGrantId: sessionState.joinGrantId,
          expiresAt: new Date(sessionState.joinGrantExpiresAtIso),
        });
      }
    } catch (error) {
      await sessionRef.collection("participants").doc(callerUid).set({
        livekitJoinGrantStatus: "failed",
        livekitJoinGrantFailedAt: nowServerTs(),
        livekitJoinGrantFailureReason:
          error instanceof Error ? error.message : "token_issue_failed",
        livekitJoinGrantLockExpiresAt: null,
        updatedAt: nowServerTs(),
      }, {merge: true});
      throwStartSessionError(
        "failed-precondition",
        "Session join token issuance failed.",
        "START_SESSION_TOKEN_ISSUE_FAILED"
      );
    }

    const tokenHash = createHash("sha256")
      .update(tokenResult.token)
      .digest("hex");
    await sessionRef.collection("participants").doc(callerUid).set({
      livekitJoinGrantStatus: "issued",
      livekitJoinGrantIssuedAt: nowServerTs(),
      livekitJoinGrantTokenHash: tokenHash,
      livekitJoinGrantLockExpiresAt: null,
      livekitJoinGrantLastIssuedAt: nowServerTs(),
      guestSessionTokenId: guestSessionToken?.tokenId ?? null,
      guestSessionTokenExpiresAt: guestSessionToken ?
        admin.firestore.Timestamp.fromDate(
          new Date(guestSessionToken.expiresAtIso)
        ) :
        null,
      updatedAt: nowServerTs(),
    }, {merge: true});
    await sessionRef.set({
      lastJoinGrantId: sessionState.joinGrantId,
      lastJoinGrantIssuedToUserId: callerUid,
      lastJoinGrantIssuedAt: nowServerTs(),
      updatedAt: nowServerTs(),
    }, {merge: true});

    const finalSessionSnap = await sessionRef.get();
    const finalSessionData = finalSessionSnap.data() ?? {};
    const sessionStartAt = finalSessionData.sessionStartAt instanceof admin.firestore.Timestamp ?
      finalSessionData.sessionStartAt.toDate().toISOString() :
      null;

    return {
      bookingId,
      sessionId: sessionState.sessionId,
      room: sessionState.room,
      status: toTrimmedString(finalSessionData.status) || SESSION_WAITING,
      participantRole: sessionState.participantRole,
      joinedParticipantCount:
        Number(finalSessionData.joinedParticipantCount ?? sessionState.joinedParticipantCount),
      sessionStartAt,
      livekitUrl: tokenResult.livekitUrl,
      token: tokenResult.token,
      joinGrantId: sessionState.joinGrantId,
      joinGrantExpiresAt: sessionState.joinGrantExpiresAtIso,
      guestSessionTokenId: guestSessionToken?.tokenId,
      guestSessionTokenExpiresAt: guestSessionToken?.expiresAtIso ?? null,
    };
  }
);

async function prepareSessionClose(params: {
  sessionId: string;
  callerUid: string;
  now: Date;
}): Promise<SessionClosePreparation | EndSessionResult> {
  const sessionRef = db.collection("tutoring_sessions").doc(params.sessionId);
  const settlementRef = db.collection("tutor_session_settlements").doc(params.sessionId);

  return db.runTransaction(async (tx) => {
    const [sessionSnap, settlementSnap] = await Promise.all([
      tx.get(sessionRef),
      tx.get(settlementRef),
    ]);

    if (settlementSnap.exists) {
      return buildEndSessionResult(
        settlementRef.id,
        settlementSnap.data() ?? {}
      );
    }
    if (!sessionSnap.exists) {
      throw new HttpsError("not-found", "Tutoring session not found.");
    }

    const sessionData = sessionSnap.data() ?? {};
    const bookingId = toTrimmedString(sessionData.bookingId) || params.sessionId;
    const paymentIntentId =
      toTrimmedString(sessionData.paymentIntentId) || bookingId;
    const bookingRef = db.collection("tutor_requests").doc(bookingId);
    const paymentIntentRef = db
      .collection("session_payment_intents")
      .doc(paymentIntentId);

    const [bookingSnap, paymentIntentSnap] = await Promise.all([
      tx.get(bookingRef),
      tx.get(paymentIntentRef),
    ]);

    if (!bookingSnap.exists || !paymentIntentSnap.exists) {
      throw new HttpsError(
        "failed-precondition",
        "Booking or payment intent is missing for this tutoring session."
      );
    }

    const bookingData = bookingSnap.data() ?? {};
    const paymentIntentData = paymentIntentSnap.data() ?? {};
    const guestTutoringMode = isGuestTutoringBooking({
      ...(bookingData as Record<string, unknown>),
      ...(paymentIntentData as Record<string, unknown>),
    });
    const studentId = toTrimmedString(bookingData.studentId || sessionData.studentId);
    const tutorId = toTrimmedString(bookingData.tutorId || sessionData.tutorId);
    if (!studentId || !tutorId) {
      throw new HttpsError(
        "failed-precondition",
        "Session is missing participant references."
      );
    }
    if (params.callerUid !== studentId && params.callerUid !== tutorId) {
      throw new HttpsError(
        "permission-denied",
        "Only session participants can end this tutoring session."
      );
    }

    const sessionStartAt = timestampToDate(
      sessionData.sessionStartAt ??
        bookingData.sessionStartAt ??
        paymentIntentData.sessionStartAt
    );
    if (!sessionStartAt) {
      throw new HttpsError(
        "failed-precondition",
        "Session cannot be ended before it has a server start time."
      );
    }

    const currentStatus = normalizeUpper(sessionData.status);
    if (
      currentStatus &&
      ![
        SESSION_ACTIVE,
        SESSION_LOW_FUNDS,
        SESSION_ENDING,
        SESSION_ENDED_INSUFFICIENT_FUNDS,
        SESSION_COMPLETED,
      ].includes(currentStatus)
    ) {
      throw new HttpsError(
        "failed-precondition",
        "Session is not in a state that can be ended."
      );
    }

    const storedBillableMinutes = Math.max(
      0,
      Math.round(Number(sessionData.closingBillableMinutes ?? 0))
    );
    const studentRatePerMinZar = asMoney(
      sessionData.studentRatePerMinZar,
      asMoney(
        bookingData.totalRatePerMinute,
        asMoney(paymentIntentData.totalRatePerMinute, 0)
      )
    );
    if (studentRatePerMinZar <= 0) {
      throw new HttpsError(
        "failed-precondition",
        "Session pricing is missing or invalid."
      );
    }

    const billableMinutes = storedBillableMinutes > 0 ?
      storedBillableMinutes :
      Math.max(
        1,
        Math.ceil(Math.max(0, params.now.getTime() - sessionStartAt.getTime()) / 60000)
      );
    const finalAmountDueZar = storedBillableMinutes > 0 &&
      asMoney(sessionData.closingAmountDueZar, 0) > 0 ?
      asMoney(sessionData.closingAmountDueZar, 0) :
      toMoney(billableMinutes * studentRatePerMinZar);
    const lockUntil = timestampToDate(sessionData.endOperationLockExpiresAt);
    const operationId =
      toTrimmedString(sessionData.endOperationId) || `end_${params.sessionId}`;

    if (
      currentStatus === SESSION_ENDING &&
      lockUntil &&
      lockUntil.getTime() > params.now.getTime()
    ) {
      // Reuse the existing closing snapshot so a retried callable continues the
      // same idempotent close operation instead of recomputing financials.
    } else {
      tx.set(sessionRef, {
        status: SESSION_ENDING,
        sessionLifecycleState: deriveTutoringSessionState(
          sessionData as Record<string, unknown>
        ),
        endOperationId: operationId,
        endOperationLockExpiresAt: admin.firestore.Timestamp.fromDate(
          new Date(params.now.getTime() + END_SESSION_LOCK_MS)
        ),
        closingBillableMinutes: billableMinutes,
        closingAmountDueZar: finalAmountDueZar,
        closeRequestedAt: nowServerTs(),
        closingRequestedBy: params.callerUid,
        updatedAt: nowServerTs(),
      }, {merge: true});

      tx.set(bookingRef, {
        sessionState: "ending",
        updatedAt: nowServerTs(),
      }, {merge: true});

      tx.set(paymentIntentRef, {
        sessionStatus: SESSION_ENDING,
        updatedAt: nowServerTs(),
      }, {merge: true});
    }

    return {
      sessionId: params.sessionId,
      bookingId,
      paymentIntentId,
      studentId,
      guestTutoringMode,
      tutorId,
      studentName: toTrimmedString(bookingData.studentName) || "Student",
      tutorName:
        toTrimmedString(bookingData.tutorName) ||
        toTrimmedString(paymentIntentData.tutorName) ||
        "Tutor",
      roomName:
        toTrimmedString(sessionData.roomName) ||
        toTrimmedString(bookingData.sessionRoomName),
      billableMinutes,
      finalAmountDueZar,
      studentRatePerMinZar,
      tutorRatePerMinZar: asMoney(
        sessionData.tutorRatePerMinZar,
        asMoney(
          bookingData.tutorRatePerMinute,
          asMoney(paymentIntentData.tutorRatePerMinute, 0)
        )
      ),
      currency:
        toTrimmedString(sessionData.currency) ||
        toTrimmedString(bookingData.currency) ||
        toTrimmedString(paymentIntentData.currency) ||
        CURRENCY,
      subject:
        toTrimmedString(bookingData.subject) ||
        toTrimmedString(paymentIntentData.subject) ||
        "Tutoring",
      topic:
        toTrimmedString(bookingData.topic) ||
        toTrimmedString(paymentIntentData.topic),
      organizationId:
        toTrimmedString(bookingData.organizationId) ||
        toTrimmedString(paymentIntentData.organizationId),
      organizationName:
        toTrimmedString(bookingData.organizationName) ||
        toTrimmedString(paymentIntentData.organizationName),
      organizationLogoUrl:
        toTrimmedString(bookingData.organizationLogoUrl) ||
        toTrimmedString(paymentIntentData.organizationLogoUrl),
      organizationMemberTitle:
        toTrimmedString(bookingData.organizationMemberTitle) ||
        toTrimmedString(paymentIntentData.organizationMemberTitle),
    };
  });
}

async function finalizeSessionClose(
  preparation: SessionClosePreparation
): Promise<EndSessionResult> {
  const sessionRef = db.collection("tutoring_sessions").doc(preparation.sessionId);
  const bookingRef = db.collection("tutor_requests").doc(preparation.bookingId);
  const paymentIntentRef = db
    .collection("session_payment_intents")
    .doc(preparation.paymentIntentId);
  const settlementRef = db
    .collection("tutor_session_settlements")
    .doc(preparation.sessionId);
  const outcomeRef = db
    .collection("tutor_session_outcomes")
    .doc(preparation.paymentIntentId);
  const studentRef = db.collection("users").doc(preparation.studentId);
  const guestCustomerDocRef = guestTutoringCustomerRef(preparation.studentId);
  const tutorRef = db.collection("users").doc(preparation.tutorId);
  const financeRef = db.collection("platform_finance").doc("overview");

  return db.runTransaction(async (tx) => {
    const [sessionSnap, bookingSnap, paymentIntentSnap, settlementSnap, tutorSnap] =
      await Promise.all([
        tx.get(sessionRef),
        tx.get(bookingRef),
        tx.get(paymentIntentRef),
        tx.get(settlementRef),
        tx.get(tutorRef),
      ]);

    if (settlementSnap.exists) {
      return buildEndSessionResult(
        settlementRef.id,
        settlementSnap.data() ?? {}
      );
    }
    if (!sessionSnap.exists || !bookingSnap.exists || !paymentIntentSnap.exists) {
      throw new HttpsError(
        "failed-precondition",
        "Session close references were not found."
      );
    }

    const sessionData = sessionSnap.data() ?? {};
    const bookingData = bookingSnap.data() ?? {};
    const paymentIntentData = paymentIntentSnap.data() ?? {};
    const tutorData = tutorSnap.data() ?? {};
    const tutorProfile =
      (tutorData.tutorProfile as Record<string, unknown> | undefined) ?? {};

    const billableMinutes = Math.max(
      1,
      Math.round(Number(sessionData.closingBillableMinutes ?? preparation.billableMinutes))
    );
    const finalAmountDueZar = asMoney(
      sessionData.closingAmountDueZar,
      preparation.finalAmountDueZar
    );
    const capturedTotalZar = asMoney(
      sessionData.capturedTotalZar,
      asMoney(paymentIntentData.capturedAmountZar, 0)
    );
    const pendingCaptureTotalZar = asMoney(
      sessionData.pendingCaptureTotalZar,
      asMoney(paymentIntentData.pendingCaptureTotalZar, 0)
    );
    const releasedAuthorizationAmountZar = asMoney(
      sessionData.releasedAuthorizationAmountZar,
      asMoney(paymentIntentData.releasedAmountZar, 0)
    );
    const pendingReleasedAuthorizationAmountZar = asMoney(
      sessionData.pendingReleasedAuthorizationAmountZar,
      asMoney(paymentIntentData.pendingReleasedAmountZar, 0)
    );
    const accountedTotalZar = toMoney(
      capturedTotalZar + pendingCaptureTotalZar
    );
    const insufficientFunds =
      normalizeUpper(sessionData.status) === SESSION_ENDED_INSUFFICIENT_FUNDS ||
      accountedTotalZar + 0.0001 < finalAmountDueZar;
    const currentSessionLifecycle = deriveTutoringSessionState(
      sessionData as Record<string, unknown>
    );
    const currentBookingState = deriveTutoringBookingState(
      bookingData as Record<string, unknown>
    );
    const guestTutoringMode = isGuestTutoringBooking({
      ...(sessionData as Record<string, unknown>),
      ...(bookingData as Record<string, unknown>),
      ...(paymentIntentData as Record<string, unknown>),
    });
    const terminalSessionState = insufficientFunds ?
      TutoringSessionState.ENDED_INSUFFICIENT_FUNDS :
      TutoringSessionState.ENDED_NORMAL;
    const finalBookingState = insufficientFunds ?
      TutoringBookingState.ENDED_INSUFFICIENT_FUNDS :
      TutoringBookingState.COMPLETED;
    assertSessionStateOrThrow({
      current: currentSessionLifecycle,
      next: terminalSessionState,
      actor: insufficientFunds ?
        TutoringTransitionActor.BILLING :
        TutoringTransitionActor.SYSTEM,
      isGuestSession: guestTutoringMode,
      reason: insufficientFunds ? "insufficient_funds" : "normal_end",
    });
    assertSessionStateOrThrow({
      current: terminalSessionState,
      next: TutoringSessionState.SETTLEMENT_PENDING,
      actor: TutoringTransitionActor.SYSTEM,
      isGuestSession: guestTutoringMode,
    });
    assertSessionStateOrThrow({
      current: TutoringSessionState.SETTLEMENT_PENDING,
      next: TutoringSessionState.SETTLED,
      actor: TutoringTransitionActor.BILLING,
      isGuestSession: guestTutoringMode,
    });
    assertBookingStateOrThrow({
      current: currentBookingState,
      next: finalBookingState,
      actor: insufficientFunds ?
        TutoringTransitionActor.BILLING :
        TutoringTransitionActor.SYSTEM,
      isGuestSession: guestTutoringMode,
      reason: insufficientFunds ? "insufficient_funds" : "normal_end",
    });
    const status = insufficientFunds ?
      "ended_due_to_insufficient_funds" :
      "completed";
    const settledAt = new Date();
    const settlementArtifacts = buildTutoringSettlementArtifacts({
      settlementId: settlementRef.id,
      sessionId: preparation.sessionId,
      bookingId: preparation.bookingId,
      paymentIntentId: preparation.paymentIntentId,
      studentId: preparation.studentId,
      tutorId: preparation.tutorId,
      status,
      billableMinutes,
      finalAmountDueZar,
      capturedAmountZar: capturedTotalZar,
      pendingCaptureAmountZar: pendingCaptureTotalZar,
      releasedAuthorizationAmountZar,
      pendingReleasedAuthorizationAmountZar,
      ratingRequired: true,
      currency: preparation.currency || CURRENCY,
      createdAt: settledAt,
      updatedAt: nowServerTs(),
      settledAt,
      payoutReservedAmountZar: 0,
      payoutPaidAmountZar: 0,
      disputeHeldAmountZar: 0,
      existingDisputeId: null,
    });
    const settlementStatus = String(settlementArtifacts.metrics.settlementStatus);
    const tutorEarningZar = settlementArtifacts.metrics.tutorEarningZar;
    const platformFeeZar = settlementArtifacts.metrics.platformFeeZar;
    const qualifiesForGoldTick =
      !insufficientFunds &&
      settlementArtifacts.metrics.settlementStatus === "completed" &&
      billableMinutes > 10;
    const organizationId =
      preparation.organizationId ||
      toTrimmedString(bookingData.organizationId) ||
      toTrimmedString(paymentIntentData.organizationId) ||
      toTrimmedString(tutorProfile.organizationId);
    const organizationName =
      preparation.organizationName ||
      toTrimmedString(bookingData.organizationName) ||
      toTrimmedString(paymentIntentData.organizationName) ||
      toTrimmedString(tutorProfile.organizationName);
    const organizationLogoUrl =
      preparation.organizationLogoUrl ||
      toTrimmedString(bookingData.organizationLogoUrl) ||
      toTrimmedString(paymentIntentData.organizationLogoUrl);
    const organizationMemberTitle =
      preparation.organizationMemberTitle ||
      toTrimmedString(bookingData.organizationMemberTitle) ||
      toTrimmedString(paymentIntentData.organizationMemberTitle) ||
      toTrimmedString(tutorProfile.organizationRole);

    const settlementBase = {
      ...settlementArtifacts.settlementBase,
      outstandingAmountZar: settlementArtifacts.metrics.uncapturedAmountZar,
    };
    const tutorPayableBase = {
      ...settlementArtifacts.tutorPayableBase,
      outstandingAmountZar: settlementArtifacts.metrics.uncapturedAmountZar,
    };

    tx.set(settlementRef, {
      ...settlementBase,
    }, {merge: true});

    tx.set(
      db.collection("tutor_payables").doc(settlementRef.id),
      tutorPayableBase,
      {merge: true}
    );

    tx.set(sessionRef, {
      status: insufficientFunds ?
        SESSION_ENDED_INSUFFICIENT_FUNDS :
        SESSION_COMPLETED,
      sessionLifecycleState: TutoringSessionState.SETTLED,
      sessionTerminalState: terminalSessionState,
      sessionEndAt: nowServerTs(),
      endedAt: nowServerTs(),
      endedReason: insufficientFunds ? "insufficient_funds" : "completed",
      billableMinutes,
      amountDueZar: finalAmountDueZar,
      outstandingDueZar: toMoney(Math.max(0, finalAmountDueZar - accountedTotalZar)),
      ratingRequired: true,
      settlementId: settlementRef.id,
      endOperationLockExpiresAt: admin.firestore.FieldValue.delete(),
      updatedAt: nowServerTs(),
    }, {merge: true});

    tx.set(bookingRef, {
      bookingState: finalBookingState,
      status,
      tutoringPaymentRail: "TUTORING",
      sessionState: insufficientFunds ? "ended_due_to_insufficient_funds" : "settled",
      paymentStatus: settlementStatus,
      settlementStatus,
      ratingRequired: true,
      reviewStatus: "pending",
      reviewEligible: true,
      goldTickQualifiedSession: qualifiesForGoldTick,
      billableMinutes,
      chargeAmountZar: finalAmountDueZar,
      capturedAmountZar: capturedTotalZar,
      pendingCaptureTotalZar,
      tutorPayoutZar: tutorEarningZar,
      platformRevenueZar: platformFeeZar,
      organizationId,
      organizationName,
      organizationLogoUrl,
      organizationMemberTitle,
      settledAt: nowServerTs(),
      updatedAt: nowServerTs(),
    }, {merge: true});

    tx.set(paymentIntentRef, {
      status: insufficientFunds ? "ended_due_to_insufficient_funds" : "settled",
      tutoringPaymentRail: "TUTORING",
      sessionStatus: insufficientFunds ?
        SESSION_ENDED_INSUFFICIENT_FUNDS :
        SESSION_COMPLETED,
      sessionLifecycleState: TutoringSessionState.SETTLED,
      sessionTerminalState: terminalSessionState,
      settlementStatus,
      ratingRequired: true,
      reviewStatus: "pending",
      reviewEligible: true,
      goldTickQualifiedSession: qualifiesForGoldTick,
      billableMinutes,
      chargeAmountZar: finalAmountDueZar,
      capturedAmountZar: capturedTotalZar,
      pendingCaptureTotalZar,
      holdRemainingZar: 0,
      holdStatus:
        releasedAuthorizationAmountZar > 0 ||
          pendingReleasedAuthorizationAmountZar > 0 ?
          "captured_and_released" :
          "captured",
      releasedAmountZar: releasedAuthorizationAmountZar,
      pendingReleasedAmountZar: pendingReleasedAuthorizationAmountZar,
      tutorPayoutZar: tutorEarningZar,
      platformRevenueZar: platformFeeZar,
      tutorName: preparation.tutorName,
      subject: preparation.subject,
      topic: preparation.topic,
      organizationId,
      organizationName,
      organizationLogoUrl,
      organizationMemberTitle,
      settledAt: nowServerTs(),
      updatedAt: nowServerTs(),
    }, {merge: true});

    tx.set(outcomeRef, {
      paymentIntentId: preparation.paymentIntentId,
      requestId: preparation.bookingId,
      tutoringPaymentRail: "TUTORING",
      studentId: preparation.studentId,
      tutorId: preparation.tutorId,
      tutorName: preparation.tutorName,
      subject: preparation.subject,
      topic: preparation.topic,
      organizationId,
      organizationName,
      organizationLogoUrl,
      organizationMemberTitle,
      billableMinutes,
      qualifiesForGoldTick,
      settlementStatus,
      paymentModel: "card_authorize_settlement",
      completedAt: nowServerTs(),
      createdAt: nowServerTs(),
      updatedAt: nowServerTs(),
    }, {merge: true});

    if (preparation.guestTutoringMode) {
      tx.set(guestCustomerDocRef, {
        guestId: preparation.studentId,
        guestTutoringCustomerId: preparation.studentId,
        studentId: preparation.studentId,
        isGuest: true,
        accountType: "instant_tutor",
        accessTier: "instant_tutor",
        accessMode: "instantTutor",
        instantTutorAccess: true,
        status: "active",
        lastBookingId: preparation.bookingId,
        lastSettlementId: settlementRef.id,
        lastTutorReviewIntentId: preparation.paymentIntentId,
        tutorReviewRequired: true,
        billingSpendTotalZar: admin.firestore.FieldValue.increment(capturedTotalZar),
        billingLastChargeAt: nowServerTs(),
        lastUsedAt: nowServerTs(),
        updatedAt: nowServerTs(),
      }, {merge: true});
    } else {
      tx.set(studentRef, {
        tutorReviewRequired: true,
        lastTutorReviewIntentId: preparation.paymentIntentId,
        lastTutorReviewRequiredAt: nowServerTs(),
        billingSpendTotalZar: admin.firestore.FieldValue.increment(capturedTotalZar),
        billingLastChargeAt: nowServerTs(),
        billingUpdatedAt: nowServerTs(),
      }, {merge: true});
    }

    tx.set(tutorRef, {
      "walletPayoutPendingZar": admin.firestore.FieldValue.increment(tutorEarningZar),
      "walletEarningsTotalZar": admin.firestore.FieldValue.increment(tutorEarningZar),
      "walletUpdatedAt": nowServerTs(),
      "tutorStats.totalEarnings": admin.firestore.FieldValue.increment(
        Math.round(tutorEarningZar)
      ),
      "tutorStats.sessionsCompleted": admin.firestore.FieldValue.increment(1),
      "tutorStats.minutesTutored": admin.firestore.FieldValue.increment(
        billableMinutes
      ),
    }, {merge: true});

    tx.set(financeRef, {
      grossVolumeZar: admin.firestore.FieldValue.increment(capturedTotalZar),
      platformRevenueZar: admin.firestore.FieldValue.increment(platformFeeZar),
      tutorPayoutPendingZar: admin.firestore.FieldValue.increment(tutorEarningZar),
      settledSessions: admin.firestore.FieldValue.increment(1),
      updatedAt: nowServerTs(),
    }, {merge: true});

    if (organizationId) {
      const organizationRef = db.collection("tutor_organizations").doc(organizationId);
      const organizationMemberRef = organizationRef.collection("members").doc(preparation.tutorId);
      tx.set(organizationRef, {
        organizationId,
        name: organizationName,
        logoUrl: organizationLogoUrl,
        subjects: admin.firestore.FieldValue.arrayUnion(preparation.subject),
        totalSessionsCompleted: admin.firestore.FieldValue.increment(1),
        totalMinutesTutored: admin.firestore.FieldValue.increment(billableMinutes),
        updatedAt: nowServerTs(),
      }, {merge: true});
      tx.set(organizationMemberRef, {
        organizationId,
        organizationName,
        organizationLogoUrl,
        tutorId: preparation.tutorId,
        name: preparation.tutorName,
        memberTitle: organizationMemberTitle,
        sessionsCompleted: admin.firestore.FieldValue.increment(1),
        qualifyingSessionCount: admin.firestore.FieldValue.increment(
          qualifiesForGoldTick ? 1 : 0
        ),
        minutesTutored: admin.firestore.FieldValue.increment(billableMinutes),
        updatedAt: nowServerTs(),
      }, {merge: true});
    }

    if (!preparation.guestTutoringMode) {
      tx.set(
        studentRef.collection("payment_transactions").doc(preparation.paymentIntentId),
        {
          type: "session_capture",
          tutoringPaymentRail: "TUTORING",
          direction: "debit",
          status: settlementStatus,
          paymentIntentId: preparation.paymentIntentId,
          requestId: preparation.bookingId,
          billableMinutes,
          grossChargeZar: finalAmountDueZar,
          capturedAmountZar: capturedTotalZar,
          paymentModel: "card_authorize_settlement",
          createdAt: nowServerTs(),
          updatedAt: nowServerTs(),
        },
        {merge: true}
      );
    }

    tx.set(
      tutorRef.collection("wallet_transactions").doc(preparation.paymentIntentId),
      {
        type: "session_payout_pending",
        tutoringPaymentRail: "TUTORING",
        direction: "credit",
        status: settlementStatus,
        paymentIntentId: preparation.paymentIntentId,
        requestId: preparation.bookingId,
        billableMinutes,
        payoutAmountZar: tutorEarningZar,
        createdAt: nowServerTs(),
        updatedAt: nowServerTs(),
      },
      {merge: true}
    );

    return {
      sessionId: preparation.sessionId,
      bookingId: preparation.bookingId,
      paymentIntentId: preparation.paymentIntentId,
      settlementId: settlementRef.id,
      status,
      settlementStatus,
      billableMinutes,
      finalAmountDueZar,
      capturedTotalZar,
      pendingCaptureTotalZar,
      tutorEarningZar,
      platformFeeZar,
      releasedAuthorizationAmountZar,
      pendingReleasedAuthorizationAmountZar,
      ratingRequired: true,
    };
  });
}

export const endSession = onCall(
  {region: REGION},
  async (request): Promise<EndSessionResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }

    const sessionId = toTrimmedString(request.data?.sessionId);
    if (!sessionId) {
      throw new HttpsError("invalid-argument", "sessionId is required.");
    }

    const prepared = await prepareSessionClose({
      sessionId,
      callerUid: request.auth.uid,
      now: new Date(),
    });
    if ("settlementId" in prepared) {
      return prepared;
    }

    // Validate billing conditions before processing payment
    await validateSessionBillingConditions(prepared);

    const sessionRef = db.collection("tutoring_sessions").doc(prepared.sessionId);
    const bookingRef = db.collection("tutor_requests").doc(prepared.bookingId);
    const paymentIntentRef = db
      .collection("session_payment_intents")
      .doc(prepared.paymentIntentId);
    const config = getPaymentProviderContext();

    let sessionSnap = await sessionRef.get();
    let sessionData = sessionSnap.data() ?? {};
    let capturedTotalZar = asMoney(sessionData.capturedTotalZar, 0);
    let pendingCaptureTotalZar = asMoney(sessionData.pendingCaptureTotalZar, 0);
    let deltaZar = toMoney(
      Math.max(
        0,
        prepared.finalAmountDueZar - capturedTotalZar - pendingCaptureTotalZar
      )
    );

    let authorizations = await loadAuthorizations(prepared.bookingId);
    let captureIndex = 0;
    for (const authorization of authorizations) {
      if (deltaZar <= 0) break;
      if (
        normalizeUpper(authorization.status) !== AUTH_STATUS_AUTHORIZED ||
        authorization.remainingAuthorizedZar <= 0
      ) {
        continue;
      }

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
        billableMinutes: prepared.billableMinutes,
        captureIndex,
        amountZar: captureAmountZar,
      });
      captureIndex += 1;
      if (captureResult.accountedAmountZar > 0) {
        deltaZar = toMoney(Math.max(0, deltaZar - captureResult.accountedAmountZar));
      }
    }

    authorizations = await loadAuthorizations(prepared.bookingId);
    for (const authorization of authorizations) {
      if (
        normalizeUpper(authorization.status) !== AUTH_STATUS_AUTHORIZED ||
        authorization.remainingAuthorizedZar <= 0
      ) {
        continue;
      }
      await reverseAuthorizationRemainder({
        config,
        sessionRef,
        bookingRef,
        paymentIntentRef,
        authorization,
        amountZar: authorization.remainingAuthorizedZar,
      });
    }

    await forceEndRoom(prepared.sessionId);

    sessionSnap = await sessionRef.get();
    sessionData = sessionSnap.data() ?? {};
    capturedTotalZar = asMoney(sessionData.capturedTotalZar, 0);
    pendingCaptureTotalZar = asMoney(sessionData.pendingCaptureTotalZar, 0);

    if (
      capturedTotalZar + pendingCaptureTotalZar + 0.0001 <
      prepared.finalAmountDueZar
    ) {
      assertSessionStateOrThrow({
        current: deriveTutoringSessionState(sessionData as Record<string, unknown>),
        next: TutoringSessionState.ENDED_INSUFFICIENT_FUNDS,
        actor: TutoringTransitionActor.BILLING,
        isGuestSession: prepared.guestTutoringMode,
        reason: "insufficient_funds",
      });
      await sessionRef.set({
        status: SESSION_ENDED_INSUFFICIENT_FUNDS,
        sessionLifecycleState: TutoringSessionState.ENDED_INSUFFICIENT_FUNDS,
        sessionTerminalState: TutoringSessionState.ENDED_INSUFFICIENT_FUNDS,
        lowFundsAt: sessionData.lowFundsAt ?? nowServerTs(),
        updatedAt: nowServerTs(),
      }, {merge: true});
    }

    return finalizeSessionClose(prepared);
  }
);

export { prepareSessionRuntime, attemptAutoStart };
