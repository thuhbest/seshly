import {
  type CallableOptions,
  type CallableRequest,
  type CallableResponse,
  type FunctionsErrorCode,
  HttpsError,
  onCall as firebaseOnCall,
} from "firebase-functions/v2/https";

import {
  type CallableRuntimePolicy,
  enforceCallableRuntimePolicy,
} from "./security";

const ENFORCE_APP_CHECK = process.env.FUNCTIONS_ENFORCE_APP_CHECK === "true";

const ALLOW_ANONYMOUS = new Set([
  "createGuestTutoringCustomer",
  "updateGuestTutoringCustomer",
  "createTutoringBooking",
  "setupTutoringPaymentMethod",
  "saveMockTutoringPaymentMethod",
  "startTutoringPreauth",
  "startSession",
  "endSession",
]);

const RATE_LIMIT_POLICIES: Record<string, CallableRuntimePolicy> = {
  createTutoringBooking: {allowAnonymous: true, requireVerifiedEmail: false, rateLimitProfile: "payment"},
  createGuestTutoringCustomer: {allowAnonymous: true, requireVerifiedEmail: false, rateLimitProfile: "auth"},
  updateGuestTutoringCustomer: {allowAnonymous: true, requireVerifiedEmail: false, rateLimitProfile: "auth"},
  setupTutoringPaymentMethod: {allowAnonymous: true, requireVerifiedEmail: false, rateLimitProfile: "payment"},
  saveMockTutoringPaymentMethod: {allowAnonymous: true, requireVerifiedEmail: false, rateLimitProfile: "payment"},
  startTutoringPreauth: {allowAnonymous: true, requireVerifiedEmail: false, rateLimitProfile: "payment"},
  respondToTutoringBooking: {rateLimitProfile: "payment"},
  processPaymentEvent: {rateLimitProfile: "payment"},
  startPaymentAuthorization: {rateLimitProfile: "payment"},
  requestTutorPayout: {rateLimitProfile: "payment"},
  approveTutorPayout: {rateLimitProfile: "admin"},
  rejectTutorPayout: {rateLimitProfile: "admin"},
  markTutorPayoutProcessing: {rateLimitProfile: "admin"},
  markTutorPayoutPaid: {rateLimitProfile: "admin"},
  markTutorPayoutFailed: {rateLimitProfile: "admin"},
  retryTutorPayoutBatch: {rateLimitProfile: "admin"},
  startSession: {allowAnonymous: true, requireVerifiedEmail: false, rateLimitProfile: "payment"},
  endSession: {allowAnonymous: true, requireVerifiedEmail: false, rateLimitProfile: "payment"},
  purchaseSeshCredits: {rateLimitProfile: "payment"},
  purchaseSeshMinutes: {rateLimitProfile: "payment"},
  purchaseStudyVaultResource: {rateLimitProfile: "payment"},
  activateGoldTickSubscription: {rateLimitProfile: "payment"},
  activateOrganizationSubscription: {rateLimitProfile: "payment"},
  requestTutorPayoutSecure: {rateLimitProfile: "payment"},
  submitTutorApplication: {rateLimitProfile: "writeHeavy"},
  reviewTutorApplication: {rateLimitProfile: "admin"},
  approveTutorApplication: {rateLimitProfile: "admin"},
  rejectTutorApplication: {rateLimitProfile: "admin"},
  suspendTutor: {rateLimitProfile: "admin"},
  restoreTutor: {rateLimitProfile: "admin"},
  setTutorPayoutReadiness: {rateLimitProfile: "admin"},
  refreshTutorPayoutDashboardAggregates: {rateLimitProfile: "admin"},
  listTutorsDueForMondayPayout: {rateLimitProfile: "admin"},
  getTutorPayoutTotalsByWeek: {rateLimitProfile: "admin"},
  listBlockedTutorPayoutProfiles: {rateLimitProfile: "admin"},
  listFailedTutorPayoutAttempts: {rateLimitProfile: "admin"},
  listDisputedTutorPayables: {rateLimitProfile: "admin"},
  getTutorPayoutHistoryByTutor: {rateLimitProfile: "admin"},
  exportTutorPayoutData: {rateLimitProfile: "admin"},
  getSupportedBanksForTutorPayout: {rateLimitProfile: "default"},
  submitTutorPayoutDetails: {rateLimitProfile: "payment"},
  verifyTutorPayoutProfile: {rateLimitProfile: "payment"},
};

function deriveActionName(request: CallableRequest): string {
  const rawPath =
    request.rawRequest.path ||
    request.rawRequest.originalUrl ||
    request.rawRequest.url ||
    "";
  const withoutQuery = rawPath.split("?")[0];
  const segments = withoutQuery.split("/").filter((segment) => segment.length > 0);
  return segments[segments.length - 1] || "callable";
}

function sanitizeError(error: HttpsError): HttpsError {
  if ([
    "invalid-argument",
    "failed-precondition",
    "permission-denied",
    "unauthenticated",
    "resource-exhausted",
    "not-found",
    "already-exists",
  ].includes(error.code)) {
    return error;
  }
  return new HttpsError("internal", "Something went wrong. Please try again.");
}

function resolvePolicy(actionName: string): CallableRuntimePolicy {
  const basePolicy = RATE_LIMIT_POLICIES[actionName] ?? {rateLimitProfile: "default"};
  return {
    requireAuth: true,
    requireVerifiedEmail: !ALLOW_ANONYMOUS.has(actionName),
    allowAnonymous: ALLOW_ANONYMOUS.has(actionName),
    ...basePolicy,
  };
}

export function onCall<T = any, Return = any | Promise<any>, Stream = unknown>(
  opts: CallableOptions<T>,
  handler: (request: CallableRequest<T>, response?: CallableResponse<Stream>) => Return
): Return extends Promise<unknown> ? Return : Promise<Return>;
export function onCall<T = any, Return = any | Promise<any>, Stream = unknown>(
  handler: (request: CallableRequest<T>, response?: CallableResponse<Stream>) => Return
): Return extends Promise<unknown> ? Return : Promise<Return>;
export function onCall<T = any, Return = any | Promise<any>, Stream = unknown>(
  optsOrHandler:
    | CallableOptions<T>
    | ((request: CallableRequest<T>, response?: CallableResponse<Stream>) => Return),
  maybeHandler?: (request: CallableRequest<T>, response?: CallableResponse<Stream>) => Return
) {
  const opts = typeof optsOrHandler === "function" ?
    {} as CallableOptions<T> :
    optsOrHandler;
  const handler = typeof optsOrHandler === "function" ?
    optsOrHandler :
    maybeHandler;

  if (!handler) {
    throw new Error("Callable handler is required.");
  }

  const resolvedHandler =
    handler as (
      request: CallableRequest<T>,
      response?: CallableResponse<Stream>
    ) => Return | Promise<Return>;
  const wrappedHandler = async (
    request: CallableRequest<T>,
    response?: CallableResponse<Stream>
  ): Promise<Awaited<Return>> => {
    const actionName = deriveActionName(request);
    await enforceCallableRuntimePolicy(
      actionName,
      request,
      resolvePolicy(actionName)
    );

    try {
      return await Promise.resolve(
        resolvedHandler(request, response)
      ) as Awaited<Return>;
    } catch (error) {
      if (error instanceof HttpsError) {
        throw sanitizeError(error);
      }
      throw new HttpsError("internal", "Something went wrong. Please try again.");
    }
  };

  return firebaseOnCall<T, Promise<Awaited<Return>>, Stream>(
    {
      enforceAppCheck: ENFORCE_APP_CHECK,
      ...opts,
    },
    wrappedHandler
  ) as unknown as Return extends Promise<unknown> ? Return : Promise<Return>;
}

export {HttpsError};
export type {FunctionsErrorCode};
