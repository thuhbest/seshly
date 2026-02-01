"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.healthRouter = void 0;
const express_1 = require("express");
const env_1 = require("../utils/env");
const version_1 = require("../utils/version");
exports.healthRouter = (0, express_1.Router)();
exports.healthRouter.get('/health', (_req, res) => {
    res.json({ status: 'ok', service: env_1.config.serviceName, time: new Date().toISOString() });
});
exports.healthRouter.get('/version', (_req, res) => {
    res.json((0, version_1.getVersionInfo)());
});
