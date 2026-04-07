import * as admin from "firebase-admin";
import * as crypto from "node:crypto";
import * as logger from "firebase-functions/logger";
import {
  onDocumentCreated,
  onDocumentWritten,
} from "firebase-functions/v2/firestore";

const db = admin.firestore();
const REGION = process.env.PARALLEL_PRACTICE_REGION || "europe-west2";
const ANALYTICS_SCHEMA_VERSION = 1;
const STUCK_SIGNAL_WINDOW_MS = 5 * 60 * 1000;
const HINT_EFFECT_WINDOW_MS = 15 * 60 * 1000;
const TEACHING_CONFUSION_WINDOW_MS = 15 * 60 * 1000;
const SLOW_MODE_SWITCH_MS = 800;
const BOARD_LAG_SPIKE_MS = 1500;
const THUMBNAIL_SLOW_MS = 2000;
const AI_JOB_SLOW_MS = 5000;
const SESSION_PACK_SLOW_MS = 8000;

export type ClassroomAnalyticsEventKind =
  | "orchestrator_action"
  | "board_sync"
  | "spotlight"
  | "intervention"
  | "submission"
  | "reconnect"
  | "student_status"
  | "teach_marker"
  | "ai_job"
  | "ai_memory_job"
  | "thumbnail_job"
  | "session_pack"
  | "transport_migration";

export interface AnalyticsLatencySummary {
  count: number;
  totalMs: number;
  avgMs: number;
  maxMs: number;
  lastMs: number;
  slowCount: number;
  buckets: {
    le100: number;
    le300: number;
    le800: number;
    le1500: number;
    gt1500: number;
  };
}

export interface ClassroomAnalyticsEventDoc {
  eventId: string;
  schemaVersion: number;
  kind: ClassroomAnalyticsEventKind;
  sourceCollection: string;
  sourceId: string;
  operation: string | null;
  actorId: string | null;
  studentId: string | null;
  taskId: string | null;
  taskStepKey: string | null;
  boardId: string | null;
  markerId: string | null;
  status: string | null;
  occurredAtMs: number;
  latencyMs: number | null;
  durationMs: number | null;
  spotlightMode: string | null;
  details: Record<string, unknown>;
  recordedAt: admin.firestore.FieldValue;
}

export interface ClassroomAnalyticsMetricsDoc {
  sessionId: string;
  schemaVersion: number;
  updatedAt: admin.firestore.FieldValue | admin.firestore.Timestamp;
  summary: {
    modeSwitchCount: number;
    slowModeSwitchCount: number;
    boardAcceptedCount: number;
    boardRejectedCount: number;
    boardIgnoredCount: number;
    boardLagSpikeCount: number;
    thumbnailJobCount: number;
    thumbnailFailureCount: number;
    spotlightCount: number;
    spotlightSoftCount: number;
    spotlightHardCount: number;
    spotlightDurationMsTotal: number;
    interventionCount: number;
    nudgeCount: number;
    correctionCount: number;
    tutorObservationCount: number;
    tutorInterventionCount: number;
    submissionCount: number;
    submissionExpectedCount: number;
    submissionCompletionRate: number;
    reconnectCount: number;
    aiJobSuccessCount: number;
    aiJobFailureCount: number;
    aiJobDegradedCount: number;
    aiMemoryJobSuccessCount: number;
    aiMemoryJobFailureCount: number;
    aiMemoryJobDegradedCount: number;
    sessionPackCount: number;
    sessionPackFailureCount: number;
    studentsFinishedAfterHintCount: number;
    studentsFinishedAfterInterventionCount: number;
    stuckSignalCount: number;
    stuckSignalConfirmedCount: number;
    stuckSignalFalsePositiveCount: number;
    lastActiveTaskId: string | null;
    lastTeachMarkerId: string | null;
    lastTeachMarkerLabel: string | null;
  };
  latency: {
    modeSwitch: AnalyticsLatencySummary;
    boardEventLag: AnalyticsLatencySummary;
    thumbnailGeneration: AnalyticsLatencySummary;
    aiJob: AnalyticsLatencySummary;
    sessionPackGeneration: AnalyticsLatencySummary;
  };
  students: Record<string, Record<string, unknown>>;
  taskSteps: Record<string, Record<string, unknown>>;
  teachingMoments: Record<string, Record<string, unknown>>;
  context: {
    lastTeachMoment: Record<string, unknown> | null;
    lastHintByStudent: Record<string, unknown>;
    lastInterventionByStudent: Record<string, unknown>;
    pendingStuckSignals: Record<string, unknown>;
  };
}

export interface ClassroomAnalyticsExportDoc {
  schemaVersion: number;
  sessionId: string;
  generatedAt: admin.firestore.FieldValue | admin.firestore.Timestamp;
  summary: Record<string, unknown>;
  rankings: {
    studentsNeedingMostIntervention: Array<Record<string, unknown>>;
    taskStepsWithMostStruggle: Array<Record<string, unknown>>;
    teachingMomentsWithMostConfusion: Array<Record<string, unknown>>;
  };
  health: {
    aiFailures: number;
    aiDegraded: number;
    thumbnailFailures: number;
    slowModeSwitches: number;
    boardLagSpikes: number;
  };
}

interface AnalyticsRollupEvent {
  kind: ClassroomAnalyticsEventKind;
  sourceCollection: string;
  sourceId: string;
  operation?: string | null;
  actorId?: string | null;
  studentId?: string | null;
  taskId?: string | null;
  taskStepKey?: string | null;
  boardId?: string | null;
  markerId?: string | null;
  status?: string | null;
  occurredAtMs: number;
  latencyMs?: number | null;
  durationMs?: number | null;
  spotlightMode?: string | null;
  details?: Record<string, unknown>;
}

function nowServerTs() {
  return admin.firestore.FieldValue.serverTimestamp();
}

function sessionRef(sessionId: string) {
  return db.collection("sessions").doc(sessionId);
}

function analyticsEventsCollection(sessionId: string) {
  return sessionRef(sessionId).collection("analyticsEvents");
}

function analyticsMetricsRef(sessionId: string) {
  return sessionRef(sessionId).collection("analyticsMetrics").doc("current");
}

function analyticsExportRef(sessionId: string) {
  return sessionRef(sessionId).collection("analyticsExports").doc("current");
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

function asBool(value: unknown, fallback = false): boolean {
  return typeof value === "boolean" ? value : fallback;
}

function asTimestamp(value: unknown): admin.firestore.Timestamp | null {
  return value instanceof admin.firestore.Timestamp ? value : null;
}

function sanitizeObject(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value) ?
    value as Record<string, unknown> :
    {};
}

function cloneMetrics(value: ClassroomAnalyticsMetricsDoc): ClassroomAnalyticsMetricsDoc {
  return JSON.parse(JSON.stringify(value)) as ClassroomAnalyticsMetricsDoc;
}

function hashId(parts: Array<string | number | null | undefined>): string {
  return crypto.createHash("sha1")
    .update(parts.map((part) => String(part ?? "")).join("|"))
    .digest("hex")
    .slice(0, 20);
}

function latencySummary(): AnalyticsLatencySummary {
  return {
    count: 0,
    totalMs: 0,
    avgMs: 0,
    maxMs: 0,
    lastMs: 0,
    slowCount: 0,
    buckets: {
      le100: 0,
      le300: 0,
      le800: 0,
      le1500: 0,
      gt1500: 0,
    },
  };
}

export function initialClassroomAnalyticsMetrics(sessionId: string): ClassroomAnalyticsMetricsDoc {
  return {
    sessionId,
    schemaVersion: ANALYTICS_SCHEMA_VERSION,
    updatedAt: admin.firestore.Timestamp.now(),
    summary: {
      modeSwitchCount: 0,
      slowModeSwitchCount: 0,
      boardAcceptedCount: 0,
      boardRejectedCount: 0,
      boardIgnoredCount: 0,
      boardLagSpikeCount: 0,
      thumbnailJobCount: 0,
      thumbnailFailureCount: 0,
      spotlightCount: 0,
      spotlightSoftCount: 0,
      spotlightHardCount: 0,
      spotlightDurationMsTotal: 0,
      interventionCount: 0,
      nudgeCount: 0,
      correctionCount: 0,
      tutorObservationCount: 0,
      tutorInterventionCount: 0,
      submissionCount: 0,
      submissionExpectedCount: 0,
      submissionCompletionRate: 0,
      reconnectCount: 0,
      aiJobSuccessCount: 0,
      aiJobFailureCount: 0,
      aiJobDegradedCount: 0,
      aiMemoryJobSuccessCount: 0,
      aiMemoryJobFailureCount: 0,
      aiMemoryJobDegradedCount: 0,
      sessionPackCount: 0,
      sessionPackFailureCount: 0,
      studentsFinishedAfterHintCount: 0,
      studentsFinishedAfterInterventionCount: 0,
      stuckSignalCount: 0,
      stuckSignalConfirmedCount: 0,
      stuckSignalFalsePositiveCount: 0,
      lastActiveTaskId: null,
      lastTeachMarkerId: null,
      lastTeachMarkerLabel: null,
    },
    latency: {
      modeSwitch: latencySummary(),
      boardEventLag: latencySummary(),
      thumbnailGeneration: latencySummary(),
      aiJob: latencySummary(),
      sessionPackGeneration: latencySummary(),
    },
    students: {},
    taskSteps: {},
    teachingMoments: {},
    context: {
      lastTeachMoment: null,
      lastHintByStudent: {},
      lastInterventionByStudent: {},
      pendingStuckSignals: {},
    },
  };
}

function observeLatency(summary: AnalyticsLatencySummary, ms: number, slowThresholdMs: number) {
  const safeMs = Math.max(0, Math.round(ms));
  summary.count += 1;
  summary.totalMs += safeMs;
  summary.avgMs = summary.count > 0 ? Number((summary.totalMs / summary.count).toFixed(2)) : 0;
  summary.maxMs = Math.max(summary.maxMs, safeMs);
  summary.lastMs = safeMs;
  if (safeMs >= slowThresholdMs) summary.slowCount += 1;
  if (safeMs <= 100) summary.buckets.le100 += 1;
  else if (safeMs <= 300) summary.buckets.le300 += 1;
  else if (safeMs <= 800) summary.buckets.le800 += 1;
  else if (safeMs <= 1500) summary.buckets.le1500 += 1;
  else summary.buckets.gt1500 += 1;
}

function ensureStudentMetrics(metrics: ClassroomAnalyticsMetricsDoc, studentId: string): Record<string, unknown> {
  const current = sanitizeObject(metrics.students[studentId]);
  const next = {
    studentId,
    interventionCount: asNumber(current.interventionCount, 0),
    nudgeCount: asNumber(current.nudgeCount, 0),
    correctionCount: asNumber(current.correctionCount, 0),
    spotlightCount: asNumber(current.spotlightCount, 0),
    spotlightDurationMsTotal: asNumber(current.spotlightDurationMsTotal, 0),
    submissionCount: asNumber(current.submissionCount, 0),
    reconnectCount: asNumber(current.reconnectCount, 0),
    stuckSignalCount: asNumber(current.stuckSignalCount, 0),
    stuckSignalConfirmedCount: asNumber(current.stuckSignalConfirmedCount, 0),
    stuckSignalFalsePositiveCount: asNumber(current.stuckSignalFalsePositiveCount, 0),
    finishedAfterHintCount: asNumber(current.finishedAfterHintCount, 0),
    finishedAfterInterventionCount: asNumber(current.finishedAfterInterventionCount, 0),
    hintsReceivedCount: asNumber(current.hintsReceivedCount, 0),
    lastHintAtMs: asNumber(current.lastHintAtMs, 0),
    lastInterventionAtMs: asNumber(current.lastInterventionAtMs, 0),
    lastSpotlightAtMs: asNumber(current.lastSpotlightAtMs, 0),
    lastSubmissionAtMs: asNumber(current.lastSubmissionAtMs, 0),
  } satisfies Record<string, unknown>;
  metrics.students[studentId] = next;
  return next;
}

function ensureTaskStepMetrics(
  metrics: ClassroomAnalyticsMetricsDoc,
  taskStepKey: string,
  taskId: string | null,
): Record<string, unknown> {
  const key = taskStepKey || taskId || "unscoped";
  const current = sanitizeObject(metrics.taskSteps[key]);
  const next = {
    taskStepKey: key,
    taskId: taskId,
    struggleCount: asNumber(current.struggleCount, 0),
    hintCount: asNumber(current.hintCount, 0),
    interventionCount: asNumber(current.interventionCount, 0),
    submissionCount: asNumber(current.submissionCount, 0),
    lastStruggleAtMs: asNumber(current.lastStruggleAtMs, 0),
  } satisfies Record<string, unknown>;
  metrics.taskSteps[key] = next;
  return next;
}

function ensureTeachingMomentMetrics(
  metrics: ClassroomAnalyticsMetricsDoc,
  markerId: string,
  data: {
    label?: string | null;
    markerType?: string | null;
    taskId?: string | null;
    boardId?: string | null;
    createdAtMs?: number | null;
  } = {},
): Record<string, unknown> {
  const current = sanitizeObject(metrics.teachingMoments[markerId]);
  const next = {
    markerId,
    label: data.label ?? (toTrimmedString(current.label) || null),
    markerType: data.markerType ?? (toTrimmedString(current.markerType) || null),
    taskId: data.taskId ?? (toTrimmedString(current.taskId) || null),
    boardId: data.boardId ?? (toTrimmedString(current.boardId) || null),
    createdAtMs: data.createdAtMs ?? asNumber(current.createdAtMs, 0),
    confusionCount: asNumber(current.confusionCount, 0),
    interventionCount: asNumber(current.interventionCount, 0),
    spotlightCount: asNumber(current.spotlightCount, 0),
    lastConfusionAtMs: asNumber(current.lastConfusionAtMs, 0),
  } satisfies Record<string, unknown>;
  metrics.teachingMoments[markerId] = next;
  return next;
}

function roundRate(numerator: number, denominator: number): number {
  if (denominator <= 0) return 0;
  return Number(((numerator / denominator) * 100).toFixed(2));
}

function currentContextMap(
  metrics: ClassroomAnalyticsMetricsDoc,
  key: "lastHintByStudent" | "lastInterventionByStudent" | "pendingStuckSignals",
) {
  return sanitizeObject(metrics.context[key]);
}

function setContextMap(
  metrics: ClassroomAnalyticsMetricsDoc,
  key: "lastHintByStudent" | "lastInterventionByStudent" | "pendingStuckSignals",
  next: Record<string, unknown>,
) {
  metrics.context[key] = next;
}

function maybeAttributeTeachingConfusion(metrics: ClassroomAnalyticsMetricsDoc, params: {
  studentId: string | null;
  taskId: string | null;
  boardId: string | null;
  occurredAtMs: number;
  source: "hint" | "intervention" | "spotlight";
}) {
  const lastTeachMoment = sanitizeObject(metrics.context.lastTeachMoment);
  const markerId = toTrimmedString(lastTeachMoment.markerId);
  if (!markerId) return;
  const createdAtMs = asNumber(lastTeachMoment.createdAtMs, 0);
  if (createdAtMs <= 0) return;
  if (params.occurredAtMs - createdAtMs > TEACHING_CONFUSION_WINDOW_MS) return;

  const teachTaskId = toTrimmedString(lastTeachMoment.taskId) || null;
  const teachBoardId = toTrimmedString(lastTeachMoment.boardId) || null;
  const matchesContext =
    (params.taskId != null && teachTaskId != null && params.taskId === teachTaskId) ||
    (params.boardId != null && teachBoardId != null && params.boardId === teachBoardId) ||
    (teachTaskId == null && teachBoardId == null);
  if (!matchesContext) return;

  const moment = ensureTeachingMomentMetrics(metrics, markerId);
  moment.confusionCount = asNumber(moment.confusionCount, 0) + 1;
  moment.lastConfusionAtMs = params.occurredAtMs;
  if (params.source === "intervention") {
    moment.interventionCount = asNumber(moment.interventionCount, 0) + 1;
  }
  if (params.source === "spotlight") {
    moment.spotlightCount = asNumber(moment.spotlightCount, 0) + 1;
  }
}

function maybeConfirmStuckSignal(
  metrics: ClassroomAnalyticsMetricsDoc,
  studentId: string | null,
  occurredAtMs: number,
  resolution: "confirmed" | "false_positive",
) {
  if (!studentId) return;
  const pendingSignals = currentContextMap(metrics, "pendingStuckSignals");
  const signal = sanitizeObject(pendingSignals[studentId]);
  const signalledAtMs = asNumber(signal.atMs, 0);
  if (signalledAtMs <= 0 || occurredAtMs - signalledAtMs > STUCK_SIGNAL_WINDOW_MS) {
    return;
  }

  const student = ensureStudentMetrics(metrics, studentId);
  if (resolution === "confirmed") {
    metrics.summary.stuckSignalConfirmedCount += 1;
    student.stuckSignalConfirmedCount = asNumber(student.stuckSignalConfirmedCount, 0) + 1;
  } else {
    metrics.summary.stuckSignalFalsePositiveCount += 1;
    student.stuckSignalFalsePositiveCount = asNumber(student.stuckSignalFalsePositiveCount, 0) + 1;
  }
  delete pendingSignals[studentId];
  setContextMap(metrics, "pendingStuckSignals", pendingSignals);
}

function maybeMarkSubmissionOutcome(metrics: ClassroomAnalyticsMetricsDoc, params: {
  studentId: string | null;
  taskId: string | null;
  occurredAtMs: number;
}) {
  if (!params.studentId) return;
  const hintMap = currentContextMap(metrics, "lastHintByStudent");
  const interventionMap = currentContextMap(metrics, "lastInterventionByStudent");
  const hint = sanitizeObject(hintMap[params.studentId]);
  const intervention = sanitizeObject(interventionMap[params.studentId]);
  const hintAtMs = asNumber(hint.atMs, 0);
  const interventionAtMs = asNumber(intervention.atMs, 0);
  const hintTaskId = toTrimmedString(hint.taskId) || null;
  const interventionTaskId = toTrimmedString(intervention.taskId) || null;
  const withinHintWindow =
    hintAtMs > 0 &&
    params.occurredAtMs - hintAtMs <= HINT_EFFECT_WINDOW_MS &&
    (hintTaskId == null || params.taskId == null || hintTaskId === params.taskId);
  const withinInterventionWindow =
    interventionAtMs > 0 &&
    params.occurredAtMs - interventionAtMs <= HINT_EFFECT_WINDOW_MS &&
    (interventionTaskId == null || params.taskId == null || interventionTaskId === params.taskId);

  const student = ensureStudentMetrics(metrics, params.studentId);
  if (withinInterventionWindow) {
    metrics.summary.studentsFinishedAfterInterventionCount += 1;
    student.finishedAfterInterventionCount = asNumber(student.finishedAfterInterventionCount, 0) + 1;
  } else if (withinHintWindow) {
    metrics.summary.studentsFinishedAfterHintCount += 1;
    student.finishedAfterHintCount = asNumber(student.finishedAfterHintCount, 0) + 1;
  }
}

export function applyAnalyticsEvent(
  metricsInput: ClassroomAnalyticsMetricsDoc,
  event: AnalyticsRollupEvent,
): ClassroomAnalyticsMetricsDoc {
  const metrics = cloneMetrics(metricsInput);
  metrics.schemaVersion = ANALYTICS_SCHEMA_VERSION;
  metrics.summary.lastActiveTaskId = event.taskId ?? metrics.summary.lastActiveTaskId;

  switch (event.kind) {
  case "orchestrator_action": {
    const operation = toTrimmedString(event.operation);
    if ([
      "teachAll",
      "monitorEveryoneQuietly",
      "sendClassworkToStudents",
      "focusOnStudent",
      "returnToClass",
      "collectTaskWork",
      "showStudentBoardToClass",
      "tutorPrivateReviewMode",
    ].includes(operation)) {
      metrics.summary.modeSwitchCount += 1;
      if ((event.latencyMs ?? 0) >= SLOW_MODE_SWITCH_MS) {
        metrics.summary.slowModeSwitchCount += 1;
      }
      if (event.latencyMs != null) {
        observeLatency(metrics.latency.modeSwitch, event.latencyMs, SLOW_MODE_SWITCH_MS);
      }
    }
    if (operation === "sendClassworkToStudents") {
      const expected = asNumber(event.details?.expectedStudentCount, metrics.summary.submissionExpectedCount);
      metrics.summary.submissionExpectedCount = expected;
      metrics.summary.submissionCompletionRate = roundRate(
        metrics.summary.submissionCount,
        expected,
      );
      metrics.summary.lastActiveTaskId = event.taskId ?? metrics.summary.lastActiveTaskId;
    }
    if (operation === "collectTaskWork") {
      const expected = asNumber(event.details?.expectedStudentCount, metrics.summary.submissionExpectedCount);
      const submitted = asNumber(event.details?.submittedStudentCount, metrics.summary.submissionCount);
      metrics.summary.submissionExpectedCount = expected;
      metrics.summary.submissionCount = Math.max(metrics.summary.submissionCount, submitted);
      metrics.summary.submissionCompletionRate = roundRate(submitted, expected);
    }
    break;
  }

  case "board_sync": {
    const status = toTrimmedString(event.status);
    if (status === "accepted") {
      metrics.summary.boardAcceptedCount += 1;
      if (event.latencyMs != null) {
        observeLatency(metrics.latency.boardEventLag, event.latencyMs, BOARD_LAG_SPIKE_MS);
        if (event.latencyMs >= BOARD_LAG_SPIKE_MS) {
          metrics.summary.boardLagSpikeCount += 1;
        }
      }
    } else if (status === "ignored") {
      metrics.summary.boardIgnoredCount += 1;
    } else {
      metrics.summary.boardRejectedCount += 1;
    }
    break;
  }

  case "thumbnail_job": {
    metrics.summary.thumbnailJobCount += 1;
    if (event.latencyMs != null) {
      observeLatency(metrics.latency.thumbnailGeneration, event.latencyMs, THUMBNAIL_SLOW_MS);
    }
    if (["error", "failed", "skipped"].includes(toTrimmedString(event.status))) {
      metrics.summary.thumbnailFailureCount += 1;
    }
    break;
  }

  case "spotlight": {
    const studentId = event.studentId;
    metrics.summary.spotlightCount += 1;
    if (toTrimmedString(event.spotlightMode) === "soft") {
      metrics.summary.spotlightSoftCount += 1;
    } else {
      metrics.summary.spotlightHardCount += 1;
    }
    if (event.durationMs != null) {
      metrics.summary.spotlightDurationMsTotal += Math.max(0, Math.round(event.durationMs));
    }
    if (studentId) {
      const student = ensureStudentMetrics(metrics, studentId);
      student.spotlightCount = asNumber(student.spotlightCount, 0) + 1;
      student.lastSpotlightAtMs = event.occurredAtMs;
      if (event.durationMs != null) {
        student.spotlightDurationMsTotal = asNumber(student.spotlightDurationMsTotal, 0) + Math.max(0, Math.round(event.durationMs));
      }
      maybeAttributeTeachingConfusion(metrics, {
        studentId,
        taskId: event.taskId ?? null,
        boardId: event.boardId ?? null,
        occurredAtMs: event.occurredAtMs,
        source: "spotlight",
      });
    }
    break;
  }

  case "intervention": {
    const studentId = event.studentId;
    const interventionType = toTrimmedString(event.status);
    metrics.summary.interventionCount += 1;
    if (studentId) {
      const student = ensureStudentMetrics(metrics, studentId);
      student.interventionCount = asNumber(student.interventionCount, 0) + 1;
      student.lastInterventionAtMs = event.occurredAtMs;
      maybeConfirmStuckSignal(metrics, studentId, event.occurredAtMs, "confirmed");
      if (interventionType !== "broadcastHint" && interventionType !== "hint") {
        const interventionContext = currentContextMap(metrics, "lastInterventionByStudent");
        interventionContext[studentId] = {
          atMs: event.occurredAtMs,
          taskId: event.taskId,
          taskStepKey: event.taskStepKey,
          type: interventionType,
        };
        setContextMap(metrics, "lastInterventionByStudent", interventionContext);
      }
    }
    const task = ensureTaskStepMetrics(metrics, event.taskStepKey ?? "", event.taskId ?? null);
    task.struggleCount = asNumber(task.struggleCount, 0) + 1;
    task.interventionCount = asNumber(task.interventionCount, 0) + 1;
    task.lastStruggleAtMs = event.occurredAtMs;
    maybeAttributeTeachingConfusion(metrics, {
      studentId: studentId ?? null,
      taskId: event.taskId ?? null,
      boardId: event.boardId ?? null,
      occurredAtMs: event.occurredAtMs,
      source: "intervention",
    });
    if (interventionType === "broadcastHint" || interventionType === "hint") {
      metrics.summary.nudgeCount += 1;
      if (studentId) {
        const student = ensureStudentMetrics(metrics, studentId);
        student.nudgeCount = asNumber(student.nudgeCount, 0) + 1;
        student.hintsReceivedCount = asNumber(student.hintsReceivedCount, 0) + 1;
        student.lastHintAtMs = event.occurredAtMs;
        const hintContext = currentContextMap(metrics, "lastHintByStudent");
        hintContext[studentId] = {
          atMs: event.occurredAtMs,
          taskId: event.taskId,
          taskStepKey: event.taskStepKey,
        };
        setContextMap(metrics, "lastHintByStudent", hintContext);
      }
      task.hintCount = asNumber(task.hintCount, 0) + 1;
      maybeAttributeTeachingConfusion(metrics, {
        studentId: studentId ?? null,
        taskId: event.taskId ?? null,
        boardId: event.boardId ?? null,
        occurredAtMs: event.occurredAtMs,
        source: "hint",
      });
    }
    if (interventionType === "correction") {
      metrics.summary.correctionCount += 1;
      if (studentId) {
        const student = ensureStudentMetrics(metrics, studentId);
        student.correctionCount = asNumber(student.correctionCount, 0) + 1;
      }
    }
    if (interventionType === "tutorObserving") {
      metrics.summary.tutorObservationCount += 1;
    }
    if (interventionType === "tutorIntervening" || interventionType === "focus") {
      metrics.summary.tutorInterventionCount += 1;
    }
    break;
  }

  case "submission": {
    metrics.summary.submissionCount += 1;
    if (event.studentId) {
      const student = ensureStudentMetrics(metrics, event.studentId);
      student.submissionCount = asNumber(student.submissionCount, 0) + 1;
      student.lastSubmissionAtMs = event.occurredAtMs;
      maybeMarkSubmissionOutcome(metrics, {
        studentId: event.studentId,
        taskId: event.taskId ?? null,
        occurredAtMs: event.occurredAtMs,
      });
      maybeConfirmStuckSignal(metrics, event.studentId, event.occurredAtMs, "false_positive");
    }
    const task = ensureTaskStepMetrics(metrics, event.taskStepKey ?? "", event.taskId ?? null);
    task.submissionCount = asNumber(task.submissionCount, 0) + 1;
    metrics.summary.submissionCompletionRate = roundRate(
      metrics.summary.submissionCount,
      metrics.summary.submissionExpectedCount,
    );
    break;
  }

  case "reconnect": {
    metrics.summary.reconnectCount += 1;
    if (event.studentId) {
      const student = ensureStudentMetrics(metrics, event.studentId);
      student.reconnectCount = asNumber(student.reconnectCount, 0) + 1;
    }
    break;
  }

  case "student_status": {
    const status = toTrimmedString(event.status);
    if ((status === "stuck" || status === "idle") && event.studentId) {
      metrics.summary.stuckSignalCount += 1;
      const student = ensureStudentMetrics(metrics, event.studentId);
      student.stuckSignalCount = asNumber(student.stuckSignalCount, 0) + 1;
      const signals = currentContextMap(metrics, "pendingStuckSignals");
      signals[event.studentId] = {
        atMs: event.occurredAtMs,
        status,
        taskId: event.taskId,
        taskStepKey: event.taskStepKey,
      };
      setContextMap(metrics, "pendingStuckSignals", signals);
      const task = ensureTaskStepMetrics(metrics, event.taskStepKey ?? "", event.taskId ?? null);
      task.struggleCount = asNumber(task.struggleCount, 0) + 1;
      task.lastStruggleAtMs = event.occurredAtMs;
    }
    break;
  }

  case "teach_marker": {
    const markerId = event.markerId ?? event.sourceId;
    const label = toTrimmedString(event.details?.label) || markerId;
    ensureTeachingMomentMetrics(metrics, markerId, {
      label,
      markerType: toTrimmedString(event.details?.markerType) || null,
      taskId: event.taskId ?? null,
      boardId: event.boardId ?? null,
      createdAtMs: event.occurredAtMs,
    });
    metrics.summary.lastTeachMarkerId = markerId;
    metrics.summary.lastTeachMarkerLabel = label;
    metrics.context.lastTeachMoment = {
      markerId,
      label,
      markerType: toTrimmedString(event.details?.markerType) || null,
      taskId: event.taskId ?? null,
      boardId: event.boardId ?? null,
      createdAtMs: event.occurredAtMs,
    };
    break;
  }

  case "ai_job": {
    if (event.latencyMs != null) {
      observeLatency(metrics.latency.aiJob, event.latencyMs, AI_JOB_SLOW_MS);
    }
    const status = toTrimmedString(event.status);
    if (status === "completed" || status === "done") {
      metrics.summary.aiJobSuccessCount += 1;
    } else if (status === "degraded") {
      metrics.summary.aiJobDegradedCount += 1;
    } else {
      metrics.summary.aiJobFailureCount += 1;
    }
    if (event.operation === "studentHelp") {
      const task = ensureTaskStepMetrics(metrics, event.taskStepKey ?? "", event.taskId ?? null);
      task.struggleCount = asNumber(task.struggleCount, 0) + 1;
      task.lastStruggleAtMs = event.occurredAtMs;
      maybeAttributeTeachingConfusion(metrics, {
        studentId: event.studentId ?? null,
        taskId: event.taskId ?? null,
        boardId: event.boardId ?? null,
        occurredAtMs: event.occurredAtMs,
        source: "hint",
      });
    }
    break;
  }

  case "ai_memory_job": {
    const status = toTrimmedString(event.status);
    if (status === "completed") metrics.summary.aiMemoryJobSuccessCount += 1;
    else if (status === "degraded") metrics.summary.aiMemoryJobDegradedCount += 1;
    else metrics.summary.aiMemoryJobFailureCount += 1;
    break;
  }

  case "session_pack": {
    metrics.summary.sessionPackCount += 1;
    if (event.latencyMs != null) {
      observeLatency(metrics.latency.sessionPackGeneration, event.latencyMs, SESSION_PACK_SLOW_MS);
    }
    if (toTrimmedString(event.status) !== "completed") {
      metrics.summary.sessionPackFailureCount += 1;
    }
    break;
  }

  case "transport_migration":
    break;
  }

  return metrics;
}

export function buildClassroomAnalyticsExport(metrics: ClassroomAnalyticsMetricsDoc): ClassroomAnalyticsExportDoc {
  const students = Object.values(metrics.students)
    .map((entry) => sanitizeObject(entry))
    .sort((left, right) =>
      asNumber(right.interventionCount, 0) - asNumber(left.interventionCount, 0) ||
      asNumber(right.spotlightDurationMsTotal, 0) - asNumber(left.spotlightDurationMsTotal, 0))
    .slice(0, 5)
    .map((entry) => ({
      studentId: toTrimmedString(entry.studentId),
      interventionCount: asNumber(entry.interventionCount, 0),
      spotlightDurationMsTotal: asNumber(entry.spotlightDurationMsTotal, 0),
      stuckSignalCount: asNumber(entry.stuckSignalCount, 0),
      finishedAfterHintCount: asNumber(entry.finishedAfterHintCount, 0),
      finishedAfterInterventionCount: asNumber(entry.finishedAfterInterventionCount, 0),
    }));

  const taskSteps = Object.values(metrics.taskSteps)
    .map((entry) => sanitizeObject(entry))
    .sort((left, right) =>
      asNumber(right.struggleCount, 0) - asNumber(left.struggleCount, 0) ||
      asNumber(right.interventionCount, 0) - asNumber(left.interventionCount, 0))
    .slice(0, 5)
    .map((entry) => ({
      taskStepKey: toTrimmedString(entry.taskStepKey),
      taskId: toTrimmedString(entry.taskId) || null,
      struggleCount: asNumber(entry.struggleCount, 0),
      hintCount: asNumber(entry.hintCount, 0),
      interventionCount: asNumber(entry.interventionCount, 0),
      submissionCount: asNumber(entry.submissionCount, 0),
    }));

  const teachingMoments = Object.values(metrics.teachingMoments)
    .map((entry) => sanitizeObject(entry))
    .sort((left, right) =>
      asNumber(right.confusionCount, 0) - asNumber(left.confusionCount, 0) ||
      asNumber(right.interventionCount, 0) - asNumber(left.interventionCount, 0))
    .slice(0, 5)
    .map((entry) => ({
      markerId: toTrimmedString(entry.markerId),
      label: toTrimmedString(entry.label),
      markerType: toTrimmedString(entry.markerType) || null,
      confusionCount: asNumber(entry.confusionCount, 0),
      interventionCount: asNumber(entry.interventionCount, 0),
      spotlightCount: asNumber(entry.spotlightCount, 0),
    }));

  return {
    schemaVersion: ANALYTICS_SCHEMA_VERSION,
    sessionId: metrics.sessionId,
    generatedAt: admin.firestore.Timestamp.now(),
    summary: {
      ...metrics.summary,
      modeSwitchAvgMs: metrics.latency.modeSwitch.avgMs,
      boardLagAvgMs: metrics.latency.boardEventLag.avgMs,
      thumbnailAvgMs: metrics.latency.thumbnailGeneration.avgMs,
      aiJobAvgMs: metrics.latency.aiJob.avgMs,
      sessionPackAvgMs: metrics.latency.sessionPackGeneration.avgMs,
    },
    rankings: {
      studentsNeedingMostIntervention: students,
      taskStepsWithMostStruggle: taskSteps,
      teachingMomentsWithMostConfusion: teachingMoments,
    },
    health: {
      aiFailures: metrics.summary.aiJobFailureCount + metrics.summary.aiMemoryJobFailureCount,
      aiDegraded: metrics.summary.aiJobDegradedCount + metrics.summary.aiMemoryJobDegradedCount,
      thumbnailFailures: metrics.summary.thumbnailFailureCount,
      slowModeSwitches: metrics.summary.slowModeSwitchCount,
      boardLagSpikes: metrics.summary.boardLagSpikeCount,
    },
  };
}

async function persistAnalyticsEvent(params: {
  sessionId: string;
  dedupeId: string;
  event: AnalyticsRollupEvent;
  persistEvent?: boolean;
}): Promise<void> {
  const eventRef = analyticsEventsCollection(params.sessionId).doc(params.dedupeId);
  await db.runTransaction(async (tx) => {
    const [eventSnap, metricsSnap] = await Promise.all([
      params.persistEvent !== false ? tx.get(eventRef) : Promise.resolve(null),
      tx.get(analyticsMetricsRef(params.sessionId)),
    ]);

    if (params.persistEvent !== false && eventSnap?.exists) {
      return;
    }

    const current = metricsSnap.exists ?
      metricsSnap.data() as ClassroomAnalyticsMetricsDoc :
      initialClassroomAnalyticsMetrics(params.sessionId);
    const next = applyAnalyticsEvent(current, params.event);

    tx.set(analyticsMetricsRef(params.sessionId), {
      ...next,
      updatedAt: nowServerTs(),
    }, {merge: true});
    tx.set(analyticsExportRef(params.sessionId), {
      ...buildClassroomAnalyticsExport(next),
      generatedAt: nowServerTs(),
    }, {merge: true});

    if (params.persistEvent !== false) {
      const eventDoc: ClassroomAnalyticsEventDoc = {
        eventId: params.dedupeId,
        schemaVersion: ANALYTICS_SCHEMA_VERSION,
        kind: params.event.kind,
        sourceCollection: params.event.sourceCollection,
        sourceId: params.event.sourceId,
        operation: params.event.operation ?? null,
        actorId: params.event.actorId ?? null,
        studentId: params.event.studentId ?? null,
        taskId: params.event.taskId ?? null,
        taskStepKey: params.event.taskStepKey ?? null,
        boardId: params.event.boardId ?? null,
        markerId: params.event.markerId ?? null,
        status: params.event.status ?? null,
        occurredAtMs: params.event.occurredAtMs,
        latencyMs: params.event.latencyMs ?? null,
        durationMs: params.event.durationMs ?? null,
        spotlightMode: params.event.spotlightMode ?? null,
        details: params.event.details ?? {},
        recordedAt: nowServerTs(),
      };
      tx.set(eventRef, eventDoc, {merge: false});
    }
  });
}

function eventDedupeId(prefix: string, sourceId: string, status?: string | null) {
  return `${prefix}_${sourceId}${status ? `_${status}` : ""}`;
}

function terminalAiStatus(status: string): boolean {
  return ["done", "completed", "failed", "degraded", "skipped", "error"].includes(status);
}

export const onclassroomanalyticsactionwritten = onDocumentWritten({
  document: "sessions/{sessionId}/orchestratorActions/{actionId}",
  region: REGION,
}, async (event) => {
  const sessionId = toTrimmedString(event.params?.sessionId);
  const actionId = toTrimmedString(event.params?.actionId);
  if (!sessionId || !actionId) return;

  const before = event.data?.before.data() ?? null;
  const after = event.data?.after.data() ?? null;
  if (!after) return;
  const status = toTrimmedString(after.status);
  if (status !== "COMPLETED" || toTrimmedString(before?.status) === "COMPLETED") return;

  const createdAt = asTimestamp(after.createdAt);
  const completedAt = asTimestamp(after.completedAt) ?? asTimestamp(after.updatedAt);
  const latencyMs = createdAt && completedAt ? completedAt.toMillis() - createdAt.toMillis() : null;
  const result = sanitizeObject(after.result);
  const payload = sanitizeObject(after.payload);

  await persistAnalyticsEvent({
    sessionId,
    dedupeId: eventDedupeId("action", actionId),
    event: {
      kind: "orchestrator_action",
      sourceCollection: "orchestratorActions",
      sourceId: actionId,
      operation: toTrimmedString(after.operation) || null,
      actorId: toTrimmedString(after.actorId) || null,
      studentId: toTrimmedString(result.studentId) || toTrimmedString(payload.studentId) || null,
      taskId: toTrimmedString(result.activeTaskId) || toTrimmedString(payload.taskId) || null,
      taskStepKey: toTrimmedString(payload.taskStepKey) || null,
      boardId: toTrimmedString(result.activeBoardRef) || toTrimmedString(payload.boardId) || null,
      status: "completed",
      occurredAtMs: completedAt?.toMillis() ?? Date.now(),
      latencyMs,
      spotlightMode: toTrimmedString(result.spotlightMode) || toTrimmedString(payload.spotlightMode) || null,
      details: {
        roomMode: result.roomMode ?? null,
        focusMode: result.focusMode ?? null,
        boardMode: result.boardMode ?? null,
        expectedStudentCount: result.expectedStudentCount ?? null,
        submittedStudentCount: result.submittedStudentCount ?? null,
        classLock: result.classLock ?? null,
      },
    },
  });
});

export const onclassroomanalyticsboardchunkwritten = onDocumentWritten({
  document: "sessions/{sessionId}/boardEventChunks/{chunkId}",
  region: REGION,
}, async (event) => {
  const sessionId = toTrimmedString(event.params?.sessionId);
  const chunkId = toTrimmedString(event.params?.chunkId);
  if (!sessionId || !chunkId) return;
  const before = event.data?.before.data() ?? null;
  const after = event.data?.after.data() ?? null;
  if (!after) return;
  const beforeStatus = toTrimmedString(before?.status);
  const afterStatus = toTrimmedString(after.status);
  if (beforeStatus === afterStatus) return;
  if (!["accepted", "ignored", "rejected"].includes(afterStatus)) return;

  const clientEmittedAt = asTimestamp(after.clientEmittedAt) ?? asTimestamp(after.createdAt);
  const appliedAt = asTimestamp(after.appliedAt) ?? asTimestamp(after.updatedAt);
  const lagMs = clientEmittedAt && appliedAt ? appliedAt.toMillis() - clientEmittedAt.toMillis() : null;
  const persistEvent = afterStatus !== "accepted" || (lagMs ?? 0) >= BOARD_LAG_SPIKE_MS;

  await persistAnalyticsEvent({
    sessionId,
    dedupeId: eventDedupeId("board_chunk", chunkId, afterStatus),
    persistEvent,
    event: {
      kind: "board_sync",
      sourceCollection: "boardEventChunks",
      sourceId: chunkId,
      actorId: toTrimmedString(after.writerId) || null,
      studentId: toTrimmedString(after.ownerId) || null,
      boardId: toTrimmedString(after.boardId) || null,
      status: afterStatus,
      occurredAtMs: appliedAt?.toMillis() ?? Date.now(),
      latencyMs: lagMs,
      details: {
        seqStart: asNumber(after.seqStart, 0),
        seqEnd: asNumber(after.seqEnd, 0),
        rejectionReason: toTrimmedString(after.rejectionReason) || null,
        serverOrder: asNumber(after.serverOrder, 0),
      },
    },
  });
});

export const onclassroomanalyticsthumbnailjobwritten = onDocumentWritten({
  document: "sessions/{sessionId}/thumbnailJobs/{jobId}",
  region: REGION,
}, async (event) => {
  const sessionId = toTrimmedString(event.params?.sessionId);
  const jobId = toTrimmedString(event.params?.jobId);
  if (!sessionId || !jobId) return;
  const before = event.data?.before.data() ?? null;
  const after = event.data?.after.data() ?? null;
  if (!after) return;
  const status = toTrimmedString(after.status);
  if (!["done", "error", "skipped"].includes(status) || toTrimmedString(before?.status) === status) return;
  const createdAt = asTimestamp(after.createdAt);
  const completedAt = asTimestamp(after.completedAt) ?? asTimestamp(after.updatedAt);
  const latencyMs = createdAt && completedAt ? completedAt.toMillis() - createdAt.toMillis() : null;

  await persistAnalyticsEvent({
    sessionId,
    dedupeId: eventDedupeId("thumbnail", jobId, status),
    event: {
      kind: "thumbnail_job",
      sourceCollection: "thumbnailJobs",
      sourceId: jobId,
      studentId: toTrimmedString(after.ownerId) || null,
      boardId: toTrimmedString(after.boardId) || null,
      status,
      occurredAtMs: completedAt?.toMillis() ?? Date.now(),
      latencyMs,
      details: {
        error: toTrimmedString(after.error) || null,
      },
    },
  });
});

export const onclassroomanalyticsspotlightwritten = onDocumentWritten({
  document: "sessions/{sessionId}/spotlightHistory/{auditId}",
  region: REGION,
}, async (event) => {
  const sessionId = toTrimmedString(event.params?.sessionId);
  const auditId = toTrimmedString(event.params?.auditId);
  if (!sessionId || !auditId) return;
  const before = event.data?.before.data() ?? null;
  const after = event.data?.after.data() ?? null;
  if (!after) return;
  const status = toTrimmedString(after.status);
  if (status !== "CLOSED" || toTrimmedString(before?.status) === "CLOSED") return;
  const startedAt = asTimestamp(after.startedAt);
  const endedAt = asTimestamp(after.endedAt) ?? asTimestamp(after.updatedAt);
  const durationMs = startedAt && endedAt ? Math.max(0, endedAt.toMillis() - startedAt.toMillis()) : null;

  await persistAnalyticsEvent({
    sessionId,
    dedupeId: eventDedupeId("spotlight", auditId, status),
    event: {
      kind: "spotlight",
      sourceCollection: "spotlightHistory",
      sourceId: auditId,
      actorId: toTrimmedString(after.startedBy) || null,
      studentId: toTrimmedString(after.studentId) || null,
      taskId: toTrimmedString(after.taskId) || null,
      boardId: toTrimmedString(after.boardId) || null,
      status,
      occurredAtMs: endedAt?.toMillis() ?? Date.now(),
      durationMs,
      spotlightMode: toTrimmedString(after.spotlightMode) || null,
      details: {
        reason: toTrimmedString(after.reason) || null,
        endedReason: toTrimmedString(after.endedReason) || null,
        pauseOthers: asBool(after.pauseOthers, false),
        deEmphasizeOthers: asBool(after.deEmphasizeOthers, false),
      },
    },
  });
});

export const onclassroomanalyticsinterventionwritten = onDocumentWritten({
  document: "sessions/{sessionId}/interventions/{interventionId}",
  region: REGION,
}, async (event) => {
  const sessionId = toTrimmedString(event.params?.sessionId);
  const interventionId = toTrimmedString(event.params?.interventionId);
  if (!sessionId || !interventionId) return;
  const before = event.data?.before.data() ?? null;
  const after = event.data?.after.data() ?? null;
  if (!after) return;
  const created = !before;
  const becameClosed = toTrimmedString(after.state) === "CLOSED" && toTrimmedString(before?.state) !== "CLOSED";
  if (!created && !becameClosed) return;

  const payload = sanitizeObject(after.payload);
  const type = toTrimmedString(after.type) || (toTrimmedString(after.state) === "CLOSED" ? "closed" : "focus");
  const createdAt = asTimestamp(after.createdAt) ?? asTimestamp(after.startedAt);
  const endedAt = asTimestamp(after.endedAt);
  const occurredAt = becameClosed ? endedAt?.toMillis() ?? Date.now() : createdAt?.toMillis() ?? Date.now();
  await persistAnalyticsEvent({
    sessionId,
    dedupeId: eventDedupeId("intervention", interventionId, becameClosed ? "closed" : "open"),
    event: {
      kind: "intervention",
      sourceCollection: "interventions",
      sourceId: interventionId,
      actorId: toTrimmedString(after.createdBy) || toTrimmedString(after.tutorId) || null,
      studentId: toTrimmedString(after.studentId) || null,
      taskId: toTrimmedString(after.taskId) || null,
      taskStepKey: toTrimmedString(after.taskStepKey) || toTrimmedString(payload.taskStepKey) || null,
      boardId: toTrimmedString(after.boardId) || null,
      status: type,
      occurredAtMs: occurredAt,
      details: {
        reason: toTrimmedString(after.reason) || null,
        state: toTrimmedString(after.state) || null,
        payload,
      },
    },
  });
});

export const onclassroomanalyticssubmissionwritten = onDocumentWritten({
  document: "sessions/{sessionId}/submissions/{submissionId}",
  region: REGION,
}, async (event) => {
  const sessionId = toTrimmedString(event.params?.sessionId);
  const submissionId = toTrimmedString(event.params?.submissionId);
  if (!sessionId || !submissionId) return;
  const before = event.data?.before.data() ?? null;
  const after = event.data?.after.data() ?? null;
  if (!after) return;
  const afterStatus = toTrimmedString(after.status);
  if (afterStatus !== "submitted" || toTrimmedString(before?.status) === "submitted") return;

  const stateSnap = await sessionRef(sessionId).collection("sessionState").doc("sessionState").get();
  const summary = sanitizeObject(stateSnap.data()?.submissionSummary);
  const expectedStudentCount = asNumber(summary.expectedStudentCount, 0);

  await persistAnalyticsEvent({
    sessionId,
    dedupeId: eventDedupeId("submission", submissionId, afterStatus),
    event: {
      kind: "submission",
      sourceCollection: "submissions",
      sourceId: submissionId,
      actorId: toTrimmedString(after.studentId) || null,
      studentId: toTrimmedString(after.studentId) || null,
      taskId: toTrimmedString(after.taskId) || null,
      taskStepKey: toTrimmedString(after.taskStepKey) || toTrimmedString(after.stepId) || null,
      boardId: toTrimmedString(after.boardId) || null,
      status: afterStatus,
      occurredAtMs: (asTimestamp(after.submittedAt) ?? asTimestamp(after.createdAt))?.toMillis() ?? Date.now(),
      details: {
        expectedStudentCount,
      },
    },
  });
});

export const onclassroomanalyticsparticipantwritten = onDocumentWritten({
  document: "sessions/{sessionId}/participants/{participantId}",
  region: REGION,
}, async (event) => {
  const sessionId = toTrimmedString(event.params?.sessionId);
  const participantId = toTrimmedString(event.params?.participantId);
  if (!sessionId || !participantId) return;
  const before = event.data?.before.data() ?? {};
  const after = event.data?.after.data() ?? null;
  if (!after) return;
  const role = toTrimmedString(after.role) || "student";
  const reconnectBefore = asNumber(before.reconnectCount, 0);
  const reconnectAfter = asNumber(after.reconnectCount, 0);
  if (reconnectAfter > reconnectBefore) {
    await persistAnalyticsEvent({
      sessionId,
      dedupeId: eventDedupeId("reconnect", `${participantId}_${reconnectAfter}`),
      event: {
        kind: "reconnect",
        sourceCollection: "participants",
        sourceId: participantId,
        actorId: participantId,
        studentId: role === "student" ? participantId : null,
        status: "reconnect",
        occurredAtMs: (asTimestamp(after.lastRecoveryAt) ?? asTimestamp(after.lastHeartbeatAt) ?? admin.firestore.Timestamp.now()).toMillis(),
        details: {
          role,
          reconnectCount: reconnectAfter,
        },
      },
    });
  }

  const beforeStatus = toTrimmedString(before.status);
  const afterStatus = toTrimmedString(after.status);
  if (role === "student" && afterStatus && afterStatus !== beforeStatus && ["stuck", "idle"].includes(afterStatus)) {
    await persistAnalyticsEvent({
      sessionId,
      dedupeId: eventDedupeId("student_status", `${participantId}_${afterStatus}_${hashId([asNumber(after.progress, 0), asTimestamp(after.lastSeenAt)?.toMillis() ?? 0])}`),
      event: {
        kind: "student_status",
        sourceCollection: "participants",
        sourceId: participantId,
        actorId: participantId,
        studentId: participantId,
        taskId: toTrimmedString(after.currentTaskId) || null,
        taskStepKey: toTrimmedString(after.taskStepKey) || null,
        status: afterStatus,
        occurredAtMs: (asTimestamp(after.lastSeenAt) ?? admin.firestore.Timestamp.now()).toMillis(),
        details: {
          progress: asNumber(after.progress, 0),
          role,
        },
      },
    });
  }
});

export const onclassroomanalyticsteachmarkercreated = onDocumentCreated({
  document: "sessions/{sessionId}/teachMarkers/{markerId}",
  region: REGION,
}, async (event) => {
  const snap = event.data;
  const sessionId = toTrimmedString(event.params?.sessionId);
  const markerId = toTrimmedString(event.params?.markerId);
  if (!snap || !sessionId || !markerId) return;
  const data = snap.data() ?? {};
  await persistAnalyticsEvent({
    sessionId,
    dedupeId: eventDedupeId("teach_marker", markerId),
    event: {
      kind: "teach_marker",
      sourceCollection: "teachMarkers",
      sourceId: markerId,
      actorId: toTrimmedString(data.createdBy) || null,
      studentId: toTrimmedString(data.studentId) || null,
      taskId: toTrimmedString(data.taskId) || null,
      boardId: toTrimmedString(data.boardId) || null,
      markerId,
      status: toTrimmedString(data.markerType) || null,
      occurredAtMs: (asTimestamp(data.createdAt) ?? admin.firestore.Timestamp.now()).toMillis(),
      details: {
        label: toTrimmedString(data.label) || null,
        note: toTrimmedString(data.note) || null,
        markerType: toTrimmedString(data.markerType) || null,
      },
    },
  });
});

export const onclassroomanalyticsaijobwritten = onDocumentWritten({
  document: "sessions/{sessionId}/aiJobs/{jobId}",
  region: REGION,
}, async (event) => {
  const sessionId = toTrimmedString(event.params?.sessionId);
  const jobId = toTrimmedString(event.params?.jobId);
  if (!sessionId || !jobId) return;
  const before = event.data?.before.data() ?? null;
  const after = event.data?.after.data() ?? null;
  if (!after) return;
  const status = toTrimmedString(after.status);
  if (!terminalAiStatus(status) || toTrimmedString(before?.status) === status) return;

  const createdAt = asTimestamp(after.createdAt);
  const completedAt = asTimestamp(after.completedAt) ?? asTimestamp(after.updatedAt);
  const latencyMs = createdAt && completedAt ? completedAt.toMillis() - createdAt.toMillis() : null;
  const payload = sanitizeObject(after.payload);

  await persistAnalyticsEvent({
    sessionId,
    dedupeId: eventDedupeId("ai_job", jobId, status),
    event: {
      kind: "ai_job",
      sourceCollection: "aiJobs",
      sourceId: jobId,
      operation: toTrimmedString(after.actionType) || null,
      actorId: toTrimmedString(after.createdBy) || null,
      studentId: toTrimmedString(after.createdByRole) === "student" ? toTrimmedString(after.createdBy) || null : null,
      taskId: toTrimmedString(payload.taskId) || null,
      taskStepKey: toTrimmedString(payload.taskStepKey) || null,
      status,
      occurredAtMs: completedAt?.toMillis() ?? Date.now(),
      latencyMs,
      details: {
        errorCode: toTrimmedString(after.errorCode) || null,
        outputId: toTrimmedString(after.outputId) || null,
      },
    },
  });
});

export const onclassroomanalyticsaimemoryjobwritten = onDocumentWritten({
  document: "sessions/{sessionId}/aiMemoryJobs/{jobId}",
  region: REGION,
}, async (event) => {
  const sessionId = toTrimmedString(event.params?.sessionId);
  const jobId = toTrimmedString(event.params?.jobId);
  if (!sessionId || !jobId) return;
  const before = event.data?.before.data() ?? null;
  const after = event.data?.after.data() ?? null;
  if (!after) return;
  const status = toTrimmedString(after.status);
  if (!["completed", "failed", "degraded", "skipped"].includes(status) || toTrimmedString(before?.status) === status) {
    return;
  }
  const createdAt = asTimestamp(after.createdAt);
  const completedAt = asTimestamp(after.updatedAt) ?? asTimestamp(after.createdAt);
  const latencyMs = createdAt && completedAt ? completedAt.toMillis() - createdAt.toMillis() : null;

  await persistAnalyticsEvent({
    sessionId,
    dedupeId: eventDedupeId("ai_memory_job", jobId, status),
    event: {
      kind: "ai_memory_job",
      sourceCollection: "aiMemoryJobs",
      sourceId: jobId,
      operation: toTrimmedString(after.strategy) || null,
      actorId: toTrimmedString(after.createdBy) || null,
      status,
      occurredAtMs: completedAt?.toMillis() ?? Date.now(),
      latencyMs,
      details: {
        degraded: asBool(after.degraded, false),
        lastError: toTrimmedString(after.lastError) || null,
      },
    },
  });
});

export const onclassroomanalyticssessionpackcreated = onDocumentCreated({
  document: "sessions/{sessionId}/sessionPacks/{packId}",
  region: REGION,
}, async (event) => {
  const snap = event.data;
  const sessionId = toTrimmedString(event.params?.sessionId);
  const packId = toTrimmedString(event.params?.packId);
  if (!snap || !sessionId || !packId) return;
  const data = snap.data() ?? {};
  const jobId = toTrimmedString(data.jobId);
  let latencyMs: number | null = null;
  let status = toTrimmedString(data.generationStatus) || "completed";
  if (jobId) {
    const jobSnap = await sessionRef(sessionId).collection("aiJobs").doc(jobId).get();
    const createdAt = asTimestamp(jobSnap.data()?.createdAt);
    const generatedAt = asTimestamp(data.generatedAt) ?? asTimestamp(data.createdAt);
    latencyMs = createdAt && generatedAt ? generatedAt.toMillis() - createdAt.toMillis() : null;
    const jobStatus = toTrimmedString(jobSnap.data()?.status);
    if (jobStatus === "degraded" || jobStatus === "failed") {
      status = jobStatus;
    }
  }
  await persistAnalyticsEvent({
    sessionId,
    dedupeId: eventDedupeId("session_pack", packId, status),
    event: {
      kind: "session_pack",
      sourceCollection: "sessionPacks",
      sourceId: packId,
      operation: toTrimmedString(data.sourceActionType) || "sessionPack",
      status,
      occurredAtMs: (asTimestamp(data.generatedAt) ?? asTimestamp(data.createdAt) ?? admin.firestore.Timestamp.now()).toMillis(),
      latencyMs,
      details: {
        jobId: jobId || null,
      },
    },
  });
});

export const onclassroomanalyticsreliabilityeventcreated = onDocumentCreated({
  document: "sessions/{sessionId}/reliabilityEvents/{eventId}",
  region: REGION,
}, async (event) => {
  const snap = event.data;
  const sessionId = toTrimmedString(event.params?.sessionId);
  const eventId = toTrimmedString(event.params?.eventId);
  if (!snap || !sessionId || !eventId) return;
  const data = snap.data() ?? {};
  const kind = toTrimmedString(data.kind);
  if (kind !== "transport_migration") return;
  await persistAnalyticsEvent({
    sessionId,
    dedupeId: eventDedupeId("transport_migration", eventId),
    event: {
      kind: "transport_migration",
      sourceCollection: "reliabilityEvents",
      sourceId: eventId,
      status: kind,
      occurredAtMs: (asTimestamp(data.createdAt) ?? admin.firestore.Timestamp.now()).toMillis(),
      details: sanitizeObject(data.payload),
    },
  });
});

export function buildAnalyticsAlertSuggestions(metrics: ClassroomAnalyticsMetricsDoc): string[] {
  const alerts: string[] = [];
  if (metrics.summary.aiJobFailureCount + metrics.summary.aiMemoryJobFailureCount > 0) {
    alerts.push("AI pipeline failures detected. Alert when any session records AI hard failures or sustained degraded jobs.");
  }
  if (metrics.summary.thumbnailFailureCount > 0) {
    alerts.push("Thumbnail worker failures detected. Alert when thumbnail failures exceed 3 per session or preview freshness stalls.");
  }
  if (metrics.summary.slowModeSwitchCount > 0) {
    alerts.push("Mode switching is slow. Alert when p95 mode switch latency exceeds 800ms for classroom sessions.");
  }
  if (metrics.summary.boardLagSpikeCount > 0) {
    alerts.push("Board lag spikes detected. Alert when accepted board event lag exceeds 1500ms repeatedly within one session.");
  }
  return alerts;
}

export function safeRunAnalyticsTrigger(
  label: string,
  handler: () => Promise<void>,
): Promise<void> {
  return handler().catch((error) => {
    logger.error(`Classroom analytics trigger failed: ${label}`, {error});
  });
}
