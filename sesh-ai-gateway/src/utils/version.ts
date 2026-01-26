import fs from 'node:fs';
import path from 'node:path';

import { config } from './env';

type VersionInfo = {
  service: string;
  version: string;
  revision: string | null;
};

let cached: VersionInfo | null = null;

export function getVersionInfo(): VersionInfo {
  if (cached) {
    return cached;
  }

  const revision = process.env.K_REVISION || process.env.GIT_SHA || null;
  let version = process.env.SERVICE_VERSION || '';

  if (!version) {
    try {
      const packagePath = path.resolve(__dirname, '..', '..', 'package.json');
      const raw = fs.readFileSync(packagePath, 'utf8');
      const pkg = JSON.parse(raw) as { version?: string };
      version = pkg.version || 'unknown';
    } catch {
      version = 'unknown';
    }
  }

  cached = {
    service: config.serviceName,
    version,
    revision,
  };

  return cached;
}
