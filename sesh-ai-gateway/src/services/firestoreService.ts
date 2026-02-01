import type { CollectionReference, DocumentReference } from 'firebase-admin/firestore';

import { getFirestore } from './firebase';
import type {
  AiLogDoc,
  AiThreadDoc,
  CalendarEventDoc,
  PracticeSetDoc,
  UserChatSettingsDoc,
  UserSettingsDoc,
  UserDoc,
  VaultDoc,
  AiUsageDayDoc,
} from '../types/firestore';

const db = getFirestore();

export const usersCollection = () => db.collection('users') as CollectionReference<UserDoc>;

export const userDoc = (userId: string) =>
  usersCollection().doc(userId) as DocumentReference<UserDoc>;

export const userChatSettingsCollection = (userId: string) =>
  db
    .collection('users')
    .doc(userId)
    .collection('chatSettings') as CollectionReference<UserChatSettingsDoc>;

export const userChatSettingsDoc = (userId: string, chatId: string) =>
  userChatSettingsCollection(userId).doc(chatId) as DocumentReference<UserChatSettingsDoc>;

export const userSettingsCollection = (userId: string) =>
  db
    .collection('users')
    .doc(userId)
    .collection('settings') as CollectionReference<UserSettingsDoc>;

export const userSettingsDoc = (userId: string, settingsId = 'preferences') =>
  userSettingsCollection(userId).doc(settingsId) as DocumentReference<UserSettingsDoc>;

export const userCalendarEventsCollection = (userId: string) =>
  db
    .collection('users')
    .doc(userId)
    .collection('calendarEvents') as CollectionReference<CalendarEventDoc>;

export const userCalendarEventDoc = (userId: string, eventId: string) =>
  userCalendarEventsCollection(userId).doc(eventId) as DocumentReference<CalendarEventDoc>;

export const vaultCollection = () => db.collection('vault') as CollectionReference<VaultDoc>;

export const vaultDoc = (docId: string) =>
  vaultCollection().doc(docId) as DocumentReference<VaultDoc>;

export const aiLogsCollection = () =>
  db.collection('ai_logs') as CollectionReference<AiLogDoc>;

export const aiLogDoc = (logId: string) =>
  aiLogsCollection().doc(logId) as DocumentReference<AiLogDoc>;

export const aiUsageCollection = () => db.collection('ai_usage');

export const aiUsageDaysCollection = (userId: string) =>
  aiUsageCollection().doc(userId).collection('days') as CollectionReference<AiUsageDayDoc>;

export const aiUsageDayDoc = (userId: string, dayId: string) =>
  aiUsageDaysCollection(userId).doc(dayId) as DocumentReference<AiUsageDayDoc>;

export const aiThreadsCollection = () =>
  db.collection('ai_threads') as CollectionReference<AiThreadDoc>;

export const aiThreadDoc = (threadId: string) =>
  aiThreadsCollection().doc(threadId) as DocumentReference<AiThreadDoc>;

export const userPracticeSetsCollection = (userId: string) =>
  db
    .collection('users')
    .doc(userId)
    .collection('practiceSets') as CollectionReference<PracticeSetDoc>;

export const userPracticeSetDoc = (userId: string, setId: string) =>
  userPracticeSetsCollection(userId).doc(setId) as DocumentReference<PracticeSetDoc>;

export const tutorsCollection = () => db.collection('tutors');
