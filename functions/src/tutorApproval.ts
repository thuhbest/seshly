import * as admin from "firebase-admin";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {HttpsError, onCall} from "./callable";
import {
  type PayoutOnboardingStatus,
  type TutorApplicationStatus,
  buildLegacyTutorStatus,
  deriveTutorApprovalSnapshot,
  assertPlatformAdmin,
  isFullAccountTutor,
  toTrimmedString,
} from "./tutorApprovalState";
import {
  isBlockedTutorPayoutProfile,
  isVerifiedTutorPayoutProfile,
} from "./tutorPayoutProfileState";

const db = admin.firestore();
const REGION = "europe-west1";
const PLATFORM_MARKUP_MULTIPLIER = 1.2;

async function writeTutorAdminAuditLog(params: {
  action: string;
  actorUid: string;
  tutorId: string;
  result: TutorStatusMutationResult;
  metadata?: Record<string, unknown>;
}): Promise<void> {
  await db.collection("security_audit_logs").add({
    action: params.action,
    actorUid: params.actorUid,
    targetType: "tutor_approval",
    targetId: params.tutorId,
    status: "succeeded",
    result: params.result,
    metadata: params.metadata ?? {},
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}
const TUTOR_APPROVAL_NORMALIZATION_VERSION = 1;
const GUEST_TUTOR_REJECTION_REASON =
  "Tutor approval requires a full verified student account. Guest tutoring mode is student-only.";

type TutorEligibilityStatus = "ineligible" | "eligible" | "blocked";

interface SubmitTutorApplicationResult {
  tutorId: string;
  tutorApplicationStatus: TutorApplicationStatus;
  tutoringEligibilityStatus: string;
  payoutOnboardingStatus: PayoutOnboardingStatus;
  adminApproval: boolean;
  tutorStatus: string;
}

interface TutorStatusMutationResult extends SubmitTutorApplicationResult {}

interface SanitizedTutorApplicationPayload {
  mainSubjects: string[];
  minorSubjects: string[];
  baseRate: number;
  displayRate: number;
  targetAudience: string;
  highestLevel: string;
  tutorType: string;
  organizationId: string;
  organizationName: string;
  organizationRole: string;
  organizationWebsite: string;
  qualification: string;
  institution: string;
  fieldOfStudy: string;
  graduationYear: string;
  yearsExperience: string;
  studentsTaught: string;
  experienceSummary: string;
  languages: string[];
  location: string;
  availabilityDays: string[];
  availabilityWindow: string;
  teachingMode: string;
  idNumber: string;
  verificationLink: string;
  referenceContact: string;
  acceptFee: boolean;
  acceptConduct: boolean;
  confirmAccuracy: boolean;
  consentVerification: boolean;
}

function nowServerTs() {
  return admin.firestore.FieldValue.serverTimestamp();
}

function asPositiveMoney(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value) && value > 0) {
    return Math.round((value + Number.EPSILON) * 100) / 100;
  }
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed) && parsed > 0) {
      return Math.round((parsed + Number.EPSILON) * 100) / 100;
    }
  }
  return null;
}

function toJSONObject(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value) ?
    value as Record<string, unknown> :
    {};
}

function readStringList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((entry) => toTrimmedString(entry))
    .filter((entry, index, list) => entry.length > 0 && list.indexOf(entry) === index);
}

function readBool(value: unknown): boolean {
  return value === true;
}

function computeDisplayRate(baseRate: number): number {
  return Math.ceil(baseRate * PLATFORM_MARKUP_MULTIPLIER);
}

function deriveOrganizationId(params: {
  tutorType: string;
  organizationName: string;
  organizationWebsite: string;
}): string {
  if (params.tutorType.toLowerCase() === "individual") {
    return "";
  }
  const rawSeed = (
    params.organizationWebsite
      .toLowerCase()
      .replace(/^https?:\/\//, "")
      .replace(/^www\./, "")
      .split("/")[0] ||
    params.organizationName.toLowerCase()
  ).trim();
  if (!rawSeed) return "";
  const slug = rawSeed
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
  return slug ? `org_${slug}` : "";
}

function sanitizeTutorApplicationPayload(raw: Record<string, unknown>): SanitizedTutorApplicationPayload {
  const mainSubjects = readStringList(raw.mainSubjects).slice(0, 2);
  const minorSubjects = readStringList(raw.minorSubjects).slice(0, 2);
  if (mainSubjects.length === 0) {
    throw new HttpsError("invalid-argument", "At least one main subject is required.");
  }
  if (mainSubjects.length + minorSubjects.length > 4) {
    throw new HttpsError("invalid-argument", "A maximum of four subjects is allowed.");
  }

  const baseRate = asPositiveMoney(raw.baseRate);
  if (!baseRate) {
    throw new HttpsError("invalid-argument", "baseRate must be greater than zero.");
  }

  const highestLevel = toTrimmedString(raw.highestLevel);
  const qualification = toTrimmedString(raw.qualification);
  const institution = toTrimmedString(raw.institution);
  const yearsExperience = toTrimmedString(raw.yearsExperience);
  const languages = readStringList(raw.languages);
  const availabilityDays = readStringList(raw.availabilityDays);
  const availabilityWindow = toTrimmedString(raw.availabilityWindow);
  if (!highestLevel || !qualification || !institution || !yearsExperience) {
    throw new HttpsError(
      "invalid-argument",
      "highestLevel, qualification, institution, and yearsExperience are required."
    );
  }
  if (languages.length === 0) {
    throw new HttpsError("invalid-argument", "At least one tutoring language is required.");
  }
  if (availabilityDays.length === 0 || !availabilityWindow) {
    throw new HttpsError("invalid-argument", "Availability days and window are required.");
  }
  if (!readBool(raw.acceptFee) || !readBool(raw.acceptConduct) || !readBool(raw.confirmAccuracy)) {
    throw new HttpsError(
      "invalid-argument",
      "Tutor agreements must be accepted before submission."
    );
  }

  const tutorType = toTrimmedString(raw.tutorType) || "Individual";
  const organizationName = toTrimmedString(raw.organizationName);
  const organizationWebsite = toTrimmedString(raw.organizationWebsite);

  return {
    mainSubjects,
    minorSubjects,
    baseRate,
    displayRate: computeDisplayRate(baseRate),
    targetAudience: toTrimmedString(raw.targetAudience) || "Varsity Students",
    highestLevel,
    tutorType,
    organizationId:
      toTrimmedString(raw.organizationId) ||
      deriveOrganizationId({
        tutorType,
        organizationName,
        organizationWebsite,
      }),
    organizationName,
    organizationRole: toTrimmedString(raw.organizationRole),
    organizationWebsite,
    qualification,
    institution,
    fieldOfStudy: toTrimmedString(raw.fieldOfStudy),
    graduationYear: toTrimmedString(raw.graduationYear),
    yearsExperience,
    studentsTaught: toTrimmedString(raw.studentsTaught),
    experienceSummary: toTrimmedString(raw.experienceSummary),
    languages,
    location: toTrimmedString(raw.location),
    availabilityDays,
    availabilityWindow,
    teachingMode: toTrimmedString(raw.teachingMode) || "Online",
    idNumber: toTrimmedString(raw.idNumber),
    verificationLink: toTrimmedString(raw.verificationLink),
    referenceContact: toTrimmedString(raw.referenceContact),
    acceptFee: readBool(raw.acceptFee),
    acceptConduct: readBool(raw.acceptConduct),
    confirmAccuracy: readBool(raw.confirmAccuracy),
    consentVerification: readBool(raw.consentVerification),
  };
}

function existingApplicationData(
  userId: string,
  userData: Record<string, unknown>,
  applicationData: Record<string, unknown>
): Record<string, unknown> {
  if (Object.keys(applicationData).length > 0) {
    return applicationData;
  }
  const profile = toJSONObject(userData.tutorProfile);
  return Object.keys(profile).length > 0 ?
    {
      userId,
      ...profile,
    } :
    {};
}

function buildApplicationProfileFields(
  payload: SanitizedTutorApplicationPayload,
  userId: string,
  userData: Record<string, unknown>
): Record<string, unknown> {
  const fullName =
    toTrimmedString(userData.fullName) ||
    toTrimmedString(userData.displayName) ||
    "Tutor";
  return {
    userId,
    fullName,
    email: toTrimmedString(userData.email),
    mainSubjects: payload.mainSubjects,
    minorSubjects: payload.minorSubjects,
    baseRate: payload.baseRate,
    displayRate: payload.displayRate,
    targetAudience: payload.targetAudience,
    highestLevel: payload.highestLevel,
    tutorType: payload.tutorType,
    organizationId: payload.organizationId,
    organizationName: payload.organizationName,
    organizationRole: payload.organizationRole,
    organizationWebsite: payload.organizationWebsite,
    qualification: payload.qualification,
    institution: payload.institution,
    fieldOfStudy: payload.fieldOfStudy,
    graduationYear: payload.graduationYear,
    yearsExperience: payload.yearsExperience,
    studentsTaught: payload.studentsTaught,
    experienceSummary: payload.experienceSummary,
    languages: payload.languages,
    location: payload.location,
    availabilityDays: payload.availabilityDays,
    availabilityWindow: payload.availabilityWindow,
    teachingMode: payload.teachingMode,
    idNumber: payload.idNumber,
    verificationLink: payload.verificationLink,
    referenceContact: payload.referenceContact,
    acceptFee: payload.acceptFee,
    acceptConduct: payload.acceptConduct,
    confirmAccuracy: payload.confirmAccuracy,
    consentVerification: payload.consentVerification,
  };
}

function buildTutorProfileMirror(
  existingUserData: Record<string, unknown>,
  applicationFields: Record<string, unknown>,
  tutorStatus: string,
  tutorApplicationStatus: TutorApplicationStatus,
  tutoringEligibilityStatus: string,
  payoutOnboardingStatus: PayoutOnboardingStatus
): Record<string, unknown> {
  const existingProfile = toJSONObject(existingUserData.tutorProfile);
  return {
    ...existingProfile,
    mainSubjects: applicationFields.mainSubjects ?? existingProfile.mainSubjects ?? [],
    minorSubjects: applicationFields.minorSubjects ?? existingProfile.minorSubjects ?? [],
    baseRate: applicationFields.baseRate ?? existingProfile.baseRate ?? 0,
    displayRate: applicationFields.displayRate ?? existingProfile.displayRate ?? 0,
    targetAudience: applicationFields.targetAudience ?? existingProfile.targetAudience ?? "Varsity Students",
    highestLevel: applicationFields.highestLevel ?? existingProfile.highestLevel ?? "",
    tutorType: applicationFields.tutorType ?? existingProfile.tutorType ?? "Individual",
    organizationId: applicationFields.organizationId ?? existingProfile.organizationId ?? "",
    organizationName: applicationFields.organizationName ?? existingProfile.organizationName ?? "",
    organizationRole: applicationFields.organizationRole ?? existingProfile.organizationRole ?? "",
    organizationWebsite:
      applicationFields.organizationWebsite ?? existingProfile.organizationWebsite ?? "",
    teachingMode: applicationFields.teachingMode ?? existingProfile.teachingMode ?? "Online",
    languages: applicationFields.languages ?? existingProfile.languages ?? [],
    location: applicationFields.location ?? existingProfile.location ?? "",
    availabilityDays: applicationFields.availabilityDays ?? existingProfile.availabilityDays ?? [],
    availabilityWindow:
      applicationFields.availabilityWindow ?? existingProfile.availabilityWindow ?? "",
    status: tutorStatus,
    tutorApplicationStatus,
    tutoringEligibilityStatus,
    payoutOnboardingStatus,
    adminApproval: tutorApplicationStatus === "approved" && tutoringEligibilityStatus === "eligible",
  };
}

function hasTutorSignals(params: {
  userData: Record<string, unknown>;
  applicationData: Record<string, unknown>;
  searchProfileExists?: boolean;
  payoutAccountCount?: number;
}): boolean {
  const tutorProfile = toJSONObject(params.userData.tutorProfile);
  const ecosystemProfile = toJSONObject(params.userData.ecosystemProfile);
  return Object.keys(params.applicationData).length > 0 ||
    Object.keys(tutorProfile).length > 0 ||
    readStringList(params.userData.tutorSubjects).length > 0 ||
    toTrimmedString(params.userData.tutorStatus).length > 0 ||
    toTrimmedString(params.userData.tutorApplicationStatus).length > 0 ||
    toTrimmedString(params.userData.tutoringEligibilityStatus).length > 0 ||
    toTrimmedString(params.userData.payoutOnboardingStatus).length > 0 ||
    params.userData.adminApproval === true ||
    ecosystemProfile.tutor === true ||
    params.searchProfileExists === true ||
    (params.payoutAccountCount ?? 0) > 0;
}

function deriveAutomaticPayoutOnboardingStatus(params: {
  tutorId: string;
  userData: Record<string, unknown>;
  tutorApplicationStatus: TutorApplicationStatus;
  tutoringEligibilityStatus: TutorEligibilityStatus;
  payoutAccounts: Record<string, unknown>[];
}): PayoutOnboardingStatus {
  const currentStatus = toTrimmedString(
    params.userData.payoutOnboardingStatus
  ).toLowerCase();
  const blocked =
    currentStatus === "blocked" ||
    params.userData.tutorPayoutsBlocked === true ||
    params.userData.payoutsBlocked === true ||
    params.userData.blockedFromPayouts === true ||
    params.tutorApplicationStatus === "suspended" ||
    params.tutoringEligibilityStatus === "blocked";
  if (blocked) {
    return "blocked";
  }

  const relatedAccounts = params.payoutAccounts.filter(
    (account) => toTrimmedString(account.tutorId) === params.tutorId
  );
  const hasAnyPayoutProfile = relatedAccounts.length > 0;
  const hasBlockedPayoutProfile = relatedAccounts.some((account) =>
    isBlockedTutorPayoutProfile(account)
  );
  const hasVerifiedPayoutProfile = relatedAccounts.some(
    (account) => isVerifiedTutorPayoutProfile(params.tutorId, account)
  );
  if (hasBlockedPayoutProfile) {
    return "blocked";
  }

  const approvedTutor =
    isFullAccountTutor(params.userData) &&
    params.tutorApplicationStatus === "approved" &&
    params.tutoringEligibilityStatus === "eligible" &&
    params.userData.isDisabled !== true;
  if (approvedTutor) {
    return hasVerifiedPayoutProfile ? "verified" : "pending";
  }

  return hasAnyPayoutProfile ? "pending" : "not_started";
}

function buildSearchVisibilityReason(params: {
  userData: Record<string, unknown>;
  tutorApplicationStatus: TutorApplicationStatus;
  tutoringEligibilityStatus: TutorEligibilityStatus;
  adminApproval: boolean;
  approvedForTutoring: boolean;
}): string {
  if (!isFullAccountTutor(params.userData)) {
    return "full_account_required";
  }
  if (params.userData.isDisabled === true) {
    return "disabled_tutor";
  }
  if (params.tutoringEligibilityStatus === "blocked" ||
      params.tutorApplicationStatus === "suspended") {
    return "blocked_tutor";
  }
  if (!params.adminApproval) {
    return `not_${params.tutorApplicationStatus}`;
  }
  if (!params.approvedForTutoring) {
    return `eligibility_${params.tutoringEligibilityStatus}`;
  }
  return "approved_visible";
}

interface DerivedTutorAuthorityState {
  adminApproval: boolean;
  approvedForTutoring: boolean;
  tutorStatus: string;
  tutorProfile: Record<string, unknown>;
  tutorSubjects: string[];
  ecosystemProfile: Record<string, unknown>;
  normalizedTutorAvailability: string;
  normalizedTutorRequestsEnabled: boolean;
  normalizedIsOnline: boolean;
  searchVisibilityReason: string;
}

function buildDerivedTutorAuthorityState(params: {
  tutorId: string;
  userData: Record<string, unknown>;
  applicationData: Record<string, unknown>;
  tutorApplicationStatus: TutorApplicationStatus;
  tutoringEligibilityStatus: TutorEligibilityStatus;
  payoutOnboardingStatus: PayoutOnboardingStatus;
}): DerivedTutorAuthorityState {
  const adminApproval =
    isFullAccountTutor(params.userData) &&
    params.tutorApplicationStatus === "approved" &&
    params.tutoringEligibilityStatus === "eligible";
  const approvedForTutoring = adminApproval && params.userData.isDisabled !== true;
  const tutorStatus = buildLegacyTutorStatus({
    tutorApplicationStatus: params.tutorApplicationStatus,
    tutoringEligibilityStatus: params.tutoringEligibilityStatus,
    adminApproval,
  });
  const tutorProfile = buildTutorProfileMirror(
    params.userData,
    params.applicationData,
    tutorStatus,
    params.tutorApplicationStatus,
    params.tutoringEligibilityStatus,
    params.payoutOnboardingStatus
  );
  const tutorSubjects = [
    ...readStringList(params.applicationData.mainSubjects),
    ...readStringList(params.applicationData.minorSubjects),
  ];
  const ecosystemProfile = {
    ...toJSONObject(params.userData.ecosystemProfile),
    tutor: adminApproval,
  };
  const normalizedTutorAvailability = approvedForTutoring ?
    (toTrimmedString(params.userData.tutorAvailability) || "offline") :
    "offline";
  const normalizedTutorRequestsEnabled =
    approvedForTutoring && params.userData.tutorRequestsEnabled === true;
  const normalizedIsOnline = approvedForTutoring && params.userData.isOnline === true;

  return {
    adminApproval,
    approvedForTutoring,
    tutorStatus,
    tutorProfile,
    tutorSubjects,
    ecosystemProfile,
    normalizedTutorAvailability,
    normalizedTutorRequestsEnabled,
    normalizedIsOnline,
    searchVisibilityReason: buildSearchVisibilityReason({
      userData: params.userData,
      tutorApplicationStatus: params.tutorApplicationStatus,
      tutoringEligibilityStatus: params.tutoringEligibilityStatus,
      adminApproval,
      approvedForTutoring,
    }),
  };
}

function computeSearchScore(params: {
  ratingAverage: number;
  ratingCount: number;
  sessionsCompleted: number;
  availability: string;
  isOnline: boolean;
  goldTickQualified: boolean;
}): number {
  let score = 0;
  score += Math.max(0, params.ratingAverage) * 10;
  score += Math.min(20, Math.max(0, params.ratingCount));
  score += Math.min(30, Math.max(0, params.sessionsCompleted));
  if (params.availability === "accepting") score += 8;
  else if (params.availability === "after_current") score += 3;
  if (params.isOnline) score += 5;
  if (params.goldTickQualified) score += 10;
  return Math.max(0, score);
}

function buildTutorSearchProfilePatch(params: {
  tutorId: string;
  userData: Record<string, unknown>;
  applicationData: Record<string, unknown>;
  tutorApplicationStatus: TutorApplicationStatus;
  tutoringEligibilityStatus: string;
  payoutOnboardingStatus: PayoutOnboardingStatus;
  adminApproval: boolean;
  approvedForTutoring: boolean;
}): Record<string, unknown> {
  const tutorStats = toJSONObject(params.userData.tutorStats);
  const organizationMembership = toJSONObject(params.userData.organizationMembership);
  const mainSubjects = readStringList(params.applicationData.mainSubjects);
  const minorSubjects = readStringList(params.applicationData.minorSubjects);
  const subjects = [...new Set([
    ...mainSubjects.map((item) => item.toLowerCase()),
    ...minorSubjects.map((item) => item.toLowerCase()),
  ])];
  const availability = params.approvedForTutoring ?
    (toTrimmedString(params.userData.tutorAvailability).toLowerCase() || "offline") :
    "offline";
  const isOnline = params.approvedForTutoring && params.userData.isOnline === true;
  const ratingAverage = Number(tutorStats.ratingAvg ?? 0);
  const ratingCount = Math.max(0, Number(tutorStats.ratingCount ?? 0));
  const completedSessions = Math.max(0, Number(tutorStats.sessionsCompleted ?? 0));
  const totalMinutesTaught = Math.max(0, Number(tutorStats.minutesTutored ?? 0));
  const goldTickQualified = toJSONObject(params.userData.goldTick).badgeVisible === true;
  const searchVisibilityReason = buildSearchVisibilityReason({
    userData: params.userData,
    tutorApplicationStatus: params.tutorApplicationStatus,
    tutoringEligibilityStatus: params.tutoringEligibilityStatus as TutorEligibilityStatus,
    adminApproval: params.adminApproval,
    approvedForTutoring: params.approvedForTutoring,
  });

  return {
    tutorId: params.tutorId,
    displayName:
      toTrimmedString(params.userData.fullName) ||
      toTrimmedString(params.userData.displayName) ||
      "Tutor",
    fullName:
      toTrimmedString(params.userData.fullName) ||
      toTrimmedString(params.userData.displayName) ||
      "Tutor",
    profilePic: toTrimmedString(params.userData.profilePic),
    organizationId:
      toTrimmedString(organizationMembership.organizationId) ||
      toTrimmedString(params.applicationData.organizationId),
    organizationName:
      toTrimmedString(organizationMembership.organizationName) ||
      toTrimmedString(params.applicationData.organizationName),
    mainSubjects,
    minorSubjects,
    subjects,
    baseRatePerMinuteZar: Number(params.applicationData.baseRate ?? 0),
    studentRatePerMinuteZar: Number(params.applicationData.displayRate ?? 0),
    availability,
    isOnline,
    isActive: params.approvedForTutoring,
    searchVisible: params.approvedForTutoring,
    tutoringSearchVisible: params.approvedForTutoring,
    tutoringSearchVisibilityReason: searchVisibilityReason,
    tutorApplicationStatus: params.tutorApplicationStatus,
    tutoringEligibilityStatus: params.tutoringEligibilityStatus,
    payoutOnboardingStatus: params.payoutOnboardingStatus,
    adminApproval: params.adminApproval,
    tutorRequestsEnabled:
      params.approvedForTutoring && params.userData.tutorRequestsEnabled === true,
    accountType: toTrimmedString(params.userData.accountType),
    accessTier: toTrimmedString(params.userData.accessTier),
    tutoringApprovalVersion: TUTOR_APPROVAL_NORMALIZATION_VERSION,
    tutoringApprovalNormalizedAt: nowServerTs(),
    ratingAverage,
    ratingCount,
    completedSessions,
    qualifyingSessionCount: Math.max(
      0,
      Number(tutorStats.qualifyingSessionCount ?? completedSessions)
    ),
    totalMinutesTaught,
    learnersHelped: Math.max(0, Number(tutorStats.learnersHelped ?? completedSessions)),
    totalEarningsZar: Math.max(0, Number(tutorStats.totalEarnings ?? 0)),
    goldTickQualified,
    organizationVerified:
      toTrimmedString(organizationMembership.verificationStatus).toLowerCase() === "verified",
    searchScore: computeSearchScore({
      ratingAverage,
      ratingCount,
      sessionsCompleted: completedSessions,
      availability,
      isOnline,
      goldTickQualified,
    }),
    updatedAt: nowServerTs(),
  };
}

function buildStatusResult(params: {
  tutorId: string;
  tutorApplicationStatus: TutorApplicationStatus;
  tutoringEligibilityStatus: string;
  payoutOnboardingStatus: PayoutOnboardingStatus;
  adminApproval: boolean;
}): TutorStatusMutationResult {
  return {
    tutorId: params.tutorId,
    tutorApplicationStatus: params.tutorApplicationStatus,
    tutoringEligibilityStatus: params.tutoringEligibilityStatus,
    payoutOnboardingStatus: params.payoutOnboardingStatus,
    adminApproval: params.adminApproval,
    tutorStatus: buildLegacyTutorStatus({
      tutorApplicationStatus: params.tutorApplicationStatus,
      tutoringEligibilityStatus: params.tutoringEligibilityStatus as
        "ineligible" | "eligible" | "blocked",
      adminApproval: params.adminApproval,
    }),
  };
}

function deriveNormalizedTutorApplicationStatusForBackfill(params: {
  userData: Record<string, unknown>;
  applicationData: Record<string, unknown>;
  currentTutorApplicationStatus: TutorApplicationStatus;
  currentTutoringEligibilityStatus: TutorEligibilityStatus;
}): TutorApplicationStatus {
  if (!isFullAccountTutor(params.userData)) {
    return hasTutorSignals({
      userData: params.userData,
      applicationData: params.applicationData,
    }) ?
      "rejected" :
      "draft";
  }
  if (params.currentTutoringEligibilityStatus === "blocked" &&
      params.currentTutorApplicationStatus !== "rejected") {
    return "suspended";
  }
  return params.currentTutorApplicationStatus;
}

function deriveNormalizedTutoringEligibilityStatus(params: {
  userData: Record<string, unknown>;
  tutorApplicationStatus: TutorApplicationStatus;
}): TutorEligibilityStatus {
  if (params.userData.isDisabled === true ||
      params.tutorApplicationStatus === "suspended") {
    return "blocked";
  }
  if (isFullAccountTutor(params.userData) &&
      params.tutorApplicationStatus === "approved") {
    return "eligible";
  }
  return "ineligible";
}

export const submitTutorApplication = onCall(
  {region: REGION},
  async (request): Promise<SubmitTutorApplicationResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }

    const tutorId = request.auth.uid;
    const userRef = db.collection("users").doc(tutorId);
    const applicationRef = db.collection("tutor_applications").doc(tutorId);
    const searchProfileRef = db.collection("tutor_search_profiles").doc(tutorId);
    const payload = sanitizeTutorApplicationPayload(
      toJSONObject(request.data)
    );

    return db.runTransaction(async (tx) => {
      const [userSnap, applicationSnap, payoutAccountsSnap] = await Promise.all([
        tx.get(userRef),
        tx.get(applicationRef),
        tx.get(
          db.collection("tutor_payout_accounts").where("tutorId", "==", tutorId)
        ),
      ]);
      if (!userSnap.exists) {
        throw new HttpsError("not-found", "Tutor user profile was not found.");
      }

      const userData = userSnap.data() ?? {};
      if (!isFullAccountTutor(userData)) {
        throw new HttpsError(
          "failed-precondition",
          "Tutor applications require a full verified account."
        );
      }

      const currentApplicationData = existingApplicationData(
        tutorId,
        userData,
        applicationSnap.data() ?? {}
      );
      const currentSnapshot = deriveTutorApprovalSnapshot({
        userData,
        applicationData: currentApplicationData,
      });

      const tutorApplicationStatus: TutorApplicationStatus =
        currentSnapshot.tutorApplicationStatus === "approved" ?
          "approved" :
          currentSnapshot.tutorApplicationStatus === "suspended" ?
            "suspended" :
            currentSnapshot.tutorApplicationStatus === "under_review" ?
              "under_review" :
              "submitted";
      const tutoringEligibilityStatus: TutorEligibilityStatus =
        tutorApplicationStatus === "approved" ?
          "eligible" :
          tutorApplicationStatus === "suspended" ?
            "blocked" :
            "ineligible";
      const applicationFields = buildApplicationProfileFields(
        payload,
        tutorId,
        userData
      );
      const payoutAccounts = payoutAccountsSnap.docs.map(
        (doc) => doc.data() ?? {}
      );
      const payoutOnboardingStatus = deriveAutomaticPayoutOnboardingStatus({
        tutorId,
        userData,
        tutorApplicationStatus,
        tutoringEligibilityStatus,
        payoutAccounts,
      });
      const derivedState = buildDerivedTutorAuthorityState({
        tutorId,
        userData,
        applicationData: applicationFields,
        tutorApplicationStatus,
        tutoringEligibilityStatus,
        payoutOnboardingStatus,
      });

      tx.set(applicationRef, {
        ...applicationFields,
        status: tutorApplicationStatus,
        tutorApplicationStatus,
        tutoringEligibilityStatus,
        payoutOnboardingStatus,
        adminApproval: derivedState.adminApproval,
        adminApprovalAt: derivedState.adminApproval ?
          (userData.adminApprovalAt ?? nowServerTs()) :
          admin.firestore.FieldValue.delete(),
        adminApprovalBy: derivedState.adminApproval ?
          (toTrimmedString(userData.adminApprovalBy) || tutorId) :
          admin.firestore.FieldValue.delete(),
        rejectionReason: admin.firestore.FieldValue.delete(),
        suspensionReason:
          tutorApplicationStatus === "suspended" ?
            currentSnapshot.suspensionReason :
            admin.firestore.FieldValue.delete(),
        tutoringApprovalVersion: TUTOR_APPROVAL_NORMALIZATION_VERSION,
        tutoringApprovalNormalizedAt: nowServerTs(),
        tutoringSearchVisible: derivedState.approvedForTutoring,
        tutoringSearchVisibilityReason: derivedState.searchVisibilityReason,
        submittedAt:
          tutorApplicationStatus === "submitted" ?
            nowServerTs() :
            (applicationSnap.data()?.submittedAt ?? null),
        updatedAt: nowServerTs(),
        createdAt: applicationSnap.exists ?
          (applicationSnap.data()?.createdAt ?? nowServerTs()) :
          nowServerTs(),
      }, {merge: true});

      tx.set(userRef, {
        tutorApplicationStatus,
        tutoringEligibilityStatus,
        payoutOnboardingStatus,
        adminApproval: derivedState.adminApproval,
        adminApprovalAt: derivedState.adminApproval ?
          (userData.adminApprovalAt ?? nowServerTs()) :
          admin.firestore.FieldValue.delete(),
        adminApprovalBy: derivedState.adminApproval ?
          (toTrimmedString(userData.adminApprovalBy) || tutorId) :
          admin.firestore.FieldValue.delete(),
        rejectionReason: admin.firestore.FieldValue.delete(),
        suspensionReason:
          tutorApplicationStatus === "suspended" ?
            currentSnapshot.suspensionReason :
            admin.firestore.FieldValue.delete(),
        tutorStatus: derivedState.tutorStatus,
        tutorStatusUpdatedAt: nowServerTs(),
        tutorProfile: derivedState.tutorProfile,
        tutorSubjects: derivedState.tutorSubjects,
        displayRate: payload.displayRate,
        tutorRequestsEnabled: derivedState.normalizedTutorRequestsEnabled,
        tutorAvailability: derivedState.normalizedTutorAvailability,
        tutorPayoutsBlocked: payoutOnboardingStatus === "blocked",
        payoutsBlocked: payoutOnboardingStatus === "blocked",
        blockedFromPayouts: payoutOnboardingStatus === "blocked",
        ecosystemProfile: derivedState.ecosystemProfile,
        tutoringSearchVisible: derivedState.approvedForTutoring,
        tutoringSearchVisibilityReason: derivedState.searchVisibilityReason,
        tutoringApprovalVersion: TUTOR_APPROVAL_NORMALIZATION_VERSION,
        tutoringApprovalNormalizedAt: nowServerTs(),
        tutorApplicationSubmittedAt:
          tutorApplicationStatus === "submitted" ?
            nowServerTs() :
            (userData.tutorApplicationSubmittedAt ?? null),
        updatedAt: nowServerTs(),
      }, {merge: true});

      tx.set(searchProfileRef, buildTutorSearchProfilePatch({
        tutorId,
        userData: {
          ...userData,
          tutorAvailability: derivedState.normalizedTutorAvailability,
          isOnline: derivedState.normalizedIsOnline,
          tutorRequestsEnabled: derivedState.normalizedTutorRequestsEnabled,
        },
        applicationData: applicationFields,
        tutorApplicationStatus,
        tutoringEligibilityStatus,
        payoutOnboardingStatus,
        adminApproval: derivedState.adminApproval,
        approvedForTutoring: derivedState.approvedForTutoring,
      }), {merge: true});

      return buildStatusResult({
        tutorId,
        tutorApplicationStatus,
        tutoringEligibilityStatus,
        payoutOnboardingStatus,
        adminApproval: derivedState.adminApproval,
      });
    });
  }
);

async function mutateTutorApprovalState(params: {
  requestAuth: {uid?: string; token?: Record<string, unknown>} | null;
  tutorId: string;
  nextTutorApplicationStatus?: TutorApplicationStatus;
  nextTutoringEligibilityStatus?: "ineligible" | "eligible" | "blocked";
  nextPayoutOnboardingStatus?: PayoutOnboardingStatus;
  rejectionReason?: string | null;
  suspensionReason?: string | null;
  requireExistingApplication?: boolean;
}): Promise<TutorStatusMutationResult> {
  const actorId = toTrimmedString(params.requestAuth?.uid);
  const userRef = db.collection("users").doc(params.tutorId);
  const applicationRef = db.collection("tutor_applications").doc(params.tutorId);
  const searchProfileRef = db.collection("tutor_search_profiles").doc(params.tutorId);

  return db.runTransaction(async (tx) => {
    const [userSnap, applicationSnap, payoutAccountsSnap] = await Promise.all([
      tx.get(userRef),
      tx.get(applicationRef),
      tx.get(
        db.collection("tutor_payout_accounts").where("tutorId", "==", params.tutorId)
      ),
    ]);
    if (!userSnap.exists) {
      throw new HttpsError("not-found", "Tutor was not found.");
    }

    const userData = userSnap.data() ?? {};
    if (
      (params.nextTutorApplicationStatus === "approved" ||
          params.nextTutoringEligibilityStatus === "eligible") &&
      !isFullAccountTutor(userData)
    ) {
      throw new HttpsError(
        "failed-precondition",
        "Only full-account tutors can be approved for tutoring."
      );
    }
    const applicationData = existingApplicationData(
      params.tutorId,
      userData,
      applicationSnap.data() ?? {}
    );
    if (params.requireExistingApplication && Object.keys(applicationData).length === 0) {
      throw new HttpsError("not-found", "Tutor application was not found.");
    }

    const currentSnapshot = deriveTutorApprovalSnapshot({
      userData,
      applicationData,
    });
    if (
      params.nextTutorApplicationStatus === "under_review" &&
      currentSnapshot.tutorApplicationStatus === "approved"
    ) {
      throw new HttpsError(
        "failed-precondition",
        "Approved tutors must be suspended instead of moved back to review."
      );
    }
    if (
      params.nextTutorApplicationStatus === "rejected" &&
      currentSnapshot.tutorApplicationStatus === "approved"
    ) {
      throw new HttpsError(
        "failed-precondition",
        "Approved tutors must be suspended instead of rejected."
      );
    }
    const tutorApplicationStatus =
      params.nextTutorApplicationStatus ?? currentSnapshot.tutorApplicationStatus;
    const tutoringEligibilityStatus: TutorEligibilityStatus =
      params.nextTutoringEligibilityStatus ?? currentSnapshot.tutoringEligibilityStatus;
    const payoutAccounts = payoutAccountsSnap.docs.map(
      (doc) => doc.data() ?? {}
    );
    const payoutOnboardingStatus =
      params.nextPayoutOnboardingStatus ??
      deriveAutomaticPayoutOnboardingStatus({
        tutorId: params.tutorId,
        userData,
        tutorApplicationStatus,
        tutoringEligibilityStatus,
        payoutAccounts,
      });
    const derivedState = buildDerivedTutorAuthorityState({
      tutorId: params.tutorId,
      userData,
      applicationData,
      tutorApplicationStatus,
      tutoringEligibilityStatus,
      payoutOnboardingStatus,
    });

    tx.set(applicationRef, {
      ...applicationData,
      status: tutorApplicationStatus,
      tutorApplicationStatus,
      tutoringEligibilityStatus,
      payoutOnboardingStatus,
      adminApproval: derivedState.adminApproval,
      adminApprovalAt: derivedState.adminApproval ?
        nowServerTs() :
        admin.firestore.FieldValue.delete(),
      adminApprovalBy: derivedState.adminApproval ?
        actorId || null :
        admin.firestore.FieldValue.delete(),
      rejectionReason:
        tutorApplicationStatus === "rejected" ?
          toTrimmedString(params.rejectionReason) :
          admin.firestore.FieldValue.delete(),
      suspensionReason:
        tutorApplicationStatus === "suspended" ?
          toTrimmedString(params.suspensionReason) :
          admin.firestore.FieldValue.delete(),
      reviewedAt:
        tutorApplicationStatus === "under_review" ? nowServerTs() : applicationSnap.data()?.reviewedAt ?? null,
      approvedAt:
        tutorApplicationStatus === "approved" ? nowServerTs() : applicationSnap.data()?.approvedAt ?? null,
      rejectedAt:
        tutorApplicationStatus === "rejected" ? nowServerTs() : applicationSnap.data()?.rejectedAt ?? null,
      suspendedAt:
        tutorApplicationStatus === "suspended" ? nowServerTs() : applicationSnap.data()?.suspendedAt ?? null,
      restoredAt:
        params.nextTutorApplicationStatus === "approved" &&
          currentSnapshot.tutorApplicationStatus === "suspended" ?
          nowServerTs() :
          applicationSnap.data()?.restoredAt ?? null,
      tutoringApprovalVersion: TUTOR_APPROVAL_NORMALIZATION_VERSION,
      tutoringApprovalNormalizedAt: nowServerTs(),
      tutoringSearchVisible: derivedState.approvedForTutoring,
      tutoringSearchVisibilityReason: derivedState.searchVisibilityReason,
      updatedAt: nowServerTs(),
      createdAt: applicationSnap.exists ?
        (applicationSnap.data()?.createdAt ?? nowServerTs()) :
        nowServerTs(),
    }, {merge: true});

    tx.set(userRef, {
      tutorApplicationStatus,
      tutoringEligibilityStatus,
      payoutOnboardingStatus,
      adminApproval: derivedState.adminApproval,
      adminApprovalAt: derivedState.adminApproval ?
        nowServerTs() :
        admin.firestore.FieldValue.delete(),
      adminApprovalBy: derivedState.adminApproval ?
        actorId || null :
        admin.firestore.FieldValue.delete(),
      rejectionReason:
        tutorApplicationStatus === "rejected" ?
          toTrimmedString(params.rejectionReason) :
          admin.firestore.FieldValue.delete(),
      suspensionReason:
        tutorApplicationStatus === "suspended" ?
          toTrimmedString(params.suspensionReason) :
          admin.firestore.FieldValue.delete(),
      tutorStatus: derivedState.tutorStatus,
      tutorStatusUpdatedAt: nowServerTs(),
      tutorProfile: derivedState.tutorProfile,
      tutorSubjects: derivedState.tutorSubjects,
      ecosystemProfile: derivedState.ecosystemProfile,
      tutorRequestsEnabled: derivedState.normalizedTutorRequestsEnabled,
      tutorAvailability: derivedState.normalizedTutorAvailability,
      tutorPayoutsBlocked: payoutOnboardingStatus === "blocked",
      payoutsBlocked: payoutOnboardingStatus === "blocked",
      blockedFromPayouts: payoutOnboardingStatus === "blocked",
      tutoringSearchVisible: derivedState.approvedForTutoring,
      tutoringSearchVisibilityReason: derivedState.searchVisibilityReason,
      tutoringApprovalVersion: TUTOR_APPROVAL_NORMALIZATION_VERSION,
      tutoringApprovalNormalizedAt: nowServerTs(),
      tutorApplicationReviewedAt:
        tutorApplicationStatus === "under_review" ? nowServerTs() : userData.tutorApplicationReviewedAt ?? null,
      tutorApprovedAt:
        tutorApplicationStatus === "approved" ? nowServerTs() : userData.tutorApprovedAt ?? null,
      tutorSuspendedAt:
        tutorApplicationStatus === "suspended" ? nowServerTs() : userData.tutorSuspendedAt ?? null,
      tutorRestoredAt:
        params.nextTutorApplicationStatus === "approved" &&
          currentSnapshot.tutorApplicationStatus === "suspended" ?
          nowServerTs() :
          userData.tutorRestoredAt ?? null,
      updatedAt: nowServerTs(),
    }, {merge: true});

    tx.set(searchProfileRef, buildTutorSearchProfilePatch({
      tutorId: params.tutorId,
      userData: {
        ...userData,
        tutorAvailability: derivedState.normalizedTutorAvailability,
        isOnline: derivedState.normalizedIsOnline,
        tutorRequestsEnabled: derivedState.normalizedTutorRequestsEnabled,
      },
      applicationData,
      tutorApplicationStatus,
      tutoringEligibilityStatus,
      payoutOnboardingStatus,
      adminApproval: derivedState.adminApproval,
      approvedForTutoring: derivedState.approvedForTutoring,
    }), {merge: true});

    return buildStatusResult({
      tutorId: params.tutorId,
      tutorApplicationStatus,
      tutoringEligibilityStatus,
      payoutOnboardingStatus,
      adminApproval: derivedState.adminApproval,
    });
  });
}

export const reviewTutorApplication = onCall(
  {region: REGION},
  async (request): Promise<TutorStatusMutationResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }
    assertPlatformAdmin(request.auth);

    const tutorId = toTrimmedString(request.data?.tutorId);
    if (!tutorId) {
      throw new HttpsError("invalid-argument", "tutorId is required.");
    }

    const result = await mutateTutorApprovalState({
      requestAuth: request.auth,
      tutorId,
      nextTutorApplicationStatus: "under_review",
      nextTutoringEligibilityStatus: "ineligible",
      requireExistingApplication: true,
    });
    await writeTutorAdminAuditLog({
      action: "review_tutor_application",
      actorUid: request.auth.uid,
      tutorId,
      result,
    });
    return result;
  }
);

export const approveTutorApplication = onCall(
  {region: REGION},
  async (request): Promise<TutorStatusMutationResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }
    assertPlatformAdmin(request.auth);

    const tutorId = toTrimmedString(request.data?.tutorId);
    if (!tutorId) {
      throw new HttpsError("invalid-argument", "tutorId is required.");
    }

    const result = await mutateTutorApprovalState({
      requestAuth: request.auth,
      tutorId,
      nextTutorApplicationStatus: "approved",
      nextTutoringEligibilityStatus: "eligible",
      requireExistingApplication: true,
    });
    await writeTutorAdminAuditLog({
      action: "approve_tutor_application",
      actorUid: request.auth.uid,
      tutorId,
      result,
    });
    return result;
  }
);

export const rejectTutorApplication = onCall(
  {region: REGION},
  async (request): Promise<TutorStatusMutationResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }
    assertPlatformAdmin(request.auth);

    const tutorId = toTrimmedString(request.data?.tutorId);
    const rejectionReason = toTrimmedString(request.data?.rejectionReason);
    if (!tutorId || !rejectionReason) {
      throw new HttpsError(
        "invalid-argument",
        "tutorId and rejectionReason are required."
      );
    }

    const result = await mutateTutorApprovalState({
      requestAuth: request.auth,
      tutorId,
      nextTutorApplicationStatus: "rejected",
      nextTutoringEligibilityStatus: "ineligible",
      rejectionReason,
      requireExistingApplication: true,
    });
    await writeTutorAdminAuditLog({
      action: "reject_tutor_application",
      actorUid: request.auth.uid,
      tutorId,
      result,
      metadata: {rejectionReason},
    });
    return result;
  }
);

export const suspendTutor = onCall(
  {region: REGION},
  async (request): Promise<TutorStatusMutationResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }
    assertPlatformAdmin(request.auth);

    const tutorId = toTrimmedString(request.data?.tutorId);
    const suspensionReason = toTrimmedString(request.data?.suspensionReason);
    if (!tutorId || !suspensionReason) {
      throw new HttpsError(
        "invalid-argument",
        "tutorId and suspensionReason are required."
      );
    }

    const result = await mutateTutorApprovalState({
      requestAuth: request.auth,
      tutorId,
      nextTutorApplicationStatus: "suspended",
      nextTutoringEligibilityStatus: "blocked",
      suspensionReason,
      requireExistingApplication: false,
    });
    await writeTutorAdminAuditLog({
      action: "suspend_tutor",
      actorUid: request.auth.uid,
      tutorId,
      result,
      metadata: {suspensionReason},
    });
    return result;
  }
);

export const restoreTutor = onCall(
  {region: REGION},
  async (request): Promise<TutorStatusMutationResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }
    assertPlatformAdmin(request.auth);

    const tutorId = toTrimmedString(request.data?.tutorId);
    if (!tutorId) {
      throw new HttpsError("invalid-argument", "tutorId is required.");
    }

    const result = await mutateTutorApprovalState({
      requestAuth: request.auth,
      tutorId,
      nextTutorApplicationStatus: "approved",
      nextTutoringEligibilityStatus: "eligible",
      requireExistingApplication: false,
    });
    await writeTutorAdminAuditLog({
      action: "restore_tutor",
      actorUid: request.auth.uid,
      tutorId,
      result,
    });
    return result;
  }
);

export const setTutorPayoutReadiness = onCall(
  {region: REGION},
  async (request): Promise<TutorStatusMutationResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }
    assertPlatformAdmin(request.auth);

    const tutorId = toTrimmedString(request.data?.tutorId);
    const payoutOnboardingStatus = toTrimmedString(
      request.data?.payoutOnboardingStatus
    ).toLowerCase() as PayoutOnboardingStatus;
    if (!tutorId || ![
      "not_started",
      "pending",
      "verified",
      "blocked",
    ].includes(payoutOnboardingStatus)) {
      throw new HttpsError(
        "invalid-argument",
        "tutorId and a valid payoutOnboardingStatus are required."
      );
    }

    const result = await mutateTutorApprovalState({
      requestAuth: request.auth,
      tutorId,
      nextPayoutOnboardingStatus: payoutOnboardingStatus,
      requireExistingApplication: false,
    });
    await writeTutorAdminAuditLog({
      action: "set_tutor_payout_readiness",
      actorUid: request.auth.uid,
      tutorId,
      result,
      metadata: {payoutOnboardingStatus},
    });
    return result;
  }
);

function buildInactiveTutorSearchProfilePatch(
  tutorId: string,
  reason: string
): Record<string, unknown> {
  return {
    tutorId,
    availability: "offline",
    isOnline: false,
    isActive: false,
    searchVisible: false,
    tutoringSearchVisible: false,
    tutoringSearchVisibilityReason: reason,
    tutorApplicationStatus: "draft",
    tutoringEligibilityStatus: "ineligible",
    payoutOnboardingStatus: "not_started",
    adminApproval: false,
    tutorRequestsEnabled: false,
    tutoringApprovalVersion: TUTOR_APPROVAL_NORMALIZATION_VERSION,
    tutoringApprovalNormalizedAt: nowServerTs(),
    updatedAt: nowServerTs(),
  };
}

interface TutorApprovalNormalizationOutcome {
  tutorId: string;
  considered: boolean;
  normalized: boolean;
  payoutOnboardingStatus: PayoutOnboardingStatus | null;
}

interface TutorApprovalBackfillResult {
  dryRun: boolean;
  processedTutorUsers: number;
  normalizedTutorUsers: number;
  skippedUsers: number;
  processedSearchProfiles: number;
  orphanedSearchProfilesDisabled: number;
  payoutVerifiedCount: number;
  payoutPendingCount: number;
  payoutBlockedCount: number;
}

async function normalizeTutorApprovalRecord(params: {
  tutorId: string;
  dryRun: boolean;
  actorId?: string | null;
}): Promise<TutorApprovalNormalizationOutcome> {
  const userRef = db.collection("users").doc(params.tutorId);
  const applicationRef = db.collection("tutor_applications").doc(params.tutorId);
  const searchProfileRef = db.collection("tutor_search_profiles").doc(params.tutorId);
  const [userSnap, applicationSnap, searchProfileSnap, payoutAccountsSnap] =
    await Promise.all([
      userRef.get(),
      applicationRef.get(),
      searchProfileRef.get(),
      db.collection("tutor_payout_accounts")
        .where("tutorId", "==", params.tutorId)
        .get(),
    ]);

  if (!userSnap.exists) {
    if (searchProfileSnap.exists && !params.dryRun) {
      await searchProfileRef.set(
        buildInactiveTutorSearchProfilePatch(
          params.tutorId,
          "missing_user_record"
        ),
        {merge: true}
      );
    }
    return {
      tutorId: params.tutorId,
      considered: searchProfileSnap.exists,
      normalized: searchProfileSnap.exists,
      payoutOnboardingStatus: null,
    };
  }

  const userData = userSnap.data() ?? {};
  const applicationData = existingApplicationData(
    params.tutorId,
    userData,
    applicationSnap.data() ?? {}
  );
  const payoutAccounts = payoutAccountsSnap.docs.map((doc) => doc.data() ?? {});
  const candidate = hasTutorSignals({
    userData,
    applicationData,
    searchProfileExists: searchProfileSnap.exists,
    payoutAccountCount: payoutAccounts.length,
  });

  if (!candidate) {
    return {
      tutorId: params.tutorId,
      considered: false,
      normalized: false,
      payoutOnboardingStatus: null,
    };
  }

  const currentSnapshot = deriveTutorApprovalSnapshot({
    userData,
    applicationData,
  });
  const tutorApplicationStatus = deriveNormalizedTutorApplicationStatusForBackfill({
    userData,
    applicationData,
    currentTutorApplicationStatus: currentSnapshot.tutorApplicationStatus,
    currentTutoringEligibilityStatus:
      currentSnapshot.tutoringEligibilityStatus as TutorEligibilityStatus,
  });
  const tutoringEligibilityStatus = deriveNormalizedTutoringEligibilityStatus({
    userData,
    tutorApplicationStatus,
  });
  const payoutOnboardingStatus = deriveAutomaticPayoutOnboardingStatus({
    tutorId: params.tutorId,
    userData,
    tutorApplicationStatus,
    tutoringEligibilityStatus,
    payoutAccounts,
  });
  const derivedState = buildDerivedTutorAuthorityState({
    tutorId: params.tutorId,
    userData,
    applicationData,
    tutorApplicationStatus,
    tutoringEligibilityStatus,
    payoutOnboardingStatus,
  });
  const rejectionReason =
    tutorApplicationStatus === "rejected" ?
      (
        currentSnapshot.rejectionReason ||
        (!isFullAccountTutor(userData) ? GUEST_TUTOR_REJECTION_REASON : null)
      ) :
      null;
  const suspensionReason =
    tutorApplicationStatus === "suspended" ?
      currentSnapshot.suspensionReason :
      null;

  if (params.dryRun) {
    return {
      tutorId: params.tutorId,
      considered: true,
      normalized: true,
      payoutOnboardingStatus,
    };
  }

  const actorId =
    toTrimmedString(params.actorId) ||
    toTrimmedString(userData.adminApprovalBy) ||
    toTrimmedString(applicationData.adminApprovalBy) ||
    "system:tutor_approval_backfill";
  const shouldPersistApplicationDoc =
    applicationSnap.exists ||
    Object.keys(applicationData).length > 0 ||
    tutorApplicationStatus !== "draft";

  if (shouldPersistApplicationDoc) {
    await applicationRef.set({
      ...applicationData,
      status: tutorApplicationStatus,
      tutorApplicationStatus,
      tutoringEligibilityStatus,
      payoutOnboardingStatus,
      adminApproval: derivedState.adminApproval,
      adminApprovalAt: derivedState.adminApproval ?
        (userData.adminApprovalAt ?? applicationData.adminApprovalAt ?? nowServerTs()) :
        admin.firestore.FieldValue.delete(),
      adminApprovalBy: derivedState.adminApproval ?
        actorId :
        admin.firestore.FieldValue.delete(),
      rejectionReason:
        rejectionReason ?? admin.firestore.FieldValue.delete(),
      suspensionReason:
        suspensionReason ?? admin.firestore.FieldValue.delete(),
      submittedAt:
        tutorApplicationStatus === "submitted" ?
          (applicationSnap.data()?.submittedAt ??
            userData.tutorApplicationSubmittedAt ??
            nowServerTs()) :
          (applicationSnap.data()?.submittedAt ?? null),
      reviewedAt:
        tutorApplicationStatus === "under_review" ?
          (applicationSnap.data()?.reviewedAt ??
            userData.tutorApplicationReviewedAt ??
            nowServerTs()) :
          (applicationSnap.data()?.reviewedAt ?? null),
      approvedAt:
        tutorApplicationStatus === "approved" ?
          (applicationSnap.data()?.approvedAt ??
            userData.tutorApprovedAt ??
            userData.adminApprovalAt ??
            nowServerTs()) :
          (applicationSnap.data()?.approvedAt ?? null),
      rejectedAt:
        tutorApplicationStatus === "rejected" ?
          (applicationSnap.data()?.rejectedAt ?? nowServerTs()) :
          (applicationSnap.data()?.rejectedAt ?? null),
      suspendedAt:
        tutorApplicationStatus === "suspended" ?
          (applicationSnap.data()?.suspendedAt ??
            userData.tutorSuspendedAt ??
            nowServerTs()) :
          (applicationSnap.data()?.suspendedAt ?? null),
      restoredAt:
        tutorApplicationStatus === "approved" &&
          currentSnapshot.tutorApplicationStatus === "suspended" ?
          (applicationSnap.data()?.restoredAt ??
            userData.tutorRestoredAt ??
            nowServerTs()) :
          (applicationSnap.data()?.restoredAt ?? null),
      tutoringApprovalVersion: TUTOR_APPROVAL_NORMALIZATION_VERSION,
      tutoringApprovalNormalizedAt: nowServerTs(),
      tutoringSearchVisible: derivedState.approvedForTutoring,
      tutoringSearchVisibilityReason: derivedState.searchVisibilityReason,
      updatedAt: nowServerTs(),
      createdAt:
        applicationSnap.data()?.createdAt ?? nowServerTs(),
    }, {merge: true});
  }

  await userRef.set({
    tutorApplicationStatus,
    tutoringEligibilityStatus,
    payoutOnboardingStatus,
    adminApproval: derivedState.adminApproval,
    adminApprovalAt: derivedState.adminApproval ?
      (userData.adminApprovalAt ?? applicationData.adminApprovalAt ?? nowServerTs()) :
      admin.firestore.FieldValue.delete(),
    adminApprovalBy: derivedState.adminApproval ?
      actorId :
      admin.firestore.FieldValue.delete(),
    rejectionReason:
      rejectionReason ?? admin.firestore.FieldValue.delete(),
    suspensionReason:
      suspensionReason ?? admin.firestore.FieldValue.delete(),
    tutorStatus: derivedState.tutorStatus,
    tutorStatusUpdatedAt: nowServerTs(),
    tutorProfile: derivedState.tutorProfile,
    tutorSubjects: derivedState.tutorSubjects,
    tutorRequestsEnabled: derivedState.normalizedTutorRequestsEnabled,
    tutorAvailability: derivedState.normalizedTutorAvailability,
    tutorPayoutsBlocked: payoutOnboardingStatus === "blocked",
    payoutsBlocked: payoutOnboardingStatus === "blocked",
    blockedFromPayouts: payoutOnboardingStatus === "blocked",
    ecosystemProfile: derivedState.ecosystemProfile,
    tutoringSearchVisible: derivedState.approvedForTutoring,
    tutoringSearchVisibilityReason: derivedState.searchVisibilityReason,
    tutoringApprovalVersion: TUTOR_APPROVAL_NORMALIZATION_VERSION,
    tutoringApprovalNormalizedAt: nowServerTs(),
    tutorApplicationSubmittedAt:
      tutorApplicationStatus === "submitted" ?
        (userData.tutorApplicationSubmittedAt ??
          applicationSnap.data()?.submittedAt ??
          nowServerTs()) :
        (userData.tutorApplicationSubmittedAt ?? null),
    tutorApplicationReviewedAt:
      tutorApplicationStatus === "under_review" ?
        (userData.tutorApplicationReviewedAt ??
          applicationSnap.data()?.reviewedAt ??
          nowServerTs()) :
        (userData.tutorApplicationReviewedAt ?? null),
    tutorApprovedAt:
      tutorApplicationStatus === "approved" ?
        (userData.tutorApprovedAt ??
          applicationSnap.data()?.approvedAt ??
          nowServerTs()) :
        (userData.tutorApprovedAt ?? null),
    tutorSuspendedAt:
      tutorApplicationStatus === "suspended" ?
        (userData.tutorSuspendedAt ??
          applicationSnap.data()?.suspendedAt ??
          nowServerTs()) :
        (userData.tutorSuspendedAt ?? null),
    tutorRestoredAt:
      tutorApplicationStatus === "approved" &&
        currentSnapshot.tutorApplicationStatus === "suspended" ?
        (userData.tutorRestoredAt ??
          applicationSnap.data()?.restoredAt ??
          nowServerTs()) :
        (userData.tutorRestoredAt ?? null),
    updatedAt: nowServerTs(),
  }, {merge: true});

  await searchProfileRef.set(buildTutorSearchProfilePatch({
    tutorId: params.tutorId,
    userData: {
      ...userData,
      tutorAvailability: derivedState.normalizedTutorAvailability,
      isOnline: derivedState.normalizedIsOnline,
      tutorRequestsEnabled: derivedState.normalizedTutorRequestsEnabled,
    },
    applicationData,
    tutorApplicationStatus,
    tutoringEligibilityStatus,
    payoutOnboardingStatus,
    adminApproval: derivedState.adminApproval,
    approvedForTutoring: derivedState.approvedForTutoring,
  }), {merge: true});

  return {
    tutorId: params.tutorId,
    considered: true,
    normalized: true,
    payoutOnboardingStatus,
  };
}

async function disableOrphanedTutorSearchProfiles(params: {
  dryRun: boolean;
}): Promise<{processed: number; disabled: number}> {
  const searchProfilesSnap = await db.collection("tutor_search_profiles").get();
  let disabled = 0;
  for (const doc of searchProfilesSnap.docs) {
    const userSnap = await db.collection("users").doc(doc.id).get();
    if (userSnap.exists) {
      continue;
    }
    disabled += 1;
    if (!params.dryRun) {
      await doc.ref.set(
        buildInactiveTutorSearchProfilePatch(doc.id, "missing_user_record"),
        {merge: true}
      );
    }
  }

  return {
    processed: searchProfilesSnap.size,
    disabled,
  };
}

export async function runTutorApprovalBackfillJob(params: {
  dryRun?: boolean;
  tutorId?: string;
  actorId?: string | null;
} = {}): Promise<TutorApprovalBackfillResult> {
  const result: TutorApprovalBackfillResult = {
    dryRun: params.dryRun === true,
    processedTutorUsers: 0,
    normalizedTutorUsers: 0,
    skippedUsers: 0,
    processedSearchProfiles: 0,
    orphanedSearchProfilesDisabled: 0,
    payoutVerifiedCount: 0,
    payoutPendingCount: 0,
    payoutBlockedCount: 0,
  };

  if (toTrimmedString(params.tutorId)) {
    const singleOutcome = await normalizeTutorApprovalRecord({
      tutorId: toTrimmedString(params.tutorId),
      dryRun: result.dryRun,
      actorId: params.actorId,
    });
    if (singleOutcome.considered) {
      result.processedTutorUsers = 1;
      result.normalizedTutorUsers = singleOutcome.normalized ? 1 : 0;
      if (singleOutcome.payoutOnboardingStatus === "verified") {
        result.payoutVerifiedCount = 1;
      } else if (singleOutcome.payoutOnboardingStatus === "pending") {
        result.payoutPendingCount = 1;
      } else if (singleOutcome.payoutOnboardingStatus === "blocked") {
        result.payoutBlockedCount = 1;
      }
    } else {
      result.skippedUsers = 1;
    }
    const orphanSummary = await disableOrphanedTutorSearchProfiles({
      dryRun: result.dryRun,
    });
    result.processedSearchProfiles = orphanSummary.processed;
    result.orphanedSearchProfilesDisabled = orphanSummary.disabled;
    return result;
  }

  let lastUserId = "";
  while (true) {
    let query = db.collection("users")
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(100);
    if (lastUserId) {
      query = query.startAfter(lastUserId);
    }
    const userBatch = await query.get();
    if (userBatch.empty) {
      break;
    }

    for (const userDoc of userBatch.docs) {
      lastUserId = userDoc.id;
      const outcome = await normalizeTutorApprovalRecord({
        tutorId: userDoc.id,
        dryRun: result.dryRun,
        actorId: params.actorId,
      });
      if (!outcome.considered) {
        result.skippedUsers += 1;
        continue;
      }
      result.processedTutorUsers += 1;
      if (outcome.normalized) {
        result.normalizedTutorUsers += 1;
      }
      if (outcome.payoutOnboardingStatus === "verified") {
        result.payoutVerifiedCount += 1;
      } else if (outcome.payoutOnboardingStatus === "pending") {
        result.payoutPendingCount += 1;
      } else if (outcome.payoutOnboardingStatus === "blocked") {
        result.payoutBlockedCount += 1;
      }
    }
  }

  const orphanSummary = await disableOrphanedTutorSearchProfiles({
    dryRun: result.dryRun,
  });
  result.processedSearchProfiles = orphanSummary.processed;
  result.orphanedSearchProfilesDisabled = orphanSummary.disabled;
  return result;
}

export const runTutorApprovalBackfill = onCall(
  {region: REGION, timeoutSeconds: 540},
  async (request): Promise<TutorApprovalBackfillResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }
    assertPlatformAdmin(request.auth);

    return runTutorApprovalBackfillJob({
      dryRun: request.data?.dryRun === true,
      tutorId: toTrimmedString(request.data?.tutorId),
      actorId: request.auth.uid,
    });
  }
);

export const ontutorapprovaluserwritten = onDocumentWritten(
  {
    document: "users/{userId}",
    region: REGION,
  },
  async (event) => {
    const userId = toTrimmedString(event.params.userId);
    if (!userId) {
      return;
    }

    const afterSnap = event.data?.after;
    if (!afterSnap?.exists) {
      await db.collection("tutor_search_profiles").doc(userId).set(
        buildInactiveTutorSearchProfilePatch(userId, "missing_user_record"),
        {merge: true}
      );
      return;
    }

    const beforeData = event.data?.before.data() ?? {};
    const afterData = afterSnap.data() ?? {};
    const syncSignature = (data: Record<string, unknown>) => JSON.stringify({
      tutorProfile: toJSONObject(data.tutorProfile),
      tutorSubjects: readStringList(data.tutorSubjects),
      tutorStatus: toTrimmedString(data.tutorStatus),
      tutorApplicationStatus: toTrimmedString(data.tutorApplicationStatus),
      tutoringEligibilityStatus: toTrimmedString(data.tutoringEligibilityStatus),
      payoutOnboardingStatus: toTrimmedString(data.payoutOnboardingStatus),
      adminApproval: data.adminApproval === true,
      tutorAvailability: toTrimmedString(data.tutorAvailability),
      tutorRequestsEnabled: data.tutorRequestsEnabled === true,
      isOnline: data.isOnline === true,
      isDisabled: data.isDisabled === true,
      tutorStats: toJSONObject(data.tutorStats),
      organizationMembership: toJSONObject(data.organizationMembership),
      goldTick: toJSONObject(data.goldTick),
      accountType: toTrimmedString(data.accountType),
      accessTier: toTrimmedString(data.accessTier),
      ecosystemProfile: toJSONObject(data.ecosystemProfile),
    });

    if (syncSignature(beforeData) === syncSignature(afterData)) {
      return;
    }

    const applicationSnap = await db.collection("tutor_applications").doc(userId).get();
    const searchProfileRef = db.collection("tutor_search_profiles").doc(userId);
    const searchProfileSnap = await searchProfileRef.get();
    const applicationData = existingApplicationData(
      userId,
      afterData,
      applicationSnap.data() ?? {}
    );
    const candidate = hasTutorSignals({
      userData: afterData,
      applicationData,
      searchProfileExists: searchProfileSnap.exists,
    });

    if (!candidate) {
      if (searchProfileSnap.exists) {
        await searchProfileRef.set(
          buildInactiveTutorSearchProfilePatch(userId, "non_tutor_profile"),
          {merge: true}
        );
      }
      return;
    }

    const snapshot = deriveTutorApprovalSnapshot({
      userData: afterData,
      applicationData,
    });
    const tutorApplicationStatus = deriveNormalizedTutorApplicationStatusForBackfill({
      userData: afterData,
      applicationData,
      currentTutorApplicationStatus: snapshot.tutorApplicationStatus,
      currentTutoringEligibilityStatus:
        snapshot.tutoringEligibilityStatus as TutorEligibilityStatus,
    });
    const tutoringEligibilityStatus = deriveNormalizedTutoringEligibilityStatus({
      userData: afterData,
      tutorApplicationStatus,
    });
    const derivedState = buildDerivedTutorAuthorityState({
      tutorId: userId,
      userData: afterData,
      applicationData,
      tutorApplicationStatus,
      tutoringEligibilityStatus,
      payoutOnboardingStatus: snapshot.payoutOnboardingStatus,
    });

    await searchProfileRef.set(buildTutorSearchProfilePatch({
      tutorId: userId,
      userData: {
        ...afterData,
        tutorAvailability: derivedState.normalizedTutorAvailability,
        isOnline: derivedState.normalizedIsOnline,
        tutorRequestsEnabled: derivedState.normalizedTutorRequestsEnabled,
      },
      applicationData,
      tutorApplicationStatus,
      tutoringEligibilityStatus,
      payoutOnboardingStatus: snapshot.payoutOnboardingStatus,
      adminApproval: derivedState.adminApproval,
      approvedForTutoring: derivedState.approvedForTutoring,
    }), {merge: true});
  }
);

export const ontutorpayoutaccountwritten = onDocumentWritten(
  {
    document: "tutor_payout_accounts/{accountId}",
    region: REGION,
  },
  async (event) => {
    const payoutData =
      event.data?.after.data() ??
      event.data?.before.data() ??
      {};
    const tutorId = toTrimmedString(payoutData.tutorId);
    if (!tutorId) {
      return;
    }

    await normalizeTutorApprovalRecord({
      tutorId,
      dryRun: false,
      actorId: "system:tutor_payout_account_trigger",
    });
  }
);
