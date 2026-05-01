import {createHash} from "node:crypto";

export type TutorPayoutVerificationStatus =
  | "not_started"
  | "pending"
  | "verified"
  | "invalid"
  | "failed"
  | "blocked";

export interface SupportedTutorPayoutBank {
  bankCode: string;
  bankName: string;
  countryCode: "ZA";
  currency: "ZAR";
}

export const SUPPORTED_TUTOR_PAYOUT_BANKS: SupportedTutorPayoutBank[] = [
  {
    bankCode: "051001",
    bankName: "Standard Bank",
    countryCode: "ZA",
    currency: "ZAR",
  },
  {
    bankCode: "250655",
    bankName: "First National Bank",
    countryCode: "ZA",
    currency: "ZAR",
  },
  {
    bankCode: "632005",
    bankName: "ABSA",
    countryCode: "ZA",
    currency: "ZAR",
  },
  {
    bankCode: "198765",
    bankName: "Nedbank",
    countryCode: "ZA",
    currency: "ZAR",
  },
  {
    bankCode: "470010",
    bankName: "Capitec",
    countryCode: "ZA",
    currency: "ZAR",
  },
];

export function toTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

export function maskSouthAfricanAccountNumber(accountNumber: string): string {
  const trimmed = accountNumber.replace(/\s+/g, "");
  if (trimmed.length <= 4) {
    return trimmed;
  }
  return `${"*".repeat(Math.max(0, trimmed.length - 4))}${trimmed.slice(-4)}`;
}

export function fingerprintTutorPayoutAccount(
  tutorId: string,
  accountNumber: string
): string {
  const normalized = accountNumber.replace(/\s+/g, "");
  return createHash("sha256")
    .update(`${tutorId}|${normalized}`)
    .digest("hex");
}

export function findSupportedTutorPayoutBank(
  bankCode: string
): SupportedTutorPayoutBank | null {
  return SUPPORTED_TUTOR_PAYOUT_BANKS.find(
    (bank) => bank.bankCode === toTrimmedString(bankCode)
  ) ?? null;
}

export function deriveTutorPayoutVerificationStatus(
  data: Record<string, unknown>
): TutorPayoutVerificationStatus {
  const explicit = toTrimmedString(data.verificationStatus).toLowerCase();
  if (
    explicit === "pending" ||
    explicit === "verified" ||
    explicit === "invalid" ||
    explicit === "failed" ||
    explicit === "blocked"
  ) {
    return explicit;
  }
  if (data.payoutEnabled === true) {
    return "verified";
  }
  const status = toTrimmedString(data.status).toUpperCase();
  if (status === "ACTIVE") {
    return "verified";
  }
  if (status === "DISABLED") {
    return "blocked";
  }
  if (status === "PENDING_VERIFICATION") {
    return "pending";
  }
  return "not_started";
}

export function payoutProfileHasMinimumFields(
  tutorId: string,
  data: Record<string, unknown>
): boolean {
  return toTrimmedString(data.tutorId) === tutorId &&
    toTrimmedString(data.provider).length > 0 &&
    toTrimmedString(data.accountHolderName).length > 0 &&
    toTrimmedString(data.bankName).length > 0 &&
    (
      toTrimmedString(data.accountNumberMasked).length > 0 ||
      toTrimmedString(data.maskedAccountNumber).length > 0
    ) &&
    (
      toTrimmedString(data.bankCode).length > 0 ||
      toTrimmedString(data.branchCode).length > 0
    );
}

export function isVerifiedTutorPayoutProfile(
  tutorId: string,
  data: Record<string, unknown>
): boolean {
  const verificationStatus = deriveTutorPayoutVerificationStatus(data);
  const recipientCode =
    toTrimmedString(data.recipientCode) ||
    toTrimmedString(data.providerBeneficiaryId);
  const payoutEnabled =
    data.payoutEnabled === true ||
    (
      verificationStatus === "verified" &&
      toTrimmedString(data.status).toUpperCase() === "ACTIVE"
    );
  return payoutProfileHasMinimumFields(tutorId, data) &&
    verificationStatus === "verified" &&
    payoutEnabled &&
    recipientCode.length > 0;
}

export function isBlockedTutorPayoutProfile(
  data: Record<string, unknown>
): boolean {
  return deriveTutorPayoutVerificationStatus(data) === "blocked" ||
    toTrimmedString(data.status).toUpperCase() === "DISABLED";
}
