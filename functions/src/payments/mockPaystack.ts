import {createHash} from "node:crypto";
import * as logger from "firebase-functions/logger";
import {
  type BulkTransferResult,
  type CapturePreauthInput,
  type CaptureResult,
  type CreateTransferRecipientInput,
  type InitiateBulkTransferInput,
  type InitiateTransferInput,
  type PaymentProvider,
  type PaymentProviderResultBase,
  type PreauthResult,
  type ProviderOperationStatus,
  type ReleasePreauthInput,
  type ReleaseResult,
  type ReservePreauthInput,
  type SouthAfricanAccountValidationResult,
  type TransactionVerificationResult,
  type TransferRecipientResult,
  type TransferResult,
  type ValidateSouthAfricanAccountInput,
  type InitializeFirstPreauthInput,
  assertIdempotencyKey,
  normalizeAmountZar,
  normalizeCurrency,
} from "./provider";

const PROVIDER_NAME = "MOCK_PAYSTACK";
const ADAPTER_KEY = "mock_paystack";
const BASE_TIME_MS = Date.UTC(2025, 0, 1, 0, 0, 0);

const SA_BANK_NAMES: Record<string, string> = {
  "051001": "Standard Bank",
  "250655": "First National Bank",
  "632005": "ABSA",
  "198765": "Nedbank",
  "470010": "Capitec",
};

type MockOutcome = "success" | "pending" | "failed" | "invalid";

function stableDigest(material: string): string {
  return createHash("sha256").update(material).digest("hex");
}

function stableId(prefix: string, material: string, length = 16): string {
  return `${prefix}_${stableDigest(material).slice(0, length)}`;
}

function stableIso(material: string): string {
  const secondsOffset = Number.parseInt(stableDigest(material).slice(0, 8), 16);
  return new Date(BASE_TIME_MS + (secondsOffset % (365 * 24 * 60 * 60)) * 1000)
    .toISOString();
}

function maskedAccountNumber(accountNumber: string): string {
  const trimmed = accountNumber.replace(/\s+/g, "");
  if (trimmed.length <= 4) {
    return trimmed;
  }
  return `${"*".repeat(Math.max(0, trimmed.length - 4))}${trimmed.slice(-4)}`;
}

function deriveOutcome(...materials: Array<string | undefined>): MockOutcome {
  const haystack = materials
    .filter((value): value is string => Boolean(value))
    .join("|")
    .toLowerCase();

  if (haystack.includes("invalid")) return "invalid";
  if (haystack.includes("fail")) return "failed";
  if (haystack.includes("pending") || haystack.includes("queue")) return "pending";
  return "success";
}

function logOperation(
  operation: string,
  payload: Record<string, unknown>,
  result: unknown
): void {
  logger.info("payments.mockPaystack", {
    providerName: PROVIDER_NAME,
    adapterKey: ADAPTER_KEY,
    operation,
    request: payload,
    result,
  });
}

function buildBaseResult(params: {
  operation: string;
  idempotencyKey: string;
  reference: string;
  status: ProviderOperationStatus;
  success: boolean;
  message: string;
  raw: Record<string, unknown>;
}): PaymentProviderResultBase {
  return {
    providerName: PROVIDER_NAME,
    adapterKey: ADAPTER_KEY,
    idempotencyKey: params.idempotencyKey,
    success: params.success,
    status: params.status,
    message: params.message,
    reference: params.reference,
    loggedAt: stableIso(`${params.operation}|${params.idempotencyKey}`),
    raw: params.raw,
  };
}

function paystackLikeRaw(params: {
  idempotencyKey: string;
  reference: string;
  status: string;
  message: string;
  data: Record<string, unknown>;
}): Record<string, unknown> {
  return {
    status: params.status !== "failed" && params.status !== "invalid",
    message: params.message,
    idempotencyKey: params.idempotencyKey,
    data: {
      reference: params.reference,
      status: params.status,
      ...params.data,
    },
  };
}

function validateSouthAfricanBankFields(accountNumber: string, bankCode: string): boolean {
  const normalizedAccount = accountNumber.replace(/\s+/g, "");
  return /^\d{6,12}$/.test(normalizedAccount) && /^\d{6}$/.test(bankCode);
}

function buildPreauth(
  operation: "initializeFirstPreauth" | "reservePreauth",
  input: InitializeFirstPreauthInput | ReservePreauthInput
): PreauthResult {
  assertIdempotencyKey(input.idempotencyKey);
  const amountZar = normalizeAmountZar(input.amountZar);
  const currency = normalizeCurrency(input.currency);
  const outcome = deriveOutcome(
    input.idempotencyKey,
    input.bookingId,
    input.paymentSessionId,
    input.sessionId,
    input.reason
  );
  const customerCode = stableId(
    "CUS",
    `${input.bookingId}|${input.paymentSessionId}|${input.idempotencyKey}|customer`
  );
  const authorizationCode = stableId(
    "AUTH",
    `${input.bookingId}|${input.paymentSessionId}|${input.idempotencyKey}|authorization`
  );
  const authorizationReference = stableId(
    "PAUTH",
    `${operation}|${input.idempotencyKey}|${amountZar.toFixed(2)}`
  );
  const preauthReference = stableId(
    "PREAUTH",
    `${operation}|${authorizationReference}|${currency}`
  );

  const success = outcome !== "failed";
  const status: ProviderOperationStatus =
    outcome === "pending" ? "pending" :
      outcome === "failed" ? "failed" :
        operation === "reservePreauth" ? "reserved" :
          "authorized";
  const message =
    status === "pending" ? "Mock Paystack preauthorization queued." :
      status === "failed" ? "Mock Paystack preauthorization failed." :
        operation === "reservePreauth" ?
          "Mock Paystack reserve preauthorization succeeded." :
          "Mock Paystack first preauthorization succeeded.";

  const raw = paystackLikeRaw({
    idempotencyKey: input.idempotencyKey,
    reference: preauthReference,
    status,
    message,
    data: {
      amount: Math.round(amountZar * 100),
      currency,
      customer_code: customerCode,
      authorization_code: authorizationCode,
      authorization_reference: authorizationReference,
      reusable: true,
    },
  });

  const result: PreauthResult = {
    ...buildBaseResult({
      operation,
      idempotencyKey: input.idempotencyKey,
      reference: preauthReference,
      status,
      success,
      message,
      raw,
    }),
    amountZar,
    currency,
    customerCode,
    authorizationCode,
    authorizationReference,
    preauthReference,
    reusable: true,
  };

  logOperation(operation, {
    bookingId: input.bookingId,
    paymentSessionId: input.paymentSessionId,
    sessionId: input.sessionId ?? null,
    amountZar,
    currency,
    idempotencyKey: input.idempotencyKey,
  }, result);
  return result;
}

function buildCaptureOrRelease(
  operation: "capturePreauth" | "releasePreauth",
  input: CapturePreauthInput | ReleasePreauthInput
): CaptureResult | ReleaseResult {
  assertIdempotencyKey(input.idempotencyKey);
  const amountZar = normalizeAmountZar(input.amountZar);
  const currency = normalizeCurrency(input.currency);
  const outcome = deriveOutcome(
    input.idempotencyKey,
    input.authorizationReference,
    input.reason
  );
  const referencePrefix = operation === "capturePreauth" ? "CAP" : "REL";
  const reference = stableId(
    referencePrefix,
    `${operation}|${input.idempotencyKey}|${input.authorizationReference}|${amountZar.toFixed(2)}`
  );

  const success = outcome !== "failed";
  const status: ProviderOperationStatus =
    outcome === "pending" ? "pending" :
      outcome === "failed" ? "failed" :
        operation === "capturePreauth" ? "captured" : "released";
  const message =
    status === "pending" ? `Mock Paystack ${operation} queued.` :
      status === "failed" ? `Mock Paystack ${operation} failed.` :
        operation === "capturePreauth" ?
          "Mock Paystack capture succeeded." :
          "Mock Paystack release succeeded.";

  const raw = paystackLikeRaw({
    idempotencyKey: input.idempotencyKey,
    reference,
    status,
    message,
    data: {
      amount: Math.round(amountZar * 100),
      currency,
      authorization_reference: input.authorizationReference,
    },
  });

  if (operation === "capturePreauth") {
    const result: CaptureResult = {
      ...buildBaseResult({
        operation,
        idempotencyKey: input.idempotencyKey,
        reference,
        status,
        success,
        message,
        raw,
      }),
      amountZar,
      currency,
      authorizationReference: input.authorizationReference,
      captureReference: reference,
    };
    logOperation(operation, {
      bookingId: input.bookingId,
      paymentSessionId: input.paymentSessionId,
      sessionId: input.sessionId,
      authorizationReference: input.authorizationReference,
      amountZar,
      currency,
      idempotencyKey: input.idempotencyKey,
    }, result);
    return result;
  }

  const result: ReleaseResult = {
    ...buildBaseResult({
      operation,
      idempotencyKey: input.idempotencyKey,
      reference,
      status,
      success,
      message,
      raw,
    }),
    amountZar,
    currency,
    authorizationReference: input.authorizationReference,
    releaseReference: reference,
  };
  logOperation(operation, {
    bookingId: input.bookingId,
    paymentSessionId: input.paymentSessionId,
    sessionId: input.sessionId,
    authorizationReference: input.authorizationReference,
    amountZar,
    currency,
    idempotencyKey: input.idempotencyKey,
  }, result);
  return result;
}

export const mockPaystackProvider: PaymentProvider = {
  providerName: PROVIDER_NAME,
  adapterKey: ADAPTER_KEY,

  async initializeFirstPreauth(
    input: InitializeFirstPreauthInput
  ): Promise<PreauthResult> {
    return buildPreauth("initializeFirstPreauth", input);
  },

  async reservePreauth(input: ReservePreauthInput): Promise<PreauthResult> {
    return buildPreauth("reservePreauth", input);
  },

  async capturePreauth(input: CapturePreauthInput): Promise<CaptureResult> {
    return buildCaptureOrRelease("capturePreauth", input) as CaptureResult;
  },

  async releasePreauth(input: ReleasePreauthInput): Promise<ReleaseResult> {
    return buildCaptureOrRelease("releasePreauth", input) as ReleaseResult;
  },

  async verifyTransaction(
    reference: string
  ): Promise<TransactionVerificationResult> {
    const normalizedReference = (reference || "").trim();
    const outcome = deriveOutcome(normalizedReference);
    const status =
      outcome === "invalid" ? "failed" :
        outcome === "pending" ? "pending" :
          outcome === "failed" ? "failed" :
            "authorized";
    const transactionStatus =
      outcome === "invalid" ? "not_found" :
        outcome === "pending" ? "pending" :
          outcome === "failed" ? "failed" :
            "success";
    const message =
      transactionStatus === "not_found" ?
        "Mock Paystack transaction not found." :
        transactionStatus === "pending" ?
          "Mock Paystack transaction is pending." :
          transactionStatus === "failed" ?
            "Mock Paystack transaction failed." :
            "Mock Paystack transaction verified.";
    const idempotencyKey = stableId("VERIFY", normalizedReference || "missing");
    const authorizationReference =
      transactionStatus === "not_found" ?
        null :
        stableId("PAUTH", `${normalizedReference}|authorization`);
    const amountZar =
      transactionStatus === "not_found" ? null :
        Number.parseInt(stableDigest(normalizedReference).slice(0, 6), 16) % 5000 / 100 + 50;
    const currency =
      transactionStatus === "not_found" ? null : "ZAR";
    const raw = paystackLikeRaw({
      idempotencyKey,
      reference: normalizedReference || "missing_reference",
      status,
      message,
      data: {
        authorization_reference: authorizationReference,
        amount: amountZar === null ? null : Math.round(amountZar * 100),
        currency,
      },
    });
    const result: TransactionVerificationResult = {
      ...buildBaseResult({
        operation: "verifyTransaction",
        idempotencyKey,
        reference: normalizedReference || "missing_reference",
        status,
        success: transactionStatus !== "failed" && transactionStatus !== "not_found",
        message,
        raw,
      }),
      transactionStatus,
      authorizationReference,
      amountZar,
      currency,
    };
    logOperation("verifyTransaction", {reference: normalizedReference}, result);
    return result;
  },

  async createTransferRecipient(
    input: CreateTransferRecipientInput
  ): Promise<TransferRecipientResult> {
    assertIdempotencyKey(input.idempotencyKey);
    const accountNumber = input.accountNumber.replace(/\s+/g, "");
    const bankCode = input.bankCode.trim();
    const currency = normalizeCurrency(input.currency || "ZAR");
    const valid = validateSouthAfricanBankFields(accountNumber, bankCode);
    const outcome = valid ?
      deriveOutcome(input.idempotencyKey, input.tutorId, input.accountName) :
      "invalid";
    const recipientReference = stableId(
      "RCPREF",
      `${input.idempotencyKey}|${input.tutorId}|${accountNumber}|${bankCode}`
    );
    const recipientCode = stableId("RCP", recipientReference);
    const status: ProviderOperationStatus =
      outcome === "invalid" ? "invalid" :
        outcome === "failed" ? "failed" :
          "validated";
    const message =
      status === "invalid" ? "Mock Paystack recipient payload is invalid." :
        status === "failed" ? "Mock Paystack recipient creation failed." :
          "Mock Paystack transfer recipient created.";
    const raw = paystackLikeRaw({
      idempotencyKey: input.idempotencyKey,
      reference: recipientReference,
      status,
      message,
      data: {
        recipient_code: recipientCode,
        account_name: input.accountName,
        account_number: maskedAccountNumber(accountNumber),
        bank_code: bankCode,
        currency,
      },
    });
    const result: TransferRecipientResult = {
      ...buildBaseResult({
        operation: "createTransferRecipient",
        idempotencyKey: input.idempotencyKey,
        reference: recipientReference,
        status,
        success: status === "validated",
        message,
        raw,
      }),
      recipientCode,
      recipientReference,
      accountName: input.accountName.trim(),
      maskedAccountNumber: maskedAccountNumber(accountNumber),
      bankCode,
      currency,
    };
    logOperation("createTransferRecipient", {
      tutorId: input.tutorId,
      bankCode,
      maskedAccountNumber: maskedAccountNumber(accountNumber),
      idempotencyKey: input.idempotencyKey,
    }, result);
    return result;
  },

  async validateSouthAfricanAccount(
    input: ValidateSouthAfricanAccountInput
  ): Promise<SouthAfricanAccountValidationResult> {
    assertIdempotencyKey(input.idempotencyKey);
    const accountNumber = input.accountNumber.replace(/\s+/g, "");
    const bankCode = input.bankCode.trim();
    const structurallyValid = validateSouthAfricanBankFields(accountNumber, bankCode);
    const outcome = structurallyValid ?
      deriveOutcome(input.idempotencyKey, input.accountName, bankCode) :
      "invalid";
    const isValid = outcome === "success" || outcome === "pending";
    const status: ProviderOperationStatus = isValid ? "validated" : "invalid";
    const reference = stableId(
      "ACCVAL",
      `${input.idempotencyKey}|${input.accountName}|${accountNumber}|${bankCode}`
    );
    const bankName = SA_BANK_NAMES[bankCode] || "South African Bank";
    const message = isValid ?
      "Mock Paystack South African account validated." :
      "Mock Paystack South African account validation failed.";
    const raw = paystackLikeRaw({
      idempotencyKey: input.idempotencyKey,
      reference,
      status,
      message,
      data: {
        bank_code: bankCode,
        bank_name: bankName,
        account_name: input.accountName.trim(),
        account_number: maskedAccountNumber(accountNumber),
      },
    });
    const result: SouthAfricanAccountValidationResult = {
      ...buildBaseResult({
        operation: "validateSouthAfricanAccount",
        idempotencyKey: input.idempotencyKey,
        reference,
        status,
        success: isValid,
        message,
        raw,
      }),
      isValid,
      bankCode,
      bankName,
      accountName: input.accountName.trim(),
      maskedAccountNumber: maskedAccountNumber(accountNumber),
    };
    logOperation("validateSouthAfricanAccount", {
      bankCode,
      maskedAccountNumber: maskedAccountNumber(accountNumber),
      idempotencyKey: input.idempotencyKey,
    }, result);
    return result;
  },

  async initiateTransfer(input: InitiateTransferInput): Promise<TransferResult> {
    assertIdempotencyKey(input.idempotencyKey);
    const amountZar = normalizeAmountZar(input.amountZar);
    const currency = normalizeCurrency(input.currency);
    const outcome = deriveOutcome(
      input.idempotencyKey,
      input.payoutId,
      input.recipientCode,
      input.reason
    );
    const transferReference = stableId(
      "TRFREF",
      `${input.idempotencyKey}|${input.payoutId}|${input.recipientCode}|${amountZar.toFixed(2)}`
    );
    const transferCode = stableId("TRF", transferReference);
    const status: ProviderOperationStatus =
      outcome === "pending" ? "queued" :
        outcome === "failed" ? "failed" :
          "processing";
    const message =
      status === "queued" ? "Mock Paystack transfer queued." :
        status === "failed" ? "Mock Paystack transfer failed." :
          "Mock Paystack transfer initiated.";
    const raw = paystackLikeRaw({
      idempotencyKey: input.idempotencyKey,
      reference: transferReference,
      status,
      message,
      data: {
        transfer_code: transferCode,
        recipient_code: input.recipientCode,
        amount: Math.round(amountZar * 100),
        currency,
        payout_id: input.payoutId,
      },
    });
    const result: TransferResult = {
      ...buildBaseResult({
        operation: "initiateTransfer",
        idempotencyKey: input.idempotencyKey,
        reference: transferReference,
        status,
        success: status !== "failed",
        message,
        raw,
      }),
      payoutId: input.payoutId,
      recipientCode: input.recipientCode,
      transferCode,
      transferReference,
      amountZar,
      currency,
    };
    logOperation("initiateTransfer", {
      payoutId: input.payoutId,
      recipientCode: input.recipientCode,
      amountZar,
      currency,
      idempotencyKey: input.idempotencyKey,
    }, result);
    return result;
  },

  async initiateBulkTransfer(
    input: InitiateBulkTransferInput
  ): Promise<BulkTransferResult> {
    assertIdempotencyKey(input.idempotencyKey);
    const currency = normalizeCurrency(input.currency);
    const batchReference = stableId(
      "BULK",
      `${input.idempotencyKey}|${input.batchId}|${input.transfers.length}|${currency}`
    );

    const transfers = await Promise.all(input.transfers.map((transfer, index) => {
      return this.initiateTransfer({
        payoutId: transfer.payoutId,
        recipientCode: transfer.recipientCode,
        amountZar: transfer.amountZar,
        currency,
        reason: transfer.reason || `bulk_${input.batchId}_${index}`,
        idempotencyKey: stableId(
          "BULKITEM",
          `${input.idempotencyKey}|${input.batchId}|${transfer.payoutId}|${index}`
        ),
        metadata: {
          batchId: input.batchId,
          itemIndex: index,
          ...(input.metadata ?? {}),
        },
        environment: input.environment,
      });
    }));

    const acceptedCount = transfers.filter((item) => item.success).length;
    const status: ProviderOperationStatus =
      acceptedCount === 0 ? "failed" :
        acceptedCount < transfers.length ? "pending" :
          "processing";
    const message =
      status === "failed" ? "Mock Paystack bulk transfer failed." :
        status === "pending" ? "Mock Paystack bulk transfer partially queued." :
          "Mock Paystack bulk transfer initiated.";
    const raw = paystackLikeRaw({
      idempotencyKey: input.idempotencyKey,
      reference: batchReference,
      status,
      message,
      data: {
        batch_id: input.batchId,
        transfer_count: transfers.length,
        accepted_count: acceptedCount,
        currency,
      },
    });
    const result: BulkTransferResult = {
      ...buildBaseResult({
        operation: "initiateBulkTransfer",
        idempotencyKey: input.idempotencyKey,
        reference: batchReference,
        status,
        success: acceptedCount > 0,
        message,
        raw,
      }),
      batchId: input.batchId,
      batchReference,
      transferCount: transfers.length,
      acceptedCount,
      transfers,
    };
    logOperation("initiateBulkTransfer", {
      batchId: input.batchId,
      transferCount: transfers.length,
      acceptedCount,
      idempotencyKey: input.idempotencyKey,
    }, result);
    return result;
  },
};

export function getMockPaystackProvider(): PaymentProvider {
  return mockPaystackProvider;
}
