import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import * as functions from "firebase-functions";
import {onRequest} from "firebase-functions/v2/https";
import {
  processPaymentEventJob,
  type PaymentEventInput,
} from "./paymentEvents";
import {
  verifyWebhookSignature,
  type PaystackWebhookEventName,
} from "./payments/paystackWebhook";
import {getPaystackProvider} from "./payments/paystack";

const REGION = "europe-west1";
const db = admin.firestore();

/**
 * Paystack webhook receiver
 * Handles charge.success, charge.failed, transfer.success, transfer.failed events
 *
 * Setup:
 * 1. Deploy this function
 * 2. Get the webhook URL: https://[region]-[project].cloudfunctions.net/paystackWebhook
 * 3. Configure in Paystack dashboard:
 *    - Go to Settings → Webhooks
 *    - Add URL: https://[region]-[project].cloudfunctions.net/paystackWebhook
 *    - Select events: charge.success, charge.failed, transfer.success, transfer.failed
 * 4. Test with mock webhooks locally using simulateMockPaystackWebhook
 */
export const paystackWebhook = onRequest(
  {region: REGION, cors: true},
  async (request, response) => {
    // Only accept POST
    if (request.method !== "POST") {
      logger.warn("paystack_webhook_invalid_method", {method: request.method});
      response.status(405).json({error: "Method not allowed"});
      return;
    }

    try {
      // Get raw body for signature verification
      const rawBody = request.rawBody || request.body;

      // Get signature header
      const signatureHeader = (request.headers["x-paystack-signature"] ||
        "") as string;

      if (!signatureHeader) {
        logger.warn("paystack_webhook_missing_signature");
        response.status(401).json({error: "Missing signature"});
        return;
      }

      // Verify webhook signature
      const config = functions.config as any;
      const webhookSecret = config.paystack?.webhook_secret;

      if (!webhookSecret) {
        logger.error("paystack_webhook_missing_secret", {
          recommendation:
            "Configure Paystack webhook signing secret with firebase functions:config:set paystack.webhook_secret='your-webhook-secret'",
        });
        response.status(500).json({error: "Webhook secret not configured"});
        return;
      }

      const verificationResult = verifyWebhookSignature({
        rawBody,
        signatureHeader,
        secretKey: webhookSecret,
      });

      if (!verificationResult.valid) {
        logger.warn("paystack_webhook_invalid_signature", {
          expected: verificationResult.expectedSignature,
          received: verificationResult.receivedSignature,
        });
        response.status(401).json({error: "Invalid signature"});
        return;
      }

      // Parse JSON body
      const payload =
        typeof rawBody === "string" ? JSON.parse(rawBody) : rawBody;

      const event = payload.event as PaystackWebhookEventName | undefined;
      const data = payload.data as Record<string, unknown> | undefined;

      if (!event || !data) {
        logger.warn("paystack_webhook_invalid_payload", {
          hasEvent: !!event,
          hasData: !!data,
        });
        response.status(400).json({error: "Invalid payload"});
        return;
      }

      logger.info("paystack_webhook_received", {
        event,
        reference: data.reference,
      });

      // Handle different event types
      await handlePaystackWebhookEvent(event, data);

      // Always return 200 to acknowledge receipt
      response.status(200).json({
        success: true,
        message: "Webhook received",
      });
    } catch (error) {
      logger.error("paystack_webhook_error", {
        error: error instanceof Error ? error.message : String(error),
      });
      // Return 500 to indicate processing error (Paystack will retry)
      response.status(500).json({error: "Internal server error"});
    }
  }
);

/**
 * Handle Paystack webhook event and create/process payment events
 */
async function handlePaystackWebhookEvent(
  event: PaystackWebhookEventName,
  data: Record<string, unknown>
): Promise<void> {
  const reference = String(data.reference || "");
  const status = String(data.status || "");
  const amount = Number(data.amount || 0);

  logger.info("paystack_webhook_processing", {
    event,
    reference,
    status,
  });

  // For charge events, we need to verify before processing
  if (event === "charge.success" || event === "charge.failed") {
    const provider = getPaystackProvider();
    const verificationResult = await provider.verifyTransaction(reference);

    if (!verificationResult.success) {
      logger.warn("paystack_webhook_verification_failed", {
        reference,
        event,
        reason: verificationResult.message,
      });
      throw new Error(
        `Webhook verification failed for reference ${reference}`
      );
    }

    // Check for idempotency - don't process duplicate events
    const eventRef = db.collection("payment_events").doc(reference);
    const existingEvent = await eventRef.get();

    if (existingEvent.exists) {
      logger.info("paystack_webhook_duplicate_event", {
        reference,
        event,
        note: "Duplicate detected, skipping processing",
      });
      return;
    }

    // Map Paystack charge event to payment event
    const paymentEvent: PaymentEventInput = {
      provider: "PAYSTACK",
      adapterKey: "paystack",
      externalEventId: reference,
      eventType:
        event === "charge.success"
          ? "authorization_created"
          : "authorization_reserve_failed",
      paymentRail: "TUTORING",
      authorizationReference: reference,
      providerReference: reference,
      providerStatus: status,
      amountZar: amount / 100, // Convert from kobo
      currency: "ZAR",
      raw: data,
    };

    // Process the payment event
    await processPaymentEventJob(paymentEvent);
  } else if (event === "transfer.success" || event === "transfer.failed") {
    // Handle transfer events
    const eventRef = db.collection("payment_events").doc(reference);
    const existingEvent = await eventRef.get();

    if (existingEvent.exists) {
      logger.info("paystack_webhook_duplicate_transfer_event", {
        reference,
        event,
        note: "Duplicate detected, skipping processing",
      });
      return;
    }

    const paymentEvent: PaymentEventInput = {
      provider: "PAYSTACK",
      adapterKey: "paystack",
      externalEventId: reference,
      eventType:
        event === "transfer.success" ? "transfer_succeeded" : "transfer_failed",
      paymentRail: "TUTORING",
      transferReference: reference,
      providerReference: reference,
      providerStatus: status,
      amountZar: amount / 100,
      currency: "ZAR",
      raw: data,
    };

    await processPaymentEventJob(paymentEvent);
  }

  logger.info("paystack_webhook_processed", {
    event,
    reference,
  });
}
