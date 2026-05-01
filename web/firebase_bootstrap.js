const firebaseSdkVersion = '10.11.1';

const firebaseServices = Object.freeze([
  {label: 'core', path: 'firebase-app.js', windowVar: 'firebase_core'},
  {label: 'auth', path: 'firebase-auth.js', windowVar: 'firebase_auth'},
  {label: 'storage', path: 'firebase-storage.js', windowVar: 'firebase_storage'},
  {
    label: 'firestore',
    path: 'firebase-firestore.js',
    windowVar: 'firebase_firestore',
  },
  {
    label: 'functions',
    path: 'firebase-functions.js',
    windowVar: 'firebase_functions',
  },
  {
    label: 'analytics',
    path: 'firebase-analytics.js',
    windowVar: 'firebase_analytics',
  },
  {
    label: 'messaging',
    path: 'firebase-messaging.js',
    windowVar: 'firebase_messaging',
  },
]);

const firebaseModuleOrigins = Object.freeze([
  `https://www.gstatic.com/firebasejs/${firebaseSdkVersion}`,
  `https://cdn.jsdelivr.net/npm/firebase@${firebaseSdkVersion}`,
  `https://unpkg.com/firebase@${firebaseSdkVersion}`,
]);

const bootstrapTraceId =
  `web-${Date.now()}-${Math.random().toString(16).slice(2, 10)}`;
const bootstrapLogPrefix = '[firebase-web-bootstrap]';
const moduleLoadTimeoutMs = 4000;

window.flutterfire_web_sdk_version = firebaseSdkVersion;
window.flutterfire_ignore_scripts = firebaseServices.map(
  (service) => service.label,
);

function logInfo(message, extra) {
  if (extra === undefined) {
    console.info(`${bootstrapLogPrefix} trace=${bootstrapTraceId} ${message}`);
    return;
  }
  console.info(
    `${bootstrapLogPrefix} trace=${bootstrapTraceId} ${message}`,
    extra,
  );
}

function logWarn(message, extra) {
  if (extra === undefined) {
    console.warn(`${bootstrapLogPrefix} trace=${bootstrapTraceId} ${message}`);
    return;
  }
  console.warn(
    `${bootstrapLogPrefix} trace=${bootstrapTraceId} ${message}`,
    extra,
  );
}

function clearFirebaseGlobals() {
  for (const service of firebaseServices) {
    delete globalThis[service.windowVar];
  }
}

function normalizeFirebaseModule(service, importedModule) {
  const namespace =
    importedModule && typeof importedModule === 'object' ? importedModule : {};
  const defaultNamespace =
    namespace.default && typeof namespace.default === 'object'
      ? namespace.default
      : null;
  const normalized = {
    ...(defaultNamespace ?? {}),
    ...namespace,
  };

  if (service.label === 'auth') {
    const persistenceFallback =
      normalized.indexedDBLocalPersistence ??
      normalized.browserLocalPersistence ??
      normalized.browserSessionPersistence ??
      normalized.inMemoryPersistence;

    if (!normalized.indexedDBLocalPersistence && persistenceFallback) {
      normalized.indexedDBLocalPersistence = persistenceFallback;
    }
    if (!normalized.browserLocalPersistence && persistenceFallback) {
      normalized.browserLocalPersistence = persistenceFallback;
    }
    if (!normalized.browserSessionPersistence && persistenceFallback) {
      normalized.browserSessionPersistence = persistenceFallback;
    }
  }

  if (Object.keys(normalized).length === 0) {
    throw new Error(`Firebase ${service.label} module exported no bindings.`);
  }

  return normalized;
}

function assignFirebaseGlobal(windowVar, moduleObject) {
  globalThis[windowVar] = moduleObject;
  if (typeof self !== 'undefined') {
    self[windowVar] = moduleObject;
  }
  if (typeof window !== 'undefined') {
    window[windowVar] = moduleObject;
  }
}

async function withTimeout(promise, timeoutMs, description) {
  let timerId;
  try {
    return await Promise.race([
      promise,
      new Promise((_, reject) => {
        timerId = window.setTimeout(() => {
          reject(new Error(`${description} timed out after ${timeoutMs}ms`));
        }, timeoutMs);
      }),
    ]);
  } finally {
    if (timerId !== undefined) {
      window.clearTimeout(timerId);
    }
  }
}

async function loadFirebaseModulesFrom(baseUrl) {
  logInfo(`loading Firebase modules from ${baseUrl}`);
  for (const service of firebaseServices) {
    const importedModule = await withTimeout(
      import(`${baseUrl}/${service.path}`),
      moduleLoadTimeoutMs,
      `Firebase ${service.label} module bootstrap from ${baseUrl}`,
    );
    assignFirebaseGlobal(
      service.windowVar,
      normalizeFirebaseModule(service, importedModule),
    );
  }

  window.__SESHLY_FIREBASE_MODULE_ORIGIN__ = baseUrl;
  logInfo(`loaded Firebase modules from ${baseUrl}`);
}

async function loadFirebaseModules() {
  let lastError;
  for (const baseUrl of firebaseModuleOrigins) {
    clearFirebaseGlobals();
    try {
      await loadFirebaseModulesFrom(baseUrl);
      return;
    } catch (error) {
      lastError = error;
      logWarn(`failed loading Firebase modules from ${baseUrl}`, error);
    }
  }

  throw lastError ?? new Error('Firebase web modules could not be loaded.');
}

function renderBootstrapFailure() {
  const container = document.createElement('div');
  container.style.minHeight = '100vh';
  container.style.display = 'flex';
  container.style.alignItems = 'center';
  container.style.justifyContent = 'center';
  container.style.padding = '24px';
  container.style.background = '#0F142B';
  container.style.color = '#FFFFFF';
  container.style.fontFamily =
    'Inter, system-ui, -apple-system, BlinkMacSystemFont, sans-serif';
  container.style.textAlign = 'center';

  const panel = document.createElement('div');
  panel.style.maxWidth = '420px';

  const title = document.createElement('h1');
  title.textContent = 'Seshly could not load web services';
  title.style.margin = '0 0 12px';
  title.style.fontSize = '24px';
  title.style.fontWeight = '700';

  const description = document.createElement('p');
  description.textContent =
    'Check your connection and try again. If the issue continues, disable blockers for Firebase and refresh.';
  description.style.margin = '0 0 16px';
  description.style.lineHeight = '1.5';
  description.style.color = '#C8D0DD';

  const retryButton = document.createElement('button');
  retryButton.type = 'button';
  retryButton.textContent = 'Retry';
  retryButton.style.border = 'none';
  retryButton.style.borderRadius = '999px';
  retryButton.style.padding = '12px 20px';
  retryButton.style.cursor = 'pointer';
  retryButton.style.fontSize = '15px';
  retryButton.style.fontWeight = '600';
  retryButton.style.background = '#00C09E';
  retryButton.style.color = '#0F142B';
  retryButton.addEventListener('click', () => window.location.reload());

  panel.append(title, description, retryButton);
  container.append(panel);
  document.body.replaceChildren(container);
}

async function startFlutterApp() {
  await new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = 'flutter_bootstrap.js';
    script.async = true;
    script.addEventListener('load', resolve, {once: true});
    script.addEventListener(
      'error',
      () => reject(new Error('Failed to load flutter_bootstrap.js')),
      {once: true},
    );
    document.body.appendChild(script);
  });
  logInfo('Flutter bootstrap loaded');
}

try {
  logInfo('starting web bootstrap');
  await loadFirebaseModules();
  await startFlutterApp();
} catch (error) {
  console.error(
    `${bootstrapLogPrefix} trace=${bootstrapTraceId} fatal bootstrap failure`,
    error,
  );
  renderBootstrapFailure();
}
