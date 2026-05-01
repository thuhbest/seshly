import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {HttpsError, onCall} from "./callable";
import {
  deriveTutorApprovalSnapshot,
  toTrimmedString,
} from "./tutorApprovalState";
import {
  asMoney,
  toMoney,
  timestampToMillis,
} from "./tutorPayoutModels";
import {
  deriveTutorPayoutVerificationStatus,
  isVerifiedTutorPayoutProfile,
} from "./tutorPayoutProfileState";
import {
  buildTutorPayoutDashboardDoc,
  TUTORING_PAYMENT_TIME_ZONE,
  TUTORING_PAYOUT_LOCAL_TIME,
} from "./tutoringFirestoreSchema";

const db = admin.firestore();
const REGION = "europe-west1";
const OPEN_PAYOUT_STATUSES = new Set([
  "PENDING",
  "REQUESTED",
  "APPROVED",
  "PROCESSING",
]);
const HISTORY_PREVIEW_LIMIT = 10;
const FAILED_NOTICE_LIMIT = 5;

interface TutorPayoutDashboardProfileView {
  payoutProfileId: string;
  tutorId: string;
  payoutEnabled: boolean;
  verificationStatus: string;
  status: string;
  bankName: string | null;
  accountNumberMasked: string | null;
  payoutBlockedReason: string | null;
  isDefault: boolean;
  recipientCode: string | null;
}

interface TutorPayoutHistoryPreviewItem {
  payoutId: string;
  payoutWeekKey: string | null;
  status: string;
  providerStatus: string;
  amountZar: number;
  currency: string;
  payoutKind: string | null;
  failureReason: string | null;
  requestedAt: string | null;
  paidAt: string | null;
  failedAt: string | null;
}

interface TutorFailedPayoutNoticeItem {
  payoutId: string;
  payoutWeekKey: string | null;
  amountZar: number;
  currency: string;
  failureReason: string | null;
  failedAt: string | null;
}

interface TutorPayoutBlockedReason {
  code: string | null;
  message: string | null;
}

function nowServerTs() {
  return admin.firestore.FieldValue.serverTimestamp();
}

function timestampToIso(value: unknown): string | null {
  if (value instanceof admin.firestore.Timestamp) {
    return value.toDate().toISOString();
  }
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return value.toISOString();
  }
  if (typeof value === "string") {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
  }
  return null;
}

function dateKeyInTimeZone(
  date: Date,
  timeZone = TUTORING_PAYMENT_TIME_ZONE
): string {
  return new Intl.DateTimeFormat("sv-SE", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

function weekdayShort(
  date: Date,
  timeZone = TUTORING_PAYMENT_TIME_ZONE
): string {
  return new Intl.DateTimeFormat("en-US", {
    timeZone,
    weekday: "short",
  }).format(date);
}

export function nextTutorPayoutMondayDateKey(
  input: Date,
  timeZone = TUTORING_PAYMENT_TIME_ZONE
): string {
  const cursor = new Date(input.getTime());
  for (let offset = 0; offset < 8; offset += 1) {
    if (weekdayShort(cursor, timeZone) === "Mon") {
      return dateKeyInTimeZone(cursor, timeZone);
    }
    cursor.setUTCDate(cursor.getUTCDate() + 1);
  }
  return dateKeyInTimeZone(input, timeZone);
}

export function buildTutorNextPayoutDisplayLabel(
  weekKey: string | null
): string | null {
  if (!weekKey) {
    return null;
  }
  return `Upcoming Monday • ${weekKey}`;
}

function buildUserDashboardSignature(data: Record<string, unknown>): string {
  return JSON.stringify({
    tutorApplicationStatus: toTrimmedString(data.tutorApplicationStatus),
    tutoringEligibilityStatus: toTrimmedString(data.tutoringEligibilityStatus),
    payoutOnboardingStatus: toTrimmedString(data.payoutOnboardingStatus),
    adminApproval: data.adminApproval === true,
    isDisabled: data.isDisabled === true,
    tutorPayoutsBlocked: data.tutorPayoutsBlocked === true,
    payoutsBlocked: data.payoutsBlocked === true,
    blockedFromPayouts: data.blockedFromPayouts === true,
    accountType: toTrimmedString(data.accountType),
    accessTier: toTrimmedString(data.accessTier),
    payoutMode: toTrimmedString(data.payoutMode),
    fullName: toTrimmedString(data.fullName),
    displayName: toTrimmedString(data.displayName),
  });
}

function payoutProfileViewFromDoc(
  doc: FirebaseFirestore.QueryDocumentSnapshot | FirebaseFirestore.DocumentSnapshot
): TutorPayoutDashboardProfileView {
  const data = doc.data() ?? {};
  return {
    payoutProfileId: doc.id,
    tutorId: toTrimmedString(data.tutorId),
    payoutEnabled: data.payoutEnabled === true,
    verificationStatus: deriveTutorPayoutVerificationStatus(data),
    status: toTrimmedString(data.status).toUpperCase(),
    bankName: toTrimmedString(data.bankName) || null,
    accountNumberMasked:
      toTrimmedString(data.accountNumberMasked || data.maskedAccountNumber) || null,
    payoutBlockedReason: toTrimmedString(data.payoutBlockedReason) || null,
    isDefault: data.isDefault === true,
    recipientCode:
      toTrimmedString(data.recipientCode || data.providerBeneficiaryId) || null,
  };
}

function choosePreferredProfile(
  tutorId: string,
  profiles: TutorPayoutDashboardProfileView[]
): TutorPayoutDashboardProfileView | null {
  if (profiles.length <= 0) {
    return null;
  }
  const verifiedDefault = profiles.find((profile) =>
    profile.isDefault &&
    isVerifiedTutorPayoutProfile(tutorId, {
      ...profile,
      tutorId,
    })
  );
  if (verifiedDefault) {
    return verifiedDefault;
  }
  const verified = profiles.find((profile) =>
    isVerifiedTutorPayoutProfile(tutorId, {
      ...profile,
      tutorId,
    })
  );
  return verified ?? profiles.find((profile) => profile.isDefault) ?? profiles[0];
}

export function deriveTutorPayoutBlockedReason(params: {
  userData: Record<string, unknown>;
  payoutProfile: TutorPayoutDashboardProfileView | null;
}): TutorPayoutBlockedReason {
  const approval = deriveTutorApprovalSnapshot({
    userData: params.userData,
  });

  if (!approval.fullAccountTutor) {
    return {
      code: "full_account_required",
      message: "Tutor payouts require a full authenticated Seshly account.",
    };
  }
  if (params.userData.isDisabled === true ||
      approval.tutorApplicationStatus === "suspended" ||
      approval.tutoringEligibilityStatus === "blocked") {
    return {
      code: "tutor_blocked",
      message: "Tutor payouts are blocked while this tutor account is suspended or blocked.",
    };
  }
  if (!approval.adminApproval || approval.tutorApplicationStatus !== "approved") {
    return {
      code: "tutor_not_approved",
      message: "Tutor payouts stay blocked until tutor approval is complete.",
    };
  }
  if (approval.payoutOnboardingStatus === "blocked") {
    return {
      code: "payout_onboarding_blocked",
      message:
        params.payoutProfile?.payoutBlockedReason ||
        "Tutor payout onboarding is currently blocked.",
    };
  }
  if (!params.payoutProfile) {
    return {
      code: "payout_profile_missing",
      message: "Add a payout profile before tutor payouts can be enabled.",
    };
  }
  if (params.payoutProfile.status === "DISABLED" ||
      params.payoutProfile.verificationStatus === "blocked") {
    return {
      code: "payout_profile_blocked",
      message:
        params.payoutProfile.payoutBlockedReason ||
        "The selected payout profile is blocked.",
    };
  }
  if (!params.payoutProfile.payoutEnabled) {
    return {
      code: "payout_not_enabled",
      message: "Complete payout verification before tutor payouts can be enabled.",
    };
  }
  if (approval.payoutOnboardingStatus !== "verified" ||
      !isVerifiedTutorPayoutProfile(params.payoutProfile.tutorId, {
        ...params.payoutProfile,
        tutorId: params.payoutProfile.tutorId,
      })) {
    return {
      code: "payout_verification_pending",
      message: "Payout onboarding is still pending verification.",
    };
  }
  return {code: null, message: null};
}

function mapPayoutHistoryPreviewItem(
  doc: FirebaseFirestore.QueryDocumentSnapshot | FirebaseFirestore.DocumentSnapshot
): TutorPayoutHistoryPreviewItem {
  const data = doc.data() ?? {};
  return {
    payoutId: doc.id,
    payoutWeekKey: toTrimmedString(data.payoutWeekKey) || null,
    status: toTrimmedString(data.status).toUpperCase(),
    providerStatus: toTrimmedString(data.providerStatus).toUpperCase(),
    amountZar: Math.max(0, asMoney(data.amountZar, 0)),
    currency: toTrimmedString(data.currency) || "ZAR",
    payoutKind: toTrimmedString(data.payoutKind) || null,
    failureReason: toTrimmedString(data.failureReason) || null,
    requestedAt: timestampToIso(data.requestedAt),
    paidAt: timestampToIso(data.paidAt),
    failedAt: timestampToIso(data.failedAt),
  };
}

function mapFailedNoticeItem(
  item: TutorPayoutHistoryPreviewItem
): TutorFailedPayoutNoticeItem {
  return {
    payoutId: item.payoutId,
    payoutWeekKey: item.payoutWeekKey,
    amountZar: item.amountZar,
    currency: item.currency,
    failureReason: item.failureReason,
    failedAt: item.failedAt,
  };
}

async function fetchUpcomingTutorPayables(params: {
  tutorId: string;
  weekKey: string;
}): Promise<FirebaseFirestore.QueryDocumentSnapshot[]> {
  const snap = await db.collection("tutor_payables")
    .where("tutorId", "==", params.tutorId)
    .where("scheduledPayoutDateKey", "==", params.weekKey)
    .get();
  return snap.docs;
}

async function fetchTutorHistoryDocs(params: {
  tutorId: string;
  limit: number;
}): Promise<FirebaseFirestore.QueryDocumentSnapshot[]> {
  const snap = await db.collection("tutor_payouts")
    .where("tutorId", "==", params.tutorId)
    .orderBy("requestedAt", "desc")
    .limit(params.limit)
    .get();
  return snap.docs;
}

async function fetchUpcomingWeekPayoutDocs(params: {
  tutorId: string;
  weekKey: string;
}): Promise<FirebaseFirestore.QueryDocumentSnapshot[]> {
  const snap = await db.collection("tutor_payouts")
    .where("tutorId", "==", params.tutorId)
    .where("payoutWeekKey", "==", params.weekKey)
    .orderBy("requestedAt", "desc")
    .limit(20)
    .get();
  return snap.docs;
}

async function fetchFailedTutorPayoutDocs(params: {
  tutorId: string;
  limit: number;
}): Promise<FirebaseFirestore.QueryDocumentSnapshot[]> {
  const snap = await db.collection("tutor_payouts")
    .where("tutorId", "==", params.tutorId)
    .where("status", "==", "FAILED")
    .orderBy("failedAt", "desc")
    .limit(params.limit)
    .get();
  return snap.docs;
}

async function computeTutorPayoutDashboard(params: {
  tutorId: string;
}): Promise<Record<string, unknown>> {
  const tutorId = toTrimmedString(params.tutorId);
  if (!tutorId) {
    throw new HttpsError("invalid-argument", "tutorId is required.");
  }

  const weekKey = nextTutorPayoutMondayDateKey(new Date());
  const [userSnap, balanceSnap, payoutProfilesSnap, payablesSnap, historyDocs, failedDocs, weekPayoutDocs] =
    await Promise.all([
      db.collection("users").doc(tutorId).get(),
      db.collection("tutor_balances").doc(tutorId).get(),
      db.collection("tutor_payout_accounts").where("tutorId", "==", tutorId).get(),
      fetchUpcomingTutorPayables({tutorId, weekKey}),
      fetchTutorHistoryDocs({tutorId, limit: HISTORY_PREVIEW_LIMIT}),
      fetchFailedTutorPayoutDocs({tutorId, limit: FAILED_NOTICE_LIMIT}),
      fetchUpcomingWeekPayoutDocs({tutorId, weekKey}),
    ]);

  if (!userSnap.exists) {
    throw new HttpsError("not-found", "Tutor user not found.");
  }

  const userData = userSnap.data() ?? {};
  const balanceData = balanceSnap.data() ?? {};
  const approval = deriveTutorApprovalSnapshot({userData});
  const payoutProfiles = payoutProfilesSnap.docs.map((doc) => payoutProfileViewFromDoc(doc));
  const preferredProfile = choosePreferredProfile(tutorId, payoutProfiles);
  const blockedReason = deriveTutorPayoutBlockedReason({
    userData,
    payoutProfile: preferredProfile,
  });

  const upcomingAvailableAmountZar = toMoney(
    payablesSnap.reduce((sum, doc) => {
      const data = doc.data() ?? {};
      const payableStatus = toTrimmedString(data.payableStatus).toLowerCase();
      const payoutEligibilityStatus =
        toTrimmedString(data.payoutEligibilityStatus).toUpperCase();
      const disputeStatus = toTrimmedString(data.disputeStatus).toLowerCase();
      const blockedAmountZar = Math.max(
        0,
        asMoney(data.blockedAmountZar ?? data.disputeHeldAmountZar, 0)
      );
      if (payableStatus !== "available" ||
          payoutEligibilityStatus !== "ELIGIBLE" ||
          disputeStatus === "open" ||
          blockedAmountZar > 0) {
        return sum;
      }
      return sum + Math.max(0, asMoney(data.availableAmountZar, 0));
    }, 0)
  );

  const pendingWeeklyAmountZar = toMoney(
    weekPayoutDocs.reduce((sum, doc) => {
      const status = toTrimmedString(doc.data()?.status).toUpperCase();
      if (!OPEN_PAYOUT_STATUSES.has(status)) {
        return sum;
      }
      return sum + Math.max(0, asMoney(doc.data()?.amountZar, 0));
    }, 0)
  );

  const payoutEnabled =
    blockedReason.code == null &&
    approval.payoutReady &&
    !!preferredProfile &&
    isVerifiedTutorPayoutProfile(tutorId, {
      ...preferredProfile,
      tutorId,
    });
  const nextPayoutDateKey = payoutEnabled ? weekKey : null;
  const payoutHistoryPreview = historyDocs.map((doc) =>
    mapPayoutHistoryPreviewItem(doc)
  );
  const failedPayoutNotices = failedDocs
    .map((doc) => mapFailedNoticeItem(mapPayoutHistoryPreviewItem(doc)))
    .sort((left, right) =>
      timestampToMillis(right.failedAt ? new Date(right.failedAt) : null) -
      timestampToMillis(left.failedAt ? new Date(left.failedAt) : null)
    );

  return {
    tutorId,
    currency: toTrimmedString(balanceData.currency) || "ZAR",
    onboardingStatus: approval.payoutOnboardingStatus,
    payoutEnabled,
    payoutMode: toTrimmedString(balanceData.payoutMode) || "MANUAL",
    payoutProfileId: preferredProfile?.payoutProfileId ?? null,
    payoutProfileVerificationStatus:
      preferredProfile?.verificationStatus ?? approval.payoutOnboardingStatus,
    payoutProfileBankName: preferredProfile?.bankName ?? null,
    payoutProfileAccountNumberMasked:
      preferredProfile?.accountNumberMasked ?? null,
    availableNextPayoutAmountZar: payoutEnabled ? upcomingAvailableAmountZar : 0,
    pendingWeeklyAmountZar,
    blockedPayoutReasonCode: blockedReason.code,
    blockedPayoutReasonMessage: blockedReason.message,
    nextPayoutDateKey,
    nextPayoutDisplayLabel: buildTutorNextPayoutDisplayLabel(nextPayoutDateKey),
    nextPayoutLocalTime: nextPayoutDateKey ? TUTORING_PAYOUT_LOCAL_TIME : null,
    failedPayoutNoticeCount: failedPayoutNotices.length,
    hasFailedPayoutNotices: failedPayoutNotices.length > 0,
    availableBalanceZar: Math.max(0, asMoney(balanceData.availableBalanceZar, 0)),
    reservedForPayoutZar: Math.max(0, asMoney(balanceData.reservedForPayoutZar, 0)),
    heldForDisputesZar: Math.max(0, asMoney(balanceData.heldForDisputesZar, 0)),
    lifetimePaidOutZar: Math.max(0, asMoney(balanceData.paidOutZar, 0)),
    lastPayoutAt: balanceData.lastPayoutAt ?? null,
    payoutHistoryPreview,
    failedPayoutNotices,
  };
}

async function refreshTutorPayoutDashboardDoc(params: {
  tutorId: string;
  actor?: string | null;
}): Promise<Record<string, unknown>> {
  const tutorId = toTrimmedString(params.tutorId);
  const dashboardRef = db.collection("tutor_payout_dashboards").doc(tutorId);
  const [existingSnap, dashboard] = await Promise.all([
    dashboardRef.get(),
    computeTutorPayoutDashboard({tutorId}),
  ]);
  const existingData = existingSnap.data() ?? {};
  const doc = buildTutorPayoutDashboardDoc(tutorId, dashboard);
  await dashboardRef.set({
    ...doc,
    createdAt: existingData.createdAt ?? nowServerTs(),
    updatedAt: nowServerTs(),
  }, {merge: true});

  logger.info("tutor_payout_dashboard_refreshed", {
    tutorId,
    actor: params.actor ?? null,
    onboardingStatus: dashboard.onboardingStatus,
    payoutEnabled: dashboard.payoutEnabled === true,
    availableNextPayoutAmountZar: dashboard.availableNextPayoutAmountZar,
    pendingWeeklyAmountZar: dashboard.pendingWeeklyAmountZar,
  });

  return {
    ...doc,
    lastPayoutAt: timestampToIso(dashboard.lastPayoutAt),
    createdAt:
      timestampToIso(existingData.createdAt) ??
      new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  };
}

export const getTutorPayoutDashboard = onCall(
  {region: REGION, timeoutSeconds: 540},
  async (request): Promise<Record<string, unknown>> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }
    return refreshTutorPayoutDashboardDoc({
      tutorId: request.auth.uid,
      actor: request.auth.uid,
    });
  }
);

export const listTutorPayoutHistory = onCall(
  {region: REGION, timeoutSeconds: 540},
  async (request): Promise<Record<string, unknown>> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }
    const limit = Math.max(
      1,
      Math.min(50, Math.round(Number(request.data?.limit ?? 20)))
    );
    const docs = await fetchTutorHistoryDocs({
      tutorId: request.auth.uid,
      limit,
    });
    return {
      tutorId: request.auth.uid,
      itemCount: docs.length,
      items: docs.map((doc) => mapPayoutHistoryPreviewItem(doc)),
    };
  }
);

function hasTutorPayoutSignals(userData: Record<string, unknown>): boolean {
  return toTrimmedString(userData.tutorApplicationStatus).length > 0 ||
    toTrimmedString(userData.tutoringEligibilityStatus).length > 0 ||
    toTrimmedString(userData.payoutOnboardingStatus).length > 0 ||
    toTrimmedString(userData.tutorStatus).length > 0 ||
    userData.adminApproval === true ||
    userData.tutorPayoutsBlocked === true ||
    userData.payoutsBlocked === true ||
    userData.blockedFromPayouts === true ||
    !!userData.tutorProfile;
}

async function refreshTutorPayoutDashboardSilently(params: {
  tutorId: string;
  actor: string;
}): Promise<void> {
  const tutorId = toTrimmedString(params.tutorId);
  if (!tutorId) {
    return;
  }
  try {
    await refreshTutorPayoutDashboardDoc({
      tutorId,
      actor: params.actor,
    });
  } catch (error) {
    logger.error("tutor_payout_dashboard_refresh_failed", {
      tutorId,
      actor: params.actor,
      error: error instanceof Error ? error.message : String(error),
    });
  }
}

export const ontutorpayoutdashboarduserwritten = onDocumentWritten(
  {
    document: "users/{userId}",
    region: REGION,
  },
  async (event) => {
    const userId = toTrimmedString(event.params.userId);
    const beforeData = event.data?.before.data() ?? {};
    const afterSnap = event.data?.after;
    if (!userId) {
      return;
    }
    if (!afterSnap?.exists) {
      await db.collection("tutor_payout_dashboards").doc(userId).delete().catch(() => undefined);
      return;
    }

    const afterData = afterSnap.data() ?? {};
    if (buildUserDashboardSignature(beforeData) === buildUserDashboardSignature(afterData)) {
      return;
    }
    if (!hasTutorPayoutSignals(afterData)) {
      return;
    }

    await refreshTutorPayoutDashboardSilently({
      tutorId: userId,
      actor: "system:user_trigger",
    });
  }
);

export const ontutorpayoutdashboardbalancewritten = onDocumentWritten(
  {
    document: "tutor_balances/{tutorId}",
    region: REGION,
  },
  async (event) => {
    await refreshTutorPayoutDashboardSilently({
      tutorId: toTrimmedString(event.params.tutorId),
      actor: "system:balance_trigger",
    });
  }
);

export const ontutorpayoutdashboardprofilewritten = onDocumentWritten(
  {
    document: "tutor_payout_accounts/{accountId}",
    region: REGION,
  },
  async (event) => {
    const payoutData =
      event.data?.after.data() ??
      event.data?.before.data() ??
      {};
    await refreshTutorPayoutDashboardSilently({
      tutorId: toTrimmedString(payoutData.tutorId),
      actor: "system:payout_profile_trigger",
    });
  }
);

export const ontutorpayoutdashboardpayoutwritten = onDocumentWritten(
  {
    document: "tutor_payouts/{payoutId}",
    region: REGION,
  },
  async (event) => {
    const payoutData =
      event.data?.after.data() ??
      event.data?.before.data() ??
      {};
    await refreshTutorPayoutDashboardSilently({
      tutorId: toTrimmedString(payoutData.tutorId),
      actor: "system:payout_trigger",
    });
  }
);

export const ontutorpayoutdashboardpayablewritten = onDocumentWritten(
  {
    document: "tutor_payables/{payableId}",
    region: REGION,
  },
  async (event) => {
    const payableData =
      event.data?.after.data() ??
      event.data?.before.data() ??
      {};
    await refreshTutorPayoutDashboardSilently({
      tutorId: toTrimmedString(payableData.tutorId),
      actor: "system:payable_trigger",
    });
  }
);
