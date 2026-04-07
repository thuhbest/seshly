import * as logger from "firebase-functions/logger";
import {HttpsError, onCall} from "./callable";
import * as admin from "firebase-admin";

import {deriveTutorApprovalSnapshot} from "./tutorApprovalState";

const REGION = "europe-west1";
const GOLD_TICK_PRICE_ZAR = 30;
const ORGANIZATION_SUBSCRIPTION_PRICE_ZAR = 250;
const SESH_CREDIT_PRICE_ZAR = 2;
const SESH_CREDIT_WELCOME = 3;
const SESH_MINUTE_PRICE_ZAR = 1;
const STUDY_VAULT_COMMISSION_PERCENT = 20;
const SESH_FOCUS_FREE_PASSES = 5;
const SESH_FOCUS_EMERGENCY_PASSES = 2;
const SESH_FOCUS_XP_COST = 50;
const SESH_FOCUS_MINUTE_COST = 10;

type JsonMap = Record<string, unknown>;

export interface SeshCreditPurchaseQuote {
  credits: number;
  amountZar: number;
  currency: string;
}

export interface GoldTickActivationDecision {
  allowed: boolean;
  reason: string;
}

export interface SeshMinutesPurchaseQuote {
  minutes: number;
  amountZar: number;
  currency: string;
}

export interface SeshFocusAllowanceState {
  freeFocusPasses: number;
  focusEmergencyPasses: number;
  seshMinutes: number;
  xp: number;
  needsFreePassReset: boolean;
  needsEmergencyPassReset: boolean;
}

export interface SeshFocusChargeDecision {
  allowed: boolean;
  reason: string;
  resourceType: "free_pass" | "xp" | "sesh_minutes" | "emergency_pass";
  resourceLabel: string;
  nextFreeFocusPasses: number;
  nextFocusEmergencyPasses: number;
  nextSeshMinutes: number;
  nextXp: number;
}

function nowServerTs() {
  return admin.firestore.FieldValue.serverTimestamp();
}

function toTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asNumber(value: unknown, fallback = 0): number {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return fallback;
}

function toInt(value: unknown, fallback = 0): number {
  return Math.round(asNumber(value, fallback));
}

function roundMoney(value: number): number {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

function readTimestampDate(value: unknown): Date | null {
  if (value instanceof admin.firestore.Timestamp) {
    return value.toDate();
  }
  if (
    value &&
    typeof value === "object" &&
    "toDate" in value &&
    typeof (value as {toDate?: unknown}).toDate === "function"
  ) {
    try {
      return ((value as {toDate: () => Date}).toDate());
    } catch {
      return null;
    }
  }
  return null;
}

function isSameMonth(date: Date | null, now: Date): boolean {
  return !!date &&
    date.getUTCFullYear() === now.getUTCFullYear() &&
    date.getUTCMonth() === now.getUTCMonth();
}

function requiredString(value: unknown, fieldName: string): string {
  const trimmed = toTrimmedString(value);
  if (!trimmed) {
    throw new HttpsError("invalid-argument", `${fieldName} is required.`);
  }
  return trimmed;
}

function sanitizeNoteTitle(value: unknown): string {
  return toTrimmedString(value).slice(0, 120);
}

function normalizeIdempotencyKey(raw: unknown, fallbackSeed: string): string {
  const trimmed = toTrimmedString(raw);
  if (trimmed.length >= 12) return trimmed.slice(0, 120);
  return `auto_${fallbackSeed}`;
}

export function buildSeshCreditPurchaseQuote(credits: number): SeshCreditPurchaseQuote {
  const normalizedCredits = Math.max(0, Math.round(credits));
  return {
    credits: normalizedCredits,
    amountZar: roundMoney(normalizedCredits * SESH_CREDIT_PRICE_ZAR),
    currency: "ZAR",
  };
}

export function buildSeshMinutesPurchaseQuote(minutes: number): SeshMinutesPurchaseQuote {
  const normalizedMinutes = Math.max(0, Math.round(minutes));
  return {
    minutes: normalizedMinutes,
    amountZar: roundMoney(normalizedMinutes * SESH_MINUTE_PRICE_ZAR),
    currency: "ZAR",
  };
}

export function deriveSeshFocusAllowanceState(
  userData: JsonMap,
  now = new Date()
): SeshFocusAllowanceState {
  const lastPassReset = readTimestampDate(userData.lastPassReset);
  const lastEmergencyReset = readTimestampDate(userData.lastFocusReset);
  const needsFreePassReset = !isSameMonth(lastPassReset, now);
  const needsEmergencyPassReset = !isSameMonth(lastEmergencyReset, now);

  return {
    freeFocusPasses: needsFreePassReset ?
      SESH_FOCUS_FREE_PASSES :
      Math.max(0, toInt(userData.freeFocusPasses, SESH_FOCUS_FREE_PASSES)),
    focusEmergencyPasses: needsEmergencyPassReset ?
      SESH_FOCUS_EMERGENCY_PASSES :
      Math.max(0, toInt(userData.focusEmergencyPasses, SESH_FOCUS_EMERGENCY_PASSES)),
    seshMinutes: Math.max(0, toInt(userData.seshMinutes, 0)),
    xp: Math.max(0, toInt(userData.xp, 0)),
    needsFreePassReset,
    needsEmergencyPassReset,
  };
}

export function decideSeshFocusStartCharge(
  userData: JsonMap,
  now = new Date()
): SeshFocusChargeDecision {
  const state = deriveSeshFocusAllowanceState(userData, now);
  if (state.freeFocusPasses > 0) {
    return {
      allowed: true,
      reason: "",
      resourceType: "free_pass",
      resourceLabel: "Free Pass",
      nextFreeFocusPasses: state.freeFocusPasses - 1,
      nextFocusEmergencyPasses: state.focusEmergencyPasses,
      nextSeshMinutes: state.seshMinutes,
      nextXp: state.xp,
    };
  }
  if (state.xp >= SESH_FOCUS_XP_COST) {
    return {
      allowed: true,
      reason: "",
      resourceType: "xp",
      resourceLabel: `${SESH_FOCUS_XP_COST} XP`,
      nextFreeFocusPasses: state.freeFocusPasses,
      nextFocusEmergencyPasses: state.focusEmergencyPasses,
      nextSeshMinutes: state.seshMinutes,
      nextXp: state.xp - SESH_FOCUS_XP_COST,
    };
  }
  if (state.seshMinutes >= SESH_FOCUS_MINUTE_COST) {
    return {
      allowed: true,
      reason: "",
      resourceType: "sesh_minutes",
      resourceLabel: `${SESH_FOCUS_MINUTE_COST} Sesh Minutes`,
      nextFreeFocusPasses: state.freeFocusPasses,
      nextFocusEmergencyPasses: state.focusEmergencyPasses,
      nextSeshMinutes: state.seshMinutes - SESH_FOCUS_MINUTE_COST,
      nextXp: state.xp,
    };
  }
  return {
    allowed: false,
    reason: `No free passes available. Need ${SESH_FOCUS_XP_COST} XP or ${SESH_FOCUS_MINUTE_COST} Sesh Minutes.`,
    resourceType: "free_pass",
    resourceLabel: "",
    nextFreeFocusPasses: state.freeFocusPasses,
    nextFocusEmergencyPasses: state.focusEmergencyPasses,
    nextSeshMinutes: state.seshMinutes,
    nextXp: state.xp,
  };
}

export function decideSeshFocusEarlyUnlockCharge(
  userData: JsonMap,
  now = new Date()
): SeshFocusChargeDecision {
  const state = deriveSeshFocusAllowanceState(userData, now);
  if (state.focusEmergencyPasses > 0 && state.xp >= SESH_FOCUS_XP_COST) {
    return {
      allowed: true,
      reason: "",
      resourceType: "emergency_pass",
      resourceLabel: `Emergency Pass + ${SESH_FOCUS_XP_COST} XP`,
      nextFreeFocusPasses: state.freeFocusPasses,
      nextFocusEmergencyPasses: state.focusEmergencyPasses - 1,
      nextSeshMinutes: state.seshMinutes,
      nextXp: state.xp - SESH_FOCUS_XP_COST,
    };
  }
  if (state.seshMinutes >= SESH_FOCUS_MINUTE_COST &&
      state.xp >= SESH_FOCUS_XP_COST) {
    return {
      allowed: true,
      reason: "",
      resourceType: "sesh_minutes",
      resourceLabel: `${SESH_FOCUS_MINUTE_COST} Sesh Minutes + ${SESH_FOCUS_XP_COST} XP`,
      nextFreeFocusPasses: state.freeFocusPasses,
      nextFocusEmergencyPasses: state.focusEmergencyPasses,
      nextSeshMinutes: state.seshMinutes - SESH_FOCUS_MINUTE_COST,
      nextXp: state.xp - SESH_FOCUS_XP_COST,
    };
  }
  return {
    allowed: false,
    reason: `Need 1 emergency pass plus ${SESH_FOCUS_XP_COST} XP, or ${SESH_FOCUS_MINUTE_COST} Sesh Minutes plus ${SESH_FOCUS_XP_COST} XP, to unlock early.`,
    resourceType: "emergency_pass",
    resourceLabel: "",
    nextFreeFocusPasses: state.freeFocusPasses,
    nextFocusEmergencyPasses: state.focusEmergencyPasses,
    nextSeshMinutes: state.seshMinutes,
    nextXp: state.xp,
  };
}

export function decideGoldTickActivation(userData: JsonMap): GoldTickActivationDecision {
  const approval = deriveTutorApprovalSnapshot({userData});
  const goldTick = (userData.goldTick as JsonMap | undefined) ?? {};
  const eligibilityStatus = toTrimmedString(goldTick.eligibilityStatus).toLowerCase();
  const subscriptionStatus = toTrimmedString(goldTick.subscriptionStatus).toLowerCase();
  const billingSetupStatus = toTrimmedString(userData.billingSetupStatus).toLowerCase();
  const last4 = toTrimmedString(userData.billingCardLast4);
  const providerReference = toTrimmedString(
    userData.billingProviderReference || userData.billingRegistrationId
  );

  if (!approval.approvedForTutoring) {
    return {
      allowed: false,
      reason: "Gold Tick is only available to approved tutors.",
    };
  }
  if (eligibilityStatus !== "eligible") {
    return {
      allowed: false,
      reason: toTrimmedString(goldTick.eligibilityReason) ||
        "Gold Tick is still locked until your tutor quality record qualifies.",
    };
  }
  if (subscriptionStatus === "active") {
    return {
      allowed: false,
      reason: "Gold Tick is already active.",
    };
  }
  if (billingSetupStatus !== "ready" || !last4 || !providerReference) {
    return {
      allowed: false,
      reason: "Add a verified payment method before activating Gold Tick.",
    };
  }
  return {allowed: true, reason: ""};
}

async function writeSecurityAuditLog(params: {
  action: string;
  actorUid: string;
  targetType: string;
  targetId: string;
  status: "succeeded" | "blocked";
  metadata?: JsonMap;
}): Promise<void> {
  const db = admin.firestore();
  const entry = {
    action: params.action,
    actorUid: params.actorUid,
    targetType: params.targetType,
    targetId: params.targetId,
    status: params.status,
    metadata: params.metadata ?? {},
    createdAt: nowServerTs(),
  };
  logger.info("security_audit", entry);
  await db.collection("security_audit_logs").add(entry);
}

async function runIdempotentMutation<T>(params: {
  userId: string;
  operation: string;
  idempotencyKey: string;
  execute: (
    tx: admin.firestore.Transaction,
    idempotencyRef: admin.firestore.DocumentReference
  ) => Promise<T>;
}): Promise<T> {
  const db = admin.firestore();
  const idempotencyRef = db
    .collection("entitlement_idempotency")
    .doc(`${params.userId}_${params.operation}_${params.idempotencyKey}`);

  return db.runTransaction(async (tx) => {
    const existing = await tx.get(idempotencyRef);
    if (existing.exists) {
      const data = existing.data() ?? {};
      if ((data.status ?? "") === "completed") {
        return data.result as T;
      }
      throw new HttpsError(
        "aborted",
        "This request is already being processed. Please wait a moment."
      );
    }

    tx.set(idempotencyRef, {
      userId: params.userId,
      operation: params.operation,
      status: "processing",
      createdAt: nowServerTs(),
      updatedAt: nowServerTs(),
    });

    const result = await params.execute(tx, idempotencyRef);
    tx.set(idempotencyRef, {
      status: "completed",
      result,
      updatedAt: nowServerTs(),
    }, {merge: true});
    return result;
  });
}

function assertSignedIn(auth: {uid?: string} | null): string {
  const uid = toTrimmedString(auth?.uid);
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be logged in.");
  }
  return uid;
}

function assertPositiveBundle(credits: unknown): number {
  const normalized = toInt(credits, 0);
  if (![5, 15, 30].includes(normalized)) {
    throw new HttpsError(
      "invalid-argument",
      "Unsupported SeshCredit bundle selected."
    );
  }
  return normalized;
}

function assertPositiveSeshMinutes(minutes: unknown): number {
  const normalized = Math.max(0, toInt(minutes, 0));
  if (normalized < 10 || normalized > 600 || normalized % 5 != 0) {
    throw new HttpsError(
      "invalid-argument",
      "Unsupported Sesh Minutes package selected."
    );
  }
  return normalized;
}

function assertFocusDurationMinutes(minutes: unknown): number {
  const normalized = Math.max(0, toInt(minutes, 0));
  if (normalized < 10 || normalized > 360) {
    throw new HttpsError(
      "invalid-argument",
      "Focus duration must be between 10 and 360 minutes."
    );
  }
  return normalized;
}

function assertFullStudentAccount(userData: JsonMap): void {
  const accountType = toTrimmedString(userData.accountType).toLowerCase();
  const accessTier = toTrimmedString(userData.accessTier).toLowerCase();
  if (accountType === "instant_tutor" || accessTier === "instant_tutor") {
    throw new HttpsError(
      "failed-precondition",
      "Guest tutoring mode cannot access verified-student-only entitlements."
    );
  }
}

function hasBillingReadiness(userData: JsonMap): boolean {
  return toTrimmedString(userData.billingSetupStatus).toLowerCase() === "ready" &&
    !!toTrimmedString(userData.billingCardLast4) &&
    !!toTrimmedString(userData.billingProviderReference || userData.billingRegistrationId);
}

function buildFocusResetPatch(
  state: SeshFocusAllowanceState,
  now: admin.firestore.FieldValue
): JsonMap {
  const patch: JsonMap = {};
  if (state.needsFreePassReset) {
    patch.freeFocusPasses = state.freeFocusPasses;
    patch.lastPassReset = now;
  }
  if (state.needsEmergencyPassReset) {
    patch.focusEmergencyPasses = state.focusEmergencyPasses;
    patch.lastFocusReset = now;
  }
  return patch;
}

export const ensureSeshCreditBootstrap = onCall(
  {region: REGION},
  async (request) => {
    const userId = assertSignedIn(request.auth ?? null);
    const db = admin.firestore();
    const userRef = db.collection("users").doc(userId);

    const result = await db.runTransaction(async (tx) => {
      const userSnap = await tx.get(userRef);
      if (!userSnap.exists) {
        throw new HttpsError("not-found", "User not found.");
      }
      const data = userSnap.data() ?? {};
      assertFullStudentAccount(data);
      const hasBalance = data.seshCreditBalance !== undefined;
      const balance = hasBalance ?
        Math.max(0, toInt(data.seshCreditBalance, 0)) :
        SESH_CREDIT_WELCOME;

      tx.set(userRef, {
        seshCreditBalance: balance,
        seshCreditCurrency: "ZAR",
        seshCreditValueZar: SESH_CREDIT_PRICE_ZAR,
        seshCreditPurchasedTotal: toInt(data.seshCreditPurchasedTotal, 0),
        seshCreditUsedTotal: toInt(data.seshCreditUsedTotal, 0),
        seshCreditSpendTotalZar: roundMoney(asNumber(data.seshCreditSpendTotalZar, 0)),
        seshCreditIntroGranted: true,
        seshCreditIntroCredits: SESH_CREDIT_WELCOME,
        seshCreditUpdatedAt: nowServerTs(),
      }, {merge: true});

      return {balance};
    });

    return result;
  }
);

export const purchaseSeshCredits = onCall(
  {region: REGION},
  async (request) => {
    const userId = assertSignedIn(request.auth ?? null);
    const credits = assertPositiveBundle(request.data?.credits);
    const source = toTrimmedString(request.data?.source) || "store";
    const quote = buildSeshCreditPurchaseQuote(credits);
    const idempotencyKey = normalizeIdempotencyKey(
      request.data?.idempotencyKey,
      `${userId}_${credits}_${source}`
    );
    const db = admin.firestore();
    const userRef = db.collection("users").doc(userId);

    const result = await runIdempotentMutation({
      userId,
      operation: "purchase_sesh_credits",
      idempotencyKey,
      execute: async (tx) => {
        const userSnap = await tx.get(userRef);
        if (!userSnap.exists) {
          throw new HttpsError("not-found", "User not found.");
        }
        const data = userSnap.data() ?? {};
        assertFullStudentAccount(data);
        const currentBalance = Math.max(0, toInt(data.seshCreditBalance, SESH_CREDIT_WELCOME));
        const purchasedTotal = Math.max(0, toInt(data.seshCreditPurchasedTotal, 0));
        const usedTotal = Math.max(0, toInt(data.seshCreditUsedTotal, 0));
        const spendTotal = roundMoney(asNumber(data.seshCreditSpendTotalZar, 0));
        const nextBalance = currentBalance + quote.credits;
        const txRef = userRef.collection("seshcredit_transactions").doc();
        const paymentRef = userRef.collection("payment_transactions").doc();

        tx.set(userRef, {
          seshCreditBalance: nextBalance,
          seshCreditCurrency: "ZAR",
          seshCreditValueZar: SESH_CREDIT_PRICE_ZAR,
          seshCreditPurchasedTotal: purchasedTotal + quote.credits,
          seshCreditUsedTotal: usedTotal,
          seshCreditSpendTotalZar: roundMoney(spendTotal + quote.amountZar),
          seshCreditIntroGranted: data.seshCreditIntroGranted === true,
          seshCreditIntroCredits: Math.max(0, toInt(data.seshCreditIntroCredits, SESH_CREDIT_WELCOME)),
          seshCreditUpdatedAt: nowServerTs(),
        }, {merge: true});

        tx.set(txRef, {
          type: "purchase",
          paymentRail: "SESH_CREDITS",
          creditsDelta: quote.credits,
          balanceAfter: nextBalance,
          amountZar: quote.amountZar,
          unitPriceZar: SESH_CREDIT_PRICE_ZAR,
          source,
          idempotencyKey,
          paymentVerificationStatus: "mock_verified",
          createdAt: nowServerTs(),
        });

        tx.set(paymentRef, {
          type: "sesh_credit_purchase",
          direction: "debit",
          status: "captured",
          amountZar: quote.amountZar,
          currency: "ZAR",
          productName: `SeshCredits x${quote.credits}`,
          paymentRail: "SESH_CREDITS",
          paymentVerificationStatus: "mock_verified",
          idempotencyKey,
          createdAt: nowServerTs(),
        });

        return {
          balance: nextBalance,
          creditsPurchased: quote.credits,
          amountZar: quote.amountZar,
        };
      },
    });

    await writeSecurityAuditLog({
      action: "purchase_sesh_credits",
      actorUid: userId,
      targetType: "user",
      targetId: userId,
      status: "succeeded",
      metadata: {
        credits,
        amountZar: quote.amountZar,
        idempotencyKey,
      },
    });

    return result;
  }
);

export const unlockLectureCapture = onCall(
  {region: REGION},
  async (request) => {
    const userId = assertSignedIn(request.auth ?? null);
    const folderId = requiredString(request.data?.folderId, "folderId");
    const noteId = requiredString(request.data?.noteId, "noteId");
    const noteTitle = sanitizeNoteTitle(request.data?.noteTitle);
    const idempotencyKey = normalizeIdempotencyKey(
      request.data?.idempotencyKey,
      `${userId}_${folderId}_${noteId}`
    );
    const db = admin.firestore();
    const userRef = db.collection("users").doc(userId);
    const noteRef = userRef.collection("note_folders").doc(folderId)
      .collection("notes").doc(noteId);

    const result = await runIdempotentMutation({
      userId,
      operation: "unlock_lecture_capture",
      idempotencyKey,
      execute: async (tx) => {
        const [userSnap, noteSnap] = await Promise.all([
          tx.get(userRef),
          tx.get(noteRef),
        ]);
        if (!userSnap.exists) {
          throw new HttpsError("not-found", "User not found.");
        }
        if (!noteSnap.exists) {
          throw new HttpsError("not-found", "This note no longer exists.");
        }
        const userData = userSnap.data() ?? {};
        assertFullStudentAccount(userData);
        const noteData = noteSnap.data() ?? {};
        const currentBalance = Math.max(0, toInt(userData.seshCreditBalance, SESH_CREDIT_WELCOME));

        if (noteData.lectureCaptureUnlocked === true) {
          return {balance: currentBalance, alreadyUnlocked: true};
        }
        if (currentBalance < 1) {
          throw new HttpsError(
            "failed-precondition",
            "You need at least 1 SeshCredit to unlock lecture capture."
          );
        }

        const nextBalance = currentBalance - 1;
        const purchasedTotal = Math.max(0, toInt(userData.seshCreditPurchasedTotal, 0));
        const usedTotal = Math.max(0, toInt(userData.seshCreditUsedTotal, 0));
        const spendTotal = roundMoney(asNumber(userData.seshCreditSpendTotalZar, 0));
        const txRef = userRef.collection("seshcredit_transactions").doc();

        tx.set(userRef, {
          seshCreditBalance: nextBalance,
          seshCreditPurchasedTotal: purchasedTotal,
          seshCreditUsedTotal: usedTotal + 1,
          seshCreditSpendTotalZar: spendTotal,
          seshCreditUpdatedAt: nowServerTs(),
        }, {merge: true});

        tx.set(noteRef, {
          noteMode: "lecture",
          lectureCaptureUnlocked: true,
          lectureCaptureUnlockedAt: nowServerTs(),
          updatedAt: nowServerTs(),
        }, {merge: true});

        tx.set(txRef, {
          type: "lecture_unlock",
          paymentRail: "SESH_CREDITS",
          creditsDelta: -1,
          balanceAfter: nextBalance,
          amountZar: SESH_CREDIT_PRICE_ZAR,
          unitPriceZar: SESH_CREDIT_PRICE_ZAR,
          folderId,
          noteId,
          noteTitle,
          idempotencyKey,
          createdAt: nowServerTs(),
        });

        return {balance: nextBalance, alreadyUnlocked: false};
      },
    });

    await writeSecurityAuditLog({
      action: "unlock_lecture_capture",
      actorUid: userId,
      targetType: "note",
      targetId: noteId,
      status: "succeeded",
      metadata: {
        folderId,
        noteId,
        idempotencyKey,
      },
    });

    return result;
  }
);

export const activateGoldTickSubscription = onCall(
  {region: REGION},
  async (request) => {
    const userId = assertSignedIn(request.auth ?? null);
    const idempotencyKey = normalizeIdempotencyKey(
      request.data?.idempotencyKey,
      `${userId}_gold_tick`
    );
    const db = admin.firestore();
    const userRef = db.collection("users").doc(userId);
    const subscriptionRef = db.collection("gold_tick_subscriptions").doc(userId);

    const result = await runIdempotentMutation({
      userId,
      operation: "activate_gold_tick",
      idempotencyKey,
      execute: async (tx) => {
        const userSnap = await tx.get(userRef);
        if (!userSnap.exists) {
          throw new HttpsError("not-found", "Tutor not found.");
        }
        const userData = userSnap.data() ?? {};
        const decision = decideGoldTickActivation(userData);
        if (!decision.allowed) {
          throw new HttpsError("failed-precondition", decision.reason);
        }
        const now = new Date();
        const periodEnd = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);
        const paymentRef = userRef.collection("payment_transactions").doc();

        tx.set(subscriptionRef, {
          tutorId: userId,
          productName: "Gold Tick",
          priceZar: GOLD_TICK_PRICE_ZAR,
          currency: "ZAR",
          billingPeriod: "monthly",
          status: "active",
          paymentMethodType: "card",
          paymentMethodSummary:
            `${toTrimmedString(userData.billingCardBrand) || "Card"} •••• ${toTrimmedString(userData.billingCardLast4)}`,
          paymentMethodId: toTrimmedString(userData.billingDefaultPaymentMethodId),
          subscriptionModel: "mock_saved_card_monthly",
          paymentVerificationStatus: "mock_verified",
          currentPeriodStart: admin.firestore.Timestamp.fromDate(now),
          currentPeriodEnd: admin.firestore.Timestamp.fromDate(periodEnd),
          activatedAt: nowServerTs(),
          updatedAt: nowServerTs(),
        }, {merge: true});

        tx.set(paymentRef, {
          type: "gold_tick_subscription",
          direction: "debit",
          status: "captured",
          amountZar: GOLD_TICK_PRICE_ZAR,
          currency: "ZAR",
          productName: "Gold Tick",
          paymentRail: "GOLD_TICK",
          paymentVerificationStatus: "mock_verified",
          idempotencyKey,
          createdAt: nowServerTs(),
        });

        return {
          status: "active",
          currentPeriodEndIso: periodEnd.toISOString(),
          amountZar: GOLD_TICK_PRICE_ZAR,
        };
      },
    });

    await writeSecurityAuditLog({
      action: "activate_gold_tick",
      actorUid: userId,
      targetType: "gold_tick_subscription",
      targetId: userId,
      status: "succeeded",
      metadata: {idempotencyKey},
    });

    return result;
  }
);

export const activateOrganizationSubscription = onCall(
  {region: REGION},
  async (request) => {
    const userId = assertSignedIn(request.auth ?? null);
    const organizationId = requiredString(request.data?.organizationId, "organizationId");
    const idempotencyKey = normalizeIdempotencyKey(
      request.data?.idempotencyKey,
      `${userId}_${organizationId}_organization`
    );
    const db = admin.firestore();
    const userRef = db.collection("users").doc(userId);
    const orgRef = db.collection("tutor_organizations").doc(organizationId);
    const subscriptionRef = db.collection("organization_subscriptions").doc(organizationId);

    const result = await runIdempotentMutation({
      userId,
      operation: "activate_organization_subscription",
      idempotencyKey,
      execute: async (tx) => {
        const [userSnap, orgSnap] = await Promise.all([tx.get(userRef), tx.get(orgRef)]);
        if (!userSnap.exists) {
          throw new HttpsError("not-found", "User not found.");
        }
        if (!orgSnap.exists) {
          throw new HttpsError("not-found", "Organization not found.");
        }

        const userData = userSnap.data() ?? {};
        const orgData = orgSnap.data() ?? {};
        const approval = deriveTutorApprovalSnapshot({userData});
        if (!approval.approvedForTutoring) {
          throw new HttpsError(
            "failed-precondition",
            "Only approved tutors can activate an organization account."
          );
        }

        const adminUserIds = Array.isArray(orgData.adminUserIds) ?
          orgData.adminUserIds.map((value: unknown) => toTrimmedString(value)) :
          [];
        const isOwner = toTrimmedString(orgData.ownerUserId) === userId;
        const isAdmin = adminUserIds.includes(userId) || isOwner;
        if (!isAdmin) {
          throw new HttpsError(
            "permission-denied",
            "Only organization admins can activate the organization account."
          );
        }
        if (
          toTrimmedString(userData.billingSetupStatus).toLowerCase() !== "ready" ||
          !toTrimmedString(userData.billingCardLast4) ||
          !toTrimmedString(userData.billingProviderReference || userData.billingRegistrationId)
        ) {
          throw new HttpsError(
            "failed-precondition",
            "Add a verified payment method before activating the organization account."
          );
        }

        const now = new Date();
        const periodEnd = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);
        const paymentRef = userRef.collection("payment_transactions").doc();

        tx.set(subscriptionRef, {
          organizationId,
          productName: "Organization Account",
          priceZar: ORGANIZATION_SUBSCRIPTION_PRICE_ZAR,
          currency: "ZAR",
          billingPeriod: "monthly",
          status: "active",
          paymentMethodType: "card",
          paymentMethodSummary:
            `${toTrimmedString(userData.billingCardBrand) || "Card"} •••• ${toTrimmedString(userData.billingCardLast4)}`,
          paymentMethodId: toTrimmedString(userData.billingDefaultPaymentMethodId),
          subscriptionModel: "mock_org_card_monthly",
          billingOwnerUserId: userId,
          paymentVerificationStatus: "mock_verified",
          currentPeriodStart: admin.firestore.Timestamp.fromDate(now),
          currentPeriodEnd: admin.firestore.Timestamp.fromDate(periodEnd),
          activatedAt: nowServerTs(),
          updatedAt: nowServerTs(),
        }, {merge: true});

        tx.set(paymentRef, {
          type: "organization_account_subscription",
          direction: "debit",
          status: "captured",
          amountZar: ORGANIZATION_SUBSCRIPTION_PRICE_ZAR,
          currency: "ZAR",
          productName: "Organization Account",
          organizationId,
          organizationName: toTrimmedString(orgData.name),
          paymentRail: "ORGANIZATION_SUBSCRIPTION",
          paymentVerificationStatus: "mock_verified",
          idempotencyKey,
          createdAt: nowServerTs(),
        });

        return {
          status: "active",
          organizationId,
          currentPeriodEndIso: periodEnd.toISOString(),
          amountZar: ORGANIZATION_SUBSCRIPTION_PRICE_ZAR,
        };
      },
    });

    await writeSecurityAuditLog({
      action: "activate_organization_subscription",
      actorUid: userId,
      targetType: "organization_subscription",
      targetId: organizationId,
      status: "succeeded",
      metadata: {idempotencyKey},
    });

    return result;
  }
);

export const purchaseSeshMinutes = onCall(
  {region: REGION},
  async (request) => {
    const userId = assertSignedIn(request.auth ?? null);
    const minutes = assertPositiveSeshMinutes(request.data?.minutes);
    const quote = buildSeshMinutesPurchaseQuote(minutes);
    const source = toTrimmedString(request.data?.source) || "focus_store";
    const idempotencyKey = normalizeIdempotencyKey(
      request.data?.idempotencyKey,
      `${userId}_${minutes}_${source}`
    );
    const db = admin.firestore();
    const userRef = db.collection("users").doc(userId);

    const result = await runIdempotentMutation({
      userId,
      operation: "purchase_sesh_minutes",
      idempotencyKey,
      execute: async (tx) => {
        const userSnap = await tx.get(userRef);
        if (!userSnap.exists) {
          throw new HttpsError("not-found", "User not found.");
        }
        const userData = userSnap.data() ?? {};
        assertFullStudentAccount(userData);
        const currentMinutes = Math.max(0, toInt(userData.seshMinutes, 0));
        const nextMinutes = currentMinutes + quote.minutes;
        const paymentRef = userRef.collection("payment_transactions").doc();

        tx.set(userRef, {
          seshMinutes: nextMinutes,
          lastEntitlementAt: nowServerTs(),
        }, {merge: true});

        tx.set(paymentRef, {
          type: "sesh_minutes_purchase",
          direction: "debit",
          status: "captured",
          amountZar: quote.amountZar,
          currency: quote.currency,
          productName: `Sesh Minutes x${quote.minutes}`,
          paymentRail: "SESH_MINUTES",
          paymentVerificationStatus: "mock_verified",
          idempotencyKey,
          createdAt: nowServerTs(),
        });

        return {
          minutesBalance: nextMinutes,
          minutesPurchased: quote.minutes,
          amountZar: quote.amountZar,
        };
      },
    });

    await writeSecurityAuditLog({
      action: "purchase_sesh_minutes",
      actorUid: userId,
      targetType: "user",
      targetId: userId,
      status: "succeeded",
      metadata: {
        minutes,
        amountZar: quote.amountZar,
        idempotencyKey,
      },
    });

    return result;
  }
);

export const getSeshFocusStatus = onCall(
  {region: REGION},
  async (request) => {
    const userId = assertSignedIn(request.auth ?? null);
    const db = admin.firestore();
    const userRef = db.collection("users").doc(userId);

    return db.runTransaction(async (tx) => {
      const userSnap = await tx.get(userRef);
      if (!userSnap.exists) {
        throw new HttpsError("not-found", "User not found.");
      }
      const userData = userSnap.data() ?? {};
      assertFullStudentAccount(userData);
      const state = deriveSeshFocusAllowanceState(userData);
      const resetPatch = buildFocusResetPatch(state, nowServerTs());
      if (Object.keys(resetPatch).length > 0) {
        tx.set(userRef, resetPatch, {merge: true});
      }
      return {
        freeFocusPasses: state.freeFocusPasses,
        focusEmergencyPasses: state.focusEmergencyPasses,
        seshMinutes: state.seshMinutes,
        xp: state.xp,
      };
    });
  }
);

export const consumeSeshFocusAccess = onCall(
  {region: REGION},
  async (request) => {
    const userId = assertSignedIn(request.auth ?? null);
    const durationMinutes = assertFocusDurationMinutes(request.data?.durationMinutes);
    const idempotencyKey = normalizeIdempotencyKey(
      request.data?.idempotencyKey,
      `${userId}_focus_start_${durationMinutes}_${Math.floor(Date.now() / 30000)}`
    );
    const db = admin.firestore();
    const userRef = db.collection("users").doc(userId);

    const result = await runIdempotentMutation({
      userId,
      operation: "consume_sesh_focus_access",
      idempotencyKey,
      execute: async (tx) => {
        const userSnap = await tx.get(userRef);
        if (!userSnap.exists) {
          throw new HttpsError("not-found", "User not found.");
        }
        const userData = userSnap.data() ?? {};
        assertFullStudentAccount(userData);
        const state = deriveSeshFocusAllowanceState(userData);
        const decision = decideSeshFocusStartCharge(userData);
        if (!decision.allowed) {
          throw new HttpsError("failed-precondition", decision.reason);
        }

        const focusSessionRef = db.collection("focusSessions").doc();
        const patch: JsonMap = {
          ...buildFocusResetPatch(state, nowServerTs()),
          freeFocusPasses: decision.nextFreeFocusPasses,
          focusEmergencyPasses: state.focusEmergencyPasses,
          seshMinutes: decision.nextSeshMinutes,
          xp: decision.nextXp,
          lastFocusSession: nowServerTs(),
        };

        tx.set(userRef, patch, {merge: true});
        tx.set(focusSessionRef, {
          userId,
          duration: durationMinutes,
          usedPass: decision.resourceType === "free_pass",
          resourceUsed: decision.resourceLabel,
          accessSource: decision.resourceType,
          status: "started",
          createdAt: nowServerTs(),
          updatedAt: nowServerTs(),
        });

        return {
          focusSessionId: focusSessionRef.id,
          resourceUsed: decision.resourceLabel,
          resourceType: decision.resourceType,
          freeFocusPasses: decision.nextFreeFocusPasses,
          seshMinutes: decision.nextSeshMinutes,
          xp: decision.nextXp,
        };
      },
    });

    await writeSecurityAuditLog({
      action: "consume_sesh_focus_access",
      actorUid: userId,
      targetType: "focus_session",
      targetId: String(result.focusSessionId ?? ""),
      status: "succeeded",
      metadata: {
        durationMinutes,
        idempotencyKey,
      },
    });

    return result;
  }
);

export const unlockSeshFocusEarly = onCall(
  {region: REGION},
  async (request) => {
    const userId = assertSignedIn(request.auth ?? null);
    const idempotencyKey = normalizeIdempotencyKey(
      request.data?.idempotencyKey,
      `${userId}_focus_unlock_${Math.floor(Date.now() / 30000)}`
    );
    const db = admin.firestore();
    const userRef = db.collection("users").doc(userId);

    const result = await runIdempotentMutation({
      userId,
      operation: "unlock_sesh_focus_early",
      idempotencyKey,
      execute: async (tx) => {
        const userSnap = await tx.get(userRef);
        if (!userSnap.exists) {
          throw new HttpsError("not-found", "User not found.");
        }
        const userData = userSnap.data() ?? {};
        assertFullStudentAccount(userData);
        const state = deriveSeshFocusAllowanceState(userData);
        const decision = decideSeshFocusEarlyUnlockCharge(userData);
        if (!decision.allowed) {
          throw new HttpsError("failed-precondition", decision.reason);
        }

        tx.set(userRef, {
          ...buildFocusResetPatch(state, nowServerTs()),
          focusEmergencyPasses: decision.nextFocusEmergencyPasses,
          seshMinutes: decision.nextSeshMinutes,
          xp: decision.nextXp,
          lastFocusSession: nowServerTs(),
        }, {merge: true});

        return {
          unlocked: true,
          resourceUsed: decision.resourceLabel,
          focusEmergencyPasses: decision.nextFocusEmergencyPasses,
          seshMinutes: decision.nextSeshMinutes,
          xp: decision.nextXp,
        };
      },
    });

    await writeSecurityAuditLog({
      action: "unlock_sesh_focus_early",
      actorUid: userId,
      targetType: "user",
      targetId: userId,
      status: "succeeded",
      metadata: {idempotencyKey},
    });

    return result;
  }
);

export const purchaseStudyVaultResource = onCall(
  {region: REGION},
  async (request) => {
    const userId = assertSignedIn(request.auth ?? null);
    const resourceId = requiredString(request.data?.resourceId, "resourceId");
    const idempotencyKey = normalizeIdempotencyKey(
      request.data?.idempotencyKey,
      `${userId}_${resourceId}`
    );
    const db = admin.firestore();
    const userRef = db.collection("users").doc(userId);
    const resourceRef = db.collection("vault").doc(resourceId);
    const purchaseRef = db.collection("vault_purchase_intents").doc(`${resourceId}_${userId}`);

    const result = await runIdempotentMutation({
      userId,
      operation: "purchase_study_vault_resource",
      idempotencyKey,
      execute: async (tx) => {
        const [userSnap, resourceSnap, existingPurchaseSnap] = await Promise.all([
          tx.get(userRef),
          tx.get(resourceRef),
          tx.get(purchaseRef),
        ]);
        if (!userSnap.exists) {
          throw new HttpsError("not-found", "User not found.");
        }
        if (!resourceSnap.exists) {
          throw new HttpsError("not-found", "StudyVault resource not found.");
        }

        const userData = userSnap.data() ?? {};
        const resourceData = resourceSnap.data() ?? {};
        assertFullStudentAccount(userData);

        if (!hasBillingReadiness(userData)) {
          throw new HttpsError(
            "failed-precondition",
            "Add a verified billing card before unlocking paid StudyVault resources."
          );
        }

        const sellerId = requiredString(
          resourceData.userId || resourceData.ownerId || resourceData.uploaderId,
          "sellerId"
        );
        if (sellerId === userId) {
          return {alreadyPurchased: true, resourceId};
        }

        const purchasedBy = Array.isArray(resourceData.purchasedBy) ?
          resourceData.purchasedBy.map((value: unknown) => toTrimmedString(value)) :
          [];
        if (purchasedBy.includes(userId)) {
          return {alreadyPurchased: true, resourceId};
        }
        if (
          existingPurchaseSnap.exists &&
          toTrimmedString(existingPurchaseSnap.data()?.accessStatus) === "granted"
        ) {
          return {alreadyPurchased: true, resourceId};
        }

        const priceZar = Math.max(0, toInt(resourceData.priceZar, 0));
        const accessType = toTrimmedString(resourceData.accessType).toLowerCase();
        if (accessType !== "paid" || priceZar <= 0) {
          throw new HttpsError(
            "failed-precondition",
            "Only paid StudyVault resources can be unlocked from this flow."
          );
        }

        const platformFeeZar = Math.round((priceZar * STUDY_VAULT_COMMISSION_PERCENT) / 100);
        const sellerNetZar = priceZar - platformFeeZar;
        const title = toTrimmedString(
          resourceData.title || resourceData.moduleName || resourceData.subject
        ) || "Study resource";
        const paymentSummary =
          `${toTrimmedString(userData.billingCardBrand) || "Card"} •••• ${toTrimmedString(userData.billingCardLast4)}`;
        const buyerPaymentRef = userRef.collection("payment_transactions").doc();
        const sellerRef = db.collection("users").doc(sellerId);

        tx.set(purchaseRef, {
          resourceId,
          resourceTitle: title,
          buyerId: userId,
          sellerId,
          priceZar,
          currency: "ZAR",
          platformCommissionPercent: STUDY_VAULT_COMMISSION_PERCENT,
          platformFeeZar,
          sellerNetZar,
          paymentMethodType: "card",
          paymentMethodSummary: paymentSummary,
          paymentStatus: "captured",
          paymentVerificationStatus: "mock_verified",
          accessStatus: "granted",
          idempotencyKey,
          createdAt: nowServerTs(),
          updatedAt: nowServerTs(),
        });

        tx.set(resourceRef, {
          purchaseCount: admin.firestore.FieldValue.increment(1),
          purchasedBy: admin.firestore.FieldValue.arrayUnion(userId),
          lastPurchasedAt: nowServerTs(),
        }, {merge: true});

        tx.set(userRef, {
          studyVaultPurchaseCount: admin.firestore.FieldValue.increment(1),
          studyVaultSpendTotalZar: admin.firestore.FieldValue.increment(priceZar),
          billingSpendTotalZar: admin.firestore.FieldValue.increment(priceZar),
        }, {merge: true});

        tx.set(sellerRef, {
          studyVaultSalesCount: admin.firestore.FieldValue.increment(1),
          studyVaultRevenueZar: admin.firestore.FieldValue.increment(sellerNetZar),
        }, {merge: true});

        tx.set(buyerPaymentRef, {
          type: "study_vault_purchase",
          direction: "debit",
          status: "captured",
          amountZar: priceZar,
          currency: "ZAR",
          productName: title,
          paymentRail: "STUDY_VAULT",
          paymentVerificationStatus: "mock_verified",
          relatedResourceId: resourceId,
          relatedSellerId: sellerId,
          idempotencyKey,
          createdAt: nowServerTs(),
        });

        return {
          alreadyPurchased: false,
          resourceId,
          priceZar,
          sellerNetZar,
          platformFeeZar,
        };
      },
    });

    await writeSecurityAuditLog({
      action: "purchase_study_vault_resource",
      actorUid: userId,
      targetType: "vault_resource",
      targetId: resourceId,
      status: "succeeded",
      metadata: {idempotencyKey},
    });

    return result;
  }
);
