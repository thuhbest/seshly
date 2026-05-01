"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.callTextModel = callTextModel;
exports.callEmbeddingModel = callEmbeddingModel;
const env_1 = require("../utils/env");
function assertApiKey(provider, apiKey) {
    if (!apiKey) {
        throw new Error(`${provider} API key is missing`);
    }
}
async function fetchWithTimeout(input, init) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), env_1.config.request.timeoutMs);
    try {
        return await fetch(input, {
            ...init,
            signal: controller.signal,
        });
    }
    finally {
        clearTimeout(timeout);
    }
}
async function callOpenAi(options) {
    const apiKey = env_1.config.model.openai.apiKey;
    assertApiKey('openai', apiKey);
    const baseUrl = env_1.config.model.openai.baseUrl.replace(/\/+$/, '');
    const body = {
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
async function callGoogle(options) {
    const apiKey = env_1.config.model.google.apiKey;
    assertApiKey('google', apiKey);
    const system = options.messages.find((m) => m.role === 'system')?.content;
    const contents = options.messages
        .filter((m) => m.role !== 'system')
        .map((m) => ({
        role: m.role === 'assistant' ? 'model' : 'user',
        parts: [{ text: m.content }],
    }));
    const body = {
        contents,
        generationConfig: {
            temperature: options.temperature ?? 0,
        },
    };
    if (typeof options.maxTokens === 'number') {
        body.generationConfig = {
            ...body.generationConfig,
            maxOutputTokens: options.maxTokens,
        };
    }
    if (system) {
        body.systemInstruction = { parts: [{ text: system }] };
    }
    if (options.jsonOnly) {
        body.generationConfig = {
            ...body.generationConfig,
            responseMimeType: 'application/json',
        };
    }
    const response = await fetchWithTimeout(`https://generativelanguage.googleapis.com/v1beta/models/${options.model}:generateContent?key=${apiKey}`, {
        method: 'POST',
        headers: {
            'content-type': 'application/json',
        },
        body: JSON.stringify(body),
    });
    if (!response.ok) {
        const text = await response.text();
        throw new Error(`Google model error ${response.status}: ${text}`);
    }
    const data = await response.json();
    return data?.candidates?.[0]?.content?.parts?.[0]?.text?.trim() ?? '';
}
async function callTextModel(options) {
    if (options.provider === 'openai') {
        return callOpenAi(options);
    }
    return callGoogle(options);
}
async function callOpenAiEmbedding(options) {
    const apiKey = env_1.config.model.openai.apiKey;
    assertApiKey('openai', apiKey);
    const baseUrl = env_1.config.model.openai.baseUrl.replace(/\/+$/, '');
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
    return Array.isArray(embedding) ? embedding.map((value) => Number(value)) : [];
}
async function callGoogleEmbedding(options) {
    const apiKey = env_1.config.model.google.apiKey;
    assertApiKey('google', apiKey);
    const response = await fetchWithTimeout(`https://generativelanguage.googleapis.com/v1beta/models/${options.model}:embedContent?key=${apiKey}`, {
        method: 'POST',
        headers: {
            'content-type': 'application/json',
        },
        body: JSON.stringify({
            content: {
                parts: [{ text: options.input }],
            },
        }),
    });
    if (!response.ok) {
        const text = await response.text();
        throw new Error(`Google embedding error ${response.status}: ${text}`);
    }
    const data = await response.json();
    const embedding = data?.embedding?.values;
    return Array.isArray(embedding) ? embedding.map((value) => Number(value)) : [];
}
async function callEmbeddingModel(options) {
    if (options.provider === 'openai') {
        return callOpenAiEmbedding(options);
    }
    return callGoogleEmbedding(options);
}
