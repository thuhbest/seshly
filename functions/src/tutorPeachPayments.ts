import {
  type CipherGCMTypes,
  type DecipherGCM,
  createDecipheriv,
  createHash,
  createHmac,
  timingSafeEqual,
} from "node:crypto";
import {request as httpsRequest} from "node:https";
import {URL, URLSearchParams} from "node:url";
import {onRequest} from "firebase-functions/v2/https";
import {HttpsError, onCall} from "./callable";
import type {Request, Response} from "express";
import * as admin from "firebase-admin";

// Retired from the live tutoring flow.
// Live tutoring payment orchestration now routes through tutoringPayments.ts
// and functions/src/payments/ so the provider adapter can later switch to
// Paystack without carrying Peach-specific callable names into production flow.

const db = admin.firestore();

const REGION = "europe-west1";
const PAYMENT_MODEL = "card_authorize_settlement";
const PAYMENT_PROVIDER = "PEACH";
const CURRENCY = "ZAR";
const INITIAL_AUTH_SUFFIX = "initial";
const PEACH_API_TIMEOUT_MS = 20000;
const PAYMENT_AUTHORIZATION_PENDING = "PAYMENT_AUTHORIZATION_PENDING";
const PAYMENT_AUTHORIZED = "PAYMENT_AUTHORIZED";
const PAYMENT_AUTH_FAILED = "PAYMENT_AUTH_FAILED";
const AUTH_STATUS_INITIATING = "INITIATING";
const AUTH_STATUS_PENDING_PROVIDER = "PENDING_PROVIDER";
const AUTH_STATUS_AUTHORIZED = "AUTHORIZED";
const AUTH_STATUS_FAILED = "FAILED";

interface StartPaymentAuthorizationResult {
  bookingId: string;
  authorizationId: string;
  paymentIntentId: string;
  status: string;
  amountZar: number;
  currency: string;
  provider: string;
  merchantTransactionId: string;
  providerPaymentId: string;
  ndc: string;
  resultCode: string;
  resultDescription: string;
  asyncReconciliationPending: boolean;
}

interface PeachConfig {
  baseUrl: string;
  entityId: string;
  bearerToken: string;
  webhookSecret: string;
  webhookSecretKey: string;
  webhookHmacSecret: string;
}

interface PeachApiResult {
  id?: string;
  ndc?: string;
  registrationId?: string;
  merchantTransactionId?: string;
  timestamp?: string;
  result?: {
    code?: string;
    description?: string;
  };
  card?: {
    bin?: string;
    last4Digits?: string;
    holder?: string;
    expiryMonth?: string;
    expiryYear?: string;
  };
  customParameters?: Record<string, unknown>;
  [key: string]: unknown;
}

interface PaymentMethodDetails {
  paymentMethodId: string;
  paymentMethodType: string;
  paymentMethodSummary: string;
  registrationId: string;
  providerReference: string;
  provider: string;
  isTemporary: boolean;
}

interface PreparedAuthorization {
  bookingId: string;
  paymentIntentId: string;
  amountZar: number;
  paymentMethod: PaymentMethodDetails;
  merchantTransactionId: string;
  tutorId: string;
}

interface AuthorizationTransactionState {
  existingResult: StartPaymentAuthorizationResult | null;
  prepared: PreparedAuthorization | null;
}

type AuthorizationOutcome = "AUTHORIZED" | "PENDING_PROVIDER" | "FAILED";
type CaptureOutcome = "CAPTURED" | "PENDING_PROVIDER" | "FAILED";

class PeachApiError extends Error {
  constructor(
    message: string,
    readonly httpStatus: number,
    readonly providerBody: Record<string, unknown> | null,
    readonly networkFailure = false
  ) {
    super(message);
  }
}

function toTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asPositiveMoney(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value) && value > 0) {
    return roundToCents(value);
  }
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed) && parsed > 0) {
      return roundToCents(parsed);
    }
  }
  return null;
}

function roundToCents(value: number): number {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

function formatMoney(value: number): string {
  return roundToCents(value).toFixed(2);
}

function getPeachConfig(): PeachConfig {
  const baseUrl =
    toTrimmedString(process.env.PEACH_API_BASE_URL) || "https://oppwa.com";
  const entityId = toTrimmedString(process.env.PEACH_ENTITY_ID);
  const bearerToken = toTrimmedString(process.env.PEACH_BEARER_TOKEN);
  const webhookSecret = toTrimmedString(process.env.PEACH_WEBHOOK_SECRET);
  const webhookSecretKey = toTrimmedString(
    process.env.PEACH_WEBHOOK_SECRET_KEY || webhookSecret
  );
  const webhookHmacSecret = toTrimmedString(
    process.env.PEACH_WEBHOOK_HMAC_SECRET
  );

  if (!entityId) {
    throw new HttpsError(
      "failed-precondition",
      "PEACH_ENTITY_ID is not configured."
    );
  }
  if (!bearerToken) {
    throw new HttpsError(
      "failed-precondition",
      "PEACH_BEARER_TOKEN is not configured."
    );
  }

  return {
    baseUrl,
    entityId,
    bearerToken,
    webhookSecret,
    webhookSecretKey,
    webhookHmacSecret,
  };
}

function isInstantTutorModeUser(data: Record<string, unknown>): boolean {
  const accessTier = toTrimmedString(data.accessTier).toLowerCase();
  const accountType = toTrimmedString(data.accountType).toLowerCase();
  const accessMode = toTrimmedString(data.accessMode).toLowerCase();
  return accessTier === "instant_tutor" ||
    accountType === "instant_tutor" ||
    accessMode === "instanttutor" ||
    data.instantTutorAccess === true;
}

function buildAuthorizationId(bookingId: string): string {
  return `pa_${bookingId}_${INITIAL_AUTH_SUFFIX}`;
}

function buildAuthorizationFingerprint(params: {
  bookingId: string;
  studentId: string;
  amountZar: number;
  registrationId: string;
}): string {
  const material = [
    params.bookingId,
    params.studentId,
    params.amountZar.toFixed(2),
    params.registrationId,
  ].join("|");
  return createHash("sha256").update(material).digest("hex");
}

function buildPeachWebhookEventId(params: {
  scope: string;
  recordId: string;
  paymentId: string;
  merchantTransactionId: string;
  ndc: string;
  resultCode: string;
}): string {
  const material = [
    params.scope,
    params.recordId,
    params.paymentId,
    params.merchantTransactionId,
    params.ndc,
    params.resultCode,
  ].join("|");
  return createHash("sha256").update(material).digest("hex");
}

function buildPaymentCaptureId(params: {
  bookingId: string;
  paymentIntentId: string;
  paymentId: string;
  merchantTransactionId: string;
}): string {
  const material = [
    params.bookingId || "booking",
    params.paymentIntentId || "intent",
    params.paymentId || "payment",
    params.merchantTransactionId || "merchant",
  ].join("|");
  return `pc_${createHash("sha256").update(material).digest("hex").slice(0, 32)}`;
}

function toJSONObject(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" &&
    !Array.isArray(value) &&
    !Buffer.isBuffer(value) ?
    value as Record<string, unknown> :
    {};
}

function getNestedString(
  source: Record<string, unknown>,
  dottedPath: string
): string {
  if (dottedPath in source) {
    return toTrimmedString(source[dottedPath]);
  }

  let current: unknown = source;
  for (const part of dottedPath.split(".")) {
    if (!current || typeof current !== "object" || Array.isArray(current)) {
      return "";
    }
    current = (current as Record<string, unknown>)[part];
  }
  return toTrimmedString(current);
}

function decodeOpaqueBuffer(value: string): Buffer {
  const trimmed = value.trim();
  if (!trimmed) return Buffer.alloc(0);

  if (/^[0-9a-fA-F]+$/.test(trimmed) && trimmed.length % 2 === 0) {
    return Buffer.from(trimmed, "hex");
  }

  try {
    const base64 = Buffer.from(trimmed, "base64");
    if (base64.length > 0 && base64.toString("base64").replace(/=+$/, "") === trimmed.replace(/=+$/, "")) {
      return base64;
    }
  } catch {
    // Fall through to UTF-8 decoding below.
  }

  return Buffer.from(trimmed, "utf8");
}

function decodeWebhookSecretKey(secret: string): Buffer {
  const decoded = decodeOpaqueBuffer(secret);
  if (![16, 24, 32].includes(decoded.length)) {
    throw new Error(
      "Peach webhook secret key must decode to 16, 24, or 32 bytes."
    );
  }
  return decoded;
}

function resolveAesGcmAlgorithm(secretKey: Buffer): string {
  switch (secretKey.length) {
  case 16:
    return "aes-128-gcm";
  case 24:
    return "aes-192-gcm";
  case 32:
    return "aes-256-gcm";
  default:
    throw new Error("Unsupported Peach webhook key length.");
  }
}

function readRawRequestBody(req: Request): Buffer {
  const rawBody = (req as Request & {rawBody?: unknown}).rawBody;
  if (Buffer.isBuffer(rawBody)) return rawBody;
  if (typeof rawBody === "string") return Buffer.from(rawBody, "utf8");
  if (Buffer.isBuffer(req.body)) return req.body;
  if (typeof req.body === "string") return Buffer.from(req.body, "utf8");
  if (req.body && typeof req.body === "object") {
    return Buffer.from(JSON.stringify(req.body), "utf8");
  }
  return Buffer.alloc(0);
}

function parseLoosePayload(rawText: string): Record<string, unknown> {
  const trimmed = rawText.trim();
  if (!trimmed) return {};

  if (trimmed.startsWith("{")) {
    try {
      return toJSONObject(JSON.parse(trimmed));
    } catch {
      return {};
    }
  }

  const params = new URLSearchParams(trimmed);
  const values: Record<string, unknown> = {};
  for (const [key, value] of params.entries()) {
    values[key] = value;
    values[key.replace(/\[([^\]]+)\]/g, ".$1")] = value;
  }
  return values;
}

function getHeaderValue(req: Request, candidates: string[]): string {
  for (const candidate of candidates) {
    const value = toTrimmedString(req.get(candidate));
    if (value) return value;
  }
  return "";
}

function extractVerificationCode(req: Request): string {
  const body = toJSONObject(req.body);
  const raw = parseLoosePayload(readRawRequestBody(req).toString("utf8"));
  const query = toJSONObject(req.query as Record<string, unknown>);

  return (
    getNestedString(body, "verificationCode") ||
    getNestedString(raw, "verificationCode") ||
    getNestedString(query, "verificationCode")
  );
}

function compareWebhookSignature(
  presented: string,
  expected: string
): boolean {
  const left = Buffer.from(presented, "utf8");
  const right = Buffer.from(expected, "utf8");
  if (left.length !== right.length) return false;
  return timingSafeEqual(left, right);
}

function verifyOptionalWebhookSignature(
  req: Request,
  rawBody: Buffer,
  config: PeachConfig
): void {
  const presented = getHeaderValue(req, [
    "x-peach-signature",
    "x-webhook-signature",
    "x-signature",
  ]);
  if (!presented) return;

  const secret = config.webhookHmacSecret || config.webhookSecret;
  if (!secret) {
    throw new Error(
      "Peach webhook signature was supplied but no HMAC secret is configured."
    );
  }

  const digestHex = createHmac("sha256", secret)
    .update(rawBody)
    .digest("hex");
  const digestBase64 = Buffer.from(digestHex, "hex").toString("base64");

  if (
    compareWebhookSignature(presented, digestHex) ||
    compareWebhookSignature(presented, digestBase64)
  ) {
    return;
  }

  throw new Error("Invalid Peach webhook signature.");
}

function extractEncryptedWebhookBody(
  req: Request,
  rawBody: Buffer
): Buffer {
  const parsedBody = toJSONObject(req.body);
  const encryptedBody =
    getNestedString(parsedBody, "encryptedBody") ||
    getNestedString(parsedBody, "payload") ||
    getNestedString(parseLoosePayload(rawBody.toString("utf8")), "encryptedBody");

  if (encryptedBody) {
    return decodeOpaqueBuffer(encryptedBody);
  }

  const rawText = rawBody.toString("utf8").trim();
  if (!rawText) return Buffer.alloc(0);
  if (rawText.startsWith("{")) {
    return Buffer.alloc(0);
  }
  return decodeOpaqueBuffer(rawText);
}

function decryptWebhookPayload(
  req: Request,
  config: PeachConfig
): Record<string, unknown> {
  if (!config.webhookSecretKey) {
    throw new Error("PEACH_WEBHOOK_SECRET_KEY is not configured.");
  }

  const rawBody = readRawRequestBody(req);
  verifyOptionalWebhookSignature(req, rawBody, config);

  const iv = decodeOpaqueBuffer(getHeaderValue(req, [
    "x-initialization-vector",
    "x-peach-initialization-vector",
    "initialization-vector",
    "x-iv",
    "iv",
  ]));
  const authTag = decodeOpaqueBuffer(getHeaderValue(req, [
    "x-authentication-tag",
    "x-peach-authentication-tag",
    "authentication-tag",
    "x-auth-tag",
    "auth-tag",
    "tag",
  ]));
  const ciphertext = extractEncryptedWebhookBody(req, rawBody);

  if (!iv.length || !authTag.length || !ciphertext.length) {
    throw new Error(
      "Missing Peach webhook encryption metadata or encrypted body."
    );
  }

  const secretKey = decodeWebhookSecretKey(config.webhookSecretKey);
  const decipher = createDecipheriv(
    resolveAesGcmAlgorithm(secretKey) as CipherGCMTypes,
    secretKey,
    iv
  ) as DecipherGCM;
  decipher.setAuthTag(authTag);

  const decrypted = Buffer.concat([
    decipher.update(ciphertext),
    decipher.final(),
  ]).toString("utf8");
  const payload = parseLoosePayload(decrypted);
  if (Object.keys(payload).length === 0) {
    throw new Error("Peach webhook decrypted successfully but was empty.");
  }
  return payload;
}

function extractWebhookField(
  payload: Record<string, unknown>,
  dottedPath: string
): string {
  return (
    getNestedString(payload, dottedPath) ||
    getNestedString(payload, dottedPath.replace(/\./g, "_"))
  );
}

function summarizePaymentMethod(brand: string, last4: string): string {
  const cleanBrand = brand || "Card";
  return last4 ? `${cleanBrand} •••• ${last4}` : cleanBrand;
}

async function readPaymentMethodForStudent(
  tx: admin.firestore.Transaction,
  studentRef: admin.firestore.DocumentReference
): Promise<PaymentMethodDetails> {
  const studentSnap = await tx.get(studentRef);
  if (!studentSnap.exists) {
    throw new HttpsError("not-found", "Student not found.");
  }

  const studentData = studentSnap.data() ?? {};
  const isTemporary = isInstantTutorModeUser(
    studentData as Record<string, unknown>
  );
  const collectionName = isTemporary ? "temporary_payment_methods" : "payment_methods";
  const rootMethodId = toTrimmedString(
    isTemporary ?
      studentData.temporaryPaymentMethodId :
      studentData.billingDefaultPaymentMethodId
  );
  const rootRegistrationId = toTrimmedString(
    isTemporary ?
      studentData.temporaryPaymentRegistrationId :
      studentData.billingRegistrationId
  );
  const rootProviderReference = toTrimmedString(
    isTemporary ?
      studentData.temporaryPaymentProviderReference :
      studentData.billingProviderReference
  );
  const rootBrand = toTrimmedString(
    isTemporary ? studentData.temporaryCardBrand : studentData.billingCardBrand
  );
  const rootLast4 = toTrimmedString(
    isTemporary ? studentData.temporaryCardLast4 : studentData.billingCardLast4
  );
  const rootProvider = toTrimmedString(
    isTemporary ? studentData.temporaryPaymentProvider : studentData.billingProvider
  );

  let methodData: Record<string, unknown> = {};
  if (rootMethodId) {
    const methodRef = studentRef.collection(collectionName).doc(rootMethodId);
    const methodSnap = await tx.get(methodRef);
    methodData = methodSnap.data() ?? {};
  }

  const registrationId = toTrimmedString(
    rootRegistrationId ||
      methodData.registrationId ||
      methodData.providerReference ||
      methodData.providerRegistrationId
  );
  const providerReference = toTrimmedString(
    rootProviderReference ||
      methodData.providerReference ||
      methodData.registrationId ||
      methodData.providerRegistrationId
  );
  const brand = toTrimmedString(methodData.brand || rootBrand || "Card");
  const last4 = toTrimmedString(methodData.last4 || rootLast4);
  const provider = toTrimmedString(
    methodData.provider || rootProvider || PAYMENT_PROVIDER
  );
  const paymentMethodId = toTrimmedString(
    methodData.paymentMethodId || rootMethodId
  );
  const paymentMethodType = toTrimmedString(methodData.type || "card");

  if (!paymentMethodId) {
    throw new HttpsError(
      "failed-precondition",
      "No billing payment method is attached to this student."
    );
  }
  if (!registrationId) {
    throw new HttpsError(
      "failed-precondition",
      "No Peach registration token is attached to the selected payment method."
    );
  }

  return {
    paymentMethodId,
    paymentMethodType,
    paymentMethodSummary: summarizePaymentMethod(brand, last4),
    registrationId,
    providerReference: providerReference || registrationId,
    provider,
    isTemporary,
  };
}

function classifyPeachResult(resultCode: string): AuthorizationOutcome {
  if (/^000\.200\./.test(resultCode)) {
    return "PENDING_PROVIDER";
  }
  if (/^(000\.000\.|000\.100\.1|000\.[36])/.test(resultCode)) {
    return "AUTHORIZED";
  }
  return "FAILED";
}

function authorizationStateRank(status: string): number {
  switch (status) {
  case AUTH_STATUS_FAILED:
    return 1;
  case AUTH_STATUS_INITIATING:
    return 2;
  case AUTH_STATUS_PENDING_PROVIDER:
    return 3;
  case AUTH_STATUS_AUTHORIZED:
    return 4;
  default:
    return 0;
  }
}

function shouldPromoteStatus(currentStatus: string, nextStatus: string): boolean {
  return authorizationStateRank(nextStatus) >= authorizationStateRank(currentStatus);
}

function mapOutcomeToStoredStatus(outcome: AuthorizationOutcome): string {
  switch (outcome) {
  case "AUTHORIZED":
    return AUTH_STATUS_AUTHORIZED;
  case "PENDING_PROVIDER":
    return AUTH_STATUS_PENDING_PROVIDER;
  case "FAILED":
    return AUTH_STATUS_FAILED;
  }
}

function buildProviderResponseSnapshot(
  providerResponse: PeachApiResult | Record<string, unknown>,
  merchantTransactionId: string
): Record<string, unknown> {
  const response = providerResponse as PeachApiResult;
  return {
    paymentId: toTrimmedString(response.id),
    ndc: toTrimmedString(response.ndc),
    resultCode: toTrimmedString(response.result?.code),
    resultDescription: toTrimmedString(response.result?.description),
    merchantTransactionId:
      toTrimmedString(response.merchantTransactionId) || merchantTransactionId,
    timestamp: toTrimmedString(response.timestamp),
    registrationId: toTrimmedString(response.registrationId),
    raw: providerResponse,
  };
}

function buildFlutterAuthorizationResponse(
  bookingId: string,
  paymentIntentId: string,
  authData: Record<string, unknown>
): StartPaymentAuthorizationResult {
  const provider = toJSONObject(authData.provider);
  return {
    bookingId,
    authorizationId: toTrimmedString(authData.authorizationId),
    paymentIntentId,
    status: toTrimmedString(authData.status),
    amountZar: asPositiveMoney(authData.amountZar) ?? 0,
    currency: toTrimmedString(authData.currency) || CURRENCY,
    provider: PAYMENT_PROVIDER,
    merchantTransactionId: toTrimmedString(provider.merchantTransactionId),
    providerPaymentId: toTrimmedString(provider.paymentId),
    ndc: toTrimmedString(provider.ndc),
    resultCode: toTrimmedString(provider.resultCode),
    resultDescription: toTrimmedString(provider.resultDescription),
    asyncReconciliationPending:
      toTrimmedString(authData.status) === AUTH_STATUS_PENDING_PROVIDER ||
      toTrimmedString(authData.status) === AUTH_STATUS_INITIATING,
  };
}

function httpsJsonRequest<T>(params: {
  method: "GET" | "POST";
  url: string;
  headers?: Record<string, string>;
  body?: string;
  timeoutMs?: number;
}): Promise<T> {
  return new Promise((resolve, reject) => {
    const target = new URL(params.url);
    const req = httpsRequest(
      target,
      {
        method: params.method,
        headers: params.headers,
        timeout: params.timeoutMs ?? PEACH_API_TIMEOUT_MS,
      },
      (res) => {
        let raw = "";
        res.setEncoding("utf8");
        res.on("data", (chunk) => {
          raw += chunk;
        });
        res.on("end", () => {
          let parsed: Record<string, unknown> | null = null;
          try {
            parsed = raw ? JSON.parse(raw) as Record<string, unknown> : {};
          } catch {
            parsed = {raw};
          }

          const statusCode = res.statusCode ?? 500;
          if (statusCode >= 200 && statusCode < 300) {
            resolve((parsed ?? {}) as T);
            return;
          }

          reject(new PeachApiError(
            `Peach API returned HTTP ${statusCode}.`,
            statusCode,
            parsed
          ));
        });
      }
    );

    req.on("error", (error) => {
      reject(new PeachApiError(error.message, 0, null, true));
    });

    if (params.body) {
      req.write(params.body);
    }
    req.end();
  });
}

async function createPeachPreauthorization(params: {
  config: PeachConfig;
  amountZar: number;
  currency: string;
  registrationId: string;
  merchantTransactionId: string;
  bookingId: string;
  studentId: string;
  tutorId: string;
}): Promise<PeachApiResult> {
  const body = new URLSearchParams({
    "entityId": params.config.entityId,
    "amount": formatMoney(params.amountZar),
    "currency": params.currency,
    "paymentType": "PA",
    "registrationId": params.registrationId,
    "merchantTransactionId": params.merchantTransactionId,
    "customParameters[bookingId]": params.bookingId,
    "customParameters[studentId]": params.studentId,
    "customParameters[tutorId]": params.tutorId,
  }).toString();

  return httpsJsonRequest<PeachApiResult>({
    method: "POST",
    url: `${params.config.baseUrl}/v1/payments`,
    headers: {
      "Authorization": `Bearer ${params.config.bearerToken}`,
      "Content-Type": "application/x-www-form-urlencoded",
      "Content-Length": Buffer.byteLength(body).toString(),
    },
    body,
  });
}

async function fetchPeachPaymentStatus(params: {
  config: PeachConfig;
  paymentId: string;
}): Promise<PeachApiResult> {
  const query = new URLSearchParams({
    entityId: params.config.entityId,
  }).toString();

  return httpsJsonRequest<PeachApiResult>({
    method: "GET",
    url: `${params.config.baseUrl}/v1/payments/${params.paymentId}?${query}`,
    headers: {
      "Authorization": `Bearer ${params.config.bearerToken}`,
    },
  });
}

async function updateAuthorizationOutcomeInTransaction(params: {
  tx: admin.firestore.Transaction;
  authorizationRef: admin.firestore.DocumentReference;
  bookingRef: admin.firestore.DocumentReference;
  paymentIntentRef: admin.firestore.DocumentReference;
  outcome: AuthorizationOutcome;
  providerSnapshot: Record<string, unknown>;
  amountZar: number;
  paymentMethod: PaymentMethodDetails;
  source: "callable" | "webhook";
}): Promise<Record<string, unknown>> {
  const [authSnap, bookingSnap, intentSnap] = await Promise.all([
    params.tx.get(params.authorizationRef),
    params.tx.get(params.bookingRef),
    params.tx.get(params.paymentIntentRef),
  ]);

  if (!authSnap.exists || !bookingSnap.exists || !intentSnap.exists) {
    throw new HttpsError(
      "not-found",
      "Authorization, booking, or payment intent was not found."
    );
  }

  const authData = authSnap.data() ?? {};
  const currentStatus = toTrimmedString(authData.status);
  const nextStatus = mapOutcomeToStoredStatus(params.outcome);
  const canPromote = shouldPromoteStatus(currentStatus, nextStatus);
  const providerData: Record<string, unknown> = {
    ...toJSONObject(authData.provider),
    ...params.providerSnapshot,
    updatedFrom: params.source,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  params.tx.set(params.authorizationRef, {
    provider: providerData,
    lastReconciledAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  if (!canPromote) {
    return {
      ...authData,
      provider: {
        ...toJSONObject(authData.provider),
        ...params.providerSnapshot,
      },
    };
  }

  if (params.outcome === "AUTHORIZED") {
    params.tx.set(params.authorizationRef, {
      status: AUTH_STATUS_AUTHORIZED,
      authorizedAt: admin.firestore.FieldValue.serverTimestamp(),
      paymentAuthorizedAt: admin.firestore.FieldValue.serverTimestamp(),
      amountZar: params.amountZar,
      amountCents: Math.round(params.amountZar * 100),
      currency: CURRENCY,
      paymentMethodId: params.paymentMethod.paymentMethodId,
      paymentMethodType: params.paymentMethod.paymentMethodType,
      paymentMethodSummary: params.paymentMethod.paymentMethodSummary,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    params.tx.set(params.bookingRef, {
      paymentStatus: PAYMENT_AUTHORIZED,
      authorizationStatus: PAYMENT_AUTHORIZED,
      paymentAuthorizationId: params.authorizationRef.id,
      paymentAuthorizationProvider: PAYMENT_PROVIDER,
      paymentAuthorizationAmountZar: params.amountZar,
      paymentAuthorizationMerchantTransactionId:
        toTrimmedString(providerData.merchantTransactionId),
      paymentAuthorizationProviderPaymentId:
        toTrimmedString(providerData.paymentId),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    params.tx.set(params.paymentIntentRef, {
      status: "session_authorized",
      holdStatus: "authorized",
      paymentAuthorizationStatus: PAYMENT_AUTHORIZED,
      paymentAuthorizationId: params.authorizationRef.id,
      holdAmountZar: params.amountZar,
      holdRemainingZar: params.amountZar,
      paymentModel: PAYMENT_MODEL,
      paymentMethodType: params.paymentMethod.paymentMethodType,
      paymentMethodStatus: "authorized",
      paymentMethodSummary: params.paymentMethod.paymentMethodSummary,
      authorizationProvider: PAYMENT_PROVIDER,
      authorizationMerchantTransactionId:
        toTrimmedString(providerData.merchantTransactionId),
      authorizationProviderPaymentId:
        toTrimmedString(providerData.paymentId),
      holdAuthorizedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  } else if (params.outcome === "FAILED") {
    params.tx.set(params.authorizationRef, {
      status: AUTH_STATUS_FAILED,
      failedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    params.tx.set(params.bookingRef, {
      paymentStatus: PAYMENT_AUTH_FAILED,
      authorizationStatus: PAYMENT_AUTH_FAILED,
      paymentFailureReason:
        toTrimmedString(providerData.resultDescription) || "authorization_failed",
      paymentAuthorizationId: params.authorizationRef.id,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    params.tx.set(params.paymentIntentRef, {
      status: "hold_failed",
      holdStatus: "failed",
      settlementStatus: "blocked",
      paymentAuthorizationStatus: PAYMENT_AUTH_FAILED,
      paymentAuthorizationId: params.authorizationRef.id,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  } else {
    params.tx.set(params.authorizationRef, {
      status: AUTH_STATUS_PENDING_PROVIDER,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    params.tx.set(params.bookingRef, {
      paymentStatus: PAYMENT_AUTHORIZATION_PENDING,
      authorizationStatus: PAYMENT_AUTHORIZATION_PENDING,
      paymentAuthorizationId: params.authorizationRef.id,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    params.tx.set(params.paymentIntentRef, {
      paymentAuthorizationStatus: PAYMENT_AUTHORIZATION_PENDING,
      paymentAuthorizationId: params.authorizationRef.id,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  }

  return {
    ...authData,
    status: nextStatus,
    provider: {
      ...toJSONObject(authData.provider),
      ...params.providerSnapshot,
    },
    amountZar: params.amountZar,
    currency: CURRENCY,
    paymentMethodId: params.paymentMethod.paymentMethodId,
    paymentMethodType: params.paymentMethod.paymentMethodType,
    paymentMethodSummary: params.paymentMethod.paymentMethodSummary,
  };
}

async function applyAuthorizationOutcome(params: {
  authorizationRef: admin.firestore.DocumentReference;
  bookingRef: admin.firestore.DocumentReference;
  paymentIntentRef: admin.firestore.DocumentReference;
  outcome: AuthorizationOutcome;
  providerSnapshot: Record<string, unknown>;
  amountZar: number;
  paymentMethod: PaymentMethodDetails;
  source: "callable" | "webhook";
}): Promise<Record<string, unknown>> {
  return db.runTransaction(async (tx) => {
    return updateAuthorizationOutcomeInTransaction({
      tx,
      ...params,
    });
  });
}

function captureStateRank(status: string): number {
  switch (status) {
  case "FAILED":
    return 1;
  case "PENDING_PROVIDER":
    return 2;
  case "CAPTURED":
    return 3;
  default:
    return 0;
  }
}

function mapCaptureOutcomeToStoredStatus(outcome: CaptureOutcome): string {
  switch (outcome) {
  case "CAPTURED":
    return "CAPTURED";
  case "PENDING_PROVIDER":
    return "PENDING_PROVIDER";
  case "FAILED":
    return "FAILED";
  }
}

function classifyCaptureResult(resultCode: string): CaptureOutcome {
  const authorizationLike = classifyPeachResult(resultCode);
  if (authorizationLike === "AUTHORIZED") return "CAPTURED";
  if (authorizationLike === "PENDING_PROVIDER") return "PENDING_PROVIDER";
  return "FAILED";
}

async function updateCaptureOutcomeInTransaction(params: {
  tx: admin.firestore.Transaction;
  captureRef: admin.firestore.DocumentReference;
  authorizationRef: admin.firestore.DocumentReference;
  bookingRef: admin.firestore.DocumentReference;
  paymentIntentRef: admin.firestore.DocumentReference;
  amountZar: number;
  providerSnapshot: Record<string, unknown>;
  outcome: CaptureOutcome;
}): Promise<void> {
  const [captureSnap, authSnap, bookingSnap, intentSnap] = await Promise.all([
    params.tx.get(params.captureRef),
    params.tx.get(params.authorizationRef),
    params.tx.get(params.bookingRef),
    params.tx.get(params.paymentIntentRef),
  ]);

  if (!authSnap.exists || !bookingSnap.exists || !intentSnap.exists) {
    throw new HttpsError(
      "not-found",
      "Capture webhook could not resolve authorization, booking, or payment intent."
    );
  }

  const existingCapture = captureSnap.data() ?? {};
  const nextStatus = mapCaptureOutcomeToStoredStatus(params.outcome);
  const previousStatus = toTrimmedString(existingCapture.status);
  const canPromote =
    captureStateRank(nextStatus) >=
    captureStateRank(previousStatus);
  const providerData: Record<string, unknown> = {
    ...toJSONObject(existingCapture.provider),
    ...params.providerSnapshot,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  const previousAccountedAmount =
    previousStatus === "CAPTURED" || previousStatus === "PENDING_PROVIDER" ?
      asPositiveMoney(existingCapture.accountedAmountZar) ??
        asPositiveMoney(existingCapture.amountZar) ??
        0 :
      0;
  const nextAccountedAmount =
    nextStatus === "FAILED" ? 0 : params.amountZar;
  const capturedDelta =
    (nextStatus === "CAPTURED" ? nextAccountedAmount : 0) -
    (previousStatus === "CAPTURED" ? previousAccountedAmount : 0);
  const pendingDelta =
    (nextStatus === "PENDING_PROVIDER" ? nextAccountedAmount : 0) -
    (previousStatus === "PENDING_PROVIDER" ? previousAccountedAmount : 0);

  params.tx.set(params.captureRef, {
    captureId: params.captureRef.id,
    authorizationId: params.authorizationRef.id,
    bookingId: params.bookingRef.id,
    paymentIntentId: params.paymentIntentRef.id,
    provider: providerData,
    amountZar: params.amountZar,
    accountedAmountZar: nextAccountedAmount,
    amountCents: Math.round(params.amountZar * 100),
    currency: CURRENCY,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  if (!canPromote) return;

  if (params.outcome === "CAPTURED") {
    params.tx.set(params.captureRef, {
      status: "CAPTURED",
      capturedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  } else if (params.outcome === "FAILED") {
    params.tx.set(params.captureRef, {
      status: "FAILED",
      failedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  } else {
    params.tx.set(params.captureRef, {
      status: "PENDING_PROVIDER",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  }

  params.tx.set(params.authorizationRef, {
    capturedAmountZar: admin.firestore.FieldValue.increment(capturedDelta),
    pendingCaptureAmountZar: admin.firestore.FieldValue.increment(pendingDelta),
    lastCaptureId: params.captureRef.id,
    lastCaptureStatus: nextStatus,
    lastCaptureAmountZar: params.amountZar,
    lastCaptureProviderPaymentId:
      toTrimmedString(providerData.paymentId),
    lastCaptureMerchantTransactionId:
      toTrimmedString(providerData.merchantTransactionId),
    lastCaptureAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  params.tx.set(params.paymentIntentRef, {
    capturedAmountZar: admin.firestore.FieldValue.increment(capturedDelta),
    pendingCaptureTotalZar: admin.firestore.FieldValue.increment(pendingDelta),
    providerCaptureId: params.captureRef.id,
    providerCaptureStatus: nextStatus,
    providerCaptureAmountZar: params.amountZar,
    providerCaptureProviderPaymentId:
      toTrimmedString(providerData.paymentId),
    providerCaptureMerchantTransactionId:
      toTrimmedString(providerData.merchantTransactionId),
    providerCaptureResultCode:
      toTrimmedString(providerData.resultCode),
    providerCaptureResultDescription:
      toTrimmedString(providerData.resultDescription),
    providerCaptureUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  params.tx.set(params.bookingRef, {
    capturedAmountZar: admin.firestore.FieldValue.increment(capturedDelta),
    pendingCaptureTotalZar: admin.firestore.FieldValue.increment(pendingDelta),
    providerCaptureId: params.captureRef.id,
    providerCaptureStatus: nextStatus,
    providerCaptureAmountZar: params.amountZar,
    providerCaptureUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  params.tx.set(db.collection("tutoring_sessions").doc(params.bookingRef.id), {
    capturedTotalZar: admin.firestore.FieldValue.increment(capturedDelta),
    pendingCaptureTotalZar: admin.firestore.FieldValue.increment(pendingDelta),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
}

async function reconcileAuthorizationWebhookEvent(params: {
  authorizationRef: admin.firestore.DocumentReference;
  bookingRef: admin.firestore.DocumentReference;
  paymentIntentRef: admin.firestore.DocumentReference;
  paymentMethod: PaymentMethodDetails;
  amountZar: number;
  providerPayload: Record<string, unknown>;
}): Promise<"processed" | "duplicate"> {
  const providerPaymentId = toTrimmedString(params.providerPayload.paymentId);
  const ndc = toTrimmedString(params.providerPayload.ndc);
  const resultCode = toTrimmedString(params.providerPayload.resultCode);
  const merchantTransactionId = toTrimmedString(
    params.providerPayload.merchantTransactionId
  );
  const eventId = buildPeachWebhookEventId({
    scope: "authorization",
    recordId: params.authorizationRef.id,
    paymentId: providerPaymentId || "unknown",
    merchantTransactionId: merchantTransactionId || "unknown",
    ndc: ndc || "unknown",
    resultCode: resultCode || "unknown",
  });
  const eventRef = db.collection("peach_webhook_events").doc(eventId);
  const outcome = classifyPeachResult(resultCode);

  return db.runTransaction(async (tx) => {
    const eventSnap = await tx.get(eventRef);
    if (eventSnap.exists) return "duplicate";

    await updateAuthorizationOutcomeInTransaction({
      tx,
      authorizationRef: params.authorizationRef,
      bookingRef: params.bookingRef,
      paymentIntentRef: params.paymentIntentRef,
      outcome,
      providerSnapshot: params.providerPayload,
      amountZar: params.amountZar,
      paymentMethod: params.paymentMethod,
      source: "webhook",
    });

    tx.set(eventRef, {
      kind: "authorization",
      authorizationId: params.authorizationRef.id,
      bookingId: params.bookingRef.id,
      paymentIntentId: params.paymentIntentRef.id,
      provider: PAYMENT_PROVIDER,
      paymentId: providerPaymentId,
      ndc,
      merchantTransactionId,
      resultCode,
      resultDescription: toTrimmedString(params.providerPayload.resultDescription),
      receivedAt: admin.firestore.FieldValue.serverTimestamp(),
      raw: params.providerPayload,
    });

    return "processed";
  });
}

async function reconcileCaptureWebhookEvent(params: {
  captureRef: admin.firestore.DocumentReference;
  authorizationRef: admin.firestore.DocumentReference;
  bookingRef: admin.firestore.DocumentReference;
  paymentIntentRef: admin.firestore.DocumentReference;
  amountZar: number;
  providerPayload: Record<string, unknown>;
}): Promise<"processed" | "duplicate"> {
  const providerPaymentId = toTrimmedString(params.providerPayload.paymentId);
  const ndc = toTrimmedString(params.providerPayload.ndc);
  const resultCode = toTrimmedString(params.providerPayload.resultCode);
  const merchantTransactionId = toTrimmedString(
    params.providerPayload.merchantTransactionId
  );
  const eventId = buildPeachWebhookEventId({
    scope: "capture",
    recordId: params.captureRef.id,
    paymentId: providerPaymentId || "unknown",
    merchantTransactionId: merchantTransactionId || "unknown",
    ndc: ndc || "unknown",
    resultCode: resultCode || "unknown",
  });
  const eventRef = db.collection("peach_webhook_events").doc(eventId);

  return db.runTransaction(async (tx) => {
    const eventSnap = await tx.get(eventRef);
    if (eventSnap.exists) return "duplicate";

    await updateCaptureOutcomeInTransaction({
      tx,
      captureRef: params.captureRef,
      authorizationRef: params.authorizationRef,
      bookingRef: params.bookingRef,
      paymentIntentRef: params.paymentIntentRef,
      amountZar: params.amountZar,
      providerSnapshot: params.providerPayload,
      outcome: classifyCaptureResult(resultCode),
    });

    tx.set(eventRef, {
      kind: "capture",
      captureId: params.captureRef.id,
      authorizationId: params.authorizationRef.id,
      bookingId: params.bookingRef.id,
      paymentIntentId: params.paymentIntentRef.id,
      provider: PAYMENT_PROVIDER,
      paymentId: providerPaymentId,
      ndc,
      merchantTransactionId,
      resultCode,
      resultDescription: toTrimmedString(params.providerPayload.resultDescription),
      receivedAt: admin.firestore.FieldValue.serverTimestamp(),
      raw: params.providerPayload,
    });

    return "processed";
  });
}

async function findAuthorizationByWebhookIdentifiers(params: {
  merchantTransactionId: string;
  paymentId: string;
}): Promise<FirebaseFirestore.DocumentSnapshot | null> {
  if (params.merchantTransactionId) {
    const direct = await db
      .collection("payment_authorizations")
      .doc(params.merchantTransactionId)
      .get();
    if (direct.exists) return direct;

    const byMerchantTx = await db
      .collection("payment_authorizations")
      .where("provider.merchantTransactionId", "==", params.merchantTransactionId)
      .limit(1)
      .get();
    if (!byMerchantTx.empty) return byMerchantTx.docs[0];
  }

  if (params.paymentId) {
    const byPaymentId = await db
      .collection("payment_authorizations")
      .where("provider.paymentId", "==", params.paymentId)
      .limit(1)
      .get();
    if (!byPaymentId.empty) return byPaymentId.docs[0];
  }

  return null;
}

async function findCaptureByWebhookIdentifiers(params: {
  merchantTransactionId: string;
  paymentId: string;
}): Promise<FirebaseFirestore.DocumentSnapshot | null> {
  if (params.merchantTransactionId) {
    const direct = await db
      .collection("payment_captures")
      .doc(params.merchantTransactionId)
      .get();
    if (direct.exists) return direct;

    const byMerchantTx = await db
      .collection("payment_captures")
      .where("provider.merchantTransactionId", "==", params.merchantTransactionId)
      .limit(1)
      .get();
    if (!byMerchantTx.empty) return byMerchantTx.docs[0];
  }

  if (params.paymentId) {
    const byPaymentId = await db
      .collection("payment_captures")
      .where("provider.paymentId", "==", params.paymentId)
      .limit(1)
      .get();
    if (!byPaymentId.empty) return byPaymentId.docs[0];
  }

  return null;
}
export const startPaymentAuthorization = onCall(
  {region: REGION},
  async (request): Promise<StartPaymentAuthorizationResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }

    const bookingId = toTrimmedString(request.data?.bookingId);
    if (!bookingId) {
      throw new HttpsError("invalid-argument", "bookingId is required.");
    }

    const config = getPeachConfig();
    const studentId = request.auth.uid;
    const bookingRef = db.collection("tutor_requests").doc(bookingId);
    const authorizationId = buildAuthorizationId(bookingId);
    const authorizationRef = db.collection("payment_authorizations").doc(authorizationId);

    const transactionState = await db.runTransaction<AuthorizationTransactionState>(async (tx) => {
      const bookingSnap = await tx.get(bookingRef);
      if (!bookingSnap.exists) {
        throw new HttpsError("not-found", "Booking not found.");
      }

      const bookingData = bookingSnap.data() ?? {};
      const bookingStudentId = toTrimmedString(bookingData.studentId);
      if (bookingStudentId !== studentId) {
        throw new HttpsError(
          "permission-denied",
          "This booking does not belong to the current student."
        );
      }

      const paymentIntentId =
        toTrimmedString(bookingData.paymentIntentId) || bookingId;
      const paymentIntentRef = db.collection("session_payment_intents").doc(paymentIntentId);
      const [authorizationSnap, paymentIntentSnap] = await Promise.all([
        tx.get(authorizationRef),
        tx.get(paymentIntentRef),
      ]);

      if (!paymentIntentSnap.exists) {
        throw new HttpsError(
          "failed-precondition",
          "Booking payment intent is missing."
        );
      }

      const amountZar = asPositiveMoney(
        bookingData.initialBufferAmountZar ??
          bookingData.holdAmountZar ??
          paymentIntentSnap.data()?.holdAmountZar
      );
      if (!amountZar) {
        throw new HttpsError(
          "failed-precondition",
          "Booking is missing an initial buffer amount."
        );
      }

      if (authorizationSnap.exists) {
        const authData = authorizationSnap.data() ?? {};
        const status = toTrimmedString(authData.status);
        if (
          status === AUTH_STATUS_AUTHORIZED ||
          status === AUTH_STATUS_PENDING_PROVIDER ||
          status === AUTH_STATUS_INITIATING
        ) {
          return {
            existingResult: buildFlutterAuthorizationResponse(
              bookingId,
              paymentIntentId,
              {
                authorizationId,
                amountZar,
                currency: CURRENCY,
                ...authData,
              }
            ),
            prepared: null,
          };
        }
      }

      const studentRef = db.collection("users").doc(studentId);
      const paymentMethod = await readPaymentMethodForStudent(tx, studentRef);
      const merchantTransactionId = authorizationId;
      const fingerprint = buildAuthorizationFingerprint({
        bookingId,
        studentId,
        amountZar,
        registrationId: paymentMethod.registrationId,
      });

      tx.set(authorizationRef, {
        authorizationId,
        bookingId,
        paymentIntentId,
        studentId,
        tutorId: toTrimmedString(bookingData.tutorId),
        provider: {
          name: PAYMENT_PROVIDER,
          entityId: config.entityId,
          merchantTransactionId,
          registrationId:
            paymentMethod.providerReference || paymentMethod.registrationId,
        },
        amountZar,
        amountCents: Math.round(amountZar * 100),
        currency: CURRENCY,
        status: AUTH_STATUS_INITIATING,
        type: "PREAUTH",
        paymentModel: PAYMENT_MODEL,
        paymentMethodId: paymentMethod.paymentMethodId,
        paymentMethodType: paymentMethod.paymentMethodType,
        paymentMethodSummary: paymentMethod.paymentMethodSummary,
        idempotencyKey: fingerprint,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      tx.set(bookingRef, {
        paymentAuthorizationId: authorizationId,
        paymentStatus: PAYMENT_AUTHORIZATION_PENDING,
        authorizationStatus: PAYMENT_AUTHORIZATION_PENDING,
        paymentAuthorizationProvider: PAYMENT_PROVIDER,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      tx.set(paymentIntentRef, {
        paymentAuthorizationId: authorizationId,
        paymentAuthorizationStatus: PAYMENT_AUTHORIZATION_PENDING,
        paymentModel: PAYMENT_MODEL,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      return {
        existingResult: null,
        prepared: {
          bookingId,
          paymentIntentId,
          amountZar,
          paymentMethod,
          merchantTransactionId,
          tutorId: toTrimmedString(bookingData.tutorId),
        },
      };
    });

    if (transactionState.existingResult) {
      return transactionState.existingResult;
    }

    const prepared = transactionState.prepared;
    if (!prepared) {
      throw new HttpsError(
        "internal",
        "Payment authorization could not be prepared."
      );
    }

    const paymentIntentRef = db
      .collection("session_payment_intents")
      .doc(prepared.paymentIntentId);

    try {
      const providerResponse = await createPeachPreauthorization({
        config,
        amountZar: prepared.amountZar,
        currency: CURRENCY,
        registrationId: prepared.paymentMethod.registrationId,
        merchantTransactionId: prepared.merchantTransactionId,
        bookingId,
        studentId,
        tutorId: prepared.tutorId,
      });

      const providerSnapshot = buildProviderResponseSnapshot(
        providerResponse,
        prepared.merchantTransactionId
      );
      const outcome = classifyPeachResult(
        toTrimmedString(providerSnapshot.resultCode)
      );
      const authData = await applyAuthorizationOutcome({
        authorizationRef,
        bookingRef,
        paymentIntentRef,
        outcome,
        providerSnapshot,
        amountZar: prepared.amountZar,
        paymentMethod: prepared.paymentMethod,
        source: "callable",
      });

      return buildFlutterAuthorizationResponse(
        bookingId,
        prepared.paymentIntentId,
        {
          authorizationId,
          amountZar: prepared.amountZar,
          currency: CURRENCY,
          ...authData,
        }
      );
    } catch (error) {
      const providerBody = error instanceof PeachApiError ?
        error.providerBody :
        null;
      const providerSnapshot = buildProviderResponseSnapshot(
        providerBody ?? {},
        prepared.merchantTransactionId
      );

      if (error instanceof PeachApiError && !error.networkFailure) {
        const resultCode = toTrimmedString(providerSnapshot.resultCode) || "provider_error";
        const authData = await applyAuthorizationOutcome({
          authorizationRef,
          bookingRef,
          paymentIntentRef,
          outcome: classifyPeachResult(resultCode),
          providerSnapshot,
          amountZar: prepared.amountZar,
          paymentMethod: prepared.paymentMethod,
          source: "callable",
        });

        return buildFlutterAuthorizationResponse(
          bookingId,
          prepared.paymentIntentId,
          {
            authorizationId,
            amountZar: prepared.amountZar,
            currency: CURRENCY,
            ...authData,
          }
        );
      }

      const authData = await applyAuthorizationOutcome({
        authorizationRef,
        bookingRef,
        paymentIntentRef,
        outcome: "PENDING_PROVIDER",
        providerSnapshot: {
          ...providerSnapshot,
          resultCode: toTrimmedString(providerSnapshot.resultCode) || "network_pending",
          resultDescription:
            toTrimmedString(providerSnapshot.resultDescription) ||
            "Authorization request sent; awaiting webhook reconciliation.",
        },
        amountZar: prepared.amountZar,
        paymentMethod: prepared.paymentMethod,
        source: "callable",
      });

      return buildFlutterAuthorizationResponse(
        bookingId,
        prepared.paymentIntentId,
        {
          authorizationId,
          amountZar: prepared.amountZar,
          currency: CURRENCY,
          ...authData,
        }
      );
    }
  }
);

export const peachWebhook = onRequest(
  {region: REGION},
  async (req: Request, res: Response) => {
    try {
      // Step 1: Peach webhook verification calls are plain JSON and must be
      // acknowledged immediately with the same verification code.
      const verificationCode = extractVerificationCode(req);
      if (verificationCode) {
        res.status(200).json({verificationCode});
        return;
      }

      // Step 2: For real payment events, verify authenticity by validating the
      // optional HMAC signature and decrypting the AES-GCM payload delivered by Peach.
      const config = getPeachConfig();
      const payload = decryptWebhookPayload(req, config);

      let paymentType = extractWebhookField(payload, "paymentType").toUpperCase();
      let paymentId = extractWebhookField(payload, "id");
      let merchantTransactionId = extractWebhookField(
        payload,
        "merchantTransactionId"
      );
      const referencedPaymentId = extractWebhookField(payload, "referencedId");
      let ndc = extractWebhookField(payload, "ndc");
      let resultCode = extractWebhookField(payload, "result.code");
      let resultDescription = extractWebhookField(
        payload,
        "result.description"
      );
      let amountZar =
        asPositiveMoney(extractWebhookField(payload, "amount")) ?? 0;
      const currency = extractWebhookField(payload, "currency") || CURRENCY;
      let bookingId = extractWebhookField(payload, "customParameters.bookingId");
      let paymentIntentId = extractWebhookField(
        payload,
        "customParameters.paymentIntentId"
      );

      if (!paymentId && !merchantTransactionId && !referencedPaymentId) {
        res.status(400).json({
          ok: false,
          message: "Peach webhook is missing provider identifiers.",
        });
        return;
      }

      // Step 3: Some webhook payloads do not include the final result code.
      // In that case we hydrate the canonical payment state from Peach directly.
      if (!resultCode && paymentId) {
        const providerResponse = await fetchPeachPaymentStatus({
          config,
          paymentId,
        });
        const providerSnapshot = buildProviderResponseSnapshot(
          providerResponse,
          merchantTransactionId
        );
        paymentId = toTrimmedString(providerSnapshot.paymentId) || paymentId;
        merchantTransactionId =
          toTrimmedString(providerSnapshot.merchantTransactionId) ||
          merchantTransactionId;
        ndc = toTrimmedString(providerSnapshot.ndc) || ndc;
        resultCode = toTrimmedString(providerSnapshot.resultCode);
        resultDescription =
          toTrimmedString(providerSnapshot.resultDescription) ||
          resultDescription;
        amountZar =
          asPositiveMoney(extractWebhookField(payload, "amount")) ?? amountZar;
        paymentType =
          extractWebhookField(payload, "paymentType").toUpperCase() ||
          paymentType;
      }

      const providerPayload: Record<string, unknown> = {
        paymentType,
        paymentId,
        merchantTransactionId,
        referencedPaymentId,
        ndc,
        resultCode,
        resultDescription,
        amountZar,
        currency,
        bookingId,
        paymentIntentId,
        raw: payload,
      };

      // Step 4: Route preauthorisation events into the booking/payment-intent
      // state machine that was created by startPaymentAuthorization().
      if (paymentType === "PA") {
        const authSnap = await findAuthorizationByWebhookIdentifiers({
          merchantTransactionId,
          paymentId,
        });
        if (!authSnap?.exists) {
          res.status(202).json({
            ok: true,
            message: "Authorization not found yet.",
          });
          return;
        }

        const authData = authSnap.data() ?? {};
        bookingId = bookingId || toTrimmedString(authData.bookingId);
        paymentIntentId =
          paymentIntentId ||
          toTrimmedString(authData.paymentIntentId) ||
          bookingId;
        amountZar = asPositiveMoney(authData.amountZar) ?? amountZar;

        const paymentMethod: PaymentMethodDetails = {
          paymentMethodId: toTrimmedString(authData.paymentMethodId),
          paymentMethodType:
            toTrimmedString(authData.paymentMethodType) || "card",
          paymentMethodSummary: toTrimmedString(authData.paymentMethodSummary),
          registrationId: toTrimmedString(
            toJSONObject(authData.provider).registrationId
          ),
          providerReference: toTrimmedString(
            toJSONObject(authData.provider).registrationId
          ),
          provider: PAYMENT_PROVIDER,
          isTemporary: false,
        };

        const result = await reconcileAuthorizationWebhookEvent({
          authorizationRef: authSnap.ref,
          bookingRef: db.collection("tutor_requests").doc(bookingId),
          paymentIntentRef: db
            .collection("session_payment_intents")
            .doc(paymentIntentId),
          paymentMethod,
          amountZar,
          providerPayload: {
            ...providerPayload,
            bookingId,
            paymentIntentId,
            amountZar,
          },
        });

        res.status(200).json({
          ok: true,
          kind: "authorization",
          processed: result === "processed",
          duplicate: result === "duplicate",
          authorizationId: authSnap.id,
          bookingId,
          paymentIntentId,
          status: classifyPeachResult(resultCode),
        });
        return;
      }

      // Step 5: Route capture events into a separate capture collection while
      // safely linking them back to the booking, intent, and authorization.
      if (paymentType === "CP") {
        let captureSnap = await findCaptureByWebhookIdentifiers({
          merchantTransactionId,
          paymentId,
        });

        let authSnap: FirebaseFirestore.DocumentSnapshot | null = null;
        if (captureSnap?.exists) {
          const captureData = captureSnap.data() ?? {};
          const authorizationId = toTrimmedString(captureData.authorizationId);
          if (authorizationId) {
            const directAuth = await db
              .collection("payment_authorizations")
              .doc(authorizationId)
              .get();
            if (directAuth.exists) authSnap = directAuth;
          }
        }

        if (!authSnap && referencedPaymentId) {
          authSnap = await findAuthorizationByWebhookIdentifiers({
            merchantTransactionId: "",
            paymentId: referencedPaymentId,
          });
        }

        if (!authSnap && bookingId) {
          const directAuth = await db
            .collection("payment_authorizations")
            .doc(buildAuthorizationId(bookingId))
            .get();
          if (directAuth.exists) authSnap = directAuth;
        }

        if (!authSnap?.exists) {
          console.warn("Peach webhook capture had no matching authorization", {
            paymentId,
            merchantTransactionId,
            referencedPaymentId,
          });
          res.status(202).json({
            ok: true,
            message: "Capture received but no matching authorization was found.",
          });
          return;
        }

        const authData = authSnap.data() ?? {};
        bookingId = bookingId || toTrimmedString(authData.bookingId);
        paymentIntentId =
          paymentIntentId ||
          toTrimmedString(authData.paymentIntentId) ||
          bookingId;
        amountZar =
          amountZar ||
          asPositiveMoney(extractWebhookField(payload, "amount")) ||
          asPositiveMoney(authData.amountZar) ||
          0;

        if (!captureSnap?.exists) {
          const captureId = buildPaymentCaptureId({
            bookingId,
            paymentIntentId,
            paymentId,
            merchantTransactionId,
          });
          captureSnap = await db.collection("payment_captures").doc(captureId).get();
        }

        const captureRef = captureSnap?.exists ?
          captureSnap.ref :
          db.collection("payment_captures").doc(buildPaymentCaptureId({
            bookingId,
            paymentIntentId,
            paymentId,
            merchantTransactionId,
          }));

        const result = await reconcileCaptureWebhookEvent({
          captureRef,
          authorizationRef: authSnap.ref,
          bookingRef: db.collection("tutor_requests").doc(bookingId),
          paymentIntentRef: db
            .collection("session_payment_intents")
            .doc(paymentIntentId),
          amountZar,
          providerPayload: {
            ...providerPayload,
            bookingId,
            paymentIntentId,
            amountZar,
          },
        });

        res.status(200).json({
          ok: true,
          kind: "capture",
          processed: result === "processed",
          duplicate: result === "duplicate",
          captureId: captureRef.id,
          authorizationId: authSnap.id,
          bookingId,
          paymentIntentId,
          status: classifyCaptureResult(resultCode),
        });
        return;
      }

      // Step 6: Unknown event types are logged for visibility but still return
      // success so Peach does not keep retrying unsupported event classes.
      console.warn("Unhandled Peach webhook event type", {
        paymentType,
        paymentId,
        merchantTransactionId,
      });
      res.status(200).json({
        ok: true,
        ignored: true,
        paymentType,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : "Webhook failed.";
      const statusCode = /signature|secret key|decrypt|encryption/i.test(message) ? 401 : 500;
      res.status(statusCode).json({ok: false, message});
    }
  }
);

export const peachAuthorizationWebhook = peachWebhook;
