import {createHash} from "node:crypto";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {
  type BuildStoredPaymentMethodParams,
  type TutoringAuthorizationParams,
  type TutoringCaptureParams,
  type TutoringPaymentProvider,
  type TutoringProviderLikeResult,
  type TutoringReversalParams,
  type TutoringStoredPaymentMethod,
  type TutoringStoredPaymentMethodRecord,
  toTrimmedString,
} from "./tutoringPaymentProvider";
import {
  assertIdempotencyKey,
} from "./provider";
import {getPaystackProvider} from "./paystack";

const PROVIDER_NAME = "PAYSTACK";
const ADAPTER_KEY = "paystack";
const PROVIDER_FAMILY: "paystack" = "paystack";
const SETUP_MODE: "live_pending" | "test" | "live" = "live_pending";
const LIVE_CHARGE_ENABLED = true;

function stableId(prefix: string, material: string): string {
  const digest = createHash("sha256").update(material).digest("hex").slice(0, 24);
  return `${prefix}_${digest}`;
}

function nowIsoString(): string {
  return new Date().toISOString();
}

function methodBasis(params: BuildStoredPaymentMethodParams): string {
  return [
    params.paymentMethodId,
    params.brand,
    params.last4,
    params.holder,
    params.expMonth,
    params.expYear,
    params.isTemporary ? "temporary" : "default",
  ].join("|");
}

const paystackTutoringProvider: TutoringPaymentProvider = {
  providerName: PROVIDER_NAME,
  adapterKey: ADAPTER_KEY,
  providerFamily: PROVIDER_FAMILY,
  setupMode: SETUP_MODE,
  liveChargeEnabled: LIVE_CHARGE_ENABLED,

  buildStoredPaymentMethod(
    params: BuildStoredPaymentMethodParams
  ): TutoringStoredPaymentMethodRecord {
    const basis = methodBasis(params);
    const prefix = params.isTemporary ? "temporary" : "billing";

    const method: TutoringStoredPaymentMethod = {
      paymentMethodId: params.paymentMethodId,
      paymentMethodType: "card_reusable_authorization",
      paymentMethodSummary: `${params.brand} •••• ${params.last4}`,
      registrationId: stableId("auth", basis),
      providerReference: stableId("ref", basis),
      provider: PROVIDER_NAME,
      isTemporary: params.isTemporary,
      brand: params.brand,
      last4: params.last4,
      holder: params.holder,
      expMonth: params.expMonth,
      expYear: params.expYear,
      mockCustomerCode: "",
      mockAuthorizationCode: "",
      mockAuthorizationReference: "",
      mockPreauthReference: "",
      reusableAuthorizationCode: stableId("authcode", basis),
      reusable: true,
      status: "ready",
    };

    const methodFields: Record<string, unknown> = {
      [`${prefix}PaymentMethodId`]: method.paymentMethodId,
      [`${prefix}CardBrand`]: method.brand,
      [`${prefix}CardLast4`]: method.last4,
      [`${prefix}CardHolder`]: method.holder,
      [`${prefix}CardExpMonth`]: method.expMonth,
      [`${prefix}CardExpYear`]: method.expYear,
      [`${prefix}PaymentProvider`]: PROVIDER_NAME,
      [`${prefix}PaymentRegistrationId`]: method.registrationId,
      [`${prefix}PaymentProviderReference`]: method.providerReference,
      [`${prefix}PaymentAuthorizationCode`]: method.reusableAuthorizationCode,
      [`${prefix}PaymentSetupStatus`]: "ready",
      [`${prefix}PaymentUpdatedAt`]: nowIsoString(),
    };

    const rootFields: Record<string, unknown> = {
      [`${prefix}DefaultPaymentMethodId`]: method.paymentMethodId,
    };

    return {
      collectionName: `users`,
      method,
      rootFields,
      methodFields,
    };
  },

  async readStoredPaymentMethod(
    tx: admin.firestore.Transaction,
    studentRef: admin.firestore.DocumentReference
  ): Promise<TutoringStoredPaymentMethod> {
    const snapshot = await tx.get(studentRef);
    const data = snapshot.data() || {};

    const isTemporary = true;
    const prefix = isTemporary ? "temporary" : "billing";

    const paymentMethodId = toTrimmedString(
      data[`${prefix}PaymentMethodId`] ||
        data[`${prefix}DefaultPaymentMethodId`]
    );
    const brand = toTrimmedString(data[`${prefix}CardBrand`] || "Card");
    const last4 = toTrimmedString(data[`${prefix}CardLast4`]);
    const holder = toTrimmedString(data[`${prefix}CardHolder`] || "Student");
    const expMonth = Number(data[`${prefix}CardExpMonth`] || 0);
    const expYear = Number(data[`${prefix}CardExpYear`] || 0);

    return {
      paymentMethodId,
      paymentMethodType: "card_reusable_authorization",
      paymentMethodSummary: `${brand} •••• ${last4}`,
      registrationId: toTrimmedString(
        data[`${prefix}PaymentRegistrationId`]
      ),
      providerReference: toTrimmedString(
        data[`${prefix}PaymentProviderReference`]
      ),
      provider: PROVIDER_NAME,
      isTemporary,
      brand,
      last4,
      holder,
      expMonth,
      expYear,
      mockCustomerCode: "",
      mockAuthorizationCode: "",
      mockAuthorizationReference: "",
      mockPreauthReference: "",
      reusableAuthorizationCode: toTrimmedString(
        data[`${prefix}PaymentAuthorizationCode`]
      ),
      reusable: true,
      status: toTrimmedString(data[`${prefix}PaymentSetupStatus`] || "ready"),
    };
  },

  async authorizeInitial(
    params: TutoringAuthorizationParams
  ): Promise<TutoringProviderLikeResult> {
    assertIdempotencyKey(params.merchantTransactionId);

    try {
      const provider = getPaystackProvider();
      const result = await provider.initializeFirstPreauth({
        idempotencyKey: params.merchantTransactionId,
        bookingId: params.bookingId,
        paymentSessionId: params.paymentIntentId,
        sessionId: params.sessionId,
        customerEmail: params.studentId,
        amountZar: params.amountZar,
        currency: params.currency,
        reason: "tutoring_initial_authorization",
      });

      logger.info("paystack_tutoring_authorize_initial", {
        bookingId: params.bookingId,
        success: result.success,
        reference: result.reference,
      });

      return {
        id: result.reference,
        registrationId: result.authorizationCode,
        providerReference: result.authorizationReference,
        preauthReference: result.preauthReference,
        timestamp: result.loggedAt,
        result: {
          code: result.success ? "000.100.110" : "100.400.500",
          description: result.message,
        },
      };
    } catch (error) {
      logger.error("paystack_tutoring_authorize_initial_error", {
        bookingId: params.bookingId,
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  },

  async authorizeReserve(
    params: TutoringAuthorizationParams
  ): Promise<TutoringProviderLikeResult> {
    assertIdempotencyKey(params.merchantTransactionId);

    try {
      const provider = getPaystackProvider();
      const result = await provider.reservePreauth({
        idempotencyKey: params.merchantTransactionId,
        bookingId: params.bookingId,
        paymentSessionId: params.paymentIntentId,
        sessionId: params.sessionId,
        authorizationCode: params.paymentMethod.reusableAuthorizationCode,
        authorizationReference: params.paymentMethod.providerReference,
        customerCode: params.studentId,
        amountZar: params.amountZar,
        currency: params.currency,
        reason: "tutoring_reserve",
      });

      logger.info("paystack_tutoring_authorize_reserve", {
        bookingId: params.bookingId,
        success: result.success,
        reference: result.reference,
      });

      return {
        id: result.reference,
        registrationId: result.authorizationCode,
        providerReference: result.authorizationReference,
        preauthReference: result.preauthReference,
        timestamp: result.loggedAt,
        result: {
          code: result.success ? "000.100.110" : "100.400.500",
          description: result.message,
        },
      };
    } catch (error) {
      logger.error("paystack_tutoring_authorize_reserve_error", {
        bookingId: params.bookingId,
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  },

  async capture(
    params: TutoringCaptureParams
  ): Promise<TutoringProviderLikeResult> {
    assertIdempotencyKey(params.merchantTransactionId);

    try {
      const provider = getPaystackProvider();
      const result = await provider.capturePreauth({
        idempotencyKey: params.merchantTransactionId,
        bookingId: params.bookingId,
        paymentSessionId: params.paymentIntentId,
        sessionId: params.sessionId,
        authorizationReference: params.authorizationProviderPaymentId,
        amountZar: params.amountZar,
        currency: params.currency,
      });

      logger.info("paystack_tutoring_capture", {
        bookingId: params.bookingId,
        success: result.success,
        reference: result.reference,
      });

      return {
        id: result.reference,
        registrationId: result.authorizationReference,
        referencedId: result.captureReference,
        timestamp: result.loggedAt,
        result: {
          code: result.success ? "000.100.110" : "100.400.500",
          description: result.message,
        },
      };
    } catch (error) {
      logger.error("paystack_tutoring_capture_error", {
        bookingId: params.bookingId,
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  },

  async reverse(
    params: TutoringReversalParams
  ): Promise<TutoringProviderLikeResult> {
    assertIdempotencyKey(params.merchantTransactionId);

    try {
      const provider = getPaystackProvider();
      const result = await provider.releasePreauth({
        idempotencyKey: params.merchantTransactionId,
        bookingId: params.bookingId,
        paymentSessionId: params.paymentIntentId,
        sessionId: params.sessionId,
        authorizationReference: params.authorizationProviderPaymentId,
        amountZar: params.amountZar,
        currency: params.currency,
      });

      logger.info("paystack_tutoring_reverse", {
        bookingId: params.bookingId,
        success: result.success,
        reference: result.reference,
      });

      return {
        id: result.reference,
        registrationId: result.authorizationReference,
        referencedId: result.releaseReference,
        timestamp: result.loggedAt,
        result: {
          code: result.success ? "000.100.110" : "100.400.500",
          description: result.message,
        },
      };
    } catch (error) {
      logger.error("paystack_tutoring_reverse_error", {
        bookingId: params.bookingId,
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  },
};

export function getPaystackTutoringProvider(): TutoringPaymentProvider {
  return paystackTutoringProvider;
}
