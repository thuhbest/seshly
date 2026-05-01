import {onDocumentUpdated} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";

const db = admin.firestore();
const REGION = "europe-west1";
const TUTORING_COLOR_HEX = 0xFF00C09E;
const TERMINAL_REQUEST_STATUSES = new Set([
  "declined",
  "cancelled",
  "expired",
  "payment_failed",
]);

function eventDoc(userId: string, requestId: string) {
  return db
    .collection("users")
    .doc(userId)
    .collection("calendarEvents")
    .doc(`tutor_request_${requestId}`);
}

export const ontutorrequestcalendarupdated = onDocumentUpdated({
  document: "tutor_requests/{requestId}",
  region: REGION,
}, async (event) => {
  const before = event.data?.before.data() ?? {};
  const after = event.data?.after.data() ?? {};
  const requestId = (event.params.requestId ?? "").toString();
  if (!requestId) return;

  const tutorId = (after.tutorId ?? before.tutorId ?? "").toString();
  const studentId = (after.studentId ?? before.studentId ?? "").toString();
  const beforeStatus = (before.status ?? "").toString();
  const afterStatus = (after.status ?? "").toString();
  const startAt = after.scheduledAt as admin.firestore.Timestamp | undefined;
  const endAt = after.scheduledEnd as admin.firestore.Timestamp | undefined;

  const refs = [tutorId, studentId]
    .filter((value) => value.trim().isNotEmpty)
    .map((userId) => eventDoc(userId, requestId));

  if (refs.length === 0) return;

  if (TERMINAL_REQUEST_STATUSES.has(afterStatus)) {
    await Promise.all(refs.map((ref) => ref.delete().catch(() => undefined)));
    return;
  }

  const shouldSyncAcceptedEvent =
    afterStatus === "accepted" &&
    startAt instanceof admin.firestore.Timestamp &&
    endAt instanceof admin.firestore.Timestamp &&
    (
      beforeStatus !== afterStatus ||
      before.scheduledAt !== after.scheduledAt ||
      before.scheduledEnd !== after.scheduledEnd
    );

  if (!shouldSyncAcceptedEvent) return;

  const subject = (after.subject ?? "Tutoring").toString();
  const topic = (after.topic ?? "").toString();
  const payload: Record<string, unknown> = {
    title: topic ? `Tutoring: ${subject} (${topic})` : `Tutoring: ${subject}`,
    start: startAt,
    end: endAt,
    location: "Seshly Tutoring",
    type: "Tutoring",
    colorHex: TUTORING_COLOR_HEX,
    source: "tutor_request",
    requestId,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (beforeStatus !== "accepted") {
    payload.createdAt = admin.firestore.FieldValue.serverTimestamp();
  }

  await Promise.all(refs.map((ref) => ref.set(payload, {merge: true})));
});
