import { config, type ModelProvider } from '../utils/env';

export type ModelMessage = {
  role: 'system' | 'user' | 'assistant';
  content: string;
};

export type CallTextModelOptions = {
  provider: ModelProvider;
  model: string;
  messages: ModelMessage[];
  jsonOnly?: boolean;
  temperature?: number;
  maxTokens?: number;
};

export type CallEmbeddingOptions = {
  provider: ModelProvider;
  model: string;
  input: string;
};

function assertApiKey(provider: ModelProvider, apiKey: string): void {
  if (!apiKey) {
    throw new Error(`${provider} API key is missing`);
  }
}

async function fetchWithTimeout(input: string, init: RequestInit): Promise<Response> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), config.request.timeoutMs);
  try {
    return await fetch(input, {
      ...init,
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timeout);
  }
}

async function callOpenAi(options: CallTextModelOptions): Promise<string> {
  const apiKey = config.model.openai.apiKey;
  assertApiKey('openai', apiKey);
  const baseUrl = config.model.openai.baseUrl.replace(/\/+$/, '');

  const body: Record<string, unknown> = {
    model: options.model,
    messages: options.messages,
    temperature: options.temperature ?? 0,
  };

  if (typeof options.maxTokens === 'number') {
    body.max_tokens = options.maxTokens;
  }

  if (options.jsonOnly) {
    body.response_format = { type: 'json_object' };
  }

  const response = await fetchWithTimeout(`${baseUrl}/chat/completions`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`OpenAI error ${response.status}: ${text}`);
  }

  const data = await response.json();
  return data?.choices?.[0]?.message?.content?.trim() ?? '';
}

async function callGoogle(options: CallTextModelOptions): Promise<string> {
  const apiKey = config.model.google.apiKey;
  assertApiKey('google', apiKey);
  const system = options.messages.find((m) => m.role === 'system')?.content;
  const contents = options.messages
    .filter((m) => m.role !== 'system')
    .map((m) => ({
      role: m.role === 'assistant' ? 'model' : 'user',
      parts: [{ text: m.content }],
    }));

  const body: Record<string, unknown> = {
    contents,
    generationConfig: {
      temperature: options.temperature ?? 0,
    },
  };

  if (typeof options.maxTokens === 'number') {
    body.generationConfig = {
      ...(body.generationConfig as Record<string, unknown>),
      maxOutputTokens: options.maxTokens,
    };
  }

  if (system) {
    body.systemInstruction = { parts: [{ text: system }] };
  }

  if (options.jsonOnly) {
    body.generationConfig = {
      ...(body.generationConfig as Record<string, unknown>),
      responseMimeType: 'application/json',
    };
  }

  const response = await fetchWithTimeout(
    `https://generativelanguage.googleapis.com/v1beta/models/${options.model}:generateContent?key=${apiKey}`,
    {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
      },
      body: JSON.stringify(body),
    },
  );

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Google model error ${response.status}: ${text}`);
  }

  const data = await response.json();
  return data?.candidates?.[0]?.content?.parts?.[0]?.text?.trim() ?? '';
}

export async function callTextModel(options: CallTextModelOptions): Promise<string> {
  if (options.provider === 'openai') {
    return callOpenAi(options);
  }
  return callGoogle(options);
}

async function callOpenAiEmbedding(options: CallEmbeddingOptions): Promise<number[]> {
  const apiKey = config.model.openai.apiKey;
  assertApiKey('openai', apiKey);
  const baseUrl = config.model.openai.baseUrl.replace(/\/+$/, '');

  const response = await fetchWithTimeout(`${baseUrl}/embeddings`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: options.model,
      input: options.input,
    }),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`OpenAI embedding error ${response.status}: ${text}`);
  }

  const data = await response.json();
  const embedding = data?.data?.[0]?.embedding;
  return Array.isArray(embedding) ? embedding.map((value: unknown) => Number(value)) : [];
}

async function callGoogleEmbedding(options: CallEmbeddingOptions): Promise<number[]> {
  const apiKey = config.model.google.apiKey;
  assertApiKey('google', apiKey);

  const response = await fetchWithTimeout(
    `https://generativelanguage.googleapis.com/v1beta/models/${options.model}:embedContent?key=${apiKey}`,
    {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        content: {
          parts: [{ text: options.input }],
        },
      }),
    },
  );

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Google embedding error ${response.status}: ${text}`);
  }

  const data = await response.json();
  const embedding = data?.embedding?.values;
  return Array.isArray(embedding) ? embedding.map((value: unknown) => Number(value)) : [];
}

export async function callEmbeddingModel(options: CallEmbeddingOptions): Promise<number[]> {
  if (options.provider === 'openai') {
    return callOpenAiEmbedding(options);
  }
  return callGoogleEmbedding(options);
}
