import {HttpsError, onCall} from "./callable";
import {onDocumentUpdated} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";

// Retired from the live tutoring flow.
// Tutoring payments now run through tutorBookings.ts, tutoringPayments.ts,
// tutorSessions.ts, tutorBillingTick.ts, and the adapter layer in
// functions/src/payments/. This file is preserved only as legacy reference.

const db = admin.firestore();

const REGION = "europe-west1";
const DEFAULT_ESTIMATED_MINUTES = 60;
const LEGACY_WALLET_MODEL = "wallet_hold_settlement";
const CARD_MODEL = "card_authorize_settlement";

interface PricingSnapshot {
  tutorRatePerMinute: number;
  platformFeePerMinute: number;
  totalRatePerMinute: number;
}

interface SettlementSummary {
  paymentIntentId: string;
  requestId: string;
  billableMinutes: number;
  totalChargeZar: number;
  capturedAmountZar: number;
  tutorPayoutZar: number;
  platformRevenueZar: number;
  settlementStatus: string;
}

function asNumber(value: unknown, fallback = 0): number {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return fallback;
}

function toMoney(value: number): number {
  return Number(value.toFixed(2));
}

function pricingFrom(data: Record<string, unknown>): PricingSnapshot {
  const nested = (data.pricing as Record<string, unknown> | undefined) ?? {};
  const tutorRate = asNumber(
    data.tutorRatePerMinute,
    asNumber(nested.tutorRatePerMinute, 0)
  );
  const platformFee = asNumber(
    data.platformFeePerMinute,
    asNumber(nested.platformFeePerMinute, 0)
  );
  const totalRate = asNumber(
    data.totalRatePerMinute,
    asNumber(nested.totalRatePerMinute, 0)
  );

  if (totalRate > 0) {
    return {
      tutorRatePerMinute: toMoney(tutorRate > 0 ? tutorRate : totalRate * 0.8),
      platformFeePerMinute: toMoney(platformFee > 0 ? platformFee : totalRate * 0.2),
      totalRatePerMinute: toMoney(totalRate),
    };
  }

  const inferredTotal = tutorRate > 0 ? tutorRate + platformFee : 0;
  return {
    tutorRatePerMinute: toMoney(tutorRate),
    platformFeePerMinute: toMoney(platformFee),
    totalRatePerMinute: toMoney(inferredTotal),
  };
}

function paymentModelFrom(data: Record<string, unknown>): string {
  return (data.paymentModel ?? CARD_MODEL).toString();
}

function studentCardReady(data: Record<string, unknown>): boolean {
  return (data.billingSetupStatus ?? "").toString() === "ready" &&
    (data.billingCardLast4 ?? "").toString().trim().length >= 4;
}

function instantTutorCardReady(data: Record<string, unknown>): boolean {
  return (data.temporaryPaymentSetupStatus ?? "").toString() === "ready" &&
    (data.temporaryCardLast4 ?? "").toString().trim().length >= 4;
}

function usesTemporaryInstantTutorCard(
  requestData: Record<string, unknown>,
  studentData: Record<string, unknown>
): boolean {
  const profileType = (
    requestData.paymentProfileType ??
    studentData.paymentProfileType ??
    ""
  ).toString().toLowerCase();
  if (profileType === "temporary_instant_tutor_card") return true;

  const accountType = (
    requestData.studentAccountType ??
    studentData.accountType ??
    ""
  ).toString().toLowerCase();
  if (accountType === "instant_tutor") return true;

  const accessTier = (
    requestData.studentAccessTier ??
    studentData.accessTier ??
    ""
  ).toString().toLowerCase();
  return accessTier === "instant_tutor" ||
    studentData.instantTutorAccess === true;
}

function cardReadyForRequest(
  requestData: Record<string, unknown>,
  studentData: Record<string, unknown>
): boolean {
  if (usesTemporaryInstantTutorCard(requestData, studentData)) {
    return instantTutorCardReady(studentData);
  }
  return studentCardReady(studentData);
}

function paymentMethodSummaryFrom(
  requestData: Record<string, unknown>,
  studentData: Record<string, unknown>
): string {
  const fromRequest = (requestData.paymentMethodSummary ?? "").toString().trim();
  if (fromRequest) return fromRequest;

  const useTemporary = usesTemporaryInstantTutorCard(requestData, studentData);
  const rawBrand = useTemporary ?
    studentData.temporaryCardBrand :
    studentData.billingCardBrand;
  const rawLast4 = useTemporary ?
    studentData.temporaryCardLast4 :
    studentData.billingCardLast4;
  const brand = (rawBrand ?? "Card").toString().trim() || "Card";
  const last4 = (rawLast4 ?? "").toString().trim();
  if (!last4) return brand;
  return `${brand} •••• ${last4}`;
}

async function authorizeHoldForAcceptedRequest(
  requestId: string,
  requestData: Record<string, unknown>
): Promise<void> {
  const paymentIntentId = (requestData.paymentIntentId ?? requestId).toString();
  const studentId = (requestData.studentId ?? "").toString();
  const tutorId = (requestData.tutorId ?? "").toString();
  if (!studentId || !tutorId) return;

  const requestRef = db.collection("tutor_requests").doc(requestId);
  const intentRef = db.collection("session_payment_intents").doc(paymentIntentId);
  const studentRef = db.collection("users").doc(studentId);
  const pricing = pricingFrom(requestData);
  const estimatedMinutes = Math.max(
    5,
    Math.min(
      240,
      Math.round(asNumber(
        requestData.estimatedSessionMinutes,
        DEFAULT_ESTIMATED_MINUTES
      ))
    )
  );
  const holdAmount = toMoney(pricing.totalRatePerMinute * estimatedMinutes);

  await db.runTransaction(async (tx) => {
    const requestSnap = await tx.get(requestRef);
    const latestRequest = requestSnap.data() ?? {};
    if (latestRequest.status !== "accepted") return;

    const studentSnap = await tx.get(studentRef);
    if (!studentSnap.exists) return;
    const studentData = studentSnap.data() ?? {};

    const intentSnap = await tx.get(intentRef);
    const intentData = intentSnap.data() ?? {};
    const alreadyHeld = (intentData.holdStatus ?? "").toString() === "authorized";
    if (alreadyHeld) return;

    const paymentModel = paymentModelFrom({
      ...requestData,
      ...intentData,
    });

    if (paymentModel === LEGACY_WALLET_MODEL) {
      const walletBalance = asNumber(studentData.walletBalanceZar, 0);
      if (walletBalance + 0.0001 < holdAmount) {
        tx.set(requestRef, {
          status: "payment_failed",
          paymentStatus: "hold_failed",
          paymentFailureReason: "insufficient_wallet_balance",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
        tx.set(intentRef, {
          requestId,
          studentId,
          tutorId,
          status: "hold_failed",
          holdStatus: "failed",
          settlementStatus: "blocked",
          holdAmountZar: holdAmount,
          estimatedHoldMinutes: estimatedMinutes,
          paymentModel,
          currency: (requestData.currency ?? "ZAR").toString(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
        return;
      }

      tx.set(studentRef, {
        walletBalanceZar: admin.firestore.FieldValue.increment(-holdAmount),
        walletHoldZar: admin.firestore.FieldValue.increment(holdAmount),
        walletUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      tx.set(intentRef, {
        requestId,
        studentId,
        tutorId,
        status: "session_authorized",
        holdStatus: "authorized",
        settlementStatus: "accruing",
        holdAmountZar: holdAmount,
        holdRemainingZar: holdAmount,
        estimatedHoldMinutes: estimatedMinutes,
        paymentModel,
        currency: (requestData.currency ?? "ZAR").toString(),
        pricing,
        tutorRatePerMinute: pricing.tutorRatePerMinute,
        platformFeePerMinute: pricing.platformFeePerMinute,
        totalRatePerMinute: pricing.totalRatePerMinute,
        holdAuthorizedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      tx.set(requestRef, {
        paymentStatus: "hold_authorized",
        holdAmountZar: holdAmount,
        paymentIntentId,
        paymentModel,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      const holdTxRef = studentRef.collection("wallet_transactions").doc();
      tx.set(holdTxRef, {
        type: "session_hold",
        direction: "debit",
        status: "completed",
        requestId,
        paymentIntentId,
        amountZar: holdAmount,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    if (!cardReadyForRequest(requestData, studentData)) {
      tx.set(requestRef, {
        status: "payment_failed",
        paymentStatus: "hold_failed",
        paymentFailureReason: "missing_payment_method",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      tx.set(intentRef, {
        requestId,
        studentId,
        tutorId,
        status: "hold_failed",
        holdStatus: "failed",
        settlementStatus: "blocked",
        holdAmountZar: holdAmount,
        estimatedHoldMinutes: estimatedMinutes,
        paymentModel: CARD_MODEL,
        paymentMethodStatus: "missing",
        currency: (requestData.currency ?? "ZAR").toString(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      return;
    }

    const paymentSummary = paymentMethodSummaryFrom(requestData, studentData);
    tx.set(intentRef, {
      requestId,
      studentId,
      tutorId,
      status: "session_authorized",
      holdStatus: "authorized",
      settlementStatus: "accruing",
      holdAmountZar: holdAmount,
      holdRemainingZar: holdAmount,
      estimatedHoldMinutes: estimatedMinutes,
      paymentModel: CARD_MODEL,
      paymentMethodType: "card",
      paymentMethodStatus: "authorized",
      paymentMethodSummary: paymentSummary,
      currency: (requestData.currency ?? "ZAR").toString(),
      pricing,
      tutorRatePerMinute: pricing.tutorRatePerMinute,
      platformFeePerMinute: pricing.platformFeePerMinute,
      totalRatePerMinute: pricing.totalRatePerMinute,
      holdAuthorizedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    tx.set(requestRef, {
      paymentStatus: "hold_authorized",
      holdAmountZar: holdAmount,
      paymentIntentId,
      paymentModel: CARD_MODEL,
      paymentMethodSummary: paymentSummary,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    const authTxRef = studentRef.collection("payment_transactions").doc();
    tx.set(authTxRef, {
      type: "session_authorization",
      direction: "hold",
      status: "authorized",
      requestId,
      paymentIntentId,
      paymentModel: CARD_MODEL,
      paymentMethodSummary: paymentSummary,
      amountZar: holdAmount,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
}

async function releaseHoldForRequest(
  requestId: string,
  requestData: Record<string, unknown>,
  reason: string
): Promise<void> {
  const paymentIntentId = (requestData.paymentIntentId ?? requestId).toString();
  const studentId = (requestData.studentId ?? "").toString();
  if (!studentId) return;

  const requestRef = db.collection("tutor_requests").doc(requestId);
  const intentRef = db.collection("session_payment_intents").doc(paymentIntentId);
  const studentRef = db.collection("users").doc(studentId);

  await db.runTransaction(async (tx) => {
    const intentSnap = await tx.get(intentRef);
    if (!intentSnap.exists) return;
    const intentData = intentSnap.data() ?? {};
    const paymentModel = paymentModelFrom({
      ...requestData,
      ...intentData,
    });

    if (paymentModel === LEGACY_WALLET_MODEL) {
      const studentSnap = await tx.get(studentRef);
      if (!studentSnap.exists) return;
      const studentData = studentSnap.data() ?? {};
      const holdRemainingRaw = asNumber(
        intentData.holdRemainingZar,
        asNumber(intentData.holdAmountZar, 0)
      );
      const studentHold = asNumber(studentData.walletHoldZar, 0);
      const holdToRelease = toMoney(Math.min(holdRemainingRaw, studentHold));
      if (holdToRelease <= 0) {
        tx.set(intentRef, {
          holdStatus: "released",
          holdRemainingZar: 0,
          status: "cancelled",
          settlementStatus: "cancelled",
          releaseReason: reason,
          releasedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
        return;
      }

      tx.set(studentRef, {
        walletBalanceZar: admin.firestore.FieldValue.increment(holdToRelease),
        walletHoldZar: admin.firestore.FieldValue.increment(-holdToRelease),
        walletUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      tx.set(intentRef, {
        holdStatus: "released",
        holdRemainingZar: 0,
        releasedAmountZar: holdToRelease,
        status: "cancelled",
        settlementStatus: "cancelled",
        releaseReason: reason,
        releasedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      tx.set(requestRef, {
        paymentStatus: "hold_released",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      const releaseTxRef = studentRef.collection("wallet_transactions").doc();
      tx.set(releaseTxRef, {
        type: "session_hold_release",
        direction: "credit",
        status: "completed",
        requestId,
        paymentIntentId,
        amountZar: holdToRelease,
        reason,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    const holdToRelease = toMoney(
      asNumber(intentData.holdRemainingZar, asNumber(intentData.holdAmountZar, 0))
    );
    tx.set(intentRef, {
      holdStatus: "released",
      holdRemainingZar: 0,
      releasedAmountZar: holdToRelease,
      status: "cancelled",
      settlementStatus: "cancelled",
      releaseReason: reason,
      releasedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    tx.set(requestRef, {
      paymentStatus: "hold_released",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    const releaseTxRef = studentRef.collection("payment_transactions").doc();
    tx.set(releaseTxRef, {
      type: "session_authorization_release",
      direction: "release",
      status: "completed",
      requestId,
      paymentIntentId,
      paymentModel: CARD_MODEL,
      amountZar: holdToRelease,
      reason,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
}

async function settlePaymentIntent(
  paymentIntentId: string,
  billableMinutesInput: number,
  actorUid?: string
): Promise<SettlementSummary> {
  const intentRef = db.collection("session_payment_intents").doc(paymentIntentId);

  return db.runTransaction(async (tx) => {
    const intentSnap = await tx.get(intentRef);
    if (!intentSnap.exists) {
      throw new HttpsError("not-found", "Payment intent not found.");
    }

    const intentData = intentSnap.data() ?? {};
    const requestId = (intentData.requestId ?? "").toString();
    const studentId = (intentData.studentId ?? "").toString();
    const tutorId = (intentData.tutorId ?? "").toString();
    if (!studentId || !tutorId || !requestId) {
      throw new HttpsError("failed-precondition", "Intent is missing key IDs.");
    }

    if (actorUid && actorUid !== studentId && actorUid !== tutorId) {
      throw new HttpsError(
        "permission-denied",
        "Only session participants can settle this intent."
      );
    }

    const settledStatus = (intentData.settlementStatus ?? "").toString();
    if (settledStatus === "completed" || settledStatus === "partial") {
      return {
        paymentIntentId,
        requestId,
        billableMinutes: asNumber(intentData.billableMinutes, 0),
        totalChargeZar: asNumber(intentData.chargeAmountZar, 0),
        capturedAmountZar: asNumber(intentData.capturedAmountZar, 0),
        tutorPayoutZar: asNumber(intentData.tutorPayoutZar, 0),
        platformRevenueZar: asNumber(intentData.platformRevenueZar, 0),
        settlementStatus: settledStatus,
      };
    }

    const pricing = pricingFrom(intentData);
    if (pricing.totalRatePerMinute <= 0) {
      throw new HttpsError("failed-precondition", "Invalid pricing.");
    }

    const billableMinutes = Math.max(
      1,
      Math.min(
        600,
        Math.round(asNumber(
          billableMinutesInput,
          asNumber(intentData.billableMinutes, 0)
        ))
      )
    );

    const grossCharge = toMoney(pricing.totalRatePerMinute * billableMinutes);
    const studentRef = db.collection("users").doc(studentId);
    const tutorRef = db.collection("users").doc(tutorId);
    const requestRef = db.collection("tutor_requests").doc(requestId);
    const outcomeRef = db.collection("tutor_session_outcomes").doc(paymentIntentId);
    const financeRef = db.collection("platform_finance").doc("overview");

    const studentSnap = await tx.get(studentRef);
    const tutorSnap = await tx.get(tutorRef);
    if (!studentSnap.exists || !tutorSnap.exists) {
      throw new HttpsError("failed-precondition", "User docs missing.");
    }

    const studentData = studentSnap.data() ?? {};
    const tutorData = tutorSnap.data() ?? {};
    const requestSnap = await tx.get(requestRef);
    const requestData = requestSnap.data() ?? {};
    const tutorProfile =
      (tutorData.tutorProfile as Record<string, unknown> | undefined) ?? {};
    const organizationMembership =
      (tutorData.organizationMembership as Record<string, unknown> | undefined) ?? {};
    const subject = (requestData.subject ?? intentData.subject ?? "Tutoring").toString();
    const topic = (requestData.topic ?? intentData.topic ?? "").toString();
    const tutorName =
      (requestData.tutorName ?? intentData.tutorName ?? tutorData.fullName ?? "Tutor").toString();
    const organizationId = (
      requestData.organizationId ??
      intentData.organizationId ??
      organizationMembership.organizationId ??
      tutorProfile.organizationId ??
      ""
    ).toString();
    const organizationName = (
      requestData.organizationName ??
      intentData.organizationName ??
      organizationMembership.organizationName ??
      tutorProfile.organizationName ??
      ""
    ).toString();
    const organizationLogoUrl = (
      requestData.organizationLogoUrl ??
      intentData.organizationLogoUrl ??
      organizationMembership.organizationLogoUrl ??
      ""
    ).toString();
    const organizationMemberTitle = (
      requestData.organizationMemberTitle ??
      intentData.organizationMemberTitle ??
      organizationMembership.memberTitle ??
      tutorProfile.organizationRole ??
      ""
    ).toString();
    const qualifiesForGoldTick = billableMinutes > 10;
    const paymentModel = paymentModelFrom(intentData);
    const organizationRef = organizationId ?
      db.collection("tutor_organizations").doc(organizationId) :
      null;
    const organizationMemberRef = organizationRef ?
      organizationRef.collection("members").doc(tutorId) :
      null;

    if (paymentModel === LEGACY_WALLET_MODEL) {
      const studentHold = asNumber(studentData.walletHoldZar, 0);
      const holdRemaining = asNumber(
        intentData.holdRemainingZar,
        asNumber(intentData.holdAmountZar, 0)
      );
      const holdAvailable = Math.min(studentHold, holdRemaining);
      const capturedFromHold = toMoney(Math.min(holdAvailable, grossCharge));

      const topUpNeeded = toMoney(grossCharge - capturedFromHold);
      const availableBalance = asNumber(studentData.walletBalanceZar, 0);
      const capturedFromBalance = toMoney(Math.min(topUpNeeded, availableBalance));
      const capturedTotal = toMoney(capturedFromHold + capturedFromBalance);
      if (capturedTotal <= 0) {
        throw new HttpsError("failed-precondition", "No funds available to settle.");
      }

      const releasedFromHold = toMoney(holdAvailable - capturedFromHold);
      const payoutRatio = Math.min(1, capturedTotal / grossCharge);
      const tutorPayout = toMoney(
        pricing.tutorRatePerMinute * billableMinutes * payoutRatio
      );
      const platformRevenue = toMoney(capturedTotal - tutorPayout);
      const settlementStatus = capturedTotal + 0.0001 >= grossCharge ?
        "completed" :
        "partial";

      tx.set(studentRef, {
        walletHoldZar: admin.firestore.FieldValue.increment(-holdAvailable),
        walletBalanceZar: admin.firestore.FieldValue.increment(
          releasedFromHold - capturedFromBalance
        ),
        walletSpentZar: admin.firestore.FieldValue.increment(capturedTotal),
        walletUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      tx.set(tutorRef, {
        "walletPayoutPendingZar": admin.firestore.FieldValue.increment(tutorPayout),
        "walletEarningsTotalZar": admin.firestore.FieldValue.increment(tutorPayout),
        "walletUpdatedAt": admin.firestore.FieldValue.serverTimestamp(),
        "tutorStats.totalEarnings": admin.firestore.FieldValue.increment(
          Math.round(tutorPayout)
        ),
        "tutorStats.sessionsCompleted": admin.firestore.FieldValue.increment(1),
        "tutorStats.minutesTutored": admin.firestore.FieldValue.increment(
          billableMinutes
        ),
      }, {merge: true});

      tx.set(financeRef, {
        grossVolumeZar: admin.firestore.FieldValue.increment(capturedTotal),
        platformRevenueZar: admin.firestore.FieldValue.increment(platformRevenue),
        tutorPayoutPendingZar: admin.firestore.FieldValue.increment(tutorPayout),
        settledSessions: admin.firestore.FieldValue.increment(1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      tx.set(intentRef, {
        status: settlementStatus === "completed" ? "settled" : "partially_settled",
        settlementStatus,
        holdStatus: releasedFromHold > 0 ? "captured_and_released" : "captured",
        reviewStatus: "pending",
        reviewEligible: true,
        goldTickQualifiedSession: qualifiesForGoldTick,
        tutorName,
        subject,
        topic,
        organizationId,
        organizationName,
        organizationLogoUrl,
        organizationMemberTitle,
        billableMinutes,
        chargeAmountZar: grossCharge,
        capturedAmountZar: capturedTotal,
        capturedFromHoldZar: capturedFromHold,
        capturedFromWalletZar: capturedFromBalance,
        releasedAmountZar: releasedFromHold,
        holdRemainingZar: 0,
        tutorPayoutZar: tutorPayout,
        platformRevenueZar: platformRevenue,
        settledAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      tx.set(requestRef, {
        status: settlementStatus === "completed" ? "completed" : "payment_partial",
        sessionState: settlementStatus === "completed" ? "settled" : "partial_settled",
        paymentStatus: settlementStatus,
        reviewStatus: "pending",
        reviewEligible: true,
        goldTickQualifiedSession: qualifiesForGoldTick,
        organizationId,
        organizationName,
        organizationLogoUrl,
        organizationMemberTitle,
        billableMinutes,
        chargeAmountZar: grossCharge,
        capturedAmountZar: capturedTotal,
        settledAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      tx.set(outcomeRef, {
        paymentIntentId,
        requestId,
        studentId,
        tutorId,
        tutorName,
        subject,
        topic,
        organizationId,
        organizationName,
        organizationLogoUrl,
        organizationMemberTitle,
        billableMinutes,
        qualifiesForGoldTick,
        settlementStatus,
        paymentModel,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      if (organizationRef && organizationMemberRef) {
        tx.set(organizationRef, {
          organizationId,
          name: organizationName,
          logoUrl: organizationLogoUrl,
          subjects: admin.firestore.FieldValue.arrayUnion(subject),
          totalSessionsCompleted: admin.firestore.FieldValue.increment(1),
          totalMinutesTutored: admin.firestore.FieldValue.increment(
            billableMinutes
          ),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
        tx.set(organizationMemberRef, {
          organizationId,
          organizationName,
          organizationLogoUrl,
          tutorId,
          name: tutorName,
          profilePic: (tutorData.profilePic ?? "").toString(),
          memberTitle: organizationMemberTitle,
          tutorStatus: (tutorData.tutorStatus ?? "").toString(),
          sessionsCompleted: admin.firestore.FieldValue.increment(1),
          qualifyingSessionCount: admin.firestore.FieldValue.increment(
            qualifiesForGoldTick ? 1 : 0
          ),
          minutesTutored: admin.firestore.FieldValue.increment(
            billableMinutes
          ),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
      }

      const studentTxRef = studentRef.collection("wallet_transactions").doc();
      tx.set(studentTxRef, {
        type: "session_settlement",
        direction: "debit",
        status: settlementStatus,
        paymentIntentId,
        requestId,
        billableMinutes,
        grossChargeZar: grossCharge,
        capturedAmountZar: capturedTotal,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      const tutorTxRef = tutorRef.collection("wallet_transactions").doc();
      tx.set(tutorTxRef, {
        type: "session_payout_pending",
        direction: "credit",
        status: settlementStatus,
        paymentIntentId,
        requestId,
        billableMinutes,
        payoutAmountZar: tutorPayout,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {
        paymentIntentId,
        requestId,
        billableMinutes,
        totalChargeZar: grossCharge,
        capturedAmountZar: capturedTotal,
        tutorPayoutZar: tutorPayout,
        platformRevenueZar: platformRevenue,
        settlementStatus,
      };
    }

    const tutorPayout = toMoney(pricing.tutorRatePerMinute * billableMinutes);
    const platformRevenue = toMoney(grossCharge - tutorPayout);
    const authorizedAmount = asNumber(intentData.holdAmountZar, grossCharge);
    const releasedAmount = toMoney(Math.max(authorizedAmount - grossCharge, 0));
    const paymentSummary = (intentData.paymentMethodSummary ?? "").toString();

    tx.set(studentRef, {
      billingSpendTotalZar: admin.firestore.FieldValue.increment(grossCharge),
      billingLastChargeAt: admin.firestore.FieldValue.serverTimestamp(),
      billingUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    tx.set(tutorRef, {
      "walletPayoutPendingZar": admin.firestore.FieldValue.increment(tutorPayout),
      "walletEarningsTotalZar": admin.firestore.FieldValue.increment(tutorPayout),
      "walletUpdatedAt": admin.firestore.FieldValue.serverTimestamp(),
      "tutorStats.totalEarnings": admin.firestore.FieldValue.increment(
        Math.round(tutorPayout)
      ),
      "tutorStats.sessionsCompleted": admin.firestore.FieldValue.increment(1),
      "tutorStats.minutesTutored": admin.firestore.FieldValue.increment(
        billableMinutes
      ),
    }, {merge: true});

    tx.set(financeRef, {
      grossVolumeZar: admin.firestore.FieldValue.increment(grossCharge),
      platformRevenueZar: admin.firestore.FieldValue.increment(platformRevenue),
      tutorPayoutPendingZar: admin.firestore.FieldValue.increment(tutorPayout),
      settledSessions: admin.firestore.FieldValue.increment(1),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    tx.set(intentRef, {
      status: "settled",
      settlementStatus: "completed",
      holdStatus: releasedAmount > 0 ? "captured_and_released" : "captured",
      reviewStatus: "pending",
      reviewEligible: true,
      goldTickQualifiedSession: qualifiesForGoldTick,
      tutorName,
      subject,
      topic,
      organizationId,
      organizationName,
      organizationLogoUrl,
      organizationMemberTitle,
      billableMinutes,
      chargeAmountZar: grossCharge,
      capturedAmountZar: grossCharge,
      capturedFromCardZar: grossCharge,
      releasedAmountZar: releasedAmount,
      holdRemainingZar: 0,
      tutorPayoutZar: tutorPayout,
      platformRevenueZar: platformRevenue,
      paymentModel: CARD_MODEL,
      paymentMethodSummary: paymentSummary,
      settledAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    tx.set(requestRef, {
      status: "completed",
      sessionState: "settled",
      paymentStatus: "completed",
      reviewStatus: "pending",
      reviewEligible: true,
      goldTickQualifiedSession: qualifiesForGoldTick,
      organizationId,
      organizationName,
      organizationLogoUrl,
      organizationMemberTitle,
      billableMinutes,
      chargeAmountZar: grossCharge,
      capturedAmountZar: grossCharge,
      paymentModel: CARD_MODEL,
      settledAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    tx.set(outcomeRef, {
      paymentIntentId,
      requestId,
      studentId,
      tutorId,
      tutorName,
      subject,
      topic,
      organizationId,
      organizationName,
      organizationLogoUrl,
      organizationMemberTitle,
      billableMinutes,
      qualifiesForGoldTick,
      settlementStatus: "completed",
      paymentModel: CARD_MODEL,
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    if (organizationRef && organizationMemberRef) {
      tx.set(organizationRef, {
        organizationId,
        name: organizationName,
        logoUrl: organizationLogoUrl,
        subjects: admin.firestore.FieldValue.arrayUnion(subject),
        totalSessionsCompleted: admin.firestore.FieldValue.increment(1),
        totalMinutesTutored: admin.firestore.FieldValue.increment(
          billableMinutes
        ),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      tx.set(organizationMemberRef, {
        organizationId,
        organizationName,
        organizationLogoUrl,
        tutorId,
        name: tutorName,
        profilePic: (tutorData.profilePic ?? "").toString(),
        memberTitle: organizationMemberTitle,
        tutorStatus: (tutorData.tutorStatus ?? "").toString(),
        sessionsCompleted: admin.firestore.FieldValue.increment(1),
        qualifyingSessionCount: admin.firestore.FieldValue.increment(
          qualifiesForGoldTick ? 1 : 0
        ),
        minutesTutored: admin.firestore.FieldValue.increment(
          billableMinutes
        ),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    }

    const studentTxRef = studentRef.collection("payment_transactions").doc();
    tx.set(studentTxRef, {
      type: "session_capture",
      direction: "debit",
      status: "completed",
      paymentIntentId,
      requestId,
      billableMinutes,
      grossChargeZar: grossCharge,
      capturedAmountZar: grossCharge,
      paymentModel: CARD_MODEL,
      paymentMethodSummary: paymentSummary,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const tutorTxRef = tutorRef.collection("wallet_transactions").doc();
    tx.set(tutorTxRef, {
      type: "session_payout_pending",
      direction: "credit",
      status: "completed",
      paymentIntentId,
      requestId,
      billableMinutes,
      payoutAmountZar: tutorPayout,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      paymentIntentId,
      requestId,
      billableMinutes,
      totalChargeZar: grossCharge,
      capturedAmountZar: grossCharge,
      tutorPayoutZar: tutorPayout,
      platformRevenueZar: platformRevenue,
      settlementStatus: "completed",
    };
  });
}

export const ontutorrequestpaymentstate = onDocumentUpdated({
  document: "tutor_requests/{requestId}",
  region: REGION,
}, async (event) => {
  const before = event.data?.before.data() ?? {};
  const after = event.data?.after.data() ?? {};
  const beforeStatus = (before.status ?? "").toString();
  const afterStatus = (after.status ?? "").toString();
  if (beforeStatus === afterStatus) return;

  const requestId = (event.params.requestId ?? "").toString();
  if (!requestId) return;

  if (afterStatus === "accepted") {
    await authorizeHoldForAcceptedRequest(
      requestId,
      after as Record<string, unknown>
    );
    return;
  }

  if (["declined", "cancelled", "expired"].includes(afterStatus)) {
    await releaseHoldForRequest(
      requestId,
      after as Record<string, unknown>,
      `request_${afterStatus}`
    );
  }
});

export const onsessionpaymentintentupdated = onDocumentUpdated({
  document: "session_payment_intents/{paymentIntentId}",
  region: REGION,
}, async (event) => {
  const before = event.data?.before.data() ?? {};
  const after = event.data?.after.data() ?? {};
  const beforeStatus = (before.settlementStatus ?? "").toString();
  const afterStatus = (after.settlementStatus ?? "").toString();
  if (beforeStatus === afterStatus) return;
  if (afterStatus !== "ready") return;

  const paymentIntentId = (event.params.paymentIntentId ?? "").toString();
  if (!paymentIntentId) return;
  const minutes = asNumber(after.billableMinutes, 0);
  await settlePaymentIntent(paymentIntentId, minutes);
});

export const settletutorsession = onCall({region: REGION}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be logged in.");
  }

  const paymentIntentId = (request.data?.paymentIntentId ?? "").toString().trim();
  const billableMinutes = asNumber(request.data?.billableMinutes, 0);
  if (!paymentIntentId) {
    throw new HttpsError("invalid-argument", "paymentIntentId is required.");
  }
  if (billableMinutes <= 0) {
    throw new HttpsError("invalid-argument", "billableMinutes must be > 0.");
  }

  return settlePaymentIntent(paymentIntentId, billableMinutes, request.auth.uid);
});
