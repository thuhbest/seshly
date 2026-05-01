# GODMODE Classroom Architecture

## Purpose
Seshly tutoring must feel like a tutor-led classroom, not a meeting tool with tutoring features added later.

The target experience is:
- tutor teaches from a shared class surface
- tutor releases task work
- students move into private workspaces
- tutor monitors all students at once
- tutor jumps into one student instantly
- tutor brings selected work back to the class
- tutor explains, marks, and closes the loop
- AI remembers what happened and carries continuity into the next session

## Current System Audit

### What already exists and should be preserved
- hard participant cap of 5
- multi-tutor support through `primaryTutor` and `coTutor`
- cost-aware media routing:
  - 1 tutor + 1 student -> P2P WebRTC
  - 3+ participants or 2+ tutors -> LiveKit SFU
- mode model:
  - `teach`
  - `practice`
  - `review`
- board/event chunking
- board snapshots
- AI jobs, outputs, session pack generation
- review concepts:
  - tagging
  - exemplars
  - corrections
- recording and timestamp surfaces

### Current architecture weaknesses
1. There are two session systems.
   - Commercial/live billing session lifecycle lives in `tutoring_sessions`.
   - Classroom orchestration lives in `sessions`.
   - This split creates lifecycle drift, duplicate room logic, and weak authority boundaries.

2. The classroom state model is too shallow.
   - `mode`, `activeTaskId`, `timerEndAt`, and `activeBoardRef` are useful, but they are not enough to model interventions, presentation source, student focus, or review queues.

3. The client is still partially demo-state.
   - `StudentGrid`, `SharedBoard`, `StudentPracticeView`, `ReviewComparisonTool`, and several tutor tools are still placeholder or dummy-data driven.
   - The UI language is classroom-shaped, but the state binding is not yet classroom-grade.

4. Media authority is not orchestrated as a classroom authority system.
   - Routing exists, but there is no formal room-control plane for who is presenting, who is isolated, who is observed, who is muted, and what board the class is looking at.

5. Intervention is modeled as an event, not as a first-class room state.
   - `interventions` exists, but there is no authoritative intervention session state that guarantees consistent tutor/student behavior across media, board, and AI capture.

6. Board ownership is too loose.
   - Boards, snapshots, and `activeBoardRef` exist, but there is no canonical board registry with explicit board type, owner, presentation visibility, intervention lock, and review state.

7. Review is command-based, not pipeline-based.
   - `collectNow`, `showToGroup`, `markExemplar`, `sendCorrection`, and `review/tag` exist, but there is no review queue that turns private work into structured classroom review.

8. AI is job-driven, but not memory-driven.
   - The stack can enqueue actions and generate session packs, but AI is not yet organized around moments, interventions, misconceptions, and per-student continuity.

9. The router has a room identity risk.
   - LiveKit room creation uses a prefixed room name while token grants and client usage use the raw session id in different places.
   - That must be normalized.

10. There is no warm transport handoff contract.
   - Switching from P2P to SFU appears functional, but there is no explicit overlap/handoff protocol to keep the room feeling seamless.

## GODMODE Target Architecture

### Core principle
Treat each class as a single authoritative `ClassroomSession` with linked subsystems, not as a call plus optional tools.

The commercial tutoring session can remain as the payment root, but the live classroom must have one canonical runtime aggregate.

### Canonical root
- `tutoring_sessions/{sessionId}` remains the commercial and runtime root
- `classroomRuntime/{sessionId}` becomes the authoritative classroom state root
- Existing `sessions/{sessionId}` classroom data should be migrated or mirrored into this runtime model

Minimum linkage:
- `tutoring_sessions/{sessionId}`
  - payment, authorization, metering, booking, settlement
- `classroomRuntime/{sessionId}`
  - mode, media topology, focus, boards, tasks, review queues, AI memory, observability

This keeps billing stable while making the classroom layer coherent.

## Subsystem boundaries

### 1. Media Layer
Responsibility:
- participant presence
- audio/video transport
- P2P vs SFU routing
- mute/camera/screen share state
- room join and room end
- force-end on insufficient funds

Inputs:
- participant join/leave
- topology policy
- tutor room control actions

Outputs:
- media state
- participant media health
- room events

Rules:
- transport selection is derived from runtime participant shape
- media layer does not decide teaching mode
- media layer obeys orchestration

### 2. Board Layer
Responsibility:
- shared tutor board
- private student boards
- board snapshots
- board event streams
- board presentation target
- intervention locks

Board types:
- `shared_class_board`
- `student_private_board`
- `review_snapshot`
- `correction_overlay`

Rules:
- every board has explicit owner, visibility, and state
- only one board is class-presented at a time
- intervention never changes ownership, only focus and edit authority

### 3. Orchestration Layer
Responsibility:
- classroom mode lifecycle
- participant focus lifecycle
- task release and timing
- intervention lifecycle
- classroom authority decisions
- transport handoff decisions

This is the real classroom brain.

### 4. AI Capture Layer
Responsibility:
- timestamp important moments
- capture board context
- capture misconceptions
- generate session memory
- generate per-student notes and corrections
- build continuity across sessions

AI should attach to moments, not just files.

### 5. Review / Assessment Layer
Responsibility:
- submissions
- collect-now snapshots
- misconception tagging
- exemplar promotion
- corrections
- review queue
- session wrap outputs

### 6. Observability Layer
Responsibility:
- participant health
- routing switches
- board lag
- AI job latency
- intervention duration
- submission coverage
- session-level classroom quality metrics

## Runtime data model

### Classroom runtime root
`classroomRuntime/{sessionId}`

Fields:
- `status`
  - `PREPARING`
  - `WAITING_FOR_PARTICIPANTS`
  - `LIVE`
  - `LOW_FUNDS`
  - `ENDING`
  - `ENDED`
- `mode`
  - `TEACH`
  - `PRACTICE`
  - `REVIEW`
- `phase`
  - `WARMUP`
  - `INSTRUCTION`
  - `TASK_ACTIVE`
  - `MONITORING`
  - `INTERVENTION`
  - `GROUP_REVIEW`
  - `WRAP`
- `topology`
  - `P2P`
  - `SFU`
- `topologyVersion: number`
- `presentedBoardId: string | null`
- `presentedBoardType: string | null`
- `activeTaskId: string | null`
- `activeReviewSetId: string | null`
- `activeInterventionId: string | null`
- `currentPresenterUserId: string | null`
- `teacherControlState`
  - `studentAnnotateEnabled: boolean`
  - `forceFocusStudentId: string | null`
  - `classMuted: boolean`
- `timers`
  - `taskEndsAt`
  - `reviewStartedAt`
- `createdAt`
- `updatedAt`

### Participants
`classroomRuntime/{sessionId}/participants/{userId}`

Fields:
- `role`
  - `PRIMARY_TUTOR`
  - `CO_TUTOR`
  - `STUDENT`
- `presenceState`
  - `JOINING`
  - `ONLINE`
  - `RECONNECTING`
  - `LEFT`
- `focusState`
  - `IN_CLASS`
  - `PRIVATE_WORK`
  - `UNDER_INTERVENTION`
  - `PRESENTING_TO_CLASS`
  - `IN_REVIEW`
- `mediaState`
  - `audioEnabled`
  - `videoEnabled`
  - `handRaised`
  - `networkQuality`
- `workState`
  - `status`
    - `WATCHING`
    - `WORKING`
    - `STUCK`
    - `SUBMITTED`
    - `DONE`
  - `progress: number`
  - `lastBoardEventAt`
  - `lastSubmissionAt`
- `currentBoardId`
- `currentTaskId`
- `joinedAt`
- `lastSeenAt`

### Boards
`classroomRuntime/{sessionId}/boards/{boardId}`

Fields:
- `boardType`
  - `SHARED_CLASS`
  - `STUDENT_PRIVATE`
  - `REVIEW_SNAPSHOT`
  - `CORRECTION`
- `ownerUserId: string | null`
- `sourceSnapshotId: string | null`
- `visibility`
  - `PRIVATE`
  - `TUTORS_ONLY`
  - `CLASS_PRESENTED`
- `editAuthority`
  - `PRIMARY_TUTOR`
  - `TUTORS`
  - `OWNER_ONLY`
  - `LOCKED`
- `interventionLock`
  - `lockedByTutorId: string | null`
  - `studentId: string | null`
  - `startedAt`
- `reviewState`
  - `NONE`
  - `QUEUED`
  - `PRESENTED`
  - `MARKED`
  - `EXEMPLAR`
- `createdAt`
- `updatedAt`

### Tasks
`classroomRuntime/{sessionId}/tasks/{taskId}`

Fields:
- `prompt`
- `attachments`
- `rubric`
- `submissionFormat`
- `allowSeshHelp`
- `timerSec`
- `state`
  - `DRAFT`
  - `LIVE`
  - `COLLECTING`
  - `REVIEWING`
  - `CLOSED`
- `createdBy`
- `createdAt`

### Review sets
`classroomRuntime/{sessionId}/reviewSets/{reviewSetId}`

Fields:
- `taskId`
- `snapshotIds`
- `studentIds`
- `queueOrder`
- `selectedSnapshotId`
- `state`
  - `OPEN`
  - `PRESENTING`
  - `COMPLETED`
- `createdBy`
- `createdAt`

### Interventions
`classroomRuntime/{sessionId}/interventions/{interventionId}`

Fields:
- `studentId`
- `tutorId`
- `boardId`
- `reason`
  - `STUCK`
  - `HELP_REQUEST`
  - `LOW_PROGRESS`
  - `QUALITY_CHECK`
  - `MANUAL`
- `state`
  - `REQUESTED`
  - `ACTIVE`
  - `RETURNING`
  - `CLOSED`
- `startedAt`
- `endedAt`
- `summaryRef`

### AI memory
`classroomRuntime/{sessionId}/aiMoments/{momentId}`

Fields:
- `momentType`
  - `EXPLANATION`
  - `TASK_RELEASE`
  - `MISCONCEPTION`
  - `INTERVENTION`
  - `EXEMPLAR`
  - `WRAP_SUMMARY`
- `scope`
  - `CLASS`
  - `STUDENT`
- `studentId: string | null`
- `relatedBoardId: string | null`
- `relatedTaskId: string | null`
- `relatedInterventionId: string | null`
- `timestampMs`
- `summary`
- `actionableCorrection`
- `tags`

## State machines

### 1. Session lifecycle
- `PREPARING`
  - booking confirmed
  - payment valid
  - room not yet live
- `WAITING_FOR_PARTICIPANTS`
  - one or more participants connected
  - media room can be prepared
- `LIVE`
  - both core parties joined
  - classroom runtime active
- `LOW_FUNDS`
  - session still live but under payment risk
- `ENDING`
  - tutor or system initiated end
  - captures, room close, AI wrap
- `ENDED`
  - final settlement and review prompts written

Allowed transitions:
- `PREPARING -> WAITING_FOR_PARTICIPANTS`
- `WAITING_FOR_PARTICIPANTS -> LIVE`
- `LIVE -> LOW_FUNDS`
- `LOW_FUNDS -> LIVE`
- `LIVE -> ENDING`
- `LOW_FUNDS -> ENDING`
- `ENDING -> ENDED`

Hard rule:
- classroom runtime cannot be `LIVE` unless commercial authorization is valid

### 2. Mode lifecycle
- `TEACH`
  - tutor-led explanation
  - shared board presented
- `PRACTICE`
  - private work active
  - task live
- `REVIEW`
  - collected work under group analysis

Phase machine inside modes:
- `TEACH/INSTRUCTION`
- `PRACTICE/TASK_ACTIVE`
- `PRACTICE/MONITORING`
- `PRACTICE/INTERVENTION`
- `REVIEW/GROUP_REVIEW`
- `REVIEW/WRAP`

Rule:
- `INTERVENTION` is a phase, not a separate top-level mode

### 3. Board ownership lifecycle
For shared class board:
- `SHARED_CLASS`
  - owner = primary tutor
  - visibility = `CLASS_PRESENTED`
  - edit authority = `TUTORS`

For student private board:
- `STUDENT_PRIVATE`
  - owner = student
  - visibility = `PRIVATE`
  - edit authority = `OWNER_ONLY`

During intervention:
- same board remains `STUDENT_PRIVATE`
- visibility becomes `TUTORS_ONLY`
- edit authority becomes `TUTORS` or `PRIMARY_TUTOR`
- intervention lock is set

During group review:
- snapshot or board clone becomes `REVIEW_SNAPSHOT`
- visibility = `CLASS_PRESENTED`
- original private board stays private

### 4. Participant focus lifecycle
Student:
- `IN_CLASS`
- `PRIVATE_WORK`
- `UNDER_INTERVENTION`
- `PRESENTING_TO_CLASS`
- `IN_REVIEW`

Tutor:
- `IN_CLASS`
- `MONITORING_GRID`
- `IN_INTERVENTION`
- `PRESENTING_REVIEW`

Transitions:
- `IN_CLASS -> PRIVATE_WORK` when task starts
- `PRIVATE_WORK -> UNDER_INTERVENTION` when tutor jumps in
- `UNDER_INTERVENTION -> PRIVATE_WORK` when tutor exits
- `PRIVATE_WORK -> PRESENTING_TO_CLASS` when selected for exemplar or review
- `PRESENTING_TO_CLASS -> IN_CLASS` after review return

## GODMODE behavior design

### Tutor authority model
Tutors must have instant room authority:
- force mode switch
- release task
- extend timer
- spotlight a board
- lock into intervention
- return to class
- promote exemplar
- issue correction
- end room

The tutor does not navigate through unrelated meeting controls.
The system should expose classroom verbs, not generic call verbs.

### Seamless class-to-student intervention
Intervention should be a controlled overlay, not a second session.

Flow:
1. Tutor in `PRACTICE/MONITORING`
2. Tutor taps student tile
3. Orchestrator opens intervention:
   - student focus -> `UNDER_INTERVENTION`
   - tutor focus -> `IN_INTERVENTION`
   - board lock set
   - AI starts intervention moment
4. Tutor annotates, nudges, or voice-corrects
5. Tutor exits intervention
6. Student returns to `PRIVATE_WORK`
7. AI records targeted correction and confidence note

### Monitoring flow
The practice grid should be state-rich:
- live board thumbnail
- progress
- stuck/help state
- AI risk signal
- tutor present indicator
- submission state

This is the tutor cockpit.

### Review flow
`collectNow` should create a structured review set:
- gather latest private board states
- create review queue
- allow tutor sort:
  - common error
  - exemplar
  - struggling student
- promote chosen board into class presentation
- attach review tags and AI notes

### AI as classroom memory
AI should not only summarize at the end.
It should maintain:
- class misconceptions
- who got stuck where
- what the tutor emphasized
- what corrections each student needs
- what should be revisited next session

Outputs:
- class summary
- per-student correction sheet
- misconception heatmap
- next-session continuation brief
- tutor memory card for future classes

## Production upgrades required

### Highest priority
1. Unify the session model.
   - Make the paid tutoring session and classroom runtime explicitly linked.
   - Stop treating `sessions` and `tutoring_sessions` as unrelated worlds.

2. Introduce a real orchestration service.
   - One server-side authority should own:
     - mode
     - phase
     - topology
     - presented board
     - active intervention
     - active task
     - review queue

3. Create a canonical board registry.
   - Boards must be first-class entities with type, owner, visibility, and edit authority.

4. Replace event-only intervention with intervention state.
   - Interventions need start, active, and end semantics.

5. Normalize LiveKit room identity.
   - Room creation, token grant, and client join must use the same room id.

6. Add transport handoff protocol.
   - P2P -> SFU migration should be warm:
     - pre-create SFU room
     - mint token before cutover
     - overlap transport briefly
     - then drop P2P

### Medium priority
7. Make AI moment-based.
   - Persist structured teaching moments rather than only raw jobs and outputs.

8. Turn review into a queue pipeline.
   - Review should be a set with ordering, selection, and resolution state.

9. Add participant health telemetry.
   - RTT, packet loss, reconnect count, board lag, AI job delay

10. Move placeholder client widgets onto live Firestore/runtime state.
   - `StudentGrid`
   - `SharedBoard`
   - `StudentPracticeView`
   - `ReviewComparisonTool`
   - `SeshAIPanel`

### Optional UI changes
These improve feel, but the architecture does not depend on them:
- add a tutor command bar with verbs:
  - `Teach`
  - `Give Task`
  - `Monitor`
  - `Jump In`
  - `Show to Class`
  - `Mark`
  - `Wrap`
- add a student status strip in practice
- add a review queue tray
- add intervention breadcrumb:
  - `Classroom > Sarah > Private Board`

## Implementation plan

### Phase 1: Structural unification
- link `tutoring_sessions/{sessionId}` and classroom runtime
- create `classroomRuntime/{sessionId}`
- introduce server-side orchestration service
- normalize room identity

### Phase 2: Board and focus authority
- add canonical boards collection
- add participant focus states
- add intervention state model
- migrate `activeBoardRef` into presented board contract

### Phase 3: Review pipeline
- add review sets
- upgrade collect/show/exemplar/correction flow
- persist queue state and tutor review decisions

### Phase 4: AI memory
- add `aiMoments`
- capture explanation, misconception, intervention, exemplar, wrap
- generate per-student continuity records

### Phase 5: Client hardening
- replace placeholder widgets with runtime-bound widgets
- add warm handoff UX
- add observability surfaces for tutors and operators

## Non-negotiable product rules
- tutor remains the authority of the room
- student private work is preserved until intentionally promoted
- interventions are temporary overlays, not separate rooms
- review is structured, not ad hoc
- AI remembers the class and the student, not just the file
- routing logic remains cost-aware but invisible to the user
- classroom behavior must stay stable at 5 participants max
