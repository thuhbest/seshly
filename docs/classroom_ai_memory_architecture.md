# Classroom AI Memory Architecture

## Goal
Seshly AI should behave like classroom memory, not an ad hoc chatbot.

## Capture pipeline
Raw classroom signals are normalized into `aiCaptureFrames` from:
- `sessionEvents`
- `aiMoments`
- `tasks`
- `submissions`
- `boardEventChunks`
- `teachMarkers`
- `tutorAnnotations`
- `transcriptPointers`
- `chat`
- `voiceNotes`

Each frame stores:
- `frameType`
- `actorId`
- `studentId`
- `boardId`
- `taskId`
- `importance`
- `spotlightMode`
- `payload`
- `createdAt`

## Job queue
Frames debounce into `aiMemoryJobs`.

Strategies:
- `cheap_live`: low-latency incremental memory refresh during class
- `expensive_wrap`: higher-quality wrap/continuity synthesis
- `manual_rebuild`: explicit tutor-triggered rebuild

## Snapshot
Current classroom memory lives at:
- `sessions/{sessionId}/aiMemory/current`

Top-level fields:
- `groupLessonMemory`
- `lessonSegments`
- `misconceptionClusters`
- `interventionMoments`
- `exemplarMoments`
- `studentLearningStates`
- `sessionContinuityNotes`

## Model routing
Gateway route:
- `POST /ai/classroom/memory/build`

Routing:
- `cheap_live` -> cheap model tier
- `expensive_wrap` and `manual_rebuild` -> expensive model tier

## Caching
Functions compute a `cacheKey` from strategy + recent capture frames.
If the current snapshot already matches that key and is ready, the job is skipped.

## Fallback
If the gateway is unavailable or model execution fails:
- Functions build a degraded heuristic snapshot
- snapshot status becomes `degraded`
- teaching is never blocked

## Design intent
This keeps AI passive during live teaching and useful after every major classroom moment.
It remembers flow, interventions, misconceptions, and individual student state.
