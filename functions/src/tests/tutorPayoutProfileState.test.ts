import test from "node:test";
import assert from "node:assert/strict";
import {
  deriveTutorPayoutVerificationStatus,
  isBlockedTutorPayoutProfile,
  isVerifiedTutorPayoutProfile,
  maskSouthAfricanAccountNumber,
} from "../tutorPayoutProfileState.js";

test("verified tutor payout profile requires recipient and payout enablement", () => {
  const profile = {
    tutorId: "tutor_123",
    provider: "MOCK_PAYSTACK",
    status: "ACTIVE",
    verificationStatus: "verified",
    bankCode: "051001",
    bankName: "Standard Bank",
    accountNumberMasked: maskSouthAfricanAccountNumber("1234567890"),
    accountHolderName: "Tutor Example",
    recipientCode: "RCP_demo_verified",
    payoutEnabled: true,
  };

  assert.equal(deriveTutorPayoutVerificationStatus(profile), "verified");
  assert.equal(isVerifiedTutorPayoutProfile("tutor_123", profile), true);
});

test("pending tutor payout profile stays unverified before recipient creation", () => {
  const profile = {
    tutorId: "tutor_123",
    provider: "MOCK_PAYSTACK",
    status: "PENDING_VERIFICATION",
    verificationStatus: "pending",
    bankCode: "250655",
    bankName: "First National Bank",
    accountNumberMasked: maskSouthAfricanAccountNumber("1234567890"),
    accountHolderName: "Tutor Example",
    recipientCode: null,
    payoutEnabled: false,
  };

  assert.equal(deriveTutorPayoutVerificationStatus(profile), "pending");
  assert.equal(isVerifiedTutorPayoutProfile("tutor_123", profile), false);
  assert.equal(isBlockedTutorPayoutProfile(profile), false);
});

test("disabled tutor payout profile is blocked", () => {
  const profile = {
    tutorId: "tutor_123",
    provider: "MOCK_PAYSTACK",
    status: "DISABLED",
    verificationStatus: "blocked",
    bankCode: "632005",
    bankName: "ABSA",
    accountNumberMasked: maskSouthAfricanAccountNumber("1234567890"),
    accountHolderName: "Tutor Example",
    recipientCode: null,
    payoutEnabled: false,
    payoutBlockedReason: "manual_review_required",
  };

  assert.equal(deriveTutorPayoutVerificationStatus(profile), "blocked");
  assert.equal(isBlockedTutorPayoutProfile(profile), true);
  assert.equal(isVerifiedTutorPayoutProfile("tutor_123", profile), false);
});
