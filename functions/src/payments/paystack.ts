import * as functions from "firebase-functions";
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
  assertIdempotencyKey,
  normalizeAmountZar,
  normalizeCurrency,
} from "./provider";

const PROVIDER_NAME = "PAYSTACK";
const ADAPTER_KEY = "paystack";
const PAYSTACK_API_BASE = "https://api.paystack.co";

// ============================================================================
// HTTP CLIENT
// ============================================================================

interface PaystackApiResponse<T> {
  status: boolean;
  message: string;
  data?: T;
}

interface PaystackTransaction {
  id: number;
  reference: string;
  amount: number;
  paid_at: string | null;
  status: string;
  customer: {
    id: number;
    customer_code: string;
    email: string;
  };
  authorization: {
    authorization_code: string;
    bin: string;
    last4: string;
    exp_month: string;
    exp_year: string;
    card_type: string;
    bank: string;
    country_code: string;
    brand: string;
    reusable: boolean;
    signature: string;
  };
}

let paystackConfigLogged = false;

function getPaystackSecret(): string {
  const config = functions.config as any;
  const secretKey = config.paystack?.secret;

  if (!secretKey) {
    throw new Error(
      "Paystack secret key not configured. Run: firebase functions:config:set paystack.secret='REMOVEDxxxx'"
    );
  }

  if (!paystackConfigLogged) {
    logger.info("paystack_config_loaded", {
      provider: PROVIDER_NAME,
      hasSecret: true,
    });
    paystackConfigLogged = true;
  }

  return secretKey;
}

async function paystackApiCall<T>(
  method: "GET" | "POST",
  path: string,
  body?: Record<string, unknown>
): Promise<PaystackApiResponse<T>> {
  const secretKey = getPaystackSecret();

  const url = `${PAYSTACK_API_BASE}${path}`;
  const headers: Record<string, string> = {
    Authorization: `Bearer ${secretKey}`,
    "Content-Type": "application/json",
  };

  logger.info("paystack_api_call", {
    method,
    path,
    hasBody: !!body,
  });

  try {
    const response = await fetch(url, {
      method,
      headers,
      body: body ? JSON.stringify(body) : undefined,
    });

    const data = (await response.json()) as PaystackApiResponse<T>;

    if (!response.ok) {
      logger.warn("paystack_api_error", {
        method,
        path,
        status: response.status,
        message: data.message,
      });
      throw new Error(
        `Paystack API error [${response.status}]: ${data.message}`
      );
    }

    return data;
  } catch (error) {
    logger.error("paystack_api_exception", {
      method,
      path,
      error: error instanceof Error ? error.message : String(error),
    });
    throw error;
  }
}

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

function buildResult<T extends PaymentProviderResultBase>(
  base: Omit<T, keyof PaymentProviderResultBase> & Partial<PaymentProviderResultBase>
): T {
  return {
    providerName: PROVIDER_NAME,
    adapterKey: ADAPTER_KEY,
    loggedAt: new Date().toISOString(),
    raw: {},
    ...base,
  } as T;
}

function normalizeStatus(status: string): ProviderOperationStatus {
  if (status === "success") return "authorized";
  if (status === "pending") return "pending";
  if (status === "failed") return "failed";
  return "pending";
}

// ============================================================================
// IMPLEMENTATION
// ============================================================================

export const paystackProvider: PaymentProvider = {
  providerName: PROVIDER_NAME,
  adapterKey: ADAPTER_KEY,

  async initializeFirstPreauth(
    input: InitializeFirstPreauthInput
  ): Promise<PreauthResult> {
    assertIdempotencyKey(input.idempotencyKey);
    const amountZar = normalizeAmountZar(input.amountZar);
    const currency = normalizeCurrency(input.currency);

    try {
      const response = await paystackApiCall<PaystackTransaction>(
        "POST",
        "/transaction/initialize",
        {
          reference: input.idempotencyKey,
          email: input.customerEmail,
          amount: Math.round(amountZar * 100), // Convert to kobo
          metadata: {
            bookingId: input.bookingId,
            paymentSessionId: input.paymentSessionId,
            sessionId: input.sessionId || null,
            reason: input.reason || "tutoring_booking",
          },
        }
      );

      if (!response.status || !response.data) {
        return buildResult<PreauthResult>({
          idempotencyKey: input.idempotencyKey,
          success: false,
          status: "failed",
          message: response.message,
          reference: input.idempotencyKey,
          amountZar,
          currency,
          customerCode: "",
          authorizationCode: "",
          authorizationReference: input.idempotencyKey,
          preauthReference: "",
          reusable: false,
        });
      }

      const txn = response.data;
      return buildResult<PreauthResult>({
        idempotencyKey: input.idempotencyKey,
        success: true,
        status: "pending",
        message: "Transaction initialization successful",
        reference: txn.reference,
        amountZar,
        currency,
        customerCode: String(txn.customer?.id || ""),
        authorizationCode: txn.authorization?.authorization_code || "",
        authorizationReference: txn.reference,
        preauthReference: txn.reference,
        reusable: txn.authorization?.reusable || false,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      logger.error("paystack_initializeFirstPreauth_error", {
        idempotencyKey: input.idempotencyKey,
        error: message,
      });

      return buildResult<PreauthResult>({
        idempotencyKey: input.idempotencyKey,
        success: false,
        status: "failed",
        message,
        reference: input.idempotencyKey,
        amountZar,
        currency,
        customerCode: "",
        authorizationCode: "",
        authorizationReference: input.idempotencyKey,
        preauthReference: "",
        reusable: false,
      });
    }
  },

  async reservePreauth(
    input: ReservePreauthInput
  ): Promise<PreauthResult> {
    assertIdempotencyKey(input.idempotencyKey);
    const amountZar = normalizeAmountZar(input.amountZar);
    const currency = normalizeCurrency(input.currency);

    try {
      const response = await paystackApiCall<PaystackTransaction>(
        "POST",
        "/transaction/charge_authorization",
        {
          reference: input.idempotencyKey,
          authorization_code: input.authorizationCode,
          email: input.customerCode,
          amount: Math.round(amountZar * 100),
          metadata: {
            bookingId: input.bookingId,
            paymentSessionId: input.paymentSessionId,
            sessionId: input.sessionId,
            reason: input.reason || "tutoring_reserve",
          },
        }
      );

      if (!response.status || !response.data) {
        return buildResult<PreauthResult>({
          idempotencyKey: input.idempotencyKey,
          success: false,
          status: "failed",
          message: response.message,
          reference: input.idempotencyKey,
          amountZar,
          currency,
          customerCode: input.customerCode || "",
          authorizationCode: input.authorizationCode,
          authorizationReference: input.authorizationReference,
          preauthReference: input.authorizationReference,
          reusable: true,
        });
      }

      const txn = response.data;
      return buildResult<PreauthResult>({
        idempotencyKey: input.idempotencyKey,
        success: true,
        status: normalizeStatus(txn.status),
        message: "Authorization reserve successful",
        reference: txn.reference,
        amountZar,
        currency,
        customerCode: input.customerCode || String(txn.customer?.id || ""),
        authorizationCode: input.authorizationCode,
        authorizationReference: input.authorizationReference,
        preauthReference: txn.reference,
        reusable: true,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      logger.error("paystack_reservePreauth_error", {
        idempotencyKey: input.idempotencyKey,
        error: message,
      });

      return buildResult<PreauthResult>({
        idempotencyKey: input.idempotencyKey,
        success: false,
        status: "failed",
        message,
        reference: input.idempotencyKey,
        amountZar,
        currency,
        customerCode: input.customerCode || "",
        authorizationCode: input.authorizationCode,
        authorizationReference: input.authorizationReference,
        preauthReference: input.authorizationReference,
        reusable: true,
      });
    }
  },

  async capturePreauth(
    input: CapturePreauthInput
  ): Promise<CaptureResult> {
    assertIdempotencyKey(input.idempotencyKey);
    const amountZar = normalizeAmountZar(input.amountZar);
    const currency = normalizeCurrency(input.currency);

    try {
      // Paystack doesn't have a partial debit, so we capture the full amount
      const response = await paystackApiCall<PaystackTransaction>(
        "POST",
        "/transaction/charge_authorization",
        {
          reference: input.idempotencyKey,
          authorization_code: input.authorizationReference,
          amount: Math.round(amountZar * 100),
          metadata: {
            bookingId: input.bookingId,
            paymentSessionId: input.paymentSessionId,
            sessionId: input.sessionId,
            reason: "tutoring_capture",
          },
        }
      );

      if (!response.status || !response.data) {
        return buildResult<CaptureResult>({
          idempotencyKey: input.idempotencyKey,
          success: false,
          status: "failed",
          message: response.message,
          reference: input.idempotencyKey,
          amountZar,
          currency,
          authorizationReference: input.authorizationReference,
          captureReference: input.idempotencyKey,
        });
      }

      const txn = response.data;
      return buildResult<CaptureResult>({
        idempotencyKey: input.idempotencyKey,
        success: txn.status === "success",
        status: normalizeStatus(txn.status),
        message: "Capture successful",
        reference: txn.reference,
        amountZar,
        currency,
        authorizationReference: input.authorizationReference,
        captureReference: txn.reference,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      logger.error("paystack_capturePreauth_error", {
        idempotencyKey: input.idempotencyKey,
        error: message,
      });

      return buildResult<CaptureResult>({
        idempotencyKey: input.idempotencyKey,
        success: false,
        status: "failed",
        message,
        reference: input.idempotencyKey,
        amountZar,
        currency,
        authorizationReference: input.authorizationReference,
        captureReference: input.idempotencyKey,
      });
    }
  },

  async releasePreauth(
    input: ReleasePreauthInput
  ): Promise<ReleaseResult> {
    assertIdempotencyKey(input.idempotencyKey);
    const amountZar = normalizeAmountZar(input.amountZar);
    const currency = normalizeCurrency(input.currency);

    // Paystack doesn't provide a dedicated void/release endpoint
    // Log the request but don't fail - treat as successful no-op
    logger.warn("paystack_releasePreauth_no_endpoint", {
      idempotencyKey: input.idempotencyKey,
      authorizationReference: input.authorizationReference,
      note: "Paystack does not expose a public void/release endpoint",
    });

    return buildResult<ReleaseResult>({
      idempotencyKey: input.idempotencyKey,
      success: true,
      status: "released",
      message:
        "Release request noted (Paystack has no public void endpoint)",
      reference: input.idempotencyKey,
      amountZar,
      currency,
      authorizationReference: input.authorizationReference,
      releaseReference: input.idempotencyKey,
    });
  },

  async verifyTransaction(
    reference: string
  ): Promise<TransactionVerificationResult> {
    try {
      const response = await paystackApiCall<PaystackTransaction>(
        "GET",
        `/transaction/verify/${reference}`
      );

      if (!response.status || !response.data) {
        return buildResult<TransactionVerificationResult>({
          idempotencyKey: `verify_${reference}`,
          success: false,
          status: "failed",
          message: response.message,
          reference,
          transactionStatus: "not_found",
          authorizationReference: null,
          amountZar: null,
          currency: null,
        });
      }

      const txn = response.data;
      const txnStatus =
        txn.status === "success"
          ? "success"
          : txn.status === "pending"
            ? "pending"
            : "failed";

      return buildResult<TransactionVerificationResult>({
        idempotencyKey: `verify_${reference}`,
        success: txnStatus === "success",
        status: normalizeStatus(txn.status),
        message: `Transaction verification: ${txn.status}`,
        reference: txn.reference,
        transactionStatus: txnStatus,
        authorizationReference: txn.authorization?.authorization_code || null,
        amountZar: txn.amount ? txn.amount / 100 : null,
        currency: "ZAR",
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      logger.error("paystack_verifyTransaction_error", {
        reference,
        error: message,
      });

      return buildResult<TransactionVerificationResult>({
        idempotencyKey: `verify_${reference}`,
        success: false,
        status: "failed",
        message,
        reference,
        transactionStatus: "failed",
        authorizationReference: null,
        amountZar: null,
        currency: null,
      });
    }
  },

  async createTransferRecipient(
    input: CreateTransferRecipientInput
  ): Promise<TransferRecipientResult> {
    assertIdempotencyKey(input.idempotencyKey);

    try {
      interface TransferRecipientResponse {
        id: number;
        recipient_code: string;
        domain: string;
        account_number: string;
        account_name: string;
        bank: {
          id: number;
          name: string;
          code: string;
        };
        currency: string;
      }

      const response = await paystackApiCall<TransferRecipientResponse>(
        "POST",
        "/transferrecipient",
        {
          type: "nuban",
          name: input.accountName,
          account_number: input.accountNumber,
          bank_code: input.bankCode,
          currency: input.currency || "ZAR",
          metadata: {
            tutorId: input.tutorId,
            idempotencyKey: input.idempotencyKey,
          },
        }
      );

      if (!response.status || !response.data) {
        return buildResult<TransferRecipientResult>({
          idempotencyKey: input.idempotencyKey,
          success: false,
          status: "failed",
          message: response.message,
          reference: input.idempotencyKey,
          recipientCode: "",
          recipientReference: "",
          accountName: input.accountName,
          maskedAccountNumber: `****${input.accountNumber.slice(-4)}`,
          bankCode: input.bankCode,
          currency: input.currency || "ZAR",
        });
      }

      const recipient = response.data;
      return buildResult<TransferRecipientResult>({
        idempotencyKey: input.idempotencyKey,
        success: true,
        status: "validated",
        message: "Transfer recipient created successfully",
        reference: recipient.recipient_code,
        recipientCode: recipient.recipient_code,
        recipientReference: String(recipient.id),
        accountName: recipient.account_name,
        maskedAccountNumber: `****${recipient.account_number.slice(-4)}`,
        bankCode: input.bankCode,
        currency: recipient.currency,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      logger.error("paystack_createTransferRecipient_error", {
        idempotencyKey: input.idempotencyKey,
        tutorId: input.tutorId,
        error: message,
      });

      return buildResult<TransferRecipientResult>({
        idempotencyKey: input.idempotencyKey,
        success: false,
        status: "failed",
        message,
        reference: input.idempotencyKey,
        recipientCode: "",
        recipientReference: "",
        accountName: input.accountName,
        maskedAccountNumber: `****${input.accountNumber.slice(-4)}`,
        bankCode: input.bankCode,
        currency: input.currency || "ZAR",
      });
    }
  },

  async validateSouthAfricanAccount(
    input: ValidateSouthAfricanAccountInput
  ): Promise<SouthAfricanAccountValidationResult> {
    assertIdempotencyKey(input.idempotencyKey);

    try {
      interface BankValidationResponse {
        account_name: string;
        account_number: string;
        bank_code: string;
      }

      const response = await paystackApiCall<BankValidationResponse>(
        "POST",
        "/bank/validate",
        {
          account_name: input.accountName,
          account_number: input.accountNumber,
          bank_code: input.bankCode,
        }
      );

      if (!response.status || !response.data) {
        return buildResult<SouthAfricanAccountValidationResult>({
          idempotencyKey: input.idempotencyKey,
          success: false,
          status: "invalid",
          message: response.message,
          reference: input.idempotencyKey,
          isValid: false,
          bankCode: input.bankCode,
          bankName: "Unknown",
          accountName: input.accountName,
          maskedAccountNumber: `****${input.accountNumber.slice(-4)}`,
        });
      }

      const validation = response.data;
      return buildResult<SouthAfricanAccountValidationResult>({
        idempotencyKey: input.idempotencyKey,
        success: true,
        status: "validated",
        message: "Account validation successful",
        reference: input.idempotencyKey,
        isValid: true,
        bankCode: validation.bank_code,
        bankName: `Bank ${validation.bank_code}`,
        accountName: validation.account_name,
        maskedAccountNumber: `****${validation.account_number.slice(-4)}`,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      logger.error("paystack_validateSouthAfricanAccount_error", {
        idempotencyKey: input.idempotencyKey,
        error: message,
      });

      return buildResult<SouthAfricanAccountValidationResult>({
        idempotencyKey: input.idempotencyKey,
        success: false,
        status: "invalid",
        message,
        reference: input.idempotencyKey,
        isValid: false,
        bankCode: input.bankCode,
        bankName: "Unknown",
        accountName: input.accountName,
        maskedAccountNumber: `****${input.accountNumber.slice(-4)}`,
      });
    }
  },

  async initiateTransfer(
    input: InitiateTransferInput
  ): Promise<TransferResult> {
    assertIdempotencyKey(input.idempotencyKey);
    const amountZar = normalizeAmountZar(input.amountZar);
    const currency = normalizeCurrency(input.currency);

    try {
      interface TransferResponse {
        id: number;
        reference: string;
        status: string;
        recipient: {
          id: number;
          recipient_code: string;
        };
        amount: number;
      }

      const response = await paystackApiCall<TransferResponse>("POST", "/transfer", {
        source: "balance",
        recipient: input.recipientCode,
        amount: Math.round(amountZar * 100),
        reference: input.idempotencyKey,
        reason: input.reason || "tutor_payout",
        metadata: {
          payoutId: input.payoutId,
        },
      });

      if (!response.status || !response.data) {
        return buildResult<TransferResult>({
          idempotencyKey: input.idempotencyKey,
          success: false,
          status: "failed",
          message: response.message,
          reference: input.idempotencyKey,
          payoutId: input.payoutId,
          recipientCode: input.recipientCode,
          transferCode: "",
          transferReference: input.idempotencyKey,
          amountZar,
          currency,
        });
      }

      const transfer = response.data;
      return buildResult<TransferResult>({
        idempotencyKey: input.idempotencyKey,
        success: true,
        status: normalizeStatus(transfer.status),
        message: "Transfer initiated successfully",
        reference: transfer.reference,
        payoutId: input.payoutId,
        recipientCode: input.recipientCode,
        transferCode: String(transfer.id),
        transferReference: transfer.reference,
        amountZar,
        currency,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      logger.error("paystack_initiateTransfer_error", {
        idempotencyKey: input.idempotencyKey,
        payoutId: input.payoutId,
        error: message,
      });

      return buildResult<TransferResult>({
        idempotencyKey: input.idempotencyKey,
        success: false,
        status: "failed",
        message,
        reference: input.idempotencyKey,
        payoutId: input.payoutId,
        recipientCode: input.recipientCode,
        transferCode: "",
        transferReference: input.idempotencyKey,
        amountZar,
        currency,
      });
    }
  },

  async initiateBulkTransfer(
    input: InitiateBulkTransferInput
  ): Promise<BulkTransferResult> {
    assertIdempotencyKey(input.idempotencyKey);
    const currency = normalizeCurrency(input.currency);
    const transfers: TransferResult[] = [];

    try {
      // Paystack bulk transfer endpoint
      interface BulkTransferResponse {
        id: number;
        reference: string;
        transfers: Array<{
          id: number;
          reference: string;
          recipient: number;
          amount: number;
          status: string;
        }>;
      }

      const bulkData = input.transfers.map((t) => ({
        recipient: t.recipientCode,
        amount: Math.round(normalizeAmountZar(t.amountZar) * 100),
        reference: `${input.idempotencyKey}_${t.payoutId}`,
      }));

      const response = await paystackApiCall<BulkTransferResponse>(
        "POST",
        "/transfer/bulk",
        {
          source: "balance",
          transfers: bulkData,
          metadata: {
            batchId: input.batchId,
          },
        }
      );

      if (!response.status || !response.data) {
        logger.warn("paystack_initiateBulkTransfer_partial_failure", {
          idempotencyKey: input.idempotencyKey,
          message: response.message,
        });
      } else {
        // Map results
        for (let i = 0; i < input.transfers.length && i < response.data.transfers.length; i++) {
          const srcTransfer = input.transfers[i];
          const resultTransfer = response.data.transfers[i];
          const amountZar = normalizeAmountZar(srcTransfer.amountZar);

          transfers.push(
            buildResult<TransferResult>({
              idempotencyKey: `${input.idempotencyKey}_${srcTransfer.payoutId}`,
              success: resultTransfer.status === "success",
              status: normalizeStatus(resultTransfer.status),
              message: `Transfer ${resultTransfer.status}`,
              reference: resultTransfer.reference,
              payoutId: srcTransfer.payoutId,
              recipientCode: srcTransfer.recipientCode,
              transferCode: String(resultTransfer.id),
              transferReference: resultTransfer.reference,
              amountZar,
              currency,
            })
          );
        }
      }

      return buildResult<BulkTransferResult>({
        idempotencyKey: input.idempotencyKey,
        success: transfers.length > 0,
        status: transfers.some((t) => t.success) ? "processing" : "failed",
        message: `Bulk transfer initiated: ${transfers.length} transfers`,
        reference: input.idempotencyKey,
        batchId: input.batchId,
        batchReference: input.idempotencyKey,
        transferCount: input.transfers.length,
        acceptedCount: transfers.filter((t) => t.success).length,
        transfers,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      logger.error("paystack_initiateBulkTransfer_error", {
        idempotencyKey: input.idempotencyKey,
        batchId: input.batchId,
        error: message,
      });

      return buildResult<BulkTransferResult>({
        idempotencyKey: input.idempotencyKey,
        success: false,
        status: "failed",
        message,
        reference: input.idempotencyKey,
        batchId: input.batchId,
        batchReference: input.idempotencyKey,
        transferCount: input.transfers.length,
        acceptedCount: 0,
        transfers,
      });
    }
  },
};

export function getPaystackProvider(): PaymentProvider {
  return paystackProvider;
}
