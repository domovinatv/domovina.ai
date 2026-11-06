// Zajednički dio e2e: zabrana mreže prema van, seed i prijava u admin.
import { test as base, expect, type Page } from '@playwright/test';

export const SHIM = `http://127.0.0.1:${process.env.VIJESTI_SHIM_PORT ?? '8790'}`;
export const EDITOR_ID = '11111111-1111-4111-8111-111111111111';
export const STRANGER_ID = '33333333-3333-4333-8333-333333333333';

export type SeedState = 'published' | 'corrected' | 'retracted' | 'review' | 'approved';
export interface SeedArticle {
  videoId: string;
  channel: string;
  state: SeedState;
  articleId: number;
  slug: string;
  versionId: number;
  title: string;
}

/** Svaki zahtjev izvan 127.0.0.1 se prekida i ruši test (e2e radi bez mreže). */
export const test = base.extend<{ blockExternal: string[] }>({
  blockExternal: [
    async ({ context }, use) => {
      const external: string[] = [];
      await context.route('**/*', async (route) => {
        const url = new URL(route.request().url());
        if (url.protocol === 'data:' || url.protocol === 'blob:' || url.hostname === '127.0.0.1') {
          await route.continue();
        } else {
          external.push(route.request().url());
          await route.abort('blockedbyclient');
        }
      });
      await use(external);
      expect(external, 'zahtjevi izvan 127.0.0.1').toEqual([]);
    },
    { auto: true },
  ],
});

export { expect };

/** Početni seed (pet članaka u pet stanja); vraća članke po stanju. */
export async function resetSeed(): Promise<Record<SeedState, SeedArticle>> {
  const r = await fetch(`${SHIM}/__shim/reset`, { method: 'POST' });
  if (!r.ok) throw new Error(`reset shima: ${String(r.status)}`);
  return seedInfo();
}

export async function seedInfo(): Promise<Record<SeedState, SeedArticle>> {
  const r = await fetch(`${SHIM}/__shim/seed`);
  const list = (await r.json()) as SeedArticle[];
  return Object.fromEntries(list.map((a) => [a.state, a])) as Record<SeedState, SeedArticle>;
}

/** Prijava kroz lokalni obrazac (nepotpisan JWT, odluka 606); čeka `data-ready`. */
export async function login(page: Page, sub = EDITOR_ID): Promise<void> {
  await page.goto('/vijesti/admin');
  await expect(page.locator('body')).toHaveAttribute('data-ready', 'true');
  await page.getByTestId('login-local-sub').fill(sub);
  await Promise.all([page.waitForEvent('load'), page.getByTestId('login-local').click()]);
  await expect(page.locator('body')).toHaveAttribute('data-ready', 'true');
}

/** Otvara članak u adminu i čeka da se iscrta. */
export async function openAdminArticle(page: Page, articleId: number): Promise<void> {
  await page.goto(`/vijesti/admin?clanak=${String(articleId)}`);
  await expect(page.locator('body')).toHaveAttribute('data-ready', 'true');
  await expect(page.getByTestId('admin-article')).toHaveAttribute('data-article-id', String(articleId));
}
