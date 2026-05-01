import test from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";

type AnalyticsMetrics = import("../classroomAnalytics.js").ClassroomAnalyticsMetricsDoc;

async function loadAnalyticsModule() {
  if (admin.apps.length === 0) {
    admin.initializeApp({projectId: "seshly-analytics-tests"});
  }
  return import("../classroomAnalytics.js");
}

function freshMetrics(
  analytics: Awaited<ReturnType<typeof loadAnalyticsModule>>,
): AnalyticsMetrics {
  return analytics.initialClassroomAnalyticsMetrics("session_1");
}

test("mode switch latency rollup marks slow transitions", async () => {
  const analytics = await loadAnalyticsModule();
  const next = analytics.applyAnalyticsEvent(
    freshMetrics(analytics),
    {
      kind: "orchestrator_action",
      sourceCollection: "orchestratorActions",
      sourceId: "action_1",
      operation: "sendClassworkToStudents",
      occurredAtMs: 1000,
      latencyMs: 1200,
      taskId: "task_1",
      details: {expectedStudentCount: 3},
    },
  );

  assert.equal(next.summary.modeSwitchCount, 1);
  assert.equal(next.summary.slowModeSwitchCount, 1);
  assert.equal(next.summary.submissionExpectedCount, 3);
  assert.equal(next.latency.modeSwitch.maxMs, 1200);
});

test("submission outcome tracks finished after hint and intervention", async () => {
  const analytics = await loadAnalyticsModule();
  let next = freshMetrics(analytics);
  next.summary.submissionExpectedCount = 2;

  next = analytics.applyAnalyticsEvent(next, {
    kind: "intervention",
    sourceCollection: "interventions",
    sourceId: "hint_1",
    studentId: "student_a",
    taskId: "task_1",
    status: "broadcastHint",
    occurredAtMs: 1_000,
  });
  next = analytics.applyAnalyticsEvent(next, {
    kind: "submission",
    sourceCollection: "submissions",
    sourceId: "submission_1",
    studentId: "student_a",
    taskId: "task_1",
    status: "submitted",
    occurredAtMs: 2_000,
  });
  next = analytics.applyAnalyticsEvent(next, {
    kind: "intervention",
    sourceCollection: "interventions",
    sourceId: "focus_1",
    studentId: "student_b",
    taskId: "task_1",
    status: "tutorIntervening",
    occurredAtMs: 3_000,
  });
  next = analytics.applyAnalyticsEvent(next, {
    kind: "submission",
    sourceCollection: "submissions",
    sourceId: "submission_2",
    studentId: "student_b",
    taskId: "task_1",
    status: "submitted",
    occurredAtMs: 4_000,
  });

  assert.equal(next.summary.studentsFinishedAfterHintCount, 1);
  assert.equal(next.summary.studentsFinishedAfterInterventionCount, 1);
  assert.equal(next.summary.submissionCount, 2);
  assert.equal(next.summary.submissionCompletionRate, 100);
});

test("teach markers accumulate confusion attribution", async () => {
  const analytics = await loadAnalyticsModule();
  let next = freshMetrics(analytics);

  next = analytics.applyAnalyticsEvent(next, {
    kind: "teach_marker",
    sourceCollection: "teachMarkers",
    sourceId: "marker_1",
    markerId: "marker_1",
    taskId: "task_1",
    boardId: "shared",
    status: "warn",
    occurredAtMs: 1_000,
    details: {
      label: "Fractions warning",
      markerType: "warn",
    },
  });
  next = analytics.applyAnalyticsEvent(next, {
    kind: "intervention",
    sourceCollection: "interventions",
    sourceId: "intervention_1",
    studentId: "student_a",
    taskId: "task_1",
    boardId: "shared",
    status: "tutorIntervening",
    occurredAtMs: 2_000,
  });

  const teachingMoment = next.teachingMoments["marker_1"] as Record<string, unknown>;
  assert.equal(teachingMoment.confusionCount, 1);
  assert.equal(teachingMoment.interventionCount, 1);
  assert.equal(next.summary.lastTeachMarkerId, "marker_1");
});

test("export ranks students and task struggle from metrics", async () => {
  const analytics = await loadAnalyticsModule();
  let next = freshMetrics(analytics);

  next = analytics.applyAnalyticsEvent(next, {
    kind: "intervention",
    sourceCollection: "interventions",
    sourceId: "i1",
    studentId: "student_a",
    taskId: "task_1",
    taskStepKey: "task_1:step_a",
    status: "tutorIntervening",
    occurredAtMs: 1_000,
  });
  next = analytics.applyAnalyticsEvent(next, {
    kind: "intervention",
    sourceCollection: "interventions",
    sourceId: "i2",
    studentId: "student_a",
    taskId: "task_1",
    taskStepKey: "task_1:step_a",
    status: "broadcastHint",
    occurredAtMs: 2_000,
  });
  next = analytics.applyAnalyticsEvent(next, {
    kind: "spotlight",
    sourceCollection: "spotlightHistory",
    sourceId: "spotlight_1",
    studentId: "student_a",
    taskId: "task_1",
    status: "CLOSED",
    occurredAtMs: 4_000,
    durationMs: 1_500,
    spotlightMode: "hard",
  });

  const exportDoc = analytics.buildClassroomAnalyticsExport(next);
  assert.equal(exportDoc.rankings.studentsNeedingMostIntervention[0].studentId, "student_a");
  assert.equal(exportDoc.rankings.taskStepsWithMostStruggle[0].taskStepKey, "task_1:step_a");
});
