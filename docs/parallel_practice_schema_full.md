# Parallel Practice Firestore Schema + Indexes (Full)

## Collections

### users/{userId}
```
{
  displayName: string,
  photoUrl: string,
  role: 'student'|'tutor'|'admin',
  createdAt: Timestamp,
  lastActiveAt: Timestamp
}
```

---

### sessions/{sid}
```
{
  title: string,
  subject: string,
  createdBy: string,           // primaryTutor uid
  maxParticipants: number,     // 5
  status: 'active'|'ended',
  participantCount: number,
  tutorCount: number,
  createdAt: Timestamp,
  updatedAt: Timestamp
}
```

Example:
```
{
  "title":"Calculus Study",
  "subject":"Calculus",
  "createdBy":"uid_tutor",
  "maxParticipants":5,
  "status":"active",
  "participantCount":2,
  "tutorCount":1,
  "createdAt":Timestamp,
  "updatedAt":Timestamp
}
```

---

### sessions/{sid}/participants/{uid}
```
{
  userId: string,
  role: 'primaryTutor'|'coTutor'|'student',
  joinState: 'joined'|'left'|'kicked',
  micEnabled: boolean,
  camEnabled: boolean,
  presenceState: 'online'|'offline',
  lastSeenAt: Timestamp,
  progress: number,            // 0–100
  status: 'working'|'idle'|'stuck'|'done',
  pinned: boolean
}
```

---

### sessions/{sid}/sessionState
```
{
  mode: 'teach'|'practice'|'review',
  callMode: 'p2p'|'sfu',
  callModeVersion: number,
  activeTaskId: string|null,
  timerEndAt: Timestamp|null,
  activeBoardRef: string|null, // boardId
  recordingState: {
    status: 'recording'|'stopped',
    startedAt: Timestamp,
    stoppedAt: Timestamp,
    startedBy: string
  },
  settings: {
    studentAnnotateEnabled: boolean
  }
}
```

---

### sessions/{sid}/invites/{inviteId}
```
{
  roleToGrant: 'student'|'coTutor',
  expiresAt: Timestamp,
  maxUses: number,
  usedCount: number,
  createdBy: string,
  createdAt: Timestamp
}
```

---

### sessions/{sid}/boards/{boardId}
```
{
  type: 'shared'|'private',
  ownerId: string|null,   // null for shared, student uid for private
  createdAt: Timestamp,
  updatedAt: Timestamp
}
```

---

### sessions/{sid}/boardEventChunks/{chunkId}
```
{
  boardId: string,
  ownerId: string,
  deviceId: string,
  seqStart: number,
  seqEnd: number,
  events: array,   // append-only
  createdAt: Timestamp
}
```

Chunk size note: keep ~200–500 events or < 0.8MB per chunk.

---

### sessions/{sid}/boardSnapshots/{snapshotId}
```
{
  boardId: string,
  studentId: string,
  url: string,
  storagePath: string,
  createdAt: Timestamp,
  locked: boolean
}
```

---

### sessions/{sid}/thumbnails/{boardId}
```
{
  boardId: string,
  studentId: string,
  url: string,
  storagePath: string,
  updatedAt: Timestamp
}
```

---

### sessions/{sid}/tasks/{taskId}
```
{
  prompt: string,
  attachments: string[],
  options: { allowSeshHelp: boolean },
  timerSec: number,
  rubric: string,
  expectedSolution: string,
  templateId: string|null,
  checklist: string[],
  createdBy: string,
  createdAt: Timestamp,
  status: 'active'|'archived'
}
```

---

### sessions/{sid}/submissions/{submissionId}
```
{
  taskId: string,
  studentId: string,
  responseText: string,
  snapshotRef: string,
  status: 'submitted'|'reviewed',
  createdAt: Timestamp
}
```

---

### sessions/{sid}/interventions/{id}
```
{
  type: 'nudge'|'pin'|'jumpIn',
  studentId: string,
  createdBy: string,
  payload: map,
  createdAt: Timestamp
}
```

---

### sessions/{sid}/tags/{tagId}
```
{
  studentId: string,
  taskId: string,
  tag: string,
  createdBy: string,
  createdAt: Timestamp
}
```

---

### sessions/{sid}/teachMarkers/{markerId}
```
{
  type: '✅'|'⚠️'|'⭐',
  timestampMs: number,
  boardSnapshotId: string|null,
  boardSeqRange: {start:number, end:number},
  audioPointerMs: number|null,
  createdBy: string,
  createdAt: Timestamp
}
```

---

### sessions/{sid}/voiceNotes/{noteId}
```
{
  targetType: 'snapshot'|'marker',
  targetId: string,
  storagePath: string,
  url: string,
  durationSec: number,
  createdBy: string,
  createdAt: Timestamp
}
```

---

### sessions/{sid}/chat/{messageId}
```
{
  senderId: string,
  text: string,
  createdAt: Timestamp
}
```

---

### sessions/{sid}/aiJobs/{jobId}
```
{
  actionType: string,
  payload: map,
  status: 'queued'|'processing'|'done',
  createdBy: string,
  createdAt: Timestamp
}
```

### sessions/{sid}/aiOutputs/{outputId}
```
{
  jobId: string,
  result: map,
  createdAt: Timestamp
}
```

### sessions/{sid}/sessionPacks/{packId}
```
{
  type: 'group'|'student',
  studentId: string|null,
  pdfUrl: string,
  notesRef: string,
  createdAt: Timestamp
}
```

### sessions/{sid}/heatmap/{heatId}
```
{
  data: map,
  createdAt: Timestamp
}
```

---

### templates/{tutorUid}/items/{templateId}
```
{
  title: string,
  task: string,
  rubric: string,
  expectedSolution: string,
  tags: string[],
  checklist: string[],
  createdAt: Timestamp
}
```

---

### P2P signaling (P2P only)
`/sessions/{sid}/webrtcSignaling/{pairId}`
```
{
  offer: map,
  answer: map,
  updatedAt: Timestamp
}
```

`/sessions/{sid}/webrtcSignaling/{pairId}/iceCandidates/{candidateId}`
```
{ from, candidate, sdpMid, sdpMLineIndex, createdAt }
```

---

## Composite Indexes

- sessions: participantCount, status, updatedAt
- participants: status + lastActivityAt
- boardSnapshots: studentId + createdAt
- submissions: taskId + createdAt
- aiJobs: status + createdAt
- webrtcSignaling: updatedAt

---

## Notes on Limits
- **Chunk size**: keep <0.8MB; ideal 200–500 events per chunk.
- **Snapshots**: keep 1 per 3–5s while active (tutor view).
- **Thumbnails**: last snapshot per board only.

