"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const authVerifyFirebaseIdToken_1 = require("./middleware/authVerifyFirebaseIdToken");
const rateLimit_1 = require("./middleware/rateLimit");
const requestId_1 = require("./middleware/requestId");
const logging_1 = require("./middleware/logging");
const aiPolicy_1 = __importDefault(require("./routes/aiPolicy"));
const aiChat_1 = __importDefault(require("./routes/aiChat"));
const aiNotes_1 = __importDefault(require("./routes/aiNotes"));
const health_1 = require("./routes/health");
const env_1 = require("./utils/env");
const app = (0, express_1.default)();
app.disable('x-powered-by');
app.use(express_1.default.json({ limit: '1mb' }));
app.use(requestId_1.requestId);
app.use(logging_1.logging);
app.use(health_1.healthRouter);
app.use(authVerifyFirebaseIdToken_1.authVerifyFirebaseIdToken);
app.use(rateLimit_1.rateLimit);
app.use(aiPolicy_1.default);
app.use(aiChat_1.default);
app.use(aiNotes_1.default);
app.get('/', (req, res) => {
    res.json({ ok: true, message: 'sesh-ai-gateway ready', requestId: req.requestId });
});
app.use((req, res) => {
    res.status(404).json({ error: 'not_found' });
});
app.use((err, _req, res, _next) => {
    console.error('Unhandled error', err);
    res.status(500).json({ error: 'internal_error' });
});
app.listen(env_1.config.port, () => {
    console.log(`[sesh-ai-gateway] listening on ${env_1.config.port}`);
});
