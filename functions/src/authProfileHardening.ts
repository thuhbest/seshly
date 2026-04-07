import * as admin from "firebase-admin";
import {HttpsError} from "firebase-functions/v2/https";

import {readTrimmedString, requireObjectPayload, secureOnCall} from "./security";

const db = admin.firestore();
const REGION = "europe-west1";

type JsonMap = Record<string, unknown>;

function nowServerTs() {
  return admin.firestore.FieldValue.serverTimestamp();
}

function convertLevelToYear(levelOfStudy: string): string {
  switch (levelOfStudy.toLowerCase()) {
  case "first year":
  case "1st year":
    return "1st Year";
  case "second year":
  case "2nd year":
    return "2nd Year";
  case "third year":
  case "3rd year":
    return "3rd Year";
  case "fourth year":
  case "4th year":
    return "4th Year";
  case "postgraduate":
  case "postgrad":
    return "Postgrad";
  default:
    return levelOfStudy;
  }
}

function buildVerifiedStudentDefaults(params: {
  uid: string;
  email: string;
  emailVerified: boolean;
  fullName: string;
  studentNumber: string;
  university: string;
  levelOfStudy: string;
}): JsonMap {
  const year = convertLevelToYear(params.levelOfStudy);
  return {
    uid: params.uid,
    accountType: "student",
    accessTier: "verified_student",
    instantTutorAccess: false,
    accessMode: "verifiedStudent",
    fullName: params.fullName,
    fullNameLowercase: params.fullName.toLowerCase(),
    studentNumber: params.studentNumber,
    studentNumberLowercase: params.studentNumber.toLowerCase(),
    university: params.university,
    levelOfStudy: params.levelOfStudy,
    year,
    email: params.email,
    emailLowercase: params.email.toLowerCase(),
    emailVerified: params.emailVerified,
    isDisabled: false,
    createdAt: nowServerTs(),
    lastLoginAt: nowServerTs(),
    seshMinutes: 0,
    walletBalanceZar: 0,
    walletHoldZar: 0,
    walletCurrency: "ZAR",
    billingSetupStatus: "missing",
    billingProvider: "Seshly Pay",
    billingDefaultPaymentMethodId: "",
    billingRegistrationId: "",
    billingProviderReference: "",
    billingAuthorizationCode: "",
    billingAuthorizationReference: "",
    billingPreauthReference: "",
    billingCustomerCode: "",
    billingReusableAuthorizationCode: "",
    billingStatus: "missing",
    billingCardBrand: "",
    billingCardLast4: "",
    billingCardExpMonth: 0,
    billingCardExpYear: 0,
    billingCardHolder: params.fullName,
    billingSpendTotalZar: 0,
    billingAuthorizationMode: "per_session",
    billingUpdatedAt: nowServerTs(),
    seshCreditBalance: 3,
    seshCreditCurrency: "ZAR",
    seshCreditValueZar: 2,
    seshCreditPurchasedTotal: 0,
    seshCreditUsedTotal: 0,
    seshCreditSpendTotalZar: 0,
    seshCreditIntroGranted: true,
    seshCreditIntroCredits: 3,
    seshCreditUpdatedAt: nowServerTs(),
    studyVaultUploadCount: 0,
    studyVaultSalesCount: 0,
    studyVaultRevenueZar: 0,
    studyVaultPurchaseCount: 0,
    studyVaultSpendTotalZar: 0,
    seshFocusHours: 0,
    freeFocusPasses: 5,
    focusEmergencyPasses: 2,
    tutorApplicationStatus: "draft",
    tutoringEligibilityStatus: "ineligible",
    payoutOnboardingStatus: "not_started",
    adminApproval: false,
    tutorStatus: "",
    tutorAvailability: "offline",
    ecosystemProfile: {
      student: true,
      tutor: false,
      mentor: false,
      universityPartner: false,
    },
    streak: 1,
    streakBest: 1,
    major: "",
    id: params.studentNumber,
  };
}

function buildInstantTutorDefaults(uid: string, existing: JsonMap): JsonMap {
  return {
    uid,
    accountType: "instant_tutor",
    accessTier: "instant_tutor",
    instantTutorAccess: true,
    accessMode: "instantTutor",
    instantTutorAccessMode: "tutor_booking_only",
    fullName: readTrimmedString(existing.fullName, 120) || "Instant Tutor Learner",
    displayName: readTrimmedString(existing.displayName, 120) || "Instant Tutor Learner",
    fullNameLowercase:
      (readTrimmedString(existing.fullNameLowercase, 120) || "instant tutor learner"),
    studentNumber: readTrimmedString(existing.studentNumber, 64),
    studentNumberLowercase: readTrimmedString(existing.studentNumberLowercase, 64),
    email: "",
    emailLowercase: "",
    emailVerified: false,
    isDisabled: false,
    university: readTrimmedString(existing.university, 120) || "Instant Tutor Mode",
    levelOfStudy: readTrimmedString(existing.levelOfStudy, 64) || "Instant",
    year: readTrimmedString(existing.year, 64) || "Instant",
    major: readTrimmedString(existing.major, 120),
    bio: readTrimmedString(existing.bio, 300) ||
      "Instant Tutor Mode supports read-only feed browsing and tutor booking only.",
    tutorAvailability: "offline",
    ecosystemProfile: {
      student: false,
      tutor: false,
      mentor: false,
      universityPartner: false,
    },
    createdAt: existing.createdAt ?? nowServerTs(),
    lastLoginAt: nowServerTs(),
    tutorApplicationStatus: "draft",
    tutoringEligibilityStatus: "ineligible",
    payoutOnboardingStatus: "not_started",
    adminApproval: false,
    tutorStatus: "",
    temporaryPaymentSetupStatus: "missing",
    temporaryPaymentProvider: "Seshly Pay",
    temporaryPaymentMethodId: "",
    temporaryPaymentRegistrationId: "",
    temporaryPaymentProviderReference: "",
    temporaryPaymentAuthorizationCode: "",
    temporaryPaymentAuthorizationReference: "",
    temporaryPaymentPreauthReference: "",
    temporaryPaymentCustomerCode: "",
    temporaryPaymentReusableAuthorizationCode: "",
    temporaryPaymentStatus: "missing",
    temporaryCardBrand: "",
    temporaryCardLast4: "",
    temporaryCardExpMonth: 0,
    temporaryCardExpYear: 0,
    temporaryCardHolder: "Instant Tutor Learner",
    temporaryPaymentScope: "tutor_booking_only",
    temporaryPaymentUpdatedAt: nowServerTs(),
  };
}

export const initializeAccountProfile = secureOnCall<JsonMap, {initialized: true}>(
  {
    region: REGION,
    action: "auth.initialize_profile",
    analyticsEvent: "signup_profile",
    requireVerifiedEmail: false,
    rateLimitProfile: "auth",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "You must be signed in.");
    }
    if (request.auth.token.firebase?.sign_in_provider === "anonymous") {
      throw new HttpsError(
        "failed-precondition",
        "Anonymous users cannot create a full account profile."
      );
    }

    const payload = requireObjectPayload(request.data);
    const fullName = readTrimmedString(payload.fullName, 120);
    const studentNumber = readTrimmedString(payload.studentNumber, 64);
    const university = readTrimmedString(payload.university, 120);
    const levelOfStudy = readTrimmedString(payload.levelOfStudy, 64);
    if (!fullName || !studentNumber || !university || !levelOfStudy) {
      throw new HttpsError(
        "invalid-argument",
        "Profile details are incomplete."
      );
    }

    const profileRef = db.collection("users").doc(request.auth.uid);
    await profileRef.set(
      buildVerifiedStudentDefaults({
        uid: request.auth.uid,
        email: (request.auth.token.email ?? "").toString(),
        emailVerified: request.auth.token.email_verified === true,
        fullName,
        studentNumber,
        university,
        levelOfStudy,
      }),
      {merge: true}
    );

    return {initialized: true};
  }
);

export const syncAccessProfile = secureOnCall<JsonMap, {synced: true}>(
  {
    region: REGION,
    action: "auth.sync_profile",
    analyticsEvent: "verification_sync",
    allowAnonymous: true,
    requireVerifiedEmail: false,
    rateLimitProfile: "auth",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "You must be signed in.");
    }

    const profileRef = db.collection("users").doc(request.auth.uid);
    const existingSnap = await profileRef.get();
    const existing = (existingSnap.data() ?? {}) as JsonMap;
    if (request.auth.token.firebase?.sign_in_provider === "anonymous") {
      await profileRef.set(
        buildInstantTutorDefaults(request.auth.uid, existing),
        {merge: true}
      );
      return {synced: true};
    }

    await profileRef.set({
      uid: request.auth.uid,
      accountType: "student",
      accessTier: "verified_student",
      instantTutorAccess: false,
      accessMode: "verifiedStudent",
      email: (request.auth.token.email ?? "").toString(),
      emailLowercase: (request.auth.token.email ?? "").toString().toLowerCase(),
      emailVerified: request.auth.token.email_verified === true,
      fullName: readTrimmedString(existing.fullName, 120) ||
        readTrimmedString(request.auth.token.name, 120),
      fullNameLowercase:
        (readTrimmedString(existing.fullName, 120) ||
          readTrimmedString(request.auth.token.name, 120)).toLowerCase(),
      ecosystemProfile: {
        ...((existing.ecosystemProfile as JsonMap | undefined) ?? {}),
        student: true,
      },
      createdAt: existing.createdAt ?? nowServerTs(),
      lastLoginAt: nowServerTs(),
      updatedAt: nowServerTs(),
    }, {merge: true});

    return {synced: true};
  }
);
