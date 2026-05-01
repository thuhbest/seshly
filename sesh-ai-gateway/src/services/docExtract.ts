import { DocumentProcessorServiceClient, protos } from '@google-cloud/documentai';
import { ImageAnnotatorClient } from '@google-cloud/vision';

type ExtractedBlock = {
  text: string;
  confidence?: number;
  boundingBox?: {
    vertices?: { x?: number; y?: number }[];
    normalizedVertices?: { x?: number; y?: number }[];
  };
};

type DocDocument = protos.google.cloud.documentai.v1.IDocument;
type DocPage = NonNullable<DocDocument['pages']>[number];
type DocBlock = NonNullable<DocPage['blocks']>[number];
type DocTable = NonNullable<DocPage['tables']>[number];
type DocTableRow = NonNullable<DocTable['headerRows']>[number];
type DocTableCell = NonNullable<NonNullable<DocTableRow['cells']>[number]>;

export type ExtractedTable = {
  rows: string[][];
  rowCount: number;
  columnCount: number;
};

export type ExtractedPage = {
  pageNumber: number;
  text: string;
  blocks: ExtractedBlock[];
  tables?: ExtractedTable[];
};

export type PdfExtractionResult = {
  fullText: string;
  pages: ExtractedPage[];
  isScanned: boolean;
};

export type ImageExtractionResult = {
  text: string;
  blocks: ExtractedBlock[];
};

type DocumentAiConfig = {
  projectId: string;
  location: string;
  processorId: string;
  processorVersion?: string;
  apiEndpoint?: string;
};

let docAiClient: DocumentProcessorServiceClient | null = null;
let visionClient: ImageAnnotatorClient | null = null;

function normalizeVertex(vertex: { x?: number | null; y?: number | null }) {
  return {
    x: vertex.x === null ? undefined : vertex.x,
    y: vertex.y === null ? undefined : vertex.y,
  };
}

function normalizeVertices(
  vertices?: Array<{ x?: number | null; y?: number | null }> | null,
) {
  if (!vertices) return undefined;
  return vertices.map((vertex) => normalizeVertex(vertex));
}

function getDocAiConfig(): DocumentAiConfig {
  const projectId =
    process.env.DOC_AI_PROJECT_ID ||
    process.env.DOCAI_PROJECT_ID ||
    process.env.GOOGLE_PROJECT_ID ||
    process.env.GOOGLE_CLOUD_PROJECT ||
    process.env.GCLOUD_PROJECT ||
    process.env.FIREBASE_PROJECT_ID;
  const location = process.env.DOC_AI_LOCATION || process.env.DOCAI_LOCATION || 'us';
  const processorId = process.env.DOC_AI_PROCESSOR_ID || process.env.DOCAI_PROCESSOR_ID;
  const processorVersion = process.env.DOC_AI_PROCESSOR_VERSION || undefined;
  const apiEndpoint =
    process.env.DOC_AI_API_ENDPOINT ||
    (location === 'us' || location === 'eu' ? `${location}-documentai.googleapis.com` : undefined);

  if (!projectId || !processorId) {
    throw new Error('Missing DOC_AI_PROJECT_ID or DOC_AI_PROCESSOR_ID.');
  }

  return { projectId, location, processorId, processorVersion, apiEndpoint };
}

function getDocAiClient(): DocumentProcessorServiceClient {
  if (!docAiClient) {
    const { apiEndpoint } = getDocAiConfig();
    docAiClient = new DocumentProcessorServiceClient(
      apiEndpoint ? { apiEndpoint } : undefined,
    );
  }
  return docAiClient;
}

function getVisionClient(): ImageAnnotatorClient {
  if (!visionClient) {
    visionClient = new ImageAnnotatorClient();
  }
  return visionClient;
}

function getProcessorName(config: DocumentAiConfig): string {
  const client = getDocAiClient();
  if (config.processorVersion) {
    return client.processorVersionPath(
      config.projectId,
      config.location,
      config.processorId,
      config.processorVersion,
    );
  }
  return client.processorPath(config.projectId, config.location, config.processorId);
}

function guessImageMime(buffer: Buffer): string {
  if (buffer.length >= 4) {
    if (buffer[0] === 0xff && buffer[1] === 0xd8) return 'image/jpeg';
    if (buffer[0] === 0x89 && buffer[1] === 0x50 && buffer[2] === 0x4e && buffer[3] === 0x47) {
      return 'image/png';
    }
    if (buffer[0] === 0x47 && buffer[1] === 0x49 && buffer[2] === 0x46) return 'image/gif';
    if (buffer[0] === 0x42 && buffer[1] === 0x4d) return 'image/bmp';
  }
  return process.env.DOC_AI_IMAGE_MIME || 'image/jpeg';
}

function extractTextFromLayout(
  layout: DocPage['layout'] | null | undefined,
  fullText: string,
): string {
  if (!layout?.textAnchor?.textSegments?.length) return '';
  return layout.textAnchor.textSegments
    .map((segment) => {
      const start = Number(segment.startIndex ?? 0);
      const end = Number(segment.endIndex ?? 0);
      return fullText.substring(start, end);
    })
    .join('');
}

function extractBlock(block: DocBlock, fullText: string): ExtractedBlock {
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

function extractTable(table: DocTable, fullText: string): ExtractedTable {
  const rows: string[][] = [];
  const rowGroups = [...(table.headerRows ?? []), ...(table.bodyRows ?? [])];

  rowGroups.forEach((row) => {
    const cells = (row.cells ?? []) as DocTableCell[];
    const rowValues = cells.map((cell) => extractTextFromLayout(cell.layout, fullText).trim());
    rows.push(rowValues);
  });

  const columnCount = rows.reduce((max, row) => Math.max(max, row.length), 0);
  return { rows, rowCount: rows.length, columnCount };
}

function parseDocument(document: DocDocument): PdfExtractionResult {
  const fullText = document.text ?? '';
  const pages: ExtractedPage[] =
    document.pages?.map((page, index) => {
      const pageText = extractTextFromLayout(page.layout, fullText);
      const blocks = (page.blocks ?? []).map((block) => extractBlock(block as DocBlock, fullText));
      const tables = (page.tables ?? []).map((table) => extractTable(table as DocTable, fullText));
      return {
        pageNumber: page.pageNumber ?? index + 1,
        text: pageText.trim(),
        blocks: blocks.filter((block) => block.text.length > 0),
        tables: tables.length > 0 ? tables : undefined,
      };
    }) ?? [];

  const hasImageQuality = document.pages?.some((page) => Boolean((page as DocPage).imageQualityScores));
  const isScanned = Boolean(hasImageQuality);

  return { fullText, pages, isScanned };
}

async function processDocumentWithDocAi(
  buffer: Buffer,
  mimeType: string,
): Promise<DocDocument> {
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

  return result.document as DocDocument;
}

async function visionOcrImage(buffer: Buffer): Promise<ImageExtractionResult> {
  const client = getVisionClient();
  const [result] = await client.documentTextDetection({
    image: { content: buffer },
  });

  const annotation = result.fullTextAnnotation;
  const text = annotation?.text ?? '';

  const blocks: ExtractedBlock[] = [];
  annotation?.pages?.forEach((page) => {
    page.blocks?.forEach((block) => {
      const blockText =
        block.paragraphs
          ?.map((paragraph) =>
            paragraph.words
              ?.map((word) => word.symbols?.map((symbol) => symbol.text).join('') ?? '')
              .filter((value) => value.length > 0)
              .join(' '),
          )
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

export async function extractTextFromPdf(pdfBuffer: Buffer): Promise<PdfExtractionResult> {
  try {
    const document = await processDocumentWithDocAi(pdfBuffer, 'application/pdf');
    return parseDocument(document);
  } catch (error) {
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
    } catch (fallbackError) {
      console.error('Vision OCR fallback failed.', fallbackError);
      throw error;
    }
  }
}

export async function extractTextFromImage(imageBuffer: Buffer): Promise<ImageExtractionResult> {
  try {
    const mimeType = guessImageMime(imageBuffer);
    const document = await processDocumentWithDocAi(imageBuffer, mimeType);
    const parsed = parseDocument(document);
    const firstPage = parsed.pages[0];
    return {
      text: parsed.fullText,
      blocks: firstPage?.blocks ?? [],
    };
  } catch (error) {
    console.error('Document AI image extraction failed, falling back to Vision OCR.', error);
    return visionOcrImage(imageBuffer);
  }
}
