"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.backpressure = backpressure;
const inFlightLimiter_1 = require("../services/inFlightLimiter");
const env_1 = require("../utils/env");
async function backpressure(req, res, next) {
    const userId = req.user?.uid;
    if (!userId) {
        res.status(401).json({ error: 'missing_user', message: 'User not found for concurrency control.' });
        return;
    }
    const admission = (0, inFlightLimiter_1.admitInFlightRequest)({
        userId,
        maxPerUser: env_1.config.maxInFlightPerUser,
        maxGlobal: env_1.config.maxInFlightGlobal,
    });
    if (!admission.allowed) {
        console.warn('AI backpressure rejection', {
            requestId: req.requestId || null,
            userId,
            globalInFlight: admission.globalInFlight,
            userInFlight: admission.userInFlight,
        });
        res.status(503).json({
            error: 'temporarily_busy',
            message: 'Sesh is handling a lot right now. Please try again in a moment.',
            retryable: true,
        });
        return;
    }
    let released = false;
    const release = () => {
        if (released)
            return;
        released = true;
        (0, inFlightLimiter_1.releaseInFlightRequest)(admission.token);
    };
    res.on('finish', release);
    res.on('close', release);
    res.on('error', release);
    next();
}
