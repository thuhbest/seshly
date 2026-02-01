import admin from 'firebase-admin';

let app: admin.app.App | null = null;
let firestore: admin.firestore.Firestore | null = null;
let storage: admin.storage.Storage | null = null;

const projectId =
  process.env.FIREBASE_PROJECT_ID ||
  process.env.GOOGLE_PROJECT_ID ||
  process.env.GOOGLE_CLOUD_PROJECT ||
  process.env.GCLOUD_PROJECT;
const storageBucket =
  process.env.FIREBASE_STORAGE_BUCKET ||
  process.env.STORAGE_BUCKET ||
  process.env.GCLOUD_STORAGE_BUCKET ||
  undefined;

export function getFirebaseApp(): admin.app.App {
  if (!app) {
    app = admin.apps.length
      ? admin.app()
      : admin.initializeApp({
          // applicationDefault() uses GOOGLE_APPLICATION_CREDENTIALS locally
          // and Workload Identity / metadata server on GCP.
          credential: admin.credential.applicationDefault(),
          projectId,
          storageBucket,
        });
  }

  return app;
}

export function getFirestore(): admin.firestore.Firestore {
  if (!firestore) {
    firestore = getFirebaseApp().firestore();
    firestore.settings({ ignoreUndefinedProperties: true });
  }

  return firestore;
}

export function getAuth(): admin.auth.Auth {
  return getFirebaseApp().auth();
}

export function getStorage(): admin.storage.Storage {
  if (!storage) {
    storage = getFirebaseApp().storage();
  }

  return storage;
}
