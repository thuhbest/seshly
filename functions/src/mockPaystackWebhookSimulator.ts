import {createHash} from "node:crypto";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {HttpsError, onCall} from "./callable";
import {
  processPaymentEventJob,
  type PaymentEventInput,
  type PaymentEventProcessResult,
} from "./paymentEvents";
import {assertPlatformAdmin} from "./tutorApprovalState";

const REGION = "europe-west1";
const PROVIDER = "MOCK_PAYSTACK";
const ADAPTER_KEY = "mock_paystack";
const TUTORING_RAIL = "TUTORING";
const DEFAULT_CURRENCY = "ZAR";
const BASE_TIME_MS = Date.UTC(2025, 0, 1, 0, 0, 0);

export type MockPaystackWebhookScenario =
  | "initial_preauthorization_success"
  | "reserve_preauthorization_success"
  | "reserve_preauthorization_failure"
  | "capture_success"
  | "capture_failure"
  | "transfer_success"
  | "transfer_failure";

export interface MockPaystackWebhookPayload {
  id: string;
  event: string;
  livemode: false;
  createdAt: string;
  provider: typeof PROVIDER;
  adapterKey: typeof ADAPTER_KEY;
  data: {
    id: string;
    reference: string;
    status: "success" | "failed";
    amount: number;
    currency: string;
    paid_at: string;
    gateway_response: string;
    domain: "test";
    metadata: Record<string, unknown>;
    customer?: {
      customer_code: string;
      email?: string | null;
    };
    authorization?: {
      authorization_code: string;
      authorization_reference: string;
      reusable: boolean;
    };
    transfer_code?: string | null;
    recipient?: {
      recipient_code: string;
    } | null;
    failure_reason?: string | null;
  };
}

export interface SimulateMockPaystackWebhookInput {
  scenario?: unknown;
  seed?: unknown;
  hydrateFromFirestore?: unknown;
  bookingId?: unknown;
  paymentSessionId?: unknown;
  sessionId?: unknown;
  authorizationId?: unknown;
  captureId?: unknown;
  payoutId?: unknown;
  payoutBatchId?: unknown;
  tutorId?: unknown;
  amountZar?: unknown;
  currency?: unknown;
  recipientCode?: unknown;
  reason?: unknown;
}

interface NormalizedSimulationInput {
  scenario: MockPaystackWebhookScenario;
  seed: string;
  bookingId: string;
  paymentSessionId: string;
  sessionId: string;
  authorizationId: string;
  captureId: string;
  payoutId: string;
  payoutBatchId: string;
  tutorId: string;
  amountZar: number;
  currency: string;
  recipientCode: string;
  reason: string | null;
}

interface FirestoreSimulationContext {
  bookingId: string;
  paymentSessionId: string;
  sessionId: string;
  authorizationId: string;
  payoutId: string;
  payoutBatchId: string;
  tutorId: string;
  amountZar: number;
  currency: string;
  recipientCode: string;
  authorizationReference: string;
  captureId: string;
  captureReference: string;
  transferReference: string;
  transferCode: string;
}

function getDb(): FirebaseFirestore.Firestore {
  return admin.firestore();
}

function toTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function toUpper(value: unknown): string {
  return toTrimmedString(value).toUpperCase();
}

function asMoney(value: unknown, fallback = 0): number {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.round((value + Number.EPSILON) * 100) / 100;
  }
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return Math.round((parsed + Number.EPSILON) * 100) / 100;
    }
  }
  return fallback;
}

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

function requireScenario(
  value: unknown
): MockPaystackWebhookScenario {
  const normalized = toTrimmedString(value).toLowerCase();
  switch (normalized) {
  case "initial_preauthorization_success":
  case "reserve_preauthorization_success":
  case "reserve_preauthorization_failure":
  case "capture_success":
  case "capture_failure":
  case "transfer_success":
  case "transfer_failure":
    return normalized;
  default:
    throw new HttpsError(
      "invalid-argument",
      "scenario is required and must be a supported mock webhook type."
    );
  }
}

function normalizeCurrency(value: unknown): string {
  return toUpper(value) || DEFAULT_CURRENCY;
}

function baseSeed(scenario: MockPaystackWebhookScenario, seed: string): string {
  return `${scenario}|${seed || "default"}`;
}

async function loadSimulationContext(
  input: SimulateMockPaystackWebhookInput,
  scenario: MockPaystackWebhookScenario,
  seed: string
): Promise<FirestoreSimulationContext> {
  const hydrateFromFirestore = input.hydrateFromFirestore === true;
  const authorizationIdInput = toTrimmedString(input.authorizationId);
  const payoutIdInput = toTrimmedString(input.payoutId);
  const authorizationSnapPromise =
    hydrateFromFirestore && admin.apps.length > 0 && authorizationIdInput ?
      getDb().collection("payment_authorizations").doc(authorizationIdInput).get() :
      Promise.resolve(null);
  const payoutSnapPromise =
    hydrateFromFirestore && admin.apps.length > 0 && payoutIdInput ?
      getDb().collection("tutor_payouts").doc(payoutIdInput).get() :
      Promise.resolve(null);
  const [authorizationSnap, payoutSnap] = await Promise.all([
    authorizationSnapPromise,
    payoutSnapPromise,
  ]);
  const authorizationData = authorizationSnap?.data() ?? {};
  const payoutData = payoutSnap?.data() ?? {};
  const authProvider = (authorizationData.provider ?? {}) as Record<string, unknown>;
  const payoutProvider = (payoutData.provider ?? {}) as Record<string, unknown>;
  const basis = baseSeed(scenario, seed);

  return {
    bookingId:
      toTrimmedString(input.bookingId) ||
      toTrimmedString(authorizationData.bookingId) ||
      stableId("booking", `${basis}|booking`),
    paymentSessionId:
      toTrimmedString(input.paymentSessionId) ||
      toTrimmedString(
        authorizationData.paymentIntentId ?? authorizationData.paymentSessionId
      ) ||
      stableId("payment", `${basis}|payment_session`),
    sessionId:
      toTrimmedString(input.sessionId) ||
      toTrimmedString(authorizationData.sessionId) ||
      stableId("session", `${basis}|session`),
    authorizationId:
      authorizationIdInput ||
      toTrimmedString(authorizationData.authorizationId) ||
      stableId("auth", `${basis}|authorization`),
    payoutId:
      payoutIdInput ||
      toTrimmedString(payoutData.payoutId) ||
      stableId("payout", `${basis}|payout`),
    payoutBatchId:
      toTrimmedString(input.payoutBatchId) ||
      toTrimmedString(payoutData.batchId ?? payoutData.payoutBatchId) ||
      stableId("batch", `${basis}|payout_batch`),
    tutorId:
      toTrimmedString(input.tutorId) ||
      toTrimmedString(authorizationData.tutorId) ||
      toTrimmedString(payoutData.tutorId) ||
      stableId("tutor", `${basis}|tutor`),
    amountZar:
      asMoney(input.amountZar, 0) ||
      asMoney(authorizationData.amountZar, 0) ||
      asMoney(payoutData.amountZar ?? payoutData.netAmountZar, 0) ||
      240,
    currency:
      normalizeCurrency(input.currency) ||
      normalizeCurrency(authorizationData.currency) ||
      normalizeCurrency(payoutData.currency),
    recipientCode:
      toTrimmedString(input.recipientCode) ||
      toTrimmedString(payoutData.recipientCode) ||
      stableId("RCP", `${basis}|recipient`),
    authorizationReference:
      toTrimmedString(authProvider.authorizationReference) ||
      stableId("PAUTH", `${basis}|authorization_reference`),
    captureId:
      toTrimmedString(input.captureId) ||
      stableId("capture", `${basis}|capture`),
    captureReference: stableId("CAP", `${basis}|capture_reference`),
    transferReference:
      toTrimmedString(payoutData.transferReference) ||
      toTrimmedString(payoutProvider.transferReference) ||
      stableId("TRFREF", `${basis}|transfer_reference`),
    transferCode:
      toTrimmedString(payoutData.transferCode) ||
      toTrimmedString(payoutProvider.transferCode) ||
      stableId("TRF", `${basis}|transfer_code`),
  };
}

function ensureRequiredContext(
  scenario: MockPaystackWebhookScenario,
  normalized: Partial<NormalizedSimulationInput>
): void {
  const requireField = (fieldName: keyof NormalizedSimulationInput) => {
    const value = normalized[fieldName];
    if (typeof value === "string" && value.trim()) {
      return;
    }
    if (typeof value === "number" && Number.isFinite(value) && value > 0) {
      return;
    }
    throw new HttpsError(
      "failed-precondition",
      `${fieldName} is required for ${scenario}.`
    );
  };

  switch (scenario) {
  case "initial_preauthorization_success":
    requireField("bookingId");
    requireField("paymentSessionId");
    requireField("authorizationId");
    requireField("amountZar");
    return;
  case "reserve_preauthorization_success":
  case "reserve_preauthorization_failure":
    requireField("bookingId");
    requireField("paymentSessionId");
    requireField("sessionId");
    requireField("authorizationId");
    requireField("amountZar");
    return;
  case "capture_success":
  case "capture_failure":
    requireField("bookingId");
    requireField("paymentSessionId");
    requireField("sessionId");
    requireField("authorizationId");
    requireField("captureId");
    requireField("amountZar");
    return;
  case "transfer_success":
  case "transfer_failure":
    requireField("payoutId");
    requireField("tutorId");
    requireField("amountZar");
    return;
  }
}

export async function normalizeSimulationInput(
  input: SimulateMockPaystackWebhookInput
): Promise<NormalizedSimulationInput> {
  const scenario = requireScenario(input.scenario);
  const seed = toTrimmedString(input.seed) || "default";
  const context = await loadSimulationContext(input, scenario, seed);
  const normalized: NormalizedSimulationInput = {
    scenario,
    seed,
    bookingId: context.bookingId,
    paymentSessionId: context.paymentSessionId,
    sessionId: context.sessionId,
    authorizationId: context.authorizationId,
    captureId: context.captureId,
    payoutId: context.payoutId,
    payoutBatchId: context.payoutBatchId,
    tutorId: context.tutorId,
    amountZar: context.amountZar,
    currency: context.currency,
    recipientCode: context.recipientCode,
    reason: toTrimmedString(input.reason) || null,
  };
  ensureRequiredContext(scenario, normalized);
  return normalized;
}

function scenarioEventName(scenario: MockPaystackWebhookScenario): string {
  switch (scenario) {
  case "initial_preauthorization_success":
    return "charge.success";
  case "reserve_preauthorization_success":
    return "charge.success";
  case "reserve_preauthorization_failure":
    return "charge.failed";
  case "capture_success":
    return "capture.success";
  case "capture_failure":
    return "capture.failed";
  case "transfer_success":
    return "transfer.success";
  case "transfer_failure":
    return "transfer.failed";
  }
}

function scenarioGatewayResponse(scenario: MockPaystackWebhookScenario): string {
  switch (scenario) {
  case "reserve_preauthorization_failure":
    return "Mock reserve preauthorization failed.";
  case "capture_failure":
    return "Mock capture failed.";
  case "transfer_failure":
    return "Mock transfer failed.";
  default:
    return "Mock webhook accepted.";
  }
}

export async function buildMockPaystackWebhookPayload(
  input: SimulateMockPaystackWebhookInput
): Promise<MockPaystackWebhookPayload> {
  const normalized = await normalizeSimulationInput(input);
  const context = await loadSimulationContext(
    input,
    normalized.scenario,
    normalized.seed
  );
  const basis = [
    normalized.scenario,
    normalized.seed,
    normalized.bookingId,
    normalized.paymentSessionId,
    normalized.sessionId,
    normalized.authorizationId,
    normalized.captureId,
    normalized.payoutId,
  ].join("|");
  const externalEventId = stableId("evt", `${basis}|external_event`, 24);
  const createdAt = stableIso(`${basis}|created_at`);
  const payloadReference =
    normalized.scenario === "capture_success" ||
    normalized.scenario === "capture_failure" ?
      context.captureReference :
    normalized.scenario === "transfer_success" ||
    normalized.scenario === "transfer_failure" ?
      context.transferReference :
      context.authorizationReference;
  const status =
    normalized.scenario === "reserve_preauthorization_failure" ||
    normalized.scenario === "capture_failure" ||
    normalized.scenario === "transfer_failure" ?
      "failed" :
      "success";
  const metadata: Record<string, unknown> = {
    paymentRail: TUTORING_RAIL,
    scenario: normalized.scenario,
    seed: normalized.seed,
    bookingId: normalized.bookingId,
    paymentSessionId: normalized.paymentSessionId,
    sessionId: normalized.sessionId,
    authorizationId: normalized.authorizationId,
    captureId: normalized.captureId,
    payoutId: normalized.payoutId,
    payoutBatchId: normalized.payoutBatchId || null,
    tutorId: normalized.tutorId,
    recipientCode: normalized.recipientCode || null,
  };
  if (normalized.reason) {
    metadata.reason = normalized.reason;
  }

  return {
    id: externalEventId,
    event: scenarioEventName(normalized.scenario),
    livemode: false,
    createdAt,
    provider: PROVIDER,
    adapterKey: ADAPTER_KEY,
    data: {
      id: stableId("evtdata", `${basis}|event_data`, 24),
      reference: payloadReference,
      status,
      amount: Math.round(normalized.amountZar * 100),
      currency: normalized.currency,
      paid_at: createdAt,
      gateway_response: scenarioGatewayResponse(normalized.scenario),
      domain: "test",
      metadata,
      customer: {
        customer_code: stableId("CUS", `${basis}|customer`),
        email: `sim+${stableDigest(`${basis}|email`).slice(0, 12)}@example.test`,
      },
      authorization: {
        authorization_code: stableId("AUTH", `${basis}|authorization_code`),
        authorization_reference: context.authorizationReference,
        reusable: true,
      },
      transfer_code:
        normalized.scenario === "transfer_success" ||
        normalized.scenario === "transfer_failure" ?
          context.transferCode :
          null,
      recipient:
        normalized.scenario === "transfer_success" ||
        normalized.scenario === "transfer_failure" ?
          {recipient_code: normalized.recipientCode} :
          null,
      failure_reason:
        status === "failed" ?
          (normalized.reason || scenarioGatewayResponse(normalized.scenario)) :
          null,
    },
  };
}

export function mapMockPaystackWebhookPayloadToPaymentEvent(
  payload: MockPaystackWebhookPayload
): PaymentEventInput {
  const metadata = payload.data.metadata;
  const scenario = requireScenario(metadata.scenario);
  let eventType: PaymentEventInput["eventType"];
  switch (scenario) {
  case "initial_preauthorization_success":
    eventType = "authorization_created";
    break;
  case "reserve_preauthorization_success":
    eventType = "authorization_reserved";
    break;
  case "reserve_preauthorization_failure":
    eventType = "authorization_reserve_failed";
    break;
  case "capture_success":
    eventType = "capture_succeeded";
    break;
  case "capture_failure":
    eventType = "capture_failed";
    break;
  case "transfer_success":
    eventType = "transfer_succeeded";
    break;
  case "transfer_failure":
    eventType = "transfer_failed";
    break;
  }

  return {
    provider: payload.provider,
    adapterKey: payload.adapterKey,
    externalEventId: payload.id,
    eventType,
    paymentRail: toUpper(metadata.paymentRail) || TUTORING_RAIL,
    authorizationId: toTrimmedString(metadata.authorizationId),
    authorizationReference:
      payload.data.authorization?.authorization_reference ??
      payload.data.reference,
    captureId: toTrimmedString(metadata.captureId),
    captureReference:
      eventType === "capture_succeeded" || eventType === "capture_failed" ?
        payload.data.reference :
        undefined,
    payoutId: toTrimmedString(metadata.payoutId),
    payoutBatchId: toTrimmedString(metadata.payoutBatchId),
    bookingId: toTrimmedString(metadata.bookingId),
    paymentSessionId: toTrimmedString(metadata.paymentSessionId),
    sessionId: toTrimmedString(metadata.sessionId),
    tutorId: toTrimmedString(metadata.tutorId),
    recipientCode: payload.data.recipient?.recipient_code,
    transferCode: payload.data.transfer_code ?? undefined,
    transferReference:
      eventType === "transfer_succeeded" || eventType === "transfer_failed" ?
        payload.data.reference :
        undefined,
    providerReference: payload.data.reference,
    providerStatus: payload.data.status,
    amountZar: payload.data.amount / 100,
    currency: payload.data.currency,
    reason:
      toTrimmedString(metadata.reason) ||
      toTrimmedString(payload.data.failure_reason) ||
      null,
    metadata,
    raw: payload as unknown as Record<string, unknown>,
  };
}

export interface SimulateMockPaystackWebhookResult {
  scenario: MockPaystackWebhookScenario;
  seed: string;
  payload: MockPaystackWebhookPayload;
  paymentEvent: PaymentEventInput;
  ingestion: PaymentEventProcessResult;
}

export async function simulateMockPaystackWebhookJob(
  input: SimulateMockPaystackWebhookInput
): Promise<SimulateMockPaystackWebhookResult> {
  const payload = await buildMockPaystackWebhookPayload(input);
  const paymentEvent = mapMockPaystackWebhookPayloadToPaymentEvent(payload);
  const ingestion = await processPaymentEventJob(paymentEvent);

  logger.info("payments.mockWebhookSimulator.processed", {
    scenario: payload.data.metadata.scenario,
    externalEventId: payload.id,
    paymentEventId: ingestion.paymentEventId,
    status: ingestion.status,
    deduplicated: ingestion.deduplicated,
  });

  return {
    scenario: requireScenario(payload.data.metadata.scenario),
    seed: toTrimmedString(payload.data.metadata.seed) || "default",
    payload,
    paymentEvent,
    ingestion,
  };
}

export const simulateMockPaystackWebhook = onCall(
  {region: REGION, timeoutSeconds: 120},
  async (request): Promise<SimulateMockPaystackWebhookResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }
    assertPlatformAdmin(request.auth);
    return simulateMockPaystackWebhookJob(
      (request.data ?? {}) as SimulateMockPaystackWebhookInput
    );
  }
);
