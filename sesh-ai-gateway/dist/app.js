"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const cors_1 = __importDefault(require("cors"));
const express_1 = __importDefault(require("express"));
const authVerifyFirebaseIdToken_1 = require("./middleware/authVerifyFirebaseIdToken");
const appCheck_1 = require("./middleware/appCheck");
const payloadGuard_1 = require("./middleware/payloadGuard");
const rateLimit_1 = require("./middleware/rateLimit");
const backpressure_1 = require("./middleware/backpressure");
const costControl_1 = require("./middleware/costControl");
const requestId_1 = require("./middleware/requestId");
const logging_1 = require("./middleware/logging");
const env_1 = require("./utils/env");
const aiPolicy_1 = __importDefault(require("./routes/aiPolicy"));
const aiChat_1 = __importDefault(require("./routes/aiChat"));
const aiClassroomMemory_1 = __importDefault(require("./routes/aiClassroomMemory"));
const aiNotes_1 = __importDefault(require("./routes/aiNotes"));
const aiPractice_1 = __importDefault(require("./routes/aiPractice"));
const aiSession_1 = __importDefault(require("./routes/aiSession"));
const aiCalendar_1 = __importDefault(require("./routes/aiCalendar"));
const aiVault_1 = __importDefault(require("./routes/aiVault"));
const aiTutors_1 = __importDefault(require("./routes/aiTutors"));
const health_1 = require("./routes/health");
const app = (0, express_1.default)();
app.disable('x-powered-by');
app.set('trust proxy', true);
app.use((0, cors_1.default)({
    origin: true,
    credentials: true,
    allowedHeaders: ['content-type', 'authorization', 'x-request-id'],
    methods: ['GET', 'POST', 'OPTIONS'],
}));
app.options('*', (0, cors_1.default)());
app.use(express_1.default.json({ limit: `${env_1.config.request.maxBodyKilobytes}kb` }));
app.use(requestId_1.requestId);
app.use(logging_1.logging);
app.use(payloadGuard_1.payloadGuard);
app.use(health_1.healthRouter);
app.use(authVerifyFirebaseIdToken_1.authVerifyFirebaseIdToken);
app.use(appCheck_1.appCheck);
app.use(rateLimit_1.rateLimit);
app.use(backpressure_1.backpressure);
app.use(costControl_1.costControl);
app.use(aiPolicy_1.default);
app.use(aiChat_1.default);
app.use(aiClassroomMemory_1.default);
app.use(aiNotes_1.default);
app.use(aiPractice_1.default);
app.use(aiSession_1.default);
app.use(aiCalendar_1.default);
app.use(aiVault_1.default);
app.use(aiTutors_1.default);
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
exports.default = app;
