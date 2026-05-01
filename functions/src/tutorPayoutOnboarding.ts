import * as admin from "firebase-admin";
import {HttpsError, onCall} from "./callable";
import {getActivePaymentProvider} from "./payments/providerSelector";
import {buildPayoutProfileSchemaFields} from "./tutoringFirestoreSchema";
import {deriveTutorApprovalSnapshot} from "./tutorApprovalState";
import {
  findSupportedTutorPayoutBank,
  fingerprintTutorPayoutAccount,
  maskSouthAfricanAccountNumber,
  SUPPORTED_TUTOR_PAYOUT_BANKS,
  toTrimmedString,
} from "./tutorPayoutProfileState";

const REGION = "europe-west1";
const COUNTRY_CODE = "ZA";
const CURRENCY = "ZAR";
const PROVIDER = "MOCK_PAYSTACK";

function getDb() {
  return admin.firestore();
}

function nowServerTs() {
  return admin.firestore.FieldValue.serverTimestamp();
}

function sanitizeAccountNumber(value: unknown): string {
  return toTrimmedString(value).replace(/\s+/g, "");
}

function assertTutorCanManagePayoutProfile(
  tutorId: string,
  userData: Record<string, unknown>
): void {
  const snapshot = deriveTutorApprovalSnapshot({userData});
  if (!snapshot.fullAccountTutor) {
    throw new HttpsError(
      "failed-precondition",
      "Guest accounts cannot create tutor payout profiles."
    );
  }
  if (["rejected", "suspended"].includes(snapshot.tutorApplicationStatus)) {
    throw new HttpsError(
      "failed-precondition",
      "Tutor payout onboarding is unavailable from the current tutor application state."
    );
  }
  if (snapshot.tutorApplicationStatus === "draft") {
    throw new HttpsError(
      "failed-precondition",
      "Submit the tutor application before starting payout onboarding."
    );
  }
  if (userData.isDisabled === true) {
    throw new HttpsError(
      "failed-precondition",
      `Tutor ${tutorId} is currently disabled.`
    );
  }
}

async function resolveTutorPayoutProfileRef(tutorId: string) {
  const db = getDb();
  const existingDefaultSnap = await db.collection("tutor_payout_accounts")
    .where("tutorId", "==", tutorId)
    .where("isDefault", "==", true)
    .limit(1)
    .get();
  if (!existingDefaultSnap.empty) {
    return existingDefaultSnap.docs[0].ref;
  }
  return db.collection("tutor_payout_accounts").doc(tutorId);
}

async function updateTutorPayoutReadinessState(params: {
  tutorId: string;
  payoutOnboardingStatus: "pending" | "verified" | "blocked";
  defaultPayoutAccountId?: string | null;
}): Promise<void> {
  const db = getDb();
  const userRef = db.collection("users").doc(params.tutorId);
  const balanceRef = db.collection("tutor_balances").doc(params.tutorId);

  await userRef.set({
    payoutOnboardingStatus: params.payoutOnboardingStatus,
    tutorPayoutsBlocked: params.payoutOnboardingStatus === "blocked",
    payoutsBlocked: params.payoutOnboardingStatus === "blocked",
    blockedFromPayouts: params.payoutOnboardingStatus === "blocked",
    updatedAt: nowServerTs(),
  }, {merge: true});

  if (params.defaultPayoutAccountId) {
    await balanceRef.set({
      defaultPayoutAccountId: params.defaultPayoutAccountId,
      updatedAt: nowServerTs(),
    }, {merge: true});
  }
}

export const getSupportedBanksForTutorPayout = onCall(
  {region: REGION},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }
    const db = getDb();
    const userSnap = await db.collection("users").doc(request.auth.uid).get();
    if (!userSnap.exists) {
      throw new HttpsError("not-found", "Tutor not found.");
    }
    assertTutorCanManagePayoutProfile(request.auth.uid, userSnap.data() ?? {});

    return {
      countryCode: COUNTRY_CODE,
      currency: CURRENCY,
      provider: PROVIDER,
      banks: SUPPORTED_TUTOR_PAYOUT_BANKS,
    };
  }
);

export const submitTutorPayoutDetails = onCall(
  {region: REGION},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }

    const tutorId = request.auth.uid;
    const db = getDb();
    const userSnap = await db.collection("users").doc(tutorId).get();
    if (!userSnap.exists) {
      throw new HttpsError("not-found", "Tutor not found.");
    }
    assertTutorCanManagePayoutProfile(tutorId, userSnap.data() ?? {});

    const bankCode = toTrimmedString(request.data?.bankCode);
    const supportedBank = findSupportedTutorPayoutBank(bankCode);
    if (!supportedBank) {
      throw new HttpsError("invalid-argument", "A supported South African bankCode is required.");
    }

    const accountNumber = sanitizeAccountNumber(request.data?.accountNumber);
    if (!/^\d{6,12}$/.test(accountNumber)) {
      throw new HttpsError(
        "invalid-argument",
        "accountNumber must contain 6 to 12 digits."
      );
    }

    const accountHolderName = toTrimmedString(request.data?.accountHolderName);
    if (!accountHolderName) {
      throw new HttpsError(
        "invalid-argument",
        "accountHolderName is required."
      );
    }

    const profileRef = await resolveTutorPayoutProfileRef(tutorId);
    const existingProfileSnap = await profileRef.get();
    const existingProfileData = existingProfileSnap.data() ?? {};
    const accountNumberMasked = maskSouthAfricanAccountNumber(accountNumber);
    const profileBase = {
      accountId: profileRef.id,
      payoutProfileId: profileRef.id,
      tutorId,
      provider: PROVIDER,
      countryCode: COUNTRY_CODE,
      currency: CURRENCY,
      status: "PENDING_VERIFICATION",
      verificationStatus: "pending",
      bankCode: supportedBank.bankCode,
      branchCode: supportedBank.bankCode,
      bankName: supportedBank.bankName,
      accountNumberMasked,
      maskedAccountNumber: accountNumberMasked,
      accountNumberFingerprint: fingerprintTutorPayoutAccount(tutorId, accountNumber),
      accountHolderName,
      recipientCode: null,
      providerBeneficiaryId: null,
      payoutEnabled: false,
      payoutBlockedReason: "verification_required",
      payoutOnboardingStatus: "pending",
      isDefault: existingProfileData.isDefault !== false,
      providerExecutionReady: false,
      updatedAt: nowServerTs(),
      createdAt: existingProfileData.createdAt ?? nowServerTs(),
      submittedAt: nowServerTs(),
      verifiedAt: null,
      lastValidationReference: null,
      lastValidationStatus: null,
      lastRecipientReference: null,
      lastRecipientStatus: null,
    };

    await profileRef.set({
      ...profileBase,
      ...buildPayoutProfileSchemaFields(profileRef.id, profileBase),
    }, {merge: true});
    await updateTutorPayoutReadinessState({
      tutorId,
      payoutOnboardingStatus: "pending",
      defaultPayoutAccountId: profileRef.id,
    });

    return {
      payoutProfileId: profileRef.id,
      tutorId,
      bankCode: supportedBank.bankCode,
      bankName: supportedBank.bankName,
      accountNumberMasked: profileBase.accountNumberMasked,
      accountHolderName,
      verificationStatus: "pending",
      recipientCode: null,
      payoutEnabled: false,
      payoutBlockedReason: "verification_required",
    };
  }
);

export const verifyTutorPayoutProfile = onCall(
  {region: REGION},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }

    const tutorId = request.auth.uid;
    const db = getDb();
    const userSnap = await db.collection("users").doc(tutorId).get();
    if (!userSnap.exists) {
      throw new HttpsError("not-found", "Tutor not found.");
    }
    assertTutorCanManagePayoutProfile(tutorId, userSnap.data() ?? {});

    const payoutProfileId =
      toTrimmedString(request.data?.payoutProfileId) || tutorId;
    const profileRef = db.collection("tutor_payout_accounts").doc(payoutProfileId);
    const profileSnap = await profileRef.get();
    if (!profileSnap.exists) {
      throw new HttpsError("not-found", "Tutor payout profile not found.");
    }
    const profileData = profileSnap.data() ?? {};
    if (toTrimmedString(profileData.tutorId) !== tutorId) {
      throw new HttpsError(
        "permission-denied",
        "This payout profile does not belong to the current tutor."
      );
    }

    const accountNumber = sanitizeAccountNumber(request.data?.accountNumber);
    if (!/^\d{6,12}$/.test(accountNumber)) {
      throw new HttpsError(
        "invalid-argument",
        "accountNumber must contain 6 to 12 digits."
      );
    }
    const accountFingerprint = fingerprintTutorPayoutAccount(tutorId, accountNumber);
    if (
      toTrimmedString(profileData.accountNumberFingerprint).length > 0 &&
      toTrimmedString(profileData.accountNumberFingerprint) !== accountFingerprint
    ) {
      throw new HttpsError(
        "failed-precondition",
        "accountNumber does not match the submitted payout profile."
      );
    }

    const provider = getActivePaymentProvider();
    const bankCode =
      toTrimmedString(profileData.bankCode) ||
      toTrimmedString(profileData.branchCode);
    const accountHolderName = toTrimmedString(profileData.accountHolderName);
    const validationResult = await provider.validateSouthAfricanAccount({
      accountName: accountHolderName,
      accountNumber,
      bankCode,
      idempotencyKey: `payout_validate_${profileRef.id}_${accountFingerprint}`,
      metadata: {
        tutorId,
        payoutProfileId: profileRef.id,
      },
    });

    if (!validationResult.success || !validationResult.isValid) {
      const failedPatch = {
        verificationStatus: "invalid",
        status: "PENDING_VERIFICATION",
        recipientCode: null,
        providerBeneficiaryId: null,
        payoutEnabled: false,
        payoutBlockedReason: validationResult.message || "account_validation_failed",
        lastValidationReference: validationResult.reference,
        lastValidationStatus: validationResult.status,
        verifiedAt: null,
        updatedAt: nowServerTs(),
      };
      await profileRef.set({
        ...failedPatch,
        ...buildPayoutProfileSchemaFields(profileRef.id, {
          ...profileData,
          ...failedPatch,
        }),
      }, {merge: true});
      await updateTutorPayoutReadinessState({
        tutorId,
        payoutOnboardingStatus: "pending",
        defaultPayoutAccountId: profileRef.id,
      });
      return {
        payoutProfileId: profileRef.id,
        tutorId,
        verificationStatus: "invalid",
        recipientCode: null,
        payoutEnabled: false,
        payoutBlockedReason: failedPatch.payoutBlockedReason,
      };
    }

    const recipientResult = await provider.createTransferRecipient({
      tutorId,
      accountName: validationResult.accountName,
      accountNumber,
      bankCode: validationResult.bankCode,
      currency: CURRENCY,
      countryCode: COUNTRY_CODE,
      idempotencyKey: `payout_recipient_${profileRef.id}_${accountFingerprint}`,
      metadata: {
        tutorId,
        payoutProfileId: profileRef.id,
      },
    });

    if (!recipientResult.success || !recipientResult.recipientCode) {
      const failedPatch = {
        verificationStatus: "failed",
        status: "PENDING_VERIFICATION",
        recipientCode: null,
        providerBeneficiaryId: null,
        payoutEnabled: false,
        payoutBlockedReason: recipientResult.message || "recipient_creation_failed",
        lastValidationReference: validationResult.reference,
        lastRecipientReference: recipientResult.reference,
        lastRecipientStatus: recipientResult.status,
        verifiedAt: null,
        updatedAt: nowServerTs(),
      };
      await profileRef.set({
        ...failedPatch,
        ...buildPayoutProfileSchemaFields(profileRef.id, {
          ...profileData,
          ...failedPatch,
        }),
      }, {merge: true});
      await updateTutorPayoutReadinessState({
        tutorId,
        payoutOnboardingStatus: "pending",
        defaultPayoutAccountId: profileRef.id,
      });
      return {
        payoutProfileId: profileRef.id,
        tutorId,
        verificationStatus: "failed",
        recipientCode: null,
        payoutEnabled: false,
        payoutBlockedReason: failedPatch.payoutBlockedReason,
      };
    }

    const verifiedPatch = {
      provider: PROVIDER,
      status: "ACTIVE",
      verificationStatus: "verified",
      bankCode: validationResult.bankCode,
      branchCode: validationResult.bankCode,
      bankName: validationResult.bankName,
      accountNumberMasked: validationResult.maskedAccountNumber,
      maskedAccountNumber: validationResult.maskedAccountNumber,
      accountNumberFingerprint: accountFingerprint,
      accountHolderName: validationResult.accountName,
      recipientCode: recipientResult.recipientCode,
      providerBeneficiaryId: recipientResult.recipientCode,
      payoutEnabled: true,
      payoutBlockedReason: null,
      payoutOnboardingStatus: "verified",
      lastValidationReference: validationResult.reference,
      lastValidationStatus: validationResult.status,
      lastRecipientReference: recipientResult.reference,
      lastRecipientStatus: recipientResult.status,
      verifiedAt: nowServerTs(),
      updatedAt: nowServerTs(),
    };
    await profileRef.set({
      ...verifiedPatch,
      ...buildPayoutProfileSchemaFields(profileRef.id, {
        ...profileData,
        ...verifiedPatch,
      }),
    }, {merge: true});
    await updateTutorPayoutReadinessState({
      tutorId,
      payoutOnboardingStatus: "verified",
      defaultPayoutAccountId: profileRef.id,
    });

    return {
      payoutProfileId: profileRef.id,
      tutorId,
      bankCode: validationResult.bankCode,
      bankName: validationResult.bankName,
      accountNumberMasked: validationResult.maskedAccountNumber,
      accountHolderName: validationResult.accountName,
      verificationStatus: "verified",
      recipientCode: recipientResult.recipientCode,
      payoutEnabled: true,
      payoutBlockedReason: null,
      provider: PROVIDER,
      mockProviderVerified: true,
    };
  }
);
