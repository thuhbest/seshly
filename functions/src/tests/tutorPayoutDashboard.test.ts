import test from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";

if (admin.apps.length === 0) {
  admin.initializeApp();
}

import {
  buildTutorNextPayoutDisplayLabel,
  deriveTutorPayoutBlockedReason,
  nextTutorPayoutMondayDateKey,
} from "../tutorPayoutDashboard.js";

test("nextTutorPayoutMondayDateKey resolves the upcoming Monday in payout timezone", () => {
  assert.equal(
    nextTutorPayoutMondayDateKey(new Date("2026-04-01T07:00:00.000Z")),
    "2026-04-06",
  );
  assert.equal(
    nextTutorPayoutMondayDateKey(new Date("2026-04-06T01:00:00.000Z")),
    "2026-04-06",
  );
  assert.equal(
    buildTutorNextPayoutDisplayLabel("2026-04-06"),
    "Upcoming Monday • 2026-04-06",
  );
});

test("deriveTutorPayoutBlockedReason prioritizes payout verification and tutor approval", () => {
  const verificationPending = deriveTutorPayoutBlockedReason({
    userData: {
      tutorApplicationStatus: "approved",
      tutoringEligibilityStatus: "eligible",
      adminApproval: true,
      payoutOnboardingStatus: "pending",
      accountType: "student",
      accessTier: "full",
    },
    payoutProfile: {
      payoutProfileId: "profile_1",
      tutorId: "tutor_1",
      payoutEnabled: false,
      verificationStatus: "pending",
      status: "PENDING_VERIFICATION",
      bankName: "Bank",
      accountNumberMasked: "****1234",
      payoutBlockedReason: null,
      isDefault: true,
      recipientCode: null,
    },
  });
  assert.equal(verificationPending.code, "payout_not_enabled");

  const blockedTutor = deriveTutorPayoutBlockedReason({
    userData: {
      tutorApplicationStatus: "suspended",
      tutoringEligibilityStatus: "blocked",
      adminApproval: false,
      payoutOnboardingStatus: "blocked",
      accountType: "student",
      accessTier: "full",
    },
    payoutProfile: null,
  });
  assert.equal(blockedTutor.code, "tutor_blocked");
});
