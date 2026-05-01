import {createHmac, timingSafeEqual} from "node:crypto";
import * as logger from "firebase-functions/logger";

export type PaystackWebhookEventName =
  | "charge.success"
  | "charge.failed"
  | "transfer.success"
  | "transfer.failed";

export interface VerifyPaystackWebhookSignatureInput {
  rawBody: string | Buffer;
  signatureHeader: string;
  secretKey: string;
}

export interface VerifyPaystackWebhookSignatureResult {
  valid: boolean;
  algorithm: "HMAC-SHA512";
  expectedSignature: string;
  receivedSignature: string;
}

export const PAYSTACK_WEBHOOK_INTEGRATION_NOTES = {
  signatureHeader: "x-paystack-signature",
  verificationAlgorithm: "HMAC-SHA512",
  events: {
    initialPreauthSuccess:
      "TODO(paystack-live): map Paystack charge.success into generic authorization_created ingestion here.",
    reservePreauthSuccess:
      "TODO(paystack-live): map Paystack charge.success for reusable authorization top-ups into authorization_reserved here.",
    reservePreauthFailure:
      "TODO(paystack-live): map Paystack charge.failed into authorization_reserve_failed here.",
    captureSuccess:
      "TODO(paystack-live): map the chosen final capture success event into capture_succeeded here.",
    captureFailure:
      "TODO(paystack-live): map the chosen final capture failure event into capture_failed here.",
    transferSuccess:
      "TODO(paystack-live): map Paystack transfer.success into transfer_succeeded here.",
    transferFailure:
      "TODO(paystack-live): map Paystack transfer.failed into transfer_failed here.",
  },
  endpoints: {
    webhookReceiver:
      "TODO(paystack-live): wire the future HTTPS webhook receiver to the Paystack dashboard webhook URL.",
    verifyTransactionFallback:
      "TODO(paystack-live): use GET /transaction/verify/:reference as a reconciliation fallback when webhook delivery is delayed.",
    verifyTransferFallback:
      "TODO(paystack-live): use the Paystack transfer verification path chosen in the live payout pass as a reconciliation fallback when webhook delivery is delayed.",
  },
} as const;

export function verifyWebhookSignature(
  input: VerifyPaystackWebhookSignatureInput
): VerifyPaystackWebhookSignatureResult {
  const bodyBuffer = Buffer.isBuffer(input.rawBody) ?
    input.rawBody :
    Buffer.from(input.rawBody, "utf8");
  const receivedSignature = (input.signatureHeader || "").trim().toLowerCase();
  const expectedSignature = createHmac("sha512", input.secretKey || "")
    .update(bodyBuffer)
    .digest("hex")
    .toLowerCase();

  const valid =
    receivedSignature.length > 0 &&
    expectedSignature.length === receivedSignature.length &&
    timingSafeEqual(
      Buffer.from(expectedSignature, "utf8"),
      Buffer.from(receivedSignature, "utf8")
    );

  logger.info("payments.paystackWebhook.signature_checked", {
    valid,
    signatureHeaderPresent: receivedSignature.length > 0,
    algorithm: "HMAC-SHA512",
    notes: PAYSTACK_WEBHOOK_INTEGRATION_NOTES.endpoints.webhookReceiver,
  });

  return {
    valid,
    algorithm: "HMAC-SHA512",
    expectedSignature,
    receivedSignature,
  };
}

export function assertWebhookStubNotWired(operation: string): never {
  logger.warn("payments.paystackWebhook.stub_not_wired", {
    operation,
    notes: PAYSTACK_WEBHOOK_INTEGRATION_NOTES,
  });
  throw new Error(
    `TODO(paystack-live): ${operation} is documented but not wired into the tutoring payment flow yet.`
  );
}
