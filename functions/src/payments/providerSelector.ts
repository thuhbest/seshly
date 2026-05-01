import * as functions from "firebase-functions";
import * as logger from "firebase-functions/logger";
import type {PaymentProvider} from "./provider";
import {getMockPaystackProvider} from "./mockPaystack";
import {getPaystackProvider} from "./paystack";

/**
 * Determines if we should use the live Paystack provider.
 * Production must use Paystack; non-production must use mock.
 */
function shouldUseLivePaystack(): boolean {
  const config = functions.config as any;
  const hasPaystackSecret = !!config.paystack?.secret;

  if (!hasPaystackSecret) {
    logger.info("provider_selector", {
      message: "Using mock provider because Paystack secret is not configured",
    });
    return false;
  }

  logger.info("provider_selector", {
    message: "Using live Paystack provider",
  });
  return true;
}

/**
 * Get the active PaymentProvider for tutor payouts and payout onboarding
 */
export function getActivePaymentProvider(): PaymentProvider {
  return shouldUseLivePaystack() ? getPaystackProvider() : getMockPaystackProvider();
}

export {getMockPaystackProvider, getPaystackProvider};
