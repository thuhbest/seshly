import * as admin from "firebase-admin";
import * as crypto from "node:crypto";
import * as logger from "firebase-functions/logger";
import {onDocumentWritten} from "firebase-functions/v2/firestore";

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();
const REGION = process.env.PARALLEL_PRACTICE_REGION || "europe-west2";
const SESSION_STATE_DOC_ID = "sessionState";
const HEARTBEAT_STALE_MS = Number(process.env.CLASSROOM_HEARTBEAT_STALE_MS ?? 90000);

type SessionRole = "primaryTutor" | "coTutor" | "student";
type ClassroomRoomMode = "teach" | "practice" | "review";
type CallMode = "p2p" | "sfu";
export type TutorPresenceState = "active" | "practiceAutonomous" | "pausedTutor";
export type RecommendedMediaProfile = "full" | "audio_priority" | "board_priority";

export interface ReliabilityParticipantView {
  id: string;
  role: SessionRole;
  joinState: string;
  presenceState: string;
  networkQuality: string;
  mediaHealth: string;
  lastSeenAt: admin.firestore.Timestamp | null;
  lastHeartbeatAt: admin.firestore.Timestamp | null;
}

export interface ReliabilityProjection {
  activeParticipantCount: number;
  activeTutorCount: number;
  weakConnectionCount: number;
  tutorPresenceState: TutorPresenceState;
  recommendedMediaProfile: RecommendedMediaProfile;
  studentsMayContinue: boolean;
}

function nowServerTs() {
  return admin.firestore.FieldValue.serverTimestamp();
}

function nowMs(): number {
  return Date.now();
}

function sessionRef(sessionId: string) {
  return db.collection("sessions").doc(sessionId);
}

function sessionStateRef(sessionId: string) {
  return sessionRef(sessionId).collection("sessionState").doc(SESSION_STATE_DOC_ID);
}

function participantsCollection(sessionId: string) {
  return sessionRef(sessionId).collection("participants");
}

function boardRoutesCollection(sessionId: string) {
  return sessionRef(sessionId).collection("boardRoutes");
}

function boardsCollection(sessionId: string) {
  return sessionRef(sessionId).collection("boards");
}

function tasksCollection(sessionId: string) {
  return sessionRef(sessionId).collection("tasks");
}

function submissionsCollection(sessionId: string) {
  return sessionRef(sessionId).collection("submissions");
}

function boardSnapshotsCollection(sessionId: string) {
  return sessionRef(sessionId).collection("boardSnapshots");
}

function boardChunksCollection(sessionId: string) {
  return sessionRef(sessionId).collection("boardEventChunks");
}

function thumbnailsCollection(sessionId: string) {
  return sessionRef(sessionId).collection("thumbnails");
}

function reliabilityEventsCollection(sessionId: string) {
  return sessionRef(sessionId).collection("reliabilityEvents");
}

function reliabilityMetricsRef(sessionId: string) {
  return sessionRef(sessionId).collection("reliabilityMetrics").doc("current");
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

function asTimestamp(value: unknown): admin.firestore.Timestamp | null {
  return value instanceof admin.firestore.Timestamp ? value : null;
}

function asStringArray(value: unknown): string[] {
  return Array.isArray(value) ?
    value.map((item) => String(item).trim()).filter((item) => item.length > 0) :
    [];
}

function sanitizeObject(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value) ?
    value as Record<string, unknown> :
    {};
}

function normalizeRole(value: unknown): SessionRole {
  const raw = toTrimmedString(value);
  if (raw === "primaryTutor" || raw === "coTutor") return raw;
  return "student";
}

function normalizeRoomMode(value: unknown): ClassroomRoomMode {
  const raw = toTrimmedString(value);
  if (raw === "practice" || raw === "review") return raw;
  return "teach";
}

function normalizeCallMode(value: unknown): CallMode {
  return toTrimmedString(value) === "sfu" ? "sfu" : "p2p";
}

function normalizeTutorPresenceState(value: unknown): TutorPresenceState {
  const raw = toTrimmedString(value);
  if (raw === "practiceAutonomous" || raw === "pausedTutor") return raw;
  return "active";
}

function normalizeMediaProfile(value: unknown): RecommendedMediaProfile {
  const raw = toTrimmedString(value);
  if (raw === "audio_priority" || raw === "board_priority") return raw;
  return "full";
}

function participantFromDoc(doc: admin.firestore.QueryDocumentSnapshot): ReliabilityParticipantView {
  const data = doc.data() ?? {};
  return {
    id: doc.id,
    role: normalizeRole(data.role),
    joinState: toTrimmedString(data.joinState) || "joined",
    presenceState: toTrimmedString(data.presenceState) || "online",
    networkQuality: toTrimmedString(data.networkQuality) || "unknown",
    mediaHealth: toTrimmedString(data.mediaHealth) || "stable",
    lastSeenAt: asTimestamp(data.lastSeenAt),
    lastHeartbeatAt: asTimestamp(data.lastHeartbeatAt),
  };
}

export function participantIsLive(
  participant: ReliabilityParticipantView,
  referenceMs: number,
  staleMs = HEARTBEAT_STALE_MS,
): boolean {
  if (participant.joinState === "left") return false;
  if (participant.presenceState === "offline") return false;
  const seenAt = participant.lastHeartbeatAt ?? participant.lastSeenAt;
  if (!seenAt) return participant.presenceState === "online";
  return referenceMs - seenAt.toMillis() <= staleMs;
}

function participantIsWeak(participant: ReliabilityParticipantView): boolean {
  return ["weak", "poor", "unstable"].includes(participant.networkQuality) ||
    ["degraded", "recovering"].includes(participant.mediaHealth);
}

export function deriveTutorPresenceState(params: {
  activeTutorCount: number;
  roomMode: ClassroomRoomMode;
  activeTaskId: string | null;
}): TutorPresenceState {
  if (params.activeTutorCount > 0) return "active";
  if (params.roomMode === "practice" && !!params.activeTaskId) {
    return "practiceAutonomous";
  }
  return "pausedTutor";
}

export function deriveRecommendedMediaProfile(params: {
  callMode: CallMode;
  activeParticipantCount: number;
  weakConnectionCount: number;
  tutorPresenceState: TutorPresenceState;
}): RecommendedMediaProfile {
  if (params.weakConnectionCount > 0) return "audio_priority";
  if (params.callMode === "sfu" && params.activeParticipantCount >= 4) {
    return "board_priority";
  }
  if (params.tutorPresenceState === "pausedTutor") return "audio_priority";
  return "full";
}

export function calculateTimerRemainingMs(
  timerEndAtMs: number | null,
  referenceNowMs: number,
): number | null {
  if (timerEndAtMs == null) return null;
  return Math.max(0, timerEndAtMs - referenceNowMs);
}

export function buildReliabilityEventId(params: {
  sessionId: string;
  kind: string;
  signature: string;
}): string {
  const digest = crypto
    .createHash("sha1")
    .update(`${params.sessionId}|${params.kind}|${params.signature}`)
    .digest("hex")
    .slice(0, 16);
  return `${params.kind}_${digest}`;
}

export function projectReliability(params: {
  participants: ReliabilityParticipantView[];
  roomMode: ClassroomRoomMode;
  callMode: CallMode;
  activeTaskId: string | null;
  referenceMs: number;
}): ReliabilityProjection {
  const activeParticipants = params.participants.filter((participant) =>
    participantIsLive(participant, params.referenceMs)
  );
  const activeTutorCount = activeParticipants
    .filter((participant) => participant.role === "primaryTutor" || participant.role === "coTutor")
    .length;
  const weakConnectionCount = activeParticipants.filter(participantIsWeak).length;
  const tutorPresenceState = deriveTutorPresenceState({
    activeTutorCount,
    roomMode: params.roomMode,
    activeTaskId: params.activeTaskId,
  });

  return {
    activeParticipantCount: activeParticipants.length,
    activeTutorCount,
    weakConnectionCount,
    tutorPresenceState,
    studentsMayContinue: tutorPresenceState === "practiceAutonomous",
    recommendedMediaProfile: deriveRecommendedMediaProfile({
      callMode: params.callMode,
      activeParticipantCount: activeParticipants.length,
      weakConnectionCount,
      tutorPresenceState,
    }),
  };
}

async function recordReliabilityEvent(params: {
  sessionId: string;
  kind: string;
  signature: string;
  payload: Record<string, unknown>;
}) {
  const eventId = buildReliabilityEventId({
    sessionId: params.sessionId,
    kind: params.kind,
    signature: params.signature,
  });
  await reliabilityEventsCollection(params.sessionId).doc(eventId).set({
    kind: params.kind,
    signature: params.signature,
    payload: params.payload,
    createdAt: nowServerTs(),
  }, {merge: true});
}

export async function reconcileClassroomReliability(sessionId: string): Promise<ReliabilityProjection | null> {
  const [stateSnap, participantsSnap] = await Promise.all([
    sessionStateRef(sessionId).get(),
    participantsCollection(sessionId).get(),
  ]);
  if (!stateSnap.exists) return null;

  const stateData = stateSnap.data() ?? {};
  const reliabilityData = sanitizeObject(stateData.reliability);
  const roomMode = normalizeRoomMode(stateData.roomMode ?? stateData.mode);
  const callMode = normalizeCallMode(stateData.callMode);
  const activeTaskId = toTrimmedString(stateData.activeTaskId) || null;
  const participants = participantsSnap.docs.map(participantFromDoc);
  const projection = projectReliability({
    participants,
    roomMode,
    callMode,
    activeTaskId,
    referenceMs: nowMs(),
  });

  const previousTutorPresence = normalizeTutorPresenceState(reliabilityData.tutorPresenceState);
  const previousMediaProfile = normalizeMediaProfile(reliabilityData.recommendedMediaProfile);
  const previousRecoveryVersion = Math.max(1, Math.round(asNumber(reliabilityData.recoveryVersion, 1)));
  const previousCallModeVersion = Math.max(1, Math.round(asNumber(reliabilityData.lastCallModeVersion, asNumber(stateData.callModeVersion, 1))));
  const currentCallModeVersion = Math.max(1, Math.round(asNumber(stateData.callModeVersion, 1)));

  const hasMeaningfulTransition =
    previousTutorPresence !== projection.tutorPresenceState ||
    previousMediaProfile !== projection.recommendedMediaProfile ||
    asNumber(reliabilityData.activeTutorCount, -1) !== projection.activeTutorCount ||
    asNumber(reliabilityData.activeParticipantCount, -1) !== projection.activeParticipantCount ||
    asNumber(reliabilityData.weakConnectionCount, -1) !== projection.weakConnectionCount ||
    previousCallModeVersion !== currentCallModeVersion;

  const nextRecoveryVersion = hasMeaningfulTransition ? previousRecoveryVersion + 1 : previousRecoveryVersion;

  await sessionStateRef(sessionId).set({
    reliability: {
      activeParticipantCount: projection.activeParticipantCount,
      activeTutorCount: projection.activeTutorCount,
      weakConnectionCount: projection.weakConnectionCount,
      tutorPresenceState: projection.tutorPresenceState,
      studentsMayContinue: projection.studentsMayContinue,
      recommendedMediaProfile: projection.recommendedMediaProfile,
      lastCallMode: callMode,
      lastCallModeVersion: currentCallModeVersion,
      lastCallMigrationAt:
        previousCallModeVersion !== currentCallModeVersion ? nowServerTs() : reliabilityData.lastCallMigrationAt ?? null,
      tutorUnavailableAt:
        projection.tutorPresenceState !== "active" && previousTutorPresence === "active" ?
          nowServerTs() :
          reliabilityData.tutorUnavailableAt ?? null,
      lastReconciledAt: nowServerTs(),
      recoveryVersion: nextRecoveryVersion,
    },
  }, {merge: true});

  await reliabilityMetricsRef(sessionId).set({
    activeParticipantCount: projection.activeParticipantCount,
    activeTutorCount: projection.activeTutorCount,
    weakConnectionCount: projection.weakConnectionCount,
    tutorPresenceState: projection.tutorPresenceState,
    studentsMayContinue: projection.studentsMayContinue,
    recommendedMediaProfile: projection.recommendedMediaProfile,
    callMode,
    callModeVersion: currentCallModeVersion,
    recoveryVersion: nextRecoveryVersion,
    updatedAt: nowServerTs(),
  }, {merge: true});

  if (previousTutorPresence !== projection.tutorPresenceState) {
    await recordReliabilityEvent({
      sessionId,
      kind: "tutor_presence",
      signature: `${previousTutorPresence}->${projection.tutorPresenceState}`,
      payload: {
        previousTutorPresence,
        nextTutorPresence: projection.tutorPresenceState,
        roomMode,
        activeTaskId,
      },
    });
  }

  if (previousMediaProfile !== projection.recommendedMediaProfile) {
    await recordReliabilityEvent({
      sessionId,
      kind: "media_profile",
      signature: `${previousMediaProfile}->${projection.recommendedMediaProfile}`,
      payload: {
        previousMediaProfile,
        nextMediaProfile: projection.recommendedMediaProfile,
        weakConnectionCount: projection.weakConnectionCount,
        callMode,
      },
    });
  }

  if (previousCallModeVersion !== currentCallModeVersion) {
    await recordReliabilityEvent({
      sessionId,
      kind: "transport_migration",
      signature: `${previousCallModeVersion}->${currentCallModeVersion}`,
      payload: {
        callMode,
        previousCallModeVersion,
        currentCallModeVersion,
      },
    });
  }

  return projection;
}

async function latestBoardSnapshot(sessionId: string, boardId: string) {
  const snap = await boardSnapshotsCollection(sessionId)
    .where("boardId", "==", boardId)
    .limit(10)
    .get();
  const docs = snap.docs
    .map((doc) => ({id: doc.id, ...(doc.data() as Record<string, unknown>)}))
    .sort((a, b) => {
      const aTs = asTimestamp((a as Record<string, unknown>).createdAt)?.toMillis() ?? 0;
      const bTs = asTimestamp((b as Record<string, unknown>).createdAt)?.toMillis() ?? 0;
      return bTs - aTs;
    });
  return docs[0] ?? null;
}

async function latestAcceptedBoardOrder(sessionId: string, boardId: string) {
  const snap = await boardChunksCollection(sessionId)
    .where("boardId", "==", boardId)
    .limit(200)
    .get();
  let latest = 0;
  for (const doc of snap.docs) {
    const data = doc.data() ?? {};
    if (toTrimmedString(data.status) !== "accepted") continue;
    latest = Math.max(latest, Math.round(asNumber(data.serverOrder, 0)));
  }
  return latest;
}

async function buildPreviewFallbacks(sessionId: string, previewBoardIds: string[]) {
  const entries = await Promise.all(previewBoardIds.slice(0, 8).map(async (boardId) => {
    const [thumbnailSnap, snapshot] = await Promise.all([
      thumbnailsCollection(sessionId).doc(boardId).get(),
      latestBoardSnapshot(sessionId, boardId),
    ]);
    return {
      boardId,
      thumbnail: thumbnailSnap.exists ? {id: thumbnailSnap.id, ...thumbnailSnap.data()} : null,
      latestSnapshot: snapshot,
    };
  }));
  return entries;
}

export async function buildRecoverySnapshot(params: {
  sessionId: string;
  participantId: string;
  connectionInfo: Record<string, unknown>;
}) {
  const [sessionSnap, stateSnap, participantSnap] = await Promise.all([
    sessionRef(params.sessionId).get(),
    sessionStateRef(params.sessionId).get(),
    participantsCollection(params.sessionId).doc(params.participantId).get(),
  ]);

  if (!sessionSnap.exists || !stateSnap.exists || !participantSnap.exists) {
    throw new Error("not_found");
  }

  const participantData = participantSnap.data() ?? {};
  if (toTrimmedString(participantData.joinState) === "left") {
    throw new Error("participant_left");
  }

  const stateData = stateSnap.data() ?? {};
  const reliability = sanitizeObject(stateData.reliability);
  const activeTaskId = toTrimmedString(stateData.activeTaskId) || null;
  const role = normalizeRole(participantData.role);
  const routeSnap = await boardRoutesCollection(params.sessionId).doc(params.participantId).get();
  const route = sanitizeObject(routeSnap.data());
  const visibleBoardIds = asStringArray(route.visibleBoardIds);
  const currentBoardId = toTrimmedString(route.currentBoardId) || toTrimmedString(stateData.activeBoardRef) || "shared";

  const [activeTaskSnap, submissionSnap, currentBoardOrder, currentBoardSnapshot, visibleBoards, previewFallbacks] = await Promise.all([
    activeTaskId ? tasksCollection(params.sessionId).doc(activeTaskId).get() : Promise.resolve(null),
    activeTaskId ? submissionsCollection(params.sessionId).doc(`${activeTaskId}_${params.participantId}`).get() : Promise.resolve(null),
    latestAcceptedBoardOrder(params.sessionId, currentBoardId),
    latestBoardSnapshot(params.sessionId, currentBoardId),
    Promise.all(visibleBoardIds.slice(0, 10).map(async (boardId) => {
      const snap = await boardsCollection(params.sessionId).doc(boardId).get();
      return snap.exists ? {boardId: snap.id, ...snap.data()} : null;
    })),
    role === "primaryTutor" || role === "coTutor" ? buildPreviewFallbacks(params.sessionId, asStringArray(route.previewBoardIds)) : Promise.resolve([]),
  ]);

  const timerEndAt = asTimestamp(stateData.timerEndAt);
  const currentNowMs = nowMs();

  return {
    sessionId: params.sessionId,
    serverNowMs: currentNowMs,
    connectionInfo: params.connectionInfo,
    classroomState: {
      roomMode: toTrimmedString(stateData.roomMode ?? stateData.mode) || "teach",
      focusMode: toTrimmedString(stateData.focusMode) || "wholeClass",
      boardMode: toTrimmedString(stateData.boardMode) || "sharedBoard",
      attentionTarget: toTrimmedString(stateData.attentionTarget) || null,
      classLock: stateData.classLock === true,
      activeTaskId,
      timerEndAtMs: timerEndAt?.toMillis() ?? null,
      timerRemainingMs: calculateTimerRemainingMs(timerEndAt?.toMillis() ?? null, currentNowMs),
      spotlight: sanitizeObject(stateData.spotlight),
      submissionSummary: sanitizeObject(stateData.submissionSummary),
      reliability: {
        activeParticipantCount: asNumber(reliability.activeParticipantCount, 0),
        activeTutorCount: asNumber(reliability.activeTutorCount, 0),
        weakConnectionCount: asNumber(reliability.weakConnectionCount, 0),
        tutorPresenceState: normalizeTutorPresenceState(reliability.tutorPresenceState),
        studentsMayContinue: reliability.studentsMayContinue === true,
        recommendedMediaProfile: normalizeMediaProfile(reliability.recommendedMediaProfile),
        recoveryVersion: asNumber(reliability.recoveryVersion, 1),
        lastCallModeVersion: asNumber(reliability.lastCallModeVersion, asNumber(stateData.callModeVersion, 1)),
      },
    },
    participantState: {
      role,
      joinState: toTrimmedString(participantData.joinState) || "joined",
      presenceState: toTrimmedString(participantData.presenceState) || "online",
      classroomFocusState: toTrimmedString(participantData.classroomFocusState) || "inClass",
      visibilityState: toTrimmedString(participantData.visibilityState) || "classVisible",
      interventionState: toTrimmedString(participantData.interventionState) || "none",
      pinned: participantData.pinned === true,
      lastSeenAtMs: asTimestamp(participantData.lastSeenAt)?.toMillis() ?? null,
    },
    activeTask: activeTaskSnap && activeTaskSnap.exists ? {taskId: activeTaskSnap.id, ...activeTaskSnap.data()} : null,
    submissionState: submissionSnap && submissionSnap.exists ? {submissionId: submissionSnap.id, ...submissionSnap.data()} : null,
    boardRecovery: {
      route,
      currentBoardId,
      currentBoardLatestAcceptedServerOrder: currentBoardOrder,
      currentBoardSnapshot,
      visibleBoards: visibleBoards.filter(Boolean),
      previewFallbacks,
    },
  };
}

export const onclassroomreliabilityparticipantwritten = onDocumentWritten({
  document: "sessions/{sessionId}/participants/{participantId}",
  region: REGION,
}, async (event) => {
  const sessionId = toTrimmedString(event.params?.sessionId);
  if (!sessionId) return;
  const before = (event.data?.before.data() ?? {}) as Record<string, unknown>;
  const after = (event.data?.after.data() ?? {}) as Record<string, unknown>;
  const beforeSignature = JSON.stringify({
    role: toTrimmedString(before.role),
    joinState: toTrimmedString(before.joinState),
    presenceState: toTrimmedString(before.presenceState),
    networkQuality: toTrimmedString(before.networkQuality),
    mediaHealth: toTrimmedString(before.mediaHealth),
    lastSeenAt: asTimestamp(before.lastSeenAt)?.toMillis() ?? null,
    lastHeartbeatAt: asTimestamp(before.lastHeartbeatAt)?.toMillis() ?? null,
  });
  const afterSignature = JSON.stringify({
    role: toTrimmedString(after.role),
    joinState: toTrimmedString(after.joinState),
    presenceState: toTrimmedString(after.presenceState),
    networkQuality: toTrimmedString(after.networkQuality),
    mediaHealth: toTrimmedString(after.mediaHealth),
    lastSeenAt: asTimestamp(after.lastSeenAt)?.toMillis() ?? null,
    lastHeartbeatAt: asTimestamp(after.lastHeartbeatAt)?.toMillis() ?? null,
  });
  if (beforeSignature === afterSignature) return;
  try {
    await reconcileClassroomReliability(sessionId);
  } catch (error) {
    logger.error("Failed to reconcile classroom reliability from participant write", {sessionId, error});
  }
});

export const onclassroomreliabilitystatewritten = onDocumentWritten({
  document: "sessions/{sessionId}/sessionState/sessionState",
  region: REGION,
}, async (event) => {
  const sessionId = toTrimmedString(event.params?.sessionId);
  if (!sessionId) return;
  const before = (event.data?.before.data() ?? {}) as Record<string, unknown>;
  const after = (event.data?.after.data() ?? {}) as Record<string, unknown>;
  const beforeSignature = JSON.stringify({
    roomMode: toTrimmedString(before.roomMode ?? before.mode),
    callMode: toTrimmedString(before.callMode),
    callModeVersion: asNumber(before.callModeVersion, 1),
    activeTaskId: toTrimmedString(before.activeTaskId),
  });
  const afterSignature = JSON.stringify({
    roomMode: toTrimmedString(after.roomMode ?? after.mode),
    callMode: toTrimmedString(after.callMode),
    callModeVersion: asNumber(after.callModeVersion, 1),
    activeTaskId: toTrimmedString(after.activeTaskId),
  });
  if (beforeSignature === afterSignature) return;
  try {
    await reconcileClassroomReliability(sessionId);
  } catch (error) {
    logger.error("Failed to reconcile classroom reliability from state write", {sessionId, error});
  }
});
