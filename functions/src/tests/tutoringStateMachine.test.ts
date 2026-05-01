import test from "node:test";
import assert from "node:assert/strict";
import {
  assertBookingTransition,
  assertSessionTransition,
  resolveCancellationState,
  resolveNoShowStateChange,
  TutoringBookingState,
  TutoringSessionState,
  TutoringStateTransitionError,
  TutoringTransitionActor,
} from "../tutoringStateMachine.js";

test("booking transitions reject skipping payment authorization", () => {
  assert.throws(
    () => assertBookingTransition(
      TutoringBookingState.CREATED,
      TutoringBookingState.CONFIRMED,
      {actor: TutoringTransitionActor.TUTOR},
    ),
    (error: unknown) =>
      error instanceof TutoringStateTransitionError &&
      error.code === "invalid-transition" &&
      error.message.includes("Illegal tutoring booking transition"),
  );
});

test("booking payment authorization is server-side only", () => {
  assert.throws(
    () => assertBookingTransition(
      TutoringBookingState.AWAITING_PAYMENT_AUTHORIZATION,
      TutoringBookingState.PAYMENT_AUTHORIZED,
      {actor: TutoringTransitionActor.STUDENT},
    ),
    (error: unknown) =>
      error instanceof TutoringStateTransitionError &&
      error.code === "permission-denied" &&
      error.message.includes("cannot transition tutoring state"),
  );
});

test("guest sessions cannot activate without validated guest access", () => {
  assert.throws(
    () => assertSessionTransition(
      TutoringSessionState.READY,
      TutoringSessionState.ACTIVE,
      {
        actor: TutoringTransitionActor.STUDENT,
        isGuestSession: true,
        guestAccessValidated: false,
      },
    ),
    (error: unknown) =>
      error instanceof TutoringStateTransitionError &&
      error.code === "failed-precondition" &&
      error.message.includes("validated guest access"),
  );
});

test("no-show resolution is restricted to server-side actors", () => {
  assert.throws(
    () => resolveNoShowStateChange({
      actor: TutoringTransitionActor.STUDENT,
      reason: "no_show",
    }),
    (error: unknown) =>
      error instanceof TutoringStateTransitionError &&
      error.code === "permission-denied",
  );
});

test("session transitions reject direct settlement from ready", () => {
  assert.throws(
    () => assertSessionTransition(
      TutoringSessionState.READY,
      TutoringSessionState.SETTLED,
      {actor: TutoringTransitionActor.SYSTEM},
    ),
    (error: unknown) =>
      error instanceof TutoringStateTransitionError &&
      error.code === "invalid-transition",
  );
});

test("no-show and cancellation helpers return canonical terminal states", () => {
  assert.deepEqual(
    resolveNoShowStateChange({
      actor: TutoringTransitionActor.SCHEDULER,
      reason: "no_show",
    }),
    {
      bookingState: TutoringBookingState.EXPIRED,
      sessionState: TutoringSessionState.ENDED_CANCELLED,
    },
  );
  assert.equal(
    resolveCancellationState({
      actor: TutoringTransitionActor.TUTOR,
      reason: "cancel",
    }),
    TutoringBookingState.CANCELLED,
  );
});
