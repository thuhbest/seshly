import * as admin from "firebase-admin";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { prepareSessionRuntime, attemptAutoStart } from "./tutorSessions";

const db = admin.firestore();

export const autoStartScheduledSessions = onSchedule(
  {
    schedule: "every 1 minutes",
    region: "europe-west1",
  },
  async () => {
    const now = new Date();

    // Find sessions that should be prepared
    const sessionsToPrepare = await db.collection("tutoring_sessions")
      .where("status", "==", "SCHEDULED")
      .where("scheduledStartAt", "<=", now)
      .get();

    // Prepare sessions
    for (const doc of sessionsToPrepare.docs) {
      try {
        await prepareSessionRuntime(doc.id);
      } catch (error) {
        console.error(`Failed to prepare session ${doc.id}:`, error);
      }
    }

    // Find sessions that should auto-start
    const sessionsToStart = await db.collection("tutoring_sessions")
      .where("status", "in", ["PREPARING", "SCHEDULED"])
      .where("autoStartEnabled", "==", true)
      .get();

    // Attempt auto-start
    for (const doc of sessionsToStart.docs) {
      try {
        await attemptAutoStart(doc.id);
      } catch (error) {
        console.error(`Failed to auto-start session ${doc.id}:`, error);
      }
    }
  }
);

// Clean up old missed sessions
export const cleanupMissedSessions = onSchedule(
  {
    schedule: "every 24 hours",
    region: "europe-west1",
  },
  async () => {
    const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000); // 24 hours ago

    const missedSessions = await db.collection("tutoring_sessions")
      .where("status", "==", "MISSED")
      .where("scheduledStartAt", "<", cutoff)
      .get();

    for (const doc of missedSessions.docs) {
      try {
        await db.collection("tutoring_sessions").doc(doc.id).update({
          status: "EXPIRED",
          expiredAt: admin.firestore.Timestamp.now(),
        });
      } catch (error) {
        console.error(`Failed to expire session ${doc.id}:`, error);
      }
    }
  }
);