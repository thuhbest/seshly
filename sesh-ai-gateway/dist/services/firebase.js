"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.getFirebaseApp = getFirebaseApp;
exports.getFirestore = getFirestore;
exports.getAuth = getAuth;
exports.getStorage = getStorage;
const firebase_admin_1 = __importDefault(require("firebase-admin"));
let app = null;
let firestore = null;
let storage = null;
const projectId = process.env.FIREBASE_PROJECT_ID ||
    process.env.GOOGLE_CLOUD_PROJECT ||
    process.env.GCLOUD_PROJECT;
const storageBucket = process.env.FIREBASE_STORAGE_BUCKET ||
    process.env.STORAGE_BUCKET ||
    process.env.GCLOUD_STORAGE_BUCKET ||
    undefined;
function getFirebaseApp() {
    if (!app) {
        app = firebase_admin_1.default.apps.length
            ? firebase_admin_1.default.app()
            : firebase_admin_1.default.initializeApp({
                // applicationDefault() uses GOOGLE_APPLICATION_CREDENTIALS locally
                // and Workload Identity / metadata server on GCP.
                credential: firebase_admin_1.default.credential.applicationDefault(),
                projectId,
                storageBucket,
            });
    }
    return app;
}
function getFirestore() {
    if (!firestore) {
        firestore = getFirebaseApp().firestore();
        firestore.settings({ ignoreUndefinedProperties: true });
    }
    return firestore;
}
function getAuth() {
    return getFirebaseApp().auth();
}
function getStorage() {
    if (!storage) {
        storage = getFirebaseApp().storage();
    }
    return storage;
}
