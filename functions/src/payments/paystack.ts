import * as logger from "firebase-functions/logger";
import {
  type BulkTransferResult,
  type CapturePreauthInput,
  type CaptureResult,
  type CreateTransferRecipientInput,
  type InitiateBulkTransferInput,
  type InitiateTransferInput,
  type InitializeFirstPreauthInput,
  type PaymentProvider,
  type PreauthResult,
  type ReleasePreauthInput,
  type ReleaseResult,
  type ReservePreauthInput,
  type SouthAfricanAccountValidationResult,
  type TransactionVerificationResult,
  type TransferRecipientResult,
  type TransferResult,
  type ValidateSouthAfricanAccountInput,
} from "./provider";

const PROVIDER_NAME = "PAYSTACK";
const ADAPTER_KEY = "paystack";

export const PAYSTACK_LIVE_ENDPOINTS = {
  initializeFirstPreauth: {
    method: "POST",
    path: "/charge",
    notes:
      "TODO(paystack-live): first tutoring card authorization should plug into Paystack Charge API here. If product later chooses hosted checkout instead of server-side charge, swap this hook to POST /transaction/initialize plus GET /transaction/verify/:reference.",
  },
  reservePreauth: {
    method: "POST",
    path: "/transaction/charge_authorization",
    notes:
      "TODO(paystack-live): refill/top-up authorization against a reusable authorization_code plugs in here.",
  },
  capturePreauth: {
    method: "POST",
    path: "/transaction/charge_authorization",
    notes:
      "TODO(paystack-live): final tutoring capture currently maps to a reusable authorization charge here. If the final production design switches to partial debit semantics, replace this hook with the exact Paystack debit endpoint during the live integration pass.",
  },
  releasePreauth: {
    method: "NONE",
    path: "NO_PUBLIC_PAYSTACK_VOID_ENDPOINT",
    notes:
      "TODO(paystack-live): Paystack public docs do not currently expose a dedicated preauthorization release/void endpoint for this architecture. Keep this hook unwired until the final live release strategy is chosen.",
  },
  verifyTransaction: {
    method: "GET",
    path: "/transaction/verify/:reference",
    notes:
      "TODO(paystack-live): polling/fallback transaction verification plugs in here.",
  },
  createTransferRecipient: {
    method: "POST",
    path: "/transferrecipient",
    notes:
      "TODO(paystack-live): South African tutor payout recipient creation plugs in here.",
  },
  validateSouthAfricanAccount: {
    method: "POST",
    path: "/bank/validate",
    notes:
      "TODO(paystack-live): payout account validation plugs in here. If the bank/name resolution flow needs an earlier lookup step, add the matching Paystack resolve endpoint in this method during the live pass.",
  },
  initiateTransfer: {
    method: "POST",
    path: "/transfer",
    notes:
      "TODO(paystack-live): single tutor payout transfer initiation plugs in here.",
  },
  initiateBulkTransfer: {
    method: "POST",
    path: "/transfer/bulk",
    notes:
      "TODO(paystack-live): Monday tutor payout batch transfer initiation plugs in here.",
  },
} as const;

function notWired(operation: keyof typeof PAYSTACK_LIVE_ENDPOINTS): never {
  const endpoint = PAYSTACK_LIVE_ENDPOINTS[operation];
  logger.warn("payments.paystack.stub_not_wired", {
    providerName: PROVIDER_NAME,
    adapterKey: ADAPTER_KEY,
    operation,
    endpointMethod: endpoint.method,
    endpointPath: endpoint.path,
    notes: endpoint.notes,
  });
  throw new Error(
    `TODO(paystack-live): ${operation} is not wired yet. Planned Paystack endpoint: ${endpoint.method} ${endpoint.path}`
  );
}

export const paystackProviderStub: PaymentProvider = {
  providerName: PROVIDER_NAME,
  adapterKey: ADAPTER_KEY,

  async initializeFirstPreauth(
    _input: InitializeFirstPreauthInput
  ): Promise<PreauthResult> {
    return notWired("initializeFirstPreauth");
  },

  async reservePreauth(
    _input: ReservePreauthInput
  ): Promise<PreauthResult> {
    return notWired("reservePreauth");
  },

  async capturePreauth(
    _input: CapturePreauthInput
  ): Promise<CaptureResult> {
    return notWired("capturePreauth");
  },

  async releasePreauth(
    _input: ReleasePreauthInput
  ): Promise<ReleaseResult> {
    return notWired("releasePreauth");
  },

  async verifyTransaction(
    _reference: string
  ): Promise<TransactionVerificationResult> {
    return notWired("verifyTransaction");
  },

  async createTransferRecipient(
    _input: CreateTransferRecipientInput
  ): Promise<TransferRecipientResult> {
    return notWired("createTransferRecipient");
  },

  async validateSouthAfricanAccount(
    _input: ValidateSouthAfricanAccountInput
  ): Promise<SouthAfricanAccountValidationResult> {
    return notWired("validateSouthAfricanAccount");
  },

  async initiateTransfer(
    _input: InitiateTransferInput
  ): Promise<TransferResult> {
    return notWired("initiateTransfer");
  },

  async initiateBulkTransfer(
    _input: InitiateBulkTransferInput
  ): Promise<BulkTransferResult> {
    return notWired("initiateBulkTransfer");
  },
};

export function getPaystackProviderStub(): PaymentProvider {
  return paystackProviderStub;
}
