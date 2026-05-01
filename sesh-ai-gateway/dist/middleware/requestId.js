"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.requestId = requestId;
const node_crypto_1 = require("node:crypto");
function requestId(req, res, next) {
    const inbound = req.header('x-request-id') || req.header('x-correlation-id');
    const id = inbound && inbound.trim().length > 0 ? inbound.trim() : (0, node_crypto_1.randomUUID)();
    req.requestId = id;
    res.setHeader('x-request-id', id);
    next();
}
