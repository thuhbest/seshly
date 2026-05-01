import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {HttpsError, onCall} from "./callable";
import {
  assertPlatformAdmin,
  deriveTutorApprovalSnapshot,
  toTrimmedString,
} from "./tutorApprovalState";
import {
  asMoney,
  timestampToMillis,
  toMoney,
} from "./tutorPayoutModels";
import {
  deriveTutorPayoutVerificationStatus,
  isVerifiedTutorPayoutProfile,
} from "./tutorPayoutProfileState";
import {
  TUTORING_PAYMENT_TIME_ZONE,
  TUTORING_PAYOUT_LOCAL_TIME,
} from "./tutoringFirestoreSchema";

const db = admin.firestore();
const REGION = "europe-west1";
const ADMIN_PAYOUT_DASHBOARD_COLLECTION = "admin_tutor_payout_dashboard";
const MAX_QUERY_LIMIT = 200;
const DEFAULT_QUERY_LIMIT = 50;

type ExportDataset =
  | "payout_records"
  | "weekly_totals"
  | "due_this_monday"
  | "blocked_profiles"
  | "failed_attempts"
  | "disputed_payables";

interface TutorPayableDashboardView {
  payableId: string;
  settlementId: string;
  tutorId: string;
  studentId: string;
  payableStatus: string;
  payoutEligibilityStatus: string;
  payoutState: string;
  disputeStatus: string;
  availableAmountZar: number;
  blockedAmountZar: number;
  grossTutorEarningZar: number;
  scheduledPayoutDateKey: string | null;
  lastPayoutBatchId: string | null;
  lastPayoutRecordId: string | null;
  updatedAt: admin.firestore.Timestamp | null;
  settledAt: admin.firestore.Timestamp | null;
}

interface TutorPayoutProfileView {
  accountId: string;
  tutorId: string;
  bankCode: string | null;
  bankName: string | null;
  accountHolderName: string | null;
  accountNumberMasked: string | null;
  payoutEnabled: boolean;
  payoutBlockedReason: string | null;
  verificationStatus: string;
  status: string;
  recipientCode: string | null;
  isDefault: boolean;
  updatedAt: admin.firestore.Timestamp | null;
}

interface TutorPayoutRecordView {
  payoutId: string;
  tutorId: string;
  payoutAccountId: string | null;
  payoutBatchId: string | null;
  payoutWeekKey: string | null;
  status: string;
  providerStatus: string;
  amountZar: number;
  currency: string;
  allocationCount: number;
  payoutKind: string | null;
  failureReason: string | null;
  requestedAt: admin.firestore.Timestamp | null;
  approvedAt: admin.firestore.Timestamp | null;
  processingAt: admin.firestore.Timestamp | null;
  paidAt: admin.firestore.Timestamp | null;
  failedAt: admin.firestore.Timestamp | null;
  updatedAt: admin.firestore.Timestamp | null;
}

interface TutorPayoutBatchView {
  batchId: string;
  batchDateKey: string | null;
  status: string;
  totalTutors: number;
  totalAmountZar: number;
  updatedAt: admin.firestore.Timestamp | null;
}

interface DueTutorDashboardItem {
  tutorId: string;
  tutorName: string;
  payoutProfileId: string;
  payoutEnabled: boolean;
  payoutVerificationStatus: string;
  payoutOnboardingStatus: string;
  dueAmountZar: number;
  duePayableCount: number;
  requiresRetryBatch: boolean;
  payoutBlockedReason: string | null;
  bankName: string | null;
  accountNumberMasked: string | null;
  scheduledPayoutDateKey: string;
}

interface BlockedTutorPayoutProfileItem {
  payoutProfileId: string;
  tutorId: string;
  tutorName: string;
  verificationStatus: string;
  payoutEnabled: boolean;
  payoutBlockedReason: string | null;
  bankName: string | null;
  accountNumberMasked: string | null;
  availableBalanceZar: number;
  updatedAt: string | null;
}

interface FailedTutorPayoutAttemptItem {
  payoutId: string;
  tutorId: string;
  tutorName: string;
  payoutWeekKey: string | null;
  amountZar: number;
  currency: string;
  providerStatus: string;
  failureReason: string | null;
  failedAt: string | null;
  payoutBatchId: string | null;
}

interface DisputedTutorPayableItem {
  payableId: string;
  tutorId: string;
  tutorName: string;
  settlementId: string;
  disputeId: string | null;
  heldAmountZar: number;
  availableAmountZar: number;
  payoutWeekKey: string | null;
  updatedAt: string | null;
}

interface TutorPayoutHistoryItem {
  payoutId: string;
  payoutWeekKey: string | null;
  payoutBatchId: string | null;
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

interface WeeklyPayoutTotalsItem {
  weekKey: string;
  dueTutorCount: number;
  duePayableCount: number;
  dueAmountZar: number;
  retryTutorCount: number;
  retryAmountZar: number;
  disputedPayableCount: number;
  disputedAmountZar: number;
  payoutRecordCount: number;
  payoutBatchCount: number;
  payoutCountsByStatus: Record<string, number>;
  payoutAmountsByStatus: Record<string, number>;
  latestBatchId: string | null;
  latestBatchStatus: string | null;
  updatedAt: string | null;
}

function nowServerTs() {
  return admin.firestore.FieldValue.serverTimestamp();
}

function clampLimit(value: unknown, fallback = DEFAULT_QUERY_LIMIT): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return fallback;
  }
  return Math.max(1, Math.min(MAX_QUERY_LIMIT, Math.floor(parsed)));
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

function asTimestamp(value: unknown): admin.firestore.Timestamp | null {
  return value instanceof admin.firestore.Timestamp ? value : null;
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

export function nextOrSameMondayDateKey(
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

function tutorNameFromUserData(userData: Record<string, unknown>): string {
  return (
    toTrimmedString(userData.fullName) ||
    toTrimmedString(userData.displayName) ||
    toTrimmedString(userData.firstName) ||
    "Tutor"
  );
}

function chunkArray<T>(items: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let index = 0; index < items.length; index += size) {
    chunks.push(items.slice(index, index + size));
  }
  return chunks;
}

function sortByTimestampDesc(
  left: admin.firestore.Timestamp | null,
  right: admin.firestore.Timestamp | null
): number {
  return timestampToMillis(right) - timestampToMillis(left);
}

function toRecordRows<T extends object>(
  items: T[]
): Array<Record<string, unknown>> {
  return items.map((item) => ({...item}) as Record<string, unknown>);
}

function payableViewFromDoc(
  doc: FirebaseFirestore.QueryDocumentSnapshot | FirebaseFirestore.DocumentSnapshot
): TutorPayableDashboardView {
  const data = doc.data() ?? {};
  return {
    payableId: doc.id,
    settlementId: toTrimmedString(data.settlementId) || doc.id,
    tutorId: toTrimmedString(data.tutorId),
    studentId: toTrimmedString(data.studentId),
    payableStatus: toTrimmedString(data.payableStatus).toLowerCase(),
    payoutEligibilityStatus: toTrimmedString(data.payoutEligibilityStatus).toUpperCase(),
    payoutState: toTrimmedString(data.payoutState).toUpperCase(),
    disputeStatus: toTrimmedString(data.disputeStatus).toLowerCase(),
    availableAmountZar: Math.max(0, asMoney(data.availableAmountZar, 0)),
    blockedAmountZar: Math.max(
      0,
      asMoney(data.blockedAmountZar ?? data.disputeHeldAmountZar, 0)
    ),
    grossTutorEarningZar: Math.max(0, asMoney(data.grossTutorEarningZar, 0)),
    scheduledPayoutDateKey:
      toTrimmedString(data.scheduledPayoutDateKey) || null,
    lastPayoutBatchId:
      toTrimmedString(data.lastPayoutBatchId) || null,
    lastPayoutRecordId:
      toTrimmedString(data.lastPayoutRecordId) || null,
    updatedAt: asTimestamp(data.updatedAt),
    settledAt: asTimestamp(data.settledAt),
  };
}

function payoutProfileViewFromDoc(
  doc: FirebaseFirestore.QueryDocumentSnapshot | FirebaseFirestore.DocumentSnapshot
): TutorPayoutProfileView {
  const data = doc.data() ?? {};
  return {
    accountId: doc.id,
    tutorId: toTrimmedString(data.tutorId),
    bankCode: toTrimmedString(data.bankCode || data.branchCode) || null,
    bankName: toTrimmedString(data.bankName) || null,
    accountHolderName: toTrimmedString(data.accountHolderName) || null,
    accountNumberMasked:
      toTrimmedString(data.accountNumberMasked || data.maskedAccountNumber) || null,
    payoutEnabled: data.payoutEnabled === true,
    payoutBlockedReason: toTrimmedString(data.payoutBlockedReason) || null,
    verificationStatus: deriveTutorPayoutVerificationStatus(data),
    status: toTrimmedString(data.status).toUpperCase(),
    recipientCode:
      toTrimmedString(data.recipientCode || data.providerBeneficiaryId) || null,
    isDefault: data.isDefault === true,
    updatedAt: asTimestamp(data.updatedAt),
  };
}

function payoutRecordViewFromDoc(
  doc: FirebaseFirestore.QueryDocumentSnapshot | FirebaseFirestore.DocumentSnapshot
): TutorPayoutRecordView {
  const data = doc.data() ?? {};
  return {
    payoutId: doc.id,
    tutorId: toTrimmedString(data.tutorId),
    payoutAccountId: toTrimmedString(data.payoutAccountId) || null,
    payoutBatchId: toTrimmedString(data.payoutBatchId) || null,
    payoutWeekKey: toTrimmedString(data.payoutWeekKey) || null,
    status: toTrimmedString(data.status).toUpperCase(),
    providerStatus: toTrimmedString(data.providerStatus).toUpperCase(),
    amountZar: Math.max(0, asMoney(data.amountZar, 0)),
    currency: toTrimmedString(data.currency) || "ZAR",
    allocationCount: Math.max(0, Math.round(Number(data.allocationCount ?? 0))),
    payoutKind: toTrimmedString(data.payoutKind) || null,
    failureReason: toTrimmedString(data.failureReason) || null,
    requestedAt: asTimestamp(data.requestedAt),
    approvedAt: asTimestamp(data.approvedAt),
    processingAt: asTimestamp(data.processingAt),
    paidAt: asTimestamp(data.paidAt),
    failedAt: asTimestamp(data.failedAt),
    updatedAt: asTimestamp(data.updatedAt),
  };
}

function payoutBatchViewFromDoc(
  doc: FirebaseFirestore.QueryDocumentSnapshot | FirebaseFirestore.DocumentSnapshot
): TutorPayoutBatchView {
  const data = doc.data() ?? {};
  return {
    batchId: doc.id,
    batchDateKey:
      toTrimmedString(data.batchDateKey || data.payoutWeekKey) || null,
    status: toTrimmedString(data.status).toUpperCase(),
    totalTutors: Math.max(0, Math.round(Number(data.totalTutors ?? 0))),
    totalAmountZar: Math.max(0, asMoney(data.totalAmountZar, 0)),
    updatedAt: asTimestamp(data.updatedAt),
  };
}

function choosePreferredPayoutProfile(
  tutorId: string,
  profiles: TutorPayoutProfileView[]
): TutorPayoutProfileView | null {
  if (profiles.length === 0) {
    return null;
  }
  const verifiedDefault = profiles.find(
    (profile) =>
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

async function fetchUsersMap(
  userIds: string[]
): Promise<Map<string, Record<string, unknown>>> {
  const normalizedIds = [...new Set(userIds.filter((item) => item.trim().length > 0))];
  const map = new Map<string, Record<string, unknown>>();
  if (normalizedIds.length === 0) {
    return map;
  }
  const refs = normalizedIds.map((userId) => db.collection("users").doc(userId));
  const snaps = await db.getAll(...refs);
  for (const snap of snaps) {
    if (snap.exists) {
      map.set(snap.id, snap.data() ?? {});
    }
  }
  return map;
}

async function fetchTutorBalancesMap(
  tutorIds: string[]
): Promise<Map<string, Record<string, unknown>>> {
  const normalizedIds = [...new Set(tutorIds.filter((item) => item.trim().length > 0))];
  const map = new Map<string, Record<string, unknown>>();
  if (normalizedIds.length === 0) {
    return map;
  }
  const refs = normalizedIds.map((tutorId) =>
    db.collection("tutor_balances").doc(tutorId)
  );
  const snaps = await db.getAll(...refs);
  for (const snap of snaps) {
    if (snap.exists) {
      map.set(snap.id, snap.data() ?? {});
    }
  }
  return map;
}

async function fetchPayoutProfilesMap(
  tutorIds: string[]
): Promise<Map<string, TutorPayoutProfileView[]>> {
  const result = new Map<string, TutorPayoutProfileView[]>();
  const uniqueTutorIds = [...new Set(tutorIds.filter((item) => item.trim().length > 0))];
  for (const chunk of chunkArray(uniqueTutorIds, 10)) {
    const snap = await db.collection("tutor_payout_accounts")
      .where("tutorId", "in", chunk)
      .get();
    for (const doc of snap.docs) {
      const profile = payoutProfileViewFromDoc(doc);
      const items = result.get(profile.tutorId) ?? [];
      items.push(profile);
      result.set(profile.tutorId, items);
    }
  }
  return result;
}

async function fetchCurrentDuePayablesByTutor(params: {
  weekKey: string;
}): Promise<Map<string, TutorPayableDashboardView[]>> {
  const snap = await db.collection("tutor_payables")
    .where("scheduledPayoutDateKey", "==", params.weekKey)
    .where("payableStatus", "==", "available")
    .orderBy("tutorId")
    .get();
  const map = new Map<string, TutorPayableDashboardView[]>();
  for (const doc of snap.docs) {
    const payable = payableViewFromDoc(doc);
    if (!payable.tutorId ||
        payable.payoutEligibilityStatus !== "ELIGIBLE" ||
        payable.disputeStatus === "open" ||
        payable.availableAmountZar <= 0) {
      continue;
    }
    const items = map.get(payable.tutorId) ?? [];
    items.push(payable);
    map.set(payable.tutorId, items);
  }
  return map;
}

async function buildDueTutorsForWeek(
  weekKey: string
): Promise<DueTutorDashboardItem[]> {
  const payablesByTutor = await fetchCurrentDuePayablesByTutor({weekKey});
  const tutorIds = [...payablesByTutor.keys()];
  const [usersMap, payoutProfilesMap] = await Promise.all([
    fetchUsersMap(tutorIds),
    fetchPayoutProfilesMap(tutorIds),
  ]);

  const items: DueTutorDashboardItem[] = [];
  for (const tutorId of tutorIds) {
    const userData = usersMap.get(tutorId) ?? {};
    const approval = deriveTutorApprovalSnapshot({userData});
    const payoutProfile = choosePreferredPayoutProfile(
      tutorId,
      payoutProfilesMap.get(tutorId) ?? []
    );
    if (!payoutProfile) {
      continue;
    }
    if (!approval.payoutReady) {
      continue;
    }
    if (!isVerifiedTutorPayoutProfile(tutorId, {
      ...payoutProfile,
      tutorId,
    })) {
      continue;
    }

    const tutorPayables = payablesByTutor.get(tutorId) ?? [];
    const dueAmountZar = toMoney(
      tutorPayables.reduce((sum, payable) => sum + payable.availableAmountZar, 0)
    );
    if (dueAmountZar <= 0) {
      continue;
    }

    const requiresRetryBatch = tutorPayables.some(
      (payable) => !!payable.lastPayoutBatchId || !!payable.lastPayoutRecordId
    );
    items.push({
      tutorId,
      tutorName: tutorNameFromUserData(userData),
      payoutProfileId: payoutProfile.accountId,
      payoutEnabled: payoutProfile.payoutEnabled,
      payoutVerificationStatus: payoutProfile.verificationStatus,
      payoutOnboardingStatus: approval.payoutOnboardingStatus,
      dueAmountZar,
      duePayableCount: tutorPayables.length,
      requiresRetryBatch,
      payoutBlockedReason: payoutProfile.payoutBlockedReason,
      bankName: payoutProfile.bankName,
      accountNumberMasked: payoutProfile.accountNumberMasked,
      scheduledPayoutDateKey: weekKey,
    });
  }

  items.sort((left, right) => {
    if (right.dueAmountZar !== left.dueAmountZar) {
      return right.dueAmountZar - left.dueAmountZar;
    }
    return left.tutorName.localeCompare(right.tutorName);
  });
  return items;
}

function zeroedStatusMap(): Record<string, number> {
  return {
    PENDING: 0,
    REQUESTED: 0,
    APPROVED: 0,
    PROCESSING: 0,
    PAID: 0,
    FAILED: 0,
    BLOCKED: 0,
    REJECTED: 0,
    CANCELLED: 0,
  };
}

async function buildWeeklyTotalsItem(weekKey: string): Promise<WeeklyPayoutTotalsItem> {
  const [dueItems, payablesSnap, payoutsSnap, batchesSnap] = await Promise.all([
    buildDueTutorsForWeek(weekKey),
    db.collection("tutor_payables")
      .where("scheduledPayoutDateKey", "==", weekKey)
      .get(),
    db.collection("tutor_payouts")
      .where("payoutWeekKey", "==", weekKey)
      .get(),
    db.collection("tutor_payout_batches")
      .where("batchDateKey", "==", weekKey)
      .get(),
  ]);

  const payoutCountsByStatus = zeroedStatusMap();
  const payoutAmountsByStatus = zeroedStatusMap();
  for (const doc of payoutsSnap.docs) {
    const payout = payoutRecordViewFromDoc(doc);
    payoutCountsByStatus[payout.status] =
      (payoutCountsByStatus[payout.status] ?? 0) + 1;
    payoutAmountsByStatus[payout.status] = toMoney(
      (payoutAmountsByStatus[payout.status] ?? 0) + payout.amountZar
    );
  }

  let disputedPayableCount = 0;
  let disputedAmountZar = 0;
  for (const doc of payablesSnap.docs) {
    const payable = payableViewFromDoc(doc);
    if (payable.disputeStatus === "open" || payable.blockedAmountZar > 0) {
      disputedPayableCount += 1;
      disputedAmountZar = toMoney(
        disputedAmountZar + Math.max(payable.blockedAmountZar, payable.availableAmountZar)
      );
    }
  }

  const latestBatch = batchesSnap.docs
    .map((doc) => payoutBatchViewFromDoc(doc))
    .sort((left, right) => sortByTimestampDesc(left.updatedAt, right.updatedAt))[0] ?? null;
  const dueAmountZar = toMoney(
    dueItems.reduce((sum, item) => sum + item.dueAmountZar, 0)
  );
  const retryItems = dueItems.filter((item) => item.requiresRetryBatch);
  const updatedAt = latestBatch?.updatedAt ?? admin.firestore.Timestamp.now();

  const item: WeeklyPayoutTotalsItem = {
    weekKey,
    dueTutorCount: dueItems.length,
    duePayableCount: dueItems.reduce((sum, dueItem) => sum + dueItem.duePayableCount, 0),
    dueAmountZar,
    retryTutorCount: retryItems.length,
    retryAmountZar: toMoney(
      retryItems.reduce((sum, dueItem) => sum + dueItem.dueAmountZar, 0)
    ),
    disputedPayableCount,
    disputedAmountZar,
    payoutRecordCount: payoutsSnap.size,
    payoutBatchCount: batchesSnap.size,
    payoutCountsByStatus,
    payoutAmountsByStatus,
    latestBatchId: latestBatch?.batchId ?? null,
    latestBatchStatus: latestBatch?.status ?? null,
    updatedAt: timestampToIso(updatedAt),
  };

  await db.collection(ADMIN_PAYOUT_DASHBOARD_COLLECTION)
    .doc(`week_${weekKey}`)
    .set({
      aggregateType: "weekly_totals",
      scheduledPayoutLocalTime: TUTORING_PAYOUT_LOCAL_TIME,
      ...item,
      updatedAt: nowServerTs(),
      generatedAt: nowServerTs(),
    }, {merge: true});

  return item;
}

async function listRecentWeekKeys(limit: number): Promise<string[]> {
  const weekKeys = new Set<string>([
    nextOrSameMondayDateKey(new Date()),
  ]);
  const [batchSnap, payoutSnap] = await Promise.all([
    db.collection("tutor_payout_batches")
      .orderBy("batchDateKey", "desc")
      .limit(limit * 4)
      .get(),
    db.collection("tutor_payouts")
      .orderBy("payoutWeekKey", "desc")
      .limit(limit * 20)
      .get(),
  ]);

  for (const doc of batchSnap.docs) {
    const key = toTrimmedString(doc.data().batchDateKey);
    if (key) {
      weekKeys.add(key);
    }
  }
  for (const doc of payoutSnap.docs) {
    const key = toTrimmedString(doc.data().payoutWeekKey);
    if (key) {
      weekKeys.add(key);
    }
  }

  return [...weekKeys]
    .sort((left, right) => right.localeCompare(left))
    .slice(0, limit);
}

async function refreshDashboardOverview(weekKey: string): Promise<Record<string, unknown>> {
  const [dueItems, blockedProfilesSnap, disputedPayablesSnap, weeklyTotals] =
    await Promise.all([
      buildDueTutorsForWeek(weekKey),
      db.collection("tutor_payout_accounts")
        .where("payoutEnabled", "==", false)
        .get(),
      db.collection("tutor_payables")
        .where("disputeStatus", "==", "open")
        .get(),
      buildWeeklyTotalsItem(weekKey),
    ]);

  const overview = {
    aggregateType: "overview",
    currentWeekKey: weekKey,
    tutorsDueThisMondayCount: dueItems.length,
    tutorsDueThisMondayAmountZar: toMoney(
      dueItems.reduce((sum, item) => sum + item.dueAmountZar, 0)
    ),
    tutorsRequiringRetryCount: dueItems.filter((item) => item.requiresRetryBatch).length,
    blockedPayoutProfileCount: blockedProfilesSnap.size,
    failedPayoutAttemptCount: weeklyTotals.payoutCountsByStatus.FAILED ?? 0,
    disputedPayablesCount: disputedPayablesSnap.size,
    disputedPayablesAmountZar: toMoney(
      disputedPayablesSnap.docs.reduce((sum, doc) => {
        return sum + Math.max(0, asMoney(doc.data().blockedAmountZar, 0));
      }, 0)
    ),
    latestWeeklyBatchId: weeklyTotals.latestBatchId,
    latestWeeklyBatchStatus: weeklyTotals.latestBatchStatus,
    updatedAt: nowServerTs(),
    generatedAt: nowServerTs(),
  };

  await db.collection(ADMIN_PAYOUT_DASHBOARD_COLLECTION)
    .doc("overview")
    .set(overview, {merge: true});

  logger.info("admin_payout_dashboard_overview_refreshed", {
    weekKey,
    dueTutorCount: dueItems.length,
    blockedPayoutProfileCount: blockedProfilesSnap.size,
    disputedPayablesCount: disputedPayablesSnap.size,
  });

  return {
    ...overview,
    updatedAt: new Date().toISOString(),
    generatedAt: new Date().toISOString(),
  };
}

async function buildBlockedPayoutProfiles(
  limit: number
): Promise<BlockedTutorPayoutProfileItem[]> {
  const payoutProfilesSnap = await db.collection("tutor_payout_accounts")
    .where("payoutEnabled", "==", false)
    .orderBy("updatedAt", "desc")
    .limit(limit)
    .get();
  const payoutProfiles = payoutProfilesSnap.docs.map((doc) => payoutProfileViewFromDoc(doc));
  const tutorIds = [...new Set(payoutProfiles.map((profile) => profile.tutorId).filter(Boolean))];
  const [usersMap, balancesMap] = await Promise.all([
    fetchUsersMap(tutorIds),
    fetchTutorBalancesMap(tutorIds),
  ]);

  return payoutProfiles.map((profile) => {
    const userData = usersMap.get(profile.tutorId) ?? {};
    const balanceData = balancesMap.get(profile.tutorId) ?? {};
    return {
      payoutProfileId: profile.accountId,
      tutorId: profile.tutorId,
      tutorName: tutorNameFromUserData(userData),
      verificationStatus: profile.verificationStatus,
      payoutEnabled: profile.payoutEnabled,
      payoutBlockedReason:
        profile.payoutBlockedReason ||
        (profile.verificationStatus === "verified" ? null : "payout_not_enabled"),
      bankName: profile.bankName,
      accountNumberMasked: profile.accountNumberMasked,
      availableBalanceZar: Math.max(
        0,
        asMoney(balanceData.availableBalanceZar, 0)
      ),
      updatedAt: timestampToIso(profile.updatedAt),
    };
  });
}

async function buildFailedPayoutAttempts(params: {
  limit: number;
  weekKey?: string | null;
}): Promise<FailedTutorPayoutAttemptItem[]> {
  const payoutsSnap = await db.collection("tutor_payouts")
    .where("status", "==", "FAILED")
    .orderBy("failedAt", "desc")
    .limit(params.limit * 3)
    .get();
  const payouts = payoutsSnap.docs
    .map((doc) => payoutRecordViewFromDoc(doc))
    .filter((payout) =>
      !params.weekKey || payout.payoutWeekKey === params.weekKey
    )
    .slice(0, params.limit);
  const usersMap = await fetchUsersMap(payouts.map((payout) => payout.tutorId));
  return payouts.map((payout) => ({
    payoutId: payout.payoutId,
    tutorId: payout.tutorId,
    tutorName: tutorNameFromUserData(usersMap.get(payout.tutorId) ?? {}),
    payoutWeekKey: payout.payoutWeekKey,
    amountZar: payout.amountZar,
    currency: payout.currency,
    providerStatus: payout.providerStatus,
    failureReason: payout.failureReason,
    failedAt: timestampToIso(payout.failedAt),
    payoutBatchId: payout.payoutBatchId,
  }));
}

async function buildDisputedPayables(params: {
  limit: number;
  weekKey?: string | null;
}): Promise<DisputedTutorPayableItem[]> {
  let query: FirebaseFirestore.Query = db.collection("tutor_payables")
    .where("disputeStatus", "==", "open")
    .orderBy("updatedAt", "desc");
  if (params.weekKey) {
    query = query.where("scheduledPayoutDateKey", "==", params.weekKey);
  }
  const disputedSnap = await query.limit(params.limit).get();
  const disputedPayables = disputedSnap.docs.map((doc) => payableViewFromDoc(doc));
  const usersMap = await fetchUsersMap(disputedPayables.map((payable) => payable.tutorId));
  return disputedPayables.map((payable) => ({
    payableId: payable.payableId,
    tutorId: payable.tutorId,
    tutorName: tutorNameFromUserData(usersMap.get(payable.tutorId) ?? {}),
    settlementId: payable.settlementId,
    disputeId: payable.payableId,
    heldAmountZar: payable.blockedAmountZar,
    availableAmountZar: payable.availableAmountZar,
    payoutWeekKey: payable.scheduledPayoutDateKey,
    updatedAt: timestampToIso(payable.updatedAt),
  }));
}

async function buildTutorPayoutHistory(params: {
  tutorId: string;
  limit: number;
}): Promise<TutorPayoutHistoryItem[]> {
  const historySnap = await db.collection("tutor_payouts")
    .where("tutorId", "==", params.tutorId)
    .orderBy("requestedAt", "desc")
    .limit(params.limit)
    .get();
  return historySnap.docs.map((doc) => {
    const payout = payoutRecordViewFromDoc(doc);
    return {
      payoutId: payout.payoutId,
      payoutWeekKey: payout.payoutWeekKey,
      payoutBatchId: payout.payoutBatchId,
      status: payout.status,
      providerStatus: payout.providerStatus,
      amountZar: payout.amountZar,
      currency: payout.currency,
      payoutKind: payout.payoutKind,
      failureReason: payout.failureReason,
      requestedAt: timestampToIso(payout.requestedAt),
      paidAt: timestampToIso(payout.paidAt),
      failedAt: timestampToIso(payout.failedAt),
    };
  });
}

export function buildAdminPayoutCsv(
  columns: string[],
  rows: Array<Record<string, unknown>>
): string {
  const escapeCell = (value: unknown): string => {
    const raw =
      value == null ? "" :
      typeof value === "string" ? value :
      typeof value === "number" || typeof value === "boolean" ? String(value) :
      JSON.stringify(value);
    const escaped = raw.replace(/"/g, "\"\"");
    return /[",\n]/.test(escaped) ? `"${escaped}"` : escaped;
  };

  const lines = [
    columns.join(","),
    ...rows.map((row) => columns.map((column) => escapeCell(row[column])).join(",")),
  ];
  return lines.join("\n");
}

async function buildExportRows(params: {
  dataset: ExportDataset;
  weekKey: string;
  tutorId?: string | null;
  limit: number;
}): Promise<{columns: string[]; rows: Array<Record<string, unknown>>}> {
  if (params.dataset === "weekly_totals") {
    const weekKeys = await listRecentWeekKeys(params.limit);
    const totals = await Promise.all(
      weekKeys.map((weekKey) => buildWeeklyTotalsItem(weekKey))
    );
    return {
      columns: [
        "weekKey",
        "dueTutorCount",
        "duePayableCount",
        "dueAmountZar",
        "retryTutorCount",
        "retryAmountZar",
        "disputedPayableCount",
        "disputedAmountZar",
        "payoutRecordCount",
        "payoutBatchCount",
        "latestBatchId",
        "latestBatchStatus",
      ],
      rows: toRecordRows(totals),
    };
  }

  if (params.dataset === "due_this_monday") {
    const dueItems = await buildDueTutorsForWeek(params.weekKey);
    return {
      columns: [
        "scheduledPayoutDateKey",
        "tutorId",
        "tutorName",
        "dueAmountZar",
        "duePayableCount",
        "requiresRetryBatch",
        "payoutProfileId",
        "payoutVerificationStatus",
        "bankName",
        "accountNumberMasked",
      ],
      rows: toRecordRows(dueItems),
    };
  }

  if (params.dataset === "blocked_profiles") {
    const profiles = await buildBlockedPayoutProfiles(params.limit);
    return {
      columns: [
        "payoutProfileId",
        "tutorId",
        "tutorName",
        "verificationStatus",
        "payoutEnabled",
        "payoutBlockedReason",
        "bankName",
        "accountNumberMasked",
        "availableBalanceZar",
        "updatedAt",
      ],
      rows: toRecordRows(profiles),
    };
  }

  if (params.dataset === "failed_attempts") {
    const failedAttempts = await buildFailedPayoutAttempts({
      limit: params.limit,
      weekKey: params.weekKey,
    });
    return {
      columns: [
        "payoutId",
        "tutorId",
        "tutorName",
        "payoutWeekKey",
        "amountZar",
        "currency",
        "providerStatus",
        "failureReason",
        "failedAt",
        "payoutBatchId",
      ],
      rows: toRecordRows(failedAttempts),
    };
  }

  if (params.dataset === "disputed_payables") {
    const disputedPayables = await buildDisputedPayables({
      limit: params.limit,
      weekKey: params.weekKey,
    });
    return {
      columns: [
        "payableId",
        "tutorId",
        "tutorName",
        "settlementId",
        "disputeId",
        "heldAmountZar",
        "availableAmountZar",
        "payoutWeekKey",
        "updatedAt",
      ],
      rows: toRecordRows(disputedPayables),
    };
  }

  let payoutQuery: FirebaseFirestore.Query = db.collection("tutor_payouts");
  if (params.tutorId) {
    payoutQuery = payoutQuery.where("tutorId", "==", params.tutorId);
  } else {
    payoutQuery = payoutQuery.where("payoutWeekKey", "==", params.weekKey);
  }
  const payoutsSnap = await payoutQuery
    .orderBy("requestedAt", "desc")
    .limit(params.limit)
    .get();
  const payouts = payoutsSnap.docs.map((doc) => payoutRecordViewFromDoc(doc));
  const usersMap = await fetchUsersMap(payouts.map((payout) => payout.tutorId));
  const profileIds = payouts
    .map((payout) => payout.payoutAccountId)
    .filter((item): item is string => !!item);
  const profileRefs = profileIds.map((profileId) =>
    db.collection("tutor_payout_accounts").doc(profileId)
  );
  const profileSnaps = profileRefs.length > 0 ? await db.getAll(...profileRefs) : [];
  const profileMap = new Map<string, TutorPayoutProfileView>();
  for (const snap of profileSnaps) {
    if (snap.exists) {
      profileMap.set(snap.id, payoutProfileViewFromDoc(snap));
    }
  }
  return {
    columns: [
      "payoutId",
      "payoutWeekKey",
      "tutorId",
      "tutorName",
      "status",
      "providerStatus",
      "amountZar",
      "currency",
      "payoutBatchId",
      "payoutKind",
      "requestedAt",
      "paidAt",
      "failedAt",
      "failureReason",
      "bankName",
      "accountNumberMasked",
      "verificationStatus",
    ],
    rows: payouts.map((payout) => {
      const profile = payout.payoutAccountId ?
        profileMap.get(payout.payoutAccountId) :
        null;
      return {
        payoutId: payout.payoutId,
        payoutWeekKey: payout.payoutWeekKey,
        tutorId: payout.tutorId,
        tutorName: tutorNameFromUserData(usersMap.get(payout.tutorId) ?? {}),
        status: payout.status,
        providerStatus: payout.providerStatus,
        amountZar: payout.amountZar,
        currency: payout.currency,
        payoutBatchId: payout.payoutBatchId,
        payoutKind: payout.payoutKind,
        requestedAt: timestampToIso(payout.requestedAt),
        paidAt: timestampToIso(payout.paidAt),
        failedAt: timestampToIso(payout.failedAt),
        failureReason: payout.failureReason,
        bankName: profile?.bankName ?? null,
        accountNumberMasked: profile?.accountNumberMasked ?? null,
        verificationStatus: profile?.verificationStatus ?? null,
      };
    }),
  };
}

export const refreshTutorPayoutDashboardAggregates = onCall(
  {region: REGION, timeoutSeconds: 540},
  async (request): Promise<Record<string, unknown>> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }
    assertPlatformAdmin(request.auth);

    const weekKey =
      toTrimmedString(request.data?.weekKey) ||
      nextOrSameMondayDateKey(new Date());
    const overview = await refreshDashboardOverview(weekKey);
    const weeklyTotals = await buildWeeklyTotalsItem(weekKey);
    return {
      weekKey,
      overview,
      weeklyTotals,
    };
  }
);

export const listTutorsDueForMondayPayout = onCall(
  {region: REGION, timeoutSeconds: 540},
  async (request): Promise<Record<string, unknown>> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }
    assertPlatformAdmin(request.auth);

    const weekKey =
      toTrimmedString(request.data?.weekKey) ||
      nextOrSameMondayDateKey(new Date());
    const limit = clampLimit(request.data?.limit);
    const items = (await buildDueTutorsForWeek(weekKey)).slice(0, limit);
    return {
      weekKey,
      scheduledPayoutLocalTime: TUTORING_PAYOUT_LOCAL_TIME,
      itemCount: items.length,
      totalDueAmountZar: toMoney(
        items.reduce((sum, item) => sum + item.dueAmountZar, 0)
      ),
      retryTutorCount: items.filter((item) => item.requiresRetryBatch).length,
      items,
    };
  }
);

export const getTutorPayoutTotalsByWeek = onCall(
  {region: REGION, timeoutSeconds: 540},
  async (request): Promise<Record<string, unknown>> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }
    assertPlatformAdmin(request.auth);

    const limit = clampLimit(request.data?.limit, 8);
    const weekKeys = await listRecentWeekKeys(limit);
    const items = await Promise.all(
      weekKeys.map((weekKey) => buildWeeklyTotalsItem(weekKey))
    );
    return {
      itemCount: items.length,
      items,
    };
  }
);

export const listBlockedTutorPayoutProfiles = onCall(
  {region: REGION, timeoutSeconds: 540},
  async (request): Promise<Record<string, unknown>> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }
    assertPlatformAdmin(request.auth);

    const limit = clampLimit(request.data?.limit);
    const items = await buildBlockedPayoutProfiles(limit);
    return {
      itemCount: items.length,
      items,
    };
  }
);

export const listFailedTutorPayoutAttempts = onCall(
  {region: REGION, timeoutSeconds: 540},
  async (request): Promise<Record<string, unknown>> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }
    assertPlatformAdmin(request.auth);

    const limit = clampLimit(request.data?.limit);
    const weekKey = toTrimmedString(request.data?.weekKey) || null;
    const items = await buildFailedPayoutAttempts({limit, weekKey});
    return {
      itemCount: items.length,
      items,
    };
  }
);

export const listDisputedTutorPayables = onCall(
  {region: REGION, timeoutSeconds: 540},
  async (request): Promise<Record<string, unknown>> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }
    assertPlatformAdmin(request.auth);

    const limit = clampLimit(request.data?.limit);
    const weekKey = toTrimmedString(request.data?.weekKey) || null;
    const items = await buildDisputedPayables({limit, weekKey});
    return {
      itemCount: items.length,
      items,
    };
  }
);

export const getTutorPayoutHistoryByTutor = onCall(
  {region: REGION, timeoutSeconds: 540},
  async (request): Promise<Record<string, unknown>> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }
    assertPlatformAdmin(request.auth);

    const tutorId = toTrimmedString(request.data?.tutorId);
    if (!tutorId) {
      throw new HttpsError("invalid-argument", "tutorId is required.");
    }

    const limit = clampLimit(request.data?.limit);
    const [items, userSnap] = await Promise.all([
      buildTutorPayoutHistory({tutorId, limit}),
      db.collection("users").doc(tutorId).get(),
    ]);
    return {
      tutorId,
      tutorName: tutorNameFromUserData(userSnap.data() ?? {}),
      itemCount: items.length,
      items,
    };
  }
);

export const exportTutorPayoutData = onCall(
  {region: REGION, timeoutSeconds: 540},
  async (request): Promise<Record<string, unknown>> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }
    assertPlatformAdmin(request.auth);

    const dataset = (
      toTrimmedString(request.data?.dataset).toLowerCase() ||
      "payout_records"
    ) as ExportDataset;
    const supportedDatasets = new Set<ExportDataset>([
      "payout_records",
      "weekly_totals",
      "due_this_monday",
      "blocked_profiles",
      "failed_attempts",
      "disputed_payables",
    ]);
    if (!supportedDatasets.has(dataset)) {
      throw new HttpsError("invalid-argument", "Unsupported export dataset.");
    }

    const weekKey =
      toTrimmedString(request.data?.weekKey) ||
      nextOrSameMondayDateKey(new Date());
    const tutorId = toTrimmedString(request.data?.tutorId) || null;
    const limit = clampLimit(request.data?.limit, 100);
    const exportPayload = await buildExportRows({
      dataset,
      weekKey,
      tutorId,
      limit,
    });
    const csv = buildAdminPayoutCsv(exportPayload.columns, exportPayload.rows);
    const fileName = `tutoring_payout_${dataset}_${weekKey}.csv`;

    logger.info("admin_tutor_payout_export_generated", {
      dataset,
      weekKey,
      tutorId,
      rowCount: exportPayload.rows.length,
      actorId: request.auth.uid,
    });

    return {
      dataset,
      weekKey,
      tutorId,
      rowCount: exportPayload.rows.length,
      fileName,
      contentType: "text/csv",
      columns: exportPayload.columns,
      csv,
    };
  }
);
