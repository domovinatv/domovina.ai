// Admin urednika (S6): red čekanja, članak lijevo, izvorni trenuci s playerom
// desno, radnje uredničkog toka. Vanilla TS bez frameworka; podaci se crtaju
// kroz `textContent` (nikad innerHTML), pa tekst iz baze ne može postati kod.
import { CATEGORY_LABELS, CATEGORY_SLUGS, categoryLabel } from '../../lib/categories.js';
import { describeError } from '../../lib/errors.js';
import { clock, hrDateTime } from '../../lib/format.js';
import { createRest } from '../../lib/rest.js';
import { appEpisodeUrl, clipUrl, episodeBundleUrl, pickClipMedia } from '../../lib/urls.js';
import {
  ARCHIVE_STATUSES,
  QUEUE_STATUSES,
  correctionState,
  createEditorApi,
  editableBlocks,
  pendingSentences,
  type ArticleBundle,
  type Block,
  type CorrectionState,
  type EditorApi,
  type EditorMoment,
  type EditorVersion,
  type Status,
} from './api.js';
import { loadAuth, type AuthApi, type Session } from './auth.js';

interface AdminConfig {
  restUrl: string;
  anonKey: string;
  authUrl: string;
  cdnBase: string;
  appBase: string;
  portalBase: string;
}

const STATUS_LABEL: Record<Status, string> = {
  draft: 'Nacrt',
  review: 'U pregledu',
  approved: 'Odobreno',
  published: 'Objavljeno',
  corrected: 'Ispravljeno',
  rejected: 'Odbijeno',
  retracted: 'Povučeno',
};

const CORRECTION_KINDS = [
  ['fact', 'Činjenica'],
  ['quote', 'Citat'],
  ['attribution', 'Pripisivanje'],
  ['other', 'Ostalo'],
] as const;

const CORRECTION_HINT: Record<CorrectionState, string> = {
  needs_edit: 'Ispravak: uredi članak i spremi novu verziju. Kad prođe automatsku provjeru, ovdje je objavljuješ kao ispravak.',
  needs_verify: 'Nova verzija čeka automatsku provjeru (verify); ispravak se objavljuje tek nakon nje.',
  needs_resolution: 'Prije objave ispravka razriješi označene rečenice nove verzije.',
  ready: 'Nova verzija je provjerena: opiši ispravak i objavi je.',
};

type Child = Node | string | null | undefined | false;

/** Mali pomoćnik za DOM: atributi kao tekst, djeca kao čvorovi ili tekst. */
function h<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  attrs: Record<string, string | number | boolean | undefined> = {},
  ...children: Child[]
): HTMLElementTagNameMap[K] {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v === undefined || v === false) continue;
    if (k === 'testid') el.dataset.testid = String(v);
    else el.setAttribute(k, v === true ? '' : String(v));
  }
  for (const c of children) if (c !== null && c !== undefined && c !== false) el.append(c);
  return el;
}

function button(label: string, testid: string, onClick: () => void, cls = ''): HTMLButtonElement {
  const b = h('button', { type: 'button', testid, class: cls || undefined }, label);
  b.addEventListener('click', onClick);
  return b;
}

const byId = (id: string): HTMLElement => {
  const el = document.getElementById(id);
  if (!el) throw new Error(`nema #${id}`);
  return el;
};

function readConfig(): AdminConfig {
  return JSON.parse(byId('vijesti-config').textContent || '{}') as AdminConfig;
}

class Admin {
  private api: EditorApi | null = null;
  private session: Session | null = null;
  private media = new Map<string, string | null>();
  private bundle: ArticleBundle | null = null;
  /** Verzija koja se gleda (povijest); radnje uvijek idu na zadnju. */
  private viewed: number | null = null;
  private editing: { title: string; lead: string; category: string; blocks: Block[] } | null = null;

  private readonly root = byId('admin');
  private readonly status = byId('admin-status');
  private readonly errorBox = byId('admin-error');

  constructor(
    private readonly cfg: AdminConfig,
    private readonly auth: AuthApi,
  ) {}

  async start(): Promise<void> {
    this.session = await this.auth.session();
    if (!this.session) {
      this.renderLogin();
      return;
    }
    const rest = createRest({ url: this.cfg.restUrl, anonKey: this.cfg.anonKey, token: this.session.token, timeoutMs: 10000 });
    this.api = createEditorApi(rest);
    try {
      const role = await this.api.role(this.session.userId);
      if (role === null) {
        this.renderNoRole();
        return;
      }
      this.renderUser(role);
    } catch (e) {
      this.showError(e);
      this.renderLogin();
      return;
    }
    window.addEventListener('popstate', () => void this.route());
    await this.route();
  }

  private articleIdFromUrl(): number | null {
    const v = new URLSearchParams(location.search).get('clanak');
    return v && /^\d+$/.test(v) ? Number(v) : null;
  }

  private navigate(articleId: number | null): void {
    const url = new URL(location.href);
    if (articleId === null) url.searchParams.delete('clanak');
    else url.searchParams.set('clanak', String(articleId));
    history.pushState(null, '', url);
    void this.route();
  }

  private async route(): Promise<void> {
    this.clearMessages();
    this.editing = null;
    this.viewed = null;
    const id = this.articleIdFromUrl();
    if (id === null) await this.renderQueue();
    else await this.loadArticle(id);
  }

  // ---------------------------------------------------------------- poruke

  private clearMessages(): void {
    this.errorBox.hidden = true;
    this.errorBox.replaceChildren();
    this.status.textContent = '';
  }

  private showError(e: unknown): void {
    const err = describeError(e);
    this.errorBox.replaceChildren(h('p', {}, err.text));
    if (err.detail) this.errorBox.append(h('p', { class: 'detail', testid: 'admin-error-detail' }, err.detail));
    if (err.code) this.errorBox.dataset.code = err.code;
    else delete this.errorBox.dataset.code;
    this.errorBox.hidden = false;
  }

  private notify(text: string): void {
    this.status.textContent = text;
  }

  // ---------------------------------------------------------------- prijava

  private renderLogin(): void {
    const box = h('section', { class: 'panel', testid: 'login' });
    this.root.replaceChildren(box);
    this.auth.renderLogin(box, () => {
      location.reload();
    });
  }

  private renderNoRole(): void {
    this.root.replaceChildren(
      h(
        'section',
        { class: 'panel', testid: 'no-role' },
        h('h2', {}, 'Nemaš uredničku ulogu'),
        h('p', {}, 'Prijavljen si, ali tvoj račun nije među urednicima vijesti. Javi se administratoru.'),
        button('Odjavi se', 'logout', () => void this.signOut()),
      ),
    );
  }

  private renderUser(role: string): void {
    const bar = byId('admin-user');
    bar.replaceChildren(
      h('span', { testid: 'admin-user' }, `${this.session?.email ?? this.session?.userId ?? ''} (${role === 'admin' ? 'administrator' : 'urednik'})`),
      ' ',
      button('Odjavi se', 'logout', () => void this.signOut(), 'link'),
    );
  }

  private async signOut(): Promise<void> {
    await this.auth.signOut();
    location.reload();
  }

  // ---------------------------------------------------------------- red čekanja

  private async renderQueue(): Promise<void> {
    const api = this.api;
    if (!api) return;
    this.root.replaceChildren(h('p', { class: 'muted' }, 'Učitavam…'));
    try {
      const [queue, archive] = await Promise.all([api.queue(QUEUE_STATUSES), api.queue(ARCHIVE_STATUSES)]);
      const list = (items: typeof queue, testid: string, empty: string) =>
        items.length === 0
          ? h('p', { class: 'muted', testid: `${testid}-empty` }, empty)
          : h(
              'ul',
              { class: 'queue', testid },
              ...items.map((q) => {
                const a = h('a', { href: `?clanak=${String(q.article.id)}` }, q.title);
                a.addEventListener('click', (e) => {
                  e.preventDefault();
                  this.navigate(q.article.id);
                });
                return h(
                  'li',
                  { testid: 'queue-item', 'data-article-id': q.article.id, 'data-status': q.article.status },
                  h('span', { class: `badge s-${q.article.status}` }, STATUS_LABEL[q.article.status]),
                  ' ',
                  a,
                  h('span', { class: 'muted' }, ` · v${String(q.version)} · ${hrDateTime(q.article.updated_at) ?? ''}`),
                );
              }),
            );
      this.root.replaceChildren(
        h('section', { class: 'panel' }, h('h2', {}, 'Na čekanju'), list(queue, 'queue', 'Nema članaka na čekanju.')),
        h(
          'section',
          { class: 'panel' },
          h('h2', {}, 'Objavljeno i arhiva'),
          list(archive, 'archive', 'Još ništa nije objavljeno.'),
        ),
      );
    } catch (e) {
      this.root.replaceChildren();
      this.showError(e);
    }
  }

  // ---------------------------------------------------------------- članak

  private async loadArticle(id: number, keepView = false): Promise<void> {
    const api = this.api;
    if (!api) return;
    if (!keepView) this.root.replaceChildren(h('p', { class: 'muted' }, 'Učitavam…'));
    try {
      const bundle = await api.article(id);
      if (!bundle) {
        this.root.replaceChildren(this.backLink(), h('p', { testid: 'admin-not-found' }, 'Članak ne postoji.'));
        return;
      }
      this.bundle = bundle;
      const videoId = bundle.latest.content?.episode.videoId;
      if (videoId && !this.media.has(videoId)) this.media.set(videoId, await this.mediaFile(videoId));
      this.renderArticle();
    } catch (e) {
      this.showError(e);
    }
  }

  private async mediaFile(videoId: string): Promise<string | null> {
    try {
      const res = await fetch(episodeBundleUrl(this.cfg.cdnBase, videoId), { signal: AbortSignal.timeout(4000) });
      if (!res.ok) return null;
      const j = (await res.json()) as { files?: unknown };
      return pickClipMedia(Array.isArray(j.files) ? j.files.filter((f): f is string => typeof f === 'string') : null);
    } catch {
      return null;
    }
  }

  private backLink(): HTMLElement {
    const a = h('a', { href: location.pathname, testid: 'back-to-queue' }, 'Natrag na red čekanja');
    a.addEventListener('click', (e) => {
      e.preventDefault();
      this.navigate(null);
    });
    return h('p', {}, a);
  }

  /** Radnja nad bazom: greška ide u okvir, uspjeh u poruku i ponovno učitavanje. */
  private async act(label: string, fn: () => Promise<unknown>): Promise<void> {
    const b = this.bundle;
    if (!b) return;
    this.clearMessages();
    try {
      await fn();
      this.editing = null;
      this.viewed = null;
      await this.loadArticle(b.article.id, true);
      this.notify(label);
    } catch (e) {
      this.showError(e);
    }
  }

  private renderArticle(): void {
    const b = this.bundle;
    if (!b) return;
    const latest = b.latest;
    const shown = b.versions.find((v) => v.id === this.viewed) ?? latest;
    const isLatest = shown.id === latest.id;
    const left = h(
      'section',
      { class: 'col-article', testid: 'admin-article', 'data-article-id': b.article.id, 'data-status': b.article.status },
      h(
        'p',
        { class: 'meta' },
        h('span', { class: `badge s-${b.article.status}`, testid: 'article-status' }, STATUS_LABEL[b.article.status]),
        ` · članak ${String(b.article.id)} · zadnja verzija v${String(latest.version)}`,
        ['published', 'corrected', 'retracted'].includes(b.article.status)
          ? h(
              'span',
              {},
              ' · ',
              h('a', { href: `${this.cfg.portalBase}/${b.article.slug}`, target: '_blank', rel: 'noopener' }, 'javna stranica'),
            )
          : null,
      ),
      this.editing ? this.renderEditor() : this.renderVersion(shown, isLatest),
    );
    const right = h('section', { class: 'col-moments', testid: 'moments' }, this.renderMoments(shown));
    this.root.replaceChildren(
      this.backLink(),
      this.renderActions(),
      h('div', { class: 'split' }, left, right),
      this.renderHistory(shown),
    );
  }

  private quoteText(id: number): EditorMoment | undefined {
    return this.bundle?.moments.find((m) => m.id === id);
  }

  private renderVersion(v: EditorVersion, isLatest: boolean): HTMLElement {
    const b = this.bundle;
    const content = v.content;
    const blocks = content?.blocks ?? [];

    const res = isLatest && b ? b.resolutions : [];
    const pending = isLatest ? pendingSentences(v, res) : [];
    const wrap = h(
      'div',
      { testid: 'version-view', 'data-version-id': v.id, 'data-version': v.version },
      isLatest ? null : h('p', { class: 'notice', testid: 'old-version' }, `Gledaš stariju verziju v${String(v.version)}. Radnje se odnose na zadnju verziju.`),
      h('p', { class: 'kicker' }, categoryLabel(v.category)),
      h('h1', { testid: 'admin-title' }, v.title),
      h('p', { class: 'lead', testid: 'admin-lead' }, v.lead ?? ''),
      h(
        'div',
        { class: 'body', testid: 'admin-body' },
        ...blocks.map((blk) => {
          if (blk.type === 'p') return h('p', {}, blk.text);
          const m = blk.moment_id === null ? undefined : this.quoteText(blk.moment_id);
          return h(
            'blockquote',
            { 'data-moment-id': blk.moment_id ?? '' },
            m ? `„${m.quote}” – ${m.speaker_name ?? m.speaker}, ${clock(m.start_ms)}` : `[citat ${blk.ref}: trenutak ne postoji]`,
          );
        }),
      ),
    );
    wrap.append(this.renderVerify(v, isLatest, pending));
    return wrap;
  }

  private renderVerify(v: EditorVersion, isLatest: boolean, pending: ReturnType<typeof pendingSentences>): HTMLElement {
    const verify = v.verify;
    if (!verify) {
      return h(
        'section',
        { class: 'panel verify', testid: 'verify-missing' },
        h('h2', {}, 'Provjera'),
        h('p', {}, 'Ova verzija još nije prošla automatsku provjeru (verify). Odobriti se može tek provjerena verzija.'),
      );
    }
    const resolved = new Map((this.bundle?.resolutions ?? []).filter((r) => r.version_id === v.id).map((r) => [r.n, r]));
    const items = verify.sentences.map((s) => {
      const r = resolved.get(s.n);
      const state = s.status === 'supported' ? 'supported' : r ? 'resolved' : 'pending';
      const li = h(
        'li',
        { testid: 'sentence', 'data-n': s.n, 'data-state': state, class: `sent ${state}` },
        h('span', { class: 'n' }, `${String(s.n)}.`),
        ' ',
        h('span', { class: 'text' }, s.text),
        h(
          'span',
          { class: 'why muted' },
          state === 'supported'
            ? s.metadata
              ? ' · podržano podacima o epizodi'
              : ` · podržano trenutkom ${s.supported_by.join(', ')}`
            : state === 'resolved' && r
              ? ` · ${r.resolution === 'verified' ? 'provjereno' : 'nije tvrdnja'}: ${r.note}`
              : ` · bez potpore${s.problems.length ? ` (${s.problems.map((p) => p.detail ?? p.code).join('; ')})` : ''}`,
        ),
      );
      if (state === 'pending' && isLatest) li.append(this.resolveForm(v, s.n));
      return li;
    });
    return h(
      'section',
      { class: 'panel verify', testid: 'verify' },
      h('h2', {}, 'Provjera rečenica'),
      h(
        'p',
        { class: 'muted' },
        `${String(verify.summary.supported)} od ${String(verify.summary.sentences)} rečenica ima potporu u snimci`,
        isLatest && pending.length > 0 ? `, ${String(pending.length)} čeka tvoje razrješenje` : '',
        '.',
      ),
      h('ol', { class: 'sentences' }, ...items),
      verify.removed.length > 0
        ? h(
            'div',
            {},
            h('h3', {}, 'Provjera je uklonila'),
            h('ul', {}, ...verify.removed.map((r) => h('li', {}, `${r.text} (${r.detail})`))),
          )
        : null,
      verify.style.length > 0
        ? h('div', {}, h('h3', {}, 'Stil (savjet)'), h('ul', {}, ...verify.style.map((s) => h('li', {}, s.detail))))
        : null,
    );
  }

  private resolveForm(v: EditorVersion, n: number): HTMLElement {
    const select = h(
      'select',
      { testid: 'resolve-kind', 'aria-label': 'Razrješenje' },
      h('option', { value: 'verified' }, 'Provjereno (snimka ili drugi izvor)'),
      h('option', { value: 'no_claim' }, 'Nije činjenična tvrdnja'),
    );
    const note = h('input', { testid: 'resolve-note', placeholder: 'Bilješka: gdje si provjerio', 'aria-label': 'Bilješka', required: true });
    const form = h('form', { class: 'resolve', testid: 'resolve-form', 'data-n': n }, select, note, h('button', { type: 'submit', testid: 'resolve-submit' }, 'Razriješi'));
    form.addEventListener('submit', (e) => {
      e.preventDefault();
      const api = this.api;
      if (!api) return;
      void this.act(`Rečenica ${String(n)} je razriješena.`, () =>
        api.resolve(v.id, n, select.value === 'no_claim' ? 'no_claim' : 'verified', note.value),
      );
    });
    return form;
  }

  // ---------------------------------------------------------------- radnje

  private renderActions(): HTMLElement {
    const b = this.bundle;
    const api = this.api;
    const bar = h('div', { class: 'actions', testid: 'actions' });
    if (!b || !api) return bar;
    const { article, latest } = b;
    const s = article.status;
    const note = h('input', { testid: 'action-note', placeholder: 'Bilješka ili obrazloženje', 'aria-label': 'Bilješka' });
    const noteVal = () => (note.value.trim() === '' ? null : note.value.trim());
    const add = (label: string, testid: string, fn: () => Promise<unknown>, done: string, cls = '') => {
      bar.append(button(label, testid, () => void this.act(done, fn), cls));
    };
    if (this.editing) return bar;
    if (s === 'draft') add('Pošalji u pregled', 'to-review', () => api.transition(article.id, 'review', noteVal()), 'Članak je u pregledu.');
    if (s === 'review') {
      add('Odobri', 'approve', () => api.approve(article.id, latest.id, noteVal()), 'Verzija je odobrena.', 'primary');
      add('Vrati u nacrt', 'to-draft', () => api.transition(article.id, 'draft', noteVal()), 'Članak je vraćen u nacrt.');
    }
    if (s === 'approved') {
      add('Objavi', 'publish', () => api.publish(article.id, noteVal()), 'Članak je objavljen.', 'primary');
      add('Vrati u pregled', 'to-review', () => api.transition(article.id, 'review', noteVal()), 'Članak je vraćen u pregled.');
    }
    if (s === 'draft' || s === 'review') {
      add('Odbij', 'reject', () => api.transition(article.id, 'rejected', noteVal()), 'Članak je odbijen.', 'danger');
    }
    if (s === 'rejected') add('Vrati u nacrt', 'to-draft', () => api.transition(article.id, 'draft', noteVal()), 'Članak je vraćen u nacrt.');
    if (s !== 'rejected' && s !== 'retracted') {
      bar.append(
        button('Uredi', 'edit', () => {
          this.editing = {
            title: latest.title,
            lead: latest.lead ?? '',
            category: latest.category ?? 'drustvo',
            blocks: editableBlocks(latest),
          };
          this.viewed = null;
          this.clearMessages();
          this.renderArticle();
        }),
      );
    }
    bar.append(note);
    const corr = correctionState(b);
    if (corr !== null) {
      // Ispravak objavljuje NOVU verziju (odluka 525): bez nje gumb bi samo
      // vratio „verzija je već objavljena”, pa se nudi tek kad je ima.
      const correctRow =
        corr === 'needs_edit'
          ? h('p', { class: 'muted', testid: 'correct-hint', 'data-state': corr }, CORRECTION_HINT[corr])
          : (() => {
              const kind = h('select', { testid: 'correct-kind', 'aria-label': 'Vrsta ispravka' }, ...CORRECTION_KINDS.map(([v, l]) => h('option', { value: v }, l)));
              const desc = h('input', { testid: 'correct-description', placeholder: 'Što je ispravljeno i zašto', 'aria-label': 'Opis ispravka' });
              const correct = button(`Objavi v${String(latest.version)} kao ispravak`, 'correct', () =>
                void this.act('Ispravak je objavljen.', () => api.correct(article.id, latest.id, kind.value, desc.value)),
              );
              if (corr !== 'ready') correct.disabled = true;
              return h(
                'div',
                {},
                h('p', { class: 'muted', testid: 'correct-hint', 'data-state': corr }, CORRECTION_HINT[corr]),
                h('div', { class: 'row' }, kind, desc, correct),
              );
            })();
      const reason = h('input', { testid: 'retract-reason', placeholder: 'Razlog povlačenja (javno)', 'aria-label': 'Razlog povlačenja' });
      const retract = button(
        'Povuci članak',
        'retract',
        () => void this.act('Članak je povučen.', () => api.retract(article.id, reason.value)),
        'danger',
      );
      bar.append(correctRow, h('div', { class: 'row' }, reason, retract));
    }
    return bar;
  }

  // ---------------------------------------------------------------- uređivanje

  private renderEditor(): HTMLElement {
    const ed = this.editing;
    const b = this.bundle;
    const api = this.api;
    if (!ed || !b || !api) return h('div');
    const title = h('input', { testid: 'editor-title', value: ed.title, 'aria-label': 'Naslov', class: 'wide' });
    title.addEventListener('input', () => (ed.title = title.value));
    const lead = h('textarea', { testid: 'editor-lead', rows: 3, 'aria-label': 'Uvod', class: 'wide' });
    lead.value = ed.lead;
    lead.addEventListener('input', () => (ed.lead = lead.value));
    const cat = h(
      'select',
      { testid: 'editor-category', 'aria-label': 'Kategorija' },
      ...CATEGORY_SLUGS.map((c) => h('option', { value: c, selected: c === ed.category }, CATEGORY_LABELS[c])),
    );
    cat.addEventListener('change', () => (ed.category = cat.value));
    const blocks = h('ol', { class: 'editor-blocks', testid: 'editor-blocks' });
    ed.blocks.forEach((blk, i) => {
      const move = (d: number) => () => {
        const j = i + d;
        if (j < 0 || j >= ed.blocks.length) return;
        const [x] = ed.blocks.splice(i, 1);
        if (x) ed.blocks.splice(j, 0, x);
        this.renderArticle();
      };
      const remove = () => {
        ed.blocks.splice(i, 1);
        this.renderArticle();
      };
      const tools = h(
        'span',
        { class: 'tools' },
        button('Gore', 'block-up', move(-1), 'link'),
        button('Dolje', 'block-down', move(1), 'link'),
        button('Ukloni', 'block-remove', remove, 'link'),
      );
      if (blk.type === 'p') {
        const ta = h('textarea', { testid: 'editor-block', rows: 4, 'data-type': 'p', class: 'wide', 'aria-label': `Odlomak ${String(i + 1)}` });
        ta.value = blk.text;
        ta.addEventListener('input', () => (blk.text = ta.value));
        blocks.append(h('li', {}, ta, tools));
      } else {
        const m = this.quoteText(blk.moment_id);
        blocks.append(
          h(
            'li',
            { testid: 'editor-block', 'data-type': 'quote', 'data-moment-id': blk.moment_id },
            h('blockquote', {}, m ? `„${m.quote}” – ${m.speaker_name ?? m.speaker}, ${clock(m.start_ms)}` : `[trenutak ${String(blk.moment_id)}]`),
            tools,
          ),
        );
      }
    });
    const addP = button('Dodaj odlomak', 'editor-add-paragraph', () => {
      ed.blocks.push({ type: 'p', text: '' });
      this.renderArticle();
    });
    const save = h('button', { type: 'submit', testid: 'editor-save', class: 'primary' }, 'Spremi novu verziju');
    const cancel = button('Odustani', 'editor-cancel', () => {
      this.editing = null;
      this.renderArticle();
    });
    const form = h(
      'form',
      { class: 'editor', testid: 'editor' },
      h('h2', {}, `Uređivanje (na temelju v${String(b.latest.version)})`),
      h('p', { class: 'muted' }, 'Citat dodaješ iz popisa trenutaka desno. Tekst citata se ne piše: dolazi iz snimke.'),
      h('label', {}, 'Naslov', title),
      h('label', {}, 'Uvod', lead),
      h('label', {}, 'Kategorija ', cat),
      blocks,
      h('p', {}, addP),
      h('p', {}, save, ' ', cancel),
    );
    form.addEventListener('submit', (e) => {
      e.preventDefault();
      const blocksOut = ed.blocks.filter((x) => x.type === 'quote' || x.text.trim() !== '');
      void this.act('Nova verzija je spremljena. Prije odobravanja mora proći automatsku provjeru.', () =>
        api.saveVersion({
          articleId: b.article.id,
          latestVersionId: b.latest.id,
          title: ed.title,
          lead: ed.lead,
          category: ed.category,
          blocks: blocksOut,
        }),
      );
    });
    return form;
  }

  // ---------------------------------------------------------------- trenuci

  private renderMoments(v: EditorVersion): HTMLElement {
    const b = this.bundle;
    if (!b) return h('div');
    const videoId = v.content?.episode.videoId ?? '';
    const file = this.media.get(videoId) ?? null;
    const quoted = new Set(
      (this.editing ? this.editing.blocks : editableBlocks(v)).flatMap((x) => (x.type === 'quote' ? [x.moment_id] : [])),
    );
    const ep = v.content?.episode;
    return h(
      'div',
      {},
      h('h2', {}, 'Izvorni trenuci'),
      ep
        ? h(
            'p',
            { class: 'muted', testid: 'admin-episode' },
            `${ep.title ?? videoId} · ${ep.channelName ?? ep.channel ?? ''}${ep.date ? ` · ${ep.date}` : ''} · `,
            h('a', { href: appEpisodeUrl(this.cfg.appBase, videoId), target: '_blank', rel: 'noopener' }, 'otvori u aplikaciji'),
          )
        : null,
      file ? null : h('p', { class: 'notice' }, 'Za ovu epizodu nema datoteke za isječke na CDN-u.'),
      h(
        'ol',
        { class: 'moment-list' },
        ...b.moments.map((m) => {
          const inArticle = quoted.has(m.id);
          const li = h(
            'li',
            { testid: 'moment', 'data-moment-id': m.id, 'data-quoted': inArticle ? 'true' : 'false', class: inArticle ? 'quoted' : '' },
            h(
              'p',
              { class: 'meta' },
              h('strong', {}, m.speaker_name ?? m.speaker),
              ` · ${clock(m.start_ms)}–${clock(m.end_ms)} · ${m.quote_check}${m.quote_lang !== 'hr' ? ` · ${m.quote_lang}` : ''}`,
              inArticle ? h('span', { class: 'badge s-approved' }, ' u članku') : null,
            ),
            h('p', { class: 'mq' }, `„${m.quote}”`),
            file
              ? h('audio', {
                  controls: true,
                  preload: 'none',
                  testid: 'moment-audio',
                  src: clipUrl(this.cfg.cdnBase, m.video_id, file, m.start_ms, m.end_ms),
                })
              : null,
          );
          const ed = this.editing;
          if (ed && !inArticle) {
            li.append(
              button('Dodaj citat u članak', 'moment-add', () => {
                ed.blocks.push({ type: 'quote', moment_id: m.id });
                this.renderArticle();
              }),
            );
          }
          return li;
        }),
      ),
    );
  }

  // ---------------------------------------------------------------- povijest

  private renderHistory(shown: EditorVersion): HTMLElement {
    const b = this.bundle;
    if (!b) return h('div');
    const versions = h(
      'ol',
      { class: 'history', testid: 'version-history', reversed: true },
      ...b.versions.map((v) => {
        const label = `v${String(v.version)} · ${v.created_by ?? 'nepoznato'} · ${hrDateTime(v.created_at) ?? ''}${
          v.verify ? ` · provjera ${String(v.verify.summary.supported)}/${String(v.verify.summary.sentences)}` : ' · bez provjere'
        }${v.id === b.article.published_version_id ? ' · objavljena' : ''}${v.id === b.article.approved_version_id ? ' · odobrena' : ''}`;
        const view = button(v.id === shown.id ? 'prikazana' : 'prikaži', 'version-show', () => {
          this.viewed = v.id;
          this.editing = null;
          this.renderArticle();
        }, 'link');
        if (v.id === shown.id) view.disabled = true;
        return h('li', { testid: 'version-item', 'data-version-id': v.id, 'data-version': v.version }, label, ' ', view);
      }),
    );
    const events = h(
      'ol',
      { class: 'events', testid: 'events' },
      ...b.events.map((e) =>
        h(
          'li',
          { testid: 'event', 'data-to': e.to_status },
          `${hrDateTime(e.created_at) ?? ''} · ${e.from_status ? STATUS_LABEL[e.from_status] : 'nastanak'} → ${STATUS_LABEL[e.to_status]} · ${e.actor_label}${e.note ? ` · ${e.note}` : ''}`,
        ),
      ),
    );
    const corrections =
      b.corrections.length === 0
        ? null
        : h(
            'div',
            {},
            h('h3', {}, 'Ispravci'),
            h('ol', {}, ...b.corrections.map((c) => h('li', { testid: 'admin-correction' }, `${hrDateTime(c.created_at) ?? ''} · ${c.kind}: ${c.description}`))),
          );
    return h('section', { class: 'panel' }, h('h2', {}, 'Povijest verzija'), versions, h('h2', {}, 'Dnevnik'), events, corrections);
  }
}

async function main(): Promise<void> {
  const cfg = readConfig();
  const auth = await loadAuth({ authUrl: cfg.authUrl, anonKey: cfg.anonKey });
  await new Admin(cfg, auth).start();
  document.body.dataset.ready = 'true';
}

void main().catch((e: unknown) => {
  const box = document.getElementById('admin-error');
  if (box) {
    box.textContent = describeError(e).text;
    box.hidden = false;
  }
  document.body.dataset.ready = 'error';
});
