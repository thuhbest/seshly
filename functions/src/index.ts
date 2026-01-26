import {onCall, HttpsError} from "firebase-functions/v2/https";
import {
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";

admin.initializeApp();
const db = admin.firestore();

// 🔥 Region set to europe-west1 for South Africa latency optimization
const REGION = "europe-west1";

interface AchievementConfig {
  field: string;
  thresholds: number[];
  rewards: number[];
  names: string[];
}

const ACHIEVEMENTS_CONFIG: Record<string, AchievementConfig> = {
  first_post: {
    field: "postCount",
    thresholds: [1, 10, 50],
    rewards: [50, 100, 200],
    names: ["First Question", "Curious Mind", "Question Master"],
  },
  helpful_student: {
    field: "totalReplies",
    thresholds: [1, 5, 25],
    rewards: [30, 60, 150],
    names: ["First Answer", "Helpful Student", "Community Hero"],
  },
  vault_contributor: {
    field: "vaultUploads",
    thresholds: [1, 5, 20],
    rewards: [40, 80, 200],
    names: ["First Upload", "Vault Contributor", "Knowledge Keeper"],
  },
  focus_master: {
    field: "seshFocusHours",
    thresholds: [1, 10, 50],
    rewards: [25, 100, 500],
    names: ["Focus Beginner", "Focus Master", "Focus Titan"],
  },
};

interface NotificationPayload {
  type: string;
  title: string;
  body: string;
  actorId?: string;
  actorName?: string;
  postId?: string;
  commentId?: string;
  requestId?: string;
  chatId?: string;
  messageId?: string;
  itemId?: string;
  orderId?: string;
}

const NOTIFICATION_PREVIEW_LIMIT = 80;

/**
 * Resolves a user's display name for notifications.
 * @param {string} userId - Firestore user document ID.
 * @return {Promise<string>} Resolved display name.
 */
async function getUserName(userId: string): Promise<string> {
  if (!userId) return "Someone";
  const userDoc = await db.collection("users").doc(userId).get();
  const data = userDoc.data() ?? {};
  return data.fullName || data.displayName || "Someone";
}

/**
 * Trims notification preview text to a safe length.
 * @param {string} text - Raw notification preview text.
 * @return {string} Trimmed preview.
 */
function trimPreview(text: string): string {
  const cleaned = (text || "").toString().trim();
  if (cleaned.length <= NOTIFICATION_PREVIEW_LIMIT) return cleaned;
  return `${cleaned.slice(0, NOTIFICATION_PREVIEW_LIMIT - 3)}...`;
}

/**
 * Builds lightweight search tokens for marketplace items.
 * @param {...string} values - Strings to tokenize.
 * @return {string[]} Unique search tokens.
 */
function buildSearchTokens(...values: string[]): string[] {
  const tokens = new Set<string>();
  for (const value of values) {
    if (!value) continue;
    value
      .toLowerCase()
      .split(/[^a-z0-9]+/g)
      .filter((token) => token.length >= 2)
      .forEach((token) => tokens.add(token));
  }
  return Array.from(tokens).slice(0, 30);
}

/**
 * Creates a notification record and pushes FCM if tokens exist.
 * @param {string} userId - Target user ID.
 * @param {NotificationPayload} payload - Notification content.
 * @return {Promise<void>} Completion promise.
 */
async function createNotification(
  userId: string,
  payload: NotificationPayload
): Promise<void> {
  if (!userId) return;
  await db
    .collection("users")
    .doc(userId)
    .collection("notifications")
    .add({
      ...payload,
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  await sendPushToUser(userId, payload);
}

/**
 * Fetches a user's registered FCM tokens.
 * @param {string} userId - Target user ID.
 * @return {Promise<string[]>} List of tokens.
 */
async function getUserTokens(userId: string): Promise<string[]> {
  const snapshot = await db
    .collection("users")
    .doc(userId)
    .collection("fcmTokens")
    .get();

  return snapshot.docs
    .map((doc) => (doc.data()?.token as string | undefined) || doc.id)
    .filter((token) => Boolean(token));
}

/**
 * Checks if a user's push notifications are enabled.
 * @param {string} userId - Target user ID.
 * @return {Promise<boolean>} True when push is enabled.
 */
async function isPushEnabled(userId: string): Promise<boolean> {
  const userSnap = await db.collection("users").doc(userId).get();
  const data = userSnap.data() ?? {};
  const prefs = (data.notificationPrefs ?? {}) as Record<string, unknown>;
  return prefs.push !== false;
}

/**
 * Builds a data payload for FCM delivery.
 * @param {NotificationPayload} payload - Notification content.
 * @return {Record<string, string>} FCM data payload.
 */
function buildDataPayload(
  payload: NotificationPayload
): Record<string, string> {
  const data: Record<string, string> = {
    type: payload.type,
  };

  if (payload.actorId) data.actorId = payload.actorId;
  if (payload.actorName) data.actorName = payload.actorName;
  if (payload.postId) data.postId = payload.postId;
  if (payload.commentId) data.commentId = payload.commentId;
  if (payload.requestId) data.requestId = payload.requestId;
  if (payload.chatId) data.chatId = payload.chatId;
  if (payload.messageId) data.messageId = payload.messageId;
  if (payload.itemId) data.itemId = payload.itemId;
  if (payload.orderId) data.orderId = payload.orderId;

  return data;
}

/**
 * Sends a push notification to all known tokens for a user.
 * @param {string} userId - Target user ID.
 * @param {NotificationPayload} payload - Notification content.
 * @return {Promise<void>} Completion promise.
 */
async function sendPushToUser(
  userId: string,
  payload: NotificationPayload
): Promise<void> {
  const pushEnabled = await isPushEnabled(userId);
  if (!pushEnabled) return;

  const tokens = await getUserTokens(userId);
  if (tokens.length === 0) return;

  const notification = {
    title: payload.title,
    body: payload.body,
  };
  const data = buildDataPayload(payload);

  const chunkSize = 500;
  for (let i = 0; i < tokens.length; i += chunkSize) {
    const batchTokens = tokens.slice(i, i + chunkSize);
    const response = await admin.messaging().sendEachForMulticast({
      tokens: batchTokens,
      notification,
      data,
    });

    const invalidTokens: string[] = [];
    response.responses.forEach((result, index) => {
      if (result.success) return;
      const code = result.error?.code;
      if (
        code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-registration-token"
      ) {
        invalidTokens.push(batchTokens[index]);
      }
    });

    if (invalidTokens.length > 0) {
      const batch = db.batch();
      for (const token of invalidTokens) {
        batch.delete(
          db
            .collection("users")
            .doc(userId)
            .collection("fcmTokens")
            .doc(token)
        );
      }
      await batch.commit();
    }
  }
}

/**
 * Checks and awards achievements based on user activity.
 * @param {admin.firestore.Transaction} transaction - The active transaction.
 * @param {admin.firestore.DocumentReference} userRef - Reference to user.
 * @param {string} field - The field being checked.
 * @param {number} newValue - The new value of the field.
 */
async function checkAndAwardAchievements(
  transaction: admin.firestore.Transaction,
  userRef: admin.firestore.DocumentReference,
  field: string,
  newValue: number
): Promise<void> {
  const userDoc = await transaction.get(userRef);
  if (!userDoc.exists) return;

  const userData = userDoc.data() ?? {};
  const achievements = userData.achievements ?? {};

  for (const [achievementKey, config] of Object.entries(ACHIEVEMENTS_CONFIG)) {
    if (config.field !== field) continue;

    for (let i = 0; i < config.thresholds.length; i++) {
      const tierKey = `${achievementKey}_${i}`;

      if (newValue >= config.thresholds[i] && !achievements[tierKey]) {
        transaction.update(userRef, {
          [`achievements.${tierKey}`]: {
            unlockedAt: admin.firestore.FieldValue.serverTimestamp(),
            name: config.names[i],
            tier: i,
            rewardXP: config.rewards[i],
          },
          xp: admin.firestore.FieldValue.increment(config.rewards[i]),
        });
      }
    }
  }
}

export const onpostcreated = onDocumentCreated({
  document: "posts/{postId}",
  region: REGION,
}, async (event) => {
  const snap = event.data;
  if (!snap) return;
  const data = snap.data();
  const userRef = db.collection("users").doc(data.authorId);

  return db.runTransaction(async (transaction) => {
    const userDoc = await transaction.get(userRef);
    if (!userDoc.exists) return;
    const postCount = (userDoc.data()?.postCount ?? 0) + 1;
    await checkAndAwardAchievements(
      transaction,
      userRef,
      "postCount",
      postCount
    );
    transaction.update(userRef, {
      xp: admin.firestore.FieldValue.increment(10),
      postCount,
    });
  });
});

export const oncommentcreated = onDocumentCreated({
  document: "posts/{postId}/comments/{commentId}",
  region: REGION,
}, async (event) => {
  const snap = event.data;
  if (!snap) return;
  const data = snap.data();
  const commenterId = data.userId;
  if (!commenterId) return;
  const userRef = db.collection("users").doc(commenterId);

  await db.runTransaction(async (transaction) => {
    const userDoc = await transaction.get(userRef);
    if (!userDoc.exists) return;
    const totalReplies = (userDoc.data()?.totalReplies ?? 0) + 1;
    await checkAndAwardAchievements(
      transaction,
      userRef,
      "totalReplies",
      totalReplies
    );
    transaction.update(userRef, {
      xp: admin.firestore.FieldValue.increment(5),
      totalReplies,
    });
  });

  const postId = event.params?.postId;
  const commentId = event.params?.commentId;
  if (!postId) return;

  const postSnap = await db.collection("posts").doc(postId).get();
  if (!postSnap.exists) return;

  const postData = postSnap.data() ?? {};
  const authorId = postData.authorId;
  if (!authorId || authorId === commenterId) return;

  const actorName = await getUserName(commenterId);
  const commentPreview = trimPreview(data.text);
  const body = commentPreview ?
    `${actorName} answered: "${commentPreview}"` :
    `${actorName} answered your question.`;

  await createNotification(authorId, {
    type: "comment",
    title: "New answer on your question",
    body,
    actorId: commenterId,
    actorName,
    postId,
    commentId,
  });
});

export const onhelpfulcreated = onDocumentCreated({
  document: "posts/{postId}/helpful_users/{userId}",
  region: REGION,
}, async (event) => {
  const snap = event.data;
  if (!snap) return;
  const postId = event.params?.postId;
  const actorId = event.params?.userId;
  if (!postId || !actorId) return;

  const postSnap = await db.collection("posts").doc(postId).get();
  if (!postSnap.exists) return;

  const postData = postSnap.data() ?? {};
  const authorId = postData.authorId;
  if (!authorId || authorId === actorId) return;

  const actorName = await getUserName(actorId);
  const questionPreview = trimPreview(
    postData.question || postData.subject || ""
  );
  const body = questionPreview ?
    `${actorName} found your question helpful: "${questionPreview}"` :
    `${actorName} found your question helpful.`;

  await createNotification(authorId, {
    type: "helpful",
    title: "Someone liked your question",
    body,
    actorId,
    actorName,
    postId,
  });
});

export const onfriendrequestcreated = onDocumentCreated({
  document: "friend_requests/{requestId}",
  region: REGION,
}, async (event) => {
  const snap = event.data;
  if (!snap) return;
  const data = snap.data();
  const toUserId = data.toUserID;
  const fromUserId = data.fromUserID;
  if (!toUserId || !fromUserId) return;
  if (data.status && data.status !== "pending") return;
  if (toUserId === fromUserId) return;

  const fromName = await getUserName(fromUserId);
  const body = `${fromName} sent you a friend request.`;
  await createNotification(toUserId, {
    type: "friend_request",
    title: "New friend request",
    body,
    actorId: fromUserId,
    actorName: fromName,
    requestId: snap.id,
  });
});

export const onfriendrequestupdated = onDocumentUpdated({
  document: "friend_requests/{requestId}",
  region: REGION,
}, async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!before || !after) return;

  const beforeStatus = before.status;
  const afterStatus = after.status;
  if (beforeStatus === afterStatus) return;
  if (afterStatus !== "accepted") return;

  const fromUserId = after.fromUserID;
  const toUserId = after.toUserID;
  if (!fromUserId || !toUserId) return;
  if (fromUserId === toUserId) return;

  const toName = await getUserName(toUserId);
  const body = `${toName} accepted your friend request.`;
  await createNotification(fromUserId, {
    type: "friend_accept",
    title: "Friend request accepted",
    body,
    actorId: toUserId,
    actorName: toName,
    requestId: event.params?.requestId,
  });
});

export const onmessagecreated = onDocumentCreated({
  document: "chats/{chatId}/messages/{messageId}",
  region: REGION,
}, async (event) => {
  const snap = event.data;
  if (!snap) return;
  const data = snap.data();
  const chatId = event.params?.chatId;
  const messageId = event.params?.messageId;
  const senderId = data.senderId;

  if (!chatId || !senderId) return;
  const chatSnap = await db.collection("chats").doc(chatId).get();
  if (!chatSnap.exists) return;

  const chatData = chatSnap.data() ?? {};
  const participants = chatData.participants ?? [];
  if (!Array.isArray(participants)) return;

  const senderName = await getUserName(senderId);
  const preview = trimPreview(data.text);
  const body = preview ?
    `${senderName}: ${preview}` :
    `${senderName} sent a message.`;

  const writes = participants
    .filter((userId: string) => userId && userId !== senderId)
    .map((userId: string) => {
      return createNotification(userId, {
        type: "message",
        title: "New message",
        body,
        actorId: senderId,
        actorName: senderName,
        chatId,
        messageId,
      });
    });

  await Promise.all(writes);
});

export const onmarketplaceitemcreated = onDocumentCreated({
  document: "marketplace_items/{itemId}",
  region: REGION,
}, async (event) => {
  const snap = event.data;
  if (!snap) return;
  const data = snap.data() ?? {};

  const updates: Record<string, unknown> = {};
  if (!data.createdAt) {
    updates.createdAt = admin.firestore.FieldValue.serverTimestamp();
  }
  if (!data.status) {
    updates.status = "active";
  }
  if (!data.currency) {
    updates.currency = "ZAR";
  }
  if (!data.searchTokens) {
    const tokens = buildSearchTokens(
      (data.title ?? "").toString(),
      (data.description ?? "").toString(),
      (data.category ?? "").toString(),
      (data.sellerName ?? "").toString()
    );
    if (tokens.length > 0) {
      updates.searchTokens = tokens;
    }
  }

  if (Object.keys(updates).length > 0) {
    await snap.ref.set(updates, {merge: true});
  }

  const sellerId = data.sellerId;
  if (!sellerId) return;
  await db.collection("users").doc(sellerId).set({
    marketListings: admin.firestore.FieldValue.increment(1),
  }, {merge: true});
});

export const onmarketplaceordercreated = onDocumentCreated({
  document: "marketplace_orders/{orderId}",
  region: REGION,
}, async (event) => {
  const snap = event.data;
  if (!snap) return;
  const data = snap.data() ?? {};

  const updates: Record<string, unknown> = {};
  if (!data.createdAt) {
    updates.createdAt = admin.firestore.FieldValue.serverTimestamp();
  }
  if (!data.status) {
    updates.status = "pending";
  }
  if (Object.keys(updates).length > 0) {
    await snap.ref.set(updates, {merge: true});
  }

  const sellerId = data.sellerId;
  const buyerId = data.buyerId;
  const itemId = data.itemId;
  if (!sellerId || !buyerId || !itemId) return;

  const itemSnap = await db.collection("marketplace_items").doc(itemId).get();
  const itemData = itemSnap.data() ?? {};
  const itemTitle = trimPreview((itemData.title ?? "item").toString());
  const buyerName = await getUserName(buyerId);
  const body = itemTitle ?
    `${buyerName} wants to buy "${itemTitle}".` :
    `${buyerName} wants to buy your item.`;

  await createNotification(sellerId, {
    type: "market_order",
    title: "New marketplace order",
    body,
    actorId: buyerId,
    actorName: buyerName,
    itemId,
    orderId: event.params?.orderId,
  });
});

export const onmarketplaceorderupdated = onDocumentUpdated({
  document: "marketplace_orders/{orderId}",
  region: REGION,
}, async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!before || !after) return;
  if (before.status === after.status) return;

  const status = after.status;
  if (status !== "completed") return;

  const sellerId = after.sellerId;
  const buyerId = after.buyerId;
  const itemId = after.itemId;

  if (itemId) {
    await db.collection("marketplace_items").doc(itemId).set({
      status: "sold",
      soldAt: admin.firestore.FieldValue.serverTimestamp(),
      soldTo: buyerId ?? null,
    }, {merge: true});
  }

  if (sellerId) {
    await db.collection("users").doc(sellerId).set({
      marketSales: admin.firestore.FieldValue.increment(1),
    }, {merge: true});
  }
});

export const onvaultupload = onDocumentCreated({
  document: "vault/{docId}",
  region: REGION,
}, async (event) => {
  const snap = event.data;
  if (!snap) return;
  const data = snap.data();
  const userRef = db.collection("users").doc(data.userId);

  return db.runTransaction(async (transaction) => {
    const userDoc = await transaction.get(userRef);
    if (!userDoc.exists) return;
    const vaultUploads = (userDoc.data()?.vaultUploads ?? 0) + 1;
    await checkAndAwardAchievements(
      transaction,
      userRef,
      "vaultUploads",
      vaultUploads
    );
    transaction.update(userRef, {
      xp: admin.firestore.FieldValue.increment(20),
      vaultUploads,
    });
  });
});

export const onfocussessionend = onCall({region: REGION}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be logged in.");
  }
  const userRef = db.collection("users").doc(request.auth.uid);
  const hours = Number(request.data.hours ?? 0);

  return db.runTransaction(async (transaction) => {
    const userDoc = await transaction.get(userRef);
    if (!userDoc.exists) return;
    const newHours = (userDoc.data()?.seshFocusHours ?? 0) + hours;
    await checkAndAwardAchievements(
      transaction,
      userRef,
      "seshFocusHours",
      newHours
    );
    transaction.update(userRef, {
      xp: admin.firestore.FieldValue.increment(hours * 10),
      seshFocusHours: newHours,
    });
  });
});

export const checkachievements = onCall({region: REGION}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be logged in.");
  }
  const userRef = db.collection("users").doc(request.auth.uid);

  return db.runTransaction(async (transaction) => {
    const userDoc = await transaction.get(userRef);
    if (!userDoc.exists) throw new HttpsError("not-found", "User not found");
    const data = userDoc.data() ?? {};
    const fields = [
      "postCount",
      "totalReplies",
      "vaultUploads",
      "seshFocusHours",
    ];
    for (const field of fields) {
      await checkAndAwardAchievements(
        transaction,
        userRef,
        field,
        data[field] ?? 0
      );
    }
    return {success: true};
  });
});
