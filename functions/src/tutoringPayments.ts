import {randomUUID} from "node:crypto";
import * as admin from "firebase-admin";
import {HttpsError, onCall} from "./callable";
import {
  buildTutoringPaymentProviderStatus,
  buildProviderResponseSnapshot,
  MOCK_TUTORING_PROVIDER_NAME,
  TUTORING_PAYMENT_CURRENCY,
  TUTORING_PAYMENT_PROVIDER_REGION,
  type TutoringStoredPaymentMethod,
  type TutoringStoredPaymentMethodRecord,
  toMoney,
  toTrimmedString,
} from "./payments/tutoringPaymentProvider";
import {getTutoringPaymentProvider} from "./payments/mockTutoringPaymentProvider";
import {assertTutorEligibleForTutoring} from "./tutorApprovalState";
import {
  assertGuestTutoringCustomerPaymentReady,
  guestTutoringCustomerRef,
  isGuestTutoringBooking,
  touchGuestTutoringCustomer,
} from "./guestTutoring";
import {
  buildGuestTutoringCustomerDoc,
  buildPaymentAuthorizationSchemaFields,
} from "./tutoringFirestoreSchema";
import {
  assertBookingTransition,
  deriveTutoringBookingState,
  toTutoringHttpsErrorCode,
  TutoringBookingState,
  TutoringStateTransitionError,
  TutoringTransitionActor,
} from "./tutoringStateMachine";

const db = admin.firestore();

const PAYMENT_MODEL = "card_authorize_settlement";
const PAYMENT_AUTHORIZATION_PENDING = "PAYMENT_AUTHORIZATION_PENDING";
const PAYMENT_AUTHORIZED = "PAYMENT_AUTHORIZED";
const PAYMENT_AUTH_FAILED = "PAYMENT_AUTH_FAILED";
const AUTH_STATUS_INITIATING = "INITIATING";
const AUTH_STATUS_PENDING_PROVIDER = "PENDING_PROVIDER";
const AUTH_STATUS_AUTHORIZED = "AUTHORIZED";
const AUTH_STATUS_FAILED = "FAILED";
const AUTHORIZED_PROTECTED_MINUTES = 20;

interface SetupTutoringPaymentMethodResult {
  paymentMethodId: string;
  isTemporary: boolean;
  provider: string;
  adapterKey: string;
  providerFamily: string;
  setupMode: string;
  liveChargeEnabled: boolean;
  paymentMethodSummary: string;
  registrationId: string;
  providerReference: string;
}

interface StartTutoringPreauthResult {
  bookingId: string;
  authorizationId: string;
  paymentIntentId: string;
  status: string;
  amountZar: number;
  currency: string;
  provider: string;
  merchantTransactionId: string;
  providerPaymentId: string;
  ndc: string;
  resultCode: string;
  resultDescription: string;
  asyncReconciliationPending: boolean;
}

interface RespondToTutoringBookingResult {
  bookingId: string;
  action: "accept" | "decline";
  status: string;
  scheduledAt: string | null;
  paymentIntentId: string;
}

interface PreparedAuthorizationState {
  existingResult: StartTutoringPreauthResult | null;
  bookingId: string;
  paymentIntentId: string;
  authorizationId: string;
  amountZar: number;
  tutorId: string;
  guestTutoringMode: boolean;
  paymentMethod: TutoringStoredPaymentMethod | null;
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

function asPositiveMoney(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value) && value > 0) {
    return toMoney(value);
  }
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed) && parsed > 0) {
      return toMoney(parsed);
    }
  }
  return null;
}

function authorizationIdForBooking(bookingId: string): string {
  return `pa_${bookingId}_initial`;
}

function paymentMethodIdForSave(): string {
  return `pm_${Date.now()}_${randomUUID().slice(0, 8)}`;
}

async function setupTutoringPaymentMethodHandler(
  request: any
): Promise<SetupTutoringPaymentMethodResult> {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be logged in.");
  }

  const brand = toTrimmedString(request.data?.brand) || "Card";
  const holder = toTrimmedString(request.data?.holder) || "Student";
  const last4 = toTrimmedString(request.data?.last4);
  const expMonth = Number(request.data?.expMonth ?? 0);
  const expYear = Number(request.data?.expYear ?? 0);
  const isTemporary = request.data?.isTemporary === true;
  if (last4.length != 4) {
    throw new HttpsError("invalid-argument", "last4 must contain 4 digits.");
  }
  if (!expMonth || expMonth < 1 || expMonth > 12 || !expYear) {
    throw new HttpsError(
      "invalid-argument",
      "A valid expiry month and year are required."
    );
  }

  const provider = getTutoringPaymentProvider();
  const providerStatus = buildTutoringPaymentProviderStatus(provider);
  const studentRef = db.collection("users").doc(request.auth.uid);
  const guestRef = guestTutoringCustomerRef(request.auth.uid);
  const existingGuestSnap = isTemporary ? await guestRef.get() : null;
  const existingGuestData =
    (existingGuestSnap?.data() as Record<string, unknown> | undefined) ?? {};
  const paymentMethodId = paymentMethodIdForSave();
  const methodRecord: TutoringStoredPaymentMethodRecord =
    provider.buildStoredPaymentMethod({
      paymentMethodId,
      isTemporary,
      brand,
      holder,
      last4,
      expMonth,
      expYear,
    });
  const methodRef = studentRef
    .collection(methodRecord.collectionName)
    .doc(paymentMethodId);

  const batch = db.batch();
  batch.set(studentRef, methodRecord.rootFields, {merge: true});
  batch.set(methodRef, methodRecord.methodFields, {merge: true});
  if (isTemporary) {
    const guestMethodRef = guestRef
      .collection(methodRecord.collectionName)
      .doc(paymentMethodId);
    batch.set(
      guestRef,
      buildGuestTutoringCustomerDoc({
        customerId: request.auth.uid,
        userData: {
          ...existingGuestData,
          accountType: "instant_tutor",
          accessTier: "instant_tutor",
          temporaryPaymentProvider: methodRecord.method.provider,
          temporaryPaymentProviderFamily: providerStatus.providerFamily,
          temporaryPaymentAdapterKey: providerStatus.adapterKey,
          temporaryPaymentProviderMode: providerStatus.setupMode,
          temporaryPaymentLiveChargeEnabled: providerStatus.liveChargeEnabled,
          temporaryPaymentMethodId: paymentMethodId,
          temporaryPaymentRegistrationId: methodRecord.method.registrationId,
          temporaryPaymentProviderReference:
            methodRecord.method.providerReference,
          temporaryPaymentAuthorizationCode:
            methodRecord.method.mockAuthorizationCode,
          temporaryPaymentAuthorizationReference:
            methodRecord.method.mockAuthorizationReference,
          temporaryPaymentPreauthReference:
            methodRecord.method.mockPreauthReference,
          temporaryPaymentCustomerCode: methodRecord.method.mockCustomerCode,
          temporaryPaymentReusableAuthorizationCode:
            methodRecord.method.reusableAuthorizationCode,
          temporaryPaymentSetupStatus: methodRecord.method.status,
          temporaryCardBrand: methodRecord.method.brand,
          temporaryCardLast4: methodRecord.method.last4,
          temporaryCardExpMonth: methodRecord.method.expMonth,
          temporaryCardExpYear: methodRecord.method.expYear,
          temporaryCardHolder: methodRecord.method.holder,
          paystackCustomerCode: methodRecord.method.mockCustomerCode,
          reusableAuthorizationCode:
            methodRecord.method.reusableAuthorizationCode,
        },
        temporaryPaymentData: {
          ...existingGuestData,
          ...methodRecord.methodFields,
        },
        tutoringBookingCount: Math.max(
          0,
          Number(existingGuestData.tutoringBookingCount ?? 0)
        ),
        lastBookingId: toTrimmedString(existingGuestData.lastBookingId) || null,
        lastBookingAt: existingGuestData.lastBookingAt ?? null,
        lastUsedAt: admin.firestore.FieldValue.serverTimestamp(),
      }),
      {merge: true}
    );
    batch.set(guestMethodRef, methodRecord.methodFields, {merge: true});
  }
  await batch.commit();

  return {
    paymentMethodId,
    isTemporary,
    provider: methodRecord.method.provider,
    adapterKey: providerStatus.adapterKey,
    providerFamily: providerStatus.providerFamily,
    setupMode: providerStatus.setupMode,
    liveChargeEnabled: providerStatus.liveChargeEnabled,
    paymentMethodSummary: methodRecord.method.paymentMethodSummary,
    registrationId: methodRecord.method.registrationId,
    providerReference: methodRecord.method.providerReference,
  };
}

function readDate(input: unknown): Date | null {
  if (input instanceof admin.firestore.Timestamp) {
    return input.toDate();
  }
  if (input instanceof Date && !Number.isNaN(input.getTime())) {
    return input;
  }
  if (typeof input === "string" || typeof input === "number") {
    const parsed = new Date(input);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  return null;
}

function classifyAuthorizationResult(resultCode: string): "AUTHORIZED" | "PENDING_PROVIDER" | "FAILED" {
  if (/^000\.200\./.test(resultCode)) {
    return "PENDING_PROVIDER";
  }
  if (/^(000\.000\.|000\.100\.1|000\.[36])/.test(resultCode)) {
    return "AUTHORIZED";
  }
  return "FAILED";
}

function classifyReversalResult(resultCode: string): "REVERSED" | "PENDING_PROVIDER" | "FAILED" {
  const authorizationLike = classifyAuthorizationResult(resultCode);
  if (authorizationLike === "AUTHORIZED") return "REVERSED";
  if (authorizationLike === "PENDING_PROVIDER") return "PENDING_PROVIDER";
  return "FAILED";
}

function mapOutcomeToStoredStatus(outcome: "AUTHORIZED" | "PENDING_PROVIDER" | "FAILED"): string {
  switch (outcome) {
  case "AUTHORIZED":
    return AUTH_STATUS_AUTHORIZED;
  case "PENDING_PROVIDER":
    return AUTH_STATUS_PENDING_PROVIDER;
  case "FAILED":
    return AUTH_STATUS_FAILED;
  }
}

function buildFlutterAuthorizationResponse(
  bookingId: string,
  paymentIntentId: string,
  authData: Record<string, unknown>
): StartTutoringPreauthResult {
  const provider = (authData.provider ?? {}) as Record<string, unknown>;
  const status = toTrimmedString(authData.status);
  return {
    bookingId,
    authorizationId: toTrimmedString(authData.authorizationId),
    paymentIntentId,
    status,
    amountZar: asPositiveMoney(authData.amountZar) ?? 0,
    currency: toTrimmedString(authData.currency) || TUTORING_PAYMENT_CURRENCY,
    provider: toTrimmedString(provider.name) || MOCK_TUTORING_PROVIDER_NAME,
    merchantTransactionId: toTrimmedString(provider.merchantTransactionId),
    providerPaymentId: toTrimmedString(provider.paymentId),
    ndc: toTrimmedString(provider.ndc),
    resultCode: toTrimmedString(provider.resultCode),
    resultDescription: toTrimmedString(provider.resultDescription),
    asyncReconciliationPending:
      status === AUTH_STATUS_PENDING_PROVIDER || status === AUTH_STATUS_INITIATING,
  };
}

async function applyAuthorizationOutcome(params: {
  authorizationRef: admin.firestore.DocumentReference;
  bookingRef: admin.firestore.DocumentReference;
  paymentIntentRef: admin.firestore.DocumentReference;
  paymentMethod: TutoringStoredPaymentMethod;
  amountZar: number;
  outcome: "AUTHORIZED" | "PENDING_PROVIDER" | "FAILED";
  providerSnapshot: Record<string, unknown>;
}): Promise<Record<string, unknown>> {
  return db.runTransaction(async (tx) => {
    const [authSnap, bookingSnap, intentSnap] = await Promise.all([
      tx.get(params.authorizationRef),
      tx.get(params.bookingRef),
      tx.get(params.paymentIntentRef),
    ]);
    if (!authSnap.exists || !bookingSnap.exists || !intentSnap.exists) {
      throw new HttpsError(
        "not-found",
        "Authorization, booking, or payment intent is missing."
      );
    }

    const authData = authSnap.data() ?? {};
    const bookingData = bookingSnap.data() ?? {};
    const guestTutoringMode = isGuestTutoringBooking(
      bookingData as Record<string, unknown>
    );
    const storedStatus = mapOutcomeToStoredStatus(params.outcome);
    const nextBookingState = params.outcome === "AUTHORIZED" ?
      TutoringBookingState.PAYMENT_AUTHORIZED :
      TutoringBookingState.AWAITING_PAYMENT_AUTHORIZATION;
    assertBookingStateOrThrow({
      current: deriveTutoringBookingState(bookingData as Record<string, unknown>),
      next: nextBookingState,
      actor: TutoringTransitionActor.PAYMENT,
      isGuestSession: guestTutoringMode,
    });
    const providerData: Record<string, unknown> = {
      ...((authData.provider as Record<string, unknown> | undefined) ?? {}),
      name: params.paymentMethod.provider,
      providerReference: params.paymentMethod.providerReference,
      registrationId: params.paymentMethod.registrationId,
      mockCustomerCode: params.paymentMethod.mockCustomerCode,
      mockAuthorizationCode: params.paymentMethod.mockAuthorizationCode,
      mockAuthorizationReference: params.paymentMethod.mockAuthorizationReference,
      mockPreauthReference: params.paymentMethod.mockPreauthReference,
      reusableAuthorizationCode: params.paymentMethod.reusableAuthorizationCode,
      reusable: params.paymentMethod.reusable,
      ...params.providerSnapshot,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    const authorizationBase = {
      authorizationId: params.authorizationRef.id,
      status: storedStatus,
      amountZar: params.amountZar,
      amountCents: Math.round(params.amountZar * 100),
      currency: TUTORING_PAYMENT_CURRENCY,
      paymentModel: PAYMENT_MODEL,
      paymentMethodId: params.paymentMethod.paymentMethodId,
      paymentMethodType: params.paymentMethod.paymentMethodType,
      paymentMethodSummary: params.paymentMethod.paymentMethodSummary,
      provider: providerData,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(params.outcome === "AUTHORIZED" ? {
        authorizedAt: admin.firestore.FieldValue.serverTimestamp(),
        paymentAuthorizedAt: admin.firestore.FieldValue.serverTimestamp(),
      } : {}),
      ...(params.outcome === "FAILED" ? {
        failedAt: admin.firestore.FieldValue.serverTimestamp(),
      } : {}),
    };

    tx.set(params.authorizationRef, {
      ...authorizationBase,
      ...buildPaymentAuthorizationSchemaFields(
        params.authorizationRef.id,
        authorizationBase
      ),
    }, {merge: true});

    if (params.outcome === "AUTHORIZED") {
      tx.set(params.bookingRef, {
        bookingState: nextBookingState,
        paymentStatus: PAYMENT_AUTHORIZED,
        authorizationStatus: PAYMENT_AUTHORIZED,
        paymentAuthorizationId: params.authorizationRef.id,
        paymentAuthorizationProvider: params.paymentMethod.provider,
        paymentAuthorizationAmountZar: params.amountZar,
        protectedMinutesPurchased: AUTHORIZED_PROTECTED_MINUTES,
        protectedMinutesRemaining: AUTHORIZED_PROTECTED_MINUTES,
        consumedMinutes: 0,
        refillAttemptCount: 0,
        lowFundsAt: null,
        paymentAuthorizationMerchantTransactionId:
          toTrimmedString(providerData["merchantTransactionId"]),
        paymentAuthorizationProviderPaymentId:
          toTrimmedString(providerData["paymentId"]),
        noFreeLearningPastAuthorizedMinutes: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      tx.set(params.paymentIntentRef, {
        status: "session_authorized",
        holdStatus: "authorized",
        paymentAuthorizationStatus: PAYMENT_AUTHORIZED,
        paymentAuthorizationId: params.authorizationRef.id,
        holdAmountZar: params.amountZar,
        holdRemainingZar: params.amountZar,
        paymentModel: PAYMENT_MODEL,
        paymentMethodType: params.paymentMethod.paymentMethodType,
        paymentMethodStatus: "authorized",
        paymentMethodSummary: params.paymentMethod.paymentMethodSummary,
        authorizationProvider: params.paymentMethod.provider,
        authorizationMerchantTransactionId:
          toTrimmedString(providerData["merchantTransactionId"]),
        authorizationProviderPaymentId:
          toTrimmedString(providerData["paymentId"]),
        protectedTutoringMinutesOnly: true,
        protectedMinutesPurchased: AUTHORIZED_PROTECTED_MINUTES,
        protectedMinutesRemaining: AUTHORIZED_PROTECTED_MINUTES,
        consumedMinutes: 0,
        refillAttemptCount: 0,
        lowFundsAt: null,
        holdAuthorizedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    } else if (params.outcome === "FAILED") {
      tx.set(params.bookingRef, {
        bookingState: nextBookingState,
        paymentStatus: PAYMENT_AUTH_FAILED,
        authorizationStatus: PAYMENT_AUTH_FAILED,
        paymentFailureReason:
          toTrimmedString(providerData["resultDescription"]) ||
          "authorization_failed",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      tx.set(params.paymentIntentRef, {
        status: "hold_failed",
        holdStatus: "failed",
        settlementStatus: "blocked",
        paymentAuthorizationStatus: PAYMENT_AUTH_FAILED,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    } else {
      tx.set(params.bookingRef, {
        bookingState: nextBookingState,
        paymentStatus: PAYMENT_AUTHORIZATION_PENDING,
        authorizationStatus: PAYMENT_AUTHORIZATION_PENDING,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      tx.set(params.paymentIntentRef, {
        paymentAuthorizationStatus: PAYMENT_AUTHORIZATION_PENDING,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    }

    return {
      ...authData,
      authorizationId: params.authorizationRef.id,
      status: storedStatus,
      amountZar: params.amountZar,
      currency: TUTORING_PAYMENT_CURRENCY,
      provider: providerData,
    };
  });
}

async function releaseDeclinedAuthorization(params: {
  bookingId: string;
  paymentIntentId: string;
  authorizationId: string;
}): Promise<void> {
  const authorizationRef = db.collection("payment_authorizations").doc(params.authorizationId);
  const bookingRef = db.collection("tutor_requests").doc(params.bookingId);
  const paymentIntentRef = db.collection("session_payment_intents").doc(params.paymentIntentId);
  const authorizationSnap = await authorizationRef.get();
  if (!authorizationSnap.exists) return;

  const authorizationData = authorizationSnap.data() ?? {};
  const provider = getTutoringPaymentProvider();
  const amountZar = toMoney(Math.max(
    0,
    Number(authorizationData.amountZar ?? 0) -
      Number(authorizationData.capturedAmountZar ?? 0) -
      Number(authorizationData.pendingCaptureAmountZar ?? 0) -
      Number(authorizationData.reversedAmountZar ?? 0) -
      Number(authorizationData.pendingReversalAmountZar ?? 0)
  ));
  if (amountZar <= 0) return;

  const providerPaymentId = toTrimmedString(
    (((authorizationData.provider as Record<string, unknown> | undefined) ?? {})[
      "paymentId"
    ])
  );
  const reversalId = `rv_decline_${params.authorizationId}`;
  const providerResult = await provider.reverse({
    authorizationId: params.authorizationId,
    bookingId: params.bookingId,
    paymentIntentId: params.paymentIntentId,
    sessionId: params.bookingId,
    amountZar,
    currency: TUTORING_PAYMENT_CURRENCY,
    merchantTransactionId: reversalId,
    authorizationProviderPaymentId: providerPaymentId,
  });
  const snapshot = buildProviderResponseSnapshot(providerResult, reversalId);
  const outcome = classifyReversalResult(toTrimmedString(snapshot.resultCode));
  const reversalRef = db.collection("payment_reversals").doc(reversalId);
  const accountedAmountZar = outcome === "FAILED" ? 0 : amountZar;

  await db.runTransaction(async (tx) => {
    tx.set(reversalRef, {
      reversalId,
      tutoringPaymentRail: "TUTORING",
      authorizationId: params.authorizationId,
      bookingId: params.bookingId,
      paymentIntentId: params.paymentIntentId,
      sessionId: params.bookingId,
      amountZar,
      accountedAmountZar,
      amountCents: Math.round(amountZar * 100),
      currency: TUTORING_PAYMENT_CURRENCY,
      status: outcome,
      provider: snapshot,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    tx.set(authorizationRef, {
      reversedAmountZar: admin.firestore.FieldValue.increment(
        outcome === "REVERSED" ? amountZar : 0
      ),
      pendingReversalAmountZar: admin.firestore.FieldValue.increment(
        outcome === "PENDING_PROVIDER" ? amountZar : 0
      ),
      lastReversalId: reversalId,
      lastReversalStatus: outcome,
      lastReversalAmountZar: amountZar,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    tx.set(bookingRef, {
      releasedAmountZar: admin.firestore.FieldValue.increment(
        outcome === "REVERSED" ? amountZar : 0
      ),
      pendingReleasedAmountZar: admin.firestore.FieldValue.increment(
        outcome === "PENDING_PROVIDER" ? amountZar : 0
      ),
      paymentAuthorizationReleaseStatus: outcome,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    tx.set(paymentIntentRef, {
      releasedAmountZar: admin.firestore.FieldValue.increment(
        outcome === "REVERSED" ? amountZar : 0
      ),
      pendingReleasedAmountZar: admin.firestore.FieldValue.increment(
        outcome === "PENDING_PROVIDER" ? amountZar : 0
      ),
      holdStatus: outcome === "FAILED" ? "release_failed" : "released",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  });
}

export const setupTutoringPaymentMethod = onCall(
  {region: TUTORING_PAYMENT_PROVIDER_REGION},
  async (request): Promise<SetupTutoringPaymentMethodResult> =>
    setupTutoringPaymentMethodHandler(request)
);

export const saveMockTutoringPaymentMethod = onCall(
  {region: TUTORING_PAYMENT_PROVIDER_REGION},
  async (request): Promise<SetupTutoringPaymentMethodResult> =>
    setupTutoringPaymentMethodHandler(request)
);

export const startTutoringPreauth = onCall(
  {region: TUTORING_PAYMENT_PROVIDER_REGION},
  async (request): Promise<StartTutoringPreauthResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }

    const bookingId = toTrimmedString(request.data?.bookingId);
    if (!bookingId) {
      throw new HttpsError("invalid-argument", "bookingId is required.");
    }

    const provider = getTutoringPaymentProvider();
    const studentId = request.auth.uid;
    const bookingRef = db.collection("tutor_requests").doc(bookingId);
    const authorizationId = authorizationIdForBooking(bookingId);
    const authorizationRef = db.collection("payment_authorizations").doc(authorizationId);

    const prepared = await db.runTransaction<PreparedAuthorizationState>(async (tx) => {
      const bookingSnap = await tx.get(bookingRef);
      if (!bookingSnap.exists) {
        throw new HttpsError("not-found", "Booking not found.");
      }
      const bookingData = bookingSnap.data() ?? {};
      if (toTrimmedString(bookingData.studentId) !== studentId) {
        throw new HttpsError(
          "permission-denied",
          "This booking does not belong to the current student."
        );
      }
      const guestTutoringMode = isGuestTutoringBooking(
        bookingData as Record<string, unknown>
      );

      const paymentIntentId =
        toTrimmedString(bookingData.paymentIntentId) || bookingId;
      const paymentIntentRef = db.collection("session_payment_intents").doc(paymentIntentId);
      const [authorizationSnap, paymentIntentSnap] = await Promise.all([
        tx.get(authorizationRef),
        tx.get(paymentIntentRef),
      ]);
      if (!paymentIntentSnap.exists) {
        throw new HttpsError(
          "failed-precondition",
          "Booking payment intent is missing."
        );
      }

      const amountZar = asPositiveMoney(
        bookingData.initialBufferAmountZar ??
          bookingData.holdAmountZar ??
          paymentIntentSnap.data()?.holdAmountZar
      );
      if (!amountZar) {
        throw new HttpsError(
          "failed-precondition",
          "Booking is missing an authorization buffer amount."
        );
      }

      if (authorizationSnap.exists) {
        const authData = authorizationSnap.data() ?? {};
        const status = toTrimmedString(authData.status);
        if ([
          AUTH_STATUS_AUTHORIZED,
          AUTH_STATUS_PENDING_PROVIDER,
          AUTH_STATUS_INITIATING,
        ].includes(status)) {
          return {
            existingResult: buildFlutterAuthorizationResponse(
              bookingId,
              paymentIntentId,
              {
                authorizationId,
                amountZar,
                currency: TUTORING_PAYMENT_CURRENCY,
                ...authData,
              }
            ),
            bookingId,
            paymentIntentId,
            authorizationId,
            amountZar,
            tutorId: toTrimmedString(bookingData.tutorId),
            guestTutoringMode,
            paymentMethod: null,
          };
        }
      }

      const paymentMethodOwnerRef = guestTutoringMode ?
        guestTutoringCustomerRef(studentId) :
        db.collection("users").doc(studentId);
      if (guestTutoringMode) {
        const guestCustomerSnap = await tx.get(paymentMethodOwnerRef);
        if (!guestCustomerSnap.exists) {
          throw new HttpsError(
            "failed-precondition",
            "Guest tutoring profile is missing for this booking."
          );
        }
        assertGuestTutoringCustomerPaymentReady(
          guestCustomerSnap.data() as Record<string, unknown>,
          studentId
        );
      }
      const paymentMethod = await provider.readStoredPaymentMethod(
        tx,
        paymentMethodOwnerRef
      );
      assertBookingStateOrThrow({
        current: deriveTutoringBookingState(bookingData as Record<string, unknown>),
        next: TutoringBookingState.AWAITING_PAYMENT_AUTHORIZATION,
        actor: TutoringTransitionActor.STUDENT,
        isGuestSession: guestTutoringMode,
      });
      const authorizationBase = {
        authorizationId,
        bookingId,
        paymentIntentId,
        studentId,
        tutorId: toTrimmedString(bookingData.tutorId),
        provider: {
          name: provider.providerName,
          adapterKey: provider.adapterKey,
          providerReference: paymentMethod.providerReference,
          registrationId: paymentMethod.registrationId,
          mockCustomerCode: paymentMethod.mockCustomerCode,
          mockAuthorizationCode: paymentMethod.mockAuthorizationCode,
          mockAuthorizationReference: paymentMethod.mockAuthorizationReference,
          mockPreauthReference: paymentMethod.mockPreauthReference,
          reusableAuthorizationCode: paymentMethod.reusableAuthorizationCode,
          reusable: paymentMethod.reusable,
          merchantTransactionId: authorizationId,
        },
        amountZar,
        amountCents: Math.round(amountZar * 100),
        currency: TUTORING_PAYMENT_CURRENCY,
        status: AUTH_STATUS_INITIATING,
        type: "PREAUTH",
        paymentModel: PAYMENT_MODEL,
        paymentMethodId: paymentMethod.paymentMethodId,
        paymentMethodType: paymentMethod.paymentMethodType,
        paymentMethodSummary: paymentMethod.paymentMethodSummary,
        tutoringPaymentRail: "TUTORING",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      tx.set(authorizationRef, {
        ...authorizationBase,
        ...buildPaymentAuthorizationSchemaFields(authorizationId, authorizationBase),
      }, {merge: true});

      tx.set(bookingRef, {
        bookingState: TutoringBookingState.AWAITING_PAYMENT_AUTHORIZATION,
        paymentAuthorizationId: authorizationId,
        paymentStatus: PAYMENT_AUTHORIZATION_PENDING,
        authorizationStatus: PAYMENT_AUTHORIZATION_PENDING,
        paymentAuthorizationProvider: provider.providerName,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      tx.set(paymentIntentRef, {
        paymentAuthorizationId: authorizationId,
        paymentAuthorizationStatus: PAYMENT_AUTHORIZATION_PENDING,
        paymentModel: PAYMENT_MODEL,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      return {
        existingResult: null,
        bookingId,
        paymentIntentId,
        authorizationId,
        amountZar,
        tutorId: toTrimmedString(bookingData.tutorId),
        guestTutoringMode,
        paymentMethod,
      };
    });

    if (prepared.existingResult) {
      if (prepared.guestTutoringMode) {
        await touchGuestTutoringCustomer(studentId, {
          lastBookingId: bookingId,
          lastAuthorizationId: prepared.authorizationId,
        });
      }
      return prepared.existingResult;
    }
    if (!prepared.paymentMethod) {
      throw new HttpsError(
        "failed-precondition",
        "Tutoring payment method was not available for authorization."
      );
    }

    const paymentIntentRef = db
      .collection("session_payment_intents")
      .doc(prepared.paymentIntentId);
    const providerResult = await provider.authorizeInitial({
      authorizationId: prepared.authorizationId,
      bookingId,
      paymentIntentId: prepared.paymentIntentId,
      sessionId: bookingId,
      studentId,
      tutorId: prepared.tutorId,
      amountZar: prepared.amountZar,
      currency: TUTORING_PAYMENT_CURRENCY,
      merchantTransactionId: prepared.authorizationId,
      paymentMethod: prepared.paymentMethod,
    });
    const providerSnapshot = buildProviderResponseSnapshot(
      providerResult,
      prepared.authorizationId
    );
    const outcome = classifyAuthorizationResult(
      toTrimmedString(providerSnapshot.resultCode)
    );
    const authData = await applyAuthorizationOutcome({
      authorizationRef,
      bookingRef,
      paymentIntentRef,
      paymentMethod: prepared.paymentMethod,
      amountZar: prepared.amountZar,
      outcome,
      providerSnapshot,
    });
    if (prepared.guestTutoringMode) {
      await touchGuestTutoringCustomer(studentId, {
        lastBookingId: bookingId,
        lastAuthorizationId: prepared.authorizationId,
        paystackCustomerCode:
          prepared.paymentMethod.mockCustomerCode || null,
        reusableAuthorizationCode:
          prepared.paymentMethod.reusableAuthorizationCode || null,
      });
    }

    return buildFlutterAuthorizationResponse(
      bookingId,
      prepared.paymentIntentId,
      {
        authorizationId: prepared.authorizationId,
        amountZar: prepared.amountZar,
        currency: TUTORING_PAYMENT_CURRENCY,
        ...authData,
      }
    );
  }
);

export const respondToTutoringBooking = onCall(
  {region: TUTORING_PAYMENT_PROVIDER_REGION},
  async (request): Promise<RespondToTutoringBookingResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }

    const bookingId = toTrimmedString(request.data?.bookingId);
    const action = toTrimmedString(request.data?.action).toLowerCase();
    if (!bookingId || !["accept", "decline"].includes(action)) {
      throw new HttpsError(
        "invalid-argument",
        "bookingId and a valid action are required."
      );
    }

    const bookingRef = db.collection("tutor_requests").doc(bookingId);
    const callerUid = request.auth.uid;
    const scheduledAtInput = request.data?.scheduledAt;

    const result = await db.runTransaction(async (tx) => {
      const bookingSnap = await tx.get(bookingRef);
      if (!bookingSnap.exists) {
        throw new HttpsError("not-found", "Booking not found.");
      }
      const bookingData = bookingSnap.data() ?? {};
      const tutorId = toTrimmedString(bookingData.tutorId);
      const studentId = toTrimmedString(bookingData.studentId);
      if (callerUid !== tutorId) {
        throw new HttpsError(
          "permission-denied",
          "Only the tutor for this booking can respond."
        );
      }

      const tutorRef = db.collection("users").doc(tutorId);
      const tutorSnap = await tx.get(tutorRef);
      if (!tutorSnap.exists) {
        throw new HttpsError("not-found", "Tutor not found.");
      }
      assertTutorEligibleForTutoring(
        tutorSnap.data() as Record<string, unknown>,
        tutorId
      );

      const paymentIntentId =
        toTrimmedString(bookingData.paymentIntentId) || bookingId;
      const paymentIntentRef = db.collection("session_payment_intents").doc(paymentIntentId);
      const paymentIntentSnap = await tx.get(paymentIntentRef);
      if (!paymentIntentSnap.exists) {
        throw new HttpsError(
          "failed-precondition",
          "Booking payment intent is missing."
        );
      }
      const paymentIntentData = paymentIntentSnap.data() ?? {};
      const authorizationId =
        toTrimmedString(bookingData.paymentAuthorizationId) ||
        toTrimmedString(paymentIntentData.paymentAuthorizationId);
      const authorizationRef = authorizationId ?
        db.collection("payment_authorizations").doc(authorizationId) :
        null;
      const authorizationSnap = authorizationRef ?
        await tx.get(authorizationRef) :
        null;
      const authorizationStatus = toTrimmedString(
        authorizationSnap?.data()?.status || paymentIntentData.paymentAuthorizationStatus
      );
      const currentBookingState = deriveTutoringBookingState(
        bookingData as Record<string, unknown>
      );

      if (action === "accept") {
        if (authorizationStatus !== AUTH_STATUS_AUTHORIZED) {
          throw new HttpsError(
            "failed-precondition",
            "Tutoring booking must be preauthorized before the tutor accepts."
          );
        }
        assertBookingStateOrThrow({
          current: currentBookingState,
          next: TutoringBookingState.CONFIRMED,
          actor: TutoringTransitionActor.TUTOR,
          isGuestSession: isGuestTutoringBooking(
            bookingData as Record<string, unknown>
          ),
        });

        const scheduledAt =
          readDate(scheduledAtInput) ||
          readDate(bookingData.scheduledAt) ||
          new Date();
        tx.set(bookingRef, {
          bookingState: TutoringBookingState.CONFIRMED,
          status: "accepted",
          sessionState: "approved",
          scheduledAt: admin.firestore.Timestamp.fromDate(scheduledAt),
          acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
          acceptedByTutorId: tutorId,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
        tx.set(paymentIntentRef, {
          status: "ready_for_session",
          studentId,
          tutorId,
          scheduledAt: admin.firestore.Timestamp.fromDate(scheduledAt),
          paymentAuthorizationStatus: PAYMENT_AUTHORIZED,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
        tx.set(tutorRef, {
          tutorRequestsEnabled: true,
          tutorAvailability: "accepting",
        }, {merge: true});

        return {
          bookingId,
          action: "accept" as const,
          status: "accepted",
          scheduledAt: scheduledAt.toISOString(),
          paymentIntentId,
          authorizationId,
        };
      }

      assertBookingStateOrThrow({
        current: currentBookingState,
        next: TutoringBookingState.CANCELLED,
        actor: TutoringTransitionActor.TUTOR,
        isGuestSession: isGuestTutoringBooking(
          bookingData as Record<string, unknown>
        ),
        reason: "cancel",
      });
      tx.set(bookingRef, {
        bookingState: TutoringBookingState.CANCELLED,
        status: "declined",
        sessionState: "declined",
        declinedAt: admin.firestore.FieldValue.serverTimestamp(),
        declinedByTutorId: tutorId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      tx.set(paymentIntentRef, {
        status: "booking_declined",
        settlementStatus: "cancelled",
        holdStatus: authorizationStatus === AUTH_STATUS_AUTHORIZED ?
          "releasing" :
          "cancelled",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      return {
        bookingId,
        action: "decline" as const,
        status: "declined",
        scheduledAt: null,
        paymentIntentId,
        authorizationId,
      };
    });

    if (result.action === "decline" && result.authorizationId) {
      await releaseDeclinedAuthorization({
        bookingId,
        paymentIntentId: result.paymentIntentId,
        authorizationId: result.authorizationId,
      });
    }

    return {
      bookingId,
      action: result.action,
      status: result.status,
      scheduledAt: result.scheduledAt,
      paymentIntentId: result.paymentIntentId,
    };
  }
);
