import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {SecretManagerServiceClient} from "@google-cloud/secret-manager";
import {RoomServiceClient} from "livekit-server-sdk";

const db = admin.firestore();
const secretClient = new SecretManagerServiceClient();

const ROOM_CLOSE_LOCK_MS = 30 * 1000;
const LIVEKIT_ROOM_PREFIX = "tutor-";

interface ForceEndRoomState {
  alreadyClosed: boolean;
  roomName: string;
  shouldCallLiveKit: boolean;
  bookingId: string;
  paymentIntentId: string;
}

export interface ForceEndRoomResult {
  sessionId: string;
  roomName: string;
  alreadyClosed: boolean;
  closed: boolean;
  livekitAction: "deleted" | "not_found" | "skipped";
}

function toTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function timestampToDate(value: unknown): Date | null {
  if (value instanceof admin.firestore.Timestamp) {
    return value.toDate();
  }
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return value;
  }
  if (typeof value === "string" || typeof value === "number") {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  return null;
}

function roomNameForSession(sessionId: string): string {
  return `${LIVEKIT_ROOM_PREFIX}${sessionId}`;
}

let liveKitEnvLoaded = false;

async function readSecretValue(name: string): Promise<string> {
  const projectId =
    process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "";
  if (!projectId) return "";

  const [version] = await secretClient.accessSecretVersion({
    name: `projects/${projectId}/secrets/${name}/versions/latest`,
  });
  return version.payload?.data?.toString() || "";
}

async function ensureLiveKitEnv(): Promise<void> {
  if (liveKitEnvLoaded) return;

  const [url, apiKey, apiSecret] = await Promise.all([
    process.env.LIVEKIT_URL || readSecretValue("livekit_url"),
    process.env.LIVEKIT_API_KEY || readSecretValue("livekit_api_key"),
    process.env.LIVEKIT_API_SECRET || readSecretValue("livekit_api_secret"),
  ]);

  if (url) process.env.LIVEKIT_URL = url;
  if (apiKey) process.env.LIVEKIT_API_KEY = apiKey;
  if (apiSecret) process.env.LIVEKIT_API_SECRET = apiSecret;
  liveKitEnvLoaded = true;
}

async function liveKitClient(): Promise<RoomServiceClient | null> {
  await ensureLiveKitEnv();
  const url = process.env.LIVEKIT_URL || "";
  const apiKey = process.env.LIVEKIT_API_KEY || "";
  const apiSecret = process.env.LIVEKIT_API_SECRET || "";
  if (!url || !apiKey || !apiSecret) {
    logger.warn("forceEndRoom skipped because LiveKit is not configured");
    return null;
  }
  return new RoomServiceClient(url, apiKey, apiSecret);
}

function isRoomMissingError(error: unknown): boolean {
  const message = error instanceof Error ? error.message.toLowerCase() : "";
  return message.includes("not found") ||
    message.includes("room does not exist") ||
    message.includes("requested room does not exist");
}

async function prepareRoomClose(
  sessionId: string,
  now: Date
): Promise<ForceEndRoomState> {
  const sessionRef = db.collection("tutoring_sessions").doc(sessionId);

  return db.runTransaction(async (tx) => {
    const sessionSnap = await tx.get(sessionRef);
    if (!sessionSnap.exists) {
      throw new Error(`Tutoring session ${sessionId} was not found.`);
    }

    const sessionData = sessionSnap.data() ?? {};
    const roomName =
      toTrimmedString(sessionData.roomName) || roomNameForSession(sessionId);
    const bookingId = toTrimmedString(sessionData.bookingId) || sessionId;
    const paymentIntentId =
      toTrimmedString(sessionData.paymentIntentId) || bookingId;
    const roomStatus = toTrimmedString(sessionData.roomStatus).toUpperCase();
    const roomClosedAt = timestampToDate(sessionData.roomClosedAt);
    const lockExpiry = timestampToDate(sessionData.roomCloseLockExpiresAt);

    if (roomStatus === "CLOSED" || roomClosedAt) {
      return {
        alreadyClosed: true,
        roomName,
        shouldCallLiveKit: false,
        bookingId,
        paymentIntentId,
      };
    }

    if (roomStatus === "CLOSING" && lockExpiry && lockExpiry.getTime() > now.getTime()) {
      return {
        alreadyClosed: false,
        roomName,
        shouldCallLiveKit: false,
        bookingId,
        paymentIntentId,
      };
    }

    tx.set(sessionRef, {
      roomName,
      roomStatus: "CLOSING",
      roomTerminationStatus: "closing",
      roomCloseRequestedAt: admin.firestore.FieldValue.serverTimestamp(),
      roomCloseAttemptCount: admin.firestore.FieldValue.increment(1),
      roomCloseLockExpiresAt: admin.firestore.Timestamp.fromDate(
        new Date(now.getTime() + ROOM_CLOSE_LOCK_MS)
      ),
      roomCloseError: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    return {
      alreadyClosed: false,
      roomName,
      shouldCallLiveKit: true,
      bookingId,
      paymentIntentId,
    };
  });
}

async function markRoomClosed(params: {
  sessionId: string;
  bookingId: string;
  paymentIntentId: string;
  roomName: string;
  livekitAction: "deleted" | "not_found" | "skipped";
}): Promise<void> {
  const sessionRef = db.collection("tutoring_sessions").doc(params.sessionId);
  const bookingRef = db.collection("tutor_requests").doc(params.bookingId);
  const paymentIntentRef = db
    .collection("session_payment_intents")
    .doc(params.paymentIntentId);

  await db.runTransaction(async (tx) => {
    const sessionSnap = await tx.get(sessionRef);
    if (!sessionSnap.exists) return;
    const sessionData = sessionSnap.data() ?? {};
    const roomClosedAt = timestampToDate(sessionData.roomClosedAt);
    if (roomClosedAt) return;

    tx.set(sessionRef, {
      roomName: params.roomName,
      roomStatus: "CLOSED",
      roomTerminationStatus: "closed",
      roomClosedAt: admin.firestore.FieldValue.serverTimestamp(),
      roomCloseLockExpiresAt: admin.firestore.FieldValue.delete(),
      roomClosedBySystem: true,
      roomCloseResult: params.livekitAction,
      joinedParticipantCount: 0,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    tx.set(bookingRef, {
      sessionRoomStatus: "closed",
      roomTerminationStatus: "closed",
      sessionRoomClosedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    tx.set(paymentIntentRef, {
      sessionRoomStatus: "closed",
      roomTerminationStatus: "closed",
      sessionRoomClosedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  });
}

async function markRoomCloseFailure(sessionId: string, error: unknown): Promise<void> {
  const sessionRef = db.collection("tutoring_sessions").doc(sessionId);
  await sessionRef.set({
    roomStatus: "CLOSING",
    roomTerminationStatus: "retryable_error",
    roomCloseError: error instanceof Error ? error.message : "Room close failed.",
    roomCloseFailedAt: admin.firestore.FieldValue.serverTimestamp(),
    roomCloseLockExpiresAt: admin.firestore.FieldValue.delete(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
}

export async function forceEndRoom(
  sessionId: string
): Promise<ForceEndRoomResult> {
  const trimmedSessionId = toTrimmedString(sessionId);
  if (!trimmedSessionId) {
    throw new Error("sessionId is required.");
  }

  const prepared = await prepareRoomClose(trimmedSessionId, new Date());
  if (prepared.alreadyClosed) {
    return {
      sessionId: trimmedSessionId,
      roomName: prepared.roomName,
      alreadyClosed: true,
      closed: true,
      livekitAction: "skipped",
    };
  }

  if (!prepared.shouldCallLiveKit) {
    return {
      sessionId: trimmedSessionId,
      roomName: prepared.roomName,
      alreadyClosed: false,
      closed: false,
      livekitAction: "skipped",
    };
  }

  let livekitAction: "deleted" | "not_found" | "skipped" = "deleted";

  try {
    const client = await liveKitClient();
    if (!client) {
      livekitAction = "skipped";
    } else {
      try {
        const participants = await client.listParticipants(prepared.roomName);
        for (const participant of participants) {
          const identity = toTrimmedString(participant.identity);
          if (!identity) continue;
          try {
            await client.removeParticipant(prepared.roomName, identity);
          } catch (error) {
            if (!isRoomMissingError(error)) {
              logger.warn("forceEndRoom removeParticipant failed", {
                sessionId: trimmedSessionId,
                roomName: prepared.roomName,
                identity,
                error,
              });
            }
          }
        }
      } catch (error) {
        if (isRoomMissingError(error)) {
          livekitAction = "not_found";
        } else {
          throw error;
        }
      }

      if (livekitAction !== "not_found") {
        try {
          await client.deleteRoom(prepared.roomName);
        } catch (error) {
          if (isRoomMissingError(error)) {
            livekitAction = "not_found";
          } else {
            throw error;
          }
        }
      }
    }

    await markRoomClosed({
      sessionId: trimmedSessionId,
      bookingId: prepared.bookingId,
      paymentIntentId: prepared.paymentIntentId,
      roomName: prepared.roomName,
      livekitAction,
    });

    return {
      sessionId: trimmedSessionId,
      roomName: prepared.roomName,
      alreadyClosed: false,
      closed: true,
      livekitAction,
    };
  } catch (error) {
    await markRoomCloseFailure(trimmedSessionId, error);
    throw error;
  }
}
