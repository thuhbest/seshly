import {
  deriveTutoringBookingState,
  deriveTutoringSessionState,
  TutoringBookingState,
  TutoringSessionState,
} from "./tutoringStateMachine";

const PAYMENT_AUTHORIZED = "PAYMENT_AUTHORIZED";
const AUTH_STATUS_AUTHORIZED = "AUTHORIZED";
const SESSION_ACTIVE = "ACTIVE";

function toTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function normalizeUpper(value: unknown): string {
  return toTrimmedString(value).toUpperCase();
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
