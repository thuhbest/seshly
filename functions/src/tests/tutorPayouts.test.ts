import test from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";

if (admin.apps.length === 0) {
  admin.initializeApp();
}

import {
  retryBatchIdForSourceBatch,
  shouldIncludeTutorPayableInBatch,
  summarizeBatchStatus,
  weeklyBatchIdForDateKey,
} from "../tutorPayouts.js";

test("weekly payout batch ids are deterministic by payout date key", () => {
  assert.equal(weeklyBatchIdForDateKey("2026-04-06"), "weekly_2026-04-06");
  assert.equal(
    retryBatchIdForSourceBatch("weekly_2026-04-06", "tutor_123"),
    "retry_weekly_2026-04-06_tutor_123",
  );
  assert.equal(
    retryBatchIdForSourceBatch("weekly_2026-04-06"),
    "retry_weekly_2026-04-06_all",
  );
});

test("weekly payout batching includes only clean available tutor payables", () => {
  const payable = {
    payableId: "payable_1",
    settlementId: "settlement_1",
    tutorId: "tutor_123",
    availableAmountZar: 250,
    reservedAmountZar: 0,
    paidAmountZar: 0,
    blockedAmountZar: 0,
    grossTutorEarningZar: 250,
    payableStatus: "available",
    payoutEligibilityStatus: "ELIGIBLE",
    payoutState: "UNPAID",
    disputeStatus: "none",
    scheduledPayoutDateKey: "2026-04-06",
    lastPayoutBatchId: null,
    lastPayoutRecordId: null,
    settledAt: admin.firestore.Timestamp.fromMillis(1),
  };

  assert.equal(
    shouldIncludeTutorPayableInBatch(payable, {
      allowRebatchedPayables: false,
      batchDateKey: "2026-04-06",
    }),
    true,
  );
});

test("weekly payout batching excludes disputed or previously batched payables unless retrying", () => {
  const disputedPayable = {
    payableId: "payable_2",
    settlementId: "settlement_2",
    tutorId: "tutor_123",
    availableAmountZar: 150,
    reservedAmountZar: 0,
    paidAmountZar: 0,
    blockedAmountZar: 50,
    grossTutorEarningZar: 200,
    payableStatus: "available",
    payoutEligibilityStatus: "HELD",
    payoutState: "HELD",
    disputeStatus: "open",
    scheduledPayoutDateKey: "2026-04-06",
    lastPayoutBatchId: null,
    lastPayoutRecordId: null,
    settledAt: admin.firestore.Timestamp.fromMillis(1),
  };
  const historicalPayable = {
    ...disputedPayable,
    blockedAmountZar: 0,
    payoutEligibilityStatus: "ELIGIBLE",
    payoutState: "UNPAID",
    disputeStatus: "resolved",
    lastPayoutBatchId: "weekly_2026-04-06",
    lastPayoutRecordId: "weekly_2026-04-06_tutor_123",
  };

  assert.equal(
    shouldIncludeTutorPayableInBatch(disputedPayable, {
      allowRebatchedPayables: false,
      batchDateKey: "2026-04-06",
    }),
    false,
  );
  assert.equal(
    shouldIncludeTutorPayableInBatch(historicalPayable, {
      allowRebatchedPayables: false,
      batchDateKey: "2026-04-06",
    }),
    false,
  );
  assert.equal(
    shouldIncludeTutorPayableInBatch(historicalPayable, {
      allowRebatchedPayables: true,
      batchDateKey: "2026-04-06",
    }),
    true,
  );
});

test("batch status summary marks mixed outcomes as partial", () => {
  assert.equal(
    summarizeBatchStatus({
      draftCount: 2,
      pendingCount: 1,
      blockedCount: 0,
      skippedCount: 0,
    }),
    "PARTIAL",
  );
  assert.equal(
    summarizeBatchStatus({
      draftCount: 0,
      pendingCount: 0,
      blockedCount: 2,
      skippedCount: 3,
    }),
    "SKIPPED",
  );
});
