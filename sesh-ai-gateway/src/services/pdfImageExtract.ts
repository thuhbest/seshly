export type PdfPageImages = {
  pageNumber: number;
  images: Buffer[];
};

type PdfImageData = {
  width?: number;
  height?: number;
  data?: Uint8ClampedArray | Uint8Array | Buffer;
  kind?: number;
};

function toPngBuffer(
  image: PdfImageData,
  imageKind: { RGB_24BPP: number; RGBA_32BPP: number; GRAYSCALE_8BPP: number; GRAYSCALE_1BPP: number },
  pngFactory: typeof import('pngjs'),
): Buffer | null {
  const width = image.width ?? 0;
  const height = image.height ?? 0;
  const data = image.data;
  if (!width || !height || !data) return null;
  const { PNG } = pngFactory;
  const png = new PNG({ width, height });
  const kind = image.kind ?? imageKind.RGBA_32BPP;
  const src = Buffer.from(data as Uint8Array);

  if (kind === imageKind.RGBA_32BPP) {
    src.copy(png.data);
  } else if (kind === imageKind.RGB_24BPP) {
    for (let i = 0, j = 0; i < src.length; i += 3, j += 4) {
      png.data[j] = src[i];
      png.data[j + 1] = src[i + 1];
      png.data[j + 2] = src[i + 2];
      png.data[j + 3] = 255;
    }
  } else if (kind === imageKind.GRAYSCALE_8BPP) {
    for (let i = 0, j = 0; i < src.length; i += 1, j += 4) {
      png.data[j] = src[i];
      png.data[j + 1] = src[i];
      png.data[j + 2] = src[i];
      png.data[j + 3] = 255;
    }
  } else if (kind === imageKind.GRAYSCALE_1BPP) {
    for (let i = 0, j = 0; i < src.length; i += 1, j += 4) {
      const value = src[i] === 0 ? 0 : 255;
      png.data[j] = value;
      png.data[j + 1] = value;
      png.data[j + 2] = value;
      png.data[j + 3] = 255;
    }
  } else {
    return null;
  }

  return PNG.sync.write(png);
}

export async function extractImagesFromPdf(
  pdfBuffer: Buffer,
  maxImagesPerPage = 4,
): Promise<PdfPageImages[]> {
  const pdfjsModule: any = await import('pdfjs-dist/legacy/build/pdf.js');
  const pdfjsLib = pdfjsModule.default ?? pdfjsModule;
  const pngFactory = await import('pngjs');

  const loadingTask = pdfjsLib.getDocument({
    data: pdfBuffer,
    disableWorker: true,
  });
  const pdf = await loadingTask.promise;
  const pageCount = pdf.numPages;
  const results: PdfPageImages[] = [];

  for (let pageNumber = 1; pageNumber <= pageCount; pageNumber += 1) {
    const page = await pdf.getPage(pageNumber);
    const opList = await page.getOperatorList();
    const images: Buffer[] = [];

    for (let i = 0; i < opList.fnArray.length; i += 1) {
      const fn = opList.fnArray[i];
      const args = opList.argsArray[i];

      if (fn === pdfjsLib.OPS.paintImageXObject || fn === pdfjsLib.OPS.paintJpegXObject) {
        const name = args[0];
        const image = await new Promise<PdfImageData>((resolve) => page.objs.get(name, resolve));
        const buffer = toPngBuffer(image, pdfjsLib.ImageKind, pngFactory);
        if (buffer) images.push(buffer);
      } else if (fn === pdfjsLib.OPS.paintInlineImageXObject) {
        const image = args[0] as PdfImageData;
        const buffer = toPngBuffer(image, pdfjsLib.ImageKind, pngFactory);
        if (buffer) images.push(buffer);
      }

      if (images.length >= maxImagesPerPage) break;
    }

    results.push({ pageNumber, images });
  }

  return results;
}
