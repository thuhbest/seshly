import test from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";

async function loadParallelPracticeModule() {
  if (admin.apps.length === 0) {
    admin.initializeApp({projectId: "seshly-runtime-hardening-tests"});
  }
  return import("../parallelPracticeV2.js");
}

test("LiveKit room naming round-trips cleanly", async () => {
  const {buildLiveKitRoomName, extractSessionIdFromLiveKitRoom} = await loadParallelPracticeModule();
  const roomName = buildLiveKitRoomName("sess_123", "seshly-");
  assert.equal(roomName, "seshly-sess_123");
  assert.equal(extractSessionIdFromLiveKitRoom(roomName, "seshly-"), "sess_123");
});

test("pair member normalization is deterministic and deduplicated", async () => {
  const {normalizePairMembers} = await loadParallelPracticeModule();
  assert.deepEqual(
    normalizePairMembers(["b_user", "a_user", "b_user", "", null]),
    ["a_user", "b_user"],
  );
});

test("capacity deltas only increase counts when a participant newly joins", async () => {
  const {countDeltaForAdmission} = await loadParallelPracticeModule();
  assert.deepEqual(
    countDeltaForAdmission({
      wasJoined: false,
      wasTutor: false,
      nextJoined: true,
      nextTutor: false,
    }),
    {participantDelta: 1, tutorDelta: 0},
  );

  assert.deepEqual(
    countDeltaForAdmission({
      wasJoined: true,
      wasTutor: false,
      nextJoined: true,
      nextTutor: false,
    }),
    {participantDelta: 0, tutorDelta: 0},
  );
});

test("promoting an already joined student to tutor only bumps tutor count", async () => {
  const {countDeltaForAdmission} = await loadParallelPracticeModule();
  assert.deepEqual(
    countDeltaForAdmission({
      wasJoined: true,
      wasTutor: false,
      nextJoined: true,
      nextTutor: true,
    }),
    {participantDelta: 0, tutorDelta: 1},
  );
});

test("leaving the room decrements participant and tutor counts correctly", async () => {
  const {countDeltaForAdmission} = await loadParallelPracticeModule();
  assert.deepEqual(
    countDeltaForAdmission({
      wasJoined: true,
      wasTutor: true,
      nextJoined: false,
      nextTutor: false,
    }),
    {participantDelta: -1, tutorDelta: -1},
  );
});
