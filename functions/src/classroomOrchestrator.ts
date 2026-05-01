import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {onDocumentWritten} from "firebase-functions/v2/firestore";

const db = admin.firestore();
const REGION = process.env.PARALLEL_PRACTICE_REGION || "europe-west2";
const SESSION_STATE_DOC_ID = "sessionState";

export type ClassroomRoomMode = "teach" | "practice" | "review";
export type ClassroomFocusMode =
  | "wholeClass"
  | "spotlightStudent"
  | "tutorPrivateReview";
export type ClassroomSpotlightMode = "none" | "soft" | "hard";
export type ClassroomBoardMode =
  | "sharedBoard"
  | "studentPrivateBoards"
  | "reviewBoard";
export type InterventionState =
  | "none"
  | "nudged"
  | "tutorObserving"
  | "tutorIntervening"
  | "correctionSent";
export type ParticipantVisibilityState =
  | "classVisible"
  | "privateBoardOnly"
  | "spotlighted"
  | "reviewVisible";
export type ClassroomParticipantFocusState =
  | "inClass"
  | "privateWork"
  | "underIntervention"
  | "presentingToClass"
  | "inReview"
  | "monitoringGrid"
  | "inIntervention"
  | "presentingReview";
export type ClassroomEventType =
  | "MODE_CHANGED"
  | "FOCUS_CHANGED"
  | "TASK_STARTED"
  | "TASK_COLLECTED"
  | "SPOTLIGHT_STARTED"
  | "SPOTLIGHT_ENDED"
  | "STUDENT_BOARD_BROADCAST"
  | "RETURN_TO_CLASS"
  | "SESSION_ENDED";

type SessionRole = "primaryTutor" | "coTutor" | "student";
type CallMode = "p2p" | "sfu";

interface OrchestratorContextSnapshot {
  roomMode: ClassroomRoomMode;
  focusMode: ClassroomFocusMode;
  boardMode: ClassroomBoardMode;
  attentionTarget: string | null;
  activeBoardRef: string | null;
  classLock: boolean;
}

export interface ClassroomStateDoc {
  mode: ClassroomRoomMode;
  roomMode: ClassroomRoomMode;
  focusMode: ClassroomFocusMode;
  boardMode: ClassroomBoardMode;
  attentionTarget: string | null;
  classLock: boolean;
  callMode: CallMode;
  callModeVersion: number;
  activeTaskId: string | null;
  timerEndAt: admin.firestore.Timestamp | null;
  activeBoardRef: string | null;
  activeInterventionId: string | null;
  orchestratorVersion: number;
  submissionSummary: {
    expectedStudentCount: number;
    submittedStudentCount: number;
    collectedAt: admin.firestore.Timestamp | null;
    collectedSnapshotCount: number;
    collected: boolean;
  };
  settings: {
    studentAnnotateEnabled: boolean;
  };
  spotlight: {
    active: boolean;
    mode: ClassroomSpotlightMode;
    pauseOthers: boolean;
    deEmphasizeOthers: boolean;
    studentId: string | null;
    observeOnly: boolean;
    reason: string | null;
    boardId: string | null;
    startedAt: admin.firestore.Timestamp | null;
    startedBy: string | null;
    momentId: string | null;
    auditId: string | null;
  };
  returnContext: OrchestratorContextSnapshot | null;
}

interface ParticipantView {
  ref: admin.firestore.DocumentReference;
  id: string;
  role: SessionRole;
  joinState: string;
  data: Record<string, unknown>;
}

interface EventPayload {
  type: ClassroomEventType;
  payload?: Record<string, unknown>;
}

interface ActionEnvelope<Result extends Record<string, unknown>> {
  actionId: string;
  result: Result;
}

interface ActionContext {
  tx: admin.firestore.Transaction;
  sessionId: string;
  actorId: string;
  actionId: string;
  sessionRef: admin.firestore.DocumentReference;
  stateRef: admin.firestore.DocumentReference;
  sessionData: Record<string, unknown>;
  state: ClassroomStateDoc;
  participants: ParticipantView[];
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

function actionRef(sessionId: string, actionId: string) {
  return sessionRef(sessionId).collection("orchestratorActions").doc(actionId);
}

function sessionEventRef(sessionId: string, actionId: string, index: number) {
  return sessionRef(sessionId)
    .collection("sessionEvents")
    .doc(`${actionId}_${index.toString().padStart(2, "0")}`);
}

function interventionsCollection(sessionId: string) {
  return sessionRef(sessionId).collection("interventions");
}

function aiJobsCollection(sessionId: string) {
  return sessionRef(sessionId).collection("aiJobs");
}

function aiMomentsCollection(sessionId: string) {
  return sessionRef(sessionId).collection("aiMoments");
}

function spotlightHistoryCollection(sessionId: string) {
  return sessionRef(sessionId).collection("spotlightHistory");
}

function boardsCollection(sessionId: string) {
  return sessionRef(sessionId).collection("boards");
}

function boardSnapshotsCollection(sessionId: string) {
  return sessionRef(sessionId).collection("boardSnapshots");
}

function submissionsCollection(sessionId: string) {
  return sessionRef(sessionId).collection("submissions");
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

function asTimestamp(value: unknown): admin.firestore.Timestamp | null {
  return value instanceof admin.firestore.Timestamp ? value : null;
}

function normalizeRoomMode(value: unknown): ClassroomRoomMode {
  const raw = toTrimmedString(value);
  return raw === "practice" || raw === "review" ? raw : "teach";
}

function normalizeFocusMode(value: unknown): ClassroomFocusMode {
  const raw = toTrimmedString(value);
  if (raw === "spotlightStudent") return raw;
  if (raw === "tutorPrivateReview") return raw;
  return "wholeClass";
}

function normalizeSpotlightMode(value: unknown): ClassroomSpotlightMode {
  const raw = toTrimmedString(value);
  if (raw === "soft" || raw === "hard") return raw;
  return "none";
}

function normalizeBoardMode(value: unknown): ClassroomBoardMode {
  const raw = toTrimmedString(value);
  if (raw === "studentPrivateBoards") return raw;
  if (raw === "reviewBoard") return raw;
  return "sharedBoard";
}

function normalizeCallMode(value: unknown): CallMode {
  return toTrimmedString(value) === "sfu" ? "sfu" : "p2p";
}

function normalizeSessionRole(value: unknown): SessionRole {
  const raw = toTrimmedString(value);
  if (raw === "primaryTutor" || raw === "coTutor") return raw;
  return "student";
}

function buildInitialClassroomState(): ClassroomStateDoc {
  return {
    mode: "teach",
    roomMode: "teach",
    focusMode: "wholeClass",
    boardMode: "sharedBoard",
    attentionTarget: null,
    classLock: true,
    callMode: "p2p",
    callModeVersion: 1,
    activeTaskId: null,
    timerEndAt: null,
    activeBoardRef: null,
    activeInterventionId: null,
    orchestratorVersion: 1,
    submissionSummary: {
      expectedStudentCount: 0,
      submittedStudentCount: 0,
      collectedAt: null,
      collectedSnapshotCount: 0,
      collected: false,
    },
    settings: {
      studentAnnotateEnabled: false,
    },
    spotlight: {
      active: false,
      mode: "none",
      pauseOthers: false,
      deEmphasizeOthers: false,
      studentId: null,
      observeOnly: false,
      reason: null,
      boardId: null,
      startedAt: null,
      startedBy: null,
      momentId: null,
      auditId: null,
    },
    returnContext: null,
  };
}

function normalizeClassroomState(data: Record<string, unknown>): ClassroomStateDoc {
  const defaults = buildInitialClassroomState();
  const settings = (
    data.settings && typeof data.settings === "object" && !Array.isArray(data.settings)
  ) ?
    data.settings as Record<string, unknown> :
    {};
  const submissionSummary = (
    data.submissionSummary &&
    typeof data.submissionSummary === "object" &&
    !Array.isArray(data.submissionSummary)
  ) ?
    data.submissionSummary as Record<string, unknown> :
    {};
  const returnContext = (
    data.returnContext &&
    typeof data.returnContext === "object" &&
    !Array.isArray(data.returnContext)
  ) ?
    data.returnContext as Record<string, unknown> :
    null;
  const spotlight = (
    data.spotlight &&
    typeof data.spotlight === "object" &&
    !Array.isArray(data.spotlight)
  ) ?
    data.spotlight as Record<string, unknown> :
    {};

  const classLock =
    typeof data.classLock === "boolean" ?
      data.classLock :
      !(settings.studentAnnotateEnabled === true);

  return {
    mode: normalizeRoomMode(data.mode),
    roomMode: normalizeRoomMode(data.roomMode ?? data.mode),
    focusMode: normalizeFocusMode(data.focusMode),
    boardMode: normalizeBoardMode(data.boardMode),
    attentionTarget: toTrimmedString(data.attentionTarget) || null,
    classLock,
    callMode: normalizeCallMode(data.callMode),
    callModeVersion: Math.max(1, Math.round(asNumber(data.callModeVersion, 1))),
    activeTaskId: toTrimmedString(data.activeTaskId) || null,
    timerEndAt: asTimestamp(data.timerEndAt),
    activeBoardRef: toTrimmedString(data.activeBoardRef) || null,
    activeInterventionId: toTrimmedString(data.activeInterventionId) || null,
    orchestratorVersion: Math.max(1, Math.round(asNumber(data.orchestratorVersion, 1))),
    submissionSummary: {
      expectedStudentCount: Math.max(
        0,
        Math.round(asNumber(submissionSummary.expectedStudentCount, defaults.submissionSummary.expectedStudentCount))
      ),
      submittedStudentCount: Math.max(
        0,
        Math.round(asNumber(submissionSummary.submittedStudentCount, defaults.submissionSummary.submittedStudentCount))
      ),
      collectedAt: asTimestamp(submissionSummary.collectedAt),
      collectedSnapshotCount: Math.max(
        0,
        Math.round(asNumber(submissionSummary.collectedSnapshotCount, defaults.submissionSummary.collectedSnapshotCount))
      ),
      collected: asBool(submissionSummary.collected, defaults.submissionSummary.collected),
    },
    settings: {
      studentAnnotateEnabled: !classLock,
    },
    spotlight: {
      active: asBool(spotlight.active, defaults.spotlight.active),
      mode: normalizeSpotlightMode(spotlight.mode),
      pauseOthers: asBool(spotlight.pauseOthers, defaults.spotlight.pauseOthers),
      deEmphasizeOthers: asBool(
        spotlight.deEmphasizeOthers,
        defaults.spotlight.deEmphasizeOthers
      ),
      studentId: toTrimmedString(spotlight.studentId) || null,
      observeOnly: asBool(spotlight.observeOnly, defaults.spotlight.observeOnly),
      reason: toTrimmedString(spotlight.reason) || null,
      boardId: toTrimmedString(spotlight.boardId) || null,
      startedAt: asTimestamp(spotlight.startedAt),
      startedBy: toTrimmedString(spotlight.startedBy) || null,
      momentId: toTrimmedString(spotlight.momentId) || null,
      auditId: toTrimmedString(spotlight.auditId) || null,
    },
    returnContext: returnContext ? {
      roomMode: normalizeRoomMode(returnContext.roomMode),
      focusMode: normalizeFocusMode(returnContext.focusMode),
      boardMode: normalizeBoardMode(returnContext.boardMode),
      attentionTarget: toTrimmedString(returnContext.attentionTarget) || null,
      activeBoardRef: toTrimmedString(returnContext.activeBoardRef) || null,
      classLock: asBool(returnContext.classLock, true),
    } : null,
  };
}

function normalizeParticipantVisibility(
  value: unknown,
  fallback: ParticipantVisibilityState
): ParticipantVisibilityState {
  const raw = toTrimmedString(value);
  if (raw === "privateBoardOnly" || raw === "spotlighted" || raw === "reviewVisible") {
    return raw;
  }
  return fallback;
}

function normalizeParticipantFocus(
  value: unknown,
  fallback: ClassroomParticipantFocusState
): ClassroomParticipantFocusState {
  const raw = toTrimmedString(value);
  if ([
    "privateWork",
    "underIntervention",
    "presentingToClass",
    "inReview",
    "monitoringGrid",
    "inIntervention",
    "presentingReview",
  ].includes(raw)) {
    return raw as ClassroomParticipantFocusState;
  }
  return fallback;
}

function normalizeInterventionState(value: unknown): InterventionState {
  const raw = toTrimmedString(value);
  if ([
    "nudged",
    "tutorObserving",
    "tutorIntervening",
    "correctionSent",
  ].includes(raw)) {
    return raw as InterventionState;
  }
  return "none";
}

function activeParticipants(participants: ParticipantView[]): ParticipantView[] {
  return participants.filter((participant) => participant.joinState !== "left");
}

function activeStudents(participants: ParticipantView[]): ParticipantView[] {
  return activeParticipants(participants).filter((participant) => participant.role === "student");
}

function desiredCallMode(participantCount: number, tutorCount: number): CallMode {
  if (participantCount >= 3 || tutorCount >= 2) return "sfu";
  return "p2p";
}

function buildReturnContext(state: ClassroomStateDoc): OrchestratorContextSnapshot {
  return {
    roomMode: state.roomMode,
    focusMode: state.focusMode,
    boardMode: state.boardMode,
    attentionTarget: state.attentionTarget,
    activeBoardRef: state.activeBoardRef,
    classLock: state.classLock,
  };
}

async function appendEvents(
  tx: admin.firestore.Transaction,
  sessionId: string,
  actionId: string,
  actorId: string,
  state: Record<string, unknown>,
  events: EventPayload[]
): Promise<void> {
  events.forEach((event, index) => {
    tx.set(sessionEventRef(sessionId, actionId, index), {
      type: event.type,
      actionId,
      createdBy: actorId,
      roomMode: state.roomMode,
      focusMode: state.focusMode,
      boardMode: state.boardMode,
      attentionTarget: state.attentionTarget ?? null,
      payload: event.payload ?? {},
      createdAt: nowServerTs(),
    });
  });
}

async function markActionCompleted(
  tx: admin.firestore.Transaction,
  sessionId: string,
  actionId: string,
  operation: string,
  actorId: string,
  payload: Record<string, unknown>,
  result: Record<string, unknown>
): Promise<void> {
  tx.set(actionRef(sessionId, actionId), {
    actionId,
    operation,
    actorId,
    payload,
    status: "COMPLETED",
    result,
    completedAt: nowServerTs(),
    updatedAt: nowServerTs(),
  }, {merge: true});
}

async function beginAction(
  tx: admin.firestore.Transaction,
  sessionId: string,
  actionId: string,
  operation: string,
  actorId: string,
  payload: Record<string, unknown>
): Promise<Record<string, unknown> | null> {
  const ref = actionRef(sessionId, actionId);
  const snap = await tx.get(ref);
  if (snap.exists) {
    const data = snap.data() ?? {};
    const status = toTrimmedString(data.status);
    if (status === "COMPLETED" && data.result && typeof data.result === "object") {
      return data.result as Record<string, unknown>;
    }
  }

  tx.set(ref, {
    actionId,
    operation,
    actorId,
    payload,
    status: "PROCESSING",
    createdAt: nowServerTs(),
    updatedAt: nowServerTs(),
  }, {merge: true});
  return null;
}

async function loadActionContext(
  tx: admin.firestore.Transaction,
  sessionId: string,
  actorId: string,
  actionId: string
): Promise<ActionContext> {
  const currentSessionRef = sessionRef(sessionId);
  const currentStateRef = sessionStateRef(sessionId);
  const [sessionSnap, stateSnap, participantsSnap] = await Promise.all([
    tx.get(currentSessionRef),
    tx.get(currentStateRef),
    tx.get(participantCollection(sessionId)),
  ]);

  if (!sessionSnap.exists) {
    throw new Error("not_found");
  }

  const sessionData = sessionSnap.data() ?? {};
  if (toTrimmedString(sessionData.status) === "ended") {
    throw new Error("session_closed");
  }

  const participants = participantsSnap.docs.map((doc) => {
    const data = doc.data() ?? {};
    return {
      ref: doc.ref,
      id: doc.id,
      role: normalizeSessionRole(data.role),
      joinState: toTrimmedString(data.joinState) || "joined",
      data,
    } satisfies ParticipantView;
  });

  return {
    tx,
    sessionId,
    actorId,
    actionId,
    sessionRef: currentSessionRef,
    stateRef: currentStateRef,
    sessionData,
    state: normalizeClassroomState(stateSnap.data() ?? {}),
    participants,
  };
}

function ensureTutorActor(ctx: ActionContext): void {
  const actor = ctx.participants.find((participant) => participant.id === ctx.actorId);
  if (!actor) throw new Error("forbidden");
  if (actor.role !== "primaryTutor" && actor.role !== "coTutor") {
    throw new Error("forbidden");
  }
}

function ensureLeadTutorActor(ctx: ActionContext): void {
  const actor = ctx.participants.find((participant) => participant.id === ctx.actorId);
  if (!actor || actor.role !== "primaryTutor") {
    throw new Error("forbidden");
  }
}

function ensureSpotlightAuthority(
  ctx: ActionContext,
  spotlightMode: ClassroomSpotlightMode,
  pauseOthers: boolean
): void {
  if (spotlightMode === "hard" || pauseOthers) {
    ensureLeadTutorActor(ctx);
    return;
  }
  ensureTutorActor(ctx);
}

function ensureStudentTarget(ctx: ActionContext, studentId: string): ParticipantView {
  const participant = ctx.participants.find((item) => item.id === studentId);
  if (!participant || participant.role !== "student" || participant.joinState === "left") {
    throw new Error("student_not_found");
  }
  return participant;
}

function nextStatePatch(
  state: ClassroomStateDoc,
  patch: Partial<ClassroomStateDoc>
): Record<string, unknown> {
  const merged = {
    ...state,
    ...patch,
    orchestratorVersion: state.orchestratorVersion + 1,
    settings: {
      studentAnnotateEnabled:
        patch.classLock !== undefined ? !patch.classLock : !state.classLock,
    },
  };

  return {
    mode: merged.roomMode,
    roomMode: merged.roomMode,
    focusMode: merged.focusMode,
    boardMode: merged.boardMode,
    attentionTarget: merged.attentionTarget,
    classLock: merged.classLock,
    callMode: merged.callMode,
    callModeVersion: merged.callModeVersion,
    activeTaskId: merged.activeTaskId,
    timerEndAt: merged.timerEndAt,
    activeBoardRef: merged.activeBoardRef,
    activeInterventionId: merged.activeInterventionId,
    orchestratorVersion: merged.orchestratorVersion,
    submissionSummary: merged.submissionSummary,
    settings: merged.settings,
    spotlight: merged.spotlight,
    returnContext: merged.returnContext,
    updatedAt: nowServerTs(),
  };
}

function participantPatch(params: {
  role: SessionRole;
  currentData: Record<string, unknown>;
  focusState: ClassroomParticipantFocusState;
  visibilityState: ParticipantVisibilityState;
  interventionState?: InterventionState;
  currentTaskId?: string | null;
  pinned?: boolean;
  deemphasized?: boolean;
  workPaused?: boolean;
}): Record<string, unknown> {
  const currentInterventionState = normalizeInterventionState(
    params.currentData.interventionState
  );
  const nextInterventionState =
    params.interventionState ?? currentInterventionState;

  return {
    classroomFocusState: normalizeParticipantFocus(
      params.currentData.classroomFocusState,
      params.focusState
    ) === params.focusState ?
      params.focusState :
      params.focusState,
    visibilityState: normalizeParticipantVisibility(
      params.currentData.visibilityState,
      params.visibilityState
    ) === params.visibilityState ?
      params.visibilityState :
      params.visibilityState,
    interventionState: nextInterventionState,
    currentTaskId:
      params.currentTaskId !== undefined ? params.currentTaskId : params.currentData.currentTaskId ?? null,
    pinned:
      params.pinned !== undefined ?
        params.pinned :
        asBool(params.currentData.pinned, params.role !== "student"),
    deemphasized:
      params.deemphasized !== undefined ?
        params.deemphasized :
        asBool(params.currentData.deemphasized, false),
    workPaused:
      params.workPaused !== undefined ?
        params.workPaused :
        asBool(params.currentData.workPaused, false),
    lastOrchestratedAt: nowServerTs(),
  };
}

function buildDefaultActionId(): string {
  return db.collection("_").doc().id;
}

function privateBoardId(studentId: string): string {
  return `student_${studentId}`;
}

async function closeActiveSpotlight(
  tx: admin.firestore.Transaction,
  sessionId: string,
  state: ClassroomStateDoc,
  reason: string
): Promise<void> {
  if (state.spotlight.momentId) {
    tx.set(aiMomentsCollection(sessionId).doc(state.spotlight.momentId), {
      status: "CLOSED",
      endedAt: nowServerTs(),
      endedReason: reason,
    }, {merge: true});
  }
  if (state.spotlight.auditId) {
    tx.set(spotlightHistoryCollection(sessionId).doc(state.spotlight.auditId), {
      status: "CLOSED",
      endedAt: nowServerTs(),
      endedReason: reason,
    }, {merge: true});
  }
}

async function closeActiveIntervention(
  tx: admin.firestore.Transaction,
  sessionId: string,
  state: ClassroomStateDoc,
  reason: string
): Promise<void> {
  if (!state.activeInterventionId) return;
  tx.set(interventionsCollection(sessionId).doc(state.activeInterventionId), {
    state: "CLOSED",
    endedAt: nowServerTs(),
    endedReason: reason,
  }, {merge: true});
}

async function runAction(
  params: {
    sessionId: string;
    actorId: string;
    actionId?: string;
    operation: string;
    payload?: Record<string, unknown>;
    apply: (ctx: ActionContext) => Promise<Record<string, unknown>>;
  }
): Promise<ActionEnvelope<Record<string, unknown>>> {
  const resolvedActionId = params.actionId || buildDefaultActionId();
  let response: Record<string, unknown> | null = null;

  await db.runTransaction(async (tx) => {
    const existing = await beginAction(
      tx,
      params.sessionId,
      resolvedActionId,
      params.operation,
      params.actorId,
      params.payload ?? {}
    );
    if (existing) {
      response = existing;
      return;
    }

    const ctx = await loadActionContext(
      tx,
      params.sessionId,
      params.actorId,
      resolvedActionId
    );
    const result = await params.apply(ctx);
    response = result;
    await markActionCompleted(
      tx,
      params.sessionId,
      resolvedActionId,
      params.operation,
      params.actorId,
      params.payload ?? {},
      result
    );
  });

  return {
    actionId: resolvedActionId,
    result: response ?? {ok: true},
  };
}

export function initialClassroomState(): ClassroomStateDoc {
  return buildInitialClassroomState();
}

export async function reconcileClassroomTopology(sessionId: string): Promise<void> {
  await db.runTransaction(async (tx) => {
    const currentSessionRef = sessionRef(sessionId);
    const currentStateRef = sessionStateRef(sessionId);
    const [sessionSnap, stateSnap, participantsSnap] = await Promise.all([
      tx.get(currentSessionRef),
      tx.get(currentStateRef),
      tx.get(participantCollection(sessionId)),
    ]);

    if (!sessionSnap.exists) return;
    const participants = participantsSnap.docs.map((doc) => {
      const data = doc.data() ?? {};
      return {
        role: normalizeSessionRole(data.role),
        joinState: toTrimmedString(data.joinState) || "joined",
      };
    });
    const active = participants.filter((participant) => participant.joinState !== "left");
    const participantCount = active.length;
    const tutorCount = active.filter(
      (participant) =>
        participant.role === "primaryTutor" || participant.role === "coTutor"
    ).length;
    const nextCall = desiredCallMode(participantCount, tutorCount);
    const state = normalizeClassroomState(stateSnap.data() ?? {});
    const callModeVersion =
      state.callMode === nextCall ? state.callModeVersion : state.callModeVersion + 1;

    tx.set(currentSessionRef, {
      participantCount,
      tutorCount,
      updatedAt: nowServerTs(),
    }, {merge: true});
    tx.set(currentStateRef, {
      callMode: nextCall,
      callModeVersion,
      updatedAt: nowServerTs(),
    }, {merge: true});
  });
}

export async function teachAll(params: {
  sessionId: string;
  actorId: string;
  classLock?: boolean;
  actionId?: string;
}): Promise<ActionEnvelope<Record<string, unknown>>> {
  return runAction({
    sessionId: params.sessionId,
    actorId: params.actorId,
    actionId: params.actionId,
    operation: "teachAll",
    payload: {classLock: params.classLock ?? true},
    apply: async (ctx) => {
      ensureLeadTutorActor(ctx);
      const classLock = params.classLock ?? true;
      await closeActiveIntervention(ctx.tx, ctx.sessionId, ctx.state, "teach_all");
      await closeActiveSpotlight(ctx.tx, ctx.sessionId, ctx.state, "teach_all");
      const statePatch = nextStatePatch(ctx.state, {
        roomMode: "teach",
        focusMode: "wholeClass",
        boardMode: "sharedBoard",
        attentionTarget: null,
        classLock,
        activeInterventionId: null,
        spotlight: buildInitialClassroomState().spotlight,
        returnContext: null,
      });

      ctx.tx.set(ctx.stateRef, statePatch, {merge: true});

      for (const participant of activeParticipants(ctx.participants)) {
        const isStudent = participant.role === "student";
        ctx.tx.set(participant.ref, participantPatch({
          role: participant.role,
          currentData: participant.data,
          focusState: isStudent ? "inClass" : "inClass",
          visibilityState: "classVisible",
          interventionState:
            isStudent &&
            normalizeInterventionState(participant.data.interventionState) === "correctionSent" ?
              "correctionSent" :
              "none",
          pinned: false,
          deemphasized: false,
          workPaused: false,
        }), {merge: true});
      }

      await appendEvents(
        ctx.tx,
        ctx.sessionId,
        ctx.actionId,
        ctx.actorId,
        statePatch,
        [
          {
            type: "MODE_CHANGED",
            payload: {roomMode: "teach", boardMode: "sharedBoard"},
          },
          {
            type: "FOCUS_CHANGED",
            payload: {focusMode: "wholeClass", attentionTarget: null},
          },
        ]
      );

      return {
        ok: true,
        roomMode: "teach",
        focusMode: "wholeClass",
        boardMode: "sharedBoard",
        attentionTarget: null,
        classLock,
        orchestratorVersion: statePatch.orchestratorVersion,
      };
    },
  });
}

export async function monitorEveryoneQuietly(params: {
  sessionId: string;
  actorId: string;
  actionId?: string;
}): Promise<ActionEnvelope<Record<string, unknown>>> {
  return runAction({
    sessionId: params.sessionId,
    actorId: params.actorId,
    actionId: params.actionId,
    operation: "monitorEveryoneQuietly",
    apply: async (ctx) => {
      ensureLeadTutorActor(ctx);
      await closeActiveIntervention(ctx.tx, ctx.sessionId, ctx.state, "monitor_everyone");
      await closeActiveSpotlight(ctx.tx, ctx.sessionId, ctx.state, "monitor_everyone");
      const statePatch = nextStatePatch(ctx.state, {
        roomMode: "practice",
        focusMode: "wholeClass",
        boardMode: "studentPrivateBoards",
        attentionTarget: null,
        classLock: true,
        activeInterventionId: null,
        spotlight: buildInitialClassroomState().spotlight,
        returnContext: null,
      });

      ctx.tx.set(ctx.stateRef, statePatch, {merge: true});

      for (const participant of activeParticipants(ctx.participants)) {
        if (participant.role === "student") {
          const currentIntervention = normalizeInterventionState(
            participant.data.interventionState
          );
          ctx.tx.set(participant.ref, participantPatch({
            role: participant.role,
            currentData: participant.data,
            focusState: "privateWork",
            visibilityState: "privateBoardOnly",
            interventionState:
              currentIntervention === "correctionSent" ? "correctionSent" : "none",
            currentTaskId: ctx.state.activeTaskId,
            pinned: false,
            deemphasized: false,
            workPaused: false,
          }), {merge: true});
        } else {
          ctx.tx.set(participant.ref, participantPatch({
            role: participant.role,
            currentData: participant.data,
            focusState: "monitoringGrid",
            visibilityState: "classVisible",
            pinned: participant.role === "primaryTutor",
            deemphasized: false,
            workPaused: false,
          }), {merge: true});
        }
      }

      await appendEvents(
        ctx.tx,
        ctx.sessionId,
        ctx.actionId,
        ctx.actorId,
        statePatch,
        [
          {
            type: "MODE_CHANGED",
            payload: {roomMode: "practice", boardMode: "studentPrivateBoards"},
          },
          {
            type: "FOCUS_CHANGED",
            payload: {focusMode: "wholeClass", attentionTarget: null},
          },
        ]
      );

      return {
        ok: true,
        roomMode: "practice",
        focusMode: "wholeClass",
        boardMode: "studentPrivateBoards",
        attentionTarget: null,
        orchestratorVersion: statePatch.orchestratorVersion,
      };
    },
  });
}

export async function sendClassworkToStudents(params: {
  sessionId: string;
  actorId: string;
  taskPayload: Record<string, unknown>;
  actionId?: string;
}): Promise<ActionEnvelope<Record<string, unknown>>> {
  return runAction({
    sessionId: params.sessionId,
    actorId: params.actorId,
    actionId: params.actionId,
    operation: "sendClassworkToStudents",
    payload: {taskPayload: params.taskPayload},
    apply: async (ctx) => {
      ensureLeadTutorActor(ctx);
      await closeActiveIntervention(ctx.tx, ctx.sessionId, ctx.state, "send_classwork");
      await closeActiveSpotlight(ctx.tx, ctx.sessionId, ctx.state, "send_classwork");
      const taskRef = sessionRef(ctx.sessionId).collection("tasks").doc();
      const timerSec = Math.max(0, Math.round(asNumber(params.taskPayload.timerSec, 0)));
      const timerEndAt = timerSec > 0 ?
        admin.firestore.Timestamp.fromMillis(Date.now() + timerSec * 1000) :
        null;
      const expectedStudentCount = activeStudents(ctx.participants).length;

      ctx.tx.set(taskRef, {
        prompt: params.taskPayload.prompt ?? "",
        attachments: params.taskPayload.attachments ?? [],
        options: {allowSeshHelp: params.taskPayload.allowSeshHelp ?? true},
        timerSec,
        rubric: params.taskPayload.rubric ?? "",
        expectedSolution: params.taskPayload.expectedSolution ?? "",
        checklist: params.taskPayload.checklist ?? [],
        submissionFormat: params.taskPayload.submissionFormat ?? "final",
        templateId: params.taskPayload.templateId ?? null,
        createdBy: ctx.actorId,
        createdAt: nowServerTs(),
        status: "active",
      });

      const statePatch = nextStatePatch(ctx.state, {
        roomMode: "practice",
        focusMode: "wholeClass",
        boardMode: "studentPrivateBoards",
        attentionTarget: null,
        classLock: true,
        activeTaskId: taskRef.id,
        timerEndAt,
        activeInterventionId: null,
        spotlight: buildInitialClassroomState().spotlight,
        returnContext: null,
        submissionSummary: {
          expectedStudentCount,
          submittedStudentCount: 0,
          collectedAt: null,
          collectedSnapshotCount: 0,
          collected: false,
        },
      });
      ctx.tx.set(ctx.stateRef, statePatch, {merge: true});

      for (const participant of activeParticipants(ctx.participants)) {
        if (participant.role === "student") {
          ctx.tx.set(participant.ref, participantPatch({
            role: participant.role,
            currentData: participant.data,
            focusState: "privateWork",
            visibilityState: "privateBoardOnly",
            interventionState: "none",
            currentTaskId: taskRef.id,
            pinned: false,
            deemphasized: false,
            workPaused: false,
          }), {merge: true});
        } else {
          ctx.tx.set(participant.ref, participantPatch({
            role: participant.role,
            currentData: participant.data,
            focusState: "monitoringGrid",
            visibilityState: "classVisible",
            currentTaskId: taskRef.id,
            pinned: participant.role === "primaryTutor",
            deemphasized: false,
            workPaused: false,
          }), {merge: true});
        }
      }

      await appendEvents(
        ctx.tx,
        ctx.sessionId,
        ctx.actionId,
        ctx.actorId,
        statePatch,
        [
          {
            type: "MODE_CHANGED",
            payload: {roomMode: "practice", boardMode: "studentPrivateBoards"},
          },
          {
            type: "TASK_STARTED",
            payload: {
              taskId: taskRef.id,
              timerEndAt: timerEndAt?.toMillis() ?? null,
              expectedStudentCount,
            },
          },
        ]
      );

      return {
        ok: true,
        taskId: taskRef.id,
        timerEndAt: timerEndAt?.toMillis() ?? null,
        roomMode: "practice",
        focusMode: "wholeClass",
        boardMode: "studentPrivateBoards",
        expectedStudentCount,
        orchestratorVersion: statePatch.orchestratorVersion,
      };
    },
  });
}

export async function focusOnStudent(params: {
  sessionId: string;
  actorId: string;
  studentId: string;
  observeOnly?: boolean;
  spotlightMode?: ClassroomSpotlightMode;
  pauseOthers?: boolean;
  deEmphasizeOthers?: boolean;
  reason?: string;
  actionId?: string;
}): Promise<ActionEnvelope<Record<string, unknown>>> {
  return runAction({
    sessionId: params.sessionId,
    actorId: params.actorId,
    actionId: params.actionId,
    operation: "focusOnStudent",
    payload: {
      studentId: params.studentId,
      observeOnly: params.observeOnly ?? false,
      spotlightMode: params.spotlightMode ?? "hard",
      pauseOthers: params.pauseOthers ?? false,
      deEmphasizeOthers: params.deEmphasizeOthers ?? true,
      reason: params.reason ?? "manual",
    },
    apply: async (ctx) => {
      const spotlightMode = params.spotlightMode ?? "hard";
      const pauseOthers = params.pauseOthers ?? false;
      const deEmphasizeOthers = params.deEmphasizeOthers ?? true;
      ensureSpotlightAuthority(ctx, spotlightMode, pauseOthers);
      ensureStudentTarget(ctx, params.studentId);
      if (ctx.state.roomMode !== "practice" && ctx.state.roomMode !== "review") {
        throw new Error("focus_not_allowed");
      }

      await closeActiveIntervention(ctx.tx, ctx.sessionId, ctx.state, "superseded");
      await closeActiveSpotlight(ctx.tx, ctx.sessionId, ctx.state, "superseded");

      const interventionRef = interventionsCollection(ctx.sessionId).doc();
      const momentRef = aiMomentsCollection(ctx.sessionId).doc();
      const auditRef = spotlightHistoryCollection(ctx.sessionId).doc();
      const interventionState: InterventionState =
        params.observeOnly === true ? "tutorObserving" : "tutorIntervening";
      const returnContext = ctx.state.returnContext ?? buildReturnContext(ctx.state);
      const nextBoardMode =
        ctx.state.roomMode === "review" ? "reviewBoard" : "studentPrivateBoards";
      const statePatch = nextStatePatch(ctx.state, {
        focusMode: "spotlightStudent",
        boardMode: nextBoardMode,
        attentionTarget: params.studentId,
        activeInterventionId: interventionRef.id,
        spotlight: {
          active: true,
          mode: spotlightMode,
          pauseOthers,
          deEmphasizeOthers,
          studentId: params.studentId,
          observeOnly: params.observeOnly ?? false,
          reason: params.reason ?? "manual",
          boardId: privateBoardId(params.studentId),
          startedAt: admin.firestore.Timestamp.now(),
          startedBy: ctx.actorId,
          momentId: momentRef.id,
          auditId: auditRef.id,
        },
        returnContext,
      });

      ctx.tx.set(ctx.stateRef, statePatch, {merge: true});
      ctx.tx.set(interventionRef, {
        interventionId: interventionRef.id,
        studentId: params.studentId,
        tutorId: ctx.actorId,
        taskId: ctx.state.activeTaskId,
        taskStepKey: null,
        boardId: privateBoardId(params.studentId),
        reason: params.reason ?? "manual",
        state: "ACTIVE",
        startedAt: nowServerTs(),
      });
      ctx.tx.set(momentRef, {
        momentId: momentRef.id,
        type: "spotlight",
        importance: "high",
        status: "ACTIVE",
        studentId: params.studentId,
        spotlightMode,
        pauseOthers,
        deEmphasizeOthers,
        observeOnly: params.observeOnly ?? false,
        roomMode: ctx.state.roomMode,
        boardMode: nextBoardMode,
        boardId: privateBoardId(params.studentId),
        interventionId: interventionRef.id,
        createdBy: ctx.actorId,
        startedAt: nowServerTs(),
      });
      ctx.tx.set(auditRef, {
        auditId: auditRef.id,
        actionType: "spotlight_started",
        status: "ACTIVE",
        studentId: params.studentId,
        spotlightMode,
        pauseOthers,
        deEmphasizeOthers,
        observeOnly: params.observeOnly ?? false,
        reason: params.reason ?? "manual",
        interventionId: interventionRef.id,
        momentId: momentRef.id,
        startedBy: ctx.actorId,
        startedAt: nowServerTs(),
        taskId: ctx.state.activeTaskId,
        boardId: privateBoardId(params.studentId),
      });

      for (const participant of activeParticipants(ctx.participants)) {
        if (participant.role === "student") {
          if (participant.id === params.studentId) {
            ctx.tx.set(participant.ref, participantPatch({
              role: participant.role,
              currentData: participant.data,
              focusState: "underIntervention",
              visibilityState: "spotlighted",
              interventionState,
              currentTaskId: ctx.state.activeTaskId,
              pinned: true,
              deemphasized: false,
              workPaused: false,
            }), {merge: true});
          } else {
            ctx.tx.set(participant.ref, participantPatch({
              role: participant.role,
              currentData: participant.data,
              focusState:
                ctx.state.roomMode === "practice" ? "privateWork" : "inClass",
              visibilityState:
                ctx.state.roomMode === "practice" ? "privateBoardOnly" : "classVisible",
              currentTaskId: ctx.state.activeTaskId,
              pinned: false,
              deemphasized: deEmphasizeOthers,
              workPaused: pauseOthers && ctx.state.roomMode === "practice",
            }), {merge: true});
          }
        } else {
          ctx.tx.set(participant.ref, participantPatch({
            role: participant.role,
            currentData: participant.data,
            focusState:
              participant.id === ctx.actorId ? "inIntervention" : "monitoringGrid",
            visibilityState: "classVisible",
            pinned: participant.id === ctx.actorId,
            deemphasized:
              participant.id === ctx.actorId ? false : deEmphasizeOthers,
            workPaused: false,
          }), {merge: true});
        }
      }

      await appendEvents(
        ctx.tx,
        ctx.sessionId,
        ctx.actionId,
        ctx.actorId,
        statePatch,
        [
          {
            type: "FOCUS_CHANGED",
            payload: {
              focusMode: "spotlightStudent",
              attentionTarget: params.studentId,
              spotlightMode,
              pauseOthers,
              deEmphasizeOthers,
            },
          },
          {
            type: "SPOTLIGHT_STARTED",
            payload: {
              studentId: params.studentId,
              observeOnly: params.observeOnly ?? false,
              spotlightMode,
              pauseOthers,
              deEmphasizeOthers,
              interventionId: interventionRef.id,
              momentId: momentRef.id,
            },
          },
        ]
      );

      return {
        ok: true,
        studentId: params.studentId,
        attentionTarget: params.studentId,
        interventionId: interventionRef.id,
        momentId: momentRef.id,
        focusMode: "spotlightStudent",
        boardMode: nextBoardMode,
        spotlightMode,
        pauseOthers,
        deEmphasizeOthers,
        orchestratorVersion: statePatch.orchestratorVersion,
      };
    },
  });
}

export async function returnToClass(params: {
  sessionId: string;
  actorId: string;
  actionId?: string;
}): Promise<ActionEnvelope<Record<string, unknown>>> {
  return runAction({
    sessionId: params.sessionId,
    actorId: params.actorId,
    actionId: params.actionId,
    operation: "returnToClass",
    apply: async (ctx) => {
      ensureLeadTutorActor(ctx);
      const returnContext = ctx.state.returnContext ?? {
        roomMode: ctx.state.roomMode,
        focusMode: "wholeClass" as ClassroomFocusMode,
        boardMode:
          ctx.state.roomMode === "teach" ? "sharedBoard" :
            ctx.state.roomMode === "practice" ? "studentPrivateBoards" :
              "reviewBoard",
        attentionTarget: null,
        activeBoardRef: ctx.state.activeBoardRef,
        classLock: ctx.state.classLock,
      };

      const activeInterventionId = ctx.state.activeInterventionId;
      if (activeInterventionId) {
        ctx.tx.set(interventionsCollection(ctx.sessionId).doc(activeInterventionId), {
          state: "CLOSED",
          endedAt: nowServerTs(),
        }, {merge: true});
      }
      await closeActiveSpotlight(ctx.tx, ctx.sessionId, ctx.state, "returned_to_class");

      const statePatch = nextStatePatch(ctx.state, {
        roomMode: returnContext.roomMode,
        focusMode: "wholeClass",
        boardMode: returnContext.boardMode,
        attentionTarget: null,
        activeBoardRef: returnContext.activeBoardRef,
        classLock: returnContext.classLock,
        activeInterventionId: null,
        spotlight: buildInitialClassroomState().spotlight,
        returnContext: null,
      });

      ctx.tx.set(ctx.stateRef, statePatch, {merge: true});

      for (const participant of activeParticipants(ctx.participants)) {
        if (participant.role === "student") {
          const wasTarget = participant.id === ctx.state.attentionTarget;
          ctx.tx.set(participant.ref, participantPatch({
            role: participant.role,
            currentData: participant.data,
            focusState:
              returnContext.roomMode === "practice" ? "privateWork" :
                returnContext.roomMode === "review" ? "inReview" :
                  "inClass",
            visibilityState:
              returnContext.roomMode === "practice" ? "privateBoardOnly" :
                returnContext.roomMode === "review" ? "reviewVisible" :
                  "classVisible",
            interventionState:
              wasTarget ? "tutorObserving" :
                normalizeInterventionState(participant.data.interventionState),
            currentTaskId: ctx.state.activeTaskId,
            pinned: false,
            deemphasized: false,
            workPaused: false,
          }), {merge: true});
        } else {
          ctx.tx.set(participant.ref, participantPatch({
            role: participant.role,
            currentData: participant.data,
            focusState:
              returnContext.roomMode === "review" ? "presentingReview" :
                returnContext.roomMode === "practice" ? "monitoringGrid" :
                  "inClass",
            visibilityState: "classVisible",
            pinned: participant.role === "primaryTutor",
            deemphasized: false,
            workPaused: false,
          }), {merge: true});
        }
      }

      await appendEvents(
        ctx.tx,
        ctx.sessionId,
        ctx.actionId,
        ctx.actorId,
        statePatch,
        [
          {
            type: "SPOTLIGHT_ENDED",
            payload: {
              previousTarget: ctx.state.attentionTarget,
              spotlightMode: ctx.state.spotlight.mode,
              pauseOthers: ctx.state.spotlight.pauseOthers,
              momentId: ctx.state.spotlight.momentId,
            },
          },
          {
            type: "FOCUS_CHANGED",
            payload: {focusMode: "wholeClass", attentionTarget: null},
          },
          {
            type: "RETURN_TO_CLASS",
            payload: {
              roomMode: returnContext.roomMode,
              boardMode: returnContext.boardMode,
            },
          },
        ]
      );

      return {
        ok: true,
        roomMode: returnContext.roomMode,
        focusMode: "wholeClass",
        boardMode: returnContext.boardMode,
        attentionTarget: null,
        orchestratorVersion: statePatch.orchestratorVersion,
      };
    },
  });
}

export async function collectTaskWork(params: {
  sessionId: string;
  actorId: string;
  actionId?: string;
}): Promise<ActionEnvelope<Record<string, unknown>>> {
  return runAction({
    sessionId: params.sessionId,
    actorId: params.actorId,
    actionId: params.actionId,
    operation: "collectTaskWork",
    apply: async (ctx) => {
      ensureLeadTutorActor(ctx);
      await closeActiveIntervention(ctx.tx, ctx.sessionId, ctx.state, "collect_task_work");
      await closeActiveSpotlight(ctx.tx, ctx.sessionId, ctx.state, "collect_task_work");
      const boardsSnap = await ctx.tx.get(boardsCollection(ctx.sessionId));
      const snapshotIds: string[] = [];
      for (const boardDoc of boardsSnap.docs) {
        const boardData = boardDoc.data() ?? {};
        if (toTrimmedString(boardData.boardKind) !== "studentPrivateBoard") {
          continue;
        }
        const snapshotRef = boardSnapshotsCollection(ctx.sessionId).doc();
        snapshotIds.push(snapshotRef.id);
        ctx.tx.set(snapshotRef, {
          snapshotId: snapshotRef.id,
          boardId: boardDoc.id,
          boardKind: boardData.boardKind ?? "studentPrivateBoard",
          ownerId: boardData.ownerId ?? null,
          studentId: boardData.ownerId ?? null,
          snapshotKind: "submission",
          sourceBoardId: boardDoc.id,
          sourceSnapshotId: boardData.sourceSnapshotId ?? null,
          sourceBoardRevision: boardData.revisionCursor ?? 0,
          sourceEventWatermark: boardData.revisionCursor ?? 0,
          visibilityScope: "tutorOnly",
          immutable: true,
          createdAt: nowServerTs(),
          locked: true,
          source: "collectNow",
        });
      }

      const activeTaskId = ctx.state.activeTaskId;
      const submissionsSnap = activeTaskId ?
        await ctx.tx.get(
          submissionsCollection(ctx.sessionId).where("taskId", "==", activeTaskId)
        ) :
        null;
      const submittedStudentCount = submissionsSnap?.docs.length ?? 0;
      const expectedStudentCount = activeStudents(ctx.participants).length;

      const statePatch = nextStatePatch(ctx.state, {
        roomMode: "review",
        focusMode: "tutorPrivateReview",
        boardMode: "reviewBoard",
        attentionTarget: null,
        classLock: true,
        activeInterventionId: null,
        spotlight: buildInitialClassroomState().spotlight,
        submissionSummary: {
          expectedStudentCount,
          submittedStudentCount,
          collectedAt: admin.firestore.Timestamp.now(),
          collectedSnapshotCount: snapshotIds.length,
          collected: true,
        },
        returnContext: null,
      });
      ctx.tx.set(ctx.stateRef, statePatch, {merge: true});

      for (const participant of activeParticipants(ctx.participants)) {
        if (participant.role === "student") {
          ctx.tx.set(participant.ref, participantPatch({
            role: participant.role,
            currentData: participant.data,
            focusState: "inReview",
            visibilityState: "reviewVisible",
            currentTaskId: ctx.state.activeTaskId,
            pinned: false,
            deemphasized: false,
            workPaused: false,
          }), {merge: true});
        } else {
          ctx.tx.set(participant.ref, participantPatch({
            role: participant.role,
            currentData: participant.data,
            focusState: "presentingReview",
            visibilityState: "classVisible",
            currentTaskId: ctx.state.activeTaskId,
            pinned: participant.role === "primaryTutor",
            deemphasized: false,
            workPaused: false,
          }), {merge: true});
        }
      }

      await appendEvents(
        ctx.tx,
        ctx.sessionId,
        ctx.actionId,
        ctx.actorId,
        statePatch,
        [
          {
            type: "MODE_CHANGED",
            payload: {roomMode: "review", boardMode: "reviewBoard"},
          },
          {
            type: "TASK_COLLECTED",
            payload: {
              activeTaskId,
              submittedStudentCount,
              expectedStudentCount,
              snapshotIds,
            },
          },
        ]
      );

      return {
        ok: true,
        snapshotIds,
        roomMode: "review",
        focusMode: "tutorPrivateReview",
        boardMode: "reviewBoard",
        submittedStudentCount,
        expectedStudentCount,
        orchestratorVersion: statePatch.orchestratorVersion,
      };
    },
  });
}

export async function showStudentBoardToClass(params: {
  sessionId: string;
  actorId: string;
  studentId: string;
  snapshotId: string;
  actionId?: string;
}): Promise<ActionEnvelope<Record<string, unknown>>> {
  return runAction({
    sessionId: params.sessionId,
    actorId: params.actorId,
    actionId: params.actionId,
    operation: "showStudentBoardToClass",
    payload: {
      studentId: params.studentId,
      snapshotId: params.snapshotId,
    },
    apply: async (ctx) => {
      ensureLeadTutorActor(ctx);
      ensureStudentTarget(ctx, params.studentId);
      await closeActiveIntervention(ctx.tx, ctx.sessionId, ctx.state, "broadcast_to_class");
      await closeActiveSpotlight(ctx.tx, ctx.sessionId, ctx.state, "broadcast_to_class");

      const statePatch = nextStatePatch(ctx.state, {
        roomMode: "review",
        focusMode: "wholeClass",
        boardMode: "reviewBoard",
        attentionTarget: params.studentId,
        activeBoardRef: params.snapshotId,
        classLock: true,
        activeInterventionId: null,
        spotlight: buildInitialClassroomState().spotlight,
        returnContext: null,
      });
      ctx.tx.set(ctx.stateRef, statePatch, {merge: true});

      for (const participant of activeParticipants(ctx.participants)) {
        if (participant.role === "student") {
          ctx.tx.set(participant.ref, participantPatch({
            role: participant.role,
            currentData: participant.data,
            focusState:
              participant.id === params.studentId ? "presentingToClass" : "inReview",
            visibilityState:
              participant.id === params.studentId ? "spotlighted" : "reviewVisible",
            currentTaskId: ctx.state.activeTaskId,
            pinned: participant.id === params.studentId,
            deemphasized: false,
            workPaused: false,
          }), {merge: true});
        } else {
          ctx.tx.set(participant.ref, participantPatch({
            role: participant.role,
            currentData: participant.data,
            focusState: "presentingReview",
            visibilityState: "classVisible",
            pinned: participant.role === "primaryTutor",
            deemphasized: false,
            workPaused: false,
          }), {merge: true});
        }
      }

      await appendEvents(
        ctx.tx,
        ctx.sessionId,
        ctx.actionId,
        ctx.actorId,
        statePatch,
        [
          {
            type: "MODE_CHANGED",
            payload: {roomMode: "review", boardMode: "reviewBoard"},
          },
          {
            type: "FOCUS_CHANGED",
            payload: {focusMode: "wholeClass", attentionTarget: params.studentId},
          },
          {
            type: "STUDENT_BOARD_BROADCAST",
            payload: {
              studentId: params.studentId,
              snapshotId: params.snapshotId,
            },
          },
        ]
      );

      return {
        ok: true,
        roomMode: "review",
        focusMode: "wholeClass",
        boardMode: "reviewBoard",
        attentionTarget: params.studentId,
        activeBoardRef: params.snapshotId,
        orchestratorVersion: statePatch.orchestratorVersion,
      };
    },
  });
}

export async function tutorPrivateReviewMode(params: {
  sessionId: string;
  actorId: string;
  actionId?: string;
}): Promise<ActionEnvelope<Record<string, unknown>>> {
  return runAction({
    sessionId: params.sessionId,
    actorId: params.actorId,
    actionId: params.actionId,
    operation: "tutorPrivateReviewMode",
    apply: async (ctx) => {
      ensureLeadTutorActor(ctx);
      await closeActiveIntervention(ctx.tx, ctx.sessionId, ctx.state, "tutor_private_review");
      await closeActiveSpotlight(ctx.tx, ctx.sessionId, ctx.state, "tutor_private_review");
      const statePatch = nextStatePatch(ctx.state, {
        roomMode: "review",
        focusMode: "tutorPrivateReview",
        boardMode: "reviewBoard",
        attentionTarget: null,
        classLock: true,
        activeInterventionId: null,
        spotlight: buildInitialClassroomState().spotlight,
        returnContext: null,
      });
      ctx.tx.set(ctx.stateRef, statePatch, {merge: true});

      for (const participant of activeParticipants(ctx.participants)) {
        if (participant.role === "student") {
          ctx.tx.set(participant.ref, participantPatch({
            role: participant.role,
            currentData: participant.data,
            focusState: "inReview",
            visibilityState: "reviewVisible",
            currentTaskId: ctx.state.activeTaskId,
            pinned: false,
            deemphasized: false,
            workPaused: false,
          }), {merge: true});
        } else {
          ctx.tx.set(participant.ref, participantPatch({
            role: participant.role,
            currentData: participant.data,
            focusState: "presentingReview",
            visibilityState: "classVisible",
            currentTaskId: ctx.state.activeTaskId,
            pinned: participant.role === "primaryTutor",
            deemphasized: false,
            workPaused: false,
          }), {merge: true});
        }
      }

      await appendEvents(
        ctx.tx,
        ctx.sessionId,
        ctx.actionId,
        ctx.actorId,
        statePatch,
        [
          {
            type: "MODE_CHANGED",
            payload: {roomMode: "review", boardMode: "reviewBoard"},
          },
          {
            type: "FOCUS_CHANGED",
            payload: {focusMode: "tutorPrivateReview", attentionTarget: null},
          },
        ]
      );

      return {
        ok: true,
        roomMode: "review",
        focusMode: "tutorPrivateReview",
        boardMode: "reviewBoard",
        attentionTarget: null,
        orchestratorVersion: statePatch.orchestratorVersion,
      };
    },
  });
}

export async function sendCorrection(params: {
  sessionId: string;
  actorId: string;
  studentId: string;
  snapshotId: string;
  annotationsRef: string;
  voiceNoteRef?: string;
  actionId?: string;
}): Promise<ActionEnvelope<Record<string, unknown>>> {
  return runAction({
    sessionId: params.sessionId,
    actorId: params.actorId,
    actionId: params.actionId,
    operation: "sendCorrection",
    payload: {
      studentId: params.studentId,
      snapshotId: params.snapshotId,
      annotationsRef: params.annotationsRef,
      voiceNoteRef: params.voiceNoteRef ?? null,
    },
    apply: async (ctx) => {
      ensureTutorActor(ctx);
      ensureStudentTarget(ctx, params.studentId);
      const interventionRef = interventionsCollection(ctx.sessionId).doc();
      const statePatch = nextStatePatch(ctx.state, {
        roomMode: "review",
        focusMode: "tutorPrivateReview",
        boardMode: "reviewBoard",
        attentionTarget: params.studentId,
        activeBoardRef: params.snapshotId,
        classLock: true,
      });
      ctx.tx.set(ctx.stateRef, statePatch, {merge: true});
      ctx.tx.set(interventionRef, {
        interventionId: interventionRef.id,
        type: "correction",
        studentId: params.studentId,
        taskId: ctx.state.activeTaskId,
        taskStepKey: null,
        boardId: params.snapshotId,
        snapshotId: params.snapshotId,
        annotationsRef: params.annotationsRef,
        voiceNoteRef: params.voiceNoteRef ?? null,
        state: "CLOSED",
        createdBy: ctx.actorId,
        createdAt: nowServerTs(),
      });

      for (const participant of activeParticipants(ctx.participants)) {
        if (participant.role === "student") {
          ctx.tx.set(participant.ref, participantPatch({
            role: participant.role,
            currentData: participant.data,
            focusState:
              participant.id === params.studentId ? "privateWork" : "inReview",
            visibilityState:
              participant.id === params.studentId ? "privateBoardOnly" : "reviewVisible",
            interventionState:
              participant.id === params.studentId ? "correctionSent" :
                normalizeInterventionState(participant.data.interventionState),
            currentTaskId: ctx.state.activeTaskId,
            pinned: false,
          }), {merge: true});
        }
      }

      await appendEvents(
        ctx.tx,
        ctx.sessionId,
        ctx.actionId,
        ctx.actorId,
        statePatch,
        [
          {
            type: "FOCUS_CHANGED",
            payload: {focusMode: "tutorPrivateReview", attentionTarget: params.studentId},
          },
        ]
      );

      return {
        ok: true,
        studentId: params.studentId,
        snapshotId: params.snapshotId,
        attentionTarget: params.studentId,
        focusMode: "tutorPrivateReview",
        boardMode: "reviewBoard",
        orchestratorVersion: statePatch.orchestratorVersion,
      };
    },
  });
}

export async function endSessionWithStructuredOutputs(params: {
  sessionId: string;
  actorId: string;
  wrapOptions?: Record<string, unknown>;
  actionId?: string;
}): Promise<ActionEnvelope<Record<string, unknown>>> {
  return runAction({
    sessionId: params.sessionId,
    actorId: params.actorId,
    actionId: params.actionId,
    operation: "endSessionWithStructuredOutputs",
    payload: {wrapOptions: params.wrapOptions ?? {}},
    apply: async (ctx) => {
      ensureLeadTutorActor(ctx);
      await closeActiveIntervention(ctx.tx, ctx.sessionId, ctx.state, "end_session");
      await closeActiveSpotlight(ctx.tx, ctx.sessionId, ctx.state, "end_session");
      const statePatch = nextStatePatch(ctx.state, {
        roomMode: "review",
        focusMode: "tutorPrivateReview",
        boardMode: "reviewBoard",
        classLock: true,
        spotlight: buildInitialClassroomState().spotlight,
      });
      const aiJobRef = aiJobsCollection(ctx.sessionId).doc();

      ctx.tx.set(ctx.stateRef, statePatch, {merge: true});
      ctx.tx.set(ctx.sessionRef, {
        status: "ended",
        updatedAt: nowServerTs(),
      }, {merge: true});
      ctx.tx.set(aiJobRef, {
        actionType: "sessionPack",
        payload: params.wrapOptions ?? {},
        status: "queued",
        createdBy: ctx.actorId,
        createdByRole: "tutor",
        createdAt: nowServerTs(),
      });

      await appendEvents(
        ctx.tx,
        ctx.sessionId,
        ctx.actionId,
        ctx.actorId,
        statePatch,
        [
          {
            type: "MODE_CHANGED",
            payload: {roomMode: "review", boardMode: "reviewBoard"},
          },
          {
            type: "SESSION_ENDED",
            payload: {jobId: aiJobRef.id},
          },
        ]
      );

      return {
        ok: true,
        roomMode: "review",
        focusMode: "tutorPrivateReview",
        boardMode: "reviewBoard",
        jobId: aiJobRef.id,
        orchestratorVersion: statePatch.orchestratorVersion,
      };
    },
  });
}

export async function recordStudentNudge(params: {
  sessionId: string;
  actorId: string;
  studentId: string;
  hintText: string;
  taskId?: string | null;
  taskStepKey?: string | null;
  boardId?: string | null;
}): Promise<void> {
  await db.runTransaction(async (tx) => {
    const ctx = await loadActionContext(
      tx,
      params.sessionId,
      params.actorId,
      buildDefaultActionId()
    );
    ensureTutorActor(ctx);
    const student = ensureStudentTarget(ctx, params.studentId);
    tx.set(student.ref, {
      interventionState: "nudged",
      lastOrchestratedAt: nowServerTs(),
    }, {merge: true});
    const interventionRef = interventionsCollection(params.sessionId).doc();
    tx.set(interventionRef, {
      interventionId: interventionRef.id,
      type: "broadcastHint",
      studentId: params.studentId,
      taskId: params.taskId ?? ctx.state.activeTaskId,
      taskStepKey: params.taskStepKey ?? null,
      boardId: params.boardId ?? privateBoardId(params.studentId),
      payload: {hintText: params.hintText},
      createdBy: params.actorId,
      createdAt: nowServerTs(),
      state: "CLOSED",
    });
  });
}

export const onclassroomparticipantwritten = onDocumentWritten({
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
    classroomFocusState: toTrimmedString(before.classroomFocusState),
    visibilityState: toTrimmedString(before.visibilityState),
    interventionState: toTrimmedString(before.interventionState),
    currentTaskId: toTrimmedString(before.currentTaskId),
    pinned: before.pinned === true,
    deemphasized: before.deemphasized === true,
    workPaused: before.workPaused === true,
  });
  const afterSignature = JSON.stringify({
    role: toTrimmedString(after.role),
    joinState: toTrimmedString(after.joinState),
    classroomFocusState: toTrimmedString(after.classroomFocusState),
    visibilityState: toTrimmedString(after.visibilityState),
    interventionState: toTrimmedString(after.interventionState),
    currentTaskId: toTrimmedString(after.currentTaskId),
    pinned: after.pinned === true,
    deemphasized: after.deemphasized === true,
    workPaused: after.workPaused === true,
  });
  if (beforeSignature === afterSignature) return;
  try {
    await reconcileClassroomTopology(sessionId);
  } catch (error) {
    logger.error("Failed to reconcile classroom topology", {sessionId, error});
  }
});

export const onclassroomsubmissionwritten = onDocumentWritten({
  document: "sessions/{sessionId}/submissions/{submissionId}",
  region: REGION,
}, async (event) => {
  const sessionId = toTrimmedString(event.params?.sessionId);
  if (!sessionId) return;
  const after = event.data?.after.data() ?? null;
  if (!after) return;
  const taskId = toTrimmedString(after.taskId);
  if (!taskId) return;

  try {
    await db.runTransaction(async (tx) => {
      const [stateSnap, participantsSnap, submissionsSnap] = await Promise.all([
        tx.get(sessionStateRef(sessionId)),
        tx.get(participantCollection(sessionId)),
        tx.get(submissionsCollection(sessionId).where("taskId", "==", taskId)),
      ]);
      const state = normalizeClassroomState(stateSnap.data() ?? {});
      if (state.activeTaskId != taskId) return;

      const expectedStudentCount = participantsSnap.docs
        .map((doc) => {
          const data = doc.data() ?? {};
          return {
            role: normalizeSessionRole(data.role),
            joinState: toTrimmedString(data.joinState) || "joined",
          };
        })
        .filter((participant) => participant.role === "student" && participant.joinState !== "left")
        .length;

      tx.set(sessionStateRef(sessionId), {
        submissionSummary: {
          ...state.submissionSummary,
          expectedStudentCount,
          submittedStudentCount: submissionsSnap.docs.length,
        },
        updatedAt: nowServerTs(),
      }, {merge: true});
    });
  } catch (error) {
    logger.error("Failed to reconcile classroom submissions", {sessionId, error});
  }
});
