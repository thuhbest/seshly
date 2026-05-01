import * as admin from "firebase-admin";
import {HttpsError, onCall} from "./callable";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {
  type TutorPayoutBatchDoc,
  type TutorPayoutBatchItemDoc,
  type TutorPayoutAllocationDoc,
  type TutorPayoutBatchStatus,
  type TutorPayoutDoc,
  type TutorPayoutEventDoc,
  type TutorPayoutMode,
  type TutorPayoutProvider,
  buildBalanceSnapshot,
  settlementViewFromDoc,
  toMoney,
  asMoney,
  timestampToMillis,
  toTrimmedString,
} from "./tutorPayoutModels";
import {
  buildPayoutBatchSchemaFields,
  buildPayoutRecordSchemaFields,
} from "./tutoringFirestoreSchema";
import {
  assertPlatformAdmin,
  assertTutorReadyForPayout,
  deriveTutorApprovalSnapshot,
} from "./tutorApprovalState";
import {isVerifiedTutorPayoutProfile} from "./tutorPayoutProfileState";

const db = admin.firestore();
const REGION = "europe-west1";
const MANUAL_PROVIDER: TutorPayoutProvider = "MANUAL_BANK";
const WEEKLY_PAYOUT_TIME_ZONE = "Africa/Johannesburg";
const WEEKLY_PAYOUT_SCHEDULE = "0 6 * * 1";
const WEEKLY_BATCH_PROVIDER = "MOCK_WEEKLY_BATCH";
const OPEN_PAYOUT_STATUSES = new Set(["PENDING", "REQUESTED", "APPROVED", "PROCESSING"]);

interface TutorPayableFundingView {
  payableId: string;
  settlementId: string;
  tutorId: string;
  availableAmountZar: number;
  reservedAmountZar: number;
  paidAmountZar: number;
  blockedAmountZar: number;
  grossTutorEarningZar: number;
  payableStatus: string;
  payoutEligibilityStatus: string;
  payoutState: string;
  disputeStatus: string;
  scheduledPayoutDateKey: string | null;
  lastPayoutBatchId: string | null;
  lastPayoutRecordId: string | null;
  settledAt: admin.firestore.Timestamp | null;
}

interface WeeklyBatchBuildParams {
  batchId: string;
  batchDateKey: string;
  payoutKind: TutorPayoutDoc["payoutKind"];
  allowRebatchedPayables: boolean;
  retrySourceBatchId?: string | null;
  retryTutorId?: string | null;
}

interface WeeklyBatchBuildResult {
  batchId: string;
  batchDateKey: string;
  totalTutors: number;
  totalAmountZar: number;
  itemCount: number;
  draftCount: number;
  pendingCount: number;
  blockedCount: number;
  skippedCount: number;
  status: TutorPayoutBatchStatus;
}

interface RequestTutorPayoutResult {
  payoutId: string;
  tutorId: string;
  status: string;
  amountZar: number;
  availableBalanceZar: number;
  reservedForPayoutZar: number;
}

interface AdminPayoutResult {
  payoutId: string;
  status: string;
  providerStatus: string;
}

function nowServerTs() {
  return admin.firestore.FieldValue.serverTimestamp();
}

function asPositiveMoney(value: unknown): number | null {
  const amount = asMoney(value, -1);
  return amount > 0 ? amount : null;
}

function assertApprovedTutor(
  userData: Record<string, unknown>,
  tutorId: string
): void {
  assertTutorReadyForPayout(userData, tutorId);
}

function payoutStateAfterReservation(params: {
  reserved: number;
  paid: number;
  earning: number;
  held: number;
}): string {
  const remaining = toMoney(
    Math.max(0, params.earning - params.reserved - params.paid - params.held)
  );
  if (params.held > 0 && params.paid <= 0 && params.reserved <= 0) return "HELD";
  if (remaining <= 0 && params.paid >= params.earning - params.held - 0.0001) {
    return "PAID";
  }
  if (params.reserved > 0) return "RESERVED";
  if (params.paid > 0) return "PARTIALLY_PAID";
  return "UNPAID";
}

function payoutModeFromUserAndBalance(
  userData: Record<string, unknown>,
  balanceData: Record<string, unknown>
): TutorPayoutMode {
  const raw =
    toTrimmedString(balanceData.payoutMode) ||
    toTrimmedString(userData.payoutMode) ||
    "MANUAL";
  return raw === "AUTOMATED" ? "AUTOMATED" : "MANUAL";
}

function dateKeyInTimeZone(date: Date, timeZone: string): string {
  return new Intl.DateTimeFormat("sv-SE", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

function isTutorBlockedFromWeeklyPayout(userData: Record<string, unknown>): boolean {
  const accountType = toTrimmedString(userData.accountType).toLowerCase();
  const accessTier = toTrimmedString(userData.accessTier).toLowerCase();
  const approval = deriveTutorApprovalSnapshot({userData});
  return userData.isDisabled === true ||
    userData.tutorPayoutsBlocked === true ||
    userData.payoutsBlocked === true ||
    userData.blockedFromPayouts === true ||
    accountType === "instant_tutor" ||
    accessTier === "instant_tutor" ||
    !approval.payoutReady;
}

function draftBatchItem(params: {
  batchId: string;
  tutorId: string;
  payoutAccountId: string | null;
  payoutRecordId: string | null;
  amountZar: number;
  status: TutorPayoutBatchItemDoc["status"];
  skipReason: string | null;
  sourceSettlementIds: string[];
  sourcePayableIds: string[];
}): TutorPayoutBatchItemDoc {
  return {
    batchItemId: params.tutorId,
    batchId: params.batchId,
    tutorId: params.tutorId,
    payoutAccountId: params.payoutAccountId,
    payoutRecordId: params.payoutRecordId,
    amountZar: params.amountZar,
    currency: "ZAR",
    status: params.status,
    skipReason: params.skipReason,
    sourceSettlementIds: params.sourceSettlementIds,
    sourcePayableIds: params.sourcePayableIds,
    createdAt: nowServerTs(),
    updatedAt: nowServerTs(),
  };
}

function payoutAccountFromDoc(
  doc: FirebaseFirestore.QueryDocumentSnapshot | FirebaseFirestore.DocumentSnapshot
): Record<string, unknown> & {accountId: string} {
  return {
    accountId: doc.id,
    ...(doc.data() ?? {}),
  };
}

export function weeklyBatchIdForDateKey(batchDateKey: string): string {
  return `weekly_${batchDateKey}`;
}

export function retryBatchIdForSourceBatch(sourceBatchId: string, tutorId?: string | null): string {
  return tutorId ?
    `retry_${sourceBatchId}_${tutorId}` :
    `retry_${sourceBatchId}_all`;
}

function payoutRecordIdForBatch(batchId: string, tutorId: string): string {
  return `${batchId}_${tutorId}`;
}

function tutorPayableViewFromDoc(
  doc: FirebaseFirestore.QueryDocumentSnapshot | FirebaseFirestore.DocumentSnapshot
): TutorPayableFundingView {
  const data = doc.data() ?? {};
  return {
    payableId: doc.id,
    settlementId: toTrimmedString(data.settlementId) || doc.id,
    tutorId: toTrimmedString(data.tutorId),
    availableAmountZar: Math.max(0, asMoney(data.availableAmountZar, 0)),
    reservedAmountZar: Math.max(0, asMoney(data.reservedAmountZar, 0)),
    paidAmountZar: Math.max(0, asMoney(data.paidAmountZar, 0)),
    blockedAmountZar: Math.max(0, asMoney(data.blockedAmountZar, 0)),
    grossTutorEarningZar: Math.max(0, asMoney(data.grossTutorEarningZar, 0)),
    payableStatus: toTrimmedString(data.payableStatus).toLowerCase(),
    payoutEligibilityStatus: toTrimmedString(data.payoutEligibilityStatus).toUpperCase(),
    payoutState: toTrimmedString(data.payoutState).toUpperCase(),
    disputeStatus: toTrimmedString(data.disputeStatus).toLowerCase(),
    scheduledPayoutDateKey:
      toTrimmedString(data.scheduledPayoutDateKey) || null,
    lastPayoutBatchId:
      toTrimmedString(data.lastPayoutBatchId) || null,
    lastPayoutRecordId:
      toTrimmedString(data.lastPayoutRecordId) || null,
    settledAt:
      data.settledAt instanceof admin.firestore.Timestamp ?
        data.settledAt :
        null,
  };
}

function isOpenPayoutStatus(status: string): boolean {
  return OPEN_PAYOUT_STATUSES.has(status.toUpperCase());
}

export function shouldIncludeTutorPayableInBatch(
  payable: TutorPayableFundingView,
  options: {allowRebatchedPayables: boolean; batchDateKey: string}
): boolean {
  if (!payable.tutorId) return false;
  if (!payable.settledAt) return false;
  if (payable.availableAmountZar <= 0) return false;
  if (payable.payableStatus !== "available") return false;
  if (payable.payoutEligibilityStatus !== "ELIGIBLE") return false;
  if (payable.disputeStatus === "open" || payable.blockedAmountZar > 0) return false;
  if (
    payable.scheduledPayoutDateKey &&
    payable.scheduledPayoutDateKey !== options.batchDateKey
  ) {
    return false;
  }
  if (!options.allowRebatchedPayables &&
      (payable.lastPayoutBatchId || payable.lastPayoutRecordId)) {
    return false;
  }
  return true;
}

async function recomputeTutorBalanceTransaction(params: {
  tx: admin.firestore.Transaction;
  tutorId: string;
  userRef: admin.firestore.DocumentReference;
  balanceRef: admin.firestore.DocumentReference;
  defaultPayoutAccountId: string | null;
}): Promise<Record<string, unknown>> {
  const [userSnap, balanceSnap, settlementsSnap] = await Promise.all([
    params.tx.get(params.userRef),
    params.tx.get(params.balanceRef),
    params.tx.get(
      db.collection("tutor_session_settlements").where("tutorId", "==", params.tutorId)
    ),
  ]);

  if (!userSnap.exists) {
    throw new HttpsError("not-found", "Tutor not found.");
  }
  const userData = userSnap.data() ?? {};
  assertApprovedTutor(userData as Record<string, unknown>, params.tutorId);

  const balanceData = balanceSnap.data() ?? {};
  const payoutMode = payoutModeFromUserAndBalance(
    userData as Record<string, unknown>,
    balanceData as Record<string, unknown>
  );
  const settlements = settlementsSnap.docs.map((doc) => settlementViewFromDoc(doc));
  const snapshot = buildBalanceSnapshot({
    tutorId: params.tutorId,
    payoutMode,
    defaultPayoutAccountId:
      params.defaultPayoutAccountId ??
      (toTrimmedString(balanceData.defaultPayoutAccountId) || null),
    settlements,
    previousLastPayoutAt:
      balanceData.lastPayoutAt instanceof admin.firestore.Timestamp ?
        balanceData.lastPayoutAt :
        null,
  });

  params.tx.set(params.balanceRef, {
    ...snapshot,
    updatedAt: nowServerTs(),
    version: Math.max(1, Math.round(Number(balanceData.version ?? 0)) + 1),
  }, {merge: true});

  return {
    userData,
    balanceData,
    settlements,
    snapshot,
  };
}

async function findOpenWeeklyPayoutForTutor(params: {
  tutorId: string;
  batchDateKey: string;
  excludePayoutId?: string | null;
}): Promise<(Record<string, unknown> & {payoutId: string}) | null> {
  const snap = await db.collection("tutor_payouts")
    .where("tutorId", "==", params.tutorId)
    .where("payoutWeekKey", "==", params.batchDateKey)
    .limit(20)
    .get();

  for (const doc of snap.docs) {
    if (doc.id === params.excludePayoutId) {
      continue;
    }
    const data = doc.data() ?? {};
    if (isOpenPayoutStatus(toTrimmedString(data.status))) {
      return {
        payoutId: doc.id,
        ...data,
      };
    }
  }
  return null;
}

async function fetchTutorPayablesForDate(params: {
  tutorId?: string | null;
  batchDateKey: string;
}): Promise<TutorPayableFundingView[]> {
  let query: FirebaseFirestore.Query = db.collection("tutor_payables")
    .where("scheduledPayoutDateKey", "==", params.batchDateKey);
  if (params.tutorId) {
    query = query.where("tutorId", "==", params.tutorId);
  }
  const snap = await query.get();
  return snap.docs.map((doc) => tutorPayableViewFromDoc(doc));
}

function payableStateAfterReservation(params: {
  reserved: number;
  paid: number;
  earning: number;
  held: number;
}): string {
  return payoutStateAfterReservation(params);
}

async function reserveTutorPayablesForPayout(params: {
  tx: admin.firestore.Transaction;
  payoutRef: admin.firestore.DocumentReference;
  tutorId: string;
  amountZar: number;
  payables: TutorPayableFundingView[];
  batchId?: string | null;
}): Promise<{
  allocationCount: number;
  reservedAmountZar: number;
  sourceSettlementIds: string[];
  sourcePayableIds: string[];
}> {
  let remaining = toMoney(params.amountZar);
  let allocationCount = 0;
  let reservedAmountZar = 0;
  const sourceSettlementIds: string[] = [];
  const sourcePayableIds: string[] = [];

  for (const payable of params.payables.sort((left, right) =>
    timestampToMillis(left.settledAt) - timestampToMillis(right.settledAt)
  )) {
    if (remaining <= 0) break;
    const allocationAmountZar = toMoney(
      Math.min(remaining, payable.availableAmountZar)
    );
    if (allocationAmountZar <= 0) {
      continue;
    }

    const payableRef = db.collection("tutor_payables").doc(payable.payableId);
    const settlementRef = db.collection("tutor_session_settlements")
      .doc(payable.settlementId);
    const allocationRef = params.payoutRef.collection("allocations")
      .doc(payable.payableId);
    const [payableSnap, settlementSnap] = await Promise.all([
      params.tx.get(payableRef),
      params.tx.get(settlementRef),
    ]);
    if (!payableSnap.exists || !settlementSnap.exists) {
      continue;
    }
    const payableData = payableSnap.data() ?? {};
    const settlementData = settlementSnap.data() ?? {};
    const currentAvailableAmountZar = Math.max(
      0,
      asMoney(payableData.availableAmountZar, payable.availableAmountZar)
    );
    if (currentAvailableAmountZar <= 0) {
      continue;
    }
    const nextAllocationAmountZar = toMoney(
      Math.min(remaining, currentAvailableAmountZar)
    );
    if (nextAllocationAmountZar <= 0) {
      continue;
    }
    const currentReserved = Math.max(0, asMoney(payableData.reservedAmountZar, payable.reservedAmountZar));
    const currentPaid = Math.max(0, asMoney(payableData.paidAmountZar, payable.paidAmountZar));
    const currentHeld = Math.max(0, asMoney(
      payableData.blockedAmountZar ?? payableData.disputeHeldAmountZar,
      payable.blockedAmountZar
    ));
    const currentEarning = Math.max(0, asMoney(
      payableData.grossTutorEarningZar ?? settlementData.tutorEarningZar,
      payable.grossTutorEarningZar
    ));
    const nextReserved = toMoney(currentReserved + nextAllocationAmountZar);
    const nextAvailable = toMoney(
      Math.max(0, currentEarning - nextReserved - currentPaid - currentHeld)
    );
    const nextPayoutState = payableStateAfterReservation({
      reserved: nextReserved,
      paid: currentPaid,
      earning: currentEarning,
      held: currentHeld,
    });
    const nextPayableStatus =
      currentHeld > 0 ? "blocked" :
      nextReserved > 0 ? "reserved" :
      nextAvailable > 0 ? "available" :
      currentPaid > 0 ? "partially_paid" :
      "settled_zero";

    const allocationDoc: TutorPayoutAllocationDoc = {
      allocationId: allocationRef.id,
      payoutId: params.payoutRef.id,
      tutorId: params.tutorId,
      settlementId: payable.settlementId,
      allocatedAmountZar: nextAllocationAmountZar,
      status: "RESERVED",
      createdAt: nowServerTs(),
      updatedAt: nowServerTs(),
    };
    params.tx.set(allocationRef, allocationDoc);
    params.tx.set(payableRef, {
      reservedAmountZar: nextReserved,
      availableAmountZar: nextAvailable,
      payoutState: nextPayoutState,
      payableStatus: nextPayableStatus,
      lastPayoutRecordId: params.payoutRef.id,
      lastPayoutBatchId: params.batchId ?? null,
      updatedAt: nowServerTs(),
    }, {merge: true});
    params.tx.set(settlementRef, {
      payoutReservedAmountZar: nextReserved,
      availableForPayoutZar: nextAvailable,
      payoutState: nextPayoutState,
      lastPayoutRecordId: params.payoutRef.id,
      lastPayoutBatchId: params.batchId ?? null,
      updatedAt: nowServerTs(),
    }, {merge: true});

    allocationCount += 1;
    reservedAmountZar = toMoney(reservedAmountZar + nextAllocationAmountZar);
    sourceSettlementIds.push(payable.settlementId);
    sourcePayableIds.push(payable.payableId);
    remaining = toMoney(Math.max(0, remaining - nextAllocationAmountZar));
  }

  if (remaining > 0.0001) {
    throw new HttpsError(
      "failed-precondition",
      "Not enough eligible tutor payables were available for this payout."
    );
  }

  return {
    allocationCount,
    reservedAmountZar,
    sourceSettlementIds,
    sourcePayableIds,
  };
}

async function createPayoutEvent(params: {
  tx: admin.firestore.Transaction;
  payoutId: string;
  tutorId: string;
  eventType: string;
  actorType: TutorPayoutEventDoc["actorType"];
  actorId: string | null;
  note?: string | null;
  metadata?: Record<string, unknown>;
}): Promise<void> {
  const eventRef = db.collection("tutor_payout_events").doc();
  const eventDoc: TutorPayoutEventDoc = {
    eventId: eventRef.id,
    payoutId: params.payoutId,
    tutorId: params.tutorId,
    eventType: params.eventType,
    actorType: params.actorType,
    actorId: params.actorId,
    note: params.note ?? null,
    metadata: params.metadata ?? {},
    createdAt: nowServerTs(),
  };
  params.tx.set(eventRef, eventDoc);
}

async function releasePayoutAllocations(params: {
  tx: admin.firestore.Transaction;
  payoutRef: admin.firestore.DocumentReference;
  tutorId: string;
}): Promise<number> {
  const allocationsSnap = await params.tx.get(params.payoutRef.collection("allocations"));
  let releasedTotal = 0;

  for (const allocationDoc of allocationsSnap.docs) {
    const allocationData = allocationDoc.data() ?? {};
    const status = toTrimmedString(allocationData.status);
    if (status !== "RESERVED") continue;

    const settlementId = toTrimmedString(allocationData.settlementId);
    const allocatedAmountZar = asMoney(allocationData.allocatedAmountZar, 0);
    if (!settlementId || allocatedAmountZar <= 0) continue;

    const settlementRef = db.collection("tutor_session_settlements").doc(settlementId);
    const payableRef = db.collection("tutor_payables").doc(settlementId);
    const [settlementSnap, payableSnap] = await Promise.all([
      params.tx.get(settlementRef),
      params.tx.get(payableRef),
    ]);
    if (!settlementSnap.exists) continue;

    const settlementData = settlementSnap.data() ?? {};
    const payableData = payableSnap.data() ?? {};
    const nextReserved = toMoney(
      Math.max(
        0,
        asMoney(
          payableData.reservedAmountZar ?? settlementData.payoutReservedAmountZar,
          0
        ) - allocatedAmountZar
      )
    );
    const nextPaid = asMoney(
      payableData.paidAmountZar ?? settlementData.payoutPaidAmountZar,
      0
    );
    const nextHeld = asMoney(
      payableData.blockedAmountZar ?? settlementData.disputeHeldAmountZar,
      0
    );
    const nextEarning = asMoney(
      payableData.grossTutorEarningZar ?? settlementData.tutorEarningZar,
      0
    );
    const nextAvailable = toMoney(
      Math.max(0, nextEarning - nextReserved - nextPaid - nextHeld)
    );
    const nextPayoutState = payoutStateAfterReservation({
      reserved: nextReserved,
      paid: nextPaid,
      earning: nextEarning,
      held: nextHeld,
    });

    params.tx.set(settlementRef, {
      payoutReservedAmountZar: nextReserved,
      availableForPayoutZar: nextAvailable,
      payoutState: nextPayoutState,
      updatedAt: nowServerTs(),
    }, {merge: true});
    if (payableSnap.exists) {
      params.tx.set(payableRef, {
        reservedAmountZar: nextReserved,
        availableAmountZar: nextAvailable,
        payoutState: nextPayoutState,
        payableStatus:
          nextHeld > 0 ? "blocked" :
          nextReserved > 0 ? "reserved" :
          nextAvailable > 0 ? "available" :
          nextPaid > 0 ? "partially_paid" : "settled_zero",
        updatedAt: nowServerTs(),
      }, {merge: true});
    }

    params.tx.set(allocationDoc.ref, {
      status: "RELEASED",
      updatedAt: nowServerTs(),
    }, {merge: true});
    releasedTotal = toMoney(releasedTotal + allocatedAmountZar);
  }

  return releasedTotal;
}

async function markPayoutAllocationsPaid(params: {
  tx: admin.firestore.Transaction;
  payoutRef: admin.firestore.DocumentReference;
}): Promise<number> {
  const allocationsSnap = await params.tx.get(params.payoutRef.collection("allocations"));
  let paidTotal = 0;

  for (const allocationDoc of allocationsSnap.docs) {
    const allocationData = allocationDoc.data() ?? {};
    const status = toTrimmedString(allocationData.status);
    if (status !== "RESERVED") continue;

    const settlementId = toTrimmedString(allocationData.settlementId);
    const allocatedAmountZar = asMoney(allocationData.allocatedAmountZar, 0);
    if (!settlementId || allocatedAmountZar <= 0) continue;

    const settlementRef = db.collection("tutor_session_settlements").doc(settlementId);
    const payableRef = db.collection("tutor_payables").doc(settlementId);
    const [settlementSnap, payableSnap] = await Promise.all([
      params.tx.get(settlementRef),
      params.tx.get(payableRef),
    ]);
    if (!settlementSnap.exists) continue;

    const settlementData = settlementSnap.data() ?? {};
    const payableData = payableSnap.data() ?? {};
    const nextReserved = toMoney(
      Math.max(
        0,
        asMoney(
          payableData.reservedAmountZar ?? settlementData.payoutReservedAmountZar,
          0
        ) - allocatedAmountZar
      )
    );
    const nextPaid = toMoney(
      asMoney(
        payableData.paidAmountZar ?? settlementData.payoutPaidAmountZar,
        0
      ) + allocatedAmountZar
    );
    const nextHeld = asMoney(
      payableData.blockedAmountZar ?? settlementData.disputeHeldAmountZar,
      0
    );
    const nextEarning = asMoney(
      payableData.grossTutorEarningZar ?? settlementData.tutorEarningZar,
      0
    );
    const nextAvailable = toMoney(
      Math.max(0, nextEarning - nextReserved - nextPaid - nextHeld)
    );
    const nextPayoutState = payoutStateAfterReservation({
      reserved: nextReserved,
      paid: nextPaid,
      earning: nextEarning,
      held: nextHeld,
    });

    params.tx.set(settlementRef, {
      payoutReservedAmountZar: nextReserved,
      payoutPaidAmountZar: nextPaid,
      availableForPayoutZar: nextAvailable,
      payoutState: nextPayoutState,
      updatedAt: nowServerTs(),
    }, {merge: true});
    if (payableSnap.exists) {
      params.tx.set(payableRef, {
        reservedAmountZar: nextReserved,
        paidAmountZar: nextPaid,
        availableAmountZar: nextAvailable,
        payoutState: nextPayoutState,
        payableStatus:
          nextHeld > 0 ? "blocked" :
          nextPaid > 0 && nextAvailable > 0 ? "partially_paid" :
          nextPaid > 0 ? "paid" :
          nextReserved > 0 ? "reserved" :
          "settled_zero",
        updatedAt: nowServerTs(),
      }, {merge: true});
    }

    params.tx.set(allocationDoc.ref, {
      status: "PAID",
      updatedAt: nowServerTs(),
    }, {merge: true});
    paidTotal = toMoney(paidTotal + allocatedAmountZar);
  }

  return paidTotal;
}

export const requestTutorPayout = onCall(
  {region: REGION},
  async (request): Promise<RequestTutorPayoutResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }

    const tutorId = request.auth.uid;
    const amountZar = asPositiveMoney(request.data?.amountZar);
    const payoutAccountId = toTrimmedString(request.data?.payoutAccountId);
    if (!amountZar) {
      throw new HttpsError("invalid-argument", "amountZar must be greater than zero.");
    }

    const userRef = db.collection("users").doc(tutorId);
    const balanceRef = db.collection("tutor_balances").doc(tutorId);
    const payoutRef = db.collection("tutor_payouts").doc();

    return db.runTransaction(async (tx) => {
      const recomputed = await recomputeTutorBalanceTransaction({
        tx,
        tutorId,
        userRef,
        balanceRef,
        defaultPayoutAccountId: payoutAccountId || null,
      });
      const snapshot = recomputed.snapshot as ReturnType<typeof buildBalanceSnapshot>;
      const resolvedPayoutAccountId =
        payoutAccountId ||
        toTrimmedString(snapshot.defaultPayoutAccountId) ||
        null;
      if (!resolvedPayoutAccountId) {
        throw new HttpsError(
          "failed-precondition",
          "A payout account is required before requesting a payout."
        );
      }

      const payoutAccountRef = db
        .collection("tutor_payout_accounts")
        .doc(resolvedPayoutAccountId);
      const payoutAccountSnap = await tx.get(payoutAccountRef);
      if (!payoutAccountSnap.exists) {
        throw new HttpsError("not-found", "Payout account not found.");
      }
      const payoutAccountData = payoutAccountSnap.data() ?? {};
      if (toTrimmedString(payoutAccountData.tutorId) !== tutorId) {
        throw new HttpsError(
          "permission-denied",
          "This payout account does not belong to the current tutor."
        );
      }
      if (!isVerifiedTutorPayoutProfile(tutorId, payoutAccountData)) {
        throw new HttpsError(
          "failed-precondition",
          "The selected payout profile is not verified and payout-enabled."
        );
      }
      if (amountZar > snapshot.availableBalanceZar + 0.0001) {
        throw new HttpsError(
          "failed-precondition",
          "Requested payout exceeds the available balance."
        );
      }

      const payableSnap = await tx.get(
        db.collection("tutor_payables").where("tutorId", "==", tutorId)
      );
      const eligiblePayables = payableSnap.docs
        .map((doc) => tutorPayableViewFromDoc(doc))
        .filter((payable) =>
          payable.tutorId === tutorId &&
          payable.availableAmountZar > 0 &&
          payable.payableStatus === "available" &&
          payable.payoutEligibilityStatus === "ELIGIBLE" &&
          payable.disputeStatus !== "open" &&
          payable.blockedAmountZar <= 0
        );

      const reserved = await reserveTutorPayablesForPayout({
        tx,
        payoutRef,
        tutorId,
        amountZar,
        payables: eligiblePayables,
        batchId: null,
      });

      const payoutMode = snapshot.payoutMode;
      const payoutDoc: TutorPayoutDoc = {
        payoutId: payoutRef.id,
        tutorId,
        payoutAccountId: resolvedPayoutAccountId,
        payoutBatchId: null,
        payoutWeekKey: null,
        payoutKind: "manual_request",
        retryOfPayoutId: null,
        payoutMode,
        provider: payoutMode === "AUTOMATED" ? "PEACH_PAYOUTS" : MANUAL_PROVIDER,
        providerStatus: "NONE",
        status: "REQUESTED",
        amountZar,
        currency: "ZAR",
        allocationCount: reserved.allocationCount,
        externalTransferId: null,
        externalBatchId: null,
        requestedAt: nowServerTs(),
        approvedAt: null,
        processingAt: null,
        paidAt: null,
        failedAt: null,
        cancelledAt: null,
        requestedByUserId: tutorId,
        approvedByUserId: null,
        failureReason: null,
        adminNote: null,
        createdAt: nowServerTs(),
        updatedAt: nowServerTs(),
      };
      tx.set(payoutRef, {
        ...payoutDoc,
        ...buildPayoutRecordSchemaFields(
          payoutRef.id,
          payoutDoc as unknown as Record<string, unknown>
        ),
      });

      tx.set(balanceRef, {
        payoutMode,
        defaultPayoutAccountId: resolvedPayoutAccountId,
        reservedForPayoutZar: toMoney(
          snapshot.reservedForPayoutZar + reserved.reservedAmountZar
        ),
        availableBalanceZar: toMoney(
          snapshot.availableBalanceZar - reserved.reservedAmountZar
        ),
        updatedAt: nowServerTs(),
      }, {merge: true});

      await createPayoutEvent({
        tx,
        payoutId: payoutRef.id,
        tutorId,
        eventType: "REQUESTED",
        actorType: "TUTOR",
        actorId: tutorId,
        metadata: {amountZar},
      });

      return {
        payoutId: payoutRef.id,
        tutorId,
        status: "REQUESTED",
        amountZar,
        availableBalanceZar: toMoney(
          snapshot.availableBalanceZar - reserved.reservedAmountZar
        ),
        reservedForPayoutZar: toMoney(
          snapshot.reservedForPayoutZar + reserved.reservedAmountZar
        ),
      };
    });
  }
);

export const approveTutorPayout = onCall(
  {region: REGION},
  async (request): Promise<AdminPayoutResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }
    assertPlatformAdmin(request.auth);

    const payoutId = toTrimmedString(request.data?.payoutId);
    const adminNote = toTrimmedString(request.data?.adminNote);
    if (!payoutId) {
      throw new HttpsError("invalid-argument", "payoutId is required.");
    }

    const payoutRef = db.collection("tutor_payouts").doc(payoutId);
    return db.runTransaction(async (tx) => {
      const payoutSnap = await tx.get(payoutRef);
      if (!payoutSnap.exists) {
        throw new HttpsError("not-found", "Payout not found.");
      }
      const payoutData = payoutSnap.data() ?? {};
      const status = toTrimmedString(payoutData.status);
      if (!["PENDING", "REQUESTED"].includes(status)) {
        throw new HttpsError(
          "failed-precondition",
          "Only pending or requested payouts can be approved."
        );
      }

      const nextPayout = {
        ...payoutData,
        status: "APPROVED",
        approvedAt: nowServerTs(),
        approvedByUserId: request.auth?.uid ?? null,
        adminNote: adminNote || null,
        updatedAt: nowServerTs(),
      };
      tx.set(payoutRef, {
        ...nextPayout,
        ...buildPayoutRecordSchemaFields(payoutId, nextPayout),
      }, {merge: true});

      await createPayoutEvent({
        tx,
        payoutId,
        tutorId: toTrimmedString(payoutData.tutorId),
        eventType: "APPROVED",
        actorType: "ADMIN",
        actorId: request.auth?.uid ?? null,
        note: adminNote || null,
      });

      return {
        payoutId,
        status: "APPROVED",
        providerStatus: toTrimmedString(payoutData.providerStatus) || "NONE",
      };
    });
  }
);

export const rejectTutorPayout = onCall(
  {region: REGION},
  async (request): Promise<AdminPayoutResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }
    assertPlatformAdmin(request.auth);

    const payoutId = toTrimmedString(request.data?.payoutId);
    const reason = toTrimmedString(request.data?.reason);
    if (!payoutId || !reason) {
      throw new HttpsError("invalid-argument", "payoutId and reason are required.");
    }

    const payoutRef = db.collection("tutor_payouts").doc(payoutId);
    return db.runTransaction(async (tx) => {
      const payoutSnap = await tx.get(payoutRef);
      if (!payoutSnap.exists) {
        throw new HttpsError("not-found", "Payout not found.");
      }
      const payoutData = payoutSnap.data() ?? {};
      const status = toTrimmedString(payoutData.status);
      if (!["PENDING", "REQUESTED", "APPROVED"].includes(status)) {
        throw new HttpsError(
          "failed-precondition",
          "Only pending, requested, or approved payouts can be rejected."
        );
      }

      const tutorId = toTrimmedString(payoutData.tutorId);
      const balanceRef = db.collection("tutor_balances").doc(tutorId);
      const balanceSnap = await tx.get(balanceRef);
      const balanceData = balanceSnap.data() ?? {};
      const releasedTotal = await releasePayoutAllocations({
        tx,
        payoutRef,
        tutorId,
      });

      const nextPayout = {
        ...payoutData,
        status: "REJECTED",
        failureReason: reason,
        failedAt: nowServerTs(),
        updatedAt: nowServerTs(),
      };
      tx.set(payoutRef, {
        ...nextPayout,
        ...buildPayoutRecordSchemaFields(payoutId, nextPayout),
      }, {merge: true});

      tx.set(balanceRef, {
        reservedForPayoutZar: toMoney(
          Math.max(0, asMoney(balanceData.reservedForPayoutZar, 0) - releasedTotal)
        ),
        availableBalanceZar: toMoney(
          asMoney(balanceData.availableBalanceZar, 0) + releasedTotal
        ),
        updatedAt: nowServerTs(),
      }, {merge: true});

      await createPayoutEvent({
        tx,
        payoutId,
        tutorId,
        eventType: "REJECTED",
        actorType: "ADMIN",
        actorId: request.auth?.uid ?? null,
        note: reason,
      });

      return {
        payoutId,
        status: "REJECTED",
        providerStatus: toTrimmedString(payoutData.providerStatus) || "NONE",
      };
    });
  }
);

export const markTutorPayoutProcessing = onCall(
  {region: REGION},
  async (request): Promise<AdminPayoutResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }
    assertPlatformAdmin(request.auth);

    const payoutId = toTrimmedString(request.data?.payoutId);
    const externalBatchId = toTrimmedString(request.data?.externalBatchId);
    const externalTransferId = toTrimmedString(request.data?.externalTransferId);
    if (!payoutId) {
      throw new HttpsError("invalid-argument", "payoutId is required.");
    }

    const payoutRef = db.collection("tutor_payouts").doc(payoutId);
    return db.runTransaction(async (tx) => {
      const payoutSnap = await tx.get(payoutRef);
      if (!payoutSnap.exists) {
        throw new HttpsError("not-found", "Payout not found.");
      }
      const payoutData = payoutSnap.data() ?? {};
      const status = toTrimmedString(payoutData.status);
      if (!["PENDING", "REQUESTED", "APPROVED"].includes(status)) {
        throw new HttpsError(
          "failed-precondition",
          "Only pending, requested, or approved payouts can move to processing."
        );
      }

      const nextPayout = {
        ...payoutData,
        status: "PROCESSING",
        providerStatus: "QUEUED",
        processingAt: nowServerTs(),
        externalBatchId: externalBatchId || null,
        externalTransferId: externalTransferId || null,
        updatedAt: nowServerTs(),
      };
      tx.set(payoutRef, {
        ...nextPayout,
        ...buildPayoutRecordSchemaFields(payoutId, nextPayout),
      }, {merge: true});

      await createPayoutEvent({
        tx,
        payoutId,
        tutorId: toTrimmedString(payoutData.tutorId),
        eventType: "PROCESSING",
        actorType: "ADMIN",
        actorId: request.auth?.uid ?? null,
        metadata: {
          externalBatchId: externalBatchId || null,
          externalTransferId: externalTransferId || null,
        },
      });

      return {
        payoutId,
        status: "PROCESSING",
        providerStatus: "QUEUED",
      };
    });
  }
);

export const markTutorPayoutPaid = onCall(
  {region: REGION},
  async (request): Promise<AdminPayoutResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }
    assertPlatformAdmin(request.auth);

    const payoutId = toTrimmedString(request.data?.payoutId);
    const externalTransferId = toTrimmedString(request.data?.externalTransferId);
    if (!payoutId) {
      throw new HttpsError("invalid-argument", "payoutId is required.");
    }

    const payoutRef = db.collection("tutor_payouts").doc(payoutId);
    return db.runTransaction(async (tx) => {
      const payoutSnap = await tx.get(payoutRef);
      if (!payoutSnap.exists) {
        throw new HttpsError("not-found", "Payout not found.");
      }
      const payoutData = payoutSnap.data() ?? {};
      const status = toTrimmedString(payoutData.status);
      if (!["PENDING", "REQUESTED", "APPROVED", "PROCESSING"].includes(status)) {
        throw new HttpsError(
          "failed-precondition",
          "This payout cannot be marked as paid from its current state."
        );
      }

      const tutorId = toTrimmedString(payoutData.tutorId);
      const balanceRef = db.collection("tutor_balances").doc(tutorId);
      const tutorRef = db.collection("users").doc(tutorId);
      const balanceSnap = await tx.get(balanceRef);
      const balanceData = balanceSnap.data() ?? {};
      const paidTotal = await markPayoutAllocationsPaid({
        tx,
        payoutRef,
      });

      const nextPayout = {
        ...payoutData,
        status: "PAID",
        providerStatus: "SETTLED",
        externalTransferId: externalTransferId || null,
        paidAt: nowServerTs(),
        updatedAt: nowServerTs(),
      };
      tx.set(payoutRef, {
        ...nextPayout,
        ...buildPayoutRecordSchemaFields(payoutId, nextPayout),
      }, {merge: true});

      tx.set(balanceRef, {
        reservedForPayoutZar: toMoney(
          Math.max(0, asMoney(balanceData.reservedForPayoutZar, 0) - paidTotal)
        ),
        paidOutZar: toMoney(asMoney(balanceData.paidOutZar, 0) + paidTotal),
        lastPayoutAt: nowServerTs(),
        updatedAt: nowServerTs(),
      }, {merge: true});

      tx.set(tutorRef, {
        "walletPayoutPendingZar": admin.firestore.FieldValue.increment(-paidTotal),
        "walletUpdatedAt": nowServerTs(),
      }, {merge: true});

      await createPayoutEvent({
        tx,
        payoutId,
        tutorId,
        eventType: "PAID",
        actorType: "ADMIN",
        actorId: request.auth?.uid ?? null,
        metadata: {externalTransferId: externalTransferId || null},
      });

      return {
        payoutId,
        status: "PAID",
        providerStatus: "SETTLED",
      };
    });
  }
);

export const markTutorPayoutFailed = onCall(
  {region: REGION},
  async (request): Promise<AdminPayoutResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }
    assertPlatformAdmin(request.auth);

    const payoutId = toTrimmedString(request.data?.payoutId);
    const reason = toTrimmedString(request.data?.reason);
    if (!payoutId || !reason) {
      throw new HttpsError("invalid-argument", "payoutId and reason are required.");
    }

    const payoutRef = db.collection("tutor_payouts").doc(payoutId);
    return db.runTransaction(async (tx) => {
      const payoutSnap = await tx.get(payoutRef);
      if (!payoutSnap.exists) {
        throw new HttpsError("not-found", "Payout not found.");
      }
      const payoutData = payoutSnap.data() ?? {};
      const status = toTrimmedString(payoutData.status);
      if (!["PENDING", "REQUESTED", "APPROVED", "PROCESSING", "BLOCKED"].includes(status)) {
        throw new HttpsError(
          "failed-precondition",
          "This payout cannot be failed from its current state."
        );
      }

      const tutorId = toTrimmedString(payoutData.tutorId);
      const balanceRef = db.collection("tutor_balances").doc(tutorId);
      const balanceSnap = await tx.get(balanceRef);
      const balanceData = balanceSnap.data() ?? {};
      const releasedTotal = await releasePayoutAllocations({
        tx,
        payoutRef,
        tutorId,
      });

      const nextPayout = {
        ...payoutData,
        status: "FAILED",
        providerStatus: "FAILED",
        failureReason: reason,
        failedAt: nowServerTs(),
        updatedAt: nowServerTs(),
      };
      tx.set(payoutRef, {
        ...nextPayout,
        ...buildPayoutRecordSchemaFields(payoutId, nextPayout),
      }, {merge: true});

      tx.set(balanceRef, {
        reservedForPayoutZar: toMoney(
          Math.max(0, asMoney(balanceData.reservedForPayoutZar, 0) - releasedTotal)
        ),
        availableBalanceZar: toMoney(
          asMoney(balanceData.availableBalanceZar, 0) + releasedTotal
        ),
        updatedAt: nowServerTs(),
      }, {merge: true});

      await createPayoutEvent({
        tx,
        payoutId,
        tutorId,
        eventType: "FAILED",
        actorType: "ADMIN",
        actorId: request.auth?.uid ?? null,
        note: reason,
      });

      return {
        payoutId,
        status: "FAILED",
        providerStatus: "FAILED",
      };
    });
  }
);

async function findVerifiedDefaultPayoutProfile(
  tutorId: string
): Promise<(Record<string, unknown> & {accountId: string}) | null> {
  const payoutAccountsSnap = await db
    .collection("tutor_payout_accounts")
    .where("tutorId", "==", tutorId)
    .get();
  const verifiedProfiles = payoutAccountsSnap.docs
    .map((doc) => payoutAccountFromDoc(doc))
    .filter((account) => isVerifiedTutorPayoutProfile(tutorId, account));
  return (
    verifiedProfiles.find((account) => account.isDefault === true) ??
    verifiedProfiles[0] ??
    null
  );
}

export function summarizeBatchStatus(params: {
  draftCount: number;
  pendingCount: number;
  blockedCount: number;
  skippedCount: number;
}): TutorPayoutBatchStatus {
  if (params.draftCount <= 0 && params.pendingCount <= 0) {
    return "SKIPPED";
  }
  if (params.blockedCount > 0 || params.skippedCount > 0 || params.pendingCount > 0) {
    return "PARTIAL";
  }
  return "DRAFT";
}

async function createOrRefreshWeeklyTutorPayoutBatch(
  params: WeeklyBatchBuildParams
): Promise<WeeklyBatchBuildResult> {
  const batchRef = db.collection("tutor_payout_batches").doc(params.batchId);
  const payableViews = await fetchTutorPayablesForDate({
    tutorId: params.retryTutorId ?? null,
    batchDateKey: params.batchDateKey,
  });
  const payablesByTutor = new Map<string, TutorPayableFundingView[]>();
  for (const payable of payableViews) {
    if (!payable.tutorId) {
      continue;
    }
    const items = payablesByTutor.get(payable.tutorId) ?? [];
    items.push(payable);
    payablesByTutor.set(payable.tutorId, items);
  }

  let totalTutors = 0;
  let totalAmountZar = 0;
  let itemCount = 0;
  let draftCount = 0;
  let pendingCount = 0;
  let blockedCount = 0;
  let skippedCount = 0;

  for (const [tutorId, rawPayables] of payablesByTutor.entries()) {
    const itemRef = batchRef.collection("items").doc(tutorId);
    const payoutId = payoutRecordIdForBatch(params.batchId, tutorId);
    const payoutRef = db.collection("tutor_payouts").doc(payoutId);
    const sourceSettlementIds = [...new Set(rawPayables.map((payable) => payable.settlementId))];
    const sourcePayableIds = [...new Set(rawPayables.map((payable) => payable.payableId))];
    const userSnap = await db.collection("users").doc(tutorId).get();

    if (!userSnap.exists) {
      await itemRef.set(
        draftBatchItem({
          batchId: params.batchId,
          tutorId,
          payoutAccountId: null,
          payoutRecordId: null,
          amountZar: 0,
          status: "SKIPPED",
          skipReason: "missing_tutor_user",
          sourceSettlementIds,
          sourcePayableIds,
        }),
        {merge: true}
      );
      itemCount += 1;
      skippedCount += 1;
      continue;
    }

    const userData = userSnap.data() ?? {};
    const defaultAccount = await findVerifiedDefaultPayoutProfile(tutorId);
    const blockedTutor = isTutorBlockedFromWeeklyPayout(userData as Record<string, unknown>);
    const eligiblePayables = rawPayables.filter((payable) =>
      shouldIncludeTutorPayableInBatch(payable, {
        allowRebatchedPayables: params.allowRebatchedPayables,
        batchDateKey: params.batchDateKey,
      })
    );
    const openPayout = await findOpenWeeklyPayoutForTutor({
      tutorId,
      batchDateKey: params.batchDateKey,
      excludePayoutId: payoutId,
    });

    if (blockedTutor) {
      await itemRef.set(
        draftBatchItem({
          batchId: params.batchId,
          tutorId,
          payoutAccountId: defaultAccount?.accountId ?? null,
          payoutRecordId: null,
          amountZar: 0,
          status: "BLOCKED",
          skipReason: "blocked_or_ineligible_tutor",
          sourceSettlementIds,
          sourcePayableIds,
        }),
        {merge: true}
      );
      itemCount += 1;
      blockedCount += 1;
      continue;
    }

    if (!defaultAccount) {
      await itemRef.set(
        draftBatchItem({
          batchId: params.batchId,
          tutorId,
          payoutAccountId: null,
          payoutRecordId: null,
          amountZar: 0,
          status: "BLOCKED",
          skipReason: "missing_verified_payout_profile",
          sourceSettlementIds,
          sourcePayableIds,
        }),
        {merge: true}
      );
      itemCount += 1;
      blockedCount += 1;
      continue;
    }

    if (openPayout) {
      const pendingAmountZar = Math.max(0, asMoney(openPayout.amountZar, 0));
      await itemRef.set(
        draftBatchItem({
          batchId: params.batchId,
          tutorId,
          payoutAccountId: defaultAccount.accountId,
          payoutRecordId: openPayout.payoutId,
          amountZar: pendingAmountZar,
          status: "PENDING",
          skipReason: "pending_existing_payout_record",
          sourceSettlementIds,
          sourcePayableIds,
        }),
        {merge: true}
      );
      itemCount += 1;
      pendingCount += 1;
      totalTutors += 1;
      totalAmountZar = toMoney(totalAmountZar + pendingAmountZar);
      continue;
    }

    if (eligiblePayables.length === 0) {
      await itemRef.set(
        draftBatchItem({
          batchId: params.batchId,
          tutorId,
          payoutAccountId: defaultAccount.accountId,
          payoutRecordId: null,
          amountZar: 0,
          status: "SKIPPED",
          skipReason: params.allowRebatchedPayables ?
            "no_retry_eligible_payables" :
            "no_eligible_payables",
          sourceSettlementIds,
          sourcePayableIds,
        }),
        {merge: true}
      );
      itemCount += 1;
      skippedCount += 1;
      continue;
    }

    const payoutResult = await db.runTransaction(async (tx) => {
      const payoutSnap = await tx.get(payoutRef);
      if (payoutSnap.exists) {
        const payoutData = payoutSnap.data() ?? {};
        const payoutStatus = toTrimmedString(payoutData.status).toUpperCase();
        if (isOpenPayoutStatus(payoutStatus) || payoutStatus === "PAID") {
          return {
            payoutId: payoutRef.id,
            amountZar: Math.max(0, asMoney(payoutData.amountZar, 0)),
            allocationCount: Math.max(0, Math.round(Number(payoutData.allocationCount ?? 0))),
            existing: true,
          };
        }
      }

      const userRef = db.collection("users").doc(tutorId);
      const balanceRef = db.collection("tutor_balances").doc(tutorId);
      const recomputed = await recomputeTutorBalanceTransaction({
        tx,
        tutorId,
        userRef,
        balanceRef,
        defaultPayoutAccountId: defaultAccount.accountId,
      });
      const snapshot = recomputed.snapshot as ReturnType<typeof buildBalanceSnapshot>;
      const reserveAllAmountZar = toMoney(
        eligiblePayables.reduce((sum, payable) => sum + payable.availableAmountZar, 0)
      );
      const reserved = await reserveTutorPayablesForPayout({
        tx,
        payoutRef,
        tutorId,
        amountZar: reserveAllAmountZar,
        payables: eligiblePayables,
        batchId: params.batchId,
      });
      if (reserved.reservedAmountZar <= 0 || reserved.allocationCount <= 0) {
        throw new HttpsError(
          "failed-precondition",
          "No tutor payables were reserved for this weekly payout batch."
        );
      }

      const payoutMode = snapshot.payoutMode;
      const payoutDoc: TutorPayoutDoc = {
        payoutId: payoutRef.id,
        tutorId,
        payoutAccountId: defaultAccount.accountId,
        payoutBatchId: params.batchId,
        payoutWeekKey: params.batchDateKey,
        payoutKind: params.payoutKind,
        retryOfPayoutId: null,
        payoutMode,
        provider: payoutMode === "AUTOMATED" ? "MOCK_PAYSTACK" : MANUAL_PROVIDER,
        providerStatus: "NONE",
        status: "PENDING",
        amountZar: reserved.reservedAmountZar,
        currency: "ZAR",
        allocationCount: reserved.allocationCount,
        externalTransferId: null,
        externalBatchId: null,
        requestedAt: nowServerTs(),
        approvedAt: null,
        processingAt: null,
        paidAt: null,
        failedAt: null,
        cancelledAt: null,
        requestedByUserId: "system:weekly_tutor_payout_batch",
        approvedByUserId: null,
        failureReason: null,
        adminNote: null,
        createdAt: nowServerTs(),
        updatedAt: nowServerTs(),
      };
      tx.set(payoutRef, {
        ...payoutDoc,
        ...buildPayoutRecordSchemaFields(
          payoutRef.id,
          payoutDoc as unknown as Record<string, unknown>
        ),
      }, {merge: true});
      tx.set(balanceRef, {
        payoutMode,
        defaultPayoutAccountId: defaultAccount.accountId,
        reservedForPayoutZar: toMoney(
          snapshot.reservedForPayoutZar + reserved.reservedAmountZar
        ),
        availableBalanceZar: toMoney(
          snapshot.availableBalanceZar - reserved.reservedAmountZar
        ),
        updatedAt: nowServerTs(),
      }, {merge: true});

      await createPayoutEvent({
        tx,
        payoutId: payoutRef.id,
        tutorId,
        eventType: "BATCHED",
        actorType: "SYSTEM",
        actorId: null,
        metadata: {
          payoutBatchId: params.batchId,
          payoutWeekKey: params.batchDateKey,
          payoutKind: params.payoutKind,
          retrySourceBatchId: params.retrySourceBatchId ?? null,
        },
      });

      return {
        payoutId: payoutRef.id,
        amountZar: reserved.reservedAmountZar,
        allocationCount: reserved.allocationCount,
        existing: false,
      };
    });

    await itemRef.set(
      draftBatchItem({
        batchId: params.batchId,
        tutorId,
        payoutAccountId: defaultAccount.accountId,
        payoutRecordId: payoutResult.payoutId,
        amountZar: payoutResult.amountZar,
        status: "DRAFT",
        skipReason: null,
        sourceSettlementIds,
        sourcePayableIds,
      }),
      {merge: true}
    );
    itemCount += 1;
    draftCount += 1;
    totalTutors += 1;
    totalAmountZar = toMoney(totalAmountZar + payoutResult.amountZar);
  }

  const status = summarizeBatchStatus({
    draftCount,
    pendingCount,
    blockedCount,
    skippedCount,
  });
  const existingBatchSnap = await batchRef.get();
  const existingBatchData = existingBatchSnap.data() ?? {};
  const batchDoc: TutorPayoutBatchDoc & Record<string, unknown> = {
    batchId: params.batchId,
    status,
    provider: WEEKLY_BATCH_PROVIDER,
    providerExecutionReady: false,
    scheduledForTimeZone: WEEKLY_PAYOUT_TIME_ZONE,
    scheduledForLocalTime: "Monday 06:00",
    batchDateKey: params.batchDateKey,
    totalTutors,
    totalAmountZar,
    currency: "ZAR",
    itemCount,
    draftReason:
      params.payoutKind === "weekly_batch_retry" ?
        "Admin retry batch for tutor payables that became eligible after a failed, pending, or blocked weekly payout path." :
        "Weekly tutoring payouts are batched from tutor payables only. Provider execution remains mock-only until live payout transfers are approved.",
    payoutBatchSource:
      params.payoutKind === "weekly_batch_retry" ?
        "admin_retry" :
        "scheduled_weekly",
    retrySourceBatchId: params.retrySourceBatchId ?? null,
    draftRecordCount: draftCount,
    pendingRecordCount: pendingCount,
    blockedItemCount: blockedCount,
    skippedItemCount: skippedCount,
    createdAt: existingBatchData.createdAt ?? nowServerTs(),
    updatedAt: nowServerTs(),
  };
  await batchRef.set({
    ...batchDoc,
    ...buildPayoutBatchSchemaFields(params.batchId, batchDoc),
  }, {merge: true});

  return {
    batchId: params.batchId,
    batchDateKey: params.batchDateKey,
    totalTutors,
    totalAmountZar,
    itemCount,
    draftCount,
    pendingCount,
    blockedCount,
    skippedCount,
    status,
  };
}

export const generateWeeklyTutorPayoutBatch = onSchedule(
  {
    schedule: WEEKLY_PAYOUT_SCHEDULE,
    region: REGION,
    timeZone: WEEKLY_PAYOUT_TIME_ZONE,
  },
  async () => {
    const now = new Date();
    const batchDateKey = dateKeyInTimeZone(now, WEEKLY_PAYOUT_TIME_ZONE);
    await createOrRefreshWeeklyTutorPayoutBatch({
      batchId: weeklyBatchIdForDateKey(batchDateKey),
      batchDateKey,
      payoutKind: "weekly_batch",
      allowRebatchedPayables: false,
    });
  }
);

export const retryTutorPayoutBatch = onCall(
  {region: REGION, timeoutSeconds: 540},
  async (request): Promise<WeeklyBatchBuildResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }
    assertPlatformAdmin(request.auth);

    const sourceBatchId = toTrimmedString(request.data?.batchId);
    const tutorId = toTrimmedString(request.data?.tutorId) || null;
    if (!sourceBatchId) {
      throw new HttpsError("invalid-argument", "batchId is required.");
    }

    const sourceBatchSnap = await db.collection("tutor_payout_batches").doc(sourceBatchId).get();
    if (!sourceBatchSnap.exists) {
      throw new HttpsError("not-found", "Source payout batch not found.");
    }
    const sourceBatchData = sourceBatchSnap.data() ?? {};
    const batchDateKey =
      toTrimmedString(sourceBatchData.batchDateKey) ||
      toTrimmedString(sourceBatchData.payoutWeekKey);
    if (!batchDateKey) {
      throw new HttpsError(
        "failed-precondition",
        "Source payout batch is missing a payout period key."
      );
    }

    return createOrRefreshWeeklyTutorPayoutBatch({
      batchId: retryBatchIdForSourceBatch(sourceBatchId, tutorId),
      batchDateKey,
      payoutKind: "weekly_batch_retry",
      allowRebatchedPayables: true,
      retrySourceBatchId: sourceBatchId,
      retryTutorId: tutorId,
    });
  }
);
