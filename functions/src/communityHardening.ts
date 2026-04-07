import * as admin from "firebase-admin";
import {HttpsError} from "firebase-functions/v2/https";

import {
  assertNoUnexpectedFields,
  checkRepeatedContent,
  readOptionalUrl,
  readRequiredString,
  readTrimmedString,
  recordModerationEvent,
  secureOnCall,
  type SecureCallableOptions,
  requireObjectPayload,
  validateUploadedStorageFile,
} from "./security";
import {
  evaluateModeration,
  normalizeTextFingerprint,
  type ModerationDecision,
} from "./contentModeration";

const db = admin.firestore();
const REGION = "europe-west1";
const IMAGE_CONTENT_TYPE_REGEX = /^image\/(png|jpeg|jpg|webp)$/i;
const AUDIO_CONTENT_TYPE_REGEX = /^audio\/(mpeg|mp3|wav|aac|ogg|webm|mp4|x-m4a|m4a)$/i;
const PDF_CONTENT_TYPE_REGEX = /^application\/pdf$/i;
const STUDY_VAULT_COMMISSION_PERCENT = 20;
const ALLOWED_TUTOR_AVAILABILITY = new Set(["accepting", "after_current", "offline"]);
const ALLOWED_CHAT_REACTIONS = new Set([
  "😀",
  "😂",
  "😍",
  "😮",
  "😢",
  "😡",
  "👍",
  "🙏",
  "🔥",
  "💯",
  "🎯",
  "✅",
]);

type JsonMap = Record<string, unknown>;

interface ModeratedContentResult {
  sanitizedText: string;
  moderationStatus: "clean" | "flagged";
  moderationFlags: string[];
}

function nowServerTs() {
  return admin.firestore.FieldValue.serverTimestamp();
}

function toStringList(value: unknown, maxItems = 5): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((entry) => readTrimmedString(entry, 80))
    .filter((entry, index, list) => entry.length > 0 && list.indexOf(entry) === index)
    .slice(0, maxItems);
}

function readPositiveNumber(
  value: unknown,
  fieldName: string,
  options?: {max?: number; optional?: boolean}
): number {
  if (options?.optional && (value == null || value === "")) {
    return 0;
  }
  const numeric = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(numeric) || numeric < 0) {
    throw new HttpsError("invalid-argument", `${fieldName} is invalid.`);
  }
  if (options?.max != null && numeric > options.max) {
    throw new HttpsError("invalid-argument", `${fieldName} is invalid.`);
  }
  return numeric;
}

function computeStudyVaultFees(priceZar: number): {
  platformFeeZar: number;
  sellerNetZar: number;
} {
  const platformFeeZar = Math.round((priceZar * STUDY_VAULT_COMMISSION_PERCENT) / 100);
  return {
    platformFeeZar,
    sellerNetZar: priceZar - platformFeeZar,
  };
}

async function resolveUserProfile(userId: string): Promise<JsonMap> {
  const snap = await db.collection("users").doc(userId).get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "User profile could not be found.");
  }
  return (snap.data() ?? {}) as JsonMap;
}

async function applyModerationOrThrow(params: {
  action: string;
  actorUid: string;
  contentType: string;
  text: string;
  maxLength: number;
  fingerprintAction: string;
  metadata?: JsonMap;
}): Promise<ModeratedContentResult> {
  const decision = evaluateModeration(params.text, {maxLength: params.maxLength});
  await handleModerationDecision({
    action: params.action,
    actorUid: params.actorUid,
    contentType: params.contentType,
    decision,
    fingerprintAction: params.fingerprintAction,
    metadata: params.metadata,
  });
  return {
    sanitizedText: decision.sanitizedText,
    moderationStatus: decision.severity === "allow_with_flag" ? "flagged" : "clean",
    moderationFlags: decision.severity === "allow_with_flag" ? decision.reasons : [],
  };
}

async function handleModerationDecision(params: {
  action: string;
  actorUid: string;
  contentType: string;
  decision: ModerationDecision;
  fingerprintAction: string;
  metadata?: JsonMap;
}): Promise<void> {
  const fingerprint = normalizeTextFingerprint(params.decision.normalizedText);
  const duplicateSpam = fingerprint ?
    await checkRepeatedContent({
      action: params.fingerprintAction,
      actorUid: params.actorUid,
      fingerprint,
    }) :
    false;

  let severity = params.decision.severity;
  const reasons = [...params.decision.reasons];
  if (duplicateSpam) {
    severity = "rate_limit_user";
    if (!reasons.includes("duplicate_spam")) {
      reasons.push("duplicate_spam");
    }
  }

  if (severity === "allow") {
    return;
  }

  await recordModerationEvent({
    action: params.action,
    actorUid: params.actorUid,
    contentType: params.contentType,
    severity,
    reasons,
    metadata: params.metadata,
  });

  if (severity === "allow_with_flag") {
    return;
  }

  if (severity === "rate_limit_user") {
    throw new HttpsError(
      "resource-exhausted",
      "Too many similar submissions. Please try again later."
    );
  }

  throw new HttpsError(
    "failed-precondition",
    "This content could not be posted."
  );
}

function secureCommunityCall<T, Return>(
  options: Omit<SecureCallableOptions<T>, "region">,
  handler: Parameters<typeof secureOnCall<T, Return>>[1]
) {
  return secureOnCall<T, Return>({region: REGION, ...options}, handler);
}

export const createPost = secureCommunityCall<JsonMap, {postId: string}>(
  {
    action: "community.create_post",
    analyticsEvent: "community_post",
    rateLimitProfile: "writeHeavy",
  },
  async (request) => {
    const payload = requireObjectPayload(request.data);
    assertNoUnexpectedFields(payload, [
      "subject",
      "question",
      "link",
      "attachmentUrl",
      "attachmentPath",
      "repostText",
      "repostOf",
    ]);

    const userId = request.auth!.uid;
    const userProfile = await resolveUserProfile(userId);
    const subject = readRequiredString(payload.subject, "subject", 80);
    const question = readRequiredString(payload.question, "question", 3000);
    const link = readOptionalUrl(payload.link);
    const attachmentPath = readTrimmedString(payload.attachmentPath, 300);
    const attachmentUrl = readOptionalUrl(payload.attachmentUrl);
    const repostTextRaw = readTrimmedString(payload.repostText, 1000);
    const repostOfRaw = payload.repostOf;

    if (attachmentPath) {
      await validateUploadedStorageFile({
        path: attachmentPath,
        ownerPrefix: `post_attachments/${userId}_`,
        maxBytes: 10 * 1024 * 1024,
        contentTypePattern: IMAGE_CONTENT_TYPE_REGEX,
      });
    }

    const combined = [subject, question, repostTextRaw, link].join(" ").trim();
    const moderated = await applyModerationOrThrow({
      action: "community.create_post",
      actorUid: userId,
      contentType: "post",
      text: combined,
      maxLength: 3200,
      fingerprintAction: "community_post",
      metadata: {subject},
    });

    const authorName = readTrimmedString(
      userProfile.fullName ?? userProfile.displayName,
      120
    ) || "Student";

    let repostOf: JsonMap | null = null;
    let isRepost = false;
    if (repostOfRaw && typeof repostOfRaw === "object" && !Array.isArray(repostOfRaw)) {
      const repostObject = repostOfRaw as JsonMap;
      repostOf = {
        postId: readTrimmedString(repostObject.postId, 120),
        authorId: readTrimmedString(repostObject.authorId, 120),
        author: readTrimmedString(repostObject.author, 120),
        subject: readTrimmedString(repostObject.subject, 80),
        question: readTrimmedString(repostObject.question, 3000),
        attachmentUrl: readOptionalUrl(repostObject.attachmentUrl),
        link: readOptionalUrl(repostObject.link),
      };
      isRepost = true;
    }

    const postRef = db.collection("posts").doc();
    await postRef.set({
      subject,
      question: moderated.sanitizedText,
      author: authorName,
      authorId: userId,
      createdAt: nowServerTs(),
      likes: 0,
      comments: 0,
      isUrgent: false,
      attachmentUrl: attachmentUrl || null,
      attachmentPath: attachmentPath || null,
      link: link || null,
      repostText: repostTextRaw || null,
      repostOf,
      isRepost,
      moderationStatus: moderated.moderationStatus,
      moderationFlags: moderated.moderationFlags,
      updatedAt: nowServerTs(),
    });

    return {postId: postRef.id};
  }
);

export const createComment = secureCommunityCall<JsonMap, {commentId: string}>(
  {
    action: "community.create_comment",
    analyticsEvent: "community_comment",
    rateLimitProfile: "writeHeavy",
  },
  async (request) => {
    const payload = requireObjectPayload(request.data);
    assertNoUnexpectedFields(payload, ["postId", "text"]);

    const userId = request.auth!.uid;
    const postId = readRequiredString(payload.postId, "postId", 120);
    const text = readRequiredString(payload.text, "text", 2000);
    const userProfile = await resolveUserProfile(userId);
    const postRef = db.collection("posts").doc(postId);
    const postSnap = await postRef.get();
    if (!postSnap.exists) {
      throw new HttpsError("not-found", "Post could not be found.");
    }

    const moderated = await applyModerationOrThrow({
      action: "community.create_comment",
      actorUid: userId,
      contentType: "comment",
      text,
      maxLength: 2000,
      fingerprintAction: `community_comment:${postId}`,
      metadata: {postId},
    });

    const authorName = readTrimmedString(
      userProfile.fullName ?? userProfile.displayName,
      120
    ) || "Student";
    const authorPhoto = readOptionalUrl(userProfile.profilePic);
    const commentRef = postRef.collection("comments").doc();

    await db.runTransaction(async (tx) => {
      tx.set(commentRef, {
        text: moderated.sanitizedText,
        userId,
        authorId: userId,
        authorName,
        authorPhoto: authorPhoto || null,
        createdAt: nowServerTs(),
        likes: 0,
        moderationStatus: moderated.moderationStatus,
        moderationFlags: moderated.moderationFlags,
      });
      tx.update(postRef, {
        comments: admin.firestore.FieldValue.increment(1),
        updatedAt: nowServerTs(),
      });
    });

    return {commentId: commentRef.id};
  }
);

export const ensureDirectChat = secureCommunityCall<JsonMap, {chatId: string}>(
  {
    action: "community.ensure_direct_chat",
    analyticsEvent: "community_chat_open",
    rateLimitProfile: "writeHeavy",
  },
  async (request) => {
    const payload = requireObjectPayload(request.data);
    assertNoUnexpectedFields(payload, ["participantId"]);

    const userId = request.auth!.uid;
    const participantId = readRequiredString(
      payload.participantId,
      "participantId",
      120
    );
    if (participantId === userId) {
      throw new HttpsError("invalid-argument", "participantId is invalid.");
    }

    const [selfProfile, peerProfile] = await Promise.all([
      resolveUserProfile(userId),
      resolveUserProfile(participantId),
    ]);

    const querySnap = await db
      .collection("chats")
      .where("participants", "array-contains", userId)
      .get();
    for (const doc of querySnap.docs) {
      const participants = Array.isArray(doc.data().participants) ?
        doc.data().participants.map((entry: unknown) => String(entry)) :
        [];
      if (participants.length === 2 && participants.includes(participantId)) {
        return {chatId: doc.id};
      }
    }

    const participants = [userId, participantId].sort();
    const chatRef = db.collection("chats").doc();
    await chatRef.set({
      participants,
      participantNames: {
        [userId]: readTrimmedString(
          selfProfile.fullName ?? selfProfile.displayName,
          120
        ) || "You",
        [participantId]: readTrimmedString(
          peerProfile.fullName ?? peerProfile.displayName,
          120
        ) || "Student",
      },
      lastMessage: "",
      lastMessageTime: nowServerTs(),
      isGroup: false,
      unreadCounts: {
        [userId]: 0,
        [participantId]: 0,
      },
      createdBy: userId,
      createdAt: nowServerTs(),
      updatedAt: nowServerTs(),
    });

    return {chatId: chatRef.id};
  }
);

export const sendChatMessage = secureCommunityCall<
  JsonMap,
  {messageId: string}
>(
  {
    action: "community.send_chat_message",
    analyticsEvent: "community_chat_message",
    rateLimitProfile: "chat",
  },
  async (request) => {
    const payload = requireObjectPayload(request.data);
    assertNoUnexpectedFields(payload, [
      "chatId",
      "type",
      "text",
      "audioUrl",
      "audioPath",
    ]);

    const userId = request.auth!.uid;
    const chatId = readRequiredString(payload.chatId, "chatId", 120);
    const type = readRequiredString(payload.type, "type", 16).toLowerCase();
    if (!["text", "voice"].includes(type)) {
      throw new HttpsError("invalid-argument", "type is invalid.");
    }

    const chatRef = db.collection("chats").doc(chatId);
    const [chatSnap, userProfile] = await Promise.all([
      chatRef.get(),
      resolveUserProfile(userId),
    ]);
    if (!chatSnap.exists) {
      throw new HttpsError("not-found", "Chat could not be found.");
    }
    const chatData = chatSnap.data() ?? {};
    const participants = Array.isArray(chatData.participants) ?
      chatData.participants.map((entry) => String(entry)) :
      [];
    if (!participants.includes(userId)) {
      throw new HttpsError("permission-denied", "Chat access is invalid.");
    }

    let text = "";
    let audioUrl = "";
    let audioPath = "";
    let moderationStatus: "clean" | "flagged" = "clean";
    let moderationFlags: string[] = [];

    if (type === "text") {
      const moderated = await applyModerationOrThrow({
        action: "community.send_chat_message",
        actorUid: userId,
        contentType: "chat_message",
        text: readRequiredString(payload.text, "text", 1200),
        maxLength: 1200,
        fingerprintAction: `chat_message:${chatId}`,
        metadata: {chatId},
      });
      text = moderated.sanitizedText;
      moderationStatus = moderated.moderationStatus;
      moderationFlags = moderated.moderationFlags;
    } else {
      audioUrl = readOptionalUrl(payload.audioUrl);
      audioPath = readRequiredString(payload.audioPath, "audioPath", 300);
      await validateUploadedStorageFile({
        path: audioPath,
        ownerPrefix: `chat_voice_notes/${chatId}/`,
        maxBytes: 25 * 1024 * 1024,
        contentTypePattern: AUDIO_CONTENT_TYPE_REGEX,
      });
    }

    const messageRef = chatRef.collection("messages").doc();
    const recipientIds = participants.filter((entry) => entry !== userId);
    const unreadUpdates = recipientIds.reduce<Record<string, unknown>>(
      (accumulator, recipientId) => {
        accumulator[`unreadCounts.${recipientId}`] =
          admin.firestore.FieldValue.increment(1);
        return accumulator;
      },
      {}
    );

    await db.runTransaction(async (tx) => {
      tx.set(messageRef, {
        senderId: userId,
        type,
        text: type === "text" ? text : "",
        audioUrl: type === "voice" ? audioUrl : null,
        audioPath: type === "voice" ? audioPath : null,
        timestamp: nowServerTs(),
        status: "sent",
        reactions: {},
        deletedFor: [],
        moderationStatus,
        moderationFlags,
      });
      tx.set(chatRef, {
        lastMessage: type === "voice" ? "Voice note" : text,
        lastMessageTime: nowServerTs(),
        updatedAt: nowServerTs(),
        ...unreadUpdates,
      }, {merge: true});
    });

    const senderName = readTrimmedString(
      userProfile.fullName ?? userProfile.displayName,
      120
    );
    if (senderName) {
      await chatRef.set({
        participantNames: {
          [userId]: senderName,
        },
      }, {merge: true});
    }

    return {messageId: messageRef.id};
  }
);

export const sendFriendRequest = secureCommunityCall<
  JsonMap,
  {requestId: string}
>(
  {
    action: "community.send_friend_request",
    analyticsEvent: "community_friend_request",
    rateLimitProfile: "writeHeavy",
  },
  async (request) => {
    const payload = requireObjectPayload(request.data);
    assertNoUnexpectedFields(payload, ["toUserId"]);

    const userId = request.auth!.uid;
    const toUserId = readRequiredString(payload.toUserId, "toUserId", 120);
    if (toUserId === userId) {
      throw new HttpsError("invalid-argument", "toUserId is invalid.");
    }

    const [targetSnap, friendshipSnap, existingRequestSnap] = await Promise.all([
      db.collection("users").doc(toUserId).get(),
      db.collection("users").doc(userId).collection("friends").doc(toUserId).get(),
      db.collection("friend_requests")
        .where("fromUserID", "==", userId)
        .where("toUserID", "==", toUserId)
        .where("status", "==", "pending")
        .limit(1)
        .get(),
    ]);

    if (!targetSnap.exists) {
      throw new HttpsError("not-found", "User could not be found.");
    }
    if (friendshipSnap.exists) {
      throw new HttpsError("already-exists", "You are already friends.");
    }
    if (!existingRequestSnap.empty) {
      return {requestId: existingRequestSnap.docs[0].id};
    }

    const requestRef = db.collection("friend_requests").doc();
    await requestRef.set({
      fromUserID: userId,
      toUserID: toUserId,
      status: "pending",
      createdAt: nowServerTs(),
      updatedAt: nowServerTs(),
    });

    return {requestId: requestRef.id};
  }
);

export const respondToFriendRequest = secureCommunityCall<
  JsonMap,
  {status: string}
>(
  {
    action: "community.respond_friend_request",
    analyticsEvent: "community_friend_response",
    rateLimitProfile: "writeHeavy",
  },
  async (request) => {
    const payload = requireObjectPayload(request.data);
    assertNoUnexpectedFields(payload, ["requestId", "action"]);

    const userId = request.auth!.uid;
    const requestId = readRequiredString(payload.requestId, "requestId", 120);
    const action = readRequiredString(payload.action, "action", 16).toLowerCase();
    if (!["accept", "decline"].includes(action)) {
      throw new HttpsError("invalid-argument", "action is invalid.");
    }

    const requestRef = db.collection("friend_requests").doc(requestId);
    const requestSnap = await requestRef.get();
    if (!requestSnap.exists) {
      throw new HttpsError("not-found", "Friend request could not be found.");
    }

    const requestData = requestSnap.data() ?? {};
    const fromUserId = readRequiredString(
      requestData.fromUserID,
      "fromUserID",
      120
    );
    const toUserId = readRequiredString(requestData.toUserID, "toUserID", 120);
    const currentStatus = readTrimmedString(requestData.status, 32).toLowerCase();

    if (toUserId !== userId) {
      throw new HttpsError("permission-denied", "Friend request access is invalid.");
    }
    if (currentStatus !== "pending") {
      return {status: currentStatus || "pending"};
    }

    const nextStatus = action === "accept" ? "accepted" : "rejected";
    const currentUserFriendRef = db
      .collection("users")
      .doc(userId)
      .collection("friends")
      .doc(fromUserId);
    const requesterFriendRef = db
      .collection("users")
      .doc(fromUserId)
      .collection("friends")
      .doc(userId);

    await db.runTransaction(async (tx) => {
      tx.update(requestRef, {
        status: nextStatus,
        respondedAt: nowServerTs(),
        updatedAt: nowServerTs(),
      });

      if (nextStatus === "accepted") {
        tx.set(currentUserFriendRef, {
          addedAt: nowServerTs(),
          friendId: fromUserId,
        }, {merge: true});
        tx.set(requesterFriendRef, {
          addedAt: nowServerTs(),
          friendId: userId,
        }, {merge: true});
      }
    });

    return {status: nextStatus};
  }
);

export const markChatRead = secureCommunityCall<JsonMap, {updated: true}>(
  {
    action: "community.mark_chat_read",
    analyticsEvent: "community_chat_read",
    rateLimitProfile: "chat",
  },
  async (request) => {
    const payload = requireObjectPayload(request.data);
    assertNoUnexpectedFields(payload, ["chatId"]);

    const userId = request.auth!.uid;
    const chatId = readRequiredString(payload.chatId, "chatId", 120);
    const chatRef = db.collection("chats").doc(chatId);
    const chatSnap = await chatRef.get();
    if (!chatSnap.exists) {
      throw new HttpsError("not-found", "Chat could not be found.");
    }
    const chatData = chatSnap.data() ?? {};
    const participants = Array.isArray(chatData.participants) ?
      chatData.participants.map((entry) => String(entry)) :
      [];
    if (!participants.includes(userId)) {
      throw new HttpsError("permission-denied", "Chat access is invalid.");
    }

    await chatRef.set({
      unreadCounts: {
        [userId]: 0,
      },
      updatedAt: nowServerTs(),
    }, {merge: true});

    return {updated: true};
  }
);

export const toggleChatReaction = secureCommunityCall<
  JsonMap,
  {reacted: boolean}
>(
  {
    action: "community.toggle_chat_reaction",
    analyticsEvent: "community_chat_reaction",
    rateLimitProfile: "chat",
  },
  async (request) => {
    const payload = requireObjectPayload(request.data);
    assertNoUnexpectedFields(payload, ["chatId", "messageId", "emoji"]);

    const userId = request.auth!.uid;
    const chatId = readRequiredString(payload.chatId, "chatId", 120);
    const messageId = readRequiredString(payload.messageId, "messageId", 120);
    const emoji = readRequiredString(payload.emoji, "emoji", 12);
    if (!ALLOWED_CHAT_REACTIONS.has(emoji)) {
      throw new HttpsError("invalid-argument", "emoji is invalid.");
    }

    const chatRef = db.collection("chats").doc(chatId);
    const messageRef = chatRef.collection("messages").doc(messageId);
    const [chatSnap, messageSnap] = await Promise.all([
      chatRef.get(),
      messageRef.get(),
    ]);
    if (!chatSnap.exists || !messageSnap.exists) {
      throw new HttpsError("not-found", "Chat message could not be found.");
    }

    const chatData = chatSnap.data() ?? {};
    const participants = Array.isArray(chatData.participants) ?
      chatData.participants.map((entry) => String(entry)) :
      [];
    if (!participants.includes(userId)) {
      throw new HttpsError("permission-denied", "Chat access is invalid.");
    }

    const messageData = messageSnap.data() ?? {};
    const reactions = (messageData.reactions ?? {}) as Record<string, unknown>;
    const existing = Array.isArray(reactions[emoji]) ?
      reactions[emoji].map((entry) => String(entry)) :
      [];
    const reacted = !existing.includes(userId);

    await messageRef.set({
      reactions: {
        [emoji]: reacted ?
          admin.firestore.FieldValue.arrayUnion(userId) :
          admin.firestore.FieldValue.arrayRemove(userId),
      },
      updatedAt: nowServerTs(),
    }, {merge: true});

    return {reacted};
  }
);

export const deleteChatMessage = secureCommunityCall<
  JsonMap,
  {deleted: true}
>(
  {
    action: "community.delete_chat_message",
    analyticsEvent: "community_chat_delete",
    rateLimitProfile: "chat",
  },
  async (request) => {
    const payload = requireObjectPayload(request.data);
    assertNoUnexpectedFields(payload, ["chatId", "messageId"]);

    const userId = request.auth!.uid;
    const chatId = readRequiredString(payload.chatId, "chatId", 120);
    const messageId = readRequiredString(payload.messageId, "messageId", 120);
    const chatRef = db.collection("chats").doc(chatId);
    const messageRef = chatRef.collection("messages").doc(messageId);
    const [chatSnap, messageSnap] = await Promise.all([
      chatRef.get(),
      messageRef.get(),
    ]);
    if (!chatSnap.exists || !messageSnap.exists) {
      throw new HttpsError("not-found", "Chat message could not be found.");
    }

    const chatData = chatSnap.data() ?? {};
    const participants = Array.isArray(chatData.participants) ?
      chatData.participants.map((entry) => String(entry)) :
      [];
    if (!participants.includes(userId)) {
      throw new HttpsError("permission-denied", "Chat access is invalid.");
    }

    const messageData = messageSnap.data() ?? {};
    const senderId = readTrimmedString(messageData.senderId, 120);
    if (senderId == userId) {
      await messageRef.delete();
      return {deleted: true};
    }

    await messageRef.set({
      deletedFor: admin.firestore.FieldValue.arrayUnion(userId),
      updatedAt: nowServerTs(),
    }, {merge: true});
    return {deleted: true};
  }
);

export const toggleHelpfulReaction = secureCommunityCall<
  JsonMap,
  {reacted: boolean}
>(
  {
    action: "community.toggle_helpful_reaction",
    analyticsEvent: "community_helpful_reaction",
    rateLimitProfile: "writeHeavy",
  },
  async (request) => {
    const payload = requireObjectPayload(request.data);
    assertNoUnexpectedFields(payload, ["postId"]);

    const userId = request.auth!.uid;
    const postId = readRequiredString(payload.postId, "postId", 120);
    const postRef = db.collection("posts").doc(postId);
    const postSnap = await postRef.get();
    if (!postSnap.exists) {
      throw new HttpsError("not-found", "Post could not be found.");
    }

    const helpfulRef = postRef.collection("helpful_users").doc(userId);
    const helpfulSnap = await helpfulRef.get();
    const reacted = !helpfulSnap.exists;

    await db.runTransaction(async (tx) => {
      if (reacted) {
        tx.set(helpfulRef, {
          timestamp: nowServerTs(),
          userId,
        });
        tx.update(postRef, {
          likes: admin.firestore.FieldValue.increment(1),
          updatedAt: nowServerTs(),
        });
        return;
      }

      tx.delete(helpfulRef);
      tx.update(postRef, {
        likes: admin.firestore.FieldValue.increment(-1),
        updatedAt: nowServerTs(),
      });
    });

    return {reacted};
  }
);

export const updateProfileSecure = secureCommunityCall<
  JsonMap,
  {updated: true}
>(
  {
    action: "community.update_profile",
    analyticsEvent: "profile_update",
    rateLimitProfile: "writeHeavy",
  },
  async (request) => {
    const payload = requireObjectPayload(request.data);
    assertNoUnexpectedFields(payload, [
      "fullName",
      "middleName",
      "age",
      "major",
      "levelOfStudy",
      "bio",
      "profilePicUrl",
      "profilePicPath",
    ]);

    const userId = request.auth!.uid;
    const updates: JsonMap = {};

    const fullName = readTrimmedString(payload.fullName, 120);
    if (fullName) {
      updates.fullName = fullName;
      updates.fullNameLowercase = fullName.toLowerCase();
    }

    const middleName = readTrimmedString(payload.middleName, 120);
    if (payload.middleName != null) {
      updates.middleName = middleName;
    }

    if (payload.age != null) {
      updates.age = Math.round(readPositiveNumber(payload.age, "age", {max: 120}));
    }

    const major = readTrimmedString(payload.major, 120);
    if (payload.major != null) {
      updates.major = major;
    }

    const levelOfStudy = readTrimmedString(payload.levelOfStudy, 40);
    if (payload.levelOfStudy != null) {
      updates.levelOfStudy = levelOfStudy;
    }

    if (payload.bio != null) {
      const moderated = await applyModerationOrThrow({
        action: "community.update_profile",
        actorUid: userId,
        contentType: "profile_bio",
        text: readTrimmedString(payload.bio, 600),
        maxLength: 600,
        fingerprintAction: "profile_bio",
      });
      updates.bio = moderated.sanitizedText;
      updates.bioModerationStatus = moderated.moderationStatus;
      updates.bioModerationFlags = moderated.moderationFlags;
    }

    const profilePicPath = readTrimmedString(payload.profilePicPath, 200);
    const profilePicUrl = readOptionalUrl(payload.profilePicUrl);
    if (profilePicPath) {
      await validateUploadedStorageFile({
        path: profilePicPath,
        ownerPrefix: `profile_pics/${userId}.jpg`,
        maxBytes: 5 * 1024 * 1024,
        contentTypePattern: IMAGE_CONTENT_TYPE_REGEX,
      });
      updates.profilePic = profilePicUrl || null;
      updates.profilePicPath = profilePicPath;
    }

    if (Object.keys(updates).length == 0) {
      return {updated: true};
    }
    updates.updatedAt = nowServerTs();
    updates.emailVerified = request.auth?.token.email_verified === true;
    await db.collection("users").doc(userId).set(updates, {merge: true});
    return {updated: true};
  }
);

export const createStudyVaultResource = secureCommunityCall<
  JsonMap,
  {resourceId: string}
>(
  {
    action: "community.create_study_vault_resource",
    analyticsEvent: "study_vault_publish",
    rateLimitProfile: "upload",
  },
  async (request) => {
    const payload = requireObjectPayload(request.data);
    assertNoUnexpectedFields(payload, [
      "title",
      "description",
      "subject",
      "moduleCode",
      "moduleName",
      "courseName",
      "institute",
      "academicYear",
      "resourceType",
      "accessType",
      "priceZar",
      "fileUrl",
      "filePath",
      "fileName",
    ]);

    const userId = request.auth!.uid;
    const userProfile = await resolveUserProfile(userId);
    const title = readRequiredString(payload.title, "title", 140);
    const description = readTrimmedString(payload.description, 2500);
    const subject = readRequiredString(payload.subject, "subject", 80).toUpperCase();
    const moduleCode = readTrimmedString(payload.moduleCode, 40).toUpperCase();
    const moduleName = readTrimmedString(payload.moduleName, 120);
    const courseName = readTrimmedString(payload.courseName, 120);
    const institute = readTrimmedString(payload.institute, 120);
    const academicYear = readTrimmedString(payload.academicYear, 12);
    const resourceType = readRequiredString(payload.resourceType, "resourceType", 40);
    const accessType = readRequiredString(payload.accessType, "accessType", 10).toLowerCase();
    if (!["free", "paid"].includes(accessType)) {
      throw new HttpsError("invalid-argument", "accessType is invalid.");
    }

    const priceZar = Math.round(readPositiveNumber(payload.priceZar, "priceZar", {
      optional: true,
      max: 5_000,
    }));
    const fileUrl = readOptionalUrl(payload.fileUrl);
    const filePath = readRequiredString(payload.filePath, "filePath", 300);
    const fileName = readRequiredString(payload.fileName, "fileName", 160);
    await validateUploadedStorageFile({
      path: filePath,
      ownerPrefix: `study_vault/${userId}_`,
      maxBytes: 30 * 1024 * 1024,
      contentTypePattern: PDF_CONTENT_TYPE_REGEX,
    });

    const moderated = await applyModerationOrThrow({
      action: "community.create_study_vault_resource",
      actorUid: userId,
      contentType: "study_vault",
      text: [title, description, moduleCode, moduleName, courseName].join(" "),
      maxLength: 3000,
      fingerprintAction: "study_vault_resource",
      metadata: {resourceType, accessType},
    });

    const fees = computeStudyVaultFees(accessType === "paid" ? priceZar : 0);
    const uploaderName = readTrimmedString(
      userProfile.fullName ?? userProfile.displayName,
      120
    ) || "Student";
    const resourceRef = db.collection("vault").doc();
    await resourceRef.set({
      userId,
      ownerId: userId,
      uploaderId: userId,
      uploaderName,
      title,
      description,
      previewText: description,
      subject,
      moduleCode,
      moduleName,
      courseName,
      institute,
      year: academicYear,
      academicYear,
      type: resourceType,
      resourceType,
      accessType,
      isPaid: accessType === "paid",
      priceZar: accessType === "paid" ? priceZar : 0,
      currency: "ZAR",
      platformCommissionPercent: STUDY_VAULT_COMMISSION_PERCENT,
      platformFeeZar: accessType === "paid" ? fees.platformFeeZar : 0,
      sellerNetZar: accessType === "paid" ? fees.sellerNetZar : 0,
      fileUrl,
      filePath,
      fileName,
      stars: 0,
      starredBy: [],
      purchaseCount: 0,
      purchasedBy: [],
      status: "active",
      searchIndex: [title, subject, moduleCode, moduleName, courseName, institute, academicYear, resourceType, description]
        .join(" ")
        .toLowerCase(),
      moderationStatus: moderated.moderationStatus,
      moderationFlags: moderated.moderationFlags,
      createdAt: nowServerTs(),
      updatedAt: nowServerTs(),
    });

    return {resourceId: resourceRef.id};
  }
);

export const searchTutorsSecure = secureCommunityCall<
  JsonMap,
  {items: JsonMap[]}
>(
  {
    action: "community.search_tutors",
    analyticsEvent: "tutor_search",
    rateLimitProfile: "search",
  },
  async (request) => {
    const payload = requireObjectPayload(request.data);
    assertNoUnexpectedFields(payload, [
      "subject",
      "maxPrice",
      "availability",
      "minRating",
      "limit",
    ]);

    const subject = readRequiredString(payload.subject, "subject", 80)
      .toLowerCase();
    const maxPrice = payload.maxPrice == null ?
      null :
      readPositiveNumber(payload.maxPrice, "maxPrice", {max: 5_000});
    const minRating = payload.minRating == null ?
      null :
      readPositiveNumber(payload.minRating, "minRating", {max: 10});
    const limit = Math.max(
      1,
      Math.min(40, Math.round(readPositiveNumber(payload.limit, "limit", {
        optional: true,
        max: 40,
      }) || 20))
    );
    const availability = toStringList(payload.availability, 3)
      .map((item) => item.toLowerCase())
      .filter((item) => ALLOWED_TUTOR_AVAILABILITY.has(item));

    const candidateLimit = limit < 50 ? limit * 3 : limit;
    const snap = await db
      .collection("tutor_search_profiles")
      .where("tutoringSearchVisible", "==", true)
      .where("subjects", "array-contains", subject)
      .orderBy("searchScore", "desc")
      .limit(candidateLimit)
      .get();

    const items = snap.docs
      .map((doc) => ({id: doc.id, ...doc.data()}) as JsonMap)
      .filter((entry) => {
        const totalRate = Number(entry.studentRatePerMinuteZar ?? 0);
        const ratingAverage = Number(entry.ratingAverage ?? 0);
        const availabilityValue = String(entry.availability ?? "").toLowerCase();
        if (maxPrice != null && totalRate > maxPrice) return false;
        if (minRating != null && ratingAverage < minRating) return false;
        if (availability.length > 0 && !availability.includes(availabilityValue)) {
          return false;
        }
        return true;
      })
      .slice(0, limit);

    return {items};
  }
);
