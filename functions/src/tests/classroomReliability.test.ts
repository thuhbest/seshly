import test from "node:test";
import assert from "node:assert/strict";

import {
  buildReliabilityEventId,
  calculateTimerRemainingMs,
  deriveRecommendedMediaProfile,
  deriveTutorPresenceState,
  participantIsLive,
  projectReliability,
} from "../classroomReliability.js";

test("practice continues autonomously when no tutor is live", () => {
  assert.equal(
    deriveTutorPresenceState({
      activeTutorCount: 0,
      roomMode: "practice",
      activeTaskId: "task_1",
    }),
    "practiceAutonomous",
  );
});

test("teach mode pauses when no tutor is live", () => {
  assert.equal(
    deriveTutorPresenceState({
      activeTutorCount: 0,
      roomMode: "teach",
      activeTaskId: null,
    }),
    "pausedTutor",
  );
});

test("weak connectivity degrades media profile to audio priority", () => {
  assert.equal(
    deriveRecommendedMediaProfile({
      callMode: "sfu",
      activeParticipantCount: 4,
      weakConnectionCount: 1,
      tutorPresenceState: "active",
    }),
    "audio_priority",
  );
});

test("timer remaining is clamped to zero", () => {
  assert.equal(calculateTimerRemainingMs(1_000, 2_500), 0);
});

test("live presence uses heartbeat freshness and ignores left participants", () => {
  assert.equal(
    participantIsLive({
      id: "student_1",
      role: "student",
      joinState: "joined",
      presenceState: "online",
      networkQuality: "fair",
      mediaHealth: "stable",
      lastSeenAt: null,
      lastHeartbeatAt: null,
    }, 10_000),
    true,
  );

  assert.equal(
    participantIsLive({
      id: "student_1",
      role: "student",
      joinState: "left",
      presenceState: "online",
      networkQuality: "fair",
      mediaHealth: "stable",
      lastSeenAt: null,
      lastHeartbeatAt: null,
    }, 10_000),
    false,
  );
});

test("projectReliability keeps practice alive but flags tutor absence", () => {
  const now = Date.now();
  const timestamp = {
    toMillis: () => now,
  };

  const projection = projectReliability({
    participants: [
      {
        id: "student_1",
        role: "student",
        joinState: "joined",
        presenceState: "online",
        networkQuality: "weak",
        mediaHealth: "stable",
        lastSeenAt: timestamp as never,
        lastHeartbeatAt: timestamp as never,
      },
    ],
    roomMode: "practice",
    callMode: "p2p",
    activeTaskId: "task_1",
    referenceMs: now,
  });

  assert.equal(projection.tutorPresenceState, "practiceAutonomous");
  assert.equal(projection.studentsMayContinue, true);
  assert.equal(projection.recommendedMediaProfile, "audio_priority");
});

test("reliability event ids are deterministic", () => {
  const a = buildReliabilityEventId({
    sessionId: "sess_1",
    kind: "transport_migration",
    signature: "1->2",
  });
  const b = buildReliabilityEventId({
    sessionId: "sess_1",
    kind: "transport_migration",
    signature: "1->2",
  });
  assert.equal(a, b);
});
