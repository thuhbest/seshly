import test from "node:test";
import assert from "node:assert/strict";
import {HttpsError} from "firebase-functions/v2/https";
import {
  canSubmitTutoringRatingForEndedSession,
  resolveTutoringRatingSubmission,
} from "../tutorRatings.js";

test("completed tutoring bookings are eligible for rating submission", () => {
  assert.equal(
    canSubmitTutoringRatingForEndedSession(
      {
        bookingState: "completed",
      },
      {},
    ),
    true,
  );

  assert.equal(
    canSubmitTutoringRatingForEndedSession(
      {},
      {
        sessionTerminalState: "ended_insufficient_funds",
      },
    ),
    true,
  );
});

test("guest payer identity is preserved on tutoring ratings", () => {
  const resolved = resolveTutoringRatingSubmission({
    requesterId: "guest_123",
    bookingId: "booking_123",
    bookingData: {
      paymentIntentId: "intent_123",
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
  assert.equal(resolved.raterDisplayName, "Nadia");
  assert.equal(resolved.raterEmail, "nadia@example.com");
});

test("only ended tutoring sessions can be rated", () => {
  assert.throws(
    () => resolveTutoringRatingSubmission({
      requesterId: "student_123",
      bookingId: "booking_123",
      bookingData: {
        paymentIntentId: "intent_123",
        studentId: "student_123",
        tutorId: "tutor_123",
        bookingState: "confirmed",
        reviewStatus: "pending",
        reviewEligible: true,
      },
      paymentIntentData: {
        sessionLifecycleState: "active",
        reviewStatus: "pending",
        reviewEligible: true,
      },
    }),
    (error: unknown) =>
      error instanceof HttpsError &&
      error.code === "failed-precondition" &&
      (error.details as Record<string, unknown>)?.errorCode ===
        "RATING_SESSION_NOT_ENDED",
  );
});

test("tutors cannot rate themselves", () => {
  assert.throws(
    () => resolveTutoringRatingSubmission({
      requesterId: "tutor_123",
      bookingId: "booking_123",
      bookingData: {
        paymentIntentId: "intent_123",
        studentId: "tutor_123",
        tutorId: "tutor_123",
        bookingState: "completed",
        reviewStatus: "pending",
        reviewEligible: true,
      },
      paymentIntentData: {
        sessionTerminalState: "ended_normal",
        reviewStatus: "pending",
        reviewEligible: true,
      },
    }),
    (error: unknown) =>
      error instanceof HttpsError &&
      error.code === "permission-denied" &&
      (error.details as Record<string, unknown>)?.errorCode ===
        "RATING_TUTOR_SELF_FORBIDDEN",
  );
});

test("only the payer side can rate a tutoring booking", () => {
  assert.throws(
    () => resolveTutoringRatingSubmission({
      requesterId: "other_student",
      bookingId: "booking_123",
      bookingData: {
        paymentIntentId: "intent_123",
        studentId: "student_123",
        tutorId: "tutor_123",
        bookingState: "completed",
        reviewStatus: "pending",
        reviewEligible: true,
      },
      paymentIntentData: {
        sessionTerminalState: "ended_normal",
        reviewStatus: "pending",
        reviewEligible: true,
      },
    }),
    (error: unknown) =>
      error instanceof HttpsError &&
      error.code === "permission-denied" &&
      (error.details as Record<string, unknown>)?.errorCode ===
        "RATING_PAYER_ONLY",
  );
});
