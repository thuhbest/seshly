import {createHash} from "node:crypto";
import {HttpsError, onCall} from "./callable";
import * as admin from "firebase-admin";
import {assertTutorEligibleForTutoring} from "./tutorApprovalState";
import {
  buildBookingSchemaFields,
  buildGuestTutoringCustomerDoc,
  buildPaymentSessionSchemaFields,
} from "./tutoringFirestoreSchema";
import {
  assertBookingTransition,
  toTutoringHttpsErrorCode,
  TutoringBookingState,
  TutoringStateTransitionError,
  TutoringTransitionActor,
} from "./tutoringStateMachine";

const db = admin.firestore();

const REGION = "europe-west1";
const PLATFORM_MARKUP_MULTIPLIER = 1.2;
const INITIAL_BUFFER_MINUTES = 20;
const PAYMENT_MODEL = "card_authorize_settlement";
const CURRENCY = "ZAR";
const IDEMPOTENCY_TTL_HOURS = 24;
const MAX_RATE_PER_MIN_ZAR = 10000;
const REQUEST_TYPES = new Set(["INSTANT", "IN_5", "IN_30", "CUSTOM"]);

export type BookingRequestType = "INSTANT" | "IN_5" | "IN_30" | "CUSTOM";

interface CreateBookingPayload {
  studentId?: unknown;
  studentName?: unknown;
  tutorId?: unknown;
  requestType?: unknown;
  scheduledAt?: unknown;
  estimatedDurationMinutes?: unknown;
  tutorRatePerMinZar?: unknown;
  idempotencyKey?: unknown;
  subject?: unknown;
  topic?: unknown;
  questionText?: unknown;
  postId?: unknown;
  bookingMode?: unknown;
  prepMinutes?: unknown;
  paymentProfileType?: unknown;
  paymentMethodSummary?: unknown;
  studentAccessTier?: unknown;
  studentAccountType?: unknown;
}

interface CreateBookingResult {
  bookingId: string;
  scheduledAt: string;
  tutorRatePerMinZar: number;
  studentRatePerMinZar: number;
  requestType: BookingRequestType;
  payerType: "guest" | "student";
  paymentMode: "tutoring_metered";
  paymentStatus: string;
  initialBufferAmount: number;
  paymentIntentId: string;
}

function toTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asPositiveMoney(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value) && value > 0) {
    return roundToCents(value);
  }
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed) && parsed > 0) {
      return roundToCents(parsed);
    }
  }
  return null;
}

function roundToCents(value: number): number {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

export interface TutoringBookingQuoteInput {
  authIsAnonymous: boolean;
  studentId: string;
  tutorId: string;
  requestType?: string;
  bookingMode?: string;
  scheduledAt?: unknown;
  estimatedDurationMinutes?: unknown;
  tutorRatePerMinZar: number;
  paymentProfileType?: string;
  studentAccessTier?: string;
  studentAccountType?: string;
  studentData?: Record<string, unknown>;
  now?: Date;
}

export interface TutoringBookingQuote {
  studentId: string;
  tutorId: string;
  requestType: BookingRequestType;
  scheduledAt: Date;
  estimatedDurationMinutes: number | null;
  tutorRatePerMinZar: number;
  studentRatePerMinZar: number;
  platformFeePerMinute: number;
  initialBufferMinutes: number;
  initialBufferAmountZar: number;
  payerType: "guest" | "student";
  guestTutoringMode: boolean;
  bookingMode: string;
  prepMinutes: number;
  paymentMode: "tutoring_metered";
  paymentStatus: "authorization_pending";
  paymentSessionStatus: "booking_created";
  paymentProfileType: string;
  studentAccessTier: string;
  studentAccountType: string;
  estimatedDurationPlanningOnly: true;
  sessionMayEndAnytime: true;
}

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

function readScheduledAt(input: unknown): Date | null {
  if (!input) return null;
  if (input instanceof Date && !Number.isNaN(input.getTime())) return input;

  if (typeof input === "string" || typeof input === "number") {
    const date = new Date(input);
    return Number.isNaN(date.getTime()) ? null : date;
  }

  if (typeof input === "object") {
    const value = input as {
      _seconds?: unknown;
      seconds?: unknown;
      _nanoseconds?: unknown;
      nanoseconds?: unknown;
      toDate?: () => Date;
    };

    if (typeof value.toDate === "function") {
      const date = value.toDate();
      return Number.isNaN(date.getTime()) ? null : date;
    }

    const secondsRaw = value.seconds ?? value._seconds;
    const nanosRaw = value.nanoseconds ?? value._nanoseconds;
    const seconds = typeof secondsRaw === "number" ? secondsRaw : Number(secondsRaw);
    const nanos = typeof nanosRaw === "number" ? nanosRaw : Number(nanosRaw ?? 0);
    if (Number.isFinite(seconds) && Number.isFinite(nanos)) {
      return new Date(seconds * 1000 + nanos / 1000000);
    }
  }

  return null;
}

function asPositiveWholeMinutes(value: unknown): number | null {
  if (typeof value === "number" && Number.isInteger(value) && value > 0) {
    return value;
  }
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isInteger(parsed) && parsed > 0) {
      return parsed;
    }
  }
  return null;
}

function authUsesAnonymousProvider(
  auth: {token?: Record<string, unknown>} | null | undefined
): boolean {
  const firebaseToken =
    (auth?.token?.firebase as Record<string, unknown> | undefined) ?? {};
  return toTrimmedString(firebaseToken.sign_in_provider).toLowerCase() ===
    "anonymous";
}

function isGuestTutoringStudent(data: Record<string, unknown>): boolean {
  return toTrimmedString(data.accessTier).toLowerCase() === "instant_tutor" ||
    toTrimmedString(data.accountType).toLowerCase() === "instant_tutor" ||
    data.instantTutorAccess === true;
}

function resolvePayerType(params: {
  authIsAnonymous: boolean;
  studentData: Record<string, unknown>;
  studentAccessTier: string;
  studentAccountType: string;
}): "guest" | "student" {
  const payloadSignalsGuest =
    params.studentAccessTier.toLowerCase() === "instant_tutor" ||
    params.studentAccountType.toLowerCase() === "instant_tutor";
  if (
    params.authIsAnonymous ||
    payloadSignalsGuest ||
    isGuestTutoringStudent(params.studentData)
  ) {
    return "guest";
  }
  return "student";
}

function validatePayerFlow(params: {
  payerType: "guest" | "student";
  authIsAnonymous: boolean;
  studentData: Record<string, unknown>;
  paymentProfileType: string;
}): void {
  const profileType = params.paymentProfileType.toLowerCase();
  if (params.authIsAnonymous && params.payerType !== "guest") {
    throw new HttpsError(
      "permission-denied",
      "Anonymous learners can only create guest tutoring bookings."
    );
  }
  if (
    params.payerType === "guest" &&
    profileType &&
    !profileType.includes("temporary")
  ) {
    throw new HttpsError(
      "failed-precondition",
      "Guest tutoring bookings must use a temporary tutoring payment profile."
    );
  }
  if (
    params.payerType === "student" &&
    profileType.includes("temporary")
  ) {
    throw new HttpsError(
      "failed-precondition",
      "Authenticated student bookings must use a saved student payment profile."
    );
  }
  if (
    params.payerType === "student" &&
    isGuestTutoringStudent(params.studentData)
  ) {
    throw new HttpsError(
      "failed-precondition",
      "Instant tutor guest accounts must book through the guest tutoring flow."
    );
  }
}

function resolveScheduledAt(
  requestType: BookingRequestType,
  scheduledAtInput: unknown,
  now: Date
): Date {
  switch (requestType) {
  case "INSTANT":
    return now;
  case "IN_5":
    return new Date(now.getTime() + 5 * 60 * 1000);
  case "IN_30":
    return new Date(now.getTime() + 30 * 60 * 1000);
  case "CUSTOM": {
    const scheduledAt = readScheduledAt(scheduledAtInput);
    if (!scheduledAt) {
      throw new HttpsError(
        "invalid-argument",
        "scheduledAt is required for CUSTOM bookings."
      );
    }
    if (scheduledAt.getTime() <= now.getTime()) {
      throw new HttpsError(
        "invalid-argument",
        "scheduledAt must be in the future for CUSTOM bookings."
      );
    }
    return scheduledAt;
  }
  }
}

function buildIdempotencyFingerprint(params: {
  studentId: string;
  tutorId: string;
  requestType: BookingRequestType;
  scheduledAtIso: string;
  tutorRatePerMinZar: number;
  idempotencyKey: string;
}): string {
  const material = [
    params.studentId,
    params.tutorId,
    params.requestType,
    params.scheduledAtIso,
    params.tutorRatePerMinZar.toFixed(2),
    params.idempotencyKey,
  ].join("|");

  return createHash("sha256").update(material).digest("hex");
}

function readTutorRateFromUserData(data: Record<string, unknown>): number | null {
  const tutorProfile =
    (data.tutorProfile as Record<string, unknown> | undefined) ?? {};

  return asPositiveMoney(
    tutorProfile.displayRate ??
      data.displayRate ??
      tutorProfile.ratePerMinute ??
      data.ratePerMinute
  );
}

function bookingModeFromRequestType(requestType: BookingRequestType): string {
  switch (requestType) {
  case "INSTANT":
    return "instant";
  case "IN_5":
    return "prep_5";
  case "IN_30":
    return "prep_30";
  case "CUSTOM":
    return "scheduled";
  }
}

function prepMinutesFromRequestType(requestType: BookingRequestType): number {
  switch (requestType) {
  case "IN_5":
    return 5;
  case "IN_30":
    return 30;
  case "CUSTOM":
    return 0;
  case "INSTANT":
    return 0;
  }
}

function normalizeRequestType(
  requestTypeRaw: string,
  bookingModeRaw: string
): BookingRequestType | null {
  if (REQUEST_TYPES.has(requestTypeRaw)) {
    return requestTypeRaw as BookingRequestType;
  }
  switch (bookingModeRaw) {
  case "instant":
    return "INSTANT";
  case "prep_5":
  case "prep5":
    return "IN_5";
  case "prep_30":
  case "prep30":
    return "IN_30";
  case "scheduled":
  case "custom":
    return "CUSTOM";
  default:
    return null;
  }
}

export function resolveTutoringBookingQuote(
  params: TutoringBookingQuoteInput
): TutoringBookingQuote {
  const requestTypeRaw = toTrimmedString(params.requestType).toUpperCase();
  const bookingModeRaw = toTrimmedString(params.bookingMode).toLowerCase();
  const requestType = normalizeRequestType(requestTypeRaw, bookingModeRaw);
  if (!requestType) {
    throw new HttpsError(
      "invalid-argument",
      "requestType must be INSTANT, IN_5, IN_30, or CUSTOM."
    );
  }

  const tutorRatePerMinZar = asPositiveMoney(params.tutorRatePerMinZar);
  if (!tutorRatePerMinZar) {
    throw new HttpsError(
      "invalid-argument",
      "tutorRatePerMinZar must be a positive amount."
    );
  }
  if (tutorRatePerMinZar > MAX_RATE_PER_MIN_ZAR) {
    throw new HttpsError(
      "invalid-argument",
      "tutorRatePerMinZar exceeds the allowed maximum."
    );
  }

  const estimatedDurationMinutes = asPositiveWholeMinutes(
    params.estimatedDurationMinutes
  );
  const now = params.now ?? new Date();
  const scheduledAt = resolveScheduledAt(requestType, params.scheduledAt, now);
  const studentData = params.studentData ?? {};
  const resolvedStudentAccessTier =
    toTrimmedString(params.studentAccessTier) ||
    toTrimmedString(studentData.accessTier) ||
    (params.authIsAnonymous ? "instant_tutor" : "student");
  const resolvedStudentAccountType =
    toTrimmedString(params.studentAccountType) ||
    toTrimmedString(studentData.accountType) ||
    (params.authIsAnonymous ? "instant_tutor" : "student");
  const payerType = resolvePayerType({
    authIsAnonymous: params.authIsAnonymous,
    studentData,
    studentAccessTier: resolvedStudentAccessTier,
    studentAccountType: resolvedStudentAccountType,
  });
  validatePayerFlow({
    payerType,
    authIsAnonymous: params.authIsAnonymous,
    studentData,
    paymentProfileType: toTrimmedString(params.paymentProfileType),
  });

  const studentRatePerMinZar = roundToCents(
    tutorRatePerMinZar * PLATFORM_MARKUP_MULTIPLIER
  );
  const platformFeePerMinute = roundToCents(
    studentRatePerMinZar - tutorRatePerMinZar
  );
  const initialBufferAmountZar = roundToCents(
    INITIAL_BUFFER_MINUTES * studentRatePerMinZar
  );
  const guestTutoringMode = payerType === "guest";
  const paymentProfileType = toTrimmedString(params.paymentProfileType) ||
    (guestTutoringMode ? "temporary_instant_tutor_card" : "saved_student_card");

  return {
    studentId: toTrimmedString(params.studentId),
    tutorId: toTrimmedString(params.tutorId),
    requestType,
    scheduledAt,
    estimatedDurationMinutes,
    tutorRatePerMinZar,
    studentRatePerMinZar,
    platformFeePerMinute,
    initialBufferMinutes: INITIAL_BUFFER_MINUTES,
    initialBufferAmountZar,
    payerType,
    guestTutoringMode,
    bookingMode: bookingModeRaw || bookingModeFromRequestType(requestType),
    prepMinutes: prepMinutesFromRequestType(requestType),
    paymentMode: "tutoring_metered",
    paymentStatus: "authorization_pending",
    paymentSessionStatus: "booking_created",
    paymentProfileType,
    studentAccessTier: resolvedStudentAccessTier,
    studentAccountType: resolvedStudentAccountType,
    estimatedDurationPlanningOnly: true,
    sessionMayEndAnytime: true,
  };
}

const createTutoringBookingCallable = onCall(
  {region: REGION},
  async (request): Promise<CreateBookingResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }

    const payload = (request.data ?? {}) as CreateBookingPayload;
    const authUid = request.auth.uid;
    const authIsAnonymous = authUsesAnonymousProvider(request.auth);
    const studentId = toTrimmedString(payload.studentId);
    const studentNameFromPayload = toTrimmedString(payload.studentName);
    const tutorId = toTrimmedString(payload.tutorId);
    const requestTypeRaw = toTrimmedString(payload.requestType).toUpperCase();
    const bookingModeRaw = toTrimmedString(payload.bookingMode).toLowerCase();
    const estimatedDurationMinutes = asPositiveWholeMinutes(
      payload.estimatedDurationMinutes
    );
    const idempotencyKey = toTrimmedString(payload.idempotencyKey);
    const tutorRatePerMinZar = asPositiveMoney(payload.tutorRatePerMinZar);
    const subject = toTrimmedString(payload.subject) || "Tutoring";
    const topic = toTrimmedString(payload.topic);
    const questionText = toTrimmedString(payload.questionText);
    const postId = toTrimmedString(payload.postId);
    const paymentProfileType = toTrimmedString(payload.paymentProfileType);
    const paymentMethodSummary = toTrimmedString(payload.paymentMethodSummary);
    const studentAccessTier = toTrimmedString(payload.studentAccessTier);
    const studentAccountType = toTrimmedString(payload.studentAccountType);

    if (!studentId) {
      throw new HttpsError("invalid-argument", "studentId is required.");
    }
    if (studentId !== authUid) {
      throw new HttpsError(
        "permission-denied",
        "studentId must match the authenticated user."
      );
    }
    if (!tutorId) {
      throw new HttpsError("invalid-argument", "tutorId is required.");
    }
    if (studentId === tutorId) {
      throw new HttpsError(
        "invalid-argument",
        "studentId and tutorId must be different."
      );
    }
    const requestType = normalizeRequestType(requestTypeRaw, bookingModeRaw);
    if (!requestType) {
      throw new HttpsError(
        "invalid-argument",
        "requestType must be INSTANT, IN_5, IN_30, or CUSTOM."
      );
    }
    if (!tutorRatePerMinZar) {
      throw new HttpsError(
        "invalid-argument",
        "tutorRatePerMinZar must be a positive amount."
      );
    }
    if (tutorRatePerMinZar > MAX_RATE_PER_MIN_ZAR) {
      throw new HttpsError(
        "invalid-argument",
        "tutorRatePerMinZar exceeds the allowed maximum."
      );
    }
    const now = new Date();
    const scheduledAtDate = resolveScheduledAt(
      requestType,
      payload.scheduledAt,
      now
    );
    const scheduledAtIso = scheduledAtDate.toISOString();

    const studentRatePerMinZar = roundToCents(
      tutorRatePerMinZar * PLATFORM_MARKUP_MULTIPLIER
    );
    const platformFeePerMinute = roundToCents(
      studentRatePerMinZar - tutorRatePerMinZar
    );
    const initialBufferAmount = roundToCents(
      INITIAL_BUFFER_MINUTES * studentRatePerMinZar
    );

    const fingerprint = buildIdempotencyFingerprint({
      studentId,
      tutorId,
      requestType,
      scheduledAtIso,
      tutorRatePerMinZar,
      idempotencyKey,
    });
    const idempotencyRef = db.collection("booking_idempotency").doc(fingerprint);
    const bookingRef = db.collection("tutor_requests").doc();
    const paymentIntentRef = db.collection("session_payment_intents").doc(bookingRef.id);
    const studentRef = db.collection("users").doc(studentId);
    const guestCustomerRef = db.collection("guest_tutoring_customers").doc(studentId);
    const tutorRef = db.collection("users").doc(tutorId);
    const expiresAt = admin.firestore.Timestamp.fromDate(
      new Date(now.getTime() + IDEMPOTENCY_TTL_HOURS * 60 * 60 * 1000)
    );

    return db.runTransaction(async (tx) => {
      const idempotencySnap = await tx.get(idempotencyRef);
      if (idempotencySnap.exists) {
        const data = idempotencySnap.data() ?? {};
        const existingBookingId = toTrimmedString(data.bookingId);
        if (existingBookingId) {
          return {
            bookingId: existingBookingId,
            scheduledAt: toTrimmedString(data.scheduledAt) || scheduledAtIso,
            tutorRatePerMinZar:
              asPositiveMoney(data.tutorRatePerMinZar) ?? tutorRatePerMinZar,
            studentRatePerMinZar: asPositiveMoney(data.studentRatePerMinZar) ??
              studentRatePerMinZar,
            requestType:
              (toTrimmedString(data.requestType).toUpperCase() as BookingRequestType) ||
              requestType,
            payerType:
              toTrimmedString(data.payerType).toLowerCase() === "guest" ?
                "guest" :
                "student",
            paymentMode: "tutoring_metered",
            paymentStatus:
              toTrimmedString(data.paymentStatus) || "authorization_pending",
            initialBufferAmount: asPositiveMoney(data.initialBufferAmount) ??
              initialBufferAmount,
            paymentIntentId:
              toTrimmedString(data.paymentIntentId) || existingBookingId,
          };
        }
      }

      const [studentSnap, tutorSnap, guestCustomerSnap] = await Promise.all([
        tx.get(studentRef),
        tx.get(tutorRef),
        authIsAnonymous ? tx.get(guestCustomerRef) : Promise.resolve(null),
      ]);

      if (!studentSnap.exists && !authIsAnonymous) {
        throw new HttpsError("not-found", "Student not found.");
      }
      if (!tutorSnap.exists) {
        throw new HttpsError("not-found", "Tutor not found.");
      }

      const tutorData = tutorSnap.data() ?? {};
      assertTutorEligibleForTutoring(
        tutorData as Record<string, unknown>,
        tutorId
      );
      if (tutorData.tutorRequestsEnabled === false) {
        throw new HttpsError(
          "failed-precondition",
          "Tutor is not accepting booking requests right now."
        );
      }

      const storedTutorRate = readTutorRateFromUserData(
        tutorData as Record<string, unknown>
      );
      if (
        storedTutorRate !== null &&
        Math.abs(storedTutorRate - tutorRatePerMinZar) > 0.009
      ) {
        throw new HttpsError(
          "failed-precondition",
          "Tutor rate does not match the current tutor profile."
        );
      }

      const tutorName =
        toTrimmedString(tutorData.fullName) ||
        toTrimmedString(tutorData.displayName) ||
        "Tutor";
      const studentData = {
        ...(studentSnap.data() ?? {}),
        ...((guestCustomerSnap?.data() as Record<string, unknown> | undefined) ?? {}),
      };
      const studentName =
        studentNameFromPayload ||
        toTrimmedString(studentData.firstName) ||
        toTrimmedString(studentData.fullName) ||
        toTrimmedString(studentData.displayName) ||
        "Student";
      const organizationMembership =
        (tutorData.organizationMembership as Record<string, unknown> | undefined) ?? {};
      const tutorProfile =
        (tutorData.tutorProfile as Record<string, unknown> | undefined) ?? {};
      const resolvedStudentAccessTier =
        studentAccessTier ||
        toTrimmedString(studentData.accessTier) ||
        (authIsAnonymous ? "instant_tutor" : "verified_student");
      const resolvedStudentAccountType =
        studentAccountType ||
        toTrimmedString(studentData.accountType) ||
        (authIsAnonymous ? "instant_tutor" : "student");
      const payerType = resolvePayerType({
        authIsAnonymous,
        studentData: studentData as Record<string, unknown>,
        studentAccessTier: resolvedStudentAccessTier,
        studentAccountType: resolvedStudentAccountType,
      });
      validatePayerFlow({
        payerType,
        authIsAnonymous,
        studentData: studentData as Record<string, unknown>,
        paymentProfileType,
      });
      const guestTutoringMode = payerType === "guest";
      const questionSnippet = questionText.length > 160 ?
        questionText.slice(0, 160) :
        questionText;
      const prepMinutes = prepMinutesFromRequestType(requestType);
      const bookingMode = bookingModeRaw || bookingModeFromRequestType(requestType);
      const resolvedPaymentProfileType = paymentProfileType ||
        (guestTutoringMode ? "temporary_instant_tutor_card" : "saved_student_card");
      const pricing = {
        tutorRatePerMinute: tutorRatePerMinZar,
        platformFeePerMinute,
        totalRatePerMinute: studentRatePerMinZar,
      };
      const pricingSnapshot = {
        tutorBaseRateZar: tutorRatePerMinZar,
        platformFeeZar: platformFeePerMinute,
        studentRateZar: studentRatePerMinZar,
      };
      assertBookingStateOrThrow({
        current: null,
        next: TutoringBookingState.CREATED,
        actor: TutoringTransitionActor.STUDENT,
        isGuestSession: guestTutoringMode,
      });
      const bookingBase = {
        requestId: bookingRef.id,
        studentId,
        studentName,
        tutorId,
        tutorName,
        requestType,
        bookingType: requestType,
        bookingMode,
        prepMinutes,
        bookingState: TutoringBookingState.CREATED,
        status: "pending",
        sessionState: "requested",
        paymentStatus: "authorization_pending",
        paymentIntentId: paymentIntentRef.id,
        tutorRatePerMinZar,
        studentRatePerMinZar,
        paymentModel: PAYMENT_MODEL,
        paymentMode: "tutoring_metered",
        paymentSystem: "TUTORING",
        tutoringPaymentRail: "TUTORING",
        noFreeLearningPastAuthorizedMinutes: true,
        estimatedSessionMinutes: estimatedDurationMinutes,
        estimatedDurationMinutes,
        estimatedDurationPlanningOnly: true,
        sessionMayEndAnytime: true,
        payerType,
        initialBufferAmountZar: initialBufferAmount,
        holdAmountZar: initialBufferAmount,
        tutorRatePerMinute: tutorRatePerMinZar,
        platformFeePerMinute,
        totalRatePerMinute: studentRatePerMinZar,
        pricing,
        pricingSnapshot,
        currency: CURRENCY,
        subject,
        topic,
        questionText,
        questionSnippet,
        postId: postId || null,
        source: postId ? "post" : "manual",
        studentAccessTier: resolvedStudentAccessTier,
        studentAccountType: resolvedStudentAccountType,
        guestTutoringMode,
        paymentProfileType: resolvedPaymentProfileType,
        paymentMethodSummary,
        paymentMethodStatus: paymentMethodSummary ? "ready" : "missing",
        platformFeePercent: 20,
        requestedAt: admin.firestore.FieldValue.serverTimestamp(),
        scheduledAt: admin.firestore.Timestamp.fromDate(scheduledAtDate),
        idempotencyKey: fingerprint,
        idempotencyExpiresAt: expiresAt,
        organizationId: toTrimmedString(
          organizationMembership.organizationId ?? tutorProfile.organizationId
        ),
        organizationName: toTrimmedString(
          organizationMembership.organizationName ?? tutorProfile.organizationName
        ),
        organizationLogoUrl: toTrimmedString(
          organizationMembership.organizationLogoUrl
        ),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      const paymentIntentBase = {
        requestId: bookingRef.id,
        studentId,
        tutorId,
        tutorName,
        status: "booking_created",
        holdStatus: "pending",
        settlementStatus: "pending",
        reviewStatus: "not_ready",
        reviewEligible: false,
        paymentModel: PAYMENT_MODEL,
        paymentMode: "tutoring_metered",
        paymentSystem: "TUTORING",
        tutoringPaymentRail: "TUTORING",
        noFreeLearningPastAuthorizedMinutes: true,
        protectedMinutesPurchased: 0,
        protectedMinutesRemaining: 0,
        consumedMinutes: 0,
        refillAttemptCount: 0,
        lowFundsAt: null,
        estimatedHoldMinutes: INITIAL_BUFFER_MINUTES,
        estimatedDurationMinutes,
        estimatedDurationPlanningOnly: true,
        sessionMayEndAnytime: true,
        holdAmountZar: initialBufferAmount,
        holdRemainingZar: initialBufferAmount,
        tutorRatePerMinZar,
        studentRatePerMinZar,
        payerType,
        tutorRatePerMinute: tutorRatePerMinZar,
        platformFeePerMinute,
        totalRatePerMinute: studentRatePerMinZar,
        pricing,
        pricingSnapshot,
        currency: CURRENCY,
        requestType,
        bookingMode,
        prepMinutes,
        scheduledAt: admin.firestore.Timestamp.fromDate(scheduledAtDate),
        subject,
        topic,
        questionText,
        questionSnippet,
        postId: postId || null,
        source: postId ? "post" : "manual",
        studentAccessTier: resolvedStudentAccessTier,
        studentAccountType: resolvedStudentAccountType,
        guestTutoringMode,
        paymentProfileType: resolvedPaymentProfileType,
        paymentMethodSummary,
        paymentMethodStatus: paymentMethodSummary ? "ready" : "missing",
        platformFeePercent: 20,
        idempotencyKey: fingerprint,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      tx.set(bookingRef, {
        ...bookingBase,
        ...buildBookingSchemaFields(bookingRef.id, bookingBase),
      });

      tx.set(paymentIntentRef, {
        ...paymentIntentBase,
        ...buildPaymentSessionSchemaFields(paymentIntentRef.id, paymentIntentBase),
      });

      if (guestTutoringMode) {
        tx.set(guestCustomerRef, buildGuestTutoringCustomerDoc({
          customerId: studentId,
          userData: {
            ...studentData,
            firstName:
              toTrimmedString(studentData.firstName) ||
              studentNameFromPayload ||
              studentName,
          } as Record<string, unknown>,
          bookingData: bookingBase,
          temporaryPaymentData:
            (guestCustomerSnap?.data() as Record<string, unknown> | undefined) ?? {},
          tutoringBookingCount: Math.max(
            0,
            Number(guestCustomerSnap?.data()?.tutoringBookingCount ?? 0)
          ) + 1,
          lastBookingId: bookingRef.id,
          lastBookingAt: admin.firestore.Timestamp.fromDate(scheduledAtDate),
          lastUsedAt: admin.firestore.FieldValue.serverTimestamp(),
        }), {merge: true});
      }

      tx.set(idempotencyRef, {
        bookingId: bookingRef.id,
        paymentIntentId: paymentIntentRef.id,
        studentId,
        tutorId,
        requestType,
        scheduledAt: scheduledAtIso,
        tutorRatePerMinZar,
        studentRatePerMinZar,
        payerType,
        paymentMode: "tutoring_metered",
        paymentStatus: "authorization_pending",
        initialBufferAmount,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt,
      });

      return {
        bookingId: bookingRef.id,
        scheduledAt: scheduledAtIso,
        tutorRatePerMinZar,
        studentRatePerMinZar,
        requestType,
        payerType,
        paymentMode: "tutoring_metered",
        paymentStatus: "authorization_pending",
        initialBufferAmount,
        paymentIntentId: paymentIntentRef.id,
      };
    });
  }
);

export const createTutoringBooking = createTutoringBookingCallable;
export const createBooking = createTutoringBookingCallable;
