"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.aiThreadDoc = exports.aiThreadsCollection = exports.aiUsageDayDoc = exports.aiUsageDaysCollection = exports.aiUsageCollection = exports.aiLogDoc = exports.aiLogsCollection = exports.vaultDoc = exports.vaultCollection = exports.userCalendarEventDoc = exports.userCalendarEventsCollection = exports.userChatSettingsDoc = exports.userChatSettingsCollection = exports.userDoc = exports.usersCollection = void 0;
const firebase_1 = require("./firebase");
const db = (0, firebase_1.getFirestore)();
const usersCollection = () => db.collection('users');
exports.usersCollection = usersCollection;
const userDoc = (userId) => (0, exports.usersCollection)().doc(userId);
exports.userDoc = userDoc;
const userChatSettingsCollection = (userId) => db
    .collection('users')
    .doc(userId)
    .collection('chatSettings');
exports.userChatSettingsCollection = userChatSettingsCollection;
const userChatSettingsDoc = (userId, chatId) => (0, exports.userChatSettingsCollection)(userId).doc(chatId);
exports.userChatSettingsDoc = userChatSettingsDoc;
const userCalendarEventsCollection = (userId) => db
    .collection('users')
    .doc(userId)
    .collection('calendarEvents');
exports.userCalendarEventsCollection = userCalendarEventsCollection;
const userCalendarEventDoc = (userId, eventId) => (0, exports.userCalendarEventsCollection)(userId).doc(eventId);
exports.userCalendarEventDoc = userCalendarEventDoc;
const vaultCollection = () => db.collection('vault');
exports.vaultCollection = vaultCollection;
const vaultDoc = (docId) => (0, exports.vaultCollection)().doc(docId);
exports.vaultDoc = vaultDoc;
const aiLogsCollection = () => db.collection('ai_logs');
exports.aiLogsCollection = aiLogsCollection;
const aiLogDoc = (logId) => (0, exports.aiLogsCollection)().doc(logId);
exports.aiLogDoc = aiLogDoc;
const aiUsageCollection = () => db.collection('ai_usage');
exports.aiUsageCollection = aiUsageCollection;
const aiUsageDaysCollection = (userId) => (0, exports.aiUsageCollection)().doc(userId).collection('days');
exports.aiUsageDaysCollection = aiUsageDaysCollection;
const aiUsageDayDoc = (userId, dayId) => (0, exports.aiUsageDaysCollection)(userId).doc(dayId);
exports.aiUsageDayDoc = aiUsageDayDoc;
const aiThreadsCollection = () => db.collection('ai_threads');
exports.aiThreadsCollection = aiThreadsCollection;
const aiThreadDoc = (threadId) => (0, exports.aiThreadsCollection)().doc(threadId);
exports.aiThreadDoc = aiThreadDoc;
