import * as admin from "firebase-admin";

export const TUTORING_PAYMENT_PROVIDER_REGION = "europe-west1";
export const TUTORING_PAYMENT_CURRENCY = "ZAR";
export const MOCK_TUTORING_PROVIDER_NAME = "MOCK_TUTORING";
export const MOCK_AUTHORIZED_RESULT_CODE = "000.100.110";
export const MOCK_PENDING_RESULT_CODE = "000.200.000";
export const MOCK_FAILED_RESULT_CODE = "100.400.500";

export type TutoringPaymentProviderFamily = "paystack";
export type TutoringPaymentProviderSetupMode = "test" | "live_pending" | "live";

export interface TutoringPaymentProviderStatus {
  providerName: string;
  adapterKey: string;
  providerFamily: TutoringPaymentProviderFamily;
  setupMode: TutoringPaymentProviderSetupMode;
  liveChargeEnabled: boolean;
}

export interface TutoringStoredPaymentMethod {
  paymentMethodId: string;
  paymentMethodType: string;
  paymentMethodSummary: string;
  registrationId: string;
  providerReference: string;
  provider: string;
  isTemporary: boolean;
  brand: string;
  last4: string;
  holder: string;
  expMonth: number;
  expYear: number;
  mockCustomerCode: string;
  mockAuthorizationCode: string;
  mockAuthorizationReference: string;
  mockPreauthReference: string;
  reusableAuthorizationCode: string;
  reusable: boolean;
  status: string;
}

export interface TutoringStoredPaymentMethodRecord {
  collectionName: string;
  method: TutoringStoredPaymentMethod;
  rootFields: Record<string, unknown>;
  methodFields: Record<string, unknown>;
}

export interface TutoringProviderLikeResult {
  id?: string;
  ndc?: string;
  registrationId?: string;
  merchantTransactionId?: string;
  referencedId?: string;
  timestamp?: string;
  result?: {
    code?: string;
    description?: string;
  };
  [key: string]: unknown;
}

export interface BuildStoredPaymentMethodParams {
  paymentMethodId: string;
  isTemporary: boolean;
  brand: string;
  holder: string;
  last4: string;
  expMonth: number;
  expYear: number;
}

export interface TutoringAuthorizationParams {
  authorizationId: string;
  bookingId: string;
  paymentIntentId: string;
  sessionId: string;
  studentId: string;
  tutorId: string;
  amountZar: number;
  currency: string;
  merchantTransactionId: string;
  paymentMethod: TutoringStoredPaymentMethod;
}

export interface TutoringCaptureParams {
  authorizationId: string;
  bookingId: string;
  paymentIntentId: string;
  sessionId: string;
  amountZar: number;
  currency: string;
  merchantTransactionId: string;
  authorizationProviderPaymentId: string;
}

export interface TutoringReversalParams {
  authorizationId: string;
  bookingId: string;
  paymentIntentId: string;
  sessionId: string;
  amountZar: number;
  currency: string;
  merchantTransactionId: string;
  authorizationProviderPaymentId: string;
}

export interface TutoringPaymentProvider {
  readonly providerName: string;
  readonly adapterKey: string;
  readonly providerFamily: TutoringPaymentProviderFamily;
  readonly setupMode: TutoringPaymentProviderSetupMode;
  readonly liveChargeEnabled: boolean;
  buildStoredPaymentMethod(
    params: BuildStoredPaymentMethodParams
  ): TutoringStoredPaymentMethodRecord;
  readStoredPaymentMethod(
    tx: admin.firestore.Transaction,
    studentRef: admin.firestore.DocumentReference
  ): Promise<TutoringStoredPaymentMethod>;
  authorizeInitial(
    params: TutoringAuthorizationParams
  ): Promise<TutoringProviderLikeResult>;
  authorizeReserve(
    params: TutoringAuthorizationParams
  ): Promise<TutoringProviderLikeResult>;
  capture(params: TutoringCaptureParams): Promise<TutoringProviderLikeResult>;
  reverse(params: TutoringReversalParams): Promise<TutoringProviderLikeResult>;
}

export function toTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

export function toMoney(value: number): number {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

export function asMoney(value: unknown, fallback = 0): number {
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

export function paymentMethodCollectionName(isTemporary: boolean): string {
  return isTemporary ? "temporary_payment_methods" : "payment_methods";
}

export function isInstantTutorModeUser(data: Record<string, unknown>): boolean {
  const accessTier = toTrimmedString(data.accessTier).toLowerCase();
  const accountType = toTrimmedString(data.accountType).toLowerCase();
  const accessMode = toTrimmedString(data.accessMode).toLowerCase();
  return accessTier === "instant_tutor" ||
    accountType === "instant_tutor" ||
    accessMode === "instanttutor" ||
    data.instantTutorAccess === true;
}

export function paymentMethodSummary(brand: string, last4: string): string {
  const cleanBrand = toTrimmedString(brand) || "Card";
  const cleanLast4 = toTrimmedString(last4);
  return cleanLast4 ? `${cleanBrand} •••• ${cleanLast4}` : cleanBrand;
}

export function buildProviderResponseSnapshot(
  providerResponse: TutoringProviderLikeResult | Record<string, unknown>,
  merchantTransactionId: string
): Record<string, unknown> {
  const response = providerResponse as TutoringProviderLikeResult;
  return {
    paymentId: toTrimmedString(response.id),
    ndc: toTrimmedString(response.ndc),
    referencedId: toTrimmedString(response.referencedId),
    resultCode: toTrimmedString(response.result?.code),
    resultDescription: toTrimmedString(response.result?.description),
    merchantTransactionId:
      toTrimmedString(response.merchantTransactionId) || merchantTransactionId,
    timestamp: toTrimmedString(response.timestamp),
    registrationId: toTrimmedString(response.registrationId),
    raw: providerResponse,
  };
}

export function buildTutoringPaymentProviderStatus(
  provider: TutoringPaymentProvider
): TutoringPaymentProviderStatus {
  return {
    providerName: provider.providerName,
    adapterKey: provider.adapterKey,
    providerFamily: provider.providerFamily,
    setupMode: provider.setupMode,
    liveChargeEnabled: provider.liveChargeEnabled,
  };
}
