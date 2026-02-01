import { getStorage } from './firebase';

type ParsedGsPath = {
  bucket?: string;
  object: string;
};

function parseGsPath(gsPath: string): ParsedGsPath {
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

function getBucket(parsed: ParsedGsPath) {
  const storage = getStorage();
  const bucket = parsed.bucket ? storage.bucket(parsed.bucket) : storage.bucket();
  if (!bucket.name) {
    throw new Error('Storage bucket not configured. Provide gs://bucket/... or set STORAGE_BUCKET.');
  }
  return bucket;
}

export async function generateSignedReadUrl(
  gsPath: string,
  expiresInMinutes: number,
): Promise<string> {
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

export async function downloadFileFromSignedUrl(url: string): Promise<Buffer> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to download file: ${response.status} ${response.statusText}`);
  }
  const arrayBuffer = await response.arrayBuffer();
  return Buffer.from(arrayBuffer);
}

export async function uploadBufferToStorage(
  buffer: Buffer,
  gsPath: string,
  contentType: string,
): Promise<string> {
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
