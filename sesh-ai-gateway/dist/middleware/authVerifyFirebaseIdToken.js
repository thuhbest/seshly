"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.authVerifyFirebaseIdToken = authVerifyFirebaseIdToken;
const firebase_1 = require("../services/firebase");
async function authVerifyFirebaseIdToken(req, res, next) {
    const header = req.header('authorization') || '';
    const match = header.match(/^Bearer\s+(.+)$/i);
    if (!match) {
        res.status(401).json({ error: 'missing_auth', message: 'Missing Authorization bearer token.' });
        return;
    }
    try {
        const decoded = await (0, firebase_1.getAuth)().verifyIdToken(match[1]);
        req.user = decoded;
        next();
    }
    catch (error) {
        console.error('Auth verification failed', error);
        res.status(401).json({ error: 'invalid_token', message: 'Invalid or expired token.' });
    }
}
