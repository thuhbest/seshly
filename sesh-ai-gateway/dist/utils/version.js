"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.getVersionInfo = getVersionInfo;
const node_fs_1 = __importDefault(require("node:fs"));
const node_path_1 = __importDefault(require("node:path"));
const env_1 = require("./env");
let cached = null;
function getVersionInfo() {
    if (cached) {
        return cached;
    }
    const revision = process.env.K_REVISION || process.env.GIT_SHA || null;
    let version = process.env.SERVICE_VERSION || '';
    if (!version) {
        try {
            const packagePath = node_path_1.default.resolve(__dirname, '..', '..', 'package.json');
            const raw = node_fs_1.default.readFileSync(packagePath, 'utf8');
            const pkg = JSON.parse(raw);
            version = pkg.version || 'unknown';
        }
        catch {
            version = 'unknown';
        }
    }
    cached = {
        service: env_1.config.serviceName,
        version,
        revision,
    };
    return cached;
}
