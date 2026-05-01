"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.admitInFlightRequest = admitInFlightRequest;
exports.releaseInFlightRequest = releaseInFlightRequest;
exports.resetInFlightLimiter = resetInFlightLimiter;
let globalInFlight = 0;
const userInFlight = new Map();
function admitInFlightRequest(params) {
    const currentUser = userInFlight.get(params.userId) ?? 0;
    if (currentUser >= params.maxPerUser || globalInFlight >= params.maxGlobal) {
        return {
            allowed: false,
            globalInFlight,
            userInFlight: currentUser,
        };
    }
    globalInFlight += 1;
    userInFlight.set(params.userId, currentUser + 1);
    return {
        allowed: true,
        globalInFlight,
        userInFlight: currentUser + 1,
        token: { userId: params.userId },
    };
}
function releaseInFlightRequest(token) {
    if (!token)
        return;
    const currentUser = userInFlight.get(token.userId) ?? 0;
    if (currentUser <= 1) {
        userInFlight.delete(token.userId);
    }
    else {
        userInFlight.set(token.userId, currentUser - 1);
    }
    globalInFlight = Math.max(globalInFlight - 1, 0);
}
function resetInFlightLimiter() {
    globalInFlight = 0;
    userInFlight.clear();
}
