import test from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";

type BoardParticipant = import("../classroomBoards.js").BoardParticipant;
type BoardRoutingState = import("../classroomBoards.js").BoardRoutingState;
type ClassroomBoardDoc = import("../classroomBoards.js").ClassroomBoardDoc;

async function loadBoardsModule() {
  if (admin.apps.length === 0) {
    admin.initializeApp({projectId: "seshly-board-tests"});
  }
  return import("../classroomBoards.js");
}

function practiceState(overrides: Partial<BoardRoutingState> = {}): BoardRoutingState {
  return {
    roomMode: "practice",
    focusMode: "wholeClass",
    boardMode: "studentPrivateBoards",
    attentionTarget: null,
    classLock: true,
    activeBoardRef: null,
    activeTaskId: "task_1",
    orchestratorVersion: 3,
    spotlightMode: "none",
    pauseOthers: false,
    deEmphasizeOthers: false,
    observeOnly: false,
    ...overrides,
  };
}

function participants(): BoardParticipant[] {
  return [
    {id: "tutor_1", role: "primaryTutor", joinState: "joined", interventionState: "none"},
    {id: "student_a", role: "student", joinState: "joined", interventionState: "none"},
    {id: "student_b", role: "student", joinState: "joined", interventionState: "none"},
  ];
}

test("practice routing isolates student private boards and gives tutor previews", async () => {
  const {deriveBoardTopology} = await loadBoardsModule();
  const plan = deriveBoardTopology({
    state: practiceState(),
    participants: participants(),
  });

  const studentARoute = plan.routes.get("student_a");
  const studentBRoute = plan.routes.get("student_b");
  const tutorRoute = plan.routes.get("tutor_1");

  assert(studentARoute);
  assert(studentBRoute);
  assert(tutorRoute);
  assert.deepEqual(studentARoute.visibleBoardIds, ["student_student_a"]);
  assert.deepEqual(studentBRoute.visibleBoardIds, ["student_student_b"]);
  assert.deepEqual(tutorRoute.previewBoardIds.sort(), ["student_student_a", "student_student_b"]);
  assert.equal(tutorRoute.currentBoardId, "shared");
});

test("spotlight promotes target board to co-editable without leaking other routes", async () => {
  const {deriveBoardTopology} = await loadBoardsModule();
  const participantList = participants();
  participantList[1] = {
    ...participantList[1],
    interventionState: "tutorIntervening",
  };
  const plan = deriveBoardTopology({
    state: practiceState({
      focusMode: "spotlightStudent",
      attentionTarget: "student_a",
      spotlightMode: "hard",
    }),
    participants: participantList,
  });

  const targetBoard = plan.boards.get("student_student_a");
  const targetRoute = plan.routes.get("student_a");
  const otherRoute = plan.routes.get("student_b");
  const tutorRoute = plan.routes.get("tutor_1");

  assert(targetBoard);
  assert.equal(targetBoard.ownershipState, "coEditable");
  assert(targetRoute);
  assert.equal(targetRoute.currentBoardId, "student_student_a");
  assert(otherRoute);
  assert.deepEqual(otherRoute.visibleBoardIds, ["student_student_b"]);
  assert(tutorRoute);
  assert(tutorRoute.writeBoardIds.includes("student_student_a"));
});

test("soft spotlight keeps other students writable while tutor focuses target", async () => {
  const {deriveBoardTopology} = await loadBoardsModule();
  const plan = deriveBoardTopology({
    state: practiceState({
      focusMode: "spotlightStudent",
      attentionTarget: "student_a",
      spotlightMode: "soft",
    }),
    participants: participants(),
  });

  const tutorRoute = plan.routes.get("tutor_1");
  const otherRoute = plan.routes.get("student_b");

  assert(tutorRoute);
  assert.equal(tutorRoute.currentBoardId, "student_student_a");
  assert(otherRoute);
  assert.deepEqual(otherRoute.writeBoardIds, ["student_student_b"]);
  assert.equal(otherRoute.isPausedByTutor, false);
});

test("pauseOthers locks non-target students during spotlight without disconnecting them", async () => {
  const {deriveBoardTopology} = await loadBoardsModule();
  const participantList = participants();
  participantList[1] = {
    ...participantList[1],
    interventionState: "tutorIntervening",
  };
  const plan = deriveBoardTopology({
    state: practiceState({
      focusMode: "spotlightStudent",
      attentionTarget: "student_a",
      spotlightMode: "hard",
      pauseOthers: true,
      deEmphasizeOthers: true,
    }),
    participants: participantList,
  });

  const targetRoute = plan.routes.get("student_a");
  const otherRoute = plan.routes.get("student_b");

  assert(targetRoute);
  assert.deepEqual(targetRoute.writeBoardIds, ["student_student_a"]);
  assert(otherRoute);
  assert.deepEqual(otherRoute.writeBoardIds, []);
  assert.equal(otherRoute.isPausedByTutor, true);
  assert.equal(otherRoute.isDeemphasized, true);
});

test("review routing creates a class-visible review lane and no student writes", async () => {
  const {deriveBoardTopology} = await loadBoardsModule();
  const plan = deriveBoardTopology({
    state: practiceState({
      roomMode: "review",
      boardMode: "reviewBoard",
      focusMode: "wholeClass",
      attentionTarget: "student_a",
      activeBoardRef: "snap_1",
    }),
    participants: participants(),
  });

  const reviewBoard = plan.boards.get("review");
  const exemplarBoard = plan.boards.get("exemplar_snap_1");
  const studentRoute = plan.routes.get("student_a");

  assert(reviewBoard);
  assert.equal(reviewBoard.boardKind, "reviewBoard");
  assert(exemplarBoard);
  assert.equal(exemplarBoard.ownershipState, "broadcastBase");
  assert(studentRoute);
  assert.equal(studentRoute.currentBoardId, "review");
  assert.deepEqual(studentRoute.writeBoardIds, []);
  assert(studentRoute.visibleBoardIds.includes("exemplar_snap_1"));
});

test("chunk id is deterministic across retries", async () => {
  const {buildBoardChunkId} = await loadBoardsModule();
  const first = buildBoardChunkId({
    boardId: "student_student_a",
    writerId: "student_a",
    deviceId: "ipad",
    seqStart: 10,
    seqEnd: 20,
  });
  const second = buildBoardChunkId({
    boardId: "student_student_a",
    writerId: "student_a",
    deviceId: "ipad",
    seqStart: 10,
    seqEnd: 20,
  });

  assert.equal(first, second);
});

test("chunk acceptance rejects stale or unauthorized edits deterministically", async () => {
  const {
    canWriteBoard,
    evaluateChunkAcceptance,
  } = await loadBoardsModule();
  const board: ClassroomBoardDoc = {
    boardId: "shared",
    boardKind: "sharedBoard",
    ownerId: null,
    subjectStudentId: null,
    ownershipState: "tutorOwned",
    visibilityScope: "class",
    transientState: "none",
    sourceBoardId: null,
    sourceSnapshotId: null,
    previewEnabled: false,
    revisionCursor: 4,
    lastSeqByWriter: {tutor_1: 10},
    active: true,
  };

  assert.equal(canWriteBoard({board, writerId: "student_a", writerRole: "student"}), false);
  assert.deepEqual(
    evaluateChunkAcceptance({
      board,
      writerId: "tutor_1",
      writerRole: "primaryTutor",
      seqEnd: 9,
    }),
    {status: "ignored", reason: "stale_sequence"},
  );
  assert.deepEqual(
    evaluateChunkAcceptance({
      board,
      writerId: "student_a",
      writerRole: "student",
      seqEnd: 11,
    }),
    {status: "rejected", reason: "writer_not_allowed"},
  );
});
