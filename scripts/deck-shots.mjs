// Snima screenshotove za slajd 8 seed decka sa ŽIVE produkcije.
//
//   node scripts/deck-shots.mjs [izlazni-dir]     # default build/marketing/shots
//
// Headed sistemski Chrome, ne headless: automatizirani headless nema WebGL i
// Flutter na domovina.ai crta prazno platno. Viewport 1440×817 (omjer 1160:658
// kao postojeći shotovi), dpr 2; >= 1100 px širine da epizoda ima tri stupca.
// 45 s čekanja po stranici — prvi paint u automatiziranom Chromeu traje ~30 s.
// Ugradnja u deck: sips -Z 1160 + JPEG ~74, pa data: URI (vidi deck/README.md).
import { mkdir } from 'node:fs/promises';
import { chromium } from 'playwright';

const out = process.argv[2] ?? 'build/marketing/shots';
await mkdir(out, { recursive: true });
const browser = await chromium.launch({ channel: 'chrome', headless: false });
const ctx = await browser.newContext({
  viewport: { width: 1440, height: 817 },
  deviceScaleFactor: 2,
  locale: 'hr-HR',
  colorScheme: 'dark',
});
const page = await ctx.newPage();

async function shot(url, file) {
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForTimeout(45000);
  await page.screenshot({ path: `${out}/${file}` });
  console.log(`${out}/${file}`);
}

await shot('https://domovina.ai/', 'home.png');
// Ista epizoda i trenutak kao slajd 4 (24:35).
await shot('https://domovina.ai/v/WRE248YCIeI/t/1475', 'episode.png');
await browser.close();
