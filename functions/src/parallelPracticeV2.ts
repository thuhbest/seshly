import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {onRequest} from "firebase-functions/v2/https";
import {onDocumentCreated, onDocumentWritten} from "firebase-functions/v2/firestore";
import express, {Request, Response, NextFunction} from "express";
import cors from "cors";
import {SecretManagerServiceClient} from "@google-cloud/secret-manager";
import {
  AccessToken,
  RoomServiceClient,
  EgressClient,
  WebhookReceiver,
  EncodedFileOutput,
} from "livekit-server-sdk";
import {EncodedFileType} from "@livekit/protocol";
import {
  collectTaskWork,
  endSessionWithStructuredOutputs,
  focusOnStudent,
  initialClassroomState,
  monitorEveryoneQuietly,
  recordStudentNudge,
  returnToClass,
  sendClassworkToStudents,
  sendCorrection as orchestrateCorrection,
  showStudentBoardToClass,
  teachAll,
  tutorPrivateReviewMode,
} from "./classroomOrchestrator";
import {
  freezeBoardSnapshot,
  promoteSnapshotForBroadcast,
  syncBoardTopology,
} from "./classroomBoards";
import {
  buildRecoverySnapshot,
  reconcileClassroomReliability,
} from "./classroomReliability";
import {queueClassroomMemoryRefresh} from "./classroomMemory";

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();
const secretClient = new SecretManagerServiceClient();
const REGION = process.env.PARALLEL_PRACTICE_REGION || "europe-west2";

const DEFAULT_MAX_PARTICIPANTS = 5;
const DEFAULT_STUN = ["stun:stun.l.google.com:19302"];
const SESSION_STATE_DOC_ID = "sessionState";
const RATE_LIMIT_COLLECTION = "rateLimits";
const DEFAULT_RATE_LIMITS: Record<string, RateLimitConfig> = {
  "session/create": {windowSec: 60, max: 4},
  "session/join": {windowSec: 30, max: 8},
  "session/leave": {windowSec: 30, max: 8},
  "session/createInvite": {windowSec: 60, max: 12},
  "session/redeemInvite": {windowSec: 30, max: 8},
  "session/addTutor": {windowSec: 60, max: 6},
  "session/promoteTutor": {windowSec: 60, max: 8},
  "session/setMode": {windowSec: 20, max: 20},
  "session/giveTask": {windowSec: 30, max: 20},
  "session/extendTimer": {windowSec: 20, max: 20},
  "session/broadcastHint": {windowSec: 20, max: 24},
  "session/collectNow": {windowSec: 20, max: 20},
  "task/submit": {windowSec: 20, max: 30},
  "session/showToGroup": {windowSec: 20, max: 24},
  "session/sendCorrection": {windowSec: 20, max: 24},
  "classroom/teachAll": {windowSec: 20, max: 20},
  "classroom/sendClasswork": {windowSec: 20, max: 20},
  "classroom/monitor": {windowSec: 20, max: 20},
  "classroom/focusStudent": {windowSec: 20, max: 24},
  "classroom/returnToClass": {windowSec: 20, max: 24},
  "board/spotlight": {windowSec: 20, max: 24},
  "board/freezeSnapshot": {windowSec: 20, max: 30},
  "board/broadcastSnapshot": {windowSec: 20, max: 24},
  "classroom/showToGroup": {windowSec: 20, max: 24},
  "classroom/sendCorrection": {windowSec: 20, max: 24},
  "session/markExemplar": {windowSec: 20, max: 24},
  "review/tag": {windowSec: 20, max: 40},
  "templates/create": {windowSec: 60, max: 20},
  "templates/list": {windowSec: 30, max: 20},
  "templates/update": {windowSec: 60, max: 30},
  "templates/delete": {windowSec: 60, max: 30},
  "templates/apply": {windowSec: 30, max: 20},
  "templates/saveFromTask": {windowSec: 30, max: 20},
  "session/end": {windowSec: 60, max: 6},
  "classroom/endSession": {windowSec: 60, max: 6},
  "session/mintLiveKitToken": {windowSec: 20, max: 20},
  "session/getConnectionInfo": {windowSec: 20, max: 24},
  "session/recording/start": {windowSec: 60, max: 4},
  "session/recording/stop": {windowSec: 60, max: 4},
  "session/heartbeat": {windowSec: 60, max: 90},
  "session/recoverState": {windowSec: 30, max: 20},
  "laser/emit": {windowSec: 10, max: 40},
  "voiceNotes/prepare": {windowSec: 60, max: 20},
  "memory/teachMarker": {windowSec: 30, max: 30},
  "memory/annotate": {windowSec: 30, max: 30},
  "memory/transcriptPointer": {windowSec: 30, max: 30},
  "memory/refresh": {windowSec: 30, max: 12},
  "ai/enqueue": {windowSec: 30, max: 16},
  "ai/studentSeshHelpRequest": {windowSec: 30, max: 12},
};

const app = express();
app.use(cors({origin: true}));
app.use(express.json({limit: "2mb"}));

interface AuthedRequest extends Request {
  user?: {uid: string};
}

type Role = "primaryTutor" | "coTutor" | "student";
type Mode = "teach" | "practice" | "review";
type CallMode = "p2p" | "sfu";
type RateLimitConfig = {windowSec: number; max: number};

type SessionDoc = {
  title: string;
  subject?: string;
  createdBy: string;
  status: "active" | "ended";
  maxParticipants: number;
  participantCount: number;
  tutorCount: number;
  createdAt: admin.firestore.FieldValue;
  updatedAt: admin.firestore.FieldValue;
};

type SessionState = {
  mode: Mode;
  callMode: CallMode;
  callModeVersion: number;
  activeTaskId: string | null;
  timerEndAt: admin.firestore.Timestamp | null;
  activeBoardRef: string | null;
  recordingState?: {
    status: "recording" | "stopped";
    startedAt?: admin.firestore.Timestamp | admin.firestore.FieldValue;
    stoppedAt?: admin.firestore.Timestamp | admin.firestore.FieldValue;
    startedBy?: string;
    stoppedBy?: string;
    recordingId?: string;
    egressId?: string | null;
  };
  settings?: {
    studentAnnotateEnabled?: boolean;
  };
};

function nowTs() {
  return admin.firestore.FieldValue.serverTimestamp();
}

async function verifyAuth(req: AuthedRequest, res: Response, next: NextFunction) {
  const header = req.get("authorization") || "";
  const token = header.startsWith("Bearer ") ? header.substring(7) : "";
  if (!token) {
    res.status(401).json({error: "missing_auth"});
    return;
  }
  try {
    const decoded = await admin.auth().verifyIdToken(token);
    req.user = {uid: decoded.uid};
    next();
  } catch (err) {
    res.status(401).json({error: "invalid_auth"});
  }
}

app.use(verifyAuth);

function getRateLimits(): Record<string, RateLimitConfig> {
  const raw = process.env.PARALLEL_PRACTICE_V2_RATE_LIMITS;
  if (!raw) return DEFAULT_RATE_LIMITS;
  try {
    const parsed = JSON.parse(raw);
    return {...DEFAULT_RATE_LIMITS, ...parsed};
  } catch (error) {
    logger.warn("Invalid PARALLEL_PRACTICE_V2_RATE_LIMITS JSON, using defaults.");
    return DEFAULT_RATE_LIMITS;
  }
}

async function rateLimitOrThrow(uid: string, action: string): Promise<void> {
  const config = getRateLimits()[action];
  if (!config) return;

  const now = Date.now();
  const ref = db.collection(RATE_LIMIT_COLLECTION).doc(`pp_v2_${uid}_${action}`);
  const windowMs = config.windowSec * 1000;
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data() ?? {};
    const windowStart = Number(data.windowStart ?? 0);
    const count = Number(data.count ?? 0);
    if (!windowStart || now - windowStart > windowMs) {
      tx.set(ref, {uid, action, windowStart: now, count: 1, updatedAt: nowTs()});
      return;
    }
    if (count + 1 > config.max) {
      throw new Error("rate_limited");
    }
    tx.set(ref, {
      uid,
      action,
      windowStart,
      count: count + 1,
      updatedAt: nowTs(),
    }, {merge: true});
  });
}

function resolveRateLimitAction(req: Request): string | null {
  const path = req.path || "";
  const allowedPaths = new Set(Object.keys(DEFAULT_RATE_LIMITS).map((key) => `/${key}`));
  return allowedPaths.has(path) ? path.slice(1) : null;
}

async function applyRouteRateLimit(req: AuthedRequest, res: Response, next: NextFunction) {
  const uid = req.user?.uid;
  if (!uid) {
    res.status(401).json({error: "missing_auth"});
    return;
  }

  const action = resolveRateLimitAction(req);
  if (!action) {
    next();
    return;
  }

  try {
    await rateLimitOrThrow(uid, action);
    next();
  } catch (error) {
    if ((error as Error).message === "rate_limited") {
      res.status(429).json({error: "rate_limited"});
      return;
    }
    logger.error("parallelPracticeV2 rate limit failed", {action, error});
    res.status(503).json({error: "rate_limit_unavailable"});
  }
}

app.use(applyRouteRateLimit);

function requireFields(body: Record<string, unknown>, fields: string[]): string | null {
  for (const field of fields) {
    if (body[field] === undefined || body[field] === null || body[field] === "") {
      return field;
    }
  }
  return null;
}

function getStunServers(): string[] {
  const raw = process.env.P2P_STUN_SERVERS;
  if (!raw) return DEFAULT_STUN;
  return raw.split(",").map((s) => s.trim()).filter(Boolean);
}

function sessionRef(sessionId: string) {
  return db.collection("sessions").doc(sessionId);
}

function sessionStateRef(sessionId: string) {
  return db.collection("sessions").doc(sessionId).collection("sessionState").doc(SESSION_STATE_DOC_ID);
}

function idempotencyRef(sessionId: string, key: string) {
  return sessionRef(sessionId).collection("idempotency").doc(key);
}

async function getParticipantRole(sessionId: string, uid: string): Promise<Role | null> {
  const snap = await sessionRef(sessionId).collection("participants").doc(uid).get();
  if (!snap.exists) return null;
  return (snap.data()?.role ?? "student") as Role;
}

async function requireTutor(sessionId: string, uid: string): Promise<void> {
  const role = await getParticipantRole(sessionId, uid);
  if (role !== "primaryTutor" && role !== "coTutor") {
    throw new Error("forbidden");
  }
}

async function requirePrimaryTutor(sessionId: string, uid: string): Promise<void> {
  const role = await getParticipantRole(sessionId, uid);
  if (role !== "primaryTutor") {
    throw new Error("forbidden");
  }
}

async function computeCounts(sessionId: string): Promise<{participantCount: number; tutorCount: number}> {
  const snap = await sessionRef(sessionId).collection("participants").get();
  let tutorCount = 0;
  let participantCount = 0;
  snap.docs.forEach((doc) => {
    const data = doc.data() ?? {};
    const joinState = (data.joinState ?? "joined") as string;
    if (joinState === "left") return;
    participantCount += 1;
    const role = data.role as Role;
    if (role === "primaryTutor" || role === "coTutor") tutorCount += 1;
  });
  return {participantCount, tutorCount};
}

function isTutorRole(role: unknown): role is Role {
  return role === "primaryTutor" || role === "coTutor";
}

function isJoinedState(joinState: unknown): boolean {
  return String(joinState ?? "joined").trim().toLowerCase() !== "left";
}

export function countDeltaForAdmission(params: {
  wasJoined: boolean;
  wasTutor: boolean;
  nextJoined: boolean;
  nextTutor: boolean;
}): {participantDelta: number; tutorDelta: number} {
  return {
    participantDelta: (params.nextJoined ? 1 : 0) - (params.wasJoined ? 1 : 0),
    tutorDelta: (params.nextTutor ? 1 : 0) - (params.wasTutor ? 1 : 0),
  };
}

export function buildLiveKitRoomName(sessionId: string, roomPrefix = "seshly-"): string {
  return `${roomPrefix}${sessionId}`;
}

export function extractSessionIdFromLiveKitRoom(roomName: string, roomPrefix = "seshly-"): string {
  return roomName.startsWith(roomPrefix) ? roomName.slice(roomPrefix.length) : roomName;
}

function desiredCallMode(participantCount: number, tutorCount: number): CallMode {
  if (participantCount >= 3 || tutorCount >= 2) return "sfu";
  return "p2p";
}

let liveKitEnvLoaded = false;

async function readSecretValue(name: string): Promise<string> {
  const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "";
  if (!projectId) return "";
  const [version] = await secretClient.accessSecretVersion({
    name: `projects/${projectId}/secrets/${name}/versions/latest`,
  });
  const data = version.payload?.data?.toString() || "";
  return data;
}

async function ensureLiveKitEnv() {
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

async function liveKitConfig() {
  await ensureLiveKitEnv();
  return {
    url: process.env.LIVEKIT_URL || "",
    apiKey: process.env.LIVEKIT_API_KEY || "",
    apiSecret: process.env.LIVEKIT_API_SECRET || "",
    roomPrefix: process.env.LIVEKIT_ROOM_PREFIX || "seshly-",
  };
}

async function resolveLiveKitRoomName(sessionId: string) {
  const {roomPrefix} = await liveKitConfig();
  return buildLiveKitRoomName(sessionId, roomPrefix);
}

async function resolveSessionIdFromLiveKitRoom(roomName: string) {
  const {roomPrefix} = await liveKitConfig();
  return extractSessionIdFromLiveKitRoom(roomName, roomPrefix);
}

export function normalizePairMembers(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((entry) => String(entry ?? "").trim())
    .filter((entry, index, arr) => entry.length > 0 && arr.indexOf(entry) === index)
    .sort();
}

function egressConfig() {
  return {
    enabled: process.env.ENABLE_LIVEKIT_EGRESS === "true",
    bucket: process.env.LIVEKIT_EGRESS_BUCKET || "",
    prefix: process.env.LIVEKIT_EGRESS_PREFIX || "recordings",
  };
}

async function getEgressClient() {
  const {url, apiKey, apiSecret} = await liveKitConfig();
  if (!url || !apiKey || !apiSecret) return null;
  return new EgressClient(url, apiKey, apiSecret);
}

async function getWebhookReceiver() {
  const {apiKey, apiSecret} = await liveKitConfig();
  if (!apiKey || !apiSecret) return null;
  return new WebhookReceiver(apiKey, apiSecret);
}

async function createOrGetLiveKitRoom(sessionId: string) {
  const {url, apiKey, apiSecret, roomPrefix} = await liveKitConfig();
  if (!url || !apiKey || !apiSecret) return null;
  const roomName = buildLiveKitRoomName(sessionId, roomPrefix);
  const client = new RoomServiceClient(url, apiKey, apiSecret);
  try {
    await client.createRoom({name: roomName});
  } catch (err) {
    logger.info("LiveKit room create skipped", err);
  }
  return roomName;
}

async function emitSessionEvent(sessionId: string, payload: Record<string, unknown>) {
  await sessionRef(sessionId).collection("sessionEvents").add({
    ...payload,
    createdAt: nowTs(),
  });
}

async function recomputeCountsAndCallMode(sessionId: string) {
  const counts = await computeCounts(sessionId);
  const sessionDocSnap = await sessionRef(sessionId).get();
  if (!sessionDocSnap.exists) return;

  const nextMode = desiredCallMode(counts.participantCount, counts.tutorCount);
  const stateSnap = await sessionStateRef(sessionId).get();
  const state = (stateSnap.data() ?? {}) as Partial<SessionState>;
  const currentMode = (state.callMode ?? "p2p") as CallMode;
  const currentVersion = Number(state.callModeVersion ?? 0);

  await sessionRef(sessionId).set({
    participantCount: counts.participantCount,
    tutorCount: counts.tutorCount,
    updatedAt: nowTs(),
  }, {merge: true});

  if (currentMode !== nextMode) {
    const nextVersion = currentVersion + 1;
    await sessionStateRef(sessionId).set({
      callMode: nextMode,
      callModeVersion: nextVersion,
    }, {merge: true});

    if (nextMode === "sfu") {
      const roomName = await createOrGetLiveKitRoom(sessionId);
      await emitSessionEvent(sessionId, {
        type: "CALL_MODE_SWITCH",
        target: "SFU",
        roomName,
        version: nextVersion,
      });
    } else {
      await emitSessionEvent(sessionId, {
        type: "CALL_MODE_SWITCH",
        target: "P2P",
        version: nextVersion,
      });
    }
  }
}

async function buildLiveKitToken(sessionId: string, uid: string, role: Role) {
  const {apiKey, apiSecret} = await liveKitConfig();
  if (!apiKey || !apiSecret) {
    throw new Error("livekit_not_configured");
  }
  const roomName = await resolveLiveKitRoomName(sessionId);
  const token = new AccessToken(apiKey, apiSecret, {
    identity: uid,
    metadata: JSON.stringify({role}),
    ttl: "2h",
  });
  token.addGrant({
    room: roomName,
    roomJoin: true,
    canPublish: true,
    canSubscribe: true,
    canPublishData: true,
  });
  return token.toJwt();
}

async function getSessionConnectionInfo(sessionId: string, uid: string) {
  const stateSnap = await sessionStateRef(sessionId).get();
  const state = (stateSnap.data() ?? {}) as Partial<SessionState>;
  const callMode = (state.callMode ?? "p2p") as CallMode;
  const version = Number(state.callModeVersion ?? 0);

  if (callMode === "p2p") {
    return {
      callMode: "p2p",
      callModeVersion: version,
      stunServers: getStunServers(),
    };
  }

  const {url} = await liveKitConfig();
  const role = await getParticipantRole(sessionId, uid);
  if (!role) throw new Error("forbidden");
  const token = await buildLiveKitToken(sessionId, uid, role);
  const roomName = await resolveLiveKitRoomName(sessionId);
  return {
    callMode: "sfu",
    callModeVersion: version,
    livekitUrl: url,
    token,
    room: roomName,
  };
}

async function ensureSessionActive(sessionId: string) {
  const snap = await sessionRef(sessionId).get();
  if (!snap.exists) throw new Error("not_found");
  const data = snap.data() as SessionDoc;
  if (data.status !== "active") throw new Error("session_closed");
}

async function requireApprovedTutorAccount(uid: string): Promise<void> {
  const snap = await db.collection("users").doc(uid).get();
  const status = String(snap.data()?.tutorStatus ?? "").trim().toLowerCase();
  if (!["approved", "active"].includes(status)) {
    throw new Error("tutor_not_approved");
  }
}

async function getIdempotentResponse(sessionId: string, key?: string) {
  if (!key) return null;
  const snap = await idempotencyRef(sessionId, key).get();
  if (!snap.exists) return null;
  return snap.data()?.response ?? null;
}

async function setIdempotentResponse(sessionId: string, key: string | undefined, response: Record<string, unknown>) {
  if (!key) return;
  await idempotencyRef(sessionId, key).set({
    response,
    createdAt: nowTs(),
  });
}

function normalizePresenceState(value: unknown): string {
  const raw = String(value ?? "online").trim().toLowerCase();
  if (["online", "reconnecting", "unstable", "offline"].includes(raw)) {
    return raw;
  }
  return "online";
}

function normalizeNetworkQuality(value: unknown): string {
  const raw = String(value ?? "unknown").trim().toLowerCase();
  if (["strong", "fair", "weak", "poor", "unknown", "unstable"].includes(raw)) {
    return raw;
  }
  return "unknown";
}

function normalizeMediaHealth(value: unknown): string {
  const raw = String(value ?? "stable").trim().toLowerCase();
  if (["stable", "degraded", "recovering"].includes(raw)) {
    return raw;
  }
  return "stable";
}

app.post("/session/create", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const title = (body.title ?? "Parallel Practice") as string;
  const subject = (body.subject ?? "") as string;
  const maxParticipants = Math.min(Number(body.maxParticipants ?? DEFAULT_MAX_PARTICIPANTS), DEFAULT_MAX_PARTICIPANTS);

  const sessionDoc: SessionDoc = {
    title,
    subject,
    createdBy: uid,
    status: "active",
    maxParticipants,
    participantCount: 1,
    tutorCount: 1,
    createdAt: nowTs(),
    updatedAt: nowTs(),
  };

  const sessionDocRef = sessionRef(db.collection("sessions").doc().id);
  const sessionId = sessionDocRef.id;

  await db.runTransaction(async (tx) => {
    tx.set(sessionDocRef, sessionDoc);
    tx.set(sessionDocRef.collection("participants").doc(uid), {
      userId: uid,
      role: "primaryTutor" as Role,
      joinState: "joined",
      micEnabled: true,
      camEnabled: true,
      presenceState: "online",
      lastSeenAt: nowTs(),
      status: "working",
      progress: 0,
      pinned: false,
    });
    tx.set(sessionStateRef(sessionId), initialClassroomState() as SessionState);
  });

  await reconcileClassroomReliability(sessionId);
  const connectionInfo = await getSessionConnectionInfo(sessionId, uid);
  const recoverySnapshot = await buildRecoverySnapshot({
    sessionId,
    participantId: uid,
    connectionInfo,
  });

  res.json({sessionId, connectionInfo, recoverySnapshot});
});

app.post("/session/join", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);

  try {
    await ensureSessionActive(sessionId);
    await db.runTransaction(async (tx) => {
      const currentSessionRef = sessionRef(sessionId);
      const participantRef = currentSessionRef.collection("participants").doc(uid);
      const [sessionSnap, participantSnap] = await Promise.all([
        tx.get(currentSessionRef),
        tx.get(participantRef),
      ]);
      if (!sessionSnap.exists) throw new Error("not_found");
      const sessionData = sessionSnap.data() as SessionDoc;
      if (sessionData.status !== "active") throw new Error("session_closed");

      const currentParticipant = participantSnap.data() ?? {};
      const currentRole = (currentParticipant.role ?? "student") as Role;
      const wasJoined = participantSnap.exists && isJoinedState(currentParticipant.joinState);
      const nextRole = participantSnap.exists ? currentRole : "student";
      const delta = countDeltaForAdmission({
        wasJoined,
        wasTutor: wasJoined && isTutorRole(currentRole),
        nextJoined: true,
        nextTutor: isTutorRole(nextRole),
      });

      if (!wasJoined && Number(sessionData.participantCount ?? 0) + delta.participantDelta > sessionData.maxParticipants) {
        throw new Error("session_full");
      }

      tx.set(participantRef, {
        userId: uid,
        role: nextRole,
        joinState: "joined",
        micEnabled: true,
        camEnabled: true,
        presenceState: "online",
        lastSeenAt: nowTs(),
        status: "working",
        progress: 0,
        pinned: false,
      }, {merge: true});
      tx.set(currentSessionRef, {
        participantCount: Math.max(0, Number(sessionData.participantCount ?? 0) + delta.participantDelta),
        tutorCount: Math.max(0, Number(sessionData.tutorCount ?? 0) + delta.tutorDelta),
        updatedAt: nowTs(),
      }, {merge: true});
    });

    await recomputeCountsAndCallMode(sessionId);
    await reconcileClassroomReliability(sessionId);
    const connectionInfo = await getSessionConnectionInfo(sessionId, uid);
    const recoverySnapshot = await buildRecoverySnapshot({
      sessionId,
      participantId: uid,
      connectionInfo,
    });
    return res.json({ok: true, connectionInfo, recoverySnapshot});
  } catch (err) {
    const msg = (err as Error).message;
    if (msg === "session_full") return res.status(409).json({error: "session_full"});
    if (msg === "not_found") return res.status(404).json({error: "not_found"});
    if (msg === "session_closed") return res.status(409).json({error: "session_closed"});
    logger.error("session/join failed", err);
    return res.status(500).json({error: "server_error"});
  }
});

app.post("/session/leave", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);

  await db.runTransaction(async (tx) => {
    const currentSessionRef = sessionRef(sessionId);
    const participantRef = currentSessionRef.collection("participants").doc(uid);
    const [sessionSnap, participantSnap] = await Promise.all([
      tx.get(currentSessionRef),
      tx.get(participantRef),
    ]);
    if (!sessionSnap.exists || !participantSnap.exists) return;
    const sessionData = sessionSnap.data() as SessionDoc;
    const participantData = participantSnap.data() ?? {};
    const currentRole = (participantData.role ?? "student") as Role;
    const wasJoined = isJoinedState(participantData.joinState);
    const delta = countDeltaForAdmission({
      wasJoined,
      wasTutor: wasJoined && isTutorRole(currentRole),
      nextJoined: false,
      nextTutor: false,
    });

    tx.set(participantRef, {
      joinState: "left",
      presenceState: "offline",
      lastSeenAt: nowTs(),
    }, {merge: true});
    tx.set(currentSessionRef, {
      participantCount: Math.max(0, Number(sessionData.participantCount ?? 0) + delta.participantDelta),
      tutorCount: Math.max(0, Number(sessionData.tutorCount ?? 0) + delta.tutorDelta),
      updatedAt: nowTs(),
    }, {merge: true});
  });

  await recomputeCountsAndCallMode(sessionId);
  await reconcileClassroomReliability(sessionId);
  res.json({ok: true});
});

app.post("/session/createInvite", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId", "roleToGrant", "expiresAt", "maxUses"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);
  const roleToGrant = String(body.roleToGrant);
  if (!["student", "coTutor"].includes(roleToGrant)) {
    res.status(400).json({error: "invalid_role"});
    return;
  }
  try {
    await requireApprovedTutorAccount(uid);
    if (roleToGrant === "coTutor") {
      await requirePrimaryTutor(sessionId, uid);
    } else {
      await requireTutor(sessionId, uid);
    }
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }
  const inviteRef = sessionRef(sessionId).collection("invites").doc();
  await inviteRef.set({
    roleToGrant,
    expiresAt: admin.firestore.Timestamp.fromDate(new Date(body.expiresAt)),
    maxUses: Number(body.maxUses ?? 1),
    usedCount: 0,
    createdBy: uid,
    createdAt: nowTs(),
  });
  res.json({inviteId: inviteRef.id});
});

app.post("/session/redeemInvite", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId", "inviteId"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);
  const inviteId = String(body.inviteId);

  try {
    await ensureSessionActive(sessionId);
    await db.runTransaction(async (tx) => {
      const currentSessionRef = sessionRef(sessionId);
      const inviteRef = currentSessionRef.collection("invites").doc(inviteId);
      const participantRef = currentSessionRef.collection("participants").doc(uid);
      const inviteSnap = await tx.get(inviteRef);
      if (!inviteSnap.exists) throw new Error("invite_not_found");
      const invite = inviteSnap.data() ?? {};
      const roleToGrant = invite.roleToGrant as Role;
      if (!["student", "coTutor"].includes(String(roleToGrant))) {
        throw new Error("invite_invalid");
      }
      const usedCount = Number(invite.usedCount ?? 0);
      const maxUses = Number(invite.maxUses ?? 1);
      const expiresAt = invite.expiresAt as admin.firestore.Timestamp | undefined;
      if (expiresAt && expiresAt.toDate().getTime() < Date.now()) throw new Error("invite_expired");
      if (usedCount >= maxUses) throw new Error("invite_exhausted");

      const [sessionSnap, participantSnap] = await Promise.all([
        tx.get(currentSessionRef),
        tx.get(participantRef),
      ]);
      if (!sessionSnap.exists) throw new Error("not_found");
      const sessionData = sessionSnap.data() as SessionDoc;
      if (sessionData.status !== "active") throw new Error("session_closed");

      const currentParticipant = participantSnap.data() ?? {};
      const currentRole = (currentParticipant.role ?? roleToGrant) as Role;
      const wasJoined = participantSnap.exists && isJoinedState(currentParticipant.joinState);
      const nextRole = roleToGrant;
      const delta = countDeltaForAdmission({
        wasJoined,
        wasTutor: wasJoined && isTutorRole(currentRole),
        nextJoined: true,
        nextTutor: isTutorRole(nextRole),
      });
      if (!wasJoined && Number(sessionData.participantCount ?? 0) + delta.participantDelta > Number(sessionData.maxParticipants ?? DEFAULT_MAX_PARTICIPANTS)) {
        throw new Error("session_full");
      }

      tx.set(participantRef, {
        userId: uid,
        role: nextRole,
        joinState: "joined",
        micEnabled: true,
        camEnabled: true,
        presenceState: "online",
        lastSeenAt: nowTs(),
        status: "working",
        progress: 0,
        pinned: false,
      }, {merge: true});

      tx.set(inviteRef, {usedCount: usedCount + 1}, {merge: true});
      tx.set(currentSessionRef, {
        participantCount: Math.max(0, Number(sessionData.participantCount ?? 0) + delta.participantDelta),
        tutorCount: Math.max(0, Number(sessionData.tutorCount ?? 0) + delta.tutorDelta),
        updatedAt: nowTs(),
      }, {merge: true});
    });

    await recomputeCountsAndCallMode(sessionId);
    await reconcileClassroomReliability(sessionId);
    const connectionInfo = await getSessionConnectionInfo(sessionId, uid);
    const recoverySnapshot = await buildRecoverySnapshot({
      sessionId,
      participantId: uid,
      connectionInfo,
    });
    return res.json({ok: true, connectionInfo, recoverySnapshot});
  } catch (err) {
    const msg = (err as Error).message;
    if (msg === "invite_not_found") return res.status(404).json({error: msg});
    if (msg === "invite_expired" || msg === "invite_exhausted" || msg === "invite_invalid") return res.status(409).json({error: msg});
    if (msg === "session_full") return res.status(409).json({error: "session_full"});
    if (msg === "session_closed") return res.status(409).json({error: "session_closed"});
    logger.error("redeemInvite failed", err);
    return res.status(500).json({error: "server_error"});
  }
});
app.post("/session/addTutor", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);
  const targetUid = body.targetUid ? String(body.targetUid) : null;
  const inviteId = body.inviteId ? String(body.inviteId) : null;

  try {
    await requirePrimaryTutor(sessionId, uid);
    await requireApprovedTutorAccount(uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }

  if (targetUid) {
    res.status(400).json({error: "direct_add_tutor_disabled", message: "Use invite + redeem or promoteTutor."});
    return;
  } else {
    if (!inviteId) {
      const newInviteRef = sessionRef(sessionId).collection("invites").doc();
      await newInviteRef.set({
        roleToGrant: "coTutor",
        expiresAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 1000 * 60 * 60)),
        maxUses: 1,
        usedCount: 0,
        createdBy: uid,
        createdAt: nowTs(),
      });
      res.json({inviteId: newInviteRef.id});
      return;
    }
    await sessionRef(sessionId).collection("invites").doc(inviteId).set({roleToGrant: "coTutor"}, {merge: true});
  }

  await recomputeCountsAndCallMode(sessionId);
  await reconcileClassroomReliability(sessionId);
  res.json({ok: true});
});

app.post("/session/setMode", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId", "mode"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);
  const mode = String(body.mode) as Mode;
  if (!["teach", "practice", "review"].includes(mode)) {
    res.status(400).json({error: "invalid_mode"});
    return;
  }
  try {
    await requirePrimaryTutor(sessionId, uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }
  try {
    const actionId = body.actionId ? String(body.actionId) : undefined;
    const result = mode === "teach" ?
      await teachAll({
        sessionId,
        actorId: uid,
        classLock: body.classLock ?? true,
        actionId,
      }) :
      mode === "practice" ?
        await monitorEveryoneQuietly({
          sessionId,
          actorId: uid,
          actionId,
        }) :
        await tutorPrivateReviewMode({
          sessionId,
          actorId: uid,
          actionId,
        });
    res.json(result.result);
  } catch (err) {
    const msg = (err as Error).message;
    if (msg === "student_not_found") {
      res.status(404).json({error: msg});
      return;
    }
    logger.error("session/setMode failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/session/giveTask", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId", "taskPayload"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);
  const idempotencyKey = body.idempotencyKey ? String(body.idempotencyKey) : undefined;
  try {
    await requireTutor(sessionId, uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }
  try {
    const orchestrated = await sendClassworkToStudents({
      sessionId,
      actorId: uid,
      taskPayload: body.taskPayload ?? {},
      actionId: idempotencyKey,
    });
    res.json(orchestrated.result);
  } catch (err) {
    logger.error("session/giveTask failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/session/extendTimer", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId", "deltaSeconds"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);
  const deltaSeconds = Number(body.deltaSeconds ?? 0);
  try {
    await requireTutor(sessionId, uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }

  const stateSnap = await sessionStateRef(sessionId).get();
  const state = (stateSnap.data() ?? {}) as Partial<SessionState>;
  const current = state.timerEndAt ? state.timerEndAt.toMillis() : Date.now();
  const next = admin.firestore.Timestamp.fromMillis(current + deltaSeconds * 1000);
  await sessionStateRef(sessionId).set({timerEndAt: next}, {merge: true});
  res.json({timerEndAt: next.toMillis()});
});

app.post("/session/broadcastHint", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId", "hintText"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);
  try {
    await requireTutor(sessionId, uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }
  if (body.studentId) {
    try {
      await recordStudentNudge({
        sessionId,
        actorId: uid,
        studentId: String(body.studentId),
        hintText: String(body.hintText),
        taskId: body.taskId ? String(body.taskId) : null,
        taskStepKey: body.taskStepKey ? String(body.taskStepKey) : null,
        boardId: body.boardId ? String(body.boardId) : null,
      });
    } catch (err) {
      const msg = (err as Error).message;
      if (msg === "student_not_found") {
        res.status(404).json({error: msg});
        return;
      }
      logger.error("session/broadcastHint student nudge failed", err);
      res.status(500).json({error: "server_error"});
      return;
    }
  } else {
    await sessionRef(sessionId).collection("interventions").add({
      type: "broadcastHint",
      taskId: body.taskId ? String(body.taskId) : null,
      taskStepKey: body.taskStepKey ? String(body.taskStepKey) : null,
      boardId: body.boardId ? String(body.boardId) : null,
      payload: {hintText: body.hintText, aiOutputRef: body.aiOutputRef ?? null},
      createdBy: uid,
      createdAt: nowTs(),
      state: "CLOSED",
    });
  }
  res.json({ok: true});
});

app.post("/session/collectNow", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);
  try {
    await requireTutor(sessionId, uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }
  try {
    const orchestrated = await collectTaskWork({
      sessionId,
      actorId: uid,
      actionId: body.actionId ? String(body.actionId) : undefined,
    });
    res.json(orchestrated.result);
  } catch (err) {
    logger.error("session/collectNow failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/task/submit", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId", "taskId"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);
  const taskId = String(body.taskId);
  const idempotencyKey = body.idempotencyKey ? String(body.idempotencyKey) : undefined;

  const cached = await getIdempotentResponse(sessionId, idempotencyKey);
  if (cached) {
    res.json(cached);
    return;
  }

  await sessionRef(sessionId).collection("submissions").doc(`${taskId}_${uid}`).set({
    taskId,
    taskStepKey: body.taskStepKey ? String(body.taskStepKey) : null,
    stepId: body.stepId ? String(body.stepId) : null,
    studentId: uid,
    responseText: body.responseText ?? "",
    snapshotRef: body.snapshotRef ?? null,
    boardId: body.boardId ?? null,
    status: "submitted",
    createdAt: nowTs(),
    submittedAt: nowTs(),
  }, {merge: true});

  const response = {ok: true};
  await setIdempotentResponse(sessionId, idempotencyKey, response);
  res.json(response);
});

app.post("/session/showToGroup", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId", "studentId", "snapshotId"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);
  try {
    await requirePrimaryTutor(sessionId, uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }

  try {
    const promoted = await promoteSnapshotForBroadcast({
      sessionId,
      actorId: uid,
      snapshotId: String(body.snapshotId),
      studentId: String(body.studentId),
      commandId: body.actionId ? `${String(body.actionId)}_broadcast` : undefined,
    });
    const orchestrated = await showStudentBoardToClass({
      sessionId,
      actorId: uid,
      studentId: String(body.studentId),
      snapshotId: String(body.snapshotId),
      actionId: body.actionId ? String(body.actionId) : undefined,
    });
    await syncBoardTopology(sessionId);
    res.json({
      ...orchestrated.result,
      exemplarBoardId: promoted.exemplarBoardId,
    });
  } catch (err) {
    const msg = (err as Error).message;
    if (msg === "student_not_found") {
      res.status(404).json({error: msg});
      return;
    }
    logger.error("session/showToGroup failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/session/sendCorrection", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId", "studentId", "snapshotId", "annotationsRef"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);
  try {
    await requireTutor(sessionId, uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }

  try {
    const orchestrated = await orchestrateCorrection({
      sessionId,
      actorId: uid,
      studentId: String(body.studentId),
      snapshotId: String(body.snapshotId),
      annotationsRef: String(body.annotationsRef),
      voiceNoteRef: body.voiceNoteRef ? String(body.voiceNoteRef) : undefined,
      actionId: body.actionId ? String(body.actionId) : undefined,
    });
    res.json(orchestrated.result);
  } catch (err) {
    const msg = (err as Error).message;
    if (msg === "student_not_found") {
      res.status(404).json({error: msg});
      return;
    }
    logger.error("session/sendCorrection failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/classroom/teachAll", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  try {
    await requirePrimaryTutor(String(body.sessionId), uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }
  try {
    const result = await teachAll({
      sessionId: String(body.sessionId),
      actorId: uid,
      classLock: body.classLock ?? true,
      actionId: body.actionId ? String(body.actionId) : undefined,
    });
    res.json(result.result);
  } catch (err) {
    logger.error("classroom/teachAll failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/classroom/sendClasswork", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId", "taskPayload"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  try {
    await requirePrimaryTutor(String(body.sessionId), uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }
  try {
    const result = await sendClassworkToStudents({
      sessionId: String(body.sessionId),
      actorId: uid,
      taskPayload: body.taskPayload as Record<string, unknown>,
      actionId: body.actionId ? String(body.actionId) : undefined,
    });
    res.json(result.result);
  } catch (err) {
    logger.error("classroom/sendClasswork failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/classroom/monitor", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  try {
    await requirePrimaryTutor(String(body.sessionId), uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }
  try {
    const result = await monitorEveryoneQuietly({
      sessionId: String(body.sessionId),
      actorId: uid,
      actionId: body.actionId ? String(body.actionId) : undefined,
    });
    res.json(result.result);
  } catch (err) {
    logger.error("classroom/monitor failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/classroom/focusStudent", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId", "studentId"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);
  try {
    if (body.pauseOthers == true || String(body.spotlightMode ?? "").trim() === "hard") {
      await requirePrimaryTutor(sessionId, uid);
    } else {
      await requireTutor(sessionId, uid);
    }
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }
  try {
    const result = await focusOnStudent({
      sessionId,
      actorId: uid,
      studentId: String(body.studentId),
      observeOnly: body.observeOnly == true,
      spotlightMode: body.spotlightMode ? String(body.spotlightMode) as "soft" | "hard" : undefined,
      pauseOthers: body.pauseOthers == true,
      deEmphasizeOthers: body.deEmphasizeOthers !== false,
      reason: body.reason ? String(body.reason) : undefined,
      actionId: body.actionId ? String(body.actionId) : undefined,
    });
    await syncBoardTopology(sessionId);
    res.json(result.result);
  } catch (err) {
    const msg = (err as Error).message;
    if (msg === "student_not_found") {
      res.status(404).json({error: msg});
      return;
    }
    if (msg === "focus_not_allowed") {
      res.status(409).json({error: msg});
      return;
    }
    logger.error("classroom/focusStudent failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/classroom/returnToClass", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  try {
    await requirePrimaryTutor(String(body.sessionId), uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }
  try {
    const result = await returnToClass({
      sessionId: String(body.sessionId),
      actorId: uid,
      actionId: body.actionId ? String(body.actionId) : undefined,
    });
    res.json(result.result);
  } catch (err) {
    logger.error("classroom/returnToClass failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/board/spotlight", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId", "studentId"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);
  try {
    if (body.pauseOthers == true || String(body.spotlightMode ?? "").trim() === "hard") {
      await requirePrimaryTutor(sessionId, uid);
    } else {
      await requireTutor(sessionId, uid);
    }
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }
  try {
    const result = await focusOnStudent({
      sessionId,
      actorId: uid,
      studentId: String(body.studentId),
      observeOnly: body.observeOnly == true,
      spotlightMode: body.spotlightMode ? String(body.spotlightMode) as "soft" | "hard" : undefined,
      pauseOthers: body.pauseOthers == true,
      deEmphasizeOthers: body.deEmphasizeOthers !== false,
      reason: body.reason ? String(body.reason) : undefined,
      actionId: body.actionId ? String(body.actionId) : undefined,
    });
    await syncBoardTopology(sessionId);
    res.json(result.result);
  } catch (err) {
    const msg = (err as Error).message;
    if (msg === "student_not_found") {
      res.status(404).json({error: msg});
      return;
    }
    if (msg === "focus_not_allowed") {
      res.status(409).json({error: msg});
      return;
    }
    logger.error("board/spotlight failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/board/freezeSnapshot", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId", "boardId"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  try {
    const result = await freezeBoardSnapshot({
      sessionId: String(body.sessionId),
      actorId: uid,
      boardId: String(body.boardId),
      snapshotKind: body.snapshotKind,
      storagePath: body.storagePath ? String(body.storagePath) : undefined,
      url: body.url ? String(body.url) : undefined,
      studentId: body.studentId ? String(body.studentId) : undefined,
      lockBoard: body.lockBoard == true,
      commandId: body.actionId ? String(body.actionId) : undefined,
    });
    await syncBoardTopology(String(body.sessionId));
    res.json(result);
  } catch (err) {
    const msg = (err as Error).message;
    if (msg === "board_not_found") {
      res.status(404).json({error: msg});
      return;
    }
    if (msg === "forbidden") {
      res.status(403).json({error: msg});
      return;
    }
    logger.error("board/freezeSnapshot failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/board/broadcastSnapshot", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId", "studentId", "snapshotId"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  try {
    const promoted = await promoteSnapshotForBroadcast({
      sessionId: String(body.sessionId),
      actorId: uid,
      snapshotId: String(body.snapshotId),
      studentId: String(body.studentId),
      commandId: body.actionId ? `${String(body.actionId)}_broadcast` : undefined,
    });
    const orchestrated = await showStudentBoardToClass({
      sessionId: String(body.sessionId),
      actorId: uid,
      studentId: String(body.studentId),
      snapshotId: String(body.snapshotId),
      actionId: body.actionId ? String(body.actionId) : undefined,
    });
    await syncBoardTopology(String(body.sessionId));
    res.json({
      ...orchestrated.result,
      exemplarBoardId: promoted.exemplarBoardId,
    });
  } catch (err) {
    const msg = (err as Error).message;
    if (msg === "student_not_found" || msg === "snapshot_not_found") {
      res.status(404).json({error: msg});
      return;
    }
    logger.error("board/broadcastSnapshot failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/classroom/showToGroup", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId", "studentId", "snapshotId"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  try {
    await requirePrimaryTutor(String(body.sessionId), uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }
  try {
    const result = await showStudentBoardToClass({
      sessionId: String(body.sessionId),
      actorId: uid,
      studentId: String(body.studentId),
      snapshotId: String(body.snapshotId),
      actionId: body.actionId ? String(body.actionId) : undefined,
    });
    res.json(result.result);
  } catch (err) {
    const msg = (err as Error).message;
    if (msg === "student_not_found") {
      res.status(404).json({error: msg});
      return;
    }
    logger.error("classroom/showToGroup failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/classroom/sendCorrection", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId", "studentId", "snapshotId", "annotationsRef"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  try {
    const result = await orchestrateCorrection({
      sessionId: String(body.sessionId),
      actorId: uid,
      studentId: String(body.studentId),
      snapshotId: String(body.snapshotId),
      annotationsRef: String(body.annotationsRef),
      voiceNoteRef: body.voiceNoteRef ? String(body.voiceNoteRef) : undefined,
      actionId: body.actionId ? String(body.actionId) : undefined,
    });
    res.json(result.result);
  } catch (err) {
    const msg = (err as Error).message;
    if (msg === "student_not_found") {
      res.status(404).json({error: msg});
      return;
    }
    logger.error("classroom/sendCorrection failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/session/markExemplar", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId", "snapshotId"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);
  try {
    await requirePrimaryTutor(sessionId, uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }
  try {
    const promoted = await promoteSnapshotForBroadcast({
      sessionId,
      actorId: uid,
      snapshotId: String(body.snapshotId),
      commandId: body.actionId ? String(body.actionId) : undefined,
    });
    await sessionRef(sessionId).collection("boardSnapshots").doc(body.snapshotId).set({
      exemplarMarkedBy: uid,
      exemplarMarkedAt: nowTs(),
    }, {merge: true});
    res.json({ok: true, exemplarBoardId: promoted.exemplarBoardId});
  } catch (err) {
    const msg = (err as Error).message;
    if (msg === "snapshot_not_found") {
      res.status(404).json({error: msg});
      return;
    }
    logger.error("session/markExemplar failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/review/tag", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId", "studentId", "taskId", "tag"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);
  try {
    await requireTutor(sessionId, uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }
  await sessionRef(sessionId).collection("tags").add({
    studentId: body.studentId,
    taskId: body.taskId,
    tag: body.tag,
    createdBy: uid,
    createdAt: nowTs(),
  });
  res.json({ok: true});
});

app.post("/templates/create", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["title", "task"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  try {
    await requireApprovedTutorAccount(uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }
  const templateRef = db.collection("templates").doc(uid).collection("items").doc();
  await templateRef.set({
    title: body.title,
    task: body.task,
    rubric: body.rubric ?? "",
    expectedSolution: body.expectedSolution ?? "",
    tags: body.tags ?? [],
    checklist: body.checklist ?? [],
    createdAt: nowTs(),
  });
  res.json({templateId: templateRef.id});
});

app.post("/templates/list", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  try {
    await requireApprovedTutorAccount(uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }
  const snap = await db.collection("templates").doc(uid).collection("items").orderBy("createdAt", "desc").get();
  res.json({templates: snap.docs.map((doc) => ({id: doc.id, ...doc.data()}))});
});

app.post("/templates/update", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["templateId"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  try {
    await requireApprovedTutorAccount(uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }
  const templateId = String(body.templateId);
  await db.collection("templates").doc(uid).collection("items").doc(templateId).set({
    title: body.title,
    task: body.task,
    rubric: body.rubric,
    expectedSolution: body.expectedSolution,
    tags: body.tags,
    checklist: body.checklist,
    updatedAt: nowTs(),
  }, {merge: true});
  res.json({ok: true});
});

app.post("/templates/delete", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["templateId"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  try {
    await requireApprovedTutorAccount(uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }
  const templateId = String(body.templateId);
  await db.collection("templates").doc(uid).collection("items").doc(templateId).delete();
  res.json({ok: true});
});

app.post("/templates/apply", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId", "templateId"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);
  const templateId = String(body.templateId);
  try {
    await requireApprovedTutorAccount(uid);
    await requireTutor(sessionId, uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }
  const templateSnap = await db.collection("templates").doc(uid).collection("items").doc(templateId).get();
  if (!templateSnap.exists) {
    res.status(404).json({error: "not_found"});
    return;
  }
  const data = templateSnap.data() ?? {};
  const taskRef = sessionRef(sessionId).collection("tasks").doc();
  await taskRef.set({
    prompt: data.task ?? "",
    attachments: [],
    options: {allowSeshHelp: true},
    timerSec: 0,
    rubric: data.rubric ?? "",
    expectedSolution: data.expectedSolution ?? "",
    checklist: data.checklist ?? [],
    submissionFormat: "final",
    templateId: templateId,
    createdBy: uid,
    createdAt: nowTs(),
    status: "active",
  });
  await sessionStateRef(sessionId).set({activeTaskId: taskRef.id}, {merge: true});
  res.json({taskId: taskRef.id});
});

app.post("/templates/saveFromTask", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId", "taskId", "title"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);
  const taskId = String(body.taskId);
  try {
    await requireApprovedTutorAccount(uid);
    await requireTutor(sessionId, uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }
  const taskSnap = await sessionRef(sessionId).collection("tasks").doc(taskId).get();
  if (!taskSnap.exists) {
    res.status(404).json({error: "not_found"});
    return;
  }
  const task = taskSnap.data() ?? {};
  const templateRef = db.collection("templates").doc(uid).collection("items").doc();
  await templateRef.set({
    title: body.title,
    task: task.prompt ?? "",
    rubric: task.rubric ?? "",
    expectedSolution: task.expectedSolution ?? "",
    tags: task.tags ?? [],
    checklist: task.checklist ?? [],
    createdAt: nowTs(),
  });
  res.json({templateId: templateRef.id});
});

app.post("/session/end", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);
  const idempotencyKey = body.idempotencyKey ? String(body.idempotencyKey) : undefined;

  try {
    await requirePrimaryTutor(sessionId, uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }
  try {
    const result = await endSessionWithStructuredOutputs({
      sessionId,
      actorId: uid,
      wrapOptions: (body.wrapOptions ?? {}) as Record<string, unknown>,
      actionId: idempotencyKey,
    });
    res.json(result.result);
  } catch (err) {
    logger.error("session/end failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/classroom/endSession", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  try {
    await requirePrimaryTutor(String(body.sessionId), uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }
  try {
    const result = await endSessionWithStructuredOutputs({
      sessionId: String(body.sessionId),
      actorId: uid,
      wrapOptions: (body.wrapOptions ?? {}) as Record<string, unknown>,
      actionId: body.actionId ? String(body.actionId) : undefined,
    });
    res.json(result.result);
  } catch (err) {
    logger.error("classroom/endSession failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/session/mintLiveKitToken", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);
  const role = await getParticipantRole(sessionId, uid);
  if (!role) {
    res.status(403).json({error: "forbidden"});
    return;
  }
  const stateSnap = await sessionStateRef(sessionId).get();
  const state = (stateSnap.data() ?? {}) as Partial<SessionState>;
  if ((state.callMode ?? "p2p") !== "sfu") {
    res.status(400).json({error: "callmode_not_sfu"});
    return;
  }
  try {
    const token = await buildLiveKitToken(sessionId, uid, role);
    const {url} = await liveKitConfig();
    const room = await resolveLiveKitRoomName(sessionId);
    res.json({token, url, room});
  } catch (err) {
    res.status(500).json({error: "livekit_not_configured"});
  }
});

app.post("/session/recording/start", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);
  try {
    await requirePrimaryTutor(sessionId, uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }
  const stateSnap = await sessionStateRef(sessionId).get();
  const state = (stateSnap.data() ?? {}) as Partial<SessionState>;
  if ((state.callMode ?? "p2p") !== "sfu") {
    res.status(400).json({error: "recording_not_allowed"});
    return;
  }
  const recordingRef = sessionRef(sessionId).collection("recordings").doc();
  let egressId: string | null = null;
  const egress = egressConfig();
  if (egress.enabled && egress.bucket) {
    const client = await getEgressClient();
    if (client) {
      try {
        const roomName = await resolveLiveKitRoomName(sessionId);
        const output = new EncodedFileOutput({
          filepath: `${egress.prefix}/${sessionId}/${recordingRef.id}.mp4`,
          fileType: EncodedFileType.MP4,
          output: {
            case: "gcp",
            value: {bucket: egress.bucket},
          },
        });
        const info = await client.startRoomCompositeEgress(roomName, output);
        egressId = info.egressId ?? null;
      } catch (err) {
        logger.error("LiveKit egress start failed", err);
      }
    }
  }
  await sessionStateRef(sessionId).set({
    recordingState: {
      status: "recording",
      startedAt: nowTs(),
      startedBy: uid,
      recordingId: recordingRef.id,
      egressId,
    },
  }, {merge: true});
  await recordingRef.set({
    status: "recording",
    startedAt: nowTs(),
    startedBy: uid,
    provider: "livekit",
    roomName: await resolveLiveKitRoomName(sessionId),
    egressId,
    outputBucket: egress.bucket || null,
    outputPath: egress.bucket ? `${egress.prefix}/${sessionId}/${recordingRef.id}.mp4` : null,
  });
  res.json({ok: true});
});

app.post("/session/recording/stop", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);
  try {
    await requirePrimaryTutor(sessionId, uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }
  const stateSnap = await sessionStateRef(sessionId).get();
  const state = (stateSnap.data() ?? {}) as Partial<SessionState>;
  const recordingState = state.recordingState as Record<string, unknown> | undefined;
  const recordingId = recordingState?.recordingId as string | undefined;
  const egressId = recordingState?.egressId as string | undefined;
  if (egressId) {
    const client = await getEgressClient();
    if (client) {
      try {
        await client.stopEgress(egressId);
      } catch (err) {
        logger.error("LiveKit egress stop failed", err);
      }
    }
  }
  await sessionStateRef(sessionId).set({
    recordingState: {status: "stopped", stoppedAt: nowTs(), stoppedBy: uid, recordingId, egressId},
  }, {merge: true});
  if (recordingId) {
    await sessionRef(sessionId).collection("recordings").doc(recordingId).set({
      status: "stopped",
      stoppedAt: nowTs(),
      stoppedBy: uid,
      egressId: egressId ?? null,
    }, {merge: true});
  }
  res.json({ok: true});
});

app.post("/session/getConnectionInfo", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);
  try {
    await reconcileClassroomReliability(sessionId);
    const info = await getSessionConnectionInfo(sessionId, uid);
    const recoverySnapshot = await buildRecoverySnapshot({
      sessionId,
      participantId: uid,
      connectionInfo: info,
    });
    return res.json({...info, recoverySnapshot});
  } catch (err) {
    const msg = (err as Error).message;
    if (msg === "forbidden") return res.status(403).json({error: msg});
    if (msg === "participant_left") return res.status(409).json({error: msg});
    return res.status(500).json({error: "server_error"});
  }
});

app.post("/session/heartbeat", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);
  const heartbeatSeq = Number(body.heartbeatSeq ?? 0);
  const participantRef = sessionRef(sessionId).collection("participants").doc(uid);
  const now = nowTs();

  try {
    await db.runTransaction(async (tx) => {
      const participantSnap = await tx.get(participantRef);
      if (!participantSnap.exists) throw new Error("forbidden");
      const current = participantSnap.data() ?? {};
      const currentSeq = Number(current.lastHeartbeatSeq ?? 0);
      if (heartbeatSeq > 0 && currentSeq > 0 && heartbeatSeq <= currentSeq) {
        return;
      }
      const reconnectCount = Number(current.reconnectCount ?? 0);
      tx.set(participantRef, {
        presenceState: normalizePresenceState(body.presenceState),
        networkQuality: normalizeNetworkQuality(body.networkQuality),
        mediaHealth: normalizeMediaHealth(body.mediaHealth),
        preferredMediaProfile: body.preferredMediaProfile ? String(body.preferredMediaProfile).trim() : null,
        transportState: body.transportState ? String(body.transportState).trim() : null,
        clientCallModeVersion: Number(body.callModeVersion ?? 0),
        lastHeartbeatAt: now,
        lastSeenAt: now,
        lastHeartbeatSeq: heartbeatSeq > 0 ? heartbeatSeq : currentSeq,
        reconnectCount: body.isReconnect == true ? reconnectCount + 1 : reconnectCount,
        joinState: current.joinState ?? "joined",
      }, {merge: true});
    });

    const projection = await reconcileClassroomReliability(sessionId);
    res.json({
      ok: true,
      tutorPresenceState: projection?.tutorPresenceState ?? "active",
      recommendedMediaProfile: projection?.recommendedMediaProfile ?? "full",
      studentsMayContinue: projection?.studentsMayContinue ?? false,
    });
  } catch (err) {
    const msg = (err as Error).message;
    if (msg === "forbidden") {
      res.status(403).json({error: msg});
      return;
    }
    logger.error("session/heartbeat failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/session/recoverState", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);
  const participantRef = sessionRef(sessionId).collection("participants").doc(uid);

  try {
    await participantRef.set({
      presenceState: "online",
      networkQuality: normalizeNetworkQuality(body.networkQuality),
      mediaHealth: normalizeMediaHealth(body.mediaHealth),
      lastSeenAt: nowTs(),
      lastHeartbeatAt: nowTs(),
      lastRecoveryAt: nowTs(),
      reconnectCount: admin.firestore.FieldValue.increment(1),
      ...(body.forceRejoin == true ? {joinState: "joined"} : {}),
    }, {merge: true});

    await recomputeCountsAndCallMode(sessionId);
    await reconcileClassroomReliability(sessionId);
    const connectionInfo = await getSessionConnectionInfo(sessionId, uid);
    const recoverySnapshot = await buildRecoverySnapshot({
      sessionId,
      participantId: uid,
      connectionInfo,
    });
    res.json({ok: true, recoverySnapshot});
  } catch (err) {
    const msg = (err as Error).message;
    if (msg === "forbidden") {
      res.status(403).json({error: msg});
      return;
    }
    if (msg === "not_found") {
      res.status(404).json({error: msg});
      return;
    }
    if (msg === "participant_left") {
      res.status(409).json({error: msg});
      return;
    }
    logger.error("session/recoverState failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/session/promoteTutor", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId", "targetUid"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);
  const targetUid = String(body.targetUid);
  try {
    await requirePrimaryTutor(sessionId, uid);
    await requireApprovedTutorAccount(uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }
  await db.runTransaction(async (tx) => {
    const currentSessionRef = sessionRef(sessionId);
    const participantRef = currentSessionRef.collection("participants").doc(targetUid);
    const [sessionSnap, participantSnap] = await Promise.all([
      tx.get(currentSessionRef),
      tx.get(participantRef),
    ]);
    if (!sessionSnap.exists || !participantSnap.exists) throw new Error("student_not_found");
    const sessionData = sessionSnap.data() as SessionDoc;
    const participantData = participantSnap.data() ?? {};
    const currentRole = (participantData.role ?? "student") as Role;
    const joined = isJoinedState(participantData.joinState);
    const delta = countDeltaForAdmission({
      wasJoined: joined,
      wasTutor: joined && isTutorRole(currentRole),
      nextJoined: joined,
      nextTutor: joined,
    });
    tx.set(participantRef, {
      role: "coTutor",
      updatedAt: nowTs(),
    }, {merge: true});
    tx.set(currentSessionRef, {
      tutorCount: Math.max(0, Number(sessionData.tutorCount ?? 0) + delta.tutorDelta),
      updatedAt: nowTs(),
    }, {merge: true});
  });
  await recomputeCountsAndCallMode(sessionId);
  await reconcileClassroomReliability(sessionId);
  res.json({ok: true});
});

app.post("/p2p/signal", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId", "pairId", "type", "payload"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);
  const pairId = String(body.pairId);
  const members = normalizePairMembers(body.members);
  if (members.length != 2 || !members.includes(uid)) {
    res.status(400).json({error: "invalid_members"});
    return;
  }
  const role = await getParticipantRole(sessionId, uid);
  if (!role) {
    res.status(403).json({error: "forbidden"});
    return;
  }
  await sessionRef(sessionId).collection("webrtcSignaling").doc(pairId).set({
    [body.type]: body.payload,
    members,
    updatedAt: nowTs(),
    from: uid,
  }, {merge: true});
  res.json({ok: true});
});
app.post("/laser/emit", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId", "payload"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);
  const role = await getParticipantRole(sessionId, uid);
  if (!role) {
    res.status(403).json({error: "forbidden"});
    return;
  }
  await sessionRef(sessionId).collection("laserEvents").doc(uid).set({
    payload: body.payload,
    createdAt: nowTs(),
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 1000 * 15),
  });
  res.json({ok: true});
});

app.post("/voiceNotes/prepare", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId", "targetType", "targetId"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);
  try {
    await requireTutor(sessionId, uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }

  const storagePath = `sessions/${sessionId}/voiceNotes/${uid}/${Date.now()}.m4a`;
  const bucketName = process.env.FIREBASE_STORAGE_BUCKET;
  let uploadUrl: string | null = null;

  if (bucketName && process.env.ENABLE_SIGNED_UPLOADS === "true") {
    const [url] = await admin.storage().bucket(bucketName).file(storagePath).getSignedUrl({
      action: "write",
      expires: Date.now() + 1000 * 60 * 15,
      version: "v4",
      contentType: "audio/m4a",
    });
    uploadUrl = url;
  }

  const noteRef = sessionRef(sessionId).collection("voiceNotes").doc();
  const targetType = String(body.targetType).trim();
  const targetId = String(body.targetId).trim();
  await noteRef.set({
    targetType,
    targetId,
    studentId: targetType === "student" ? targetId : null,
    visibilityScope: targetType === "student" ? "targetedStudentAndTutors" : "tutorOnly",
    storagePath,
    url: body.url ?? null,
    durationSec: Number(body.durationSec ?? 0),
    createdBy: uid,
    createdAt: nowTs(),
  });

  res.json({voiceNoteId: noteRef.id, storagePath, uploadUrl});
});

app.post("/memory/teachMarker", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId", "markerType"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }

  const sessionId = String(body.sessionId);
  try {
    await requireTutor(sessionId, uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }

  const markerType = String(body.markerType).trim().toLowerCase();
  if (!["check", "warn", "star"].includes(markerType)) {
    res.status(400).json({error: "invalid_marker_type"});
    return;
  }

  const markerRef = sessionRef(sessionId).collection("teachMarkers").doc();
  await markerRef.set({
    markerType,
    label: body.label ? String(body.label).trim() : "",
    note: body.note ? String(body.note).trim() : "",
    boardId: body.boardId ? String(body.boardId).trim() : null,
    taskId: body.taskId ? String(body.taskId).trim() : null,
    studentId: body.studentId ? String(body.studentId).trim() : null,
    createdBy: uid,
    createdAt: nowTs(),
  });

  res.json({ok: true, markerId: markerRef.id});
});

app.post("/memory/annotate", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId", "targetType", "targetId", "annotationText"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }

  const sessionId = String(body.sessionId);
  try {
    await requireTutor(sessionId, uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }

  const annotationRef = sessionRef(sessionId).collection("tutorAnnotations").doc();
  await annotationRef.set({
    targetType: String(body.targetType).trim(),
    targetId: String(body.targetId).trim(),
    annotationText: String(body.annotationText).trim(),
    boardId: body.boardId ? String(body.boardId).trim() : null,
    taskId: body.taskId ? String(body.taskId).trim() : null,
    studentId: body.studentId ? String(body.studentId).trim() : null,
    tags: Array.isArray(body.tags) ?
      body.tags.map((tag: unknown) => String(tag).trim()).filter(Boolean) :
      [],
    createdBy: uid,
    createdAt: nowTs(),
  });

  res.json({ok: true, annotationId: annotationRef.id});
});

app.post("/memory/transcriptPointer", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId", "targetType", "targetId", "offsetMs"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }

  const sessionId = String(body.sessionId);
  try {
    await requireTutor(sessionId, uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }

  const offsetMs = Number(body.offsetMs);
  if (!Number.isFinite(offsetMs) || offsetMs < 0) {
    res.status(400).json({error: "invalid_offset"});
    return;
  }

  const pointerRef = sessionRef(sessionId).collection("transcriptPointers").doc();
  await pointerRef.set({
    targetType: String(body.targetType).trim(),
    targetId: String(body.targetId).trim(),
    offsetMs,
    label: body.label ? String(body.label).trim() : "",
    boardId: body.boardId ? String(body.boardId).trim() : null,
    taskId: body.taskId ? String(body.taskId).trim() : null,
    studentId: body.studentId ? String(body.studentId).trim() : null,
    createdBy: uid,
    createdAt: nowTs(),
  });

  res.json({ok: true, pointerId: pointerRef.id});
});

app.post("/memory/refresh", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }

  const sessionId = String(body.sessionId);
  try {
    await requireTutor(sessionId, uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }

  const requestedStrategy = body.strategy ? String(body.strategy).trim() : "manual_rebuild";
  const strategy = requestedStrategy === "cheap_live" || requestedStrategy === "expensive_wrap" ?
    requestedStrategy :
    "manual_rebuild";

  const jobId = await queueClassroomMemoryRefresh({
    sessionId,
    strategy,
    triggerType: "manual_refresh",
    reason: body.reason ? String(body.reason).trim() : undefined,
    createdBy: uid,
  });

  res.json({ok: true, jobId, strategy});
});

app.post("/ai/enqueue", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId", "type"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);
  try {
    await requireTutor(sessionId, uid);
  } catch {
    res.status(403).json({error: "forbidden"});
    return;
  }

  const cacheKey = JSON.stringify({type: body.type, payload: body.payload ?? {}});
  const cacheWindowSec = Number(process.env.AI_CACHE_TTL_SEC ?? 120);
  const recentCutoff = admin.firestore.Timestamp.fromMillis(Date.now() - cacheWindowSec * 1000);
  const cached = await sessionRef(sessionId)
    .collection("aiOutputs")
    .where("cacheKey", "==", cacheKey)
    .where("createdAt", ">", recentCutoff)
    .limit(1)
    .get();

  if (!cached.empty) {
    res.json({cached: true, outputId: cached.docs[0].id});
    return;
  }

  const jobRef = sessionRef(sessionId).collection("aiJobs").doc();
  await jobRef.set({
    actionType: body.type,
    payload: body.payload ?? {},
    status: "queued",
    createdBy: uid,
    createdByRole: "tutor",
    createdAt: nowTs(),
  });
  res.json({jobId: jobRef.id});
});

app.post("/ai/studentSeshHelpRequest", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  const body = req.body ?? {};
  const missing = requireFields(body, ["sessionId", "taskId"]);
  if (missing) {
    res.status(400).json({error: "missing_field", field: missing});
    return;
  }
  const sessionId = String(body.sessionId);
  const taskId = String(body.taskId);
  const role = await getParticipantRole(sessionId, uid);
  if (!role || role !== "student") {
    res.status(403).json({error: "forbidden"});
    return;
  }

  const cooldownSec = Number(process.env.SESH_HELP_COOLDOWN_SEC ?? 120);
  const dailyCap = Number(process.env.SESH_HELP_DAILY_CAP ?? 10);
  const perTaskCap = Number(process.env.SESH_HELP_TASK_CAP ?? 3);
  const dayId = new Date().toISOString().slice(0, 10);

  const usageRef = sessionRef(sessionId).collection("seshHelpUsage").doc(`${uid}_${dayId}`);
  const taskUsageRef = sessionRef(sessionId).collection("seshHelpTasks").doc(`${uid}_${taskId}`);

  const [usageSnap, taskUsageSnap] = await Promise.all([usageRef.get(), taskUsageRef.get()]);
  const usage = usageSnap.data() ?? {};
  const taskUsage = taskUsageSnap.data() ?? {};

  const lastRequest = usage.lastRequestedAt as admin.firestore.Timestamp | undefined;
  if (lastRequest && Date.now() - lastRequest.toMillis() < cooldownSec * 1000) {
    res.status(429).json({error: "cooldown", retryAfterSec: cooldownSec});
    return;
  }

  const countToday = Number(usage.count ?? 0);
  const countTask = Number(taskUsage.count ?? 0);
  if (countToday >= dailyCap) {
    res.status(429).json({error: "daily_cap", recommendTutor: true});
    return;
  }
  if (countTask >= perTaskCap) {
    res.status(429).json({error: "task_cap", recommendTutor: true});
    return;
  }

  await usageRef.set({
    count: countToday + 1,
    lastRequestedAt: nowTs(),
  }, {merge: true});
  await taskUsageRef.set({
    count: countTask + 1,
    lastRequestedAt: nowTs(),
  }, {merge: true});

  const jobRef = sessionRef(sessionId).collection("aiJobs").doc();
  await jobRef.set({
    actionType: "studentHelp",
    payload: {taskId, message: body.message ?? ""},
    status: "queued",
    createdBy: uid,
    createdByRole: "student",
    createdAt: nowTs(),
  });

  res.json({jobId: jobRef.id});
});

export const parallelPracticeV2Api = onRequest({region: REGION}, app);

export const parallelPracticeV2AiWorker = onDocumentCreated({
  document: "sessions/{sessionId}/aiJobs/{jobId}",
  region: REGION,
}, async (event) => {
  const snap = event.data;
  if (!snap) return;
  const data = snap.data() ?? {};
  const sessionId = event.params?.sessionId as string | undefined;
  const actionType = data.actionType as string;
  const payload = data.payload ?? {};
  const currentStatus = String(data.status ?? "").trim().toLowerCase();
  if (["completed", "degraded", "failed", "skipped"].includes(currentStatus)) {
    return;
  }

  await snap.ref.set({status: "processing", startedAt: nowTs()}, {merge: true});

  const outputRef = sessionRef(sessionId || "").collection("aiOutputs").doc(snap.id);
  let result: Record<string, unknown> = {message: "AI output stub", actionType, payload};

  const gatewayUrl = process.env.SESH_AI_GATEWAY_URL;
  if (gatewayUrl) {
    try {
      const response = await fetch(`${gatewayUrl}/ai/quickAction`, {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({
          sessionId,
          actionType,
          payload,
        }),
      });
      if (response.ok) {
        result = await response.json();
      } else {
        result = {error: "gateway_error", status: response.status};
      }
    } catch (err) {
      result = {error: "gateway_exception"};
    }
  } else {
    result = {error: "gateway_not_configured"};
  }

  await outputRef.set({
    jobId: snap.id,
    actionType,
    cacheKey: JSON.stringify({type: actionType, payload}),
    createdBy: data.createdBy ?? null,
    createdByRole: data.createdByRole ?? null,
    studentId: typeof payload.studentId === "string" ? payload.studentId : null,
    accessScope: actionType === "studentHelp" ? "ownerAndTutors" : "tutorOnly",
    result,
    createdAt: nowTs(),
  }, {merge: true});

  const outcomeStatus = typeof result.error === "string" && result.error.trim().length > 0 ?
    "degraded" :
    "completed";

  if (actionType === "sessionPack") {
    const packRef = sessionRef(sessionId || "").collection("sessionPacks").doc();
    const notesRef = outputRef.path;
    const pdfUrl =
      typeof result.smartNotesPdfUrl === "string" && result.smartNotesPdfUrl.trim().length > 0 ?
        result.smartNotesPdfUrl :
        typeof result.pdfUrl === "string" && result.pdfUrl.trim().length > 0 ?
          result.pdfUrl :
          null;
    const summary =
      typeof result.summary === "string" && result.summary.trim().length > 0 ?
        result.summary :
        typeof result.message === "string" && result.message.trim().length > 0 ?
          result.message :
          JSON.stringify(result);
    await packRef.set({
      jobId: snap.id,
      sourceActionType: actionType,
      type: "group",
      studentId: null,
      accessScope: "tutorOnly",
      pdfUrl,
      notesRef,
      summary,
      artifactKind: pdfUrl ? "pdf_plus_notes" : "notes_only",
      generationStatus: outcomeStatus,
      createdAt: nowTs(),
      generatedAt: nowTs(),
    });
  }

  await snap.ref.set({
    status: outcomeStatus,
    completedAt: nowTs(),
    outputId: outputRef.id,
    errorCode: typeof result.error === "string" ? result.error : null,
  }, {merge: true});
});

export const parallelPracticeBoardChunkHandler = onDocumentWritten({
  document: "sessions/{sessionId}/boardEventChunks/{chunkId}",
  region: REGION,
}, async (event) => {
  const after = event.data?.after.data();
  if (!after) return;
  const sessionId = event.params?.sessionId as string | undefined;
  if (!sessionId) return;
  const boardId = after.boardId as string | undefined;
  const ownerId = after.ownerId as string | undefined;

  if (ownerId) {
    await sessionRef(sessionId).collection("participants").doc(ownerId).set({
      lastSeenAt: nowTs(),
      status: "working",
    }, {merge: true});
  }

  if (boardId) {
    await sessionRef(sessionId).collection("thumbnails").doc(boardId).set({
      boardId,
      studentId: ownerId ?? null,
      updatedAt: nowTs(),
    }, {merge: true});
  }
});

export const parallelPracticeThumbnailWorker = onDocumentCreated({
  document: "sessions/{sessionId}/thumbnailJobs/{jobId}",
  region: REGION,
}, async (event) => {
  const snap = event.data;
  if (!snap) return;
  const jobSnap = snap;
  const data = snap.data() ?? {};
  const sessionId = event.params?.sessionId as string | undefined;
  const jobId = event.params?.jobId as string | undefined;
  const boardId = data.boardId as string | undefined;
  const workerUrl = process.env.THUMBNAIL_WORKER_URL;
  const thumbnailRef =
    sessionId && boardId ?
      sessionRef(sessionId).collection("thumbnails").doc(boardId) :
      null;

  async function applyFallback(status: "error" | "skipped", errorCode: string) {
    if (!sessionId || !boardId || !thumbnailRef) {
      await jobSnap.ref.set({status, error: errorCode, completedAt: nowTs()}, {merge: true});
      return;
    }
    const latestSnapshot = await sessionRef(sessionId)
      .collection("boardSnapshots")
      .where("boardId", "==", boardId)
      .orderBy("createdAt", "desc")
      .limit(1)
      .get();
    const snapshotData = latestSnapshot.empty ? {} : latestSnapshot.docs[0].data();
    await thumbnailRef.set({
      boardId,
      studentId: data.ownerId ?? null,
      updatedAt: nowTs(),
      fallbackSnapshotId: latestSnapshot.empty ? null : latestSnapshot.docs[0].id,
      fallbackUrl: snapshotData.url ?? null,
      fallbackStoragePath: snapshotData.storagePath ?? null,
      fallbackState: status,
    }, {merge: true});
    await jobSnap.ref.set({
      status,
      error: errorCode,
      completedAt: nowTs(),
      fallbackSnapshotId: latestSnapshot.empty ? null : latestSnapshot.docs[0].id,
    }, {merge: true});
  }

  await jobSnap.ref.set({status: "processing", startedAt: nowTs()}, {merge: true});

  if (workerUrl && sessionId && jobId && boardId) {
    try {
      const response = await fetch(workerUrl, {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({sessionId, jobId, boardId}),
      });
      if (!response.ok) {
        await applyFallback("error", `worker_${response.status}`);
        return;
      }
      await snap.ref.set({status: "done", completedAt: nowTs()}, {merge: true});
      return;
    } catch (err) {
      await applyFallback("error", "worker_exception");
      return;
    }
  }

  await applyFallback("skipped", "worker_not_configured");
});

export const livekitWebhook = onRequest({region: REGION}, async (req, res) => {
  const receiver = await getWebhookReceiver();
  let body: Record<string, unknown> | undefined =
    typeof req.body === "object" &&
    req.body !== null &&
    !Array.isArray(req.body) ?
      req.body as Record<string, unknown> :
      undefined;

  if (receiver) {
    try {
      const authHeader = req.get("authorization") || "";
      const rawBody = typeof req.rawBody === "string" ? req.rawBody : req.rawBody?.toString("utf8");
      const event = await receiver.receive(rawBody || "", authHeader);
      body = event as unknown as Record<string, unknown>;
    } catch (err) {
      logger.error("LiveKit webhook verification failed", err);
      res.status(401).json({error: "invalid_webhook"});
      return;
    }
  }

  try {
    const egressInfo = [body?.egressInfo, body?.egress, body?.egress_info]
      .find(
        (value): value is Record<string, unknown> =>
          typeof value === "object" &&
          value !== null &&
          !Array.isArray(value)
      );
    const room =
      typeof body?.room === "object" &&
      body?.room !== null &&
      !Array.isArray(body?.room) ?
        body.room as Record<string, unknown> :
        undefined;
    const roomName =
      (egressInfo?.roomName ?? room?.name ?? "").toString().trim();
    const egressId = (egressInfo?.egressId ?? body?.egress_id ?? "")
      .toString()
      .trim();
    const status = (egressInfo?.status ?? body?.status ?? "")
      .toString()
      .trim();
    const rawFileResults = egressInfo?.fileResults ?? egressInfo?.file_results;
    const fileResults = Array.isArray(rawFileResults) ? rawFileResults : [];

    if (roomName && egressId) {
      const resolvedSessionId = await resolveSessionIdFromLiveKitRoom(roomName);
      const recSnap = await sessionRef(resolvedSessionId)
        .collection("recordings")
        .where("egressId", "==", egressId)
        .limit(1)
        .get();
      if (!recSnap.empty) {
        const recRef = recSnap.docs[0].ref;
        await recRef.set({
          egressStatus: status ?? null,
          fileResults,
          updatedAt: nowTs(),
        }, {merge: true});
      }
    }
  } catch (err) {
    logger.error("LiveKit webhook processing failed", err);
  }

  res.json({ok: true});
});
