"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.requestLogger = requestLogger;
const firebase_admin_1 = __importDefault(require("firebase-admin"));
const firebase_1 = require("../services/firebase");
const env_1 = require("../utils/env");
function requestLogger(req, res, next) {
    const start = Date.now();
    res.on('finish', () => {
        const durationMs = Date.now() - start;
        const payload = {
            requestId: req.requestId || null,
            path: req.originalUrl,
            method: req.method,
            status: res.statusCode,
            durationMs,
            userId: req.user?.uid || null,
            ip: req.ip,
            userAgent: req.header('user-agent') || null,
            createdAt: firebase_admin_1.default.firestore.FieldValue.serverTimestamp(),
        };
        void (0, firebase_1.getFirestore)()
            .collection(env_1.config.logCollection)
            .add(payload)
            .catch((error) => {
            console.error('Failed to log request', error);
        });
    });
    next();
}
