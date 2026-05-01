"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.renderPdfFromHtml = renderPdfFromHtml;
const playwright_1 = require("playwright");
async function renderPdfFromHtml(html) {
    const browser = await playwright_1.chromium.launch({
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
    }
    finally {
        await browser.close();
    }
}
