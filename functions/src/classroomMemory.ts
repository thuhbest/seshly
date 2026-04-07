import * as admin from "firebase-admin";
import * as crypto from "node:crypto";
import * as logger from "firebase-functions/logger";
import {
  onDocumentCreated,
  onDocumentWritten,
} from "firebase-functions/v2/firestore";

const db = admin.firestore();
const REGION = process.env.PARALLEL_PRACTICE_REGION || "europe-west2";

export type ClassroomMemoryStrategy =
  | "cheap_live"
  | "expensive_wrap"
  | "manual_rebuild";

export type ClassroomMemoryFrameType =
  | "teach_marker"
  | "board_event"
  | "task_context"
  | "student_submission"
  | "intervention_moment"
  | "spotlight_interval"
  | "tutor_annotation"
  | "transcript_pointer"
  | "chat_message"
  | "voice_note"
  | "session_transition"
  | "exemplar_moment";

type MemoryImportance = "low" | "medium" | "high";
type JobStatus =
  | "queued"
  | "processing"
  | "completed"
  | "skipped"
  | "degraded"
  | "failed";
type SnapshotStatus = "ready" | "degraded" | "processing";
type ModelTier = "cheap" | "expensive" | "fallback";

interface ClassroomMemoryFrameDoc {
  frameType: ClassroomMemoryFrameType;
  sessionId: string;
  sourceCollection: string;
  sourceId: string;
  actorId: string | null;
  studentId: string | null;
  boardId: string | null;
  taskId: string | null;
  spotlightMode: string | null;
  importance: MemoryImportance;
  strategyHint: ClassroomMemoryStrategy;
  payload: Record<string, unknown>;
  createdAt: admin.firestore.FieldValue | admin.firestore.Timestamp;
}

interface ClassroomMemoryJobDoc {
  sessionId: string;
  strategy: ClassroomMemoryStrategy;
  triggerTypes: string[];
  status: JobStatus;
  reason: string | null;
  createdBy: string | null;
  createdAt: admin.firestore.FieldValue | admin.firestore.Timestamp;
  updatedAt: admin.firestore.FieldValue | admin.firestore.Timestamp;
  lastError: string | null;
  cacheKey: string | null;
  modelTier: ModelTier | null;
  sourceFrameCount: number;
  degraded: boolean;
}

interface GatewayParticipant {
  userId: string;
  role: string;
  displayName?: string | null;
}

interface GatewayLessonSegment {
  label: string;
  summary: string;
  startedAt?: string | null;
  endedAt?: string | null;
  markerType?: string | null;
}

interface GatewayMisconceptionCluster {
  title: string;
  misconception: string;
  evidence: string[];
  reteachAction: string;
}

interface GatewayInterventionMoment {
  studentId: string | null;
  title: string;
  summary: string;
  tutorAction: string;
  followUp: string;
}

interface GatewayExemplarMoment {
  studentId: string | null;
  title: string;
  whyItMatters: string;
  boardId?: string | null;
}

interface GatewayStudentLearningState {
  approach: string[];
  mistakes: string[];
  corrections: string[];
  stuckPoints: string[];
  nextFocusArea: string[];
}

interface GatewaySessionContinuityNotes {
  nextTutorShouldKnow: string[];
  reviseNextTime: string[];
  carryForwardTasks: string[];
  atRiskStudentIds: string[];
}

interface GatewayClassroomMemoryResponse {
  status: SnapshotStatus;
  modelTier: ModelTier;
  provider: string;
  model: string;
  groupLessonMemory: {
    whatWasTaught: string[];
    keyMisconceptions: string[];
    importantExamples: string[];
    reteachMoments: string[];
  };
  lessonSegments: GatewayLessonSegment[];
  misconceptionClusters: GatewayMisconceptionCluster[];
  interventionMoments: GatewayInterventionMoment[];
  exemplarMoments: GatewayExemplarMoment[];
  studentLearningStates: Record<string, GatewayStudentLearningState>;
  sessionContinuityNotes: GatewaySessionContinuityNotes;
}

function nowServerTs() {
  return admin.firestore.FieldValue.serverTimestamp();
}

function sessionRef(sessionId: string) {
  return db.collection("sessions").doc(sessionId);
}

function participantsCollection(sessionId: string) {
  return sessionRef(sessionId).collection("participants");
}

function aiCaptureFramesCollection(sessionId: string) {
  return sessionRef(sessionId).collection("aiCaptureFrames");
}

function aiMemoryJobsCollection(sessionId: string) {
  return sessionRef(sessionId).collection("aiMemoryJobs");
}

function aiMemoryCollection(sessionId: string) {
  return sessionRef(sessionId).collection("aiMemory");
}

function currentMemoryDoc(sessionId: string) {
  return aiMemoryCollection(sessionId).doc("current");
}

function toTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asNumber(value: unknown, fallback = 0): number {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return fallback;
}

function sanitizeObject(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value) ?
    value as Record<string, unknown> :
    {};
}

function toTimestamp(value: unknown): admin.firestore.Timestamp | null {
  if (value instanceof admin.firestore.Timestamp) return value;
  return null;
}

function strategyBucketMs(strategy: ClassroomMemoryStrategy): number {
  switch (strategy) {
  case "expensive_wrap":
    return 5 * 60 * 1000;
  case "manual_rebuild":
    return 60 * 1000;
  case "cheap_live":
  default:
    return 30 * 1000;
  }
}

function strategyModelTier(strategy: ClassroomMemoryStrategy): ModelTier {
  return strategy === "cheap_live" ? "cheap" : "expensive";
}

function buildJobId(strategy: ClassroomMemoryStrategy): string {
  const bucket = Math.floor(Date.now() / strategyBucketMs(strategy));
  return `${strategy}_${bucket}`;
}

function hashCacheKey(parts: string[]): string {
  return crypto.createHash("sha1").update(parts.join("|")).digest("hex");
}

function summarizeText(value: unknown, fallback: string): string {
  const raw = toTrimmedString(value);
  return raw || fallback;
}

function frameImportanceForType(frameType: ClassroomMemoryFrameType): MemoryImportance {
  switch (frameType) {
  case "teach_marker":
  case "intervention_moment":
  case "spotlight_interval":
  case "exemplar_moment":
    return "high";
  case "task_context":
  case "student_submission":
  case "tutor_annotation":
    return "medium";
  default:
    return "low";
  }
}

function strategyForFrameType(frameType: ClassroomMemoryFrameType): ClassroomMemoryStrategy {
  switch (frameType) {
  case "spotlight_interval":
  case "intervention_moment":
  case "exemplar_moment":
    return "cheap_live";
  case "session_transition":
    return "expensive_wrap";
  default:
    return "cheap_live";
  }
}

function snapshotStatus(degraded: boolean): SnapshotStatus {
  return degraded ? "degraded" : "ready";
}

export async function queueClassroomMemoryRefresh(params: {
  sessionId: string;
  strategy: ClassroomMemoryStrategy;
  triggerType: string;
  reason?: string;
  createdBy?: string | null;
}): Promise<string> {
  const jobId = buildJobId(params.strategy);
  const jobRef = aiMemoryJobsCollection(params.sessionId).doc(jobId);
  await db.runTransaction(async (tx) => {
    const existing = await tx.get(jobRef);
    const current = (existing.data() ?? {}) as Partial<ClassroomMemoryJobDoc>;
    tx.set(jobRef, {
      sessionId: params.sessionId,
      strategy: params.strategy,
      triggerTypes: admin.firestore.FieldValue.arrayUnion(params.triggerType),
      status:
        current.status === "processing" || current.status === "completed" ?
          current.status :
          "queued",
      reason: params.reason ?? current.reason ?? null,
      createdBy: params.createdBy ?? current.createdBy ?? null,
      createdAt: existing.exists ? current.createdAt ?? nowServerTs() : nowServerTs(),
      updatedAt: nowServerTs(),
      lastError: null,
      cacheKey: current.cacheKey ?? null,
      modelTier: current.modelTier ?? strategyModelTier(params.strategy),
      sourceFrameCount: asNumber(current.sourceFrameCount, 0),
      degraded: current.degraded === true,
    }, {merge: true});
  });
  return jobId;
}

async function writeCaptureFrame(params: {
  sessionId: string;
  frameType: ClassroomMemoryFrameType;
  sourceCollection: string;
  sourceId: string;
  actorId?: string | null;
  studentId?: string | null;
  boardId?: string | null;
  taskId?: string | null;
  spotlightMode?: string | null;
  payload?: Record<string, unknown>;
}) {
  const frameRef = aiCaptureFramesCollection(params.sessionId).doc();
  const frame: ClassroomMemoryFrameDoc = {
    frameType: params.frameType,
    sessionId: params.sessionId,
    sourceCollection: params.sourceCollection,
    sourceId: params.sourceId,
    actorId: params.actorId ?? null,
    studentId: params.studentId ?? null,
    boardId: params.boardId ?? null,
    taskId: params.taskId ?? null,
    spotlightMode: params.spotlightMode ?? null,
    importance: frameImportanceForType(params.frameType),
    strategyHint: strategyForFrameType(params.frameType),
    payload: params.payload ?? {},
    createdAt: nowServerTs(),
  };
  await frameRef.set(frame);
  await queueClassroomMemoryRefresh({
    sessionId: params.sessionId,
    strategy: frame.strategyHint,
    triggerType: params.frameType,
    createdBy: params.actorId ?? null,
  });
}

function trimList(values: string[], limit = 6): string[] {
  return values
    .map((item) => item.trim())
    .filter((item) => item.length > 0)
    .slice(0, limit);
}

function uniquePush(target: string[], value: string) {
  const item = value.trim();
  if (!item || target.includes(item)) return;
  target.push(item);
}

function buildFallbackMemory(
  sessionId: string,
  strategy: ClassroomMemoryStrategy,
  frames: Array<{id: string; data: Record<string, unknown>}>,
  cacheKey: string
) {
  const taught: string[] = [];
  const misconceptions: string[] = [];
  const examples: string[] = [];
  const reteach: string[] = [];
  const lessonSegments: GatewayLessonSegment[] = [];
  const misconceptionClusters: GatewayMisconceptionCluster[] = [];
  const interventionMoments: GatewayInterventionMoment[] = [];
  const exemplarMoments: GatewayExemplarMoment[] = [];
  const studentLearningStates: Record<string, GatewayStudentLearningState> = {};
  const carryForward: string[] = [];
  const atRiskStudentIds: string[] = [];

  for (const frame of frames) {
    const data = frame.data;
    const payload = sanitizeObject(data.payload);
    const frameType = toTrimmedString(data.frameType) as ClassroomMemoryFrameType;
    const studentId = toTrimmedString(data.studentId) || null;
    const boardId = toTrimmedString(data.boardId) || null;
    const text =
      toTrimmedString(payload.note) ||
      toTrimmedString(payload.summary) ||
      toTrimmedString(payload.label) ||
      toTrimmedString(payload.responseText) ||
      toTrimmedString(payload.message) ||
      toTrimmedString(payload.reason);

    if (frameType === "teach_marker") {
      const markerType = toTrimmedString(payload.markerType);
      lessonSegments.push({
        label: summarizeText(payload.label, markerType || "Teach marker"),
        summary: summarizeText(text, "Tutor flagged a teaching moment."),
        markerType: markerType || null,
      });
      if (markerType === "check") uniquePush(taught, summarizeText(text, "Key concept confirmed."));
      if (markerType === "warn") {
        uniquePush(misconceptions, summarizeText(text, "Potential misconception detected."));
        uniquePush(reteach, summarizeText(text, "Tutor flagged a reteach moment."));
      }
      if (markerType === "star") uniquePush(examples, summarizeText(text, "Important example highlighted."));
    }

    if (frameType === "task_context") {
      uniquePush(taught, summarizeText(text, "New classwork or task context was introduced."));
      lessonSegments.push({
        label: summarizeText(payload.title, "Task launch"),
        summary: summarizeText(text, "Tutor pushed a new task to the class."),
      });
      uniquePush(carryForward, summarizeText(payload.title, "Review the latest classwork task."));
    }

    if (frameType === "student_submission" && studentId) {
      const state = studentLearningStates[studentId] ?? {
        approach: [],
        mistakes: [],
        corrections: [],
        stuckPoints: [],
        nextFocusArea: [],
      };
      uniquePush(
        state.approach,
        summarizeText(payload.responseText, "Student submitted a working attempt.")
      );
      if (toTrimmedString(payload.status) === "submitted") {
        uniquePush(state.nextFocusArea, "Review the submitted method and tighten exam structure.");
      }
      studentLearningStates[studentId] = state;
    }

    if ((frameType === "intervention_moment" || frameType === "spotlight_interval") && studentId) {
      const state = studentLearningStates[studentId] ?? {
        approach: [],
        mistakes: [],
        corrections: [],
        stuckPoints: [],
        nextFocusArea: [],
      };
      uniquePush(
        state.stuckPoints,
        summarizeText(text, "Student needed live intervention during classwork.")
      );
      uniquePush(state.nextFocusArea, "Revisit the exact step that triggered intervention.");
      studentLearningStates[studentId] = state;
      uniquePush(reteach, summarizeText(text, "A focused reteach moment happened."));
      if (!atRiskStudentIds.includes(studentId)) atRiskStudentIds.push(studentId);
      interventionMoments.push({
        studentId,
        title: summarizeText(payload.title, "Tutor intervention"),
        summary: summarizeText(text, "Tutor intervened live on a student board."),
        tutorAction: summarizeText(payload.tutorAction, "Focused correction and explanation."),
        followUp: "Check if the student can repeat the method independently next session.",
      });
    }

    if (frameType === "tutor_annotation" && studentId) {
      const state = studentLearningStates[studentId] ?? {
        approach: [],
        mistakes: [],
        corrections: [],
        stuckPoints: [],
        nextFocusArea: [],
      };
      uniquePush(
        state.corrections,
        summarizeText(text, "Tutor left a correction on the student work.")
      );
      studentLearningStates[studentId] = state;
    }

    if (frameType === "exemplar_moment") {
      uniquePush(examples, summarizeText(text, "Tutor surfaced an exemplar solution path."));
      exemplarMoments.push({
        studentId,
        title: summarizeText(payload.title, "Exemplar work"),
        whyItMatters: summarizeText(text, "This work was strong enough to discuss with the class."),
        boardId,
      });
    }

    if (frameType === "chat_message" && studentId) {
      const state = studentLearningStates[studentId] ?? {
        approach: [],
        mistakes: [],
        corrections: [],
        stuckPoints: [],
        nextFocusArea: [],
      };
      uniquePush(
        state.stuckPoints,
        summarizeText(text, "Student asked for clarification in chat.")
      );
      studentLearningStates[studentId] = state;
    }

    if (frameType === "voice_note" && studentId) {
      const state = studentLearningStates[studentId] ?? {
        approach: [],
        mistakes: [],
        corrections: [],
        stuckPoints: [],
        nextFocusArea: [],
      };
      uniquePush(
        state.corrections,
        "Tutor attached a review voice note for follow-up listening."
      );
      studentLearningStates[studentId] = state;
    }
  }

  for (const misconception of misconceptions.slice(0, 4)) {
    misconceptionClusters.push({
      title: "Key misconception",
      misconception,
      evidence: [misconception],
      reteachAction: "Rebuild the method from first principles and force a second attempt.",
    });
  }

  const lastFrameTs = frames
    .map((frame) => toTimestamp(frame.data.createdAt))
    .filter((value): value is admin.firestore.Timestamp => value != null)
    .sort((a, b) => b.toMillis() - a.toMillis())[0] ?? null;

  return {
    sessionId,
    version: 1,
    status: snapshotStatus(true),
    strategy,
    cacheKey,
    modelTier: "fallback",
    provider: "fallback",
    model: "heuristic-classroom-memory",
    fallbackUsed: true,
    sourceFrameCount: frames.length,
    lastFrameAt: lastFrameTs,
    groupLessonMemory: {
      whatWasTaught: trimList(
        taught.length ? taught : ["The tutor moved the class through live teaching and applied practice."],
        8
      ),
      keyMisconceptions: trimList(
        misconceptions.length ? misconceptions : ["No explicit misconception cluster was captured yet."],
        8
      ),
      importantExamples: trimList(
        examples.length ? examples : ["No explicit exemplar was broadcast yet."],
        6
      ),
      reteachMoments: trimList(
        reteach.length ? reteach : ["Watch for the next intervention or warning marker to trigger reteach."],
        6
      ),
    },
    lessonSegments: lessonSegments.slice(0, 12),
    misconceptionClusters: misconceptionClusters.slice(0, 6),
    interventionMoments: interventionMoments.slice(0, 8),
    exemplarMoments: exemplarMoments.slice(0, 6),
    studentLearningStates,
    sessionContinuityNotes: {
      nextTutorShouldKnow: trimList(
        [
          ...reteach.slice(0, 3),
          ...misconceptions.slice(0, 2),
        ],
        6
      ),
      reviseNextTime: trimList(
        carryForward.length ? carryForward : ["Start by revising the main misconception before new work."],
        6
      ),
      carryForwardTasks: trimList(carryForward, 6),
      atRiskStudentIds,
    },
    updatedAt: nowServerTs(),
    createdAt: nowServerTs(),
    gatewayStatus: "fallback",
  };
}

async function buildGatewayMemory(params: {
  sessionId: string;
  strategy: ClassroomMemoryStrategy;
  cacheKey: string;
  frames: Array<{id: string; data: Record<string, unknown>}>;
  participants: GatewayParticipant[];
  priorSnapshot: Record<string, unknown>;
}): Promise<GatewayClassroomMemoryResponse> {
  const gatewayUrl = (process.env.SESH_AI_GATEWAY_URL || "").trim().replace(/\/+$/, "");
  if (!gatewayUrl) {
    throw new Error("gateway_not_configured");
  }

  const response = await fetch(`${gatewayUrl}/ai/classroom/memory/build`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
    },
    body: JSON.stringify({
      sessionId: params.sessionId,
      strategy: params.strategy,
      cacheKey: params.cacheKey,
      participants: params.participants,
      priorSnapshot: params.priorSnapshot,
      frames: params.frames.map((frame) => ({
        frameId: frame.id,
        ...frame.data,
      })),
    }),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`gateway_error_${response.status}:${text}`);
  }

  return await response.json() as GatewayClassroomMemoryResponse;
}

async function processMemoryJob(sessionId: string, jobId: string) {
  const jobRef = aiMemoryJobsCollection(sessionId).doc(jobId);
  const snapshotRef = currentMemoryDoc(sessionId);
  const jobSnap = await jobRef.get();
  if (!jobSnap.exists) return;

  const jobData = (jobSnap.data() ?? {}) as Partial<ClassroomMemoryJobDoc>;
  const strategy = (toTrimmedString(jobData.strategy) || "cheap_live") as ClassroomMemoryStrategy;

  await jobRef.set({
    status: "processing",
    updatedAt: nowServerTs(),
    modelTier: strategyModelTier(strategy),
  }, {merge: true});

  const [framesSnap, participantsSnap, priorSnapshotSnap] = await Promise.all([
    aiCaptureFramesCollection(sessionId)
      .orderBy("createdAt", "desc")
      .limit(strategy === "cheap_live" ? 120 : 240)
      .get(),
    participantsCollection(sessionId).get(),
    snapshotRef.get(),
  ]);

  const frames = framesSnap.docs
    .map((doc) => ({id: doc.id, data: doc.data() as Record<string, unknown>}))
    .reverse();
  const participants = participantsSnap.docs.map((doc) => ({
    userId: doc.id,
    role: toTrimmedString(doc.get("role")) || "student",
    displayName: toTrimmedString(doc.get("displayName")) || null,
  }));
  const cacheKey = hashCacheKey([
    strategy,
    ...frames.map((frame) => `${frame.id}:${toTrimmedString(frame.data.frameType)}`),
  ]);

  const priorSnapshot = sanitizeObject(priorSnapshotSnap.data());
  if (
    toTrimmedString(priorSnapshot.cacheKey) === cacheKey &&
    toTrimmedString(priorSnapshot.status) === "ready"
  ) {
    await jobRef.set({
      status: "skipped",
      updatedAt: nowServerTs(),
      cacheKey,
      sourceFrameCount: frames.length,
      degraded: false,
      lastError: null,
    }, {merge: true});
    return;
  }

  let nextSnapshot: Record<string, unknown>;
  let degraded = false;

  try {
    const gateway = await buildGatewayMemory({
      sessionId,
      strategy,
      cacheKey,
      frames,
      participants,
      priorSnapshot,
    });
    const lastFrameAt = frames
      .map((frame) => toTimestamp(frame.data.createdAt))
      .filter((value): value is admin.firestore.Timestamp => value != null)
      .sort((a, b) => b.toMillis() - a.toMillis())[0] ?? null;
    nextSnapshot = {
      sessionId,
      version: 1,
      status: gateway.status,
      strategy,
      cacheKey,
      modelTier: gateway.modelTier,
      provider: gateway.provider,
      model: gateway.model,
      fallbackUsed: false,
      sourceFrameCount: frames.length,
      lastFrameAt,
      groupLessonMemory: gateway.groupLessonMemory,
      lessonSegments: gateway.lessonSegments,
      misconceptionClusters: gateway.misconceptionClusters,
      interventionMoments: gateway.interventionMoments,
      exemplarMoments: gateway.exemplarMoments,
      studentLearningStates: gateway.studentLearningStates,
      sessionContinuityNotes: gateway.sessionContinuityNotes,
      updatedAt: nowServerTs(),
      createdAt: priorSnapshotSnap.exists ? priorSnapshot.createdAt ?? nowServerTs() : nowServerTs(),
      gatewayStatus: "ok",
    };
  } catch (error) {
    degraded = true;
    logger.error("Classroom memory gateway failed", {sessionId, jobId, error});
    nextSnapshot = buildFallbackMemory(sessionId, strategy, frames, cacheKey);
    nextSnapshot.lastError = error instanceof Error ? error.message : "gateway_failure";
  }

  await snapshotRef.set(nextSnapshot, {merge: true});
  await jobRef.set({
    status: degraded ? "degraded" : "completed",
    updatedAt: nowServerTs(),
    cacheKey,
    sourceFrameCount: frames.length,
    degraded,
    lastError: degraded ? String(nextSnapshot.lastError ?? "gateway_failure") : null,
  }, {merge: true});
}

export const onclassroommemoryjobcreated = onDocumentCreated({
  document: "sessions/{sessionId}/aiMemoryJobs/{jobId}",
  region: REGION,
}, async (event) => {
  const sessionId = toTrimmedString(event.params?.sessionId);
  const jobId = toTrimmedString(event.params?.jobId);
  if (!sessionId || !jobId) return;
  await processMemoryJob(sessionId, jobId);
});

export const onclassroomsessioneventmemorycreated = onDocumentCreated({
  document: "sessions/{sessionId}/sessionEvents/{eventId}",
  region: REGION,
}, async (event) => {
  const snap = event.data;
  const sessionId = toTrimmedString(event.params?.sessionId);
  const eventId = toTrimmedString(event.params?.eventId);
  if (!snap || !sessionId || !eventId) return;
  const data = snap.data() ?? {};
  const type = toTrimmedString(data.type);
  const payload = sanitizeObject(data.payload);
  const actorId = toTrimmedString(data.createdBy) || null;
  const studentId = toTrimmedString(payload.studentId) || toTrimmedString(data.attentionTarget) || null;

  let frameType: ClassroomMemoryFrameType = "session_transition";
  if (type === "TASK_STARTED" || type === "TASK_COLLECTED") frameType = "task_context";
  if (type === "SPOTLIGHT_STARTED" || type === "SPOTLIGHT_ENDED") frameType = "spotlight_interval";
  if (type === "STUDENT_BOARD_BROADCAST") frameType = "exemplar_moment";

  await writeCaptureFrame({
    sessionId,
    frameType,
    sourceCollection: "sessionEvents",
    sourceId: eventId,
    actorId,
    studentId,
    boardId: toTrimmedString(payload.boardId) || null,
    taskId: toTrimmedString(payload.taskId) || null,
    spotlightMode: toTrimmedString(payload.spotlightMode) || null,
    payload: {
      eventType: type,
      ...payload,
    },
  });
});

export const onclassroomaimomentcreated = onDocumentCreated({
  document: "sessions/{sessionId}/aiMoments/{momentId}",
  region: REGION,
}, async (event) => {
  const snap = event.data;
  const sessionId = toTrimmedString(event.params?.sessionId);
  const momentId = toTrimmedString(event.params?.momentId);
  if (!snap || !sessionId || !momentId) return;
  const data = snap.data() ?? {};
  await writeCaptureFrame({
    sessionId,
    frameType: toTrimmedString(data.type) === "spotlight" ?
      "spotlight_interval" :
      "intervention_moment",
    sourceCollection: "aiMoments",
    sourceId: momentId,
    actorId: toTrimmedString(data.startedBy) || null,
    studentId: toTrimmedString(data.studentId) || null,
    boardId: toTrimmedString(data.boardId) || null,
    spotlightMode: toTrimmedString(data.spotlightMode) || null,
    payload: data,
  });
});

export const onclassroomsubmissionmemorycreated = onDocumentCreated({
  document: "sessions/{sessionId}/submissions/{submissionId}",
  region: REGION,
}, async (event) => {
  const snap = event.data;
  const sessionId = toTrimmedString(event.params?.sessionId);
  const submissionId = toTrimmedString(event.params?.submissionId);
  if (!snap || !sessionId || !submissionId) return;
  const data = snap.data() ?? {};
  await writeCaptureFrame({
    sessionId,
    frameType: "student_submission",
    sourceCollection: "submissions",
    sourceId: submissionId,
    actorId: toTrimmedString(data.studentId) || null,
    studentId: toTrimmedString(data.studentId) || null,
    taskId: toTrimmedString(data.taskId) || null,
    payload: data,
  });
});

export const onclassroomtaskmemorywritten = onDocumentWritten({
  document: "sessions/{sessionId}/tasks/{taskId}",
  region: REGION,
}, async (event) => {
  const after = event.data?.after;
  const sessionId = toTrimmedString(event.params?.sessionId);
  const taskId = toTrimmedString(event.params?.taskId);
  if (!after || !after.exists || !sessionId || !taskId) return;
  const data = after.data() ?? {};
  await writeCaptureFrame({
    sessionId,
    frameType: "task_context",
    sourceCollection: "tasks",
    sourceId: taskId,
    actorId: toTrimmedString(data.createdBy) || null,
    taskId,
    payload: data,
  });
});

export const onclassroomboardmemorywritten = onDocumentWritten({
  document: "sessions/{sessionId}/boardEventChunks/{chunkId}",
  region: REGION,
}, async (event) => {
  const before = event.data?.before;
  const after = event.data?.after;
  const sessionId = toTrimmedString(event.params?.sessionId);
  const chunkId = toTrimmedString(event.params?.chunkId);
  if (!after || !after.exists || !sessionId || !chunkId) return;
  const beforeStatus = toTrimmedString(before?.get("status"));
  const afterStatus = toTrimmedString(after.get("status"));
  if (afterStatus !== "accepted" || beforeStatus === "accepted") return;
  const data = after.data() ?? {};
  await writeCaptureFrame({
    sessionId,
    frameType: "board_event",
    sourceCollection: "boardEventChunks",
    sourceId: chunkId,
    actorId: toTrimmedString(data.writerId) || null,
    boardId: toTrimmedString(data.boardId) || null,
    payload: {
      boardId: toTrimmedString(data.boardId) || null,
      writerId: toTrimmedString(data.writerId) || null,
      seqStart: asNumber(data.seqStart, 0),
      seqEnd: asNumber(data.seqEnd, 0),
      tool: toTrimmedString(data.tool) || null,
      strokeCount: asNumber(data.strokeCount, 0),
      status: afterStatus,
    },
  });
});

export const onclassroomteachmarkercreated = onDocumentCreated({
  document: "sessions/{sessionId}/teachMarkers/{markerId}",
  region: REGION,
}, async (event) => {
  const snap = event.data;
  const sessionId = toTrimmedString(event.params?.sessionId);
  const markerId = toTrimmedString(event.params?.markerId);
  if (!snap || !sessionId || !markerId) return;
  const data = snap.data() ?? {};
  await writeCaptureFrame({
    sessionId,
    frameType: "teach_marker",
    sourceCollection: "teachMarkers",
    sourceId: markerId,
    actorId: toTrimmedString(data.createdBy) || null,
    studentId: toTrimmedString(data.studentId) || null,
    boardId: toTrimmedString(data.boardId) || null,
    taskId: toTrimmedString(data.taskId) || null,
    payload: data,
  });
});

export const onclassroomannotationcreated = onDocumentCreated({
  document: "sessions/{sessionId}/tutorAnnotations/{annotationId}",
  region: REGION,
}, async (event) => {
  const snap = event.data;
  const sessionId = toTrimmedString(event.params?.sessionId);
  const annotationId = toTrimmedString(event.params?.annotationId);
  if (!snap || !sessionId || !annotationId) return;
  const data = snap.data() ?? {};
  await writeCaptureFrame({
    sessionId,
    frameType: "tutor_annotation",
    sourceCollection: "tutorAnnotations",
    sourceId: annotationId,
    actorId: toTrimmedString(data.createdBy) || null,
    studentId: toTrimmedString(data.studentId) || null,
    boardId: toTrimmedString(data.boardId) || null,
    taskId: toTrimmedString(data.taskId) || null,
    payload: data,
  });
});

export const onclassroomtranscriptpointercreated = onDocumentCreated({
  document: "sessions/{sessionId}/transcriptPointers/{pointerId}",
  region: REGION,
}, async (event) => {
  const snap = event.data;
  const sessionId = toTrimmedString(event.params?.sessionId);
  const pointerId = toTrimmedString(event.params?.pointerId);
  if (!snap || !sessionId || !pointerId) return;
  const data = snap.data() ?? {};
  await writeCaptureFrame({
    sessionId,
    frameType: "transcript_pointer",
    sourceCollection: "transcriptPointers",
    sourceId: pointerId,
    actorId: toTrimmedString(data.createdBy) || null,
    studentId: toTrimmedString(data.studentId) || null,
    boardId: toTrimmedString(data.boardId) || null,
    taskId: toTrimmedString(data.taskId) || null,
    payload: data,
  });
});

export const onclassroomchatmessagecreated = onDocumentCreated({
  document: "sessions/{sessionId}/chat/{messageId}",
  region: REGION,
}, async (event) => {
  const snap = event.data;
  const sessionId = toTrimmedString(event.params?.sessionId);
  const messageId = toTrimmedString(event.params?.messageId);
  if (!snap || !sessionId || !messageId) return;
  const data = snap.data() ?? {};
  await writeCaptureFrame({
    sessionId,
    frameType: "chat_message",
    sourceCollection: "chat",
    sourceId: messageId,
    actorId: toTrimmedString(data.senderId) || null,
    studentId: toTrimmedString(data.senderRole) === "student" ?
      toTrimmedString(data.senderId) || null :
      null,
    payload: data,
  });
});

export const onclassroommemoryvoicenotecreated = onDocumentCreated({
  document: "sessions/{sessionId}/voiceNotes/{noteId}",
  region: REGION,
}, async (event) => {
  const snap = event.data;
  const sessionId = toTrimmedString(event.params?.sessionId);
  const noteId = toTrimmedString(event.params?.noteId);
  if (!snap || !sessionId || !noteId) return;
  const data = snap.data() ?? {};
  await writeCaptureFrame({
    sessionId,
    frameType: "voice_note",
    sourceCollection: "voiceNotes",
    sourceId: noteId,
    actorId: toTrimmedString(data.createdBy) || null,
    studentId: toTrimmedString(data.studentId) || null,
    boardId: toTrimmedString(data.boardId) || null,
    payload: data,
  });
});
