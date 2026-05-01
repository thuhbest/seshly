import {createHash} from "node:crypto";
import {HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import {getPaystackTutoringProvider} from "./paystackTutoringProvider";
import {
  type BuildStoredPaymentMethodParams,
  type TutoringAuthorizationParams,
  type TutoringCaptureParams,
  type TutoringPaymentProvider,
  type TutoringProviderLikeResult,
  type TutoringReversalParams,
  type TutoringStoredPaymentMethod,
  type TutoringStoredPaymentMethodRecord,
  MOCK_AUTHORIZED_RESULT_CODE,
  MOCK_TUTORING_PROVIDER_NAME,
  paymentMethodCollectionName,
  paymentMethodSummary,
  isInstantTutorModeUser,
  toTrimmedString,
} from "./tutoringPaymentProvider";

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

function buildMethodFromSource(params: {
  isTemporary: boolean;
  rootData: Record<string, unknown>;
  methodData: Record<string, unknown>;
}): TutoringStoredPaymentMethod {
  const methodData = params.methodData;
  const rootData = params.rootData;
  const prefix = params.isTemporary ? "temporary" : "billing";
  const paymentMethodId = toTrimmedString(
    methodData.paymentMethodId || rootData[`${prefix}PaymentMethodId`] ||
      rootData[`${prefix}DefaultPaymentMethodId`]
  );
  const registrationId = toTrimmedString(
    methodData.registrationId ||
      rootData[`${prefix}PaymentRegistrationId`] ||
      rootData[`${prefix}RegistrationId`] ||
      methodData.providerReference
  );
  const providerReference = toTrimmedString(
    methodData.providerReference ||
      rootData[`${prefix}PaymentProviderReference`] ||
      rootData[`${prefix}ProviderReference`] ||
      registrationId
  );
  const brand = toTrimmedString(
    methodData.brand || rootData[`${prefix}CardBrand`] || "Card"
  );
  const last4 = toTrimmedString(
    methodData.last4 || rootData[`${prefix}CardLast4`]
  );
  const holder = toTrimmedString(
    methodData.holder || rootData[`${prefix}CardHolder`] || "Student"
  );
  const expMonth = Number(
    methodData.expMonth || rootData[`${prefix}CardExpMonth`] || 0
  );
  const expYear = Number(
    methodData.expYear || rootData[`${prefix}CardExpYear`] || 0
  );
  const mockCustomerCode = toTrimmedString(
    methodData.mockCustomerCode ||
      rootData[`${prefix}PaymentCustomerCode`] ||
      rootData[`${prefix}CustomerCode`]
  );
  const mockAuthorizationCode = toTrimmedString(
    methodData.mockAuthorizationCode ||
      rootData[`${prefix}PaymentAuthorizationCode`] ||
      rootData[`${prefix}AuthorizationCode`]
  );
  const mockAuthorizationReference = toTrimmedString(
    methodData.mockAuthorizationReference ||
      rootData[`${prefix}PaymentAuthorizationReference`] ||
      rootData[`${prefix}AuthorizationReference`]
  );
  const mockPreauthReference = toTrimmedString(
    methodData.mockPreauthReference ||
      rootData[`${prefix}PaymentPreauthReference`] ||
      rootData[`${prefix}PreauthReference`]
  );
  const reusableAuthorizationCode = toTrimmedString(
    methodData.reusableAuthorizationCode ||
      rootData[`${prefix}PaymentReusableAuthorizationCode`] ||
      rootData[`${prefix}ReusableAuthorizationCode`] ||
      mockAuthorizationCode
  );
  const provider = toTrimmedString(
    methodData.provider || rootData[`${prefix}PaymentProvider`] ||
      rootData[`${prefix}Provider`] || MOCK_TUTORING_PROVIDER_NAME
  );
  const status = toTrimmedString(
    methodData.status ||
      rootData[`${prefix}PaymentStatus`] ||
      rootData[`${prefix}Status`] ||
      "ready"
  );
  if (!paymentMethodId) {
    throw new HttpsError(
      "failed-precondition",
      "No tutoring payment method is attached to this student."
    );
  }
  if (!registrationId) {
    throw new HttpsError(
      "failed-precondition",
      "No mock tutoring registration reference is attached to this payment method."
    );
  }

  return {
    paymentMethodId,
    paymentMethodType: toTrimmedString(methodData.type || "card"),
    paymentMethodSummary: paymentMethodSummary(brand, last4),
    registrationId,
    providerReference,
    provider,
    isTemporary: params.isTemporary,
    brand,
    last4,
    holder,
    expMonth,
    expYear,
    mockCustomerCode,
    mockAuthorizationCode,
    mockAuthorizationReference,
    mockPreauthReference,
    reusableAuthorizationCode,
    reusable: methodData.reusable !== false,
    status: status || "ready",
  };
}

function buildProviderResult(params: {
  operation: string;
  operationId: string;
  merchantTransactionId: string;
  registrationId: string;
  referencedId?: string;
  description: string;
}): TutoringProviderLikeResult {
  return {
    id: stableId(`mock_${params.operation}`, params.operationId),
    ndc: stableId("mock_ndc", params.operationId),
    registrationId: params.registrationId,
    merchantTransactionId: params.merchantTransactionId,
    referencedId: params.referencedId ?? "",
    timestamp: nowIsoString(),
    result: {
      code: MOCK_AUTHORIZED_RESULT_CODE,
      description: params.description,
    },
  };
}

export const mockTutoringPaymentProvider: TutoringPaymentProvider = {
  providerName: MOCK_TUTORING_PROVIDER_NAME,
  adapterKey: "mock_tutoring_payment_provider",
  providerFamily: "paystack",
  setupMode: "test",
  liveChargeEnabled: false,

  buildStoredPaymentMethod(
    params: BuildStoredPaymentMethodParams
  ): TutoringStoredPaymentMethodRecord {
    const basis = methodBasis(params);
    const method: TutoringStoredPaymentMethod = {
      paymentMethodId: params.paymentMethodId,
      paymentMethodType: "card",
      paymentMethodSummary: paymentMethodSummary(params.brand, params.last4),
      registrationId: stableId("mock_reg", basis),
      providerReference: stableId("mock_ref", basis),
      provider: MOCK_TUTORING_PROVIDER_NAME,
      isTemporary: params.isTemporary,
      brand: params.brand,
      last4: params.last4,
      holder: params.holder,
      expMonth: params.expMonth,
      expYear: params.expYear,
      mockCustomerCode: stableId("mock_customer", basis),
      mockAuthorizationCode: stableId("mock_auth_code", basis),
      mockAuthorizationReference: stableId("mock_auth_ref", basis),
      mockPreauthReference: stableId("mock_preauth", basis),
      reusableAuthorizationCode: stableId("mock_reusable_auth", basis),
      reusable: true,
      status: "ready",
    };

    const rootFields = params.isTemporary ? {
      temporaryPaymentSetupStatus: "ready",
      temporaryPaymentProvider: MOCK_TUTORING_PROVIDER_NAME,
      temporaryPaymentProviderFamily: "paystack",
      temporaryPaymentAdapterKey: "mock_tutoring_payment_provider",
      temporaryPaymentProviderMode: "test",
      temporaryPaymentLiveChargeEnabled: false,
      temporaryPaymentMethodId: method.paymentMethodId,
      temporaryPaymentRegistrationId: method.registrationId,
      temporaryPaymentProviderReference: method.providerReference,
      temporaryPaymentAuthorizationCode: method.mockAuthorizationCode,
      temporaryPaymentAuthorizationReference: method.mockAuthorizationReference,
      temporaryPaymentPreauthReference: method.mockPreauthReference,
      temporaryPaymentCustomerCode: method.mockCustomerCode,
      temporaryPaymentReusableAuthorizationCode:
        method.reusableAuthorizationCode,
      temporaryPaymentStatus: method.status,
      temporaryCardBrand: method.brand,
      temporaryCardLast4: method.last4,
      temporaryCardExpMonth: method.expMonth,
      temporaryCardExpYear: method.expYear,
      temporaryCardHolder: method.holder,
      temporaryPaymentScope: "tutor_booking_only",
      temporaryPaymentUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    } : {
      billingSetupStatus: "ready",
      billingProvider: MOCK_TUTORING_PROVIDER_NAME,
      billingProviderFamily: "paystack",
      billingAdapterKey: "mock_tutoring_payment_provider",
      billingProviderMode: "test",
      billingLiveChargeEnabled: false,
      billingDefaultPaymentMethodId: method.paymentMethodId,
      billingRegistrationId: method.registrationId,
      billingProviderReference: method.providerReference,
      billingAuthorizationCode: method.mockAuthorizationCode,
      billingAuthorizationReference: method.mockAuthorizationReference,
      billingPreauthReference: method.mockPreauthReference,
      billingCustomerCode: method.mockCustomerCode,
      billingReusableAuthorizationCode: method.reusableAuthorizationCode,
      billingStatus: method.status,
      billingCardBrand: method.brand,
      billingCardLast4: method.last4,
      billingCardExpMonth: method.expMonth,
      billingCardExpYear: method.expYear,
      billingCardHolder: method.holder,
      billingAuthorizationMode: "per_session",
      billingUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    return {
      collectionName: paymentMethodCollectionName(params.isTemporary),
      method,
      rootFields,
      methodFields: {
        paymentMethodId: method.paymentMethodId,
        type: method.paymentMethodType,
        brand: method.brand,
        last4: method.last4,
        expMonth: method.expMonth,
        expYear: method.expYear,
        holder: method.holder,
        provider: method.provider,
        providerReference: method.providerReference,
        registrationId: method.registrationId,
        mockCustomerCode: method.mockCustomerCode,
        mockAuthorizationCode: method.mockAuthorizationCode,
        mockAuthorizationReference: method.mockAuthorizationReference,
        mockPreauthReference: method.mockPreauthReference,
        reusableAuthorizationCode: method.reusableAuthorizationCode,
        reusable: method.reusable,
        status: method.status,
        scope: params.isTemporary ? "tutor_booking_only" : "account_default",
        tutoringPaymentRail: "TUTORING",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
    };
  },

  async readStoredPaymentMethod(
    tx: admin.firestore.Transaction,
    studentRef: admin.firestore.DocumentReference
  ): Promise<TutoringStoredPaymentMethod> {
    const studentSnap = await tx.get(studentRef);
    if (!studentSnap.exists) {
      throw new HttpsError("not-found", "Student not found.");
    }
    const studentData = studentSnap.data() ?? {};
    const isTemporary = isInstantTutorModeUser(
      studentData as Record<string, unknown>
    );
    const collectionName = paymentMethodCollectionName(isTemporary);
    const rootMethodId = toTrimmedString(
      isTemporary ?
        studentData.temporaryPaymentMethodId :
        studentData.billingDefaultPaymentMethodId
    );
    let methodData: Record<string, unknown> = {};
    if (rootMethodId) {
      const methodSnap = await tx.get(studentRef.collection(collectionName).doc(rootMethodId));
      methodData = methodSnap.data() ?? {};
    }

    return buildMethodFromSource({
      isTemporary,
      rootData: studentData as Record<string, unknown>,
      methodData,
    });
  },

  async authorizeInitial(
    params: TutoringAuthorizationParams
  ): Promise<TutoringProviderLikeResult> {
    return buildProviderResult({
      operation: "auth",
      operationId: `${params.authorizationId}|${params.amountZar.toFixed(2)}`,
      merchantTransactionId: params.merchantTransactionId,
      registrationId: params.paymentMethod.registrationId,
      description: "Mock tutoring preauthorization succeeded.",
    });
  },

  async authorizeReserve(
    params: TutoringAuthorizationParams
  ): Promise<TutoringProviderLikeResult> {
    return buildProviderResult({
      operation: "reserve",
      operationId: `${params.authorizationId}|${params.amountZar.toFixed(2)}`,
      merchantTransactionId: params.merchantTransactionId,
      registrationId: params.paymentMethod.registrationId,
      description: "Mock tutoring reserve authorization succeeded.",
    });
  },

  async capture(params: TutoringCaptureParams): Promise<TutoringProviderLikeResult> {
    return buildProviderResult({
      operation: "capture",
      operationId: `${params.authorizationId}|${params.merchantTransactionId}|${params.amountZar.toFixed(2)}`,
      merchantTransactionId: params.merchantTransactionId,
      registrationId: "",
      referencedId: params.authorizationProviderPaymentId,
      description: "Mock tutoring capture succeeded.",
    });
  },

  async reverse(params: TutoringReversalParams): Promise<TutoringProviderLikeResult> {
    return buildProviderResult({
      operation: "void",
      operationId: `${params.authorizationId}|${params.merchantTransactionId}|${params.amountZar.toFixed(2)}`,
      merchantTransactionId: params.merchantTransactionId,
      registrationId: "",
      referencedId: params.authorizationProviderPaymentId,
      description: "Mock tutoring authorization release succeeded.",
    });
  },
};

export function getTutoringPaymentProvider(): TutoringPaymentProvider {
  const config = functions.config as any;

  if (config.paystack?.secret) {
    return getPaystackTutoringProvider();
  }

  return mockTutoringPaymentProvider;
}

export function getMockTutoringPaymentProvider(): TutoringPaymentProvider {
  return mockTutoringPaymentProvider;
}
