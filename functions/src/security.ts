import {createHash} from "node:crypto";
import * as logger from "firebase-functions/logger";
import {
  type CallableOptions,
  type CallableRequest,
  type FunctionsErrorCode,
  HttpsError,
  onCall,
} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

type JsonMap = Record<string, unknown>;

interface SlidingWindowConfig {
  windowMs: number;
  max: number;
}

interface RateLimitProfileConfig {
  burst: SlidingWindowConfig;
  sustained: SlidingWindowConfig;
  violationWindowMs: number;
  violationThreshold: number;
  blockDurationMs: number;
}

const db = admin.firestore();
const RATE_LIMIT_COLLECTION = "security_rate_limits";
const CONTENT_FINGERPRINT_COLLECTION = "content_fingerprints";
const ANALYTICS_COLLECTION = "product_analytics";
const MONITORING_COLLECTION = "monitoring_events";
const MODERATION_COLLECTION = "moderation_events";
const AUDIT_COLLECTION = "security_audit_logs";
const ENFORCE_APP_CHECK = process.env.FUNCTIONS_ENFORCE_APP_CHECK === "true";

const RATE_LIMIT_PROFILES = {
  default: {
    burst: {windowMs: 60_000, max: 20},
    sustained: {windowMs: 60 * 60_000, max: 120},
    violationWindowMs: 15 * 60_000,
    violationThreshold: 3,
    blockDurationMs: 15 * 60_000,
  },
  writeHeavy: {
    burst: {windowMs: 60_000, max: 8},
    sustained: {windowMs: 60 * 60_000, max: 40},
    violationWindowMs: 20 * 60_000,
    violationThreshold: 2,
    blockDurationMs: 30 * 60_000,
  },
  chat: {
    burst: {windowMs: 60_000, max: 12},
    sustained: {windowMs: 10 * 60_000, max: 40},
    violationWindowMs: 20 * 60_000,
    violationThreshold: 2,
    blockDurationMs: 20 * 60_000,
  },
  search: {
    burst: {windowMs: 60_000, max: 18},
    sustained: {windowMs: 60 * 60_000, max: 90},
    violationWindowMs: 15 * 60_000,
    violationThreshold: 3,
    blockDurationMs: 15 * 60_000,
  },
  payment: {
    burst: {windowMs: 60_000, max: 4},
    sustained: {windowMs: 60 * 60_000, max: 20},
    violationWindowMs: 60 * 60_000,
    violationThreshold: 2,
    blockDurationMs: 60 * 60_000,
  },
  admin: {
    burst: {windowMs: 60_000, max: 10},
    sustained: {windowMs: 60 * 60_000, max: 60},
    violationWindowMs: 20 * 60_000,
    violationThreshold: 3,
    blockDurationMs: 15 * 60_000,
  },
  upload: {
    burst: {windowMs: 60_000, max: 6},
    sustained: {windowMs: 60 * 60_000, max: 18},
    violationWindowMs: 30 * 60_000,
    violationThreshold: 2,
    blockDurationMs: 30 * 60_000,
  },
  auth: {
    burst: {windowMs: 10 * 60_000, max: 6},
    sustained: {windowMs: 24 * 60 * 60_000, max: 20},
    violationWindowMs: 24 * 60 * 60_000,
    violationThreshold: 2,
    blockDurationMs: 6 * 60 * 60_000,
  },
} satisfies Record<string, RateLimitProfileConfig>;

export type RateLimitProfileName = keyof typeof RATE_LIMIT_PROFILES;

export interface CallerIdentity {
  userId: string;
  email: string;
  emailVerified: boolean;
  isAnonymous: boolean;
  isAdmin: boolean;
}

export interface SecureCallableOptions<T> extends CallableOptions<T> {
  action: string;
  analyticsEvent?: string;
  allowAnonymous?: boolean;
  requireAuth?: boolean;
  requireVerifiedEmail?: boolean;
  rateLimitProfile?: RateLimitProfileName;
}

export interface CallableRuntimePolicy {
  allowAnonymous?: boolean;
  requireAuth?: boolean;
  requireVerifiedEmail?: boolean;
  rateLimitProfile?: RateLimitProfileName;
}

interface RateLimitKey {
  scope: "user" | "ip" | "subject";
  value: string;
}

interface RateLimitResult {
  allowed: boolean;
  blockedUntil: number | null;
}

type UploadedStorageExpectation = {
  path: string;
  maxBytes: number;
  contentTypePattern: RegExp;
  ownerPrefix?: string;
};

function nowMillis(): number {
  return Date.now();
}

function nowServerTs() {
  return admin.firestore.FieldValue.serverTimestamp();
}

function hashValue(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function rateLimitDocId(action: string, key: RateLimitKey): string {
  return Buffer.from(`${key.scope}:${action}:${key.value}`).toString("base64url");
}

function buildRateLimitKeys(
  action: string,
  ipAddress: string,
  identity: CallerIdentity | null
): RateLimitKey[] {
  const keys: RateLimitKey[] = [];
  if (identity?.userId) {
    keys.push({scope: "user", value: identity.userId});
  }
  if (ipAddress) {
    keys.push({scope: "ip", value: ipAddress});
  }
  if (!identity?.userId && ipAddress) {
    keys.push({scope: "subject", value: `anon:${ipAddress}`});
  }
  return keys.filter((key, index, list) =>
    list.findIndex((candidate) =>
      candidate.scope === key.scope && candidate.value === key.value
    ) === index
  );
}

function sanitizeCallableError(error: HttpsError): HttpsError {
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

export function isPlatformAdminClaim(token: JsonMap | undefined): boolean {
  return token?.admin === true ||
    token?.role === "admin" ||
    token?.platformRole === "admin";
}

export function detectIpAddress(
  rawRequest: CallableRequest["rawRequest"] | undefined
): string {
  const forwarded = rawRequest?.headers["x-forwarded-for"];
  if (typeof forwarded === "string" && forwarded.trim().length > 0) {
    return forwarded.split(",")[0].trim();
  }
  if (Array.isArray(forwarded) && forwarded.length > 0) {
    return forwarded[0].split(",")[0].trim();
  }
  const requestIp = rawRequest?.ip ?? rawRequest?.socket?.remoteAddress ?? "";
  return requestIp.toString().trim();
}

function buildCallerIdentity(request: CallableRequest): CallerIdentity | null {
  if (!request.auth) return null;
  const token = (request.auth.token ?? {}) as JsonMap;
  const signInProvider =
    ((token.firebase as JsonMap | undefined)?.sign_in_provider ?? "")
      .toString()
      .toLowerCase();
  const email = (token.email ?? "").toString().trim().toLowerCase();

  return {
    userId: request.auth.uid,
    email,
    emailVerified: token.email_verified === true,
    isAnonymous: signInProvider === "anonymous",
    isAdmin: isPlatformAdminClaim(token),
  };
}

export async function enforceCallableRuntimePolicy(
  action: string,
  request: CallableRequest,
  policy?: CallableRuntimePolicy
): Promise<CallerIdentity | null> {
  const identity = buildCallerIdentity(request);
  const ipAddress = detectIpAddress(request.rawRequest);
  const requireAuth = policy?.requireAuth ?? true;
  const allowAnonymous = policy?.allowAnonymous ?? false;
  const requireVerifiedEmail =
    policy?.requireVerifiedEmail ?? (requireAuth && !allowAnonymous);

  if (requireAuth && !identity) {
    throw new HttpsError("unauthenticated", "You must be signed in.");
  }
  if (!allowAnonymous && identity?.isAnonymous) {
    throw new HttpsError(
      "permission-denied",
      "This action requires a full account."
    );
  }
  if (requireVerifiedEmail && identity && !identity.emailVerified && !identity.isAdmin) {
    throw new HttpsError(
      "failed-precondition",
      "Please verify your email before continuing."
    );
  }

  const profile = RATE_LIMIT_PROFILES[policy?.rateLimitProfile ?? "default"];
  const keys = buildRateLimitKeys(action, ipAddress, identity);
  for (const key of keys) {
    const result = await consumeRateLimit(action, key, profile);
    if (!result.allowed) {
      await recordMonitoringEvent({
        action,
        severity: "warning",
        actorUid: identity?.userId,
        message: "Rate limit triggered",
        metadata: {
          scope: key.scope,
          blockedUntil: result.blockedUntil,
        },
      });
      throw new HttpsError(
        "resource-exhausted",
        "Too many requests. Please try again later."
      );
    }
  }

  return identity;
}

async function consumeRateLimit(
  action: string,
  key: RateLimitKey,
  profile: RateLimitProfileConfig
): Promise<RateLimitResult> {
  const docRef = db.collection(RATE_LIMIT_COLLECTION).doc(rateLimitDocId(action, key));
  const now = nowMillis();

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(docRef);
    const data = snap.data() ?? {};
    const burstEvents = Array.isArray(data.burstEvents) ?
      data.burstEvents.map((value) => Number(value)).filter(Number.isFinite) :
      [];
    const sustainedEvents = Array.isArray(data.sustainedEvents) ?
      data.sustainedEvents.map((value) => Number(value)).filter(Number.isFinite) :
      [];
    const violations = Array.isArray(data.violations) ?
      data.violations.map((value) => Number(value)).filter(Number.isFinite) :
      [];
    const blockedUntilRaw = Number(data.blockedUntil ?? 0);
    const blockedUntil = Number.isFinite(blockedUntilRaw) ? blockedUntilRaw : 0;

    if (blockedUntil > now) {
      return {allowed: false, blockedUntil};
    }

    const nextBurst = burstEvents.filter((value) => value >= now - profile.burst.windowMs);
    const nextSustained = sustainedEvents.filter(
      (value) => value >= now - profile.sustained.windowMs
    );
    const nextViolations = violations.filter(
      (value) => value >= now - profile.violationWindowMs
    );

    const limitExceeded =
      nextBurst.length >= profile.burst.max ||
      nextSustained.length >= profile.sustained.max;

    if (limitExceeded) {
      nextViolations.push(now);
      const nextBlockedUntil =
        nextViolations.length >= profile.violationThreshold ?
          now + profile.blockDurationMs :
          0;
      tx.set(docRef, {
        action,
        scope: key.scope,
        subjectHash: hashValue(key.value),
        burstEvents: nextBurst.slice(-profile.burst.max),
        sustainedEvents: nextSustained.slice(-profile.sustained.max),
        violations: nextViolations.slice(-profile.violationThreshold),
        blockedUntil: nextBlockedUntil,
        updatedAt: nowServerTs(),
      }, {merge: true});
      return {
        allowed: false,
        blockedUntil: nextBlockedUntil || null,
      };
    }

    nextBurst.push(now);
    nextSustained.push(now);
    tx.set(docRef, {
      action,
      scope: key.scope,
      subjectHash: hashValue(key.value),
      burstEvents: nextBurst.slice(-profile.burst.max),
      sustainedEvents: nextSustained.slice(-profile.sustained.max),
      violations: nextViolations.slice(-profile.violationThreshold),
      blockedUntil: 0,
      updatedAt: nowServerTs(),
    }, {merge: true});

    return {allowed: true, blockedUntil: null};
  });
}

export async function recordPrivacySafeAnalyticsEvent(params: {
  eventType: string;
  action: string;
  actorUid?: string;
  actorType?: string;
  status: "ok" | "blocked" | "error";
  durationMs?: number;
  metadata?: JsonMap;
}): Promise<void> {
  await db.collection(ANALYTICS_COLLECTION).add({
    eventType: params.eventType,
    action: params.action,
    actorUid: params.actorUid ?? "",
    actorType: params.actorType ?? "unknown",
    status: params.status,
    durationMs: params.durationMs ?? null,
    metadata: params.metadata ?? {},
    createdAt: nowServerTs(),
  });
}

export async function recordMonitoringEvent(params: {
  action: string;
  severity: "info" | "warning" | "critical";
  actorUid?: string;
  message: string;
  metadata?: JsonMap;
}): Promise<void> {
  logger.log("monitoring_event", {
    action: params.action,
    severity: params.severity,
    actorUid: params.actorUid ?? "",
    message: params.message,
    metadata: params.metadata ?? {},
  });
  await db.collection(MONITORING_COLLECTION).add({
    action: params.action,
    severity: params.severity,
    actorUid: params.actorUid ?? "",
    message: params.message,
    metadata: params.metadata ?? {},
    createdAt: nowServerTs(),
  });
}

export async function recordModerationEvent(params: {
  action: string;
  actorUid: string;
  contentType: string;
  severity: string;
  reasons: string[];
  metadata?: JsonMap;
}): Promise<void> {
  await db.collection(MODERATION_COLLECTION).add({
    action: params.action,
    actorUid: params.actorUid,
    contentType: params.contentType,
    severity: params.severity,
    reasons: params.reasons,
    metadata: params.metadata ?? {},
    createdAt: nowServerTs(),
  });
}

export async function recordSecurityAuditEvent(params: {
  action: string;
  actorUid?: string;
  targetType: string;
  targetId?: string;
  status: string;
  metadata?: JsonMap;
}): Promise<void> {
  await db.collection(AUDIT_COLLECTION).add({
    action: params.action,
    actorUid: params.actorUid ?? "",
    targetType: params.targetType,
    targetId: params.targetId ?? "",
    status: params.status,
    metadata: params.metadata ?? {},
    createdAt: nowServerTs(),
  });
}

export async function checkRepeatedContent(params: {
  action: string;
  actorUid: string;
  fingerprint: string;
  threshold?: number;
  windowMs?: number;
}): Promise<boolean> {
  const threshold = Math.max(2, params.threshold ?? 3);
  const windowMs = Math.max(60_000, params.windowMs ?? 10 * 60_000);
  const docRef = db
    .collection(CONTENT_FINGERPRINT_COLLECTION)
    .doc(hashValue(`${params.action}:${params.actorUid}`));
  const now = nowMillis();

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(docRef);
    const rawEntries = Array.isArray(snap.data()?.entries) ?
      snap.data()?.entries as Array<{fingerprint?: unknown; createdAt?: unknown}> :
      [];
    const recent = rawEntries
      .map((entry) => ({
        fingerprint: typeof entry?.fingerprint === "string" ? entry.fingerprint : "",
        createdAt: Number(entry?.createdAt ?? 0),
      }))
      .filter((entry) => entry.fingerprint && entry.createdAt >= now - windowMs);

    const duplicates = recent.filter(
      (entry) => entry.fingerprint === params.fingerprint
    );
    recent.push({fingerprint: params.fingerprint, createdAt: now});

    tx.set(docRef, {
      action: params.action,
      actorUid: params.actorUid,
      entries: recent.slice(-12),
      updatedAt: nowServerTs(),
    }, {merge: true});

    return duplicates.length + 1 >= threshold;
  });
}

export function assertNoUnexpectedFields(
  payload: JsonMap,
  allowedFields: string[]
): void {
  const unexpected = Object.keys(payload).filter(
    (key) => !allowedFields.includes(key)
  );
  if (unexpected.length > 0) {
    throw new HttpsError("invalid-argument", "Payload contains unsupported fields.");
  }
}

export function requireObjectPayload(value: unknown): JsonMap {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpsError("invalid-argument", "Payload must be an object.");
  }
  return value as JsonMap;
}

export function readTrimmedString(value: unknown, maxLength = 500): string {
  const text = typeof value === "string" ? value.trim() : "";
  return text.slice(0, maxLength);
}

export function readRequiredString(
  value: unknown,
  fieldName: string,
  maxLength = 500
): string {
  const text = readTrimmedString(value, maxLength);
  if (!text) {
    throw new HttpsError("invalid-argument", `${fieldName} is required.`);
  }
  return text;
}

export function readBoolean(value: unknown): boolean {
  return value === true;
}

export function readOptionalUrl(value: unknown): string {
  const raw = readTrimmedString(value, 1000);
  if (!raw) return "";
  let parsed: URL;
  try {
    parsed = new URL(raw);
  } catch {
    throw new HttpsError("invalid-argument", "A provided URL is invalid.");
  }
  if (!["http:", "https:"].includes(parsed.protocol)) {
    throw new HttpsError("invalid-argument", "A provided URL is invalid.");
  }
  return parsed.toString();
}

export async function validateUploadedStorageFile(
  expectations: UploadedStorageExpectation
): Promise<void> {
  const normalizedPath = expectations.path.trim().replace(/^\/+/, "");
  if (!normalizedPath) {
    throw new HttpsError("invalid-argument", "Uploaded file path is required.");
  }
  if (
    expectations.ownerPrefix &&
    !normalizedPath.startsWith(expectations.ownerPrefix)
  ) {
    throw new HttpsError("permission-denied", "Uploaded file ownership is invalid.");
  }

  const file = admin.storage().bucket().file(normalizedPath);
  const [exists] = await file.exists();
  if (!exists) {
    throw new HttpsError("not-found", "Uploaded file could not be found.");
  }

  const [metadata] = await file.getMetadata();
  const size = Number(metadata.size ?? 0);
  const contentType = String(metadata.contentType ?? "");

  if (!Number.isFinite(size) || size <= 0 || size > expectations.maxBytes) {
    throw new HttpsError("invalid-argument", "Uploaded file size is invalid.");
  }
  if (!expectations.contentTypePattern.test(contentType)) {
    throw new HttpsError("invalid-argument", "Uploaded file type is invalid.");
  }
}

export async function enforceRateLimitForAuthEvent(params: {
  action: string;
  ipAddress: string;
  subject?: string;
  profile?: RateLimitProfileName;
}): Promise<void> {
  const profile = RATE_LIMIT_PROFILES[params.profile ?? "auth"];
  const keys: RateLimitKey[] = [];
  if (params.ipAddress.trim()) {
    keys.push({scope: "ip", value: params.ipAddress.trim()});
  }
  if ((params.subject ?? "").trim()) {
    keys.push({scope: "subject", value: params.subject!.trim().toLowerCase()});
  }

  for (const key of keys) {
    const result = await consumeRateLimit(params.action, key, profile);
    if (!result.allowed) {
      throw new HttpsError("resource-exhausted", "Too many attempts. Please try again later.");
    }
  }
}

export function secureOnCall<T, Return>(
  options: SecureCallableOptions<T>,
  handler: (request: CallableRequest<T>) => Promise<Return> | Return
) {
  const {
    action,
    analyticsEvent,
    allowAnonymous = false,
    requireAuth = true,
    requireVerifiedEmail = requireAuth && !allowAnonymous,
    rateLimitProfile = "default",
    ...callableOptions
  } = options;

  return onCall<T>(
    {
      enforceAppCheck: ENFORCE_APP_CHECK,
      ...callableOptions,
    },
    async (request): Promise<Return> => {
      const startedAt = nowMillis();
      const identity = buildCallerIdentity(request);
      const ipAddress = detectIpAddress(request.rawRequest);

      try {
        await enforceCallableRuntimePolicy(action, request, {
          allowAnonymous,
          requireAuth,
          requireVerifiedEmail,
          rateLimitProfile,
        });

        const result = await handler(request);
        if (analyticsEvent) {
          await recordPrivacySafeAnalyticsEvent({
            eventType: analyticsEvent,
            action,
            actorUid: identity?.userId,
            actorType: identity == null ?
              "unauthenticated" :
              identity.isAnonymous ? "anonymous" : "user",
            status: "ok",
            durationMs: nowMillis() - startedAt,
          });
        }
        return result;
      } catch (error) {
        logger.error("secure_callable_failed", {
          action,
          actorUid: identity?.userId ?? "",
          ipAddressHash: ipAddress ? hashValue(ipAddress) : "",
          error,
        });

        if (analyticsEvent) {
          await recordPrivacySafeAnalyticsEvent({
            eventType: analyticsEvent,
            action,
            actorUid: identity?.userId,
            actorType: identity == null ?
              "unauthenticated" :
              identity.isAnonymous ? "anonymous" : "user",
            status: error instanceof HttpsError ? "blocked" : "error",
            durationMs: nowMillis() - startedAt,
          });
        }

        if (error instanceof HttpsError) {
          throw sanitizeCallableError(error);
        }
        throw new HttpsError("internal", "Something went wrong. Please try again.");
      }
    }
  );
}

export type {FunctionsErrorCode};
