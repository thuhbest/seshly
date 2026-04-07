import {onDocumentWritten} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";

const REGION = "europe-west1";

function toTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asNumber(value: unknown, fallback = 0): number {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return fallback;
}

function readStringList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => toTrimmedString(item))
    .filter((item) => item.length > 0);
}

function buildMembershipMirror(
  orgId: string,
  orgData: Record<string, unknown>,
  memberData: Record<string, unknown>
): Record<string, unknown> {
  return {
    organizationId: orgId,
    organizationName: toTrimmedString(orgData.name),
    organizationBio: toTrimmedString(orgData.bio),
    organizationLogoUrl: toTrimmedString(orgData.logoUrl),
    organizationWebsite: toTrimmedString(orgData.website),
    organizationSubjects: readStringList(orgData.subjects),
    organizationServices: readStringList(orgData.services),
    organizationRatingAverage10: asNumber(orgData.ratingAvg10, 0),
    organizationRatingCount: Math.round(asNumber(orgData.ratingCount, 0)),
    organizationGoldTickEligible: orgData.goldTickEligible === true,
    organizationSubscriptionStatus:
      toTrimmedString(orgData.subscriptionStatus) || "none",
    organizationPremiumFeaturesEnabled:
      orgData.premiumFeaturesEnabled === true,
    memberTutorCount: Math.round(asNumber(orgData.memberTutorCount, 0)),
    activeTutorCount: Math.round(asNumber(orgData.activeTutorCount, 0)),
    role: toTrimmedString(memberData.role) || "member",
    membershipStatus: toTrimmedString(memberData.status) || "active",
    approvalState: toTrimmedString(memberData.approvalState) || "approved",
    memberTitle: toTrimmedString(memberData.memberTitle),
    verificationStatus:
      toTrimmedString(orgData.verificationStatus) || "none",
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

async function recomputeOrganizationMembershipState(orgId: string): Promise<void> {
  if (!orgId) return;
  const db = admin.firestore();
  const orgRef = db.collection("tutor_organizations").doc(orgId);
  const orgSnap = await orgRef.get();
  if (!orgSnap.exists) return;
  const orgData = orgSnap.data() ?? {};

  const membersSnap = await orgRef.collection("members").get();
  const adminUserIds: string[] = [];
  let memberTutorCount = 0;
  let activeTutorCount = 0;

  const batch = db.batch();
  for (const memberDoc of membersSnap.docs) {
    const memberData = memberDoc.data() ?? {};
    const status = toTrimmedString(memberData.status);
    const approvalState = toTrimmedString(memberData.approvalState);
    const role = toTrimmedString(memberData.role);
    const userRef = db.collection("users").doc(memberDoc.id);

    if (status !== "removed") {
      memberTutorCount += 1;
    }
    if (status === "active" && approvalState === "approved") {
      activeTutorCount += 1;
      if (role === "owner" || role === "admin") {
        adminUserIds.push(memberDoc.id);
      }
      batch.set(userRef, {
        organizationMembership: buildMembershipMirror(orgId, orgData, memberData),
      }, {merge: true});
    } else {
      batch.set(userRef, {
        organizationMembership: admin.firestore.FieldValue.delete(),
      }, {merge: true});
    }
  }

  batch.set(orgRef, {
    adminUserIds,
    memberTutorCount,
    activeTutorCount,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  await batch.commit();
}

export const onorganizationmemberwritten = onDocumentWritten(
  {
    document: "tutor_organizations/{orgId}/members/{userId}",
    region: REGION,
  },
  async (event) => {
    const orgId = toTrimmedString(event.params.orgId);
    if (!orgId) return;
    await recomputeOrganizationMembershipState(orgId);
  }
);
