import test from "node:test";
import assert from "node:assert/strict";
import {
  computeTutoringSettlementComputation,
  deriveDisputeHoldMutation,
  deriveDisputeReleaseMutation,
} from "../tutoringSettlement.js";

test("tutor earnings are derived only from captured amounts", () => {
  const settlement = computeTutoringSettlementComputation({
    capturedAmountZar: 120,
    pendingCaptureAmountZar: 24,
    finalAmountDueZar: 144,
  });

  assert.equal(settlement.tutorEarningZar, 100);
  assert.equal(settlement.platformFeeZar, 20);
  assert.equal(settlement.pendingCaptureAmountZar, 24);
  assert.equal(settlement.uncapturedAmountZar, 24);
  assert.equal(settlement.availableForPayoutZar, 100);
  assert.equal(settlement.settlementStatus, "partial");
});

test("captured-only tutor earning rounds to cents", () => {
  const settlement = computeTutoringSettlementComputation({
    capturedAmountZar: 121,
    finalAmountDueZar: 121,
  });

  assert.equal(settlement.tutorEarningZar, 100.83);
  assert.equal(settlement.platformFeeZar, 20.17);
  assert.equal(settlement.settlementStatus, "completed");
});

test("dispute hold freezes only currently available tutor earnings", () => {
  const hold = deriveDisputeHoldMutation({
    tutorEarningZar: 100,
    payoutReservedAmountZar: 10,
    payoutPaidAmountZar: 15,
    disputeHeldAmountZar: 5,
    holdAmountZar: 200,
  });

  assert.equal(hold.appliedHoldAmountZar, 70);
  assert.equal(hold.disputeHeldAmountZar, 75);
  assert.equal(hold.availableForPayoutZar, 0);
  assert.equal(hold.payoutEligibilityStatus, "HELD");
  assert.equal(hold.payoutState, "RESERVED");
});

test("dispute release restores payable availability without exceeding held funds", () => {
  const release = deriveDisputeReleaseMutation({
    tutorEarningZar: 100,
    payoutReservedAmountZar: 10,
    payoutPaidAmountZar: 15,
    disputeHeldAmountZar: 75,
    releaseAmountZar: 50,
  });

  assert.equal(release.appliedReleaseAmountZar, 50);
  assert.equal(release.disputeHeldAmountZar, 25);
  assert.equal(release.availableForPayoutZar, 50);
  assert.equal(release.payoutEligibilityStatus, "HELD");
  assert.equal(release.payoutState, "RESERVED");
});
