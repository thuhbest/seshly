# Classroom Analytics Observability

## Goal
This subsystem is not product-marketing analytics. It exists to diagnose classroom execution quality:

- room mode switching lag
- board sync lag and write failures
- spotlight and intervention effectiveness
- submission friction
- reconnect and weak-network behavior
- AI and session-pack pipeline failures

## Firestore Schema
Under `sessions/{sessionId}`:

- `analyticsEvents/{eventId}`
  - append-only auditable analytics events for important transitions, failures, spikes, and session intelligence markers
- `analyticsMetrics/current`
  - lightweight dashboard-ready rollup doc
- `analyticsExports/current`
  - sorted export contract for dashboards, admin views, and external ETL

## Event Sources
- `orchestratorActions`
  - mode switch latency
  - task launch and task collection summary
- `boardEventChunks`
  - accepted/rejected/ignored write counts
  - board lag from `clientEmittedAt -> appliedAt`
- `thumbnailJobs`
  - thumbnail generation latency and failures
- `spotlightHistory`
  - spotlight duration and spotlight mode
- `interventions`
  - nudges, corrections, tutor intervention frequency
- `submissions`
  - completion rate
  - finished after hint vs finished after intervention
- `participants`
  - reconnect count
  - student idle/stuck signals when clients write `status = idle|stuck`
- `teachMarkers`
  - teaching moments and later confusion attribution
- `aiJobs`
  - AI action success / degraded / failure
- `aiMemoryJobs`
  - classroom memory pipeline health
- `sessionPacks`
  - session pack generation latency
- `reliabilityEvents`
  - transport migration observability

## Dashboard Model
`analyticsMetrics/current` keeps:

- summary counters
- latency rollups with bucketed distributions
- per-student intervention and reconnect summaries
- per-taREMOVEDstep struggle summaries
- per-teaching-moment confusion summaries
- context maps used to infer:
  - finished after hint
  - finished after tutor intervention
  - stuck-signal confirmation / false-positive rate

## Export Contract
`analyticsExports/current` contains:

- summary
- `studentsNeedingMostIntervention`
- `taskStepsWithMostStruggle`
- `teachingMomentsWithMostConfusion`
- health counters for alerting

## Failure Alerting Suggestions
- Alert when any session records AI hard failures or repeated degraded jobs
- Alert when thumbnail failures exceed 3 in one session
- Alert when mode-switch p95 exceeds 800ms
- Alert when board lag spikes exceed 1500ms repeatedly in one session
- Alert when session pack generation exceeds 8s or fails

## Notes
- High-volume board writes are mostly aggregated into metrics. Detailed event docs are only persisted for rejected writes, ignored writes, or lag spikes.
- This keeps the dashboard cheap while still preserving debuggability where it matters.
