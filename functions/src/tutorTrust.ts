import {
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";

const db = admin.firestore();
const REGION = "europe-west1";
const GOLD_TICK_PRICE_ZAR = 30;
const GOLD_TICK_REQUIRED_RATING = 8;
const GOLD_TICK_REQUIRED_QUALIFYING_SESSIONS = 31;

function asNumber(value: unknown, fallback = 0): number {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return fallback;
}

function toOneDecimal(value: number): number {
  return Number(value.toFixed(1));
}

function timestampToDate(value: unknown): Date | null {
  if (value instanceof admin.firestore.Timestamp) return value.toDate();
  return null;
}

function readStringList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => (item ?? "").toString().trim())
    .filter((item) => item.length > 0);
}

function organizationIdFromProfile(profile: Record<string, unknown>): string {
  const existing = (profile.organizationId ?? "").toString().trim();
  if (existing) return existing;

  const tutorType = (profile.tutorType ?? "Individual").toString();
  const name = (profile.organizationName ?? "").toString().trim().toLowerCase();
  if (tutorType === "Individual" || !name) return "";

  const website = (profile.organizationWebsite ?? "")
    .toString()
    .trim()
    .toLowerCase()
    .replace(/^https?:\/\//, "")
    .replace(/^www\./, "")
    .split("/")[0];
  const seed = website || name;
  const slug = seed
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
  if (!slug) return "";
  return `org_${slug}`;
}

function organizationMembershipFromUser(
  userData: Record<string, unknown>
): Record<string, unknown> {
  return (userData.organizationMembership as Record<string, unknown> | undefined) ?? {};
}

function organizationIdFromUser(userData: Record<string, unknown>): string {
  const membership = organizationMembershipFromUser(userData);
  const membershipId = (membership.organizationId ?? "").toString().trim();
  if (membershipId) return membershipId;

  const tutorProfile =
    (userData.tutorProfile as Record<string, unknown> | undefined) ?? {};
  return organizationIdFromProfile(tutorProfile);
}

function buildEligibilityReason(args: {
  individualEligible: boolean;
  organizationEligible: boolean;
  ratingAverage10: number;
  qualifyingSessionCount: number;
  organizationRatingAverage10: number;
}): string {
  if (args.individualEligible) {
    return "Eligible through individual tutor quality performance.";
  }
  if (args.organizationEligible) {
    return "Eligible through organization quality performance.";
  }
  if (args.ratingAverage10 <= GOLD_TICK_REQUIRED_RATING) {
    return "Raise your tutor rating above 8/10 to unlock Gold Tick.";
  }
  if (args.qualifyingSessionCount < GOLD_TICK_REQUIRED_QUALIFYING_SESSIONS) {
    return "Complete more than 30 qualifying tutoring sessions to unlock Gold Tick.";
  }
  if (
    args.organizationRatingAverage10 > 0 &&
    args.organizationRatingAverage10 <= GOLD_TICK_REQUIRED_RATING
  ) {
    return "Your organization must stay above 8/10 before members can qualify through the organization path.";
  }
  return "Gold Tick stays locked until your quality track record reaches the required standard.";
}

function buildGoldTickMirror(
  userData: Record<string, unknown>,
  orgData: Record<string, unknown>,
  subscriptionData: Record<string, unknown>
): Record<string, unknown> {
  const tutorStats =
    (userData.tutorStats as Record<string, unknown> | undefined) ?? {};
  const membership = organizationMembershipFromUser(userData);
  const organizationId = organizationIdFromUser(userData);
  const membershipStatus = (membership.membershipStatus ?? "").toString();
  const approvalState = (membership.approvalState ?? "").toString();
  const organizationMemberActive =
    organizationId.length > 0 &&
    membershipStatus === "active" &&
    approvalState === "approved";

  const ratingAverage10 = toOneDecimal(asNumber(tutorStats.ratingAvg, 0));
  const ratingCount = Math.max(0, Math.round(asNumber(tutorStats.ratingCount, 0)));
  const qualifyingSessionCount = Math.max(
    0,
    Math.round(
      asNumber(
        tutorStats.qualifyingSessionCount,
        asNumber(tutorStats.sessionsCompleted, 0)
      )
    )
  );
  const organizationRatingAverage10 = toOneDecimal(
    asNumber(orgData.ratingAvg10, 0)
  );
  const organizationRatingCount = Math.max(
    0,
    Math.round(asNumber(orgData.ratingCount, 0))
  );
  const organizationEligible =
    organizationMemberActive &&
    organizationRatingAverage10 > GOLD_TICK_REQUIRED_RATING;
  const memberQualificationStatus = organizationMemberActive ?
    (organizationEligible ? "auto_qualified" : "org_quality_not_met") :
    (organizationId ? "membership_not_active" : "");

  const individualEligible =
    ratingAverage10 > GOLD_TICK_REQUIRED_RATING &&
    qualifyingSessionCount >= GOLD_TICK_REQUIRED_QUALIFYING_SESSIONS;
  const organizationPathEligible =
    organizationEligible && memberQualificationStatus === "auto_qualified";

  const eligibilityStatus =
    individualEligible || organizationPathEligible ? "eligible" : "ineligible";
  const eligibilityPath = individualEligible ?
    "individual" :
    (organizationPathEligible ? "organization" : "none");
  const eligibilityReason = buildEligibilityReason({
    individualEligible,
    organizationEligible: organizationPathEligible,
    ratingAverage10,
    qualifyingSessionCount,
    organizationRatingAverage10,
  });

  const periodEnd = timestampToDate(subscriptionData.currentPeriodEnd);
  let subscriptionStatus = (subscriptionData.status ?? "").toString().trim() || "none";
  if (subscriptionStatus === "active") {
    if (periodEnd && periodEnd.getTime() <= Date.now()) {
      subscriptionStatus = "expired";
    } else if (eligibilityStatus !== "eligible") {
      subscriptionStatus = "suspended_ineligible";
    }
  }

  const activeBadge =
    subscriptionStatus === "active" && eligibilityStatus === "eligible";

  return {
    priceZar: GOLD_TICK_PRICE_ZAR,
    currency: "ZAR",
    eligibilityStatus,
    eligibilityPath,
    eligibilityReason,
    ratingAverage10,
    ratingCount,
    qualifyingSessionCount,
    organizationId,
    organizationEligible,
    organizationRatingAverage10,
    organizationRatingCount,
    memberQualificationStatus,
    subscriptionStatus,
    currentPeriodStart: subscriptionData.currentPeriodStart ?? null,
    currentPeriodEnd: subscriptionData.currentPeriodEnd ?? null,
    badgeVisible: activeBadge,
    rankingBoostEnabled: activeBadge,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

function buildOrganizationMembershipMirror(
  orgId: string,
  orgData: Record<string, unknown>,
  memberData: Record<string, unknown>
): Record<string, unknown> {
  return {
    organizationId: orgId,
    organizationName: (orgData.name ?? "").toString(),
    organizationBio: (orgData.bio ?? "").toString(),
    organizationLogoUrl: (orgData.logoUrl ?? "").toString(),
    organizationWebsite: (orgData.website ?? "").toString(),
    organizationSubjects: readStringList(orgData.subjects),
    organizationServices: readStringList(orgData.services),
    organizationRatingAverage10: asNumber(orgData.ratingAvg10, 0),
    organizationRatingCount: Math.round(asNumber(orgData.ratingCount, 0)),
    organizationGoldTickEligible: orgData.goldTickEligible === true,
    organizationSubscriptionStatus: (orgData.subscriptionStatus ?? "none").toString(),
    organizationPremiumFeaturesEnabled: orgData.premiumFeaturesEnabled === true,
    memberTutorCount: Math.round(asNumber(orgData.memberTutorCount, 0)),
    activeTutorCount: Math.round(asNumber(orgData.activeTutorCount, 0)),
    role: (memberData.role ?? "member").toString(),
    membershipStatus: (memberData.status ?? "active").toString(),
    approvalState: (memberData.approvalState ?? "approved").toString(),
    memberTitle: (memberData.memberTitle ?? "").toString(),
    verificationStatus: (orgData.verificationStatus ?? "none").toString(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

async function recalculateOrganizationQuality(orgId: string): Promise<void> {
  if (!orgId) return;
  const orgRef = db.collection("tutor_organizations").doc(orgId);
  const membersSnap = await orgRef.collection("members").get();

  let memberTutorCount = 0;
  let activeTutorCount = 0;
  let ratedTutorCount = 0;
  let goldTickTutorCount = 0;
  let derivedRatingTotal = 0;

  for (const doc of membersSnap.docs) {
    const data = doc.data() ?? {};
    const status = (data.status ?? "").toString();
    const approvalState = (data.approvalState ?? "").toString();
    if (status !== "removed") {
      memberTutorCount += 1;
    }
    if (status === "active" && approvalState === "approved") {
      activeTutorCount += 1;
      const ratingCount = Math.max(0, Math.round(asNumber(data.ratingCount, 0)));
      const ratingAverage10 = toOneDecimal(asNumber(data.ratingAvg10, 0));
      if (ratingCount > 0 && ratingAverage10 > 0) {
        ratedTutorCount += 1;
        derivedRatingTotal += ratingAverage10;
      }
      if (data.goldTickActive === true) {
        goldTickTutorCount += 1;
      }
    }
  }

  const derivedRatingAverage10 = ratedTutorCount > 0 ?
    toOneDecimal(derivedRatingTotal / ratedTutorCount) :
    0;

  await orgRef.set({
    ratingAvg10: derivedRatingAverage10,
    ratingCount: ratedTutorCount,
    ratingTotal10: toOneDecimal(derivedRatingTotal),
    goldTickEligible: derivedRatingAverage10 > GOLD_TICK_REQUIRED_RATING,
    memberTutorCount,
    activeTutorCount,
    goldTickTutorCount,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
}

async function syncOrganizationSubscriptionMirror(orgId: string): Promise<void> {
  if (!orgId) return;
  const orgRef = db.collection("tutor_organizations").doc(orgId);
  const subscriptionSnap = await db
    .collection("organization_subscriptions")
    .doc(orgId)
    .get();

  if (!subscriptionSnap.exists) {
    await orgRef.set({
      subscriptionProductName: "Organization Account",
      subscriptionPriceZar: 250,
      subscriptionCurrency: "ZAR",
      subscriptionBillingPeriod: "monthly",
      subscriptionStatus: "none",
      premiumFeaturesEnabled: false,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    await syncOrganizationMemberSnapshots(orgId);
    return;
  }

  const data = subscriptionSnap.data() ?? {};
  await orgRef.set({
    billingOwnerUserId: (data.billingOwnerUserId ?? "").toString(),
    subscriptionProductName: (data.productName ?? "Organization Account").toString(),
    subscriptionPriceZar: Math.round(asNumber(data.priceZar, 250)),
    subscriptionCurrency: (data.currency ?? "ZAR").toString(),
    subscriptionBillingPeriod: (data.billingPeriod ?? "monthly").toString(),
    subscriptionStatus: (data.status ?? "none").toString(),
    subscriptionPaymentMethodSummary: (data.paymentMethodSummary ?? "").toString(),
    subscriptionCurrentPeriodStart: data.currentPeriodStart ?? null,
    subscriptionCurrentPeriodEnd: data.currentPeriodEnd ?? null,
    premiumFeaturesEnabled: (data.status ?? "").toString() == "active",
    brandingUnlocked: (data.status ?? "").toString() == "active",
    analyticsDashboardEnabled: (data.status ?? "").toString() == "active",
    memberManagementEnabled: (data.status ?? "").toString() == "active",
    futurePayoutControlsEnabled: (data.status ?? "").toString() == "active",
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
  await syncOrganizationMemberSnapshots(orgId);
}

async function syncTutorGoldTickSnapshot(tutorId: string): Promise<void> {
  if (!tutorId) return;
  const tutorRef = db.collection("users").doc(tutorId);
  const tutorSnap = await tutorRef.get();
  if (!tutorSnap.exists) return;

  const userData = tutorSnap.data() ?? {};
  const organizationId = organizationIdFromUser(userData);
  const orgData = organizationId ?
    (await db.collection("tutor_organizations").doc(organizationId).get()).data() ?? {} :
    {};
  const subscriptionRef = db.collection("gold_tick_subscriptions").doc(tutorId);
  const subscriptionSnap = await subscriptionRef.get();
  const subscriptionData = subscriptionSnap.data() ?? {};
  const mirror = buildGoldTickMirror(userData, orgData, subscriptionData);
  const membership = organizationMembershipFromUser(userData);
  const batch = db.batch();

  const userUpdate: Record<string, unknown> = {
    goldTick: mirror,
  };
  if (organizationId && Object.keys(orgData).length > 0 && membership.organizationId) {
    userUpdate.organizationMembership = buildOrganizationMembershipMirror(
      organizationId,
      orgData,
      membership
    );
  }
  batch.set(tutorRef, userUpdate, {merge: true});

  if (subscriptionSnap.exists) {
    const nextStatus = (mirror.subscriptionStatus ?? "none").toString();
    if ((subscriptionData.status ?? "").toString() !== nextStatus) {
      batch.set(subscriptionRef, {
        status: nextStatus,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    }
  }

  await batch.commit();
}

async function syncOrganizationMemberSnapshots(orgId: string): Promise<void> {
  if (!orgId) return;
  const orgRef = db.collection("tutor_organizations").doc(orgId);
  const orgSnap = await orgRef.get();
  if (!orgSnap.exists) return;
  const orgData = orgSnap.data() ?? {};

  const memberSnap = await orgRef
    .collection("members")
    .where("status", "==", "active")
    .where("approvalState", "==", "approved")
    .get();

  for (const memberDoc of memberSnap.docs) {
    const tutorId = memberDoc.id;
    const userRef = db.collection("users").doc(tutorId);
    await syncTutorGoldTickSnapshot(tutorId);

    const userSnap = await userRef.get();
    if (!userSnap.exists) continue;
    const userData = userSnap.data() ?? {};
    const tutorStats =
      (userData.tutorStats as Record<string, unknown> | undefined) ?? {};
    const goldTick =
      (userData.goldTick as Record<string, unknown> | undefined) ?? {};
    const tutorProfile =
      (userData.tutorProfile as Record<string, unknown> | undefined) ?? {};
    const memberData = memberDoc.data() ?? {};
    const subjects = [
      ...readStringList(tutorProfile.mainSubjects),
      ...readStringList(tutorProfile.minorSubjects),
      ...readStringList(userData.tutorSubjects),
    ].filter((value, index, list) => list.indexOf(value) === index);

    const batch = db.batch();
    batch.set(memberDoc.ref, {
      organizationId: orgId,
      organizationName: (orgData.name ?? "").toString(),
      organizationLogoUrl: (orgData.logoUrl ?? "").toString(),
      tutorId,
      name:
        (userData.fullName ?? userData.displayName ?? memberData.name ?? "Tutor").toString(),
      email: (userData.email ?? memberData.email ?? "").toString(),
      profilePic: (userData.profilePic ?? memberData.profilePic ?? "").toString(),
      role: (memberData.role ?? "member").toString(),
      status: (memberData.status ?? "active").toString(),
      approvalState: (memberData.approvalState ?? "approved").toString(),
      memberTitle: (memberData.memberTitle ?? "").toString(),
      subjects,
      ratingAvg10: toOneDecimal(asNumber(tutorStats.ratingAvg, 0)),
      ratingCount: Math.round(asNumber(tutorStats.ratingCount, 0)),
      sessionsCompleted: Math.round(asNumber(tutorStats.sessionsCompleted, 0)),
      qualifyingSessionCount: Math.round(
        asNumber(
          tutorStats.qualifyingSessionCount,
          asNumber(tutorStats.sessionsCompleted, 0)
        )
      ),
      goldTickActive: goldTick.badgeVisible === true,
      tutorStatus: (userData.tutorStatus ?? "").toString(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    await batch.commit();
  }

  await recalculateOrganizationQuality(orgId);

  const refreshedOrgSnap = await orgRef.get();
  const refreshedOrgData = refreshedOrgSnap.data() ?? orgData;
  if (memberSnap.empty) return;

  const mirrorBatch = db.batch();
  for (const memberDoc of memberSnap.docs) {
    const memberData = memberDoc.data() ?? {};
    mirrorBatch.set(db.collection("users").doc(memberDoc.id), {
      organizationMembership: buildOrganizationMembershipMirror(
        orgId,
        refreshedOrgData,
        memberData
      ),
    }, {merge: true});
  }
  await mirrorBatch.commit();
}

export const ontutorsessionoutcomecreated = onDocumentCreated({
  document: "tutor_session_outcomes/{outcomeId}",
  region: REGION,
}, async (event) => {
  const snap = event.data;
  if (!snap) return;
  const data = snap.data() ?? {};
  const tutorId = (data.tutorId ?? "").toString();
  const organizationId = (data.organizationId ?? "").toString();
  if (!tutorId) return;

  if (data.qualifiesForGoldTick === true) {
    await db.collection("users").doc(tutorId).set({
      "tutorStats.qualifyingSessionCount":
        admin.firestore.FieldValue.increment(1),
    }, {merge: true});
  }

  await syncTutorGoldTickSnapshot(tutorId);
  if (organizationId) {
    await syncOrganizationMemberSnapshots(organizationId);
  }
});

export const ontutorsessionreviewcreated = onDocumentCreated({
  document: "tutor_session_reviews/{reviewId}",
  region: REGION,
}, async (event) => {
  const snap = event.data;
  if (!snap) return;
  const data = snap.data() ?? {};
  const reviewId = (event.params.reviewId ?? "").toString();
  const paymentIntentId = (data.paymentIntentId ?? reviewId).toString();
  const tutorId = (data.tutorId ?? "").toString();
  const requestId = (data.requestId ?? "").toString();
  const organizationId = (data.organizationId ?? "").toString();
  const rating10 = toOneDecimal(asNumber(data.rating10, 0));
  if (!tutorId || rating10 <= 0) return;

  const tutorRef = db.collection("users").doc(tutorId);
  const searchProfileRef = db.collection("tutor_search_profiles").doc(tutorId);
  const intentRef = db.collection("session_payment_intents").doc(paymentIntentId);
  const requestRef = requestId ?
    db.collection("tutor_requests").doc(requestId) :
    null;
  const orgMemberRef = organizationId ?
    db.collection("tutor_organizations").doc(organizationId).collection("members").doc(tutorId) :
    null;

  await db.runTransaction(async (tx) => {
    const tutorSnap = await tx.get(tutorRef);
    if (!tutorSnap.exists) return;
    const tutorData = tutorSnap.data() ?? {};
    const tutorStats =
      (tutorData.tutorStats as Record<string, unknown> | undefined) ?? {};
    const oldCount = Math.max(0, Math.round(asNumber(tutorStats.ratingCount, 0)));
    const oldTotal = asNumber(
      tutorStats.ratingTotal10,
      asNumber(tutorStats.ratingAvg, 0) * oldCount
    );
    const nextCount = oldCount + 1;
    const nextTotal = oldTotal + rating10;
    const nextAverage = toOneDecimal(nextTotal / nextCount);

    tx.set(tutorRef, {
      "tutorStats.ratingTotal10": nextTotal,
      "tutorStats.ratingCount": nextCount,
      "tutorStats.ratingAvg": nextAverage,
      "tutorStats.ratedSessionCount": nextCount,
      "tutorStats.lastReviewAt": admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    tx.set(searchProfileRef, {
      ratingAvg: nextAverage,
      ratingCount: nextCount,
      tutoringReviewCount: nextCount,
      lastReviewAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    tx.set(intentRef, {
      reviewStatus: "submitted",
      reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    if (requestRef) {
      tx.set(requestRef, {
        reviewStatus: "submitted",
        reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    }

    if (orgMemberRef) {
      tx.set(orgMemberRef, {
        ratingAvg10: nextAverage,
        ratingCount: nextCount,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    }
  });

  await syncTutorGoldTickSnapshot(tutorId);
  if (organizationId) {
    await syncOrganizationMemberSnapshots(organizationId);
  }
});

export const ongoldticksubscriptioncreated = onDocumentCreated({
  document: "gold_tick_subscriptions/{tutorId}",
  region: REGION,
}, async (event) => {
  const tutorId = (event.params.tutorId ?? "").toString();
  if (!tutorId) return;
  await syncTutorGoldTickSnapshot(tutorId);
});

export const ongoldticksubscriptionupdated = onDocumentUpdated({
  document: "gold_tick_subscriptions/{tutorId}",
  region: REGION,
}, async (event) => {
  const tutorId = (event.params.tutorId ?? "").toString();
  if (!tutorId) return;
  await syncTutorGoldTickSnapshot(tutorId);
});

export const onorganizationsubscriptioncreated = onDocumentCreated({
  document: "organization_subscriptions/{orgId}",
  region: REGION,
}, async (event) => {
  const orgId = (event.params.orgId ?? "").toString();
  if (!orgId) return;
  await syncOrganizationSubscriptionMirror(orgId);
});

export const onorganizationsubscriptionupdated = onDocumentUpdated({
  document: "organization_subscriptions/{orgId}",
  region: REGION,
}, async (event) => {
  const orgId = (event.params.orgId ?? "").toString();
  if (!orgId) return;
  await syncOrganizationSubscriptionMirror(orgId);
});

export const ontutororganizationupdated = onDocumentUpdated({
  document: "tutor_organizations/{orgId}",
  region: REGION,
}, async (event) => {
  const orgId = (event.params.orgId ?? "").toString();
  if (!orgId) return;

  const before = event.data?.before.data() ?? {};
  const after = event.data?.after.data() ?? {};
  const relevantBefore = JSON.stringify({
    name: before.name ?? "",
    bio: before.bio ?? "",
    logoUrl: before.logoUrl ?? "",
    website: before.website ?? "",
    subjects: before.subjects ?? [],
    services: before.services ?? [],
    ratingAvg10: before.ratingAvg10 ?? 0,
    ratingCount: before.ratingCount ?? 0,
    goldTickEligible: before.goldTickEligible ?? false,
    memberTutorCount: before.memberTutorCount ?? 0,
    activeTutorCount: before.activeTutorCount ?? 0,
    verificationStatus: before.verificationStatus ?? "none",
  });
  const relevantAfter = JSON.stringify({
    name: after.name ?? "",
    bio: after.bio ?? "",
    logoUrl: after.logoUrl ?? "",
    website: after.website ?? "",
    subjects: after.subjects ?? [],
    services: after.services ?? [],
    ratingAvg10: after.ratingAvg10 ?? 0,
    ratingCount: after.ratingCount ?? 0,
    goldTickEligible: after.goldTickEligible ?? false,
    memberTutorCount: after.memberTutorCount ?? 0,
    activeTutorCount: after.activeTutorCount ?? 0,
    verificationStatus: after.verificationStatus ?? "none",
  });
  if (relevantBefore === relevantAfter) return;

  await syncOrganizationMemberSnapshots(orgId);
});
