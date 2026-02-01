import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {onRequest} from "firebase-functions/v2/https";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import express, {Request, Response, NextFunction} from "express";
import cors from "cors";
import {AccessToken} from "livekit-server-sdk";

const db = admin.firestore();
const REGION = "europe-west1";

type Role = "primaryTutor" | "coTutor" | "student";
type Mode = "teach" | "practice" | "review";

interface AuthedRequest extends Request {
  user?: {uid: string};
}

const DEFAULT_MAX_PARTICIPANTS = 5;

const DEFAULT_RATE_LIMITS: Record<string, {windowSec: number; max: number}> = {
  "session/create": {windowSec: 60, max: 3},
  "session/join": {windowSec: 30, max: 6},
  "session/token": {windowSec: 15, max: 20},
  "session/mode": {windowSec: 10, max: 20},
  "task/create": {windowSec: 30, max: 20},
  "task/submit": {windowSec: 30, max: 30},
  "practice/status": {windowSec: 10, max: 60},
  "practice/requestHelp": {windowSec: 30, max: 10},
  "session/quickAction": {windowSec: 20, max: 15}
};

function getRateLimits(): Record<string, {windowSec: number; max: number}> {
  const raw = process.env.PP_RATE_LIMITS;
  if (!raw) return DEFAULT_RATE_LIMITS;
  try {
    const parsed = JSON.parse(raw);
    return {...DEFAULT_RATE_LIMITS, ...parsed};
  } catch (err) {
    logger.warn("Invalid PP_RATE_LIMITS JSON, using defaults.");
    return DEFAULT_RATE_LIMITS;
  }
}

async function rateLimitOrThrow(uid: string, action: string): Promise<void> {
  const limits = getRateLimits();
  const config = limits[action];
  if (!config) return;

  const now = Date.now();
  const key = `pp_${uid}_${action}`;
  const ref = db.collection("rateLimits").doc(key);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data() ?? {};
    const windowStart = (data.windowStart ?? 0) as number;
    const count = (data.count ?? 0) as number;
    const windowMs = config.windowSec * 1000;

    if (!windowStart || now - windowStart > windowMs) {
      tx.set(ref, {windowStart: now, count: 1, action, uid});
      return;
    }
    if (count + 1 > config.max) {
      throw new Error("rate_limited");
    }
    tx.set(ref, {windowStart, count: count + 1, action, uid}, {merge: true});
  });
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

function requireFields(body: Record<string, unknown>, fields: string[]): string | null {
  for (const field of fields) {
    if (body[field] === undefined || body[field] === null || body[field] === "") {
      return field;
    }
  }
  return null;
}

async function getParticipantRole(sessionId: string, uid: string): Promise<Role | null> {
  const snap = await db
    .collection("sessions")
    .doc(sessionId)
    .collection("participants")
    .doc(uid)
    .get();
  if (!snap.exists) return null;
  const data = snap.data() ?? {};
  return (data.role ?? "student") as Role;
}

async function isParticipant(sessionId: string, uid: string): Promise<boolean> {
  const snap = await db
    .collection("sessions")
    .doc(sessionId)
    .collection("participants")
    .doc(uid)
    .get();
  return snap.exists;
}

async function requireTutor(sessionId: string, uid: string): Promise<Role> {
  const role = await getParticipantRole(sessionId, uid);
  if (role !== "primaryTutor" && role !== "coTutor") {
    throw new Error("forbidden");
  }
  return role as Role;
}

async function requirePrimaryTutor(sessionId: string, uid: string): Promise<void> {
  const role = await getParticipantRole(sessionId, uid);
  if (role !== "primaryTutor") {
    throw new Error("forbidden");
  }
}

function nowTs() {
  return admin.firestore.FieldValue.serverTimestamp();
}

const app = express();
app.use(cors({origin: true}));
app.use(express.json({limit: "2mb"}));
app.use(verifyAuth);

app.post("/session/create", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  try {
    await rateLimitOrThrow(uid, "session/create");
    const body = req.body ?? {};
    const title = (body.title ?? "Parallel Practice") as string;
    const subject = (body.subject ?? "") as string;
    const maxParticipants = Math.min(
      Number(body.maxParticipants ?? DEFAULT_MAX_PARTICIPANTS),
      DEFAULT_MAX_PARTICIPANTS
    );
    const allowCoTutorEnd = Boolean(body.allowCoTutorEnd ?? false);

    const sessionRef = db.collection("sessions").doc();
    const sessionId = sessionRef.id;

    const sessionDoc = {
      title,
      subject,
      ownerId: uid,
      status: "active",
      mode: "teach" as Mode,
      maxParticipants,
      allowCoTutorEnd,
      participantIds: [uid],
      activeParticipantIds: [uid],
      tutorIds: [uid],
      createdAt: nowTs(),
      updatedAt: nowTs(),
      lastModeChangeAt: nowTs()
    };

    await db.runTransaction(async (tx) => {
      tx.set(sessionRef, sessionDoc);
      tx.set(sessionRef.collection("participants").doc(uid), {
        userId: uid,
        role: "primaryTutor" as Role,
        joinedAt: nowTs(),
        lastActiveAt: nowTs(),
        status: "active",
        progress: 0,
        isActive: true
      });
    });

    res.json({sessionId});
  } catch (err) {
    if ((err as Error).message === "rate_limited") {
      res.status(429).json({error: "rate_limited"});
      return;
    }
    logger.error("session/create failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/session/join", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  try {
    await rateLimitOrThrow(uid, "session/join");
    const body = req.body ?? {};
    const missing = requireFields(body, ["sessionId"]);
    if (missing) {
      res.status(400).json({error: "missing_field", field: missing});
      return;
    }
    const sessionId = String(body.sessionId);
    const sessionRef = db.collection("sessions").doc(sessionId);

    await db.runTransaction(async (tx) => {
      const sessionSnap = await tx.get(sessionRef);
      if (!sessionSnap.exists) throw new Error("not_found");
      const session = sessionSnap.data() ?? {};
      if (session.status !== "active") throw new Error("session_closed");
      const maxParticipants = session.maxParticipants ?? DEFAULT_MAX_PARTICIPANTS;
      const activeIds = (session.activeParticipantIds ?? []) as string[];
      if (!activeIds.includes(uid) && activeIds.length >= maxParticipants) {
        throw new Error("capacity");
      }

      const participantRef = sessionRef.collection("participants").doc(uid);
      const existing = await tx.get(participantRef);
      if (!existing.exists) {
        tx.set(participantRef, {
          userId: uid,
          role: "student" as Role,
          joinedAt: nowTs(),
          lastActiveAt: nowTs(),
          status: "active",
          progress: 0,
          isActive: true
        });
      } else {
        tx.set(participantRef, {isActive: true, lastActiveAt: nowTs()}, {merge: true});
      }

      tx.set(sessionRef, {
        participantIds: admin.firestore.FieldValue.arrayUnion(uid),
        activeParticipantIds: admin.firestore.FieldValue.arrayUnion(uid),
        updatedAt: nowTs()
      }, {merge: true});
    });

    res.json({ok: true});
  } catch (err) {
    const msg = (err as Error).message;
    if (msg === "capacity") {
      res.status(409).json({error: "session_full"});
      return;
    }
    if (msg === "not_found") {
      res.status(404).json({error: "not_found"});
      return;
    }
    if (msg === "session_closed") {
      res.status(409).json({error: "session_closed"});
      return;
    }
    if (msg === "rate_limited") {
      res.status(429).json({error: "rate_limited"});
      return;
    }
    logger.error("session/join failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/session/leave", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  try {
    const body = req.body ?? {};
    const missing = requireFields(body, ["sessionId"]);
    if (missing) {
      res.status(400).json({error: "missing_field", field: missing});
      return;
    }
    const sessionId = String(body.sessionId);
    const sessionRef = db.collection("sessions").doc(sessionId);
    await db.runTransaction(async (tx) => {
      const participantRef = sessionRef.collection("participants").doc(uid);
      tx.set(participantRef, {
        isActive: false,
        leftAt: nowTs(),
        lastActiveAt: nowTs()
      }, {merge: true});
      tx.set(sessionRef, {
        activeParticipantIds: admin.firestore.FieldValue.arrayRemove(uid),
        updatedAt: nowTs()
      }, {merge: true});
    });
    res.json({ok: true});
  } catch (err) {
    logger.error("session/leave failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/session/end", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  try {
    const body = req.body ?? {};
    const missing = requireFields(body, ["sessionId"]);
    if (missing) {
      res.status(400).json({error: "missing_field", field: missing});
      return;
    }
    const sessionId = String(body.sessionId);
    const sessionRef = db.collection("sessions").doc(sessionId);
    const sessionSnap = await sessionRef.get();
    if (!sessionSnap.exists) {
      res.status(404).json({error: "not_found"});
      return;
    }
    const session = sessionSnap.data() ?? {};
    const allowCoTutorEnd = Boolean(session.allowCoTutorEnd ?? false);
    const role = await getParticipantRole(sessionId, uid);
    if (role !== "primaryTutor" && !(allowCoTutorEnd && role === "coTutor")) {
      res.status(403).json({error: "forbidden"});
      return;
    }
    await sessionRef.set({
      status: "ended",
      endedAt: nowTs(),
      updatedAt: nowTs()
    }, {merge: true});
    res.json({ok: true});
  } catch (err) {
    logger.error("session/end failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/session/mode", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  try {
    await rateLimitOrThrow(uid, "session/mode");
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
    await requireTutor(sessionId, uid);
    const sessionRef = db.collection("sessions").doc(sessionId);
    await sessionRef.set({
      mode,
      lastModeChangeAt: nowTs(),
      updatedAt: nowTs()
    }, {merge: true});
    await sessionRef.collection("events").add({
      type: "mode_change",
      mode,
      createdBy: uid,
      createdAt: nowTs()
    });
    res.json({ok: true});
  } catch (err) {
    if ((err as Error).message === "forbidden") {
      res.status(403).json({error: "forbidden"});
      return;
    }
    if ((err as Error).message === "rate_limited") {
      res.status(429).json({error: "rate_limited"});
      return;
    }
    logger.error("session/mode failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/session/marker", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  try {
    const body = req.body ?? {};
    const missing = requireFields(body, ["sessionId", "markerType", "timestampMs"]);
    if (missing) {
      res.status(400).json({error: "missing_field", field: missing});
      return;
    }
    const sessionId = String(body.sessionId);
    const markerType = String(body.markerType);
    await requireTutor(sessionId, uid);
    const marker = {
      type: markerType,
      timestampMs: Number(body.timestampMs),
      boardSnapshotId: body.boardSnapshotId ?? null,
      note: body.note ?? "",
      createdBy: uid,
      createdAt: nowTs()
    };
    await db
      .collection("sessions")
      .doc(sessionId)
      .collection("markers")
      .add(marker);
    res.json({ok: true});
  } catch (err) {
    if ((err as Error).message === "forbidden") {
      res.status(403).json({error: "forbidden"});
      return;
    }
    logger.error("session/marker failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/session/snapshot", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  try {
    const body = req.body ?? {};
    const missing = requireFields(body, ["sessionId", "url", "storagePath"]);
    if (missing) {
      res.status(400).json({error: "missing_field", field: missing});
      return;
    }
    const sessionId = String(body.sessionId);
    if (!(await isParticipant(sessionId, uid))) {
      res.status(403).json({error: "forbidden"});
      return;
    }
    const doc = {
      url: body.url,
      storagePath: body.storagePath,
      ownerId: uid,
      mode: body.mode ?? "practice",
      studentId: body.studentId ?? uid,
      createdAt: nowTs()
    };
    const ref = await db
      .collection("sessions")
      .doc(sessionId)
      .collection("boardSnapshots")
      .add(doc);
    res.json({snapshotId: ref.id});
  } catch (err) {
    logger.error("session/snapshot failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/session/inviteTutor", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  try {
    const body = req.body ?? {};
    const missing = requireFields(body, ["sessionId", "invitedUserId"]);
    if (missing) {
      res.status(400).json({error: "missing_field", field: missing});
      return;
    }
    const sessionId = String(body.sessionId);
    const invitedUserId = String(body.invitedUserId);
    await requireTutor(sessionId, uid);
    const inviteRef = db
      .collection("sessions")
      .doc(sessionId)
      .collection("invites")
      .doc(invitedUserId);
    await inviteRef.set({
      invitedUserId,
      createdBy: uid,
      status: "pending",
      createdAt: nowTs()
    }, {merge: true});
    res.json({inviteId: inviteRef.id});
  } catch (err) {
    if ((err as Error).message === "forbidden") {
      res.status(403).json({error: "forbidden"});
      return;
    }
    logger.error("session/inviteTutor failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/session/acceptInvite", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  try {
    const body = req.body ?? {};
    const missing = requireFields(body, ["sessionId"]);
    if (missing) {
      res.status(400).json({error: "missing_field", field: missing});
      return;
    }
    const sessionId = String(body.sessionId);
    const inviteRef = db
      .collection("sessions")
      .doc(sessionId)
      .collection("invites")
      .doc(uid);
    const inviteSnap = await inviteRef.get();
    if (!inviteSnap.exists) {
      res.status(404).json({error: "invite_not_found"});
      return;
    }
    const invite = inviteSnap.data() ?? {};
    if (invite.invitedUserId !== uid) {
      res.status(403).json({error: "forbidden"});
      return;
    }
    if (invite.status === "accepted") {
      res.json({ok: true});
      return;
    }
    const sessionRef = db.collection("sessions").doc(sessionId);
    await db.runTransaction(async (tx) => {
      tx.set(inviteRef, {status: "accepted", acceptedAt: nowTs()}, {merge: true});
      tx.set(sessionRef.collection("participants").doc(uid), {
        userId: uid,
        role: "coTutor" as Role,
        joinedAt: nowTs(),
        lastActiveAt: nowTs(),
        status: "active",
        progress: 0,
        isActive: true
      }, {merge: true});
      tx.set(sessionRef, {
        participantIds: admin.firestore.FieldValue.arrayUnion(uid),
        activeParticipantIds: admin.firestore.FieldValue.arrayUnion(uid),
        tutorIds: admin.firestore.FieldValue.arrayUnion(uid),
        updatedAt: nowTs()
      }, {merge: true});
    });
    res.json({ok: true});
  } catch (err) {
    logger.error("session/acceptInvite failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/session/promoteTutor", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  try {
    const body = req.body ?? {};
    const missing = requireFields(body, ["sessionId", "userId"]);
    if (missing) {
      res.status(400).json({error: "missing_field", field: missing});
      return;
    }
    const sessionId = String(body.sessionId);
    const targetUserId = String(body.userId);
    await requirePrimaryTutor(sessionId, uid);
    const participantRef = db
      .collection("sessions")
      .doc(sessionId)
      .collection("participants")
      .doc(targetUserId);
    await participantRef.set({role: "coTutor"}, {merge: true});
    await db.collection("sessions").doc(sessionId).set({
      tutorIds: admin.firestore.FieldValue.arrayUnion(targetUserId),
      updatedAt: nowTs()
    }, {merge: true});
    res.json({ok: true});
  } catch (err) {
    if ((err as Error).message === "forbidden") {
      res.status(403).json({error: "forbidden"});
      return;
    }
    logger.error("session/promoteTutor failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/practice/status", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  try {
    await rateLimitOrThrow(uid, "practice/status");
    const body = req.body ?? {};
    const missing = requireFields(body, ["sessionId"]);
    if (missing) {
      res.status(400).json({error: "missing_field", field: missing});
      return;
    }
    const sessionId = String(body.sessionId);
    if (!(await isParticipant(sessionId, uid))) {
      res.status(403).json({error: "forbidden"});
      return;
    }
    const status = body.status ?? "working";
    const progress = Number(body.progress ?? 0);
    await db
      .collection("sessions")
      .doc(sessionId)
      .collection("participants")
      .doc(uid)
      .set({
        status,
        progress,
        lastActivityAt: nowTs(),
        lastActiveAt: nowTs()
      }, {merge: true});
    res.json({ok: true});
  } catch (err) {
    if ((err as Error).message === "rate_limited") {
      res.status(429).json({error: "rate_limited"});
      return;
    }
    logger.error("practice/status failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/practice/requestHelp", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  try {
    await rateLimitOrThrow(uid, "practice/requestHelp");
    const body = req.body ?? {};
    const missing = requireFields(body, ["sessionId"]);
    if (missing) {
      res.status(400).json({error: "missing_field", field: missing});
      return;
    }
    const sessionId = String(body.sessionId);
    if (!(await isParticipant(sessionId, uid))) {
      res.status(403).json({error: "forbidden"});
      return;
    }
    await db
      .collection("sessions")
      .doc(sessionId)
      .collection("participants")
      .doc(uid)
      .set({
        status: "stuck",
        helpMessage: body.message ?? "",
        lastActivityAt: nowTs()
      }, {merge: true});
    await db.collection("sessions").doc(sessionId).collection("events").add({
      type: "help_request",
      createdBy: uid,
      message: body.message ?? "",
      createdAt: nowTs()
    });
    res.json({ok: true});
  } catch (err) {
    if ((err as Error).message === "rate_limited") {
      res.status(429).json({error: "rate_limited"});
      return;
    }
    logger.error("practice/requestHelp failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/practice/action", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  try {
    const body = req.body ?? {};
    const missing = requireFields(body, ["sessionId", "action"]);
    if (missing) {
      res.status(400).json({error: "missing_field", field: missing});
      return;
    }
    const sessionId = String(body.sessionId);
    await requireTutor(sessionId, uid);
    const action = String(body.action);
    const payload = body.payload ?? {};
    const sessionRef = db.collection("sessions").doc(sessionId);

    if (action === "collectNow") {
      await sessionRef.set({
        mode: "review",
        lastModeChangeAt: nowTs(),
        updatedAt: nowTs()
      }, {merge: true});
    }

    await sessionRef.collection("events").add({
      type: "practice_action",
      action,
      payload,
      createdBy: uid,
      createdAt: nowTs()
    });
    res.json({ok: true});
  } catch (err) {
    if ((err as Error).message === "forbidden") {
      res.status(403).json({error: "forbidden"});
      return;
    }
    logger.error("practice/action failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/task/create", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  try {
    await rateLimitOrThrow(uid, "task/create");
    const body = req.body ?? {};
    const missing = requireFields(body, ["sessionId", "prompt"]);
    if (missing) {
      res.status(400).json({error: "missing_field", field: missing});
      return;
    }
    const sessionId = String(body.sessionId);
    await requireTutor(sessionId, uid);
    const taskRef = db
      .collection("sessions")
      .doc(sessionId)
      .collection("tasks")
      .doc();

    const task = {
      prompt: body.prompt,
      attachments: body.attachments ?? [],
      timerSec: Number(body.timerSec ?? 0),
      submissionFormat: body.submissionFormat ?? "final",
      allowSeshHelp: body.allowSeshHelp ?? true,
      rubric: body.rubric ?? "",
      expectedSolution: body.expectedSolution ?? "",
      createdBy: uid,
      status: "active",
      createdAt: nowTs()
    };

    await taskRef.set(task);
    res.json({taskId: taskRef.id});
  } catch (err) {
    if ((err as Error).message === "forbidden") {
      res.status(403).json({error: "forbidden"});
      return;
    }
    if ((err as Error).message === "rate_limited") {
      res.status(429).json({error: "rate_limited"});
      return;
    }
    logger.error("task/create failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/task/submit", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  try {
    await rateLimitOrThrow(uid, "task/submit");
    const body = req.body ?? {};
    const missing = requireFields(body, ["sessionId", "taskId"]);
    if (missing) {
      res.status(400).json({error: "missing_field", field: missing});
      return;
    }
    const sessionId = String(body.sessionId);
    const taskId = String(body.taskId);
    if (!(await isParticipant(sessionId, uid))) {
      res.status(403).json({error: "forbidden"});
      return;
    }
    const submissionRef = db
      .collection("sessions")
      .doc(sessionId)
      .collection("submissions")
      .doc(`${taskId}_${uid}`);
    await submissionRef.set({
      sessionId,
      taskId,
      studentId: uid,
      responseText: body.responseText ?? "",
      snapshotUrl: body.snapshotUrl ?? null,
      snapshotPath: body.snapshotPath ?? null,
      status: "submitted",
      submittedAt: nowTs()
    }, {merge: true});
    res.json({ok: true});
  } catch (err) {
    if ((err as Error).message === "rate_limited") {
      res.status(429).json({error: "rate_limited"});
      return;
    }
    logger.error("task/submit failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/task/template/save", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  try {
    const body = req.body ?? {};
    const missing = requireFields(body, ["sessionId", "title", "prompt"]);
    if (missing) {
      res.status(400).json({error: "missing_field", field: missing});
      return;
    }
    const sessionId = String(body.sessionId);
    await requireTutor(sessionId, uid);
    const templateRef = db
      .collection("sessions")
      .doc(sessionId)
      .collection("templates")
      .doc();
    await templateRef.set({
      title: body.title,
      prompt: body.prompt,
      attachments: body.attachments ?? [],
      rubric: body.rubric ?? "",
      expectedSolution: body.expectedSolution ?? "",
      createdBy: uid,
      createdAt: nowTs()
    });
    res.json({templateId: templateRef.id});
  } catch (err) {
    if ((err as Error).message === "forbidden") {
      res.status(403).json({error: "forbidden"});
      return;
    }
    logger.error("task/template/save failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/task/template/list", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  try {
    const body = req.body ?? {};
    const missing = requireFields(body, ["sessionId"]);
    if (missing) {
      res.status(400).json({error: "missing_field", field: missing});
      return;
    }
    const sessionId = String(body.sessionId);
    await requireTutor(sessionId, uid);
    const snap = await db
      .collection("sessions")
      .doc(sessionId)
      .collection("templates")
      .orderBy("createdAt", "desc")
      .limit(50)
      .get();
    const templates = snap.docs.map((doc) => ({id: doc.id, ...doc.data()}));
    res.json({templates});
  } catch (err) {
    if ((err as Error).message === "forbidden") {
      res.status(403).json({error: "forbidden"});
      return;
    }
    logger.error("task/template/list failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/session/quickAction", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  try {
    await rateLimitOrThrow(uid, "session/quickAction");
    const body = req.body ?? {};
    const missing = requireFields(body, ["sessionId", "actionType"]);
    if (missing) {
      res.status(400).json({error: "missing_field", field: missing});
      return;
    }
    const sessionId = String(body.sessionId);
    await requireTutor(sessionId, uid);
    const jobRef = db
      .collection("sessions")
      .doc(sessionId)
      .collection("aiJobs")
      .doc();
    await jobRef.set({
      actionType: body.actionType,
      payload: body.payload ?? {},
      status: "queued",
      createdBy: uid,
      createdAt: nowTs()
    });
    res.json({jobId: jobRef.id});
  } catch (err) {
    if ((err as Error).message === "forbidden") {
      res.status(403).json({error: "forbidden"});
      return;
    }
    if ((err as Error).message === "rate_limited") {
      res.status(429).json({error: "rate_limited"});
      return;
    }
    logger.error("session/quickAction failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/session/recording/start", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  try {
    const body = req.body ?? {};
    const missing = requireFields(body, ["sessionId"]);
    if (missing) {
      res.status(400).json({error: "missing_field", field: missing});
      return;
    }
    const sessionId = String(body.sessionId);
    await requireTutor(sessionId, uid);
    const sessionRef = db.collection("sessions").doc(sessionId);
    await sessionRef.set({
      recording: {status: "recording", startedAt: nowTs(), startedBy: uid},
      updatedAt: nowTs()
    }, {merge: true});
    await sessionRef.collection("recordings").add({
      status: "recording",
      startedAt: nowTs(),
      startedBy: uid
    });
    res.json({ok: true});
  } catch (err) {
    if ((err as Error).message === "forbidden") {
      res.status(403).json({error: "forbidden"});
      return;
    }
    logger.error("session/recording/start failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/session/recording/stop", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  try {
    const body = req.body ?? {};
    const missing = requireFields(body, ["sessionId"]);
    if (missing) {
      res.status(400).json({error: "missing_field", field: missing});
      return;
    }
    const sessionId = String(body.sessionId);
    await requireTutor(sessionId, uid);
    const sessionRef = db.collection("sessions").doc(sessionId);
    await sessionRef.set({
      recording: {status: "stopped", stoppedAt: nowTs(), stoppedBy: uid},
      updatedAt: nowTs()
    }, {merge: true});
    await sessionRef.collection("recordings").add({
      status: "stopped",
      stoppedAt: nowTs(),
      stoppedBy: uid
    });
    res.json({ok: true});
  } catch (err) {
    if ((err as Error).message === "forbidden") {
      res.status(403).json({error: "forbidden"});
      return;
    }
    logger.error("session/recording/stop failed", err);
    res.status(500).json({error: "server_error"});
  }
});

app.post("/session/token", async (req: AuthedRequest, res: Response) => {
  const uid = req.user!.uid;
  try {
    await rateLimitOrThrow(uid, "session/token");
    const body = req.body ?? {};
    const missing = requireFields(body, ["sessionId"]);
    if (missing) {
      res.status(400).json({error: "missing_field", field: missing});
      return;
    }
    const sessionId = String(body.sessionId);
    if (!(await isParticipant(sessionId, uid))) {
      res.status(403).json({error: "forbidden"});
      return;
    }
    const apiKey = process.env.LIVEKIT_API_KEY || "";
    const apiSecret = process.env.LIVEKIT_API_SECRET || "";
    const livekitUrl = process.env.LIVEKIT_URL || "";
    if (!apiKey || !apiSecret || !livekitUrl) {
      res.status(500).json({error: "livekit_not_configured"});
      return;
    }
    const role = await getParticipantRole(sessionId, uid);
    const token = new AccessToken(apiKey, apiSecret, {
      identity: uid,
      ttl: "2h",
      metadata: JSON.stringify({role})
    });
    token.addGrant({
      room: sessionId,
      roomJoin: true,
      canPublish: true,
      canSubscribe: true,
      canPublishData: true
    });
    res.json({
      token: token.toJwt(),
      url: livekitUrl,
      room: sessionId,
      role
    });
  } catch (err) {
    if ((err as Error).message === "rate_limited") {
      res.status(429).json({error: "rate_limited"});
      return;
    }
    logger.error("session/token failed", err);
    res.status(500).json({error: "server_error"});
  }
});

export const parallelPracticeApi = onRequest({region: REGION}, app);

export const parallelPracticeAiWorker = onDocumentCreated({
  document: "sessions/{sessionId}/aiJobs/{jobId}",
  region: REGION,
}, async (event) => {
  const snap = event.data;
  if (!snap) return;
  const data = snap.data() ?? {};
  await snap.ref.set({status: "processing", startedAt: nowTs()}, {merge: true});
  await snap.ref.set({
    status: "completed",
    completedAt: nowTs(),
    result: {
      message: "Queued for processing",
      actionType: data.actionType ?? "unknown"
    }
  }, {merge: true});
});
