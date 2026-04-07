# Classroom Reliability Architecture

## 1. Reliability architecture

### Authoritative state
Authoritative classroom state remains in `sessions/{sessionId}/sessionState/sessionState`.
A new `reliability` map is maintained server-side and contains:
- `activeParticipantCount`
- `activeTutorCount`
- `weakConnectionCount`
- `tutorPresenceState`
- `studentsMayContinue`
- `recommendedMediaProfile`
- `lastCallMode`
- `lastCallModeVersion`
- `lastCallMigrationAt`
- `tutorUnavailableAt`
- `lastReconciledAt`
- `recoveryVersion`

### Recovery contract
Clients recover through `POST /session/recoverState`.
The response includes:
- `connectionInfo`
- classroom mode/focus/board state
- current task
- timer end + server-derived remaining time
- submission state for the student
- board route and visible boards
- latest accepted server order for the current board
- current board snapshot
- tutor preview fallbacks

### Presence / disconnect handling
Clients send `POST /session/heartbeat`.
Tutor absence is projected into:
- `active`
- `practiceAutonomous`
- `pausedTutor`

Rule:
- if no tutor is live and class is in practice with an active task, students continue privately
- otherwise the room is treated as `pausedTutor`

### Media degradation
Server recommends:
- `full`
- `audio_priority`
- `board_priority`

Rule:
- weak connections -> `audio_priority`
- large SFU rooms -> `board_priority`
- otherwise `full`

## 2. Retry / backoff strategy

Client retry schedule:
- attempt 0: 1s
- attempt 1: 2s
- attempt 2: 4s
- attempt 3: 8s
- attempt 4: 12s
- attempt 5+: 20s cap

Reconnect sequence:
1. heartbeat with `presenceState=reconnecting`
2. request `recoverState`
3. rebind transport using returned `connectionInfo`
4. flush pending board chunks
5. resume live watchers

## 3. State reconciliation algorithm

On reconnect:
1. mark participant online + increment reconnect count
2. recompute call mode and reliability projection
3. compute timer from `timerEndAt - serverNow`
4. return current task and student submission state
5. return board route and board recovery cursor
6. client replays accepted board chunks after the returned server order
7. client reapplies pending local chunks with deterministic chunk ids

## 4. Event idempotency design

### Existing
- board chunks already use deterministic ids from board/writer/device/seq range
- task submission already supports idempotency keys

### Added
- reliability events use deterministic ids derived from:
  - `sessionId`
  - `kind`
  - transition signature

This prevents duplicate logs for the same migration or tutor-presence transition.

## 5. Observability / logs / metrics

### Metrics document
- `sessions/{sessionId}/reliabilityMetrics/current`

Contains:
- active counts
- weak connection count
- tutor presence state
- recommended media profile
- call mode + call mode version
- recovery version

### Event log
- `sessions/{sessionId}/reliabilityEvents/{eventId}`

Logged transitions:
- tutor presence changes
- media profile changes
- call transport migrations

## 6. Disconnect / reconnect tests

Tests cover:
- tutor absence in practice -> `practiceAutonomous`
- tutor absence in teach -> `pausedTutor`
- weak internet -> `audio_priority`
- timer recovery clamps correctly
- stale / left participants are not treated as live
- deterministic reliability event ids

## Failure behavior
- P2P -> SFU migration never resets classroom or board state because board/orchestrator state is outside transport
- thumbnail failure falls back to latest snapshot in recovery payload
- AI gateway failure degrades to fallback memory/output paths and does not block the classroom
