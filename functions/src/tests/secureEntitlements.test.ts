import assert from "node:assert/strict";
import test from "node:test";

import {
  buildSeshCreditPurchaseQuote,
  buildSeshMinutesPurchaseQuote,
  decideSeshFocusEarlyUnlockCharge,
  decideSeshFocusStartCharge,
  decideGoldTickActivation,
} from "../secureEntitlements";

function fakeTimestamp(iso: string) {
  return {
    toDate: () => new Date(iso),
  };
}

test("SeshCredit purchase quote is server-computed", () => {
  const quote = buildSeshCreditPurchaseQuote(15);
  assert.equal(quote.credits, 15);
  assert.equal(quote.amountZar, 30);
  assert.equal(quote.currency, "ZAR");
});

test("Sesh Minutes purchase quote is server-computed", () => {
  const quote = buildSeshMinutesPurchaseQuote(25);
  assert.equal(quote.minutes, 25);
  assert.equal(quote.amountZar, 25);
  assert.equal(quote.currency, "ZAR");
});

test("Gold Tick activation rejects unapproved tutors", () => {
  const result = decideGoldTickActivation({
    tutorApplicationStatus: "submitted",
    tutoringEligibilityStatus: "ineligible",
    adminApproval: false,
    billingSetupStatus: "ready",
    billingCardLast4: "4242",
    billingProviderReference: "ref_123",
    goldTick: {
      eligibilityStatus: "eligible",
    },
  });

  assert.equal(result.allowed, false);
  assert.match(result.reason, /approved tutors/i);
});

test("Gold Tick activation requires verified payment readiness", () => {
  const result = decideGoldTickActivation({
    accountType: "student",
    accessTier: "verified_student",
    tutorApplicationStatus: "approved",
    tutoringEligibilityStatus: "eligible",
    adminApproval: true,
    billingSetupStatus: "missing",
    billingCardLast4: "",
    billingProviderReference: "",
    goldTick: {
      eligibilityStatus: "eligible",
      subscriptionStatus: "none",
    },
  });

  assert.equal(result.allowed, false);
  assert.match(result.reason, /payment method/i);
});

test("Gold Tick activation allows eligible approved tutors with billing readiness", () => {
  const result = decideGoldTickActivation({
    accountType: "student",
    accessTier: "verified_student",
    tutorApplicationStatus: "approved",
    tutoringEligibilityStatus: "eligible",
    adminApproval: true,
    billingSetupStatus: "ready",
    billingCardLast4: "4242",
    billingProviderReference: "ref_123",
    goldTick: {
      eligibilityStatus: "eligible",
      subscriptionStatus: "none",
    },
  });

  assert.equal(result.allowed, true);
  assert.equal(result.reason, "");
});

test("SeshFocus start prefers monthly free passes before xp or minutes", () => {
  const result = decideSeshFocusStartCharge({
    freeFocusPasses: 3,
    xp: 120,
    seshMinutes: 40,
    lastPassReset: fakeTimestamp("2026-04-01T00:00:00Z"),
  }, new Date("2026-04-20T00:00:00Z"));

  assert.equal(result.allowed, true);
  assert.equal(result.resourceType, "free_pass");
  assert.equal(result.resourceLabel, "Free Pass");
  assert.equal(result.nextFreeFocusPasses, 2);
  assert.equal(result.nextXp, 120);
  assert.equal(result.nextSeshMinutes, 40);
});

test("SeshFocus start falls back to xp when passes are exhausted", () => {
  const result = decideSeshFocusStartCharge({
    freeFocusPasses: 0,
    xp: 75,
    seshMinutes: 0,
    lastPassReset: fakeTimestamp("2026-04-01T00:00:00Z"),
  }, new Date("2026-04-20T00:00:00Z"));

  assert.equal(result.allowed, true);
  assert.equal(result.resourceType, "xp");
  assert.equal(result.resourceLabel, "50 XP");
  assert.equal(result.nextXp, 25);
});

test("SeshFocus early unlock requires server-side balance and xp checks", () => {
  const result = decideSeshFocusEarlyUnlockCharge({
    focusEmergencyPasses: 0,
    seshMinutes: 5,
    xp: 40,
    lastFocusReset: fakeTimestamp("2026-04-01T00:00:00Z"),
  }, new Date("2026-04-20T00:00:00Z"));

  assert.equal(result.allowed, false);
  assert.match(result.reason, /need 1 emergency pass/i);
});
