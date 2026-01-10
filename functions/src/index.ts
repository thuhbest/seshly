import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
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
  const userRef = db.collection("users").doc(data.userId);

  return db.runTransaction(async (transaction) => {
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
