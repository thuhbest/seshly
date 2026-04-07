# Classroom Orchestrator

The Classroom Orchestrator is the authoritative control plane for Seshly tutoring sessions.

## Authoritative State
- Firestore root: `sessions/{sessionId}/sessionState/sessionState`
- Authority fields:
  - `roomMode`: `teach | practice | review`
  - `focusMode`: `wholeClass | spotlightStudent | tutorPrivateReview`
  - `boardMode`: `sharedBoard | studentPrivateBoards | reviewBoard`
  - `attentionTarget`: `null | studentId`
  - `classLock`: whether students can annotate the shared board
  - `activeTaskId`
  - `timerEndAt`
  - `activeBoardRef`
  - `activeInterventionId`
  - `callMode`: `p2p | sfu`
  - `submissionSummary`
  - `returnContext`
  - `orchestratorVersion`

## Auditable Action Log
- Idempotent command log: `sessions/{sessionId}/orchestratorActions/{actionId}`
- Event stream: `sessions/{sessionId}/sessionEvents/{actionId}_{index}`

## Participant Projection
- `sessions/{sessionId}/participants/{participantId}` receives orchestrated projection fields:
  - `classroomFocusState`
  - `visibilityState`
  - `interventionState`
  - `currentTaskId`
  - `pinned`
  - `lastOrchestratedAt`

## State Machines
### Session Lifecycle
- `teach -> practice -> review -> ended`
- `teach` can transition directly to `review`
- `practice` can transition to `spotlightStudent` via `focusMode`
- `review` can transition back to class with `returnContext`

### Mode Lifecycle
- `roomMode`
  - `teach`: tutor-led shared board
  - `practice`: student private boards with tutor monitoring
  - `review`: collected work and marking flow
- `focusMode`
  - `wholeClass`: default class state
  - `spotlightStudent`: tutor isolates one student without losing class state
  - `tutorPrivateReview`: tutor prepares review/marking state before presentation

### Board Ownership
- `sharedBoard`
  - tutor teaches on the class board
- `studentPrivateBoards`
  - students work privately while tutor monitors
- `reviewBoard`
  - tutor brings selected work to class, marks, and explains

### Participant Focus
- tutor states:
  - `inClass`
  - `monitoringGrid`
  - `presentingReview`
- student states:
  - `inClass`
  - `privateWork`
  - `underIntervention`
  - `presentingToClass`
  - `inReview`

## Determinism And Recovery
- All orchestrator mutations are transaction-backed.
- Every action can be retried with the same `actionId`.
- Topology reconciliation recomputes `callMode` when participant membership changes.
- Submission reconciliation recomputes `submissionSummary` when submissions change.
- Reconnecting clients resubscribe to:
  - authoritative state doc
  - participant projection
  - event stream

## Classroom Operations
- Teach all
- Send classwork to students
- Monitor everyone quietly
- Focus on one student
- Return to class
- Bring one student board to class
- Mark and send corrections
- End session with structured AI outputs
