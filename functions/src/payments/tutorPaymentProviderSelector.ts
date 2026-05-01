import * as functions from "firebase-functions";
import * as logger from "firebase-functions/logger";
import type {TutoringPaymentProvider} from "./tutoringPaymentProvider";
import {getMockTutoringPaymentProvider} from "./mockTutoringPaymentProvider";
import {getPaystackTutoringProvider} from "./paystackTutoringProvider";

/**
 * Determines if we should use the live Paystack tutoring payment provider.
 * Production must use Paystack; non-production must use mock.
 */
function shouldUseLivePaystack(): boolean {
  const config = functions.config as any;
  const hasPaystackSecret = !!config.paystack?.secret;

  if (!hasPaystackSecret) {
    logger.debug("tutoring_provider_selector", {
      message: "Using mock provider because Paystack secret is not configured",
    });
    return false;
  }

  logger.debug("tutoring_provider_selector", {
    message: "Using live Paystack provider",
  });
  return true;
}

/**
 * Get the active TutoringPaymentProvider
 * Returns live Paystack provider if configured, otherwise mock provider
 */
export function getActiveTutoringPaymentProvider(): TutoringPaymentProvider {
  return shouldUseLivePaystack()
    ? getPaystackTutoringProvider()
    : getMockTutoringPaymentProvider();
}

/**
 * Exported for backward compatibility
 */
export {getMockTutoringPaymentProvider, getPaystackTutoringProvider};
