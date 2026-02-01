import type { FieldValue, Timestamp } from 'firebase-admin/firestore';

export type FirestoreTimestamp = Timestamp | FieldValue;

export type BaseDoc = {
  createdAt?: FirestoreTimestamp;
  updatedAt?: FirestoreTimestamp;
};

export type UserNotificationPrefs = {
  push?: boolean;
  email?: boolean;
  studyReminders?: boolean;
};

export type TutorStats = {
  minutesTutored?: number;
  learnersHelped?: number;
  sessionsCompleted?: number;
  ratingAvg?: number;
  ratingCount?: number;
  totalEarnings?: number;
};

export type UserDoc = BaseDoc & {
  displayName?: string;
  email?: string;
  profilePic?: string;
  bio?: string;
  universityId?: string;
  status?: string;
  tutorStatus?: string;
  tutorSubjects?: string[];
  tutorStats?: TutorStats;
  notificationPrefs?: UserNotificationPrefs;
  seshMinutes?: number;
  streak?: number;
  [key: string]: unknown;
};

export type UserChatSettingsDoc = BaseDoc & {
  backgroundColor?: number;
};

export type UserSettingsDoc = BaseDoc & {
  affirmationsEnabled?: boolean;
  frequencyMin?: number;
  tone?: string;
  [key: string]: unknown;
};

export type CalendarEventDoc = BaseDoc & {
  title: string;
  start: FirestoreTimestamp;
  end: FirestoreTimestamp;
  location?: string;
  type?: string;
  subjectCode?: string;
  colorHex?: number;
  colorKey?: string;
  source?: string;
  timetableId?: string | null;
  recurrence?: string;
};

export type VaultDoc = BaseDoc & {
  userId: string;
  subject: string;
  year: string;
  type: string;
  fileUrl: string;
  stars?: number;
  starredBy?: string[];
  claimedName?: string;
  sha256?: string;
  canonical?: string;
  textSummary?: string;
  metadata?: {
    institution?: string;
    courseCode?: string;
    courseName?: string;
    year?: string;
    term?: string;
    docType?: string;
    variant?: string;
  };
  embedding?: number[];
  embeddingModel?: string;
};

export type AiLogDoc = BaseDoc & {
  type?: string;
  requestId?: string | null;
  userId?: string | null;
  uid?: string | null;
  method?: string;
  path?: string;
  status?: number;
  durationMs?: number;
  ip?: string | null;
  userAgent?: string | null;
  error?: string;
  [key: string]: unknown;
};

export type AiUsageDayDoc = BaseDoc & {
  requestCount?: number;
  tokenCount?: number;
  lastUsedAt?: FirestoreTimestamp;
};

export type AiThreadDoc = BaseDoc & {
  userId: string;
  threadId: string;
  turnsUsed: number;
  lastMessageAt?: FirestoreTimestamp;
  lastMessageSnippet?: string | null;
};

export type PracticeQuestion = {
  id: string;
  difficulty: 'weak' | 'medium' | 'hard' | 'impossible';
  question: string;
  allowedHelp: 'hint_only';
  markingGuide?: string;
};

export type PracticeSetDoc = BaseDoc & {
  userId: string;
  setId: string;
  subject?: string;
  topic: string;
  prerequisites: string[];
  questions: PracticeQuestion[];
  difficultyCounts: {
    weak: number;
    medium: number;
    hard: number;
    impossible: number;
  };
  sourceType?: 'pdf' | 'image' | 'unknown';
};
