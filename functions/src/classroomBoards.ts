import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {
  onDocumentCreated,
  onDocumentWritten,
} from "firebase-functions/v2/firestore";

const db = admin.firestore();
const REGION = process.env.PARALLEL_PRACTICE_REGION || "europe-west2";
const SESSION_STATE_DOC_ID = "sessionState";

export type ClassroomBoardKind =
  | "sharedBoard"
  | "studentPrivateBoard"
  | "reviewBoard"
  | "exemplarBoard";

export type BoardOwnershipState =
  | "tutorOwned"
  | "studentOwned"
  | "coEditable"
  | "lockedForSubmission"
  | "reviewOnly"
  | "broadcastBase";

export type BoardTransientState = "none" | "spotlight";
export type BoardVisibilityScope = "class" | "ownerAndTutors" | "tutorOnly";
type SessionRole = "primaryTutor" | "coTutor" | "student";
type RoomMode = "teach" | "practice" | "review";
type FocusMode = "wholeClass" | "spotlightStudent" | "tutorPrivateReview";
type BoardMode = "sharedBoard" | "studentPrivateBoards" | "reviewBoard";
type SpotlightMode = "none" | "soft" | "hard";

export interface BoardParticipant {
  id: string;
  role: SessionRole;
  joinState: string;
  interventionState: string;
}

export interface BoardRoutingState {
  roomMode: RoomMode;
  focusMode: FocusMode;
  boardMode: BoardMode;
  attentionTarget: string | null;
  classLock: boolean;
  activeBoardRef: string | null;
  activeTaskId: string | null;
  orchestratorVersion: number;
  spotlightMode: SpotlightMode;
  pauseOthers: boolean;
  deEmphasizeOthers: boolean;
  observeOnly: boolean;
}

export interface ClassroomBoardDoc {
  boardId: string;
  boardKind: ClassroomBoardKind;
  ownerId: string | null;
  subjectStudentId: string | null;
  ownershipState: BoardOwnershipState;
  visibilityScope: BoardVisibilityScope;
  transientState: BoardTransientState;
  sourceBoardId: string | null;
  sourceSnapshotId: string | null;
  previewEnabled: boolean;
  revisionCursor: number;
  lastSeqByWriter: Record<string, number>;
  active: boolean;
}

export interface ClassroomBoardRouteDoc {
  participantId: string;
  role: SessionRole;
  currentBoardId: string;
  currentBoardKind: ClassroomBoardKind;
  visibleBoardIds: string[];
  previewBoardIds: string[];
  writeBoardIds: string[];
  spotlightBoardId: string | null;
  reviewBoardId: string | null;
  baseSnapshotId: string | null;
  boardMode: BoardMode;
  focusMode: FocusMode;
  spotlightMode: SpotlightMode;
  pauseOthers: boolean;
  isDeemphasized: boolean;
  isPausedByTutor: boolean;
  routeVersion: number;
}

export interface ChunkAcceptanceResult {
  status: "accepted" | "ignored" | "rejected";
  reason: string | null;
}

interface ExistingBoardDoc {
  id: string;
  data: Record<string, unknown>;
}

function nowServerTs() {
  return admin.firestore.FieldValue.serverTimestamp();
}

function sessionRef(sessionId: string) {
  return db.collection("sessions").doc(sessionId);
}

function sessionStateRef(sessionId: string) {
  return sessionRef(sessionId)
    .collection("sessionState")
    .doc(SESSION_STATE_DOC_ID);
}

function participantCollection(sessionId: string) {
  return sessionRef(sessionId).collection("participants");
}

function boardsCollection(sessionId: string) {
  return sessionRef(sessionId).collection("boards");
}

function boardRoutesCollection(sessionId: string) {
  return sessionRef(sessionId).collection("boardRoutes");
}

function boardSnapshotsCollection(sessionId: string) {
  return sessionRef(sessionId).collection("boardSnapshots");
}

function boardCommandsCollection(sessionId: string) {
  return sessionRef(sessionId).collection("boardCommands");
}

function thumbnailsCollection(sessionId: string) {
  return sessionRef(sessionId).collection("thumbnails");
}

function thumbnailJobsCollection(sessionId: string) {
  return sessionRef(sessionId).collection("thumbnailJobs");
}

function relevantBoardStateSignature(data: Record<string, unknown>): string {
  return JSON.stringify({
    roomMode: toTrimmedString(data.roomMode ?? data.mode),
    focusMode: toTrimmedString(data.focusMode),
    boardMode: toTrimmedString(data.boardMode),
    attentionTarget: toTrimmedString(data.attentionTarget),
    classLock: asBool(data.classLock, true),
    activeBoardRef: toTrimmedString(data.activeBoardRef),
    activeTaskId: toTrimmedString(data.activeTaskId),
    spotlight: data.spotlight ?? null,
  });
}

function relevantBoardParticipantSignature(data: Record<string, unknown>): string {
  return JSON.stringify({
    role: toTrimmedString(data.role),
    joinState: toTrimmedString(data.joinState),
    classroomFocusState: toTrimmedString(data.classroomFocusState),
    visibilityState: toTrimmedString(data.visibilityState),
    interventionState: toTrimmedString(data.interventionState),
    currentTaskId: toTrimmedString(data.currentTaskId),
    pinned: asBool(data.pinned, false),
    deemphasized: asBool(data.deemphasized, false),
    workPaused: asBool(data.workPaused, false),
  });
}

function toTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asBool(value: unknown, fallback = false): boolean {
  return typeof value === "boolean" ? value : fallback;
}

function asNumber(value: unknown, fallback = 0): number {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return fallback;
}

function normalizeRole(value: unknown): SessionRole {
  const raw = toTrimmedString(value);
  if (raw === "primaryTutor" || raw === "coTutor") return raw;
  return "student";
}

function isTutorRole(role: SessionRole): boolean {
  return role === "primaryTutor" || role === "coTutor";
}

function normalizeRoomMode(value: unknown): RoomMode {
  const raw = toTrimmedString(value);
  return raw === "practice" || raw === "review" ? raw : "teach";
}

function normalizeFocusMode(value: unknown): FocusMode {
  const raw = toTrimmedString(value);
  if (raw === "spotlightStudent") return raw;
  if (raw === "tutorPrivateReview") return raw;
  return "wholeClass";
}

function normalizeBoardMode(value: unknown): BoardMode {
  const raw = toTrimmedString(value);
  if (raw === "studentPrivateBoards" || raw === "reviewBoard") {
    return raw;
  }
  return "sharedBoard";
}

function normalizeSpotlightMode(value: unknown): SpotlightMode {
  const raw = toTrimmedString(value);
  if (raw === "soft" || raw === "hard") return raw;
  return "none";
}

function normalizeInterventionState(value: unknown): string {
  const raw = toTrimmedString(value);
  if ([
    "nudged",
    "tutorObserving",
    "tutorIntervening",
    "correctionSent",
  ].includes(raw)) {
    return raw;
  }
  return "none";
}

function activeParticipants(participants: BoardParticipant[]): BoardParticipant[] {
  return participants.filter((participant) => participant.joinState !== "left");
}

function activeStudents(participants: BoardParticipant[]): BoardParticipant[] {
  return activeParticipants(participants).filter((participant) => participant.role === "student");
}

function sharedBoardId(): string {
  return "shared";
}

function reviewBoardId(): string {
  return "review";
}

export function privateBoardIdForStudent(studentId: string): string {
  return `student_${studentId}`;
}

export function exemplarBoardIdForSnapshot(snapshotId: string): string {
  return `exemplar_${snapshotId}`;
}

export function buildBoardChunkId(params: {
  boardId: string;
  writerId: string;
  deviceId: string;
  seqStart: number;
  seqEnd: number;
}): string {
  return [
    params.boardId,
    params.writerId,
    params.deviceId,
    params.seqStart.toString(),
    params.seqEnd.toString(),
  ].join("_");
}

function normalizeRoutingState(data: Record<string, unknown>): BoardRoutingState {
  const spotlight = (
    data.spotlight &&
    typeof data.spotlight === "object" &&
    !Array.isArray(data.spotlight)
  ) ?
    data.spotlight as Record<string, unknown> :
    {};
  return {
    roomMode: normalizeRoomMode(data.roomMode ?? data.mode),
    focusMode: normalizeFocusMode(data.focusMode),
    boardMode: normalizeBoardMode(data.boardMode),
    attentionTarget: toTrimmedString(data.attentionTarget) || null,
    classLock: asBool(data.classLock, true),
    activeBoardRef: toTrimmedString(data.activeBoardRef) || null,
    activeTaskId: toTrimmedString(data.activeTaskId) || null,
    orchestratorVersion: Math.max(1, Math.round(asNumber(data.orchestratorVersion, 1))),
    spotlightMode: normalizeSpotlightMode(spotlight.mode),
    pauseOthers: asBool(spotlight.pauseOthers, false),
    deEmphasizeOthers: asBool(spotlight.deEmphasizeOthers, false),
    observeOnly: asBool(spotlight.observeOnly, false),
  };
}

function boardFromExisting(
  boardId: string,
  existing: Map<string, ExistingBoardDoc>,
  fallback: Partial<ClassroomBoardDoc>
): ClassroomBoardDoc {
  const current = existing.get(boardId)?.data ?? {};
  return {
    boardId,
    boardKind: (fallback.boardKind ?? "sharedBoard") as ClassroomBoardKind,
    ownerId: ((fallback.ownerId ?? toTrimmedString(current.ownerId)) || null) as string | null,
    subjectStudentId: ((fallback.subjectStudentId ?? toTrimmedString(current.subjectStudentId)) || null) as string | null,
    ownershipState: ((fallback.ownershipState ?? toTrimmedString(current.ownershipState)) || "tutorOwned") as BoardOwnershipState,
    visibilityScope: ((fallback.visibilityScope ?? toTrimmedString(current.visibilityScope)) || "class") as BoardVisibilityScope,
    transientState: ((fallback.transientState ?? toTrimmedString(current.transientState)) || "none") as BoardTransientState,
    sourceBoardId: ((fallback.sourceBoardId ?? toTrimmedString(current.sourceBoardId)) || null) as string | null,
    sourceSnapshotId: ((fallback.sourceSnapshotId ?? toTrimmedString(current.sourceSnapshotId)) || null) as string | null,
    previewEnabled: fallback.previewEnabled ?? asBool(current.previewEnabled, false),
    revisionCursor: Math.max(0, Math.round(asNumber(current.revisionCursor, 0))),
    lastSeqByWriter: (current.lastSeqByWriter && typeof current.lastSeqByWriter === "object" ? current.lastSeqByWriter : {}) as Record<string, number>,
    active: fallback.active ?? asBool(current.active, true),
  };
}

function studentOwnershipState(
  participant: BoardParticipant,
  state: BoardRoutingState
): BoardOwnershipState {
  if (state.roomMode === "review") return "lockedForSubmission";
  if (state.focusMode === "spotlightStudent" && state.attentionTarget === participant.id) {
    if (participant.interventionState === "tutorIntervening") return "coEditable";
    return "studentOwned";
  }
  return "studentOwned";
}

function visiblePrivateBoardsForTutor(participants: BoardParticipant[]): string[] {
  return activeStudents(participants).map((student) => privateBoardIdForStudent(student.id));
}

export function deriveBoardTopology(params: {
  state: BoardRoutingState;
  participants: BoardParticipant[];
  existingBoards?: Map<string, ExistingBoardDoc>;
}): {
  boards: Map<string, ClassroomBoardDoc>;
  routes: Map<string, ClassroomBoardRouteDoc>;
} {
  const existingBoards = params.existingBoards ?? new Map<string, ExistingBoardDoc>();
  const boards = new Map<string, ClassroomBoardDoc>();
  const routes = new Map<string, ClassroomBoardRouteDoc>();
  const participants = activeParticipants(params.participants);
  const studentPreviewIds = visiblePrivateBoardsForTutor(participants);
  const spotlightIsActive =
    params.state.focusMode === "spotlightStudent" &&
    params.state.attentionTarget != null &&
    params.state.spotlightMode !== "none";
  const spotlightStudentId = spotlightIsActive ? params.state.attentionTarget : null;
  const hardSpotlight = spotlightIsActive && params.state.spotlightMode === "hard";
  const exemplarId = params.state.activeBoardRef ?
    exemplarBoardIdForSnapshot(params.state.activeBoardRef) :
    null;

  boards.set(sharedBoardId(), boardFromExisting(sharedBoardId(), existingBoards, {
    boardKind: "sharedBoard",
    ownerId: null,
    subjectStudentId: null,
    ownershipState: params.state.classLock ? "tutorOwned" : "coEditable",
    visibilityScope: "class",
    transientState: "none",
    sourceBoardId: null,
    sourceSnapshotId: null,
    previewEnabled: false,
    active: true,
  }));

  boards.set(reviewBoardId(), boardFromExisting(reviewBoardId(), existingBoards, {
    boardKind: "reviewBoard",
    ownerId: null,
    subjectStudentId: params.state.attentionTarget,
    ownershipState: "tutorOwned",
    visibilityScope: "class",
    transientState: "none",
    sourceBoardId: exemplarId,
    sourceSnapshotId: params.state.activeBoardRef,
    previewEnabled: false,
    active: params.state.roomMode === "review",
  }));

  if (exemplarId && params.state.activeBoardRef) {
    boards.set(exemplarId, boardFromExisting(exemplarId, existingBoards, {
      boardKind: "exemplarBoard",
      ownerId: null,
      subjectStudentId: params.state.attentionTarget,
      ownershipState: "broadcastBase",
      visibilityScope: "class",
      transientState: params.state.focusMode === "spotlightStudent" ? "spotlight" : "none",
      sourceBoardId: params.state.attentionTarget ? privateBoardIdForStudent(params.state.attentionTarget) : null,
      sourceSnapshotId: params.state.activeBoardRef,
      previewEnabled: false,
      active: true,
    }));
  }

  for (const student of activeStudents(participants)) {
    boards.set(privateBoardIdForStudent(student.id), boardFromExisting(
      privateBoardIdForStudent(student.id),
      existingBoards,
      {
        boardKind: "studentPrivateBoard",
        ownerId: student.id,
        subjectStudentId: student.id,
        ownershipState: studentOwnershipState(student, params.state),
        visibilityScope: "ownerAndTutors",
        transientState: spotlightStudentId === student.id ? "spotlight" : "none",
        sourceBoardId: null,
        sourceSnapshotId: null,
        previewEnabled: true,
        active: true,
      }
    ));
  }

  for (const participant of participants) {
    if (participant.role === "student") {
      if (params.state.roomMode === "teach") {
        routes.set(participant.id, {
          participantId: participant.id,
          role: participant.role,
          currentBoardId: sharedBoardId(),
          currentBoardKind: "sharedBoard",
          visibleBoardIds: [sharedBoardId()],
          previewBoardIds: [],
          writeBoardIds: params.state.classLock ? [] : [sharedBoardId()],
          spotlightBoardId: null,
          reviewBoardId: null,
          baseSnapshotId: null,
          boardMode: "sharedBoard",
          focusMode: params.state.focusMode,
          spotlightMode: params.state.spotlightMode,
          pauseOthers: false,
          isDeemphasized: false,
          isPausedByTutor: false,
          routeVersion: params.state.orchestratorVersion,
        });
        continue;
      }

      if (params.state.roomMode === "practice") {
        const studentBoardId = privateBoardIdForStudent(participant.id);
        const pausedByTutor =
          params.state.pauseOthers &&
          spotlightStudentId != null &&
          participant.id !== spotlightStudentId;
        routes.set(participant.id, {
          participantId: participant.id,
          role: participant.role,
          currentBoardId: studentBoardId,
          currentBoardKind: "studentPrivateBoard",
          visibleBoardIds: [studentBoardId],
          previewBoardIds: [],
          writeBoardIds: pausedByTutor ? [] : [studentBoardId],
          spotlightBoardId:
            hardSpotlight && spotlightStudentId === participant.id ? studentBoardId : null,
          reviewBoardId: null,
          baseSnapshotId: null,
          boardMode: "studentPrivateBoards",
          focusMode: params.state.focusMode,
          spotlightMode: params.state.spotlightMode,
          pauseOthers: params.state.pauseOthers,
          isDeemphasized:
            params.state.deEmphasizeOthers &&
            spotlightStudentId != null &&
            participant.id != spotlightStudentId,
          isPausedByTutor: pausedByTutor,
          routeVersion: params.state.orchestratorVersion,
        });
        continue;
      }

      const visibleBoardIds = [
        reviewBoardId(),
        ...(exemplarId != null ? [exemplarId] : []),
      ];
      routes.set(participant.id, {
        participantId: participant.id,
        role: participant.role,
        currentBoardId: reviewBoardId(),
        currentBoardKind: "reviewBoard",
        visibleBoardIds,
        previewBoardIds: [],
        writeBoardIds: [],
        spotlightBoardId: spotlightStudentId == participant.id ? reviewBoardId() : null,
        reviewBoardId: reviewBoardId(),
        baseSnapshotId: params.state.activeBoardRef,
        boardMode: "reviewBoard",
        focusMode: params.state.focusMode,
        spotlightMode: params.state.spotlightMode,
        pauseOthers: false,
        isDeemphasized: false,
        isPausedByTutor: false,
        routeVersion: params.state.orchestratorVersion,
      });
      continue;
    }

    if (params.state.roomMode === "teach") {
      routes.set(participant.id, {
        participantId: participant.id,
        role: participant.role,
        currentBoardId: sharedBoardId(),
        currentBoardKind: "sharedBoard",
        visibleBoardIds: [sharedBoardId()],
        previewBoardIds: [],
        writeBoardIds: [sharedBoardId()],
        spotlightBoardId: null,
        reviewBoardId: null,
        baseSnapshotId: null,
        boardMode: "sharedBoard",
        focusMode: params.state.focusMode,
        spotlightMode: params.state.spotlightMode,
        pauseOthers: false,
        isDeemphasized: false,
        isPausedByTutor: false,
        routeVersion: params.state.orchestratorVersion,
      });
      continue;
    }

    if (params.state.roomMode === "practice") {
      const currentBoardId = spotlightStudentId != null ?
        privateBoardIdForStudent(spotlightStudentId) :
        sharedBoardId();
      const canWriteSpotlight = spotlightStudentId != null &&
        participants.some((item) =>
          item.id == spotlightStudentId && item.interventionState == "tutorIntervening");
      const writeBoardIds = [
        sharedBoardId(),
        ...(spotlightStudentId != null && canWriteSpotlight ?
          [privateBoardIdForStudent(spotlightStudentId)] :
          []),
      ];
      routes.set(participant.id, {
        participantId: participant.id,
        role: participant.role,
        currentBoardId,
        currentBoardKind: spotlightStudentId != null ? "studentPrivateBoard" : "sharedBoard",
        visibleBoardIds: [sharedBoardId(), ...studentPreviewIds],
        previewBoardIds: studentPreviewIds,
        writeBoardIds,
        spotlightBoardId: spotlightStudentId != null ? privateBoardIdForStudent(spotlightStudentId) : null,
        reviewBoardId: null,
        baseSnapshotId: null,
        boardMode: "studentPrivateBoards",
        focusMode: params.state.focusMode,
        spotlightMode: params.state.spotlightMode,
        pauseOthers: params.state.pauseOthers,
        isDeemphasized: false,
        isPausedByTutor: false,
        routeVersion: params.state.orchestratorVersion,
      });
      continue;
    }

    routes.set(participant.id, {
      participantId: participant.id,
      role: participant.role,
      currentBoardId: reviewBoardId(),
      currentBoardKind: "reviewBoard",
      visibleBoardIds: [
        sharedBoardId(),
        reviewBoardId(),
        ...studentPreviewIds,
        ...(exemplarId != null ? [exemplarId] : []),
      ],
      previewBoardIds: studentPreviewIds,
      writeBoardIds: [reviewBoardId()],
      spotlightBoardId: spotlightStudentId != null ? reviewBoardId() : null,
      reviewBoardId: reviewBoardId(),
      baseSnapshotId: params.state.activeBoardRef,
      boardMode: "reviewBoard",
      focusMode: params.state.focusMode,
      spotlightMode: params.state.spotlightMode,
      pauseOthers: params.state.pauseOthers,
      isDeemphasized: false,
      isPausedByTutor: false,
      routeVersion: params.state.orchestratorVersion,
    });
  }

  return {
    boards,
    routes,
  };
}

export function canWriteBoard(params: {
  board: ClassroomBoardDoc;
  writerId: string;
  writerRole: SessionRole;
}): boolean {
  if (params.board.ownershipState === "reviewOnly" ||
      params.board.ownershipState === "broadcastBase" ||
      params.board.ownershipState === "lockedForSubmission") {
    return false;
  }
  if (params.board.ownershipState === "tutorOwned") {
    return isTutorRole(params.writerRole);
  }
  if (params.board.ownershipState === "studentOwned") {
    return params.writerId === params.board.ownerId;
  }
  return isTutorRole(params.writerRole) || params.writerId === params.board.ownerId;
}

export function evaluateChunkAcceptance(params: {
  board: ClassroomBoardDoc;
  writerId: string;
  writerRole: SessionRole;
  seqEnd: number;
}): ChunkAcceptanceResult {
  if (!canWriteBoard({
    board: params.board,
    writerId: params.writerId,
    writerRole: params.writerRole,
  })) {
    return {status: "rejected", reason: "writer_not_allowed"};
  }
  const lastSeq = Math.round(asNumber(params.board.lastSeqByWriter[params.writerId], -1));
  if (params.seqEnd <= lastSeq) {
    return {status: "ignored", reason: "stale_sequence"};
  }
  return {status: "accepted", reason: null};
}

export async function syncBoardTopology(sessionId: string): Promise<void> {
  await db.runTransaction(async (tx) => {
    const [sessionSnap, stateSnap, participantsSnap, boardsSnap, routesSnap] = await Promise.all([
      tx.get(sessionRef(sessionId)),
      tx.get(sessionStateRef(sessionId)),
      tx.get(participantCollection(sessionId)),
      tx.get(boardsCollection(sessionId)),
      tx.get(boardRoutesCollection(sessionId)),
    ]);

    if (!sessionSnap.exists) return;
    const state = normalizeRoutingState(stateSnap.data() ?? {});
    const participants = participantsSnap.docs.map((doc) => {
      const data = doc.data() ?? {};
      return {
        id: doc.id,
        role: normalizeRole(data.role),
        joinState: toTrimmedString(data.joinState) || "joined",
        interventionState: normalizeInterventionState(data.interventionState),
      } satisfies BoardParticipant;
    });
    const existingBoards = new Map<string, ExistingBoardDoc>(
      boardsSnap.docs.map((doc) => [doc.id, {id: doc.id, data: doc.data() ?? {}}])
    );

    const plan = deriveBoardTopology({
      state,
      participants,
      existingBoards,
    });
    const activeBoardIds = new Set(plan.boards.keys());
    const activeRouteIds = new Set(plan.routes.keys());

    for (const [boardId, board] of plan.boards.entries()) {
      tx.set(boardsCollection(sessionId).doc(boardId), {
        ...board,
        updatedAt: nowServerTs(),
        createdAt: existingBoards.has(boardId) ?
          existingBoards.get(boardId)?.data.createdAt ?? nowServerTs() :
          nowServerTs(),
      }, {merge: true});
    }

    for (const boardDoc of boardsSnap.docs) {
      if (!activeBoardIds.has(boardDoc.id)) {
        tx.set(boardDoc.ref, {active: false, updatedAt: nowServerTs()}, {merge: true});
      }
    }

    for (const [participantId, route] of plan.routes.entries()) {
      tx.set(boardRoutesCollection(sessionId).doc(participantId), {
        ...route,
        updatedAt: nowServerTs(),
        active: true,
      }, {merge: true});
    }

    for (const routeDoc of routesSnap.docs) {
      if (!activeRouteIds.has(routeDoc.id)) {
        tx.set(routeDoc.ref, {active: false, updatedAt: nowServerTs()}, {merge: true});
      }
    }
  });
}

async function requireParticipantRole(
  tx: admin.firestore.Transaction,
  sessionId: string,
  userId: string
): Promise<SessionRole> {
  const participantSnap = await tx.get(participantCollection(sessionId).doc(userId));
  if (!participantSnap.exists) throw new Error("forbidden");
  return normalizeRole(participantSnap.data()?.role);
}

function normalizeBoardDoc(boardId: string, data: Record<string, unknown>): ClassroomBoardDoc {
  return {
    boardId,
    boardKind: (toTrimmedString(data.boardKind) || "sharedBoard") as ClassroomBoardKind,
    ownerId: toTrimmedString(data.ownerId) || null,
    subjectStudentId: toTrimmedString(data.subjectStudentId) || null,
    ownershipState: (toTrimmedString(data.ownershipState) || "tutorOwned") as BoardOwnershipState,
    visibilityScope: (toTrimmedString(data.visibilityScope) || "class") as BoardVisibilityScope,
    transientState: (toTrimmedString(data.transientState) || "none") as BoardTransientState,
    sourceBoardId: toTrimmedString(data.sourceBoardId) || null,
    sourceSnapshotId: toTrimmedString(data.sourceSnapshotId) || null,
    previewEnabled: asBool(data.previewEnabled),
    revisionCursor: Math.max(0, Math.round(asNumber(data.revisionCursor, 0))),
    lastSeqByWriter: (data.lastSeqByWriter && typeof data.lastSeqByWriter === "object" ? data.lastSeqByWriter : {}) as Record<string, number>,
    active: asBool(data.active, true),
  };
}

async function beginBoardCommand(
  tx: admin.firestore.Transaction,
  sessionId: string,
  commandId: string,
  actorId: string,
  operation: string,
  payload: Record<string, unknown>
): Promise<Record<string, unknown> | null> {
  const commandRef = boardCommandsCollection(sessionId).doc(commandId);
  const existing = await tx.get(commandRef);
  if (existing.exists) {
    const data = existing.data() ?? {};
    if (toTrimmedString(data.status) == "COMPLETED") {
      return (data.result ?? {}) as Record<string, unknown>;
    }
  }

  tx.set(commandRef, {
    commandId,
    actorId,
    operation,
    payload,
    status: "PROCESSING",
    createdAt: nowServerTs(),
    updatedAt: nowServerTs(),
  }, {merge: true});
  return null;
}

async function completeBoardCommand(
  tx: admin.firestore.Transaction,
  sessionId: string,
  commandId: string,
  result: Record<string, unknown>
): Promise<void> {
  tx.set(boardCommandsCollection(sessionId).doc(commandId), {
    status: "COMPLETED",
    result,
    updatedAt: nowServerTs(),
    completedAt: nowServerTs(),
  }, {merge: true});
}

export async function freezeBoardSnapshot(params: {
  sessionId: string;
  actorId: string;
  boardId: string;
  snapshotKind?: "review" | "submission" | "exemplar";
  storagePath?: string;
  url?: string;
  studentId?: string;
  lockBoard?: boolean;
  commandId?: string;
}): Promise<Record<string, unknown>> {
  const commandId = params.commandId || db.collection("_").doc().id;
  let response: Record<string, unknown> = {};

  await db.runTransaction(async (tx) => {
    const existing = await beginBoardCommand(
      tx,
      params.sessionId,
      commandId,
      params.actorId,
      "freezeBoardSnapshot",
      {
        boardId: params.boardId,
        snapshotKind: params.snapshotKind ?? "review",
      }
    );
    if (existing) {
      response = existing;
      return;
    }

    const [boardSnap, sessionStateSnap] = await Promise.all([
      tx.get(boardsCollection(params.sessionId).doc(params.boardId)),
      tx.get(sessionStateRef(params.sessionId)),
    ]);
    if (!boardSnap.exists) throw new Error("board_not_found");
    const role = await requireParticipantRole(tx, params.sessionId, params.actorId);
    const board = normalizeBoardDoc(params.boardId, boardSnap.data() ?? {});
    const actorCanFreeze =
      isTutorRole(role) || (role === "student" && board.ownerId === params.actorId);
    if (!actorCanFreeze) throw new Error("forbidden");

    const snapshotRef = boardSnapshotsCollection(params.sessionId).doc();
    const state = normalizeRoutingState(sessionStateSnap.data() ?? {});
    tx.set(snapshotRef, {
      snapshotId: snapshotRef.id,
      boardId: params.boardId,
      boardKind: board.boardKind,
      ownerId: board.ownerId,
      studentId: params.studentId ?? board.subjectStudentId ?? board.ownerId,
      snapshotKind: params.snapshotKind ?? "review",
      mode: state.roomMode,
      sourceBoardId: board.boardId,
      sourceSnapshotId: board.sourceSnapshotId,
      sourceBoardRevision: board.revisionCursor,
      sourceEventWatermark: board.revisionCursor,
      storagePath: params.storagePath ?? null,
      url: params.url ?? null,
      visibilityScope: "tutorOnly",
      immutable: true,
      locked: true,
      createdBy: params.actorId,
      createdAt: nowServerTs(),
    });

    tx.set(boardSnap.ref, {
      latestSnapshotId: snapshotRef.id,
      ownershipState: params.lockBoard == true ? "lockedForSubmission" : board.ownershipState,
      updatedAt: nowServerTs(),
    }, {merge: true});

    response = {
      ok: true,
      snapshotId: snapshotRef.id,
      boardId: params.boardId,
      sourceBoardRevision: board.revisionCursor,
      snapshotKind: params.snapshotKind ?? "review",
    };
    await completeBoardCommand(tx, params.sessionId, commandId, response);
  });

  return response;
}

export async function promoteSnapshotForBroadcast(params: {
  sessionId: string;
  actorId: string;
  snapshotId: string;
  studentId?: string;
  commandId?: string;
}): Promise<Record<string, unknown>> {
  const commandId = params.commandId || db.collection("_").doc().id;
  let response: Record<string, unknown> = {};

  await db.runTransaction(async (tx) => {
    const existing = await beginBoardCommand(
      tx,
      params.sessionId,
      commandId,
      params.actorId,
      "promoteSnapshotForBroadcast",
      {snapshotId: params.snapshotId}
    );
    if (existing) {
      response = existing;
      return;
    }

    const role = await requireParticipantRole(tx, params.sessionId, params.actorId);
    if (!isTutorRole(role)) throw new Error("forbidden");

    const snapshotRef = boardSnapshotsCollection(params.sessionId).doc(params.snapshotId);
    const snapshotSnap = await tx.get(snapshotRef);
    if (!snapshotSnap.exists) throw new Error("snapshot_not_found");
    const snapshotData = snapshotSnap.data() ?? {};
    const exemplarBoardId = exemplarBoardIdForSnapshot(params.snapshotId);
    tx.set(snapshotRef, {
      visibilityScope: "class",
      broadcastAt: nowServerTs(),
      broadcastBy: params.actorId,
      exemplar: true,
      updatedAt: nowServerTs(),
    }, {merge: true});
    tx.set(boardsCollection(params.sessionId).doc(exemplarBoardId), {
      boardId: exemplarBoardId,
      boardKind: "exemplarBoard",
      ownerId: null,
      subjectStudentId: (params.studentId ?? toTrimmedString(snapshotData.studentId)) || null,
      ownershipState: "broadcastBase",
      visibilityScope: "class",
      transientState: "none",
      sourceBoardId: toTrimmedString(snapshotData.boardId) || null,
      sourceSnapshotId: params.snapshotId,
      previewEnabled: false,
      revisionCursor: 0,
      lastSeqByWriter: {},
      active: true,
      createdAt: nowServerTs(),
      updatedAt: nowServerTs(),
    }, {merge: true});

    response = {
      ok: true,
      snapshotId: params.snapshotId,
      exemplarBoardId,
    };
    await completeBoardCommand(tx, params.sessionId, commandId, response);
  });

  return response;
}

export const onclassroomsessionstatewritten = onDocumentWritten({
  document: "sessions/{sessionId}/sessionState/sessionState",
  region: REGION,
}, async (event) => {
  const sessionId = toTrimmedString(event.params?.sessionId);
  if (!sessionId) return;
  const beforeData = (event.data?.before.data() ?? {}) as Record<string, unknown>;
  const afterData = (event.data?.after.data() ?? {}) as Record<string, unknown>;
  if (relevantBoardStateSignature(beforeData) === relevantBoardStateSignature(afterData)) {
    return;
  }
  try {
    await syncBoardTopology(sessionId);
  } catch (error) {
    logger.error("Failed to sync board topology from session state", {
      sessionId,
      error,
    });
  }
});

export const onclassroomboardparticipantwritten = onDocumentWritten({
  document: "sessions/{sessionId}/participants/{participantId}",
  region: REGION,
}, async (event) => {
  const sessionId = toTrimmedString(event.params?.sessionId);
  if (!sessionId) return;
  const beforeData = (event.data?.before.data() ?? {}) as Record<string, unknown>;
  const afterData = (event.data?.after.data() ?? {}) as Record<string, unknown>;
  if (relevantBoardParticipantSignature(beforeData) === relevantBoardParticipantSignature(afterData)) {
    return;
  }
  try {
    await syncBoardTopology(sessionId);
  } catch (error) {
    logger.error("Failed to sync board topology from participant write", {
      sessionId,
      error,
    });
  }
});

export const onclassroomboardchunkcreated = onDocumentCreated({
  document: "sessions/{sessionId}/boardEventChunks/{chunkId}",
  region: REGION,
}, async (event) => {
  const chunkSnap = event.data;
  if (!chunkSnap) return;
  const sessionId = toTrimmedString(event.params?.sessionId);
  if (!sessionId) return;

  try {
    await db.runTransaction(async (tx) => {
      const freshChunkSnap = await tx.get(chunkSnap.ref);
      if (!freshChunkSnap.exists) return;
      const chunk = freshChunkSnap.data() ?? {};
      if (toTrimmedString(chunk.status) === "accepted" &&
          asNumber(chunk.serverOrder, 0) > 0) {
        return;
      }

      const boardId = toTrimmedString(chunk.boardId);
      const writerId = toTrimmedString(chunk.writerId);
      if (!boardId || !writerId) {
        tx.set(chunkSnap.ref, {
          status: "rejected",
          rejectionReason: "invalid_chunk",
          updatedAt: nowServerTs(),
        }, {merge: true});
        return;
      }

      const [boardSnap, writerSnap] = await Promise.all([
        tx.get(boardsCollection(sessionId).doc(boardId)),
        tx.get(participantCollection(sessionId).doc(writerId)),
      ]);

      if (!boardSnap.exists || !writerSnap.exists) {
        tx.set(chunkSnap.ref, {
          status: "rejected",
          rejectionReason: "board_or_writer_missing",
          updatedAt: nowServerTs(),
        }, {merge: true});
        return;
      }

      const writerRole = normalizeRole(writerSnap.data()?.role);
      const board = normalizeBoardDoc(boardId, boardSnap.data() ?? {});
      const acceptance = evaluateChunkAcceptance({
        board,
        writerId,
        writerRole,
        seqEnd: Math.round(asNumber(chunk.seqEnd, 0)),
      });

      if (acceptance.status !== "accepted") {
        tx.set(chunkSnap.ref, {
          status: acceptance.status,
          rejectionReason: acceptance.reason,
          updatedAt: nowServerTs(),
        }, {merge: true});
        return;
      }

      const nextServerOrder = board.revisionCursor + 1;
      const lastSeqByWriter = {...board.lastSeqByWriter};
      lastSeqByWriter[writerId] = Math.round(asNumber(chunk.seqEnd, 0));

      tx.set(boardSnap.ref, {
        revisionCursor: nextServerOrder,
        lastSeqByWriter,
        lastWriterId: writerId,
        updatedAt: nowServerTs(),
      }, {merge: true});
      tx.set(chunkSnap.ref, {
        status: "accepted",
        serverOrder: nextServerOrder,
        appliedAt: nowServerTs(),
        updatedAt: nowServerTs(),
      }, {merge: true});
      tx.set(thumbnailsCollection(sessionId).doc(boardId), {
        boardId,
        studentId: board.subjectStudentId ?? board.ownerId,
        updatedAt: nowServerTs(),
      }, {merge: true});
      tx.set(thumbnailJobsCollection(sessionId).doc(), {
        boardId,
        ownerId: board.ownerId,
        status: "queued",
        createdAt: nowServerTs(),
      });
    });
  } catch (error) {
    logger.error("Failed to arbitrate board chunk", {sessionId, error});
  }
});
