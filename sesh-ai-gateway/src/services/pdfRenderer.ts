import { chromium } from 'playwright';

export async function renderPdfFromHtml(html: string): Promise<Buffer> {
  const browser = await chromium.launch({
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
  });
  try {
    const page = await browser.newPage();
    await page.setContent(html, { waitUntil: 'networkidle' });
    const pdf = await page.pdf({
      format: 'A4',
      printBackground: true,
      margin: {
        top: '24px',
        right: '24px',
        bottom: '24px',
        left: '24px',
      },
    });
    await page.close();
    return pdf;
  } finally {
    await browser.close();
  }
}
