"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.extractTextFromPdf = extractTextFromPdf;
exports.extractTextFromImage = extractTextFromImage;
const documentai_1 = require("@google-cloud/documentai");
const vision_1 = require("@google-cloud/vision");
let docAiClient = null;
let visionClient = null;
function normalizeVertex(vertex) {
    return {
        x: vertex.x === null ? undefined : vertex.x,
        y: vertex.y === null ? undefined : vertex.y,
    };
}
function normalizeVertices(vertices) {
    if (!vertices)
        return undefined;
    return vertices.map((vertex) => normalizeVertex(vertex));
}
function getDocAiConfig() {
    const projectId = process.env.DOC_AI_PROJECT_ID ||
        process.env.GOOGLE_CLOUD_PROJECT ||
        process.env.GCLOUD_PROJECT ||
        process.env.FIREBASE_PROJECT_ID;
    const location = process.env.DOC_AI_LOCATION || 'us';
    const processorId = process.env.DOC_AI_PROCESSOR_ID;
    const processorVersion = process.env.DOC_AI_PROCESSOR_VERSION || undefined;
    const apiEndpoint = process.env.DOC_AI_API_ENDPOINT ||
        (location === 'us' || location === 'eu' ? `${location}-documentai.googleapis.com` : undefined);
    if (!projectId || !processorId) {
        throw new Error('Missing DOC_AI_PROJECT_ID or DOC_AI_PROCESSOR_ID.');
    }
    return { projectId, location, processorId, processorVersion, apiEndpoint };
}
function getDocAiClient() {
    if (!docAiClient) {
        const { apiEndpoint } = getDocAiConfig();
        docAiClient = new documentai_1.DocumentProcessorServiceClient(apiEndpoint ? { apiEndpoint } : undefined);
    }
    return docAiClient;
}
function getVisionClient() {
    if (!visionClient) {
        visionClient = new vision_1.ImageAnnotatorClient();
    }
    return visionClient;
}
function getProcessorName(config) {
    const client = getDocAiClient();
    if (config.processorVersion) {
        return client.processorVersionPath(config.projectId, config.location, config.processorId, config.processorVersion);
    }
    return client.processorPath(config.projectId, config.location, config.processorId);
}
function guessImageMime(buffer) {
    if (buffer.length >= 4) {
        if (buffer[0] === 0xff && buffer[1] === 0xd8)
            return 'image/jpeg';
        if (buffer[0] === 0x89 && buffer[1] === 0x50 && buffer[2] === 0x4e && buffer[3] === 0x47) {
            return 'image/png';
        }
        if (buffer[0] === 0x47 && buffer[1] === 0x49 && buffer[2] === 0x46)
            return 'image/gif';
        if (buffer[0] === 0x42 && buffer[1] === 0x4d)
            return 'image/bmp';
    }
    return process.env.DOC_AI_IMAGE_MIME || 'image/jpeg';
}
function extractTextFromLayout(layout, fullText) {
    if (!layout?.textAnchor?.textSegments?.length)
        return '';
    return layout.textAnchor.textSegments
        .map((segment) => {
        const start = Number(segment.startIndex ?? 0);
        const end = Number(segment.endIndex ?? 0);
        return fullText.substring(start, end);
    })
        .join('');
}
function extractBlock(block, fullText) {
    const text = extractTextFromLayout(block.layout, fullText).trim();
    return {
        text,
        confidence: block.layout?.confidence ?? undefined,
        boundingBox: block.layout?.boundingPoly
            ? {
                vertices: normalizeVertices(block.layout.boundingPoly.vertices),
                normalizedVertices: normalizeVertices(block.layout.boundingPoly.normalizedVertices),
            }
            : undefined,
    };
}
function extractTable(table, fullText) {
    const rows = [];
    const rowGroups = [...(table.headerRows ?? []), ...(table.bodyRows ?? [])];
    rowGroups.forEach((row) => {
        const cells = (row.cells ?? []);
        const rowValues = cells.map((cell) => extractTextFromLayout(cell.layout, fullText).trim());
        rows.push(rowValues);
    });
    const columnCount = rows.reduce((max, row) => Math.max(max, row.length), 0);
    return { rows, rowCount: rows.length, columnCount };
}
function parseDocument(document) {
    const fullText = document.text ?? '';
    const pages = document.pages?.map((page, index) => {
        const pageText = extractTextFromLayout(page.layout, fullText);
        const blocks = (page.blocks ?? []).map((block) => extractBlock(block, fullText));
        const tables = (page.tables ?? []).map((table) => extractTable(table, fullText));
        return {
            pageNumber: page.pageNumber ?? index + 1,
            text: pageText.trim(),
            blocks: blocks.filter((block) => block.text.length > 0),
            tables: tables.length > 0 ? tables : undefined,
        };
    }) ?? [];
    const hasImageQuality = document.pages?.some((page) => Boolean(page.imageQualityScores));
    const isScanned = Boolean(hasImageQuality);
    return { fullText, pages, isScanned };
}
async function processDocumentWithDocAi(buffer, mimeType) {
    const config = getDocAiConfig();
    const client = getDocAiClient();
    const name = getProcessorName(config);
    const [result] = await client.processDocument({
        name,
        rawDocument: {
            content: buffer.toString('base64'),
            mimeType,
        },
    });
    if (!result.document) {
        throw new Error('Document AI returned no document.');
    }
    return result.document;
}
async function visionOcrImage(buffer) {
    const client = getVisionClient();
    const [result] = await client.documentTextDetection({
        image: { content: buffer },
    });
    const annotation = result.fullTextAnnotation;
    const text = annotation?.text ?? '';
    const blocks = [];
    annotation?.pages?.forEach((page) => {
        page.blocks?.forEach((block) => {
            const blockText = block.paragraphs
                ?.map((paragraph) => paragraph.words
                ?.map((word) => word.symbols?.map((symbol) => symbol.text).join('') ?? '')
                .filter((value) => value.length > 0)
                .join(' '))
                .filter((value) => value && value.length > 0)
                .join('\n') ?? '';
            if (blockText) {
                blocks.push({
                    text: blockText,
                    confidence: block.confidence ?? undefined,
                    boundingBox: block.boundingBox
                        ? {
                            vertices: normalizeVertices(block.boundingBox.vertices),
                        }
                        : undefined,
                });
            }
        });
    });
    return { text, blocks };
}
async function extractTextFromPdf(pdfBuffer) {
    try {
        const document = await processDocumentWithDocAi(pdfBuffer, 'application/pdf');
        return parseDocument(document);
    }
    catch (error) {
        console.error('Document AI PDF extraction failed, falling back to Vision OCR.', error);
        try {
            const vision = await visionOcrImage(pdfBuffer);
            return {
                fullText: vision.text,
                pages: [
                    {
                        pageNumber: 1,
                        text: vision.text,
                        blocks: vision.blocks,
                    },
                ],
                isScanned: true,
            };
        }
        catch (fallbackError) {
            console.error('Vision OCR fallback failed.', fallbackError);
            throw error;
        }
    }
}
async function extractTextFromImage(imageBuffer) {
    try {
        const mimeType = guessImageMime(imageBuffer);
        const document = await processDocumentWithDocAi(imageBuffer, mimeType);
        const parsed = parseDocument(document);
        const firstPage = parsed.pages[0];
        return {
            text: parsed.fullText,
            blocks: firstPage?.blocks ?? [],
        };
    }
    catch (error) {
        console.error('Document AI image extraction failed, falling back to Vision OCR.', error);
        return visionOcrImage(imageBuffer);
    }
}
