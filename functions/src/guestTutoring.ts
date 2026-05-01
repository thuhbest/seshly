import {createHash} from "node:crypto";
import * as admin from "firebase-admin";
import {HttpsError, onCall} from "./callable";
import {buildGuestTutoringCustomerDoc} from "./tutoringFirestoreSchema";

const db = admin.firestore();
const REGION = "europe-west1";
const GUEST_SESSION_TOKEN_TTL_MS = 2 * 60 * 60 * 1000;

interface GuestTutoringCustomerPayload {
  firstName?: unknown;
  email?: unknown;
  phone?: unknown;
}

interface GuestTutoringCustomerResult {
  guestId: string;
  firstName: string;
  email: string | null;
  phone: string | null;
  isGuest: true;
  status: string;
}

function toTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function normalizeEmail(value: unknown): string | null {
  const email = toTrimmedString(value).toLowerCase();
  return email || null;
}

function normalizePhone(value: unknown): string | null {
  const phone = toTrimmedString(value);
  return phone || null;
}

function deriveFirstName(params: {
  payloadFirstName?: unknown;
  existingData?: Record<string, unknown>;
}): string {
  const payloadName = toTrimmedString(params.payloadFirstName);
  if (payloadName) {
    return payloadName;
  }

  const existingData = params.existingData ?? {};
  const existingFirstName = toTrimmedString(existingData.firstName);
  if (existingFirstName) {
    return existingFirstName;
  }

  const fullName = toTrimmedString(
    existingData.fullName || existingData.displayName
  );
  if (!fullName) {
    return "Guest";
  }
  return fullName.split(/\s+/)[0] || "Guest";
}

export function isAnonymousTutoringGuest(
  auth: {token?: Record<string, unknown>} | null | undefined
): boolean {
  const firebaseToken =
    (auth?.token?.firebase as Record<string, unknown> | undefined) ?? {};
  return toTrimmedString(firebaseToken.sign_in_provider).toLowerCase() ===
    "anonymous";
}

export function isGuestTutoringBooking(
  data: Record<string, unknown>
): boolean {
  return data.guestTutoringMode === true ||
    toTrimmedString(data.payerType).toLowerCase() === "guest" ||
    toTrimmedString(data.studentAccountType).toLowerCase() === "instant_tutor" ||
    toTrimmedString(data.studentAccessTier).toLowerCase() === "instant_tutor";
}

export function guestTutoringCustomerRef(
  guestId: string
): admin.firestore.DocumentReference {
  return db.collection("guest_tutoring_customers").doc(guestId);
}

export function assertGuestTutoringCustomerActive(
  guestData: Record<string, unknown>,
  guestId: string
): void {
  const status = toTrimmedString(guestData.status).toLowerCase();
  const storedGuestId =
    toTrimmedString(guestData.guestId) ||
    toTrimmedString(guestData.guestTutoringCustomerId) ||
    toTrimmedString(guestData.studentId);

  if (storedGuestId && storedGuestId !== guestId) {
    throw new HttpsError(
      "permission-denied",
      "Guest tutoring identity does not match the booking participant."
    );
  }
  if (guestData.isGuest !== true && storedGuestId !== guestId) {
    throw new HttpsError(
      "failed-precondition",
      "Guest tutoring identity is missing."
    );
  }
  if (status && status !== "active") {
    throw new HttpsError(
      "failed-precondition",
      "Guest tutoring identity is not active."
    );
  }
}

export function assertGuestTutoringCustomerPaymentReady(
  guestData: Record<string, unknown>,
  guestId: string
): void {
  assertGuestTutoringCustomerActive(guestData, guestId);

  const paymentStatus = toTrimmedString(
    guestData.temporaryPaymentSetupStatus
  ).toLowerCase();
  const registrationId = toTrimmedString(
    guestData.temporaryPaymentRegistrationId
  );
  const providerReference = toTrimmedString(
    guestData.temporaryPaymentProviderReference
  );

  if (paymentStatus !== "ready" || !registrationId || !providerReference) {
    throw new HttpsError(
      "failed-precondition",
      "Guest tutoring payment setup is not ready for authorization."
    );
  }
}

export async function touchGuestTutoringCustomer(
  guestId: string,
  patch: Record<string, unknown> = {}
): Promise<void> {
  await guestTutoringCustomerRef(guestId).set({
    guestId,
    guestTutoringCustomerId: guestId,
    studentId: guestId,
    isGuest: true,
    accountType: "instant_tutor",
    accessTier: "instant_tutor",
    accessMode: "instantTutor",
    instantTutorAccess: true,
    status: "active",
    lastUsedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    ...patch,
  }, {merge: true});
}

export async function recordGuestTutoringSessionToken(params: {
  bookingId: string;
  sessionId: string;
  guestId: string;
  participantRole: string;
  roomName: string;
  livekitUrl: string;
  token: string;
  joinGrantId: string;
  expiresAt?: Date;
}): Promise<{tokenId: string; expiresAtIso: string}> {
  const expiresAt = params.expiresAt ??
    new Date(Date.now() + GUEST_SESSION_TOKEN_TTL_MS);
  const tokenId = `gst_${params.bookingId}_${params.guestId}_${params.joinGrantId.slice(0, 12)}`;
  const tokenHash = createHash("sha256")
    .update(params.token)
    .digest("hex");

  await db.collection("guest_tutoring_session_tokens").doc(tokenId).set({
    guestSessionTokenId: tokenId,
    guestId: params.guestId,
    bookingId: params.bookingId,
    sessionId: params.sessionId,
    joinGrantId: params.joinGrantId,
    participantRole: params.participantRole,
    roomName: params.roomName,
    livekitUrl: params.livekitUrl,
    tokenHash,
    status: "issued",
    tutoringPaymentRail: "TUTORING",
    expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
    issuedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  await touchGuestTutoringCustomer(params.guestId, {
    lastSessionBookingId: params.bookingId,
    lastSessionId: params.sessionId,
  });

  return {
    tokenId,
    expiresAtIso: expiresAt.toISOString(),
  };
}

function buildGuestCustomerUpsert(params: {
  guestId: string;
  payload: GuestTutoringCustomerPayload;
  existingData?: Record<string, unknown>;
}) {
  const existingData = params.existingData ?? {};
  const firstName = deriveFirstName({
    payloadFirstName: params.payload.firstName,
    existingData,
  });
  const email =
    normalizeEmail(params.payload.email) ??
    normalizeEmail(existingData.email);
  const phone =
    normalizePhone(params.payload.phone) ??
    normalizePhone(existingData.phone);

  return {
    guestId: params.guestId,
    firstName,
    email,
    phone,
    isGuest: true,
    accountType: "instant_tutor",
    accessTier: "instant_tutor",
    accessMode: "instantTutor",
    instantTutorAccess: true,
    status: "active",
    lastUsedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

export const createGuestTutoringCustomer = onCall(
  {region: REGION},
  async (request): Promise<GuestTutoringCustomerResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }
    if (!isAnonymousTutoringGuest(request.auth)) {
      throw new HttpsError(
        "failed-precondition",
        "Guest tutoring customer creation is only available in guest mode."
      );
    }

    const guestId = request.auth.uid;
    const guestRef = guestTutoringCustomerRef(guestId);
    const payload = (request.data ?? {}) as GuestTutoringCustomerPayload;

    return db.runTransaction(async (tx) => {
      const guestSnap = await tx.get(guestRef);
      const existingData = guestSnap.data() ?? {};
      const upsert = buildGuestCustomerUpsert({
        guestId,
        payload,
        existingData,
      });

      tx.set(guestRef, buildGuestTutoringCustomerDoc({
        customerId: guestId,
        userData: {
          ...existingData,
          ...upsert,
        },
        temporaryPaymentData: existingData,
        tutoringBookingCount: Math.max(
          0,
          Number(existingData.tutoringBookingCount ?? 0)
        ),
        lastBookingId: toTrimmedString(existingData.lastBookingId) || null,
        lastBookingAt: existingData.lastBookingAt ?? null,
        lastUsedAt: admin.firestore.FieldValue.serverTimestamp(),
      }), {merge: true});

      return {
        guestId,
        firstName: upsert.firstName,
        email: upsert.email,
        phone: upsert.phone,
        isGuest: true as const,
        status: "active",
      };
    });
  }
);

export const updateGuestTutoringCustomer = onCall(
  {region: REGION},
  async (request): Promise<GuestTutoringCustomerResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }
    if (!isAnonymousTutoringGuest(request.auth)) {
      throw new HttpsError(
        "failed-precondition",
        "Guest tutoring profile updates are only available in guest mode."
      );
    }

    const guestId = request.auth.uid;
    const guestRef = guestTutoringCustomerRef(guestId);
    const payload = (request.data ?? {}) as GuestTutoringCustomerPayload;

    return db.runTransaction(async (tx) => {
      const guestSnap = await tx.get(guestRef);
      const existingData = guestSnap.data() ?? {};
      const upsert = buildGuestCustomerUpsert({
        guestId,
        payload,
        existingData,
      });

      tx.set(guestRef, buildGuestTutoringCustomerDoc({
        customerId: guestId,
        userData: {
          ...existingData,
          ...upsert,
        },
        temporaryPaymentData: existingData,
        tutoringBookingCount: Math.max(
          0,
          Number(existingData.tutoringBookingCount ?? 0)
        ),
        lastBookingId: toTrimmedString(existingData.lastBookingId) || null,
        lastBookingAt: existingData.lastBookingAt ?? null,
        lastUsedAt: admin.firestore.FieldValue.serverTimestamp(),
      }), {merge: true});

      return {
        guestId,
        firstName: upsert.firstName,
        email: upsert.email,
        phone: upsert.phone,
        isGuest: true as const,
        status: "active",
      };
    });
  }
);
