"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateSignedReadUrl = generateSignedReadUrl;
exports.downloadFileFromSignedUrl = downloadFileFromSignedUrl;
exports.uploadBufferToStorage = uploadBufferToStorage;
const firebase_1 = require("./firebase");
function parseGsPath(gsPath) {
    const trimmed = gsPath.trim();
    if (trimmed.startsWith('gs://')) {
        const withoutScheme = trimmed.slice('gs://'.length);
        const [bucket, ...rest] = withoutScheme.split('/');
        if (!bucket || rest.length === 0) {
            throw new Error('gsPath must include bucket and object: gs://bucket/path');
        }
        return { bucket, object: rest.join('/') };
    }
    const object = trimmed.replace(/^\/+/, '');
    if (!object) {
        throw new Error('gsPath must include an object path.');
    }
    return { object };
}
function getBucket(parsed) {
    const storage = (0, firebase_1.getStorage)();
    const bucket = parsed.bucket ? storage.bucket(parsed.bucket) : storage.bucket();
    if (!bucket.name) {
        throw new Error('Storage bucket not configured. Provide gs://bucket/... or set STORAGE_BUCKET.');
    }
    return bucket;
}
async function generateSignedReadUrl(gsPath, expiresInMinutes) {
    const parsed = parseGsPath(gsPath);
    const bucket = getBucket(parsed);
    const file = bucket.file(parsed.object);
    const expiresMs = Math.max(expiresInMinutes, 1) * 60 * 1000;
    const [url] = await file.getSignedUrl({
        action: 'read',
        expires: Date.now() + expiresMs,
    });
    return url;
}
async function downloadFileFromSignedUrl(url) {
    const response = await fetch(url);
    if (!response.ok) {
        throw new Error(`Failed to download file: ${response.status} ${response.statusText}`);
    }
    const arrayBuffer = await response.arrayBuffer();
    return Buffer.from(arrayBuffer);
}
async function uploadBufferToStorage(buffer, gsPath, contentType) {
    const parsed = parseGsPath(gsPath);
    const bucket = getBucket(parsed);
    const file = bucket.file(parsed.object);
    await file.save(buffer, {
        resumable: false,
        contentType,
        metadata: { contentType },
    });
    return `gs://${bucket.name}/${parsed.object}`;
}
