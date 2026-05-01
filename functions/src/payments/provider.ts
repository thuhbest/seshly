export type PaymentProviderEnvironment =
  | "local"
  | "staging"
  | "test"
  | "production";

export type ProviderOperationStatus =
  | "authorized"
  | "reserved"
  | "captured"
  | "released"
  | "pending"
  | "failed"
  | "validated"
  | "invalid"
  | "queued"
  | "processing";

export interface PaymentProviderOperationContext {
  idempotencyKey: string;
  environment?: PaymentProviderEnvironment;
  metadata?: Record<string, unknown>;
}

export interface PaymentProviderResultBase {
  providerName: string;
  adapterKey: string;
  idempotencyKey: string;
  success: boolean;
  status: ProviderOperationStatus;
  message: string;
  reference: string;
  loggedAt: string;
  raw: Record<string, unknown>;
}

export interface InitializeFirstPreauthInput
  extends PaymentProviderOperationContext {
  bookingId: string;
  paymentSessionId: string;
  sessionId?: string;
  customerEmail?: string;
  customerCode?: string;
  authorizationCode?: string;
  amountZar: number;
  currency: string;
  reason?: string;
}

export interface ReservePreauthInput extends PaymentProviderOperationContext {
  bookingId: string;
  paymentSessionId: string;
  sessionId: string;
  authorizationCode: string;
  authorizationReference: string;
  customerCode?: string;
  amountZar: number;
  currency: string;
  reason?: string;
}

export interface CapturePreauthInput extends PaymentProviderOperationContext {
  bookingId: string;
  paymentSessionId: string;
  sessionId: string;
  authorizationReference: string;
  amountZar: number;
  currency: string;
  reason?: string;
}

export interface ReleasePreauthInput extends PaymentProviderOperationContext {
  bookingId: string;
  paymentSessionId: string;
  sessionId: string;
  authorizationReference: string;
  amountZar: number;
  currency: string;
  reason?: string;
}

export interface TransactionVerificationResult extends PaymentProviderResultBase {
  transactionStatus: "success" | "pending" | "failed" | "not_found";
  authorizationReference: string | null;
  amountZar: number | null;
  currency: string | null;
}

export interface PreauthResult extends PaymentProviderResultBase {
  amountZar: number;
  currency: string;
  customerCode: string;
  authorizationCode: string;
  authorizationReference: string;
  preauthReference: string;
  reusable: boolean;
}

export interface CaptureResult extends PaymentProviderResultBase {
  amountZar: number;
  currency: string;
  authorizationReference: string;
  captureReference: string;
}

export interface ReleaseResult extends PaymentProviderResultBase {
  amountZar: number;
  currency: string;
  authorizationReference: string;
  releaseReference: string;
}

export interface CreateTransferRecipientInput
  extends PaymentProviderOperationContext {
  tutorId: string;
  accountName: string;
  accountNumber: string;
  bankCode: string;
  currency?: string;
  countryCode?: string;
}

export interface TransferRecipientResult extends PaymentProviderResultBase {
  recipientCode: string;
  recipientReference: string;
  accountName: string;
  maskedAccountNumber: string;
  bankCode: string;
  currency: string;
}

export interface ValidateSouthAfricanAccountInput
  extends PaymentProviderOperationContext {
  accountName: string;
  accountNumber: string;
  bankCode: string;
}

export interface SouthAfricanAccountValidationResult
  extends PaymentProviderResultBase {
  isValid: boolean;
  bankCode: string;
  bankName: string;
  accountName: string;
  maskedAccountNumber: string;
}

export interface InitiateTransferInput extends PaymentProviderOperationContext {
  payoutId: string;
  recipientCode: string;
  amountZar: number;
  currency: string;
  reason?: string;
}

export interface TransferResult extends PaymentProviderResultBase {
  payoutId: string;
  recipientCode: string;
  transferCode: string;
  transferReference: string;
  amountZar: number;
  currency: string;
}

export interface BulkTransferItemInput {
  payoutId: string;
  recipientCode: string;
  amountZar: number;
  reason?: string;
}

export interface InitiateBulkTransferInput
  extends PaymentProviderOperationContext {
  batchId: string;
  currency: string;
  transfers: BulkTransferItemInput[];
}

export interface BulkTransferResult extends PaymentProviderResultBase {
  batchId: string;
  batchReference: string;
  transferCount: number;
  acceptedCount: number;
  transfers: TransferResult[];
}

export interface PaymentProvider {
  readonly providerName: string;
  readonly adapterKey: string;
  initializeFirstPreauth(input: InitializeFirstPreauthInput): Promise<PreauthResult>;
  reservePreauth(input: ReservePreauthInput): Promise<PreauthResult>;
  capturePreauth(input: CapturePreauthInput): Promise<CaptureResult>;
  releasePreauth(input: ReleasePreauthInput): Promise<ReleaseResult>;
  verifyTransaction(reference: string): Promise<TransactionVerificationResult>;
  createTransferRecipient(
    input: CreateTransferRecipientInput
  ): Promise<TransferRecipientResult>;
  validateSouthAfricanAccount(
    input: ValidateSouthAfricanAccountInput
  ): Promise<SouthAfricanAccountValidationResult>;
  initiateTransfer(input: InitiateTransferInput): Promise<TransferResult>;
  initiateBulkTransfer(input: InitiateBulkTransferInput): Promise<BulkTransferResult>;
}

export function assertIdempotencyKey(idempotencyKey: string): void {
  if (!idempotencyKey || !idempotencyKey.trim()) {
    throw new Error("Payment provider idempotencyKey is required.");
  }
}

export function normalizeCurrency(currency: string): string {
  return (currency || "").trim().toUpperCase() || "ZAR";
}

export function normalizeAmountZar(amountZar: number): number {
  if (!Number.isFinite(amountZar) || amountZar <= 0) {
    throw new Error("Payment provider amountZar must be greater than zero.");
  }
  return Math.round((amountZar + Number.EPSILON) * 100) / 100;
}
