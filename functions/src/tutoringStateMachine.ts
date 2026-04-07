export enum TutoringBookingState {
  CREATED = "created",
  AWAITING_PAYMENT_AUTHORIZATION = "awaiting_payment_authorization",
  PAYMENT_AUTHORIZED = "payment_authorized",
  CONFIRMED = "confirmed",
  IN_PROGRESS = "in_progress",
  COMPLETED = "completed",
  ENDED_INSUFFICIENT_FUNDS = "ended_insufficient_funds",
  CANCELLED = "cancelled",
  EXPIRED = "expired",
}

export enum TutoringSessionState {
  READY = "ready",
  ACTIVE = "active",
  LOW_FUNDS = "low_funds",
  ENDED_NORMAL = "ended_normal",
  ENDED_INSUFFICIENT_FUNDS = "ended_insufficient_funds",
  ENDED_CANCELLED = "ended_cancelled",
  SETTLEMENT_PENDING = "settlement_pending",
  SETTLED = "settled",
}

export enum TutoringTransitionActor {
  STUDENT = "student",
  TUTOR = "tutor",
  PAYMENT = "payment",
  SYSTEM = "system",
  BILLING = "billing",
  SCHEDULER = "scheduler",
  ADMIN = "admin",
}

export interface TutoringTransitionContext {
  actor: TutoringTransitionActor;
  isGuestSession?: boolean;
  guestAccessValidated?: boolean;
  reason?: "cancel" | "no_show" | "normal_end" | "insufficient_funds";
}

export class TutoringStateTransitionError extends Error {
  constructor(
    readonly code: "invalid-transition" | "permission-denied" | "failed-precondition",
    message: string
  ) {
    super(message);
    this.name = "TutoringStateTransitionError";
  }
}

function toTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function normalizeLower(value: unknown): string {
  return toTrimmedString(value).toLowerCase();
}

function normalizeUpper(value: unknown): string {
  return toTrimmedString(value).toUpperCase();
}

const BOOKING_STATE_SET = new Set<string>(Object.values(TutoringBookingState));
const SESSION_STATE_SET = new Set<string>(Object.values(TutoringSessionState));

const BOOKING_TRANSITIONS: Record<
  TutoringBookingState,
  readonly TutoringBookingState[]
> = {
  [TutoringBookingState.CREATED]: [
    TutoringBookingState.AWAITING_PAYMENT_AUTHORIZATION,
    TutoringBookingState.CANCELLED,
    TutoringBookingState.EXPIRED,
  ],
  [TutoringBookingState.AWAITING_PAYMENT_AUTHORIZATION]: [
    TutoringBookingState.PAYMENT_AUTHORIZED,
    TutoringBookingState.CANCELLED,
    TutoringBookingState.EXPIRED,
  ],
  [TutoringBookingState.PAYMENT_AUTHORIZED]: [
    TutoringBookingState.CONFIRMED,
    TutoringBookingState.CANCELLED,
    TutoringBookingState.EXPIRED,
  ],
  [TutoringBookingState.CONFIRMED]: [
    TutoringBookingState.IN_PROGRESS,
    TutoringBookingState.CANCELLED,
    TutoringBookingState.EXPIRED,
  ],
  [TutoringBookingState.IN_PROGRESS]: [
    TutoringBookingState.COMPLETED,
    TutoringBookingState.ENDED_INSUFFICIENT_FUNDS,
    TutoringBookingState.CANCELLED,
  ],
  [TutoringBookingState.COMPLETED]: [],
  [TutoringBookingState.ENDED_INSUFFICIENT_FUNDS]: [],
  [TutoringBookingState.CANCELLED]: [],
  [TutoringBookingState.EXPIRED]: [],
};

const SESSION_TRANSITIONS: Record<
  TutoringSessionState,
  readonly TutoringSessionState[]
> = {
  [TutoringSessionState.READY]: [
    TutoringSessionState.ACTIVE,
    TutoringSessionState.ENDED_CANCELLED,
  ],
  [TutoringSessionState.ACTIVE]: [
    TutoringSessionState.LOW_FUNDS,
    TutoringSessionState.ENDED_NORMAL,
    TutoringSessionState.ENDED_CANCELLED,
    TutoringSessionState.ENDED_INSUFFICIENT_FUNDS,
  ],
  [TutoringSessionState.LOW_FUNDS]: [
    TutoringSessionState.ACTIVE,
    TutoringSessionState.ENDED_CANCELLED,
    TutoringSessionState.ENDED_INSUFFICIENT_FUNDS,
  ],
  [TutoringSessionState.ENDED_NORMAL]: [
    TutoringSessionState.SETTLEMENT_PENDING,
  ],
  [TutoringSessionState.ENDED_INSUFFICIENT_FUNDS]: [
    TutoringSessionState.SETTLEMENT_PENDING,
  ],
  [TutoringSessionState.ENDED_CANCELLED]: [
    TutoringSessionState.SETTLEMENT_PENDING,
  ],
  [TutoringSessionState.SETTLEMENT_PENDING]: [
    TutoringSessionState.SETTLED,
  ],
  [TutoringSessionState.SETTLED]: [],
};

const BOOKING_TARGET_ACTORS: Record<
  TutoringBookingState,
  readonly TutoringTransitionActor[]
> = {
  [TutoringBookingState.CREATED]: [
    TutoringTransitionActor.STUDENT,
    TutoringTransitionActor.SYSTEM,
  ],
  [TutoringBookingState.AWAITING_PAYMENT_AUTHORIZATION]: [
    TutoringTransitionActor.STUDENT,
    TutoringTransitionActor.PAYMENT,
    TutoringTransitionActor.SYSTEM,
  ],
  [TutoringBookingState.PAYMENT_AUTHORIZED]: [
    TutoringTransitionActor.PAYMENT,
    TutoringTransitionActor.SYSTEM,
  ],
  [TutoringBookingState.CONFIRMED]: [
    TutoringTransitionActor.TUTOR,
    TutoringTransitionActor.SYSTEM,
    TutoringTransitionActor.ADMIN,
  ],
  [TutoringBookingState.IN_PROGRESS]: [
    TutoringTransitionActor.STUDENT,
    TutoringTransitionActor.TUTOR,
    TutoringTransitionActor.SYSTEM,
  ],
  [TutoringBookingState.COMPLETED]: [
    TutoringTransitionActor.SYSTEM,
    TutoringTransitionActor.BILLING,
  ],
  [TutoringBookingState.ENDED_INSUFFICIENT_FUNDS]: [
    TutoringTransitionActor.SYSTEM,
    TutoringTransitionActor.BILLING,
  ],
  [TutoringBookingState.CANCELLED]: [
    TutoringTransitionActor.STUDENT,
    TutoringTransitionActor.TUTOR,
    TutoringTransitionActor.SYSTEM,
    TutoringTransitionActor.ADMIN,
  ],
  [TutoringBookingState.EXPIRED]: [
    TutoringTransitionActor.SYSTEM,
    TutoringTransitionActor.SCHEDULER,
    TutoringTransitionActor.ADMIN,
  ],
};

const SESSION_TARGET_ACTORS: Record<
  TutoringSessionState,
  readonly TutoringTransitionActor[]
> = {
  [TutoringSessionState.READY]: [
    TutoringTransitionActor.STUDENT,
    TutoringTransitionActor.TUTOR,
    TutoringTransitionActor.SYSTEM,
  ],
  [TutoringSessionState.ACTIVE]: [
    TutoringTransitionActor.STUDENT,
    TutoringTransitionActor.TUTOR,
    TutoringTransitionActor.SYSTEM,
  ],
  [TutoringSessionState.LOW_FUNDS]: [
    TutoringTransitionActor.BILLING,
    TutoringTransitionActor.SYSTEM,
  ],
  [TutoringSessionState.ENDED_NORMAL]: [
    TutoringTransitionActor.STUDENT,
    TutoringTransitionActor.TUTOR,
    TutoringTransitionActor.SYSTEM,
    TutoringTransitionActor.ADMIN,
  ],
  [TutoringSessionState.ENDED_INSUFFICIENT_FUNDS]: [
    TutoringTransitionActor.BILLING,
    TutoringTransitionActor.SYSTEM,
  ],
  [TutoringSessionState.ENDED_CANCELLED]: [
    TutoringTransitionActor.STUDENT,
    TutoringTransitionActor.TUTOR,
    TutoringTransitionActor.SYSTEM,
    TutoringTransitionActor.SCHEDULER,
    TutoringTransitionActor.ADMIN,
  ],
  [TutoringSessionState.SETTLEMENT_PENDING]: [
    TutoringTransitionActor.SYSTEM,
    TutoringTransitionActor.BILLING,
  ],
  [TutoringSessionState.SETTLED]: [
    TutoringTransitionActor.SYSTEM,
    TutoringTransitionActor.BILLING,
  ],
};

function assertActorAllowed(
  nextState: TutoringBookingState | TutoringSessionState,
  allowedActors: readonly TutoringTransitionActor[],
  context: TutoringTransitionContext
): void {
  if (allowedActors.includes(context.actor)) {
    return;
  }
  throw new TutoringStateTransitionError(
    "permission-denied",
    `Actor ${context.actor} cannot transition tutoring state to ${nextState}.`
  );
}

function assertGuestGuard(
  nextState: TutoringBookingState | TutoringSessionState,
  context: TutoringTransitionContext
): void {
  const requiresValidatedGuest =
    nextState === TutoringBookingState.IN_PROGRESS ||
    nextState === TutoringSessionState.ACTIVE;
  if (
    context.isGuestSession &&
    context.actor === TutoringTransitionActor.STUDENT &&
    requiresValidatedGuest &&
    context.guestAccessValidated !== true
  ) {
    throw new TutoringStateTransitionError(
      "failed-precondition",
      "Guest tutoring transitions into an active session require validated guest access."
    );
  }
}

function assertReasonGuard(
  nextState: TutoringBookingState | TutoringSessionState,
  context: TutoringTransitionContext
): void {
  if (
    nextState === TutoringBookingState.EXPIRED &&
    context.reason !== "no_show"
  ) {
    throw new TutoringStateTransitionError(
      "failed-precondition",
      "Booking expiry is reserved for no-show handling."
    );
  }
  if (
    nextState === TutoringSessionState.ENDED_CANCELLED &&
    context.reason === "insufficient_funds"
  ) {
    throw new TutoringStateTransitionError(
      "failed-precondition",
      "Insufficient funds must end the session with ended_insufficient_funds."
    );
  }
}

export function isTutoringBookingState(value: unknown): value is TutoringBookingState {
  return BOOKING_STATE_SET.has(normalizeLower(value));
}

export function isTutoringSessionState(value: unknown): value is TutoringSessionState {
  return SESSION_STATE_SET.has(normalizeLower(value));
}

export function deriveTutoringBookingState(
  data: Record<string, unknown>
): TutoringBookingState {
  const explicit = normalizeLower(data.bookingState);
  if (isTutoringBookingState(explicit)) {
    return explicit;
  }

  const status = normalizeLower(data.status);
  const paymentStatus = normalizeLower(data.paymentStatus);
  const authorizationStatus = normalizeLower(data.authorizationStatus);
  const sessionState = normalizeLower(data.sessionState);

  if (
    status === "ended_due_to_insufficient_funds" ||
    sessionState === "ended_due_to_insufficient_funds"
  ) {
    return TutoringBookingState.ENDED_INSUFFICIENT_FUNDS;
  }
  if (
    status === "completed" ||
    sessionState === "settled"
  ) {
    return TutoringBookingState.COMPLETED;
  }
  if (
    status === "declined" ||
    status === "cancelled" ||
    sessionState === "declined"
  ) {
    return TutoringBookingState.CANCELLED;
  }
  if (
    sessionState === "active" ||
    status === "in_progress"
  ) {
    return TutoringBookingState.IN_PROGRESS;
  }
  if (
    status === "accepted" ||
    sessionState === "approved"
  ) {
    return TutoringBookingState.CONFIRMED;
  }
  if (
    paymentStatus === "payment_authorized" ||
    authorizationStatus === "payment_authorized"
  ) {
    return TutoringBookingState.PAYMENT_AUTHORIZED;
  }
  if (
    paymentStatus === "authorization_pending" ||
    paymentStatus === "payment_authorization_pending" ||
    authorizationStatus === "authorization_pending" ||
    authorizationStatus === "payment_authorization_pending"
  ) {
    return TutoringBookingState.AWAITING_PAYMENT_AUTHORIZATION;
  }
  return TutoringBookingState.CREATED;
}

export function deriveTutoringSessionState(
  data: Record<string, unknown>
): TutoringSessionState {
  const explicit = normalizeLower(data.sessionLifecycleState);
  if (isTutoringSessionState(explicit)) {
    return explicit;
  }

  const terminalState = normalizeLower(data.sessionTerminalState);
  if (isTutoringSessionState(terminalState)) {
    return terminalState;
  }

  const runtimeStatus = normalizeUpper(data.status || data.sessionStatus);
  const settlementStatus = normalizeLower(data.settlementStatus);
  const settledAt = data.settledAt != null;

  if (runtimeStatus === "LOW_FUNDS") {
    return TutoringSessionState.LOW_FUNDS;
  }
  if (runtimeStatus === "ACTIVE") {
    return TutoringSessionState.ACTIVE;
  }
  if (
    runtimeStatus === "ENDED_INSUFFICIENT_FUNDS"
  ) {
    return settledAt || settlementStatus ? 
      TutoringSessionState.SETTLED :
      TutoringSessionState.ENDED_INSUFFICIENT_FUNDS;
  }
  if (
    runtimeStatus === "CANCELLED" ||
    runtimeStatus === "MISSED" ||
    runtimeStatus === "NO_SHOW"
  ) {
    return settledAt || settlementStatus ?
      TutoringSessionState.SETTLED :
      TutoringSessionState.ENDED_CANCELLED;
  }
  if (runtimeStatus === "COMPLETED") {
    return settledAt || settlementStatus ?
      TutoringSessionState.SETTLED :
      TutoringSessionState.ENDED_NORMAL;
  }
  if (
    runtimeStatus === "ENDING" ||
    settlementStatus === "pending"
  ) {
    return TutoringSessionState.SETTLEMENT_PENDING;
  }
  return TutoringSessionState.READY;
}

export function assertBookingTransition(
  current: TutoringBookingState | null | undefined,
  next: TutoringBookingState,
  context: TutoringTransitionContext
): void {
  assertActorAllowed(next, BOOKING_TARGET_ACTORS[next], context);
  assertGuestGuard(next, context);
  assertReasonGuard(next, context);

  if (current == null) {
    if (next !== TutoringBookingState.CREATED) {
      throw new TutoringStateTransitionError(
        "invalid-transition",
        `Tutoring booking state must start at ${TutoringBookingState.CREATED}.`
      );
    }
    return;
  }

  if (current === next) {
    return;
  }

  if (!BOOKING_TRANSITIONS[current].includes(next)) {
    throw new TutoringStateTransitionError(
      "invalid-transition",
      `Illegal tutoring booking transition from ${current} to ${next}.`
    );
  }
}

export function assertSessionTransition(
  current: TutoringSessionState | null | undefined,
  next: TutoringSessionState,
  context: TutoringTransitionContext
): void {
  assertActorAllowed(next, SESSION_TARGET_ACTORS[next], context);
  assertGuestGuard(next, context);
  assertReasonGuard(next, context);

  if (current == null) {
    if (next !== TutoringSessionState.READY) {
      throw new TutoringStateTransitionError(
        "invalid-transition",
        `Tutoring session state must start at ${TutoringSessionState.READY}.`
      );
    }
    return;
  }

  if (current === next) {
    return;
  }

  if (!SESSION_TRANSITIONS[current].includes(next)) {
    throw new TutoringStateTransitionError(
      "invalid-transition",
      `Illegal tutoring session transition from ${current} to ${next}.`
    );
  }
}

export function resolveNoShowStateChange(
  context: TutoringTransitionContext
): {
  bookingState: TutoringBookingState;
  sessionState: TutoringSessionState;
} {
  if (
    context.actor !== TutoringTransitionActor.SYSTEM &&
    context.actor !== TutoringTransitionActor.SCHEDULER &&
    context.actor !== TutoringTransitionActor.ADMIN
  ) {
    throw new TutoringStateTransitionError(
      "permission-denied",
      "No-show resolution is reserved for server-side actors."
    );
  }

  return {
    bookingState: TutoringBookingState.EXPIRED,
    sessionState: TutoringSessionState.ENDED_CANCELLED,
  };
}

export function resolveCancellationState(
  context: TutoringTransitionContext
): TutoringBookingState {
  if (
    context.actor !== TutoringTransitionActor.STUDENT &&
    context.actor !== TutoringTransitionActor.TUTOR &&
    context.actor !== TutoringTransitionActor.SYSTEM &&
    context.actor !== TutoringTransitionActor.ADMIN
  ) {
    throw new TutoringStateTransitionError(
      "permission-denied",
      "Booking cancellation is not allowed for this actor."
    );
  }
  return TutoringBookingState.CANCELLED;
}

export function toTutoringHttpsErrorCode(
  error: TutoringStateTransitionError
): "permission-denied" | "failed-precondition" {
  return error.code === "permission-denied" ?
    "permission-denied" :
    "failed-precondition";
}
