import {HttpsError} from "firebase-functions/v2/https";

export type TutorApplicationStatus =
  | "draft"
  | "submitted"
  | "under_review"
  | "approved"
  | "rejected"
  | "suspended";

export type TutoringEligibilityStatus =
  | "ineligible"
  | "eligible"
  | "blocked";

export type PayoutOnboardingStatus =
  | "not_started"
  | "pending"
  | "verified"
  | "blocked";

export interface TutorApprovalSnapshot {
  tutorApplicationStatus: TutorApplicationStatus;
  tutoringEligibilityStatus: TutoringEligibilityStatus;
  payoutOnboardingStatus: PayoutOnboardingStatus;
  adminApproval: boolean;
  adminApprovalAt: unknown;
  adminApprovalBy: string | null;
  rejectionReason: string | null;
  suspensionReason: string | null;
  legacyTutorStatus: string;
  fullAccountTutor: boolean;
  approvedForTutoring: boolean;
  payoutReady: boolean;
}

const TUTOR_APPLICATION_STATUSES = new Set<TutorApplicationStatus>([
  "draft",
  "submitted",
  "under_review",
  "approved",
  "rejected",
  "suspended",
]);

const TUTORING_ELIGIBILITY_STATUSES =
  new Set<TutoringEligibilityStatus>([
    "ineligible",
    "eligible",
    "blocked",
  ]);

const PAYOUT_ONBOARDING_STATUSES = new Set<PayoutOnboardingStatus>([
  "not_started",
  "pending",
  "verified",
  "blocked",
]);

export function toTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function normalizeStatus(value: unknown): string {
  return toTrimmedString(value).toLowerCase();
}

function readStatus<T extends string>(value: unknown, allowed: Set<T>): T | null {
  const normalized = normalizeStatus(value);
  return allowed.has(normalized as T) ? normalized as T : null;
}

function hasApplicationContent(data: Record<string, unknown>): boolean {
  return [
    "mainSubjects",
    "minorSubjects",
    "baseRate",
    "qualification",
    "institution",
    "yearsExperience",
    "availabilityDays",
    "availabilityWindow",
  ].some((field) => {
    const value = data[field];
    if (Array.isArray(value)) return value.length > 0;
    if (typeof value === "number") return Number.isFinite(value) && value > 0;
    return toTrimmedString(value).length > 0;
  });
}

export function isFullAccountTutor(userData: Record<string, unknown>): boolean {
  const accountType = normalizeStatus(userData.accountType);
  const accessTier = normalizeStatus(userData.accessTier);
  return accountType !== "instant_tutor" && accessTier !== "instant_tutor";
}

function deriveTutorApplicationStatus(params: {
  userData: Record<string, unknown>;
  applicationData: Record<string, unknown>;
}): TutorApplicationStatus {
  const explicit =
    readStatus(
      params.userData.tutorApplicationStatus ??
        params.applicationData.tutorApplicationStatus ??
        params.applicationData.status,
      TUTOR_APPLICATION_STATUSES
    );
  if (explicit) {
    return explicit;
  }

  const legacyStatus = normalizeStatus(params.userData.tutorStatus);
  if (["approved", "active"].includes(legacyStatus)) {
    return "approved";
  }
  if (legacyStatus === "suspended" || legacyStatus === "blocked") {
    return "suspended";
  }
  if (legacyStatus === "rejected") {
    return "rejected";
  }
  if (["pending", "submitted", "under_review"].includes(legacyStatus)) {
    return legacyStatus === "under_review" ? "under_review" : "submitted";
  }
  if (hasApplicationContent(params.applicationData)) {
    return "submitted";
  }
  return "draft";
}

function deriveTutoringEligibilityStatus(params: {
  userData: Record<string, unknown>;
  applicationStatus: TutorApplicationStatus;
  fullAccountTutor: boolean;
}): TutoringEligibilityStatus {
  const explicit = readStatus(
    params.userData.tutoringEligibilityStatus,
    TUTORING_ELIGIBILITY_STATUSES
  );
  if (explicit) {
    return explicit;
  }

  if (
    params.userData.isDisabled === true ||
    params.applicationStatus === "suspended"
  ) {
    return "blocked";
  }
  if (
    params.fullAccountTutor &&
    params.applicationStatus === "approved" &&
    ["approved", "active"].includes(normalizeStatus(params.userData.tutorStatus))
  ) {
    return "eligible";
  }
  return "ineligible";
}

function derivePayoutOnboardingStatus(
  userData: Record<string, unknown>
): PayoutOnboardingStatus {
  const explicit = readStatus(
    userData.payoutOnboardingStatus,
    PAYOUT_ONBOARDING_STATUSES
  );
  if (explicit) {
    return explicit;
  }
  if (
    userData.tutorPayoutsBlocked === true ||
    userData.payoutsBlocked === true ||
    userData.blockedFromPayouts === true
  ) {
    return "blocked";
  }
  return "not_started";
}

export function buildLegacyTutorStatus(
  snapshot: Pick<
    TutorApprovalSnapshot,
    "tutorApplicationStatus" | "tutoringEligibilityStatus" | "adminApproval"
  >
): string {
  if (
    snapshot.tutorApplicationStatus === "approved" &&
    snapshot.tutoringEligibilityStatus === "eligible" &&
    snapshot.adminApproval
  ) {
    return "approved";
  }
  if (
    snapshot.tutorApplicationStatus === "suspended" ||
    snapshot.tutoringEligibilityStatus === "blocked"
  ) {
    return "suspended";
  }
  if (snapshot.tutorApplicationStatus === "rejected") {
    return "rejected";
  }
  if (
    snapshot.tutorApplicationStatus === "submitted" ||
    snapshot.tutorApplicationStatus === "under_review"
  ) {
    return "pending";
  }
  return "";
}

export function deriveTutorApprovalSnapshot(params: {
  userData: Record<string, unknown>;
  applicationData?: Record<string, unknown>;
}): TutorApprovalSnapshot {
  const applicationData = params.applicationData ?? {};
  const fullAccountTutor = isFullAccountTutor(params.userData);
  const tutorApplicationStatus = deriveTutorApplicationStatus({
    userData: params.userData,
    applicationData,
  });
  const adminApproval =
    params.userData.adminApproval === true ||
    (tutorApplicationStatus === "approved" &&
      ["approved", "active"].includes(normalizeStatus(params.userData.tutorStatus)));
  const tutoringEligibilityStatus = deriveTutoringEligibilityStatus({
    userData: params.userData,
    applicationStatus: tutorApplicationStatus,
    fullAccountTutor,
  });
  const payoutOnboardingStatus = derivePayoutOnboardingStatus(params.userData);
  const approvedForTutoring =
    fullAccountTutor &&
    adminApproval &&
    tutorApplicationStatus === "approved" &&
    tutoringEligibilityStatus === "eligible" &&
    params.userData.isDisabled !== true;
  const payoutReady =
    approvedForTutoring &&
    payoutOnboardingStatus === "verified" &&
    params.userData.tutorPayoutsBlocked !== true &&
    params.userData.payoutsBlocked !== true &&
    params.userData.blockedFromPayouts !== true;

  const snapshot: TutorApprovalSnapshot = {
    tutorApplicationStatus,
    tutoringEligibilityStatus,
    payoutOnboardingStatus,
    adminApproval,
    adminApprovalAt: params.userData.adminApprovalAt ?? applicationData.adminApprovalAt ?? null,
    adminApprovalBy:
      toTrimmedString(params.userData.adminApprovalBy) ||
      toTrimmedString(applicationData.adminApprovalBy) ||
      null,
    rejectionReason:
      toTrimmedString(params.userData.rejectionReason) ||
      toTrimmedString(applicationData.rejectionReason) ||
      null,
    suspensionReason:
      toTrimmedString(params.userData.suspensionReason) ||
      toTrimmedString(applicationData.suspensionReason) ||
      null,
    legacyTutorStatus: "",
    fullAccountTutor,
    approvedForTutoring,
    payoutReady,
  };

  snapshot.legacyTutorStatus = buildLegacyTutorStatus(snapshot);
  return snapshot;
}

export function assertPlatformAdmin(auth: {token?: Record<string, unknown>} | null): void {
  const token = auth?.token ?? {};
  const isAdmin =
    token.admin === true ||
    normalizeStatus(token.role) === "admin" ||
    normalizeStatus(token.platformRole) === "admin";
  if (!isAdmin) {
    throw new HttpsError(
      "permission-denied",
      "This action is reserved for a platform admin."
    );
  }
}

export function assertTutorEligibleForTutoring(
  userData: Record<string, unknown>,
  tutorId: string,
  applicationData?: Record<string, unknown>
): TutorApprovalSnapshot {
  const snapshot = deriveTutorApprovalSnapshot({userData, applicationData});
  if (!snapshot.fullAccountTutor) {
    throw new HttpsError(
      "failed-precondition",
      "Tutors must use full accounts. Guest tutoring mode is student-only."
    );
  }
  if (!snapshot.approvedForTutoring) {
    throw new HttpsError(
      "failed-precondition",
      `Tutor ${tutorId} is not approved and eligible for tutoring.`
    );
  }
  return snapshot;
}

export function assertTutorReadyForPayout(
  userData: Record<string, unknown>,
  tutorId: string,
  applicationData?: Record<string, unknown>
): TutorApprovalSnapshot {
  const snapshot = deriveTutorApprovalSnapshot({userData, applicationData});
  if (!snapshot.payoutReady) {
    throw new HttpsError(
      "failed-precondition",
      `Tutor ${tutorId} is not payout-ready.`
    );
  }
  return snapshot;
}
