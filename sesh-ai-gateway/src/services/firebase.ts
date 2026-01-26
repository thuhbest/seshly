import admin from 'firebase-admin';

let app: admin.app.App | null = null;
let firestore: admin.firestore.Firestore | null = null;

export function getFirebaseApp(): admin.app.App {
  if (!app) {
    app = admin.apps.length
      ? admin.app()
      : admin.initializeApp({
          projectId: process.env.FIREBASE_PROJECT_ID || process.env.GOOGLE_CLOUD_PROJECT,
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
