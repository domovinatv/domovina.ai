// Admin urednika u pravom pregledniku nad shimom (odluke 604, 606, 607).
// Svaki test kreće od svježeg seeda.
import {
  SHIM,
  STRANGER_ID,
  expect,
  login,
  openAdminArticle,
  resetSeed,
  test,
  type SeedArticle,
  type SeedState,
} from './fixtures.js';

let seed: Record<SeedState, SeedArticle>;

test.beforeEach(async () => {
  seed = await resetSeed();
});

test('korisnik bez uloge ne vidi red čekanja', async ({ page }) => {
  await login(page, STRANGER_ID);
  await expect(page.getByTestId('no-role')).toBeVisible();
  await expect(page.getByTestId('queue-item')).toHaveCount(0);
  // Ni izravan URL članka ne otkriva ništa.
  await page.goto(`/vijesti/admin?clanak=${String(seed.review.articleId)}`);
  await expect(page.locator('body')).toHaveAttribute('data-ready', 'true');
  await expect(page.getByTestId('no-role')).toBeVisible();
  await expect(page.getByTestId('admin-article')).toHaveCount(0);
});

test('neprijavljen vidi samo obrazac za prijavu', async ({ page }) => {
  await page.goto('/vijesti/admin');
  await expect(page.locator('body')).toHaveAttribute('data-ready', 'true');
  await expect(page.getByTestId('login-local-form')).toBeVisible();
  await expect(page.getByTestId('queue-item')).toHaveCount(0);
});

test('urednik: red, razrješenje rečenice, odobrenje, objava, članak je javan', async ({ page }) => {
  await login(page);
  await expect(page.getByTestId('admin-user')).toContainText('urednik');
  const queue = page.getByTestId('queue');
  await expect(queue.getByTestId('queue-item')).toHaveCount(2);
  await expect(page.getByTestId('archive').getByTestId('queue-item')).toHaveCount(3);

  await queue.locator(`[data-article-id="${String(seed.review.articleId)}"] a`).click();
  await expect(page).toHaveURL(new RegExp(`clanak=${String(seed.review.articleId)}$`));
  await expect(page.getByTestId('article-status')).toHaveText('U pregledu');
  await expect(page.getByTestId('admin-title')).toHaveText(seed.review.title);

  // Sljedeći korak je odobrenje, blokirano dok rečenice čekaju potvrdu, s razlogom.
  await expect(page.getByTestId('steps')).toHaveAttribute('data-current', 'review');
  const next = page.getByTestId('next-step');
  await expect(next).toHaveAttribute('data-action', 'approve');
  await expect(next).toHaveAttribute('data-blocked', 'true');
  await expect(page.getByTestId('approve')).toBeDisabled();
  await expect(next.locator('[data-testid=blocker][data-kind=sentences]')).toContainText(/čeka(ju)? potvrdu/);

  const pending = page.locator('[data-testid=sentence][data-state=pending]');
  const n = await pending.count();
  expect(n).toBeGreaterThan(0);
  for (let i = 0; i < n; i++) {
    const s = pending.first();
    const num = await s.getAttribute('data-n');
    await s.getByTestId('resolve-kind').selectOption('verified');
    await s.getByTestId('resolve-note').fill('Provjereno u snimci, 12:30.');
    await s.getByTestId('resolve-submit').click();
    await expect(page.getByTestId('admin-status')).toHaveText(`Rečenica ${num ?? ''} je razriješena.`);
    await expect(page.locator(`[data-testid=sentence][data-n="${num ?? ''}"]`)).toHaveAttribute('data-state', 'resolved');
  }
  await expect(page.getByTestId('admin-error')).toBeHidden();
  await expect(page.getByTestId('next-step')).toHaveAttribute('data-blocked', 'false');

  await page.getByTestId('approve').click();
  await expect(page.getByTestId('admin-status')).toHaveText('Verzija je odobrena.');
  await expect(page.getByTestId('article-status')).toHaveText('Odobreno');
  await expect(page.getByTestId('next-step')).toHaveAttribute('data-action', 'publish');

  await page.getByTestId('publish').click();
  await expect(page.getByTestId('admin-status')).toHaveText('Članak je objavljen.');
  await expect(page.getByTestId('article-status')).toHaveText('Objavljeno');
  await expect(page.locator('[data-testid=event]').last()).toHaveAttribute('data-to', 'published');

  const res = await page.goto(`/vijesti/${seed.review.slug}`);
  expect(res?.status()).toBe(200);
  await expect(page.getByTestId('article-title')).toHaveText(seed.review.title);
  await page.goto('/vijesti/');
  await expect(page.locator(`[data-slug="${seed.review.slug}"]`).first()).toBeVisible();
});

test('uredi: nova verzija vraća članak u pregled, povijest raste, odobrenje traži provjeru', async ({ page }) => {
  await login(page);
  await openAdminArticle(page, seed.approved.articleId);
  await expect(page.getByTestId('article-status')).toHaveText('Odobreno');
  const before = await page.getByTestId('version-item').count();

  await page.getByTestId('edit').click();
  await expect(page.getByTestId('editor')).toBeVisible();
  const title = `${seed.approved.title} (uređeno)`;
  await page.getByTestId('editor-title').fill(title);
  await page.getByTestId('editor-save').click();
  await expect(page.getByTestId('admin-status')).toContainText('Nova verzija je spremljena.');
  await expect(page.getByTestId('editor')).toHaveCount(0);
  await expect(page.getByTestId('article-status')).toHaveText('U pregledu');
  await expect(page.getByTestId('admin-title')).toHaveText(title);
  await expect(page.getByTestId('version-item')).toHaveCount(before + 1);
  await expect(page.getByTestId('verify-missing')).toBeVisible();

  // Verzija iz admina nema provjeru: odobrenje je blokirano i admin kaže zašto.
  const blocker = page.locator('[data-testid=blocker][data-kind=verify]');
  await expect(blocker).toContainText(`v${String(before + 1)} čeka automatsku provjeru`);
  await expect(blocker).toContainText('Spremljena je u adminu');
  await expect(page.getByTestId('approve')).toBeDisabled();

  // Stara verzija se može pogledati (povijest je sklopljena), uz napomenu.
  await page.getByTestId('history').locator('summary').click();
  await page.locator(`[data-testid=version-item][data-version="1"] [data-testid=version-show]`).click();
  await expect(page.getByTestId('old-version')).toBeVisible();
  await expect(page.getByTestId('admin-title')).toHaveText(seed.approved.title);

  // Nakon automatske provjere blokada prelazi na rečenice ili nestaje.
  const verified = await fetch(`${SHIM}/__shim/verify?article=${String(seed.approved.articleId)}`, { method: 'POST' });
  expect(verified.status).toBe(200);
  await openAdminArticle(page, seed.approved.articleId);
  await expect(page.locator('[data-testid=blocker][data-kind=verify]')).toHaveCount(0);
  await expect(page.getByTestId('verify')).toBeVisible();
});

test('jedan stupac: rečenica uz tekst s izvorom, Poslušaj u jednom playeru, nacrt → pregled', async ({ page }) => {
  await login(page);
  await openAdminArticle(page, seed.review.articleId);

  // Nema nezavisnih scrollova unutar admina: čita se jedna stranica.
  const scrollers = await page.evaluate(
    () =>
      [...document.querySelectorAll('#admin *')].filter((e) => {
        const cs = getComputedStyle(e);
        return /(auto|scroll)/.test(cs.overflowY) && e.scrollHeight > e.clientHeight;
      }).length,
  );
  expect(scrollers).toBe(0);

  // Označena rečenica je istaknuta u tekstu, a kartica s potvrdom stoji odmah iza tog odlomka.
  const mark = page.locator('[data-testid=sentence-mark].pending').first();
  await expect(mark).toBeVisible();
  const n = (await mark.getAttribute('data-n')) ?? '';
  const card = page.locator(`[data-testid=sentence][data-n="${n}"]`);
  await expect(card).toHaveAttribute('data-state', 'pending');
  await expect(card.getByTestId('resolve-form')).toBeVisible();
  const adjacent = await mark.evaluate(
    (m, nn) => !!m.parentElement?.nextElementSibling?.querySelector(`[data-testid=sentence][data-n="${nn}"]`),
    n,
  );
  expect(adjacent).toBe(true);

  // Rečenica s potporom: klik otvara izvorni trenutak.
  const ok = page.locator('[data-testid=sentence-mark].supported').first();
  const okN = (await ok.getAttribute('data-n')) ?? '';
  await expect(page.locator(`[data-testid=sentence][data-n="${okN}"]`)).toHaveCount(0);
  await ok.click();
  await expect(page.locator(`[data-testid=sentence][data-n="${okN}"]`)).toHaveAttribute('data-state', 'supported');

  // Poslušaj: jedan player na dnu, isječak od početka do kraja trenutka.
  await expect(page.getByTestId('player')).toBeHidden();
  const quote = page.locator('.quote-block').first();
  const momentId = (await quote.getAttribute('data-moment-id')) ?? '';
  await quote.getByTestId('listen').click();
  await expect(page.getByTestId('player')).toBeVisible();
  const audio = page.getByTestId('player-audio');
  await expect(audio).toHaveAttribute('src', /\/data\/[^/]+\/(audio\.mp3|video_h264\.mp4)#t=[\d.]+,[\d.]+$/);
  await expect(audio).toHaveAttribute('data-moment-id', momentId);
  await expect(page.locator('audio')).toHaveCount(1);
  await expect(quote.getByTestId('listen-app')).toHaveAttribute('href', /\/v\/[^/]+\/t\/\d+$/);

  // Nacrt: sljedeći korak je slanje u pregled, a blokada odobravanja je najavljena.
  await page.getByTestId('to-draft').click();
  await expect(page.getByTestId('admin-status')).toHaveText('Članak je vraćen u nacrt.');
  await expect(page.getByTestId('steps')).toHaveAttribute('data-current', 'draft');
  await expect(page.getByTestId('article-status')).toHaveText('Nacrt');
  await expect(page.getByTestId('next-step')).toHaveAttribute('data-action', 'to-review');
  await expect(page.getByTestId('next-step')).toContainText('potvrdu');
  await page.getByTestId('to-review').click();
  await expect(page.getByTestId('article-status')).toHaveText('U pregledu');
});

test('stale_version: spremanje nad zastarjelom verzijom (dvije kartice)', async ({ page, context }) => {
  await login(page);
  await openAdminArticle(page, seed.approved.articleId);
  const other = await context.newPage();
  await openAdminArticle(other, seed.approved.articleId);

  await other.getByTestId('edit').click();
  await other.getByTestId('editor-title').fill('Druga kartica');
  await page.getByTestId('edit').click();
  await page.getByTestId('editor-title').fill('Prva kartica');

  await page.getByTestId('editor-save').click();
  await expect(page.getByTestId('admin-status')).toContainText('Nova verzija je spremljena.');

  await other.getByTestId('editor-save').click();
  const error = other.getByTestId('admin-error');
  await expect(error).toHaveAttribute('data-code', 'stale_version');
  await expect(error).toContainText(/novij|osvježi/i);
  // Uređivanje ostaje otvoreno da tekst ne propadne.
  await expect(other.getByTestId('editor')).toBeVisible();
  await expect(other.getByTestId('editor-title')).toHaveValue('Druga kartica');

  await other.reload();
  await expect(other.getByTestId('admin-title')).toHaveText('Prva kartica');
  await other.close();
});

test('ispravak objavljenog članka: nova verzija, provjera, objava; vidi se u javnom dnevniku', async ({ page }) => {
  await login(page);
  await openAdminArticle(page, seed.published.articleId);
  await expect(page.getByTestId('article-status')).toHaveText('Objavljeno');
  // Bez nove verzije nema što objaviti kao ispravak: samo uputa.
  await expect(page.getByTestId('correct-hint')).toHaveAttribute('data-state', 'needs_edit');
  await expect(page.getByTestId('correct')).toHaveCount(0);

  const lead = 'Ispravljen uvod: govornik je govorio o obitelji, ne o politici.';
  await page.getByTestId('edit').click();
  await page.getByTestId('editor-lead').fill(lead);
  await page.getByTestId('editor-save').click();
  await expect(page.getByTestId('admin-status')).toContainText('Nova verzija je spremljena.');
  // Objavljen članak ostaje objavljen dok se ispravak ne objavi.
  await expect(page.getByTestId('article-status')).toHaveText('Objavljeno');
  await expect(page.getByTestId('correct-hint')).toHaveAttribute('data-state', 'needs_verify');
  await expect(page.getByTestId('correct')).toBeDisabled();
  await page.goto(`/vijesti/${seed.published.slug}`);
  await expect(page.getByTestId('article-lead')).not.toHaveText(lead);

  // Automatska provjera (engine izvan preglednika), pa razrješenje ako treba.
  const verified = await fetch(`${SHIM}/__shim/verify?article=${String(seed.published.articleId)}`, { method: 'POST' });
  expect(verified.status).toBe(200);
  await openAdminArticle(page, seed.published.articleId);
  for (const s of await page.locator('[data-testid=sentence][data-state=pending]').all()) {
    await s.getByTestId('resolve-note').fill('Provjereno u snimci.');
    await s.getByTestId('resolve-submit').click();
    await expect(page.getByTestId('admin-status')).toContainText('je razriješena.');
  }
  await expect(page.getByTestId('correct-hint')).toHaveAttribute('data-state', 'ready');

  const description = 'Ispravljen je opis teme u uvodu.';
  await page.getByTestId('correct-kind').selectOption('fact');
  await page.getByTestId('correct-description').fill(description);
  await page.getByTestId('correct').click();
  await expect(page.getByTestId('admin-status')).toHaveText('Ispravak je objavljen.');
  await expect(page.getByTestId('article-status')).toHaveText('Ispravljeno');
  await expect(page.getByTestId('admin-correction')).toContainText(description);
  await expect(page.getByTestId('correct-hint')).toHaveAttribute('data-state', 'needs_edit');

  await page.goto(`/vijesti/${seed.published.slug}`);
  await expect(page.getByTestId('article')).toHaveAttribute('data-status', 'corrected');
  await expect(page.getByTestId('article-lead')).toHaveText(lead);
  await expect(page.locator('[data-testid=correction][data-kind=fact]')).toContainText(description);
});

test('povlačenje objavljenog članka: javna stranica pokazuje razlog', async ({ page }) => {
  await login(page);
  await openAdminArticle(page, seed.published.articleId);
  const reason = 'Govornik je povukao pristanak za objavu.';
  await page.getByTestId('retract-reason').fill(reason);
  await page.getByTestId('retract').click();
  await expect(page.getByTestId('admin-status')).toHaveText('Članak je povučen.');
  await expect(page.getByTestId('article-status')).toHaveText('Povučeno');
  await expect(page.getByTestId('edit')).toHaveCount(0);

  await page.goto(`/vijesti/${seed.published.slug}`);
  await expect(page.getByTestId('retraction-reason')).toHaveText(reason);
  await expect(page.getByTestId('article-body')).toHaveCount(0);
});

test('odbij: članak iz pregleda je odbijen i nije javan', async ({ page }) => {
  await login(page);
  await openAdminArticle(page, seed.review.articleId);
  await page.getByTestId('action-note').fill('Tema nije za portal.');
  await page.getByTestId('reject').click();
  await expect(page.getByTestId('admin-status')).toHaveText('Članak je odbijen.');
  await expect(page.getByTestId('article-status')).toHaveText('Odbijeno');
  await expect(page.locator('[data-testid=event]').last()).toContainText('Tema nije za portal.');
  await expect(page.getByTestId('to-draft')).toBeVisible();

  await page.getByTestId('back-to-queue').click();
  await expect(page.getByTestId('queue').locator(`[data-article-id="${String(seed.review.articleId)}"]`)).toHaveCount(0);
  const res = await page.goto(`/vijesti/${seed.review.slug}`);
  expect(res?.status()).toBe(404);
});

test('admin na 390 px i u tamnoj temi: bez horizontalnog scrolla', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.emulateMedia({ colorScheme: 'dark' });
  const fits = async (what: string) => {
    const { scroll, client } = await page.evaluate(() => ({
      scroll: document.documentElement.scrollWidth,
      client: document.documentElement.clientWidth,
    }));
    expect(scroll, what).toBeLessThanOrEqual(client);
  };
  await page.goto('/vijesti/admin');
  await expect(page.locator('body')).toHaveAttribute('data-ready', 'true');
  await fits('prijava');
  await login(page);
  await fits('red čekanja');
  await openAdminArticle(page, seed.review.articleId);
  await fits('članak u pregledu');
  await page.getByTestId('edit').click();
  await fits('uređivanje');
  await openAdminArticle(page, seed.published.articleId);
  await fits('objavljen članak');
  const bg = await page.evaluate(() => getComputedStyle(document.body).backgroundColor);
  expect(bg).toBe('rgb(17, 19, 24)');
});
