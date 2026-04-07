import * as admin from "firebase-admin";
import {HttpsError, onCall} from "./callable";
import {buildRatingSchemaFields} from "./tutoringFirestoreSchema";

const REGION = "europe-west1";
const MIN_STARS = 1;
const MAX_STARS = 5;
const MAX_REVIEW_TEXT_LENGTH = 2000;

type TutoringPayerType = "guest" | "student";

function getDb(): FirebaseFirestore.Firestore {
  return admin.firestore();
}

interface SubmitRatingResult {
  bookingId: string;
  paymentIntentId: string;
  reviewId: string;
  stars: number;
  rating10: number;
  status: string;
  payerType: TutoringPayerType;
  raterType: TutoringPayerType;
}

interface ResolvedTutoringRatingSubmission {
  reviewId: string;
  bookingId: string;
  paymentIntentId: string;
  sessionId: string | null;
  tutorId: string;
  tutorName: string;
  payerId: string;
  payerType: TutoringPayerType;
  raterId: string;
  raterType: TutoringPayerType;
  guestId: string | null;
  raterDisplayName: string;
  raterEmail: string | null;
  raterPhone: string | null;
  studentId: string;
  studentName: string;
  subject: string;
  topic: string;
  billableMinutes: number;
  qualifiesForGoldTick: boolean;
  organizationId: string;
  organizationName: string;
  guestTutoringMode: boolean;
}

function toTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function normalizeLower(value: unknown): string {
  return toTrimmedString(value).toLowerCase();
}

function asInteger(value: unknown): number | null {
  if (typeof value === "number" && Number.isInteger(value)) {
    return value;
  }
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isInteger(parsed)) {
      return parsed;
    }
  }
  return null;
}

function asBillableMinutes(value: unknown): number {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.max(0, Math.round(value));
  }
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return Math.max(0, Math.round(parsed));
    }
  }
  return 0;
}

function getMapValue(
  primary: Record<string, unknown>,
  secondary: Record<string, unknown>,
  ...keys: string[]
): unknown {
  for (const key of keys) {
    if (primary[key] !== undefined && primary[key] !== null) {
      return primary[key];
    }
    if (secondary[key] !== undefined && secondary[key] !== null) {
      return secondary[key];
    }
  }
  return undefined;
}

function throwRatingError(
  code: "invalid-argument" | "permission-denied" | "failed-precondition" | "already-exists" | "not-found",
  errorCode: string,
  message: string
): never {
  throw new HttpsError(code, message, {errorCode});
}

export function isGuestTutoringRater(
  bookingData: Record<string, unknown>,
  paymentIntentData: Record<string, unknown>
): boolean {
  const payerType = normalizeLower(
    getMapValue(bookingData, paymentIntentData, "payerType")
  );
  const accountType = normalizeLower(
    getMapValue(
      bookingData,
      paymentIntentData,
      "studentAccountType",
      "accountType"
    )
  );
  const accessTier = normalizeLower(
    getMapValue(
      bookingData,
      paymentIntentData,
      "studentAccessTier",
      "accessTier"
    )
  );

  return payerType === "guest" ||
    bookingData.guestTutoringMode === true ||
    paymentIntentData.guestTutoringMode === true ||
    bookingData.isGuest === true ||
    paymentIntentData.isGuest === true ||
    bookingData.instantTutorAccess === true ||
    paymentIntentData.instantTutorAccess === true ||
    accountType === "instant_tutor" ||
    accessTier === "instant_tutor";
}

export function canSubmitTutoringRatingForEndedSession(
  bookingData: Record<string, unknown>,
  paymentIntentData: Record<string, unknown>
): boolean {
  const bookingState = normalizeLower(bookingData.bookingState);
  const bookingStatus = normalizeLower(bookingData.status);
  const bookingSessionState = normalizeLower(bookingData.sessionState);
  const sessionLifecycleState = normalizeLower(paymentIntentData.sessionLifecycleState);
  const sessionTerminalState = normalizeLower(paymentIntentData.sessionTerminalState);
  const sessionStatus = normalizeLower(paymentIntentData.sessionStatus);

  return bookingState === "completed" ||
    bookingState === "ended_insufficient_funds" ||
    bookingStatus === "completed" ||
    bookingStatus === "ended_due_to_insufficient_funds" ||
    bookingSessionState === "settled" ||
    bookingSessionState === "ended_due_to_insufficient_funds" ||
    bookingSessionState === "ended_insufficient_funds" ||
    sessionLifecycleState === "settled" ||
    sessionLifecycleState === "ended_insufficient_funds" ||
    sessionTerminalState === "ended_normal" ||
    sessionTerminalState === "ended_insufficient_funds" ||
    sessionStatus === "completed" ||
    sessionStatus === "ended_insufficient_funds";
}

function requirePendingRatingWindow(
  bookingData: Record<string, unknown>,
  paymentIntentData: Record<string, unknown>
): void {
  const reviewStatus = normalizeLower(
    getMapValue(paymentIntentData, bookingData, "reviewStatus")
  );
  const reviewEligible =
    getMapValue(paymentIntentData, bookingData, "reviewEligible") === true;

  if (reviewStatus === "submitted") {
    throwRatingError(
      "already-exists",
      "RATING_ALREADY_SUBMITTED",
      "A rating has already been submitted for this booking."
    );
  }

  if (reviewStatus !== "pending" || !reviewEligible) {
    throwRatingError(
      "failed-precondition",
      "RATING_NOT_ELIGIBLE",
      "This booking is not awaiting a tutor rating."
    );
  }
}

export function resolveTutoringRatingSubmission(params: {
  requesterId: string;
  bookingId: string;
  bookingData: Record<string, unknown>;
  paymentIntentData: Record<string, unknown>;
  guestCustomerData?: Record<string, unknown>;
}): ResolvedTutoringRatingSubmission {
  const bookingData = params.bookingData;
  const paymentIntentData = params.paymentIntentData;
  const guestCustomerData = params.guestCustomerData ?? {};
  const paymentIntentId =
    toTrimmedString(getMapValue(bookingData, paymentIntentData, "paymentIntentId", "requestId")) ||
    params.bookingId;
  const payerId = toTrimmedString(
    getMapValue(bookingData, paymentIntentData, "studentId")
  );
  const payerType: TutoringPayerType =
    isGuestTutoringRater(bookingData, paymentIntentData) ? "guest" : "student";
  const tutorId = toTrimmedString(
    getMapValue(bookingData, paymentIntentData, "tutorId")
  );

  if (!payerId) {
    throwRatingError(
      "failed-precondition",
      "RATING_PAYER_MISSING",
      "Booking is missing payer information."
    );
  }
  if (payerId !== params.requesterId) {
    throwRatingError(
      "permission-denied",
      "RATING_PAYER_ONLY",
      "Only the payer side can submit a tutor rating."
    );
  }
  if (!tutorId) {
    throwRatingError(
      "failed-precondition",
      "RATING_TUTOR_MISSING",
      "Booking is missing tutor information."
    );
  }
  if (tutorId === params.requesterId) {
    throwRatingError(
      "permission-denied",
      "RATING_TUTOR_SELF_FORBIDDEN",
      "Tutors cannot rate themselves on tutoring bookings."
    );
  }
  if (!canSubmitTutoringRatingForEndedSession(bookingData, paymentIntentData)) {
    throwRatingError(
      "failed-precondition",
      "RATING_SESSION_NOT_ENDED",
      "Ratings are only allowed after completed or insufficient-funds tutoring sessions."
    );
  }

  requirePendingRatingWindow(bookingData, paymentIntentData);

  const guestId = payerType === "guest" ? payerId : null;
  if (guestId) {
    const guestStatus = normalizeLower(guestCustomerData.status);
    const storedGuestId = toTrimmedString(
      getMapValue(
        guestCustomerData,
        guestCustomerData,
        "guestId",
        "guestTutoringCustomerId",
        "studentId"
      )
    );
    if (!storedGuestId || storedGuestId !== guestId) {
      throwRatingError(
        "failed-precondition",
        "RATING_GUEST_IDENTITY_MISSING",
        "Guest tutoring identity is missing for this rating."
      );
    }
    if (guestStatus && guestStatus !== "active") {
      throwRatingError(
        "failed-precondition",
        "RATING_GUEST_IDENTITY_INACTIVE",
        "Guest tutoring identity is not active."
      );
    }
  }

  const studentName = toTrimmedString(
    getMapValue(
      bookingData,
      paymentIntentData,
      "studentName",
      "firstName"
    )
  ) ||
    toTrimmedString(getMapValue(guestCustomerData, bookingData, "firstName")) ||
    "Student";

  return {
    reviewId: params.bookingId,
    bookingId: params.bookingId,
    paymentIntentId,
    sessionId: toTrimmedString(
      getMapValue(
        bookingData,
        paymentIntentData,
        "tutorSessionId",
        "sessionId"
      )
    ) || null,
    tutorId,
    tutorName: toTrimmedString(
      getMapValue(bookingData, paymentIntentData, "tutorName")
    ) || "Tutor",
    payerId,
    payerType,
    raterId: payerId,
    raterType: payerType,
    guestId,
    raterDisplayName:
      guestId ?
        (
          toTrimmedString(getMapValue(guestCustomerData, bookingData, "firstName")) ||
          studentName
        ) :
        studentName,
    raterEmail:
      toTrimmedString(getMapValue(guestCustomerData, bookingData, "email")) || null,
    raterPhone:
      toTrimmedString(getMapValue(guestCustomerData, bookingData, "phone")) || null,
    studentId: payerId,
    studentName,
    subject: toTrimmedString(getMapValue(bookingData, paymentIntentData, "subject")) || "Tutoring",
    topic: toTrimmedString(getMapValue(bookingData, paymentIntentData, "topic")),
    billableMinutes: asBillableMinutes(
      getMapValue(bookingData, paymentIntentData, "billableMinutes")
    ),
    qualifiesForGoldTick:
      getMapValue(paymentIntentData, bookingData, "goldTickQualifiedSession") === true,
    organizationId: toTrimmedString(
      getMapValue(bookingData, paymentIntentData, "organizationId")
    ),
    organizationName: toTrimmedString(
      getMapValue(bookingData, paymentIntentData, "organizationName")
    ),
    guestTutoringMode: guestId !== null,
  };
}

const submitTutoringRatingCallable = onCall(
  {region: REGION},
  async (request): Promise<SubmitRatingResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }

    const bookingId = toTrimmedString(request.data?.bookingId);
    const stars = asInteger(request.data?.stars);
    const reviewText = toTrimmedString(request.data?.reviewText);

    if (!bookingId) {
      throwRatingError("invalid-argument", "RATING_BOOKING_REQUIRED", "bookingId is required.");
    }
    if (stars === null || stars < MIN_STARS || stars > MAX_STARS) {
      throwRatingError(
        "invalid-argument",
        "RATING_STARS_INVALID",
        "stars must be an integer between 1 and 5."
      );
    }
    if (reviewText.length > MAX_REVIEW_TEXT_LENGTH) {
      throwRatingError(
        "invalid-argument",
        "RATING_REVIEW_TEXT_TOO_LONG",
        "reviewText is too long."
      );
    }

    const requesterId = request.auth.uid;
    const db = getDb();
    const bookingRef = db.collection("tutor_requests").doc(bookingId);

    return db.runTransaction(async (tx) => {
      const bookingSnap = await tx.get(bookingRef);
      if (!bookingSnap.exists) {
        throwRatingError("not-found", "RATING_BOOKING_NOT_FOUND", "Booking not found.");
      }

      const bookingData = bookingSnap.data() ?? {};
      const paymentIntentId =
        toTrimmedString(bookingData.paymentIntentId) || bookingId;
      const paymentIntentRef = db
        .collection("session_payment_intents")
        .doc(paymentIntentId);
      const reviewRef = db.collection("tutor_session_reviews").doc(bookingId);
      const legacyReviewRef = paymentIntentId !== bookingId ?
        db.collection("tutor_session_reviews").doc(paymentIntentId) :
        null;
      const existingReviewQuery = db.collection("tutor_session_reviews")
        .where("requestId", "==", bookingId)
        .limit(1);

      const paymentIntentSnap = await tx.get(paymentIntentRef);
      const canonicalReviewSnap = await tx.get(reviewRef);
      const legacyReviewSnap = legacyReviewRef ? await tx.get(legacyReviewRef) : null;
      const existingReviewSnap = await tx.get(existingReviewQuery);
      if (!paymentIntentSnap.exists) {
        throwRatingError(
          "failed-precondition",
          "RATING_PAYMENT_SESSION_MISSING",
          "Booking payment session is missing."
        );
      }
      if (
        canonicalReviewSnap.exists ||
        legacyReviewSnap?.exists ||
        !existingReviewSnap.empty
      ) {
        throwRatingError(
          "already-exists",
          "RATING_ALREADY_SUBMITTED",
          "A rating has already been submitted for this booking."
        );
      }

      const paymentIntentData = paymentIntentSnap.data() ?? {};
      const guestId = isGuestTutoringRater(bookingData, paymentIntentData) ?
        requesterId :
        "";
      const guestRef = guestId ?
        db.collection("guest_tutoring_customers").doc(guestId) :
        null;
      const guestSnap = guestRef ? await tx.get(guestRef) : null;
      const guestCustomerData = guestSnap?.data() ?? {};

      const resolved = resolveTutoringRatingSubmission({
        requesterId,
        bookingId,
        bookingData,
        paymentIntentData,
        guestCustomerData,
      });

      const rating10 = Number((stars * 2).toFixed(1));
      const reviewPayload = {
        ...buildRatingSchemaFields(resolved.reviewId, {
          requestId: resolved.bookingId,
          bookingId: resolved.bookingId,
          sessionId: resolved.sessionId,
          paymentIntentId: resolved.paymentIntentId,
          status: "submitted",
          ratingStatus: "submitted",
          payerType: resolved.payerType,
          payerId: resolved.payerId,
          raterType: resolved.raterType,
          raterId: resolved.raterId,
          guestId: resolved.guestId,
          tutorId: resolved.tutorId,
          studentId: resolved.studentId,
          guestTutoringMode: resolved.guestTutoringMode,
        }),
        paymentIntentId: resolved.paymentIntentId,
        requestId: resolved.bookingId,
        bookingId: resolved.bookingId,
        sessionId: resolved.sessionId,
        payerType: resolved.payerType,
        payerId: resolved.payerId,
        raterType: resolved.raterType,
        raterId: resolved.raterId,
        raterDisplayName: resolved.raterDisplayName,
        raterEmail: resolved.raterEmail,
        raterPhone: resolved.raterPhone,
        guestId: resolved.guestId,
        studentId: resolved.studentId,
        studentName: resolved.studentName,
        tutorId: resolved.tutorId,
        tutorName: resolved.tutorName,
        subject: resolved.subject,
        topic: resolved.topic,
        billableMinutes: resolved.billableMinutes,
        qualifiesForGoldTick: resolved.qualifiesForGoldTick,
        organizationId: resolved.organizationId,
        organizationName: resolved.organizationName,
        stars,
        rating10,
        reviewText,
        note: reviewText,
        status: "submitted",
        ratingStatus: "submitted",
        source: "callable",
        tutoringPaymentRail: "TUTORING",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      tx.create(reviewRef, reviewPayload);
      tx.set(paymentIntentRef, {
        reviewStatus: "submitted",
        reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      tx.set(bookingRef, {
        reviewStatus: "submitted",
        reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      if (resolved.guestId && guestRef) {
        tx.set(guestRef, {
          guestId: resolved.guestId,
          guestTutoringCustomerId: resolved.guestId,
          studentId: resolved.guestId,
          isGuest: true,
          accountType: "instant_tutor",
          accessTier: "instant_tutor",
          accessMode: "instantTutor",
          instantTutorAccess: true,
          status: "active",
          lastRatedBookingId: bookingId,
          lastReviewId: reviewRef.id,
          lastUsedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
      } else {
        tx.set(db.collection("users").doc(requesterId), {
          lastTutorRatingBookingId: bookingId,
          lastTutorRatingAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
      }

      return {
        bookingId,
        paymentIntentId: resolved.paymentIntentId,
        reviewId: reviewRef.id,
        stars,
        rating10,
        status: "submitted",
        payerType: resolved.payerType,
        raterType: resolved.raterType,
      };
    });
  }
);

export const submitTutoringRating = submitTutoringRatingCallable;
export const submitRating = submitTutoringRatingCallable;
