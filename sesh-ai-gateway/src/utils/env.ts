export const config = {
  port: Number.parseInt(process.env.PORT || '8080', 10),
  serviceName: process.env.SERVICE_NAME || 'sesh-ai-gateway',
  logCollection: process.env.LOG_COLLECTION || 'ai_logs',
  rateLimitCollection: process.env.RATE_LIMIT_COLLECTION || 'ai_rate_limits',
  rateLimit: {
    windowSeconds: Number.parseInt(process.env.RATE_LIMIT_WINDOW_SECONDS || '60', 10),
    max: Number.parseInt(process.env.RATE_LIMIT_MAX || '60', 10),
  },
};
