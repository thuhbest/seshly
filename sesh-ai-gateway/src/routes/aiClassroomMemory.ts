import { Router } from 'express';

import { callTextModel } from '../services/modelRouter';
import { config } from '../utils/env';

type ClassroomMemoryStrategy = 'cheap_live' | 'expensive_wrap' | 'manual_rebuild';
type FrameRecord = {
  frameId: string;
  frameType?: string;
  studentId?: string | null;
  boardId?: string | null;
  taskId?: string | null;
  importance?: string | null;
  spotlightMode?: string | null;
  payload?: Record<string, unknown>;
};

type ParticipantRecord = {
  userId: string;
  role: string;
  displayName?: string | null;
};

type MemoryRequest = {
  sessionId?: string;
  strategy?: ClassroomMemoryStrategy;
  cacheKey?: string;
  frames?: FrameRecord[];
  participants?: ParticipantRecord[];
  priorSnapshot?: Record<string, unknown>;
};

type GroupLessonMemory = {
  whatWasTaught: string[];
  keyMisconceptions: string[];
  importantExamples: string[];
  reteachMoments: string[];
};

type LessonSegment = {
  label: string;
  summary: string;
  startedAt?: string | null;
  endedAt?: string | null;
  markerType?: string | null;
};

type MisconceptionCluster = {
  title: string;
  misconception: string;
  evidence: string[];
  reteachAction: string;
};

type InterventionMoment = {
  studentId: string | null;
  title: string;
  summary: string;
  tutorAction: string;
  followUp: string;
};

type ExemplarMoment = {
  studentId: string | null;
  title: string;
  whyItMatters: string;
  boardId?: string | null;
};

type StudentLearningState = {
  approach: string[];
  mistakes: string[];
  corrections: string[];
  stuckPoints: string[];
  nextFocusArea: string[];
};

type SessionContinuityNotes = {
  nextTutorShouldKnow: string[];
  reviseNextTime: string[];
  carryForwardTasks: string[];
  atRiskStudentIds: string[];
};

type MemoryResponse = {
  status: 'ready' | 'degraded' | 'processing';
  modelTier: 'cheap' | 'expensive' | 'fallback';
  provider: string;
  model: string;
  groupLessonMemory: GroupLessonMemory;
  lessonSegments: LessonSegment[];
  misconceptionClusters: MisconceptionCluster[];
  interventionMoments: InterventionMoment[];
  exemplarMoments: ExemplarMoment[];
  studentLearningStates: Record<string, StudentLearningState>;
  sessionContinuityNotes: SessionContinuityNotes;
};

const router = Router();

function trim(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

function safeObject(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function asArray<T>(value: unknown): T[] {
  return Array.isArray(value) ? (value as T[]) : [];
}

function strings(value: unknown, limit = 8): string[] {
  return asArray<unknown>(value)
    .map((item) => String(item).trim())
    .filter((item) => item.length > 0)
    .slice(0, limit);
}

function frameToLine(frame: FrameRecord): string {
  const payload = safeObject(frame.payload);
  const parts = [
    `type=${trim(frame.frameType) || 'unknown'}`,
    frame.studentId ? `student=${trim(frame.studentId)}` : '',
    frame.boardId ? `board=${trim(frame.boardId)}` : '',
    frame.taskId ? `task=${trim(frame.taskId)}` : '',
    frame.importance ? `importance=${trim(frame.importance)}` : '',
    frame.spotlightMode ? `spotlight=${trim(frame.spotlightMode)}` : '',
    trim(payload.markerType) ? `marker=${trim(payload.markerType)}` : '',
    trim(payload.label) ? `label=${trim(payload.label)}` : '',
    trim(payload.note) ? `note=${trim(payload.note)}` : '',
    trim(payload.summary) ? `summary=${trim(payload.summary)}` : '',
    trim(payload.responseText) ? `submission=${trim(payload.responseText)}` : '',
    trim(payload.annotationText) ? `annotation=${trim(payload.annotationText)}` : '',
    trim(payload.message) ? `message=${trim(payload.message)}` : '',
  ].filter(Boolean);
  return parts.join(' | ').slice(0, 420);
}

function buildPrompt(body: MemoryRequest): string {
  const participants = asArray<ParticipantRecord>(body.participants)
    .map((participant) => {
      const name = trim(participant.displayName) || participant.userId;
      return `${name} (${trim(participant.role) || 'student'})`;
    })
    .join(', ');

  const frames = asArray<FrameRecord>(body.frames)
    .slice(-180)
    .map((frame, index) => `${index + 1}. ${frameToLine(frame)}`)
    .join('\n');

  const priorSnapshot = JSON.stringify(body.priorSnapshot ?? {}).slice(0, 4000);

  return [
    `sessionId: ${trim(body.sessionId)}`,
    `strategy: ${trim(body.strategy) || 'cheap_live'}`,
    `participants: ${participants || '[unknown participants]'}`,
    'priorSnapshot:',
    priorSnapshot || '{}',
    'frames:',
    frames || '[no frames]',
  ].join('\n');
}

function defaultStudentState(): StudentLearningState {
  return {
    approach: [],
    mistakes: [],
    corrections: [],
    stuckPoints: [],
    nextFocusArea: [],
  };
}

function normalizeResponse(raw: Record<string, unknown>, modelTier: 'cheap' | 'expensive', model: string): MemoryResponse {
  const lessonSegments = asArray<Record<string, unknown>>(raw.lessonSegments).slice(0, 12).map((item) => ({
    label: trim(item.label) || 'Lesson segment',
    summary: trim(item.summary) || 'Classroom memory segment.',
    startedAt: trim(item.startedAt) || null,
    endedAt: trim(item.endedAt) || null,
    markerType: trim(item.markerType) || null,
  }));

  const misconceptionClusters = asArray<Record<string, unknown>>(raw.misconceptionClusters).slice(0, 8).map((item) => ({
    title: trim(item.title) || 'Misconception',
    misconception: trim(item.misconception) || 'Potential misconception detected.',
    evidence: strings(item.evidence, 4),
    reteachAction: trim(item.reteachAction) || 'Reteach the step with a worked example and a student redo.',
  }));

  const interventionMoments = asArray<Record<string, unknown>>(raw.interventionMoments).slice(0, 10).map((item) => ({
    studentId: trim(item.studentId) || null,
    title: trim(item.title) || 'Intervention moment',
    summary: trim(item.summary) || 'Tutor intervened during live work.',
    tutorAction: trim(item.tutorAction) || 'Guided correction',
    followUp: trim(item.followUp) || 'Check the same skill again next session.',
  }));

  const exemplarMoments = asArray<Record<string, unknown>>(raw.exemplarMoments).slice(0, 6).map((item) => ({
    studentId: trim(item.studentId) || null,
    title: trim(item.title) || 'Exemplar moment',
    whyItMatters: trim(item.whyItMatters) || 'Useful work to discuss with the class.',
    boardId: trim(item.boardId) || null,
  }));

  const studentLearningStatesRaw = safeObject(raw.studentLearningStates);
  const studentLearningStates: Record<string, StudentLearningState> = {};
  for (const [studentId, value] of Object.entries(studentLearningStatesRaw)) {
    const item = safeObject(value);
    studentLearningStates[studentId] = {
      approach: strings(item.approach, 6),
      mistakes: strings(item.mistakes, 6),
      corrections: strings(item.corrections, 6),
      stuckPoints: strings(item.stuckPoints, 6),
      nextFocusArea: strings(item.nextFocusArea, 6),
    };
  }

  return {
    status: 'ready',
    modelTier,
    provider: config.model.provider,
    model,
    groupLessonMemory: {
      whatWasTaught: strings(safeObject(raw.groupLessonMemory).whatWasTaught, 8),
      keyMisconceptions: strings(safeObject(raw.groupLessonMemory).keyMisconceptions, 8),
      importantExamples: strings(safeObject(raw.groupLessonMemory).importantExamples, 6),
      reteachMoments: strings(safeObject(raw.groupLessonMemory).reteachMoments, 6),
    },
    lessonSegments,
    misconceptionClusters,
    interventionMoments,
    exemplarMoments,
    studentLearningStates,
    sessionContinuityNotes: {
      nextTutorShouldKnow: strings(safeObject(raw.sessionContinuityNotes).nextTutorShouldKnow, 6),
      reviseNextTime: strings(safeObject(raw.sessionContinuityNotes).reviseNextTime, 6),
      carryForwardTasks: strings(safeObject(raw.sessionContinuityNotes).carryForwardTasks, 6),
      atRiskStudentIds: strings(safeObject(raw.sessionContinuityNotes).atRiskStudentIds, 8),
    },
  };
}

function chooseModel(strategy: ClassroomMemoryStrategy): { model: string; tier: 'cheap' | 'expensive' } {
  const provider = config.model.provider;
  if (strategy === 'cheap_live') {
    return {
      model: provider === 'openai' ? config.model.openai.cheapModel : config.model.google.cheapModel,
      tier: 'cheap',
    };
  }
  return {
    model: provider === 'openai' ? config.model.openai.expensiveModel : config.model.google.expensiveModel,
    tier: 'expensive',
  };
}

function safeJsonParse(text: string): Record<string, unknown> | null {
  try {
    return JSON.parse(text);
  } catch {
    const match = text.match(/\{[\s\S]*\}/);
    if (!match) return null;
    try {
      return JSON.parse(match[0]);
    } catch {
      return null;
    }
  }
}

router.post('/ai/classroom/memory/build', async (req, res) => {
  const body = (req.body ?? {}) as MemoryRequest;
  const sessionId = trim(body.sessionId);
  const frames = asArray<FrameRecord>(body.frames).filter((frame) => trim(frame.frameId).length > 0);
  const strategy = (trim(body.strategy) || 'cheap_live') as ClassroomMemoryStrategy;

  if (!sessionId) {
    res.status(400).json({ error: 'invalid_request', message: 'sessionId is required.' });
    return;
  }

  if (!frames.length) {
    res.json({
      status: 'ready',
      modelTier: 'fallback',
      provider: 'fallback',
      model: 'empty-classroom-memory',
      groupLessonMemory: {
        whatWasTaught: [],
        keyMisconceptions: [],
        importantExamples: [],
        reteachMoments: [],
      },
      lessonSegments: [],
      misconceptionClusters: [],
      interventionMoments: [],
      exemplarMoments: [],
      studentLearningStates: {},
      sessionContinuityNotes: {
        nextTutorShouldKnow: [],
        reviseNextTime: [],
        carryForwardTasks: [],
        atRiskStudentIds: [],
      },
    } satisfies MemoryResponse);
    return;
  }

  const { model, tier } = chooseModel(strategy);
  const maxTokens = config.maxTokensPerEndpoint['POST /ai/classroom/memory/build'];
  const systemPrompt = [
    'You are Seshly classroom memory.',
    'Return JSON only.',
    'Be educational, exam-oriented, and concise.',
    'Do not act like a chatbot. Build memory from teaching flow.',
    'Use these exact top-level keys: groupLessonMemory, lessonSegments, misconceptionClusters, interventionMoments, exemplarMoments, studentLearningStates, sessionContinuityNotes.',
    'groupLessonMemory must contain: whatWasTaught, keyMisconceptions, importantExamples, reteachMoments.',
    'studentLearningStates must be an object keyed by studentId, each with: approach, mistakes, corrections, stuckPoints, nextFocusArea.',
    'sessionContinuityNotes must contain: nextTutorShouldKnow, reviseNextTime, carryForwardTasks, atRiskStudentIds.',
    'Favor grounded statements from the frames. If uncertain, omit rather than invent.',
  ].join('\n');

  const output = await callTextModel({
    provider: config.model.provider,
    model,
    jsonOnly: true,
    temperature: tier === 'cheap' ? 0.1 : 0.2,
    maxTokens,
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: buildPrompt(body).slice(0, 12000) },
    ],
  });

  const parsed = safeJsonParse(output) ?? {};
  const normalized = normalizeResponse(parsed, tier, model);
  res.json(normalized);
});

export default router;
