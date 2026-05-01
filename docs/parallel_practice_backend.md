# Seshly Parallel Practice Architecture (Firebase + LiveKit)

## 1) Call Routing State Machine

### sessionState.callMode
- Values: `p2p` | `sfu`
- Server computes from counts:
  - `p2p` when `participantCount == 2` AND `tutorCount == 1`
  - `sfu` when `participantCount >= 3` OR `tutorCount >= 2`

### Server-side computation
- On **join/leave**, **acceptInvite**, **promoteTutor**:
  1) Recompute counts from `sessions/{sessionId}/participants`
  2) Set `participantCount`, `tutorCount`
  3) Compute `callMode`
  4) If changed: increment `callModeVersion` and emit event `call_mode_change`

### Invariants
- `callMode` is never written by clients
- `callModeVersion` increments on any callMode change

---

## 2) Automatic Migration: P2P → SFU

### Flow
1. Server updates `sessionState.callMode = sfu` and `callModeVersion++`.
2. Server emits event:
   ```json
   {"type":"call_mode_change","mode":"sfu","version":N,"createdAt":...}
   ```
3. Clients listen to session doc. On version change:
   - Tear down P2P peer connection
   - Call `/session/getCallConfig`
   - Receive LiveKit token + URL
   - Join SFU room

### Safety
- Clients **must** compare local version to remote; if mismatch, reconnect.
- P2P signaling is ignored once `callMode == sfu`.

---

## 3) Firebase Boundaries (Realtime vs Functions)

### Direct client writes (realtime-safe)
- Presence: `sessions/{sessionId}/presence/{uid}`
- Whiteboard event chunks: `sessions/{sessionId}/boards/{boardId}/chunks/{chunkId}`
- P2P signaling docs: `sessions/{sessionId}/p2pSignals/{signalId}`

### Server-authoritative writes (Cloud Functions only)
- `sessionState.mode` changes (Teach/Practice/Review)
- `callMode` updates + version increments
- `giveTask`, `startPractice`, `collectNow`
- `inviteTutor`, `acceptInvite`, `promoteTutor`
- `endSession`
- `recording start/stop`
- AI quick actions jobs

---

## 4) Whiteboard Sync Protocol

### Chunking
- Collection: `sessions/{sessionId}/boards/{boardId}/chunks/{chunkId}`
- Each chunk:
  ```json
  {"ownerId":"uid","deviceId":"...","seqStart":100,"seqEnd":140,"events":[...],"createdAt":...}
  ```

### Ordering
- Global order: `(seqStart asc, createdAt asc)` within board.
- Clients maintain local `lastSeq` per board.

### Dedupe
- Each event has `deviceId` + `seq`.
- If `(deviceId, seq)` already seen, discard.

### Conflict rules
- Last-writer-wins for **overlapping strokes**.
- Jump‑In is allowed for tutors; their events are tagged `writerRole: tutor`.
- Student board accepts both student + tutor writer roles.

### Multi-writer Jump In
- Writers = student + 1..N tutors.
- No hard lock; use event layer ordering and clear author tags.

---

## 5) Low‑FPS Thumbnails (Tutor-only)

### Cadence
- While a student is active: 1 snapshot every **3–5s**
- Idle: no snapshots

### Storage
- `sessions/{sessionId}/thumbnails/{studentId}/{timestamp}.jpg`

### Firestore index
- `sessions/{sessionId}/boardSnapshots/{snapshotId}`
  ```json
  {"studentId":"uid","url":"...","storagePath":"...","createdAt":...}
  ```

### Visibility
- Tutors read all thumbnails
- Students read only their own (optional)

### Stub mode
- If capture not available, client writes `status=idle` and leaves snapshots empty.

---

## 6) Teach Markers

### Anchor payload
```
{
  type: '✅'|'⚠️'|'⭐',
  timestampMs,
  mode: 'teach'|'practice'|'review',
  boardSnapshotId?,
  eventPointer?,
  audioPointerMs?,
  createdBy
}
```

### Linking
- `eventPointer` is `(boardId, seqStart, seqEnd)` to map the stroke range.
- If recording is active, store `audioPointerMs`.

---

## 7) Voice Notes

### Flow
1. Tutor records (10–20s)
2. Upload to Storage:
   - `sessions/{sessionId}/voiceNotes/{tutorId}/{timestamp}.m4a`
3. Register in Firestore:
   - `sessions/{sessionId}/voiceNotes/{voiceNoteId}`

### Access
- Tutors can read/write all
- Students read only those attached to them or shared globally

---

## 8) AI Jobs

### Queue
- `sessions/{sessionId}/aiJobs/{jobId}`
  ```json
  {"actionType","payload","status":"queued|processing|done","createdBy","createdAt"}
  ```

### Worker
- Firestore trigger processes jobs
- Applies cooldown per session + action type (store `lastRunAt`)
- Cache output in `aiJobs/{jobId}.result`

---

## 9) Edge Cases

### Late join in Practice
- Server assigns student role
- Client loads current task from `sessionState.activeTaskId`
- Student board is private; no cross‑visibility

### Reconnect
- Client re‑joins, compares `callModeVersion`
- If mismatched → reconfigure call mode

### Tutor disconnect
- Session continues if any tutor remains
- If primary leaves, co‑tutor remains but cannot end unless `allowCoTutorEnd=true`

### Mode switch mid-task
- Mode is authoritative
- Client must stop timers when mode != practice

---

# Firestore Schema (Implementable)

## sessions/{sessionId}
```
{
  title,
  subject,
  ownerId,
  status,
  maxParticipants,
  participantCount,
  tutorCount,
  sessionState: {
    mode,
    callMode,
    callModeVersion,
    activeTaskId,
    recording
  },
  allowCoTutorEnd,
  createdAt,
  updatedAt
}
```

## sessions/{sessionId}/participants/{userId}
```
{
  userId,
  role,
  status,
  progress,
  pinned,
  tags,
  lastActivityAt,
  lastActiveAt,
  isActive
}
```

## sessions/{sessionId}/presence/{userId}
```
{ lastSeenAt, deviceId, mode }
```

## sessions/{sessionId}/p2pSignals/{signalId}
```
{ from, to, type, payload, createdAt }
```

## sessions/{sessionId}/boards/{boardId}/chunks/{chunkId}
```
{ ownerId, deviceId, seqStart, seqEnd, events[], createdAt }
```

## sessions/{sessionId}/boardSnapshots/{snapshotId}
```
{ studentId, url, storagePath, createdAt }
```

## sessions/{sessionId}/markers/{markerId}
```
{ type, timestampMs, mode, boardSnapshotId, eventPointer, audioPointerMs, createdBy, createdAt }
```

## sessions/{sessionId}/tasks/{taskId}
```
{ prompt, attachments[], timerSec, submissionFormat, allowSeshHelp, rubric, expectedSolution, tags[], createdBy, status, createdAt }
```

## sessions/{sessionId}/submissions/{taskId_userId}
```
{ studentId, responseText, snapshotUrl, snapshotPath, status, submittedAt }
```

## sessions/{sessionId}/templates/{templateId}
```
{ title, prompt, attachments[], rubric, expectedSolution, tags[], createdBy, createdAt }
```

## sessions/{sessionId}/controlRequests/{studentId}
```
{ status, createdAt, decidedBy, decidedAt }
```

## sessions/{sessionId}/nudges/{nudgeId}
```
{ studentId, message, createdBy, createdAt }
```

## sessions/{sessionId}/voiceNotes/{voiceNoteId}
```
{ targetType, targetId, storagePath, url, durationSec, createdBy, createdAt }
```

## sessions/{sessionId}/aiJobs/{jobId}
```
{ actionType, payload, status, createdBy, createdAt, result? }
```
