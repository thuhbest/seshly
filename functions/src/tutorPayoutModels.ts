import * as admin from "firebase-admin";
import {type TutorPayoutVerificationStatus} from "./tutorPayoutProfileState";

export type TutorPayoutMode = "MANUAL" | "AUTOMATED";
export type TutorPayoutStatus =
  | "PENDING"
  | "REQUESTED"
  | "APPROVED"
  | "PROCESSING"
  | "PAID"
  | "FAILED"
  | "BLOCKED"
  | "REJECTED"
  | "CANCELLED";
export type TutorPayoutProvider =
  | "MANUAL_BANK"
  | "PEACH_PAYOUTS"
  | "MOCK_PAYSTACK";
export type TutorPayoutProviderStatus =
  | "NONE"
  | "QUEUED"
  | "SENT"
  | "SETTLED"
  | "FAILED";
export type TutorPayoutAllocationStatus =
  | "RESERVED"
  | "PAID"
  | "RELEASED";
export type TutorPayoutBatchStatus =
  | "DRAFT"
  | "PARTIAL"
  | "SKIPPED";
export type TutorSettlementPayoutState =
  | "UNPAID"
  | "RESERVED"
  | "PARTIALLY_PAID"
  | "PAID"
  | "HELD";
export type TutorSettlementEligibilityStatus =
  | "ELIGIBLE"
  | "HELD"
  | "INELIGIBLE";

export interface TutorBalanceSnapshotDoc {
  tutorId: string;
  currency: string;
  payoutMode: TutorPayoutMode;
  defaultPayoutAccountId: string | null;
  totalSettledTutorEarningsZar: number;
  reservedForPayoutZar: number;
  paidOutZar: number;
  heldForDisputesZar: number;
  availableBalanceZar: number;
  lastSettlementAt: admin.firestore.Timestamp | null;
  lastPayoutAt: admin.firestore.Timestamp | null;
  updatedAt: admin.firestore.FieldValue | admin.firestore.Timestamp;
  version: number;
}

export interface TutorPayoutAccountDoc {
  accountId: string;
  tutorId: string;
  provider: TutorPayoutProvider;
  status: "ACTIVE" | "PENDING_VERIFICATION" | "DISABLED";
  verificationStatus: TutorPayoutVerificationStatus;
  bankCode: string;
  accountHolderName: string;
  bankName: string;
  accountNumberMasked: string;
  maskedAccountNumber: string;
  recipientCode: string | null;
  payoutEnabled: boolean;
  payoutBlockedReason: string | null;
  branchCode: string;
  providerBeneficiaryId: string | null;
  countryCode: string;
  currency: string;
  isDefault: boolean;
  providerExecutionReady?: boolean;
  createdAt: admin.firestore.FieldValue | admin.firestore.Timestamp;
  updatedAt: admin.firestore.FieldValue | admin.firestore.Timestamp;
}

export interface TutorPayoutDoc {
  payoutId: string;
  tutorId: string;
  payoutAccountId: string;
  payoutBatchId: string | null;
  payoutWeekKey: string | null;
  payoutKind: "manual_request" | "weekly_batch" | "weekly_batch_retry";
  retryOfPayoutId: string | null;
  payoutMode: TutorPayoutMode;
  provider: TutorPayoutProvider;
  providerStatus: TutorPayoutProviderStatus;
  status: TutorPayoutStatus;
  amountZar: number;
  currency: string;
  allocationCount: number;
  externalTransferId: string | null;
  externalBatchId: string | null;
  requestedAt: admin.firestore.FieldValue | admin.firestore.Timestamp;
  approvedAt: admin.firestore.FieldValue | admin.firestore.Timestamp | null;
  processingAt: admin.firestore.FieldValue | admin.firestore.Timestamp | null;
  paidAt: admin.firestore.FieldValue | admin.firestore.Timestamp | null;
  failedAt: admin.firestore.FieldValue | admin.firestore.Timestamp | null;
  cancelledAt: admin.firestore.FieldValue | admin.firestore.Timestamp | null;
  requestedByUserId: string;
  approvedByUserId: string | null;
  failureReason: string | null;
  adminNote: string | null;
  createdAt: admin.firestore.FieldValue | admin.firestore.Timestamp;
  updatedAt: admin.firestore.FieldValue | admin.firestore.Timestamp;
}

export interface TutorPayoutAllocationDoc {
  allocationId: string;
  payoutId: string;
  tutorId: string;
  settlementId: string;
  allocatedAmountZar: number;
  status: TutorPayoutAllocationStatus;
  createdAt: admin.firestore.FieldValue | admin.firestore.Timestamp;
  updatedAt: admin.firestore.FieldValue | admin.firestore.Timestamp;
}

export interface TutorPayoutEventDoc {
  eventId: string;
  payoutId: string;
  tutorId: string;
  eventType: string;
  actorType: "TUTOR" | "ADMIN" | "SYSTEM" | "PROVIDER";
  actorId: string | null;
  note: string | null;
  metadata: Record<string, unknown>;
  createdAt: admin.firestore.FieldValue | admin.firestore.Timestamp;
}

export interface TutorPayoutBatchDoc {
  batchId: string;
  status: TutorPayoutBatchStatus;
  provider: TutorPayoutProvider | "MOCK_WEEKLY_BATCH";
  providerExecutionReady: boolean;
  scheduledForTimeZone: string;
  scheduledForLocalTime: string;
  batchDateKey: string;
  totalTutors: number;
  totalAmountZar: number;
  currency: string;
  itemCount: number;
  draftReason: string;
  createdAt: admin.firestore.FieldValue | admin.firestore.Timestamp;
  updatedAt: admin.firestore.FieldValue | admin.firestore.Timestamp;
}

export interface TutorPayoutBatchItemDoc {
  batchItemId: string;
  batchId: string;
  tutorId: string;
  payoutAccountId: string | null;
  payoutRecordId: string | null;
  amountZar: number;
  currency: string;
  status: "DRAFT" | "SKIPPED" | "BLOCKED" | "PENDING";
  skipReason: string | null;
  sourceSettlementIds: string[];
  sourcePayableIds: string[];
  createdAt: admin.firestore.FieldValue | admin.firestore.Timestamp;
  updatedAt: admin.firestore.FieldValue | admin.firestore.Timestamp;
}

export interface TutorSettlementPayoutView {
  settlementId: string;
  tutorId: string;
  settlementStatus: string;
  tutorEarningZar: number;
  payoutReservedAmountZar: number;
  payoutPaidAmountZar: number;
  disputeHeldAmountZar: number;
  payoutState: TutorSettlementPayoutState;
  payoutEligibilityStatus: TutorSettlementEligibilityStatus;
  availableForPayoutZar: number;
  settledAt: admin.firestore.Timestamp | null;
}

export function toTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

export function toMoney(value: number): number {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

export function asMoney(value: unknown, fallback = 0): number {
  if (typeof value === "number" && Number.isFinite(value)) {
    return toMoney(value);
  }
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return toMoney(parsed);
    }
  }
  return fallback;
}

export function timestampToMillis(value: unknown): number {
  if (value instanceof admin.firestore.Timestamp) {
    return value.toMillis();
  }
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return value.getTime();
  }
  return 0;
}

export function settlementViewFromDoc(
  doc: FirebaseFirestore.QueryDocumentSnapshot | FirebaseFirestore.DocumentSnapshot
): TutorSettlementPayoutView {
  const data = doc.data() ?? {};
  const tutorEarningZar = Math.max(0, asMoney(data.tutorEarningZar, 0));
  const payoutReservedAmountZar = Math.max(
    0,
    asMoney(data.payoutReservedAmountZar, 0)
  );
  const payoutPaidAmountZar = Math.max(
    0,
    asMoney(data.payoutPaidAmountZar, 0)
  );
  const disputeHeldAmountZar = Math.max(
    0,
    asMoney(data.disputeHeldAmountZar, 0)
  );
  const payoutEligibilityStatus = (
    toTrimmedString(data.payoutEligibilityStatus) || "ELIGIBLE"
  ) as TutorSettlementEligibilityStatus;
  const availableForPayoutZar = payoutEligibilityStatus !== "ELIGIBLE" ?
    0 :
    toMoney(
      Math.max(
        0,
        tutorEarningZar -
          payoutReservedAmountZar -
          payoutPaidAmountZar -
          disputeHeldAmountZar
      )
    );

  return {
    settlementId: doc.id,
    tutorId: toTrimmedString(data.tutorId),
    settlementStatus: toTrimmedString(data.settlementStatus),
    tutorEarningZar,
    payoutReservedAmountZar,
    payoutPaidAmountZar,
    disputeHeldAmountZar,
    payoutState: (
      toTrimmedString(data.payoutState) || "UNPAID"
    ) as TutorSettlementPayoutState,
    payoutEligibilityStatus,
    availableForPayoutZar,
    settledAt:
      data.settledAt instanceof admin.firestore.Timestamp ?
        data.settledAt :
        null,
  };
}

export function buildBalanceSnapshot(params: {
  tutorId: string;
  payoutMode: TutorPayoutMode;
  defaultPayoutAccountId: string | null;
  settlements: TutorSettlementPayoutView[];
  previousLastPayoutAt: admin.firestore.Timestamp | null;
}): Omit<TutorBalanceSnapshotDoc, "updatedAt" | "version"> {
  const totalSettledTutorEarningsZar = toMoney(
    params.settlements.reduce((sum, settlement) => sum + settlement.tutorEarningZar, 0)
  );
  const reservedForPayoutZar = toMoney(
    params.settlements.reduce((sum, settlement) => sum + settlement.payoutReservedAmountZar, 0)
  );
  const paidOutZar = toMoney(
    params.settlements.reduce((sum, settlement) => sum + settlement.payoutPaidAmountZar, 0)
  );
  const heldForDisputesZar = toMoney(
    params.settlements.reduce((sum, settlement) => sum + settlement.disputeHeldAmountZar, 0)
  );
  const availableBalanceZar = toMoney(
    Math.max(
      0,
      totalSettledTutorEarningsZar -
        reservedForPayoutZar -
        paidOutZar -
        heldForDisputesZar
    )
  );
  const sortedSettlements = [...params.settlements].sort((left, right) =>
    timestampToMillis(right.settledAt) - timestampToMillis(left.settledAt)
  );

  return {
    tutorId: params.tutorId,
    currency: "ZAR",
    payoutMode: params.payoutMode,
    defaultPayoutAccountId: params.defaultPayoutAccountId,
    totalSettledTutorEarningsZar,
    reservedForPayoutZar,
    paidOutZar,
    heldForDisputesZar,
    availableBalanceZar,
    lastSettlementAt: sortedSettlements[0]?.settledAt ?? null,
    lastPayoutAt: params.previousLastPayoutAt,
  };
}
