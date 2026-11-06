// Pravne stranice (S7, odluke 710–712): 200, canonical, poveznice u podnožju,
// i vidljiv „[upisuje izdavač]” dok konfiguracija nema podatke izdavača.
import { expect, test } from './fixtures.js';

const PAGES = [
  { slug: 'impresum', h1: 'Impresum' },
  { slug: 'kako-nastaju-clanci', h1: 'Kako nastaju članci' },
  { slug: 'ispravci', h1: 'Ispravci i povlačenje' },
] as const;

test.describe('pravne stranice', () => {
  for (const p of PAGES) {
    test(`/vijesti/${p.slug}: 200, naslov, canonical, indeksira se`, async ({ page }) => {
      const res = await page.goto(`/vijesti/${p.slug}`);
      expect(res?.status()).toBe(200);
      await expect(page.getByRole('heading', { level: 1 })).toHaveText(p.h1);
      await expect(page.locator('link[rel="canonical"]')).toHaveAttribute('href', `https://domovina.ai/vijesti/${p.slug}`);
      await expect(page.locator('meta[name="robots"]')).not.toHaveAttribute('content', /noindex/);
    });
  }

  test('impresum bez podataka izdavača pokazuje „[upisuje izdavač]” za svako polje', async ({ page }) => {
    await page.goto('/vijesti/impresum');
    const fields = await page
      .getByTestId('legal-placeholder')
      .evaluateAll((els) => [...new Set(els.map((e) => e.getAttribute('data-field')))]);
    expect(fields.sort()).toEqual(
      ['aemRegistration', 'contactEmail', 'editorInChief', 'publisherAddress', 'publisherName'].sort(),
    );
    await expect(page.getByTestId('legal-placeholder').first()).toHaveText('[upisuje izdavač]');
    await expect(page.getByTestId('legal-placeholder').first()).toBeVisible();
  });

  test('podnožje vodi na pravne stranice; ispravci opisuju kontakt za kreatore', async ({ page }) => {
    await page.goto('/vijesti/');
    await page.getByTestId('footer-ispravci').click();
    await expect(page).toHaveURL(/\/vijesti\/ispravci$/);
    await expect(page.getByRole('heading', { name: 'Za autore podcasta' })).toBeVisible();
    await page.getByTestId('footer-kako-nastaju-clanci').click();
    await expect(page).toHaveURL(/\/vijesti\/kako-nastaju-clanci$/);
    await expect(page.getByText('Jedina dopuštena razlika su glasovi oklijevanja')).toBeVisible();
    await page.getByTestId('footer-impresum').click();
    await expect(page).toHaveURL(/\/vijesti\/impresum$/);
  });

  test('mobilna širina 390 px: impresum bez horizontalnog scrolla', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto('/vijesti/impresum');
    const { scroll, client } = await page.evaluate(() => ({
      scroll: document.documentElement.scrollWidth,
      client: document.documentElement.clientWidth,
    }));
    expect(scroll).toBeLessThanOrEqual(client);
  });
});
