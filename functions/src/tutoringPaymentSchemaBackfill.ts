import * as admin from "firebase-admin";
import {HttpsError, onCall} from "./callable";
import {assertPlatformAdmin, toTrimmedString} from "./tutorApprovalState";
import {
  buildBookingSchemaFields,
  buildCaptureSchemaFields,
  buildDisputeDoc,
  buildGuestTutoringCustomerDoc,
  buildPaymentAuthorizationSchemaFields,
  buildPaymentSessionSchemaFields,
  buildPayoutBatchSchemaFields,
  buildPayoutProfileSchemaFields,
  buildPayoutRecordSchemaFields,
  buildRatingSchemaFields,
  buildSessionSchemaFields,
  buildSettlementSchemaFields,
  buildTutorPayableDoc,
} from "./tutoringFirestoreSchema";

const db = admin.firestore();
const REGION = "europe-west1";

interface GuestCustomerAggregate {
  bookingCount: number;
  lastBookingId: string | null;
  lastBookingAt: unknown;
}

export interface TutoringPaymentSchemaBackfillResult {
  dryRun: boolean;
  normalizedBookings: number;
  normalizedSessions: number;
  normalizedPaymentSessions: number;
  normalizedAuthorizations: number;
  normalizedCaptures: number;
  normalizedSettlements: number;
  normalizedTutorPayables: number;
  normalizedPayoutBatches: number;
  normalizedPayoutRecords: number;
  normalizedPayoutProfiles: number;
  normalizedGuestCustomers: number;
  normalizedDisputes: number;
  normalizedRatings: number;
}

async function forEachCollectionDoc(
  collectionName: string,
  handler: (
    doc: FirebaseFirestore.QueryDocumentSnapshot
  ) => Promise<void>
): Promise<void> {
  let lastId = "";
  while (true) {
    let query = db.collection(collectionName)
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(100);
    if (lastId) {
      query = query.startAfter(lastId);
    }
    const snap = await query.get();
    if (snap.empty) {
      return;
    }
    for (const doc of snap.docs) {
      lastId = doc.id;
      await handler(doc);
    }
  }
}

async function loadTemporaryPaymentData(
  userId: string,
  userData: Record<string, unknown>
): Promise<Record<string, unknown>> {
  const methodId = toTrimmedString(userData.temporaryPaymentMethodId);
  if (!methodId) {
    return {};
  }
  const methodSnap = await db
    .collection("users")
    .doc(userId)
    .collection("temporary_payment_methods")
    .doc(methodId)
    .get();
  return methodSnap.data() ?? {};
}

export async function runTutoringPaymentSchemaBackfillJob(params: {
  dryRun?: boolean;
} = {}): Promise<TutoringPaymentSchemaBackfillResult> {
  const dryRun = params.dryRun === true;
  const result: TutoringPaymentSchemaBackfillResult = {
    dryRun,
    normalizedBookings: 0,
    normalizedSessions: 0,
    normalizedPaymentSessions: 0,
    normalizedAuthorizations: 0,
    normalizedCaptures: 0,
    normalizedSettlements: 0,
    normalizedTutorPayables: 0,
    normalizedPayoutBatches: 0,
    normalizedPayoutRecords: 0,
    normalizedPayoutProfiles: 0,
    normalizedGuestCustomers: 0,
    normalizedDisputes: 0,
    normalizedRatings: 0,
  };
  const guestCustomerMap = new Map<string, GuestCustomerAggregate>();

  await forEachCollectionDoc("tutor_requests", async (doc) => {
    const data = doc.data() ?? {};
    const guestCustomerId = toTrimmedString(data.guestTutoringCustomerId) ||
      (data.guestTutoringMode === true ? toTrimmedString(data.studentId) : "");
    if (guestCustomerId) {
      const aggregate = guestCustomerMap.get(guestCustomerId) ?? {
        bookingCount: 0,
        lastBookingId: null,
        lastBookingAt: null,
      };
      aggregate.bookingCount += 1;
      aggregate.lastBookingId = doc.id;
      aggregate.lastBookingAt = data.scheduledAt ?? aggregate.lastBookingAt;
      guestCustomerMap.set(guestCustomerId, aggregate);
    }
    result.normalizedBookings += 1;
    if (!dryRun) {
      await doc.ref.set(buildBookingSchemaFields(doc.id, data), {merge: true});
    }
  });

  await forEachCollectionDoc("session_payment_intents", async (doc) => {
    result.normalizedPaymentSessions += 1;
    if (!dryRun) {
      await doc.ref.set(
        buildPaymentSessionSchemaFields(doc.id, doc.data() ?? {}),
        {merge: true}
      );
    }
  });

  await forEachCollectionDoc("tutoring_sessions", async (doc) => {
    result.normalizedSessions += 1;
    if (!dryRun) {
      await doc.ref.set(buildSessionSchemaFields(doc.id, doc.data() ?? {}), {
        merge: true,
      });
    }
  });

  await forEachCollectionDoc("payment_authorizations", async (doc) => {
    result.normalizedAuthorizations += 1;
    if (!dryRun) {
      await doc.ref.set(
        buildPaymentAuthorizationSchemaFields(doc.id, doc.data() ?? {}),
        {merge: true}
      );
    }
  });

  await forEachCollectionDoc("payment_captures", async (doc) => {
    result.normalizedCaptures += 1;
    if (!dryRun) {
      await doc.ref.set(buildCaptureSchemaFields(doc.id, doc.data() ?? {}), {
        merge: true,
      });
    }
  });

  await forEachCollectionDoc("tutor_session_settlements", async (doc) => {
    const data = doc.data() ?? {};
    result.normalizedSettlements += 1;
    result.normalizedTutorPayables += 1;
    if (!dryRun) {
      await doc.ref.set(buildSettlementSchemaFields(doc.id, data), {merge: true});
      await db.collection("tutor_payables").doc(doc.id).set(
        buildTutorPayableDoc(doc.id, {
          settlementId: doc.id,
          ...data,
        }),
        {merge: true}
      );

      const heldAmountZar = Number(data.disputeHeldAmountZar ?? 0);
      const payoutEligibilityStatus = toTrimmedString(data.payoutEligibilityStatus)
        .toUpperCase();
      if (heldAmountZar > 0 || payoutEligibilityStatus === "HELD") {
        result.normalizedDisputes += 1;
        await db.collection("disputes").doc(doc.id).set(
          buildDisputeDoc(doc.id, {
            settlementId: doc.id,
            ...data,
          }),
          {merge: true}
        );
      }
    }
  });

  await forEachCollectionDoc("tutor_payout_batches", async (doc) => {
    result.normalizedPayoutBatches += 1;
    if (!dryRun) {
      await doc.ref.set(buildPayoutBatchSchemaFields(doc.id, doc.data() ?? {}), {
        merge: true,
      });
    }
  });

  await forEachCollectionDoc("tutor_payouts", async (doc) => {
    result.normalizedPayoutRecords += 1;
    if (!dryRun) {
      await doc.ref.set(buildPayoutRecordSchemaFields(doc.id, doc.data() ?? {}), {
        merge: true,
      });
    }
  });

  await forEachCollectionDoc("tutor_payout_accounts", async (doc) => {
    result.normalizedPayoutProfiles += 1;
    if (!dryRun) {
      await doc.ref.set(buildPayoutProfileSchemaFields(doc.id, doc.data() ?? {}), {
        merge: true,
      });
    }
  });

  await forEachCollectionDoc("tutor_session_reviews", async (doc) => {
    result.normalizedRatings += 1;
    if (!dryRun) {
      await doc.ref.set(buildRatingSchemaFields(doc.id, doc.data() ?? {}), {
        merge: true,
      });
    }
  });

  await forEachCollectionDoc("users", async (doc) => {
    const userData = doc.data() ?? {};
    const guestCustomerId = doc.id;
    const isGuest =
      toTrimmedString(userData.accountType).toLowerCase() === "instant_tutor" ||
      toTrimmedString(userData.accessTier).toLowerCase() === "instant_tutor" ||
      toTrimmedString(userData.accessMode).toLowerCase() === "instanttutor" ||
      userData.instantTutorAccess === true ||
      toTrimmedString(userData.temporaryPaymentMethodId).length > 0 ||
      guestCustomerMap.has(guestCustomerId);

    if (!isGuest) {
      return;
    }

    result.normalizedGuestCustomers += 1;
    if (!dryRun) {
      const temporaryPaymentData = await loadTemporaryPaymentData(guestCustomerId, userData);
      const aggregate = guestCustomerMap.get(guestCustomerId);
      await db.collection("guest_tutoring_customers").doc(guestCustomerId).set(
        buildGuestTutoringCustomerDoc({
          customerId: guestCustomerId,
          userData,
          temporaryPaymentData,
          tutoringBookingCount: aggregate?.bookingCount ?? 0,
          lastBookingId: aggregate?.lastBookingId ?? null,
          lastBookingAt: aggregate?.lastBookingAt ?? null,
        }),
        {merge: true}
      );
    }
  });

  return result;
}

export const runTutoringPaymentSchemaBackfill = onCall(
  {region: REGION, timeoutSeconds: 540},
  async (request): Promise<TutoringPaymentSchemaBackfillResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in.");
    }
    assertPlatformAdmin(request.auth);

    return runTutoringPaymentSchemaBackfillJob({
      dryRun: request.data?.dryRun === true,
    });
  }
);
