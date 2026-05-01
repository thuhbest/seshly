import fs from 'node:fs';
import path from 'node:path';

import { extractTextFromImage, extractTextFromPdf } from '../src/services/docExtract';

function usage() {
  console.log('Usage: npm run doc:extract -- <path-to-file>');
}

async function main() {
  const target = process.argv[2];
  if (!target) {
    usage();
    process.exit(1);
  }

  const filePath = path.resolve(process.cwd(), target);
  if (!fs.existsSync(filePath)) {
    console.error(`File not found: ${filePath}`);
    process.exit(1);
  }

  const buffer = fs.readFileSync(filePath);
  const ext = path.extname(filePath).toLowerCase();

  if (ext === '.pdf') {
    const result = await extractTextFromPdf(buffer);
    console.log(JSON.stringify(result, null, 2));
    return;
  }

  const result = await extractTextFromImage(buffer);
  console.log(JSON.stringify(result, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
