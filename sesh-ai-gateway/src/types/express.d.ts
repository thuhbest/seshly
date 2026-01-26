import 'express-serve-static-core';
import type { DecodedIdToken } from 'firebase-admin/auth';

declare module 'express-serve-static-core' {
  interface Request {
    requestId?: string;
    user?: DecodedIdToken;
  }
}
