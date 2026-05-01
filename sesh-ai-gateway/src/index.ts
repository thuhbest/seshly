import app from './app';
import { config } from './utils/env';

app.listen(config.port, () => {
  console.log(`[sesh-ai-gateway] listening on ${config.port}`);
});
