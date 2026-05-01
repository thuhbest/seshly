"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.appCheck = appCheck;
const firebase_1 = require("../services/firebase");
const env_1 = require("../utils/env");
async function appCheck(req, res, next) {
    const token = req.header('x-firebase-appcheck') || req.header('x-firebase-app-check') || '';
    if (!token) {
        if (env_1.config.requireAppCheck) {
            res.status(401).json({
                error: 'app_check_required',
                message: 'App integrity verification is required for this request.',
            });
            return;
        }
        next();
        return;
    }
    try {
        await (0, firebase_1.getFirebaseApp)().appCheck().verifyToken(token);
        req.appCheckVerified = true;
        next();
    }
    catch (error) {
        console.error('App Check verification failed', error);
        res.status(401).json({
            error: 'invalid_app_check',
            message: 'App integrity verification failed.',
        });
    }
}
