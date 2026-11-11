// Admin urednika: red čekanja i članak u JEDNOM stupcu (S8 redizajn). Traka
// koraka s jednim sljedećim korakom i razlogom blokade; označena rečenica stoji
// u tekstu, a ispod nje izvorni trenutak s „Poslušaj” (jedan player na dnu) i
// potvrda na istom mjestu. Vanilla TS bez frameworka; podaci se crtaju kroz
// `textContent` (nikad innerHTML), pa tekst iz baze ne može postati kod.
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
  type Resolution,
  type SentenceCheck,
  type Status,
} from './api.js';
import {
  STEPS,
  blockerText,
  nextStep,
  plural,
  problemText,
  segmentText,
  sentencesByPlace,
  stepOf,
  type NextAction,
} from './flow.js';
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

interface SentenceCtx {
  v: EditorVersion;
  isLatest: boolean;
  resolved: Map<number, Resolution>;
}

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
  /** Rečenice s potporom koje je urednik otvorio da vidi izvor. */
  private openSentences = new Set<number>();
  private momentFilter = '';

  private readonly root = byId('admin');
  private readonly status = byId('admin-status');
  private readonly errorBox = byId('admin-error');
  private readonly playerBar = byId('admin-player');
  private readonly player = byId('admin-player-audio') as HTMLAudioElement;
  private readonly playerLabel = byId('admin-player-label');

  constructor(
    private readonly cfg: AdminConfig,
    private readonly auth: AuthApi,
  ) {}

  async start(): Promise<void> {
    byId('admin-player-close').addEventListener('click', () => {
      this.player.pause();
      this.playerBar.hidden = true;
    });
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
    this.openSentences.clear();
    this.momentFilter = '';
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
    const article = h(
      'article',
      { class: 'read', testid: 'admin-article', 'data-article-id': b.article.id, 'data-status': b.article.status },
      this.editing ? this.renderEditor() : this.renderVersion(shown, isLatest),
    );
    const parts: (HTMLElement | null)[] = [
      this.backLink(),
      this.renderEpisode(shown),
      this.renderFlow(),
      article,
      this.editing ? null : this.renderVerifyNotes(shown),
      this.renderHistory(shown),
    ];
    this.root.replaceChildren(...parts.filter((x): x is HTMLElement => x !== null));
  }

  private momentById(id: number): EditorMoment | undefined {
    return this.bundle?.moments.find((m) => m.id === id);
  }

  private quoteLine(m: EditorMoment | undefined, fallback: string): string {
    return m ? `„${m.quote}” – ${m.speaker_name ?? m.speaker}, ${clock(m.start_ms)}` : fallback;
  }

  // ---------------------------------------------------------------- epizoda i tok

  private renderEpisode(v: EditorVersion): HTMLElement | null {
    const ep = v.content?.episode;
    if (!ep) return null;
    return h(
      'p',
      { class: 'episode-line muted', testid: 'admin-episode' },
      'Izvor: ',
      h('strong', {}, ep.title ?? ep.videoId),
      ` · ${ep.channelName ?? ep.channel ?? ''}${ep.date ? ` · ${ep.date}` : ''} · `,
      h('a', { href: appEpisodeUrl(this.cfg.appBase, ep.videoId), target: '_blank', rel: 'noopener' }, 'otvori epizodu u aplikaciji'),
    );
  }

  /** Traka koraka + jedan sljedeći korak s razlogom blokade + sporedne radnje. */
  private renderFlow(): HTMLElement {
    const b = this.bundle;
    const api = this.api;
    const box = h('section', { class: 'flow', testid: 'actions' });
    if (!b || !api) return box;
    const { article, latest } = b;
    const s = article.status;

    const current = stepOf(s);
    const idx = current === null ? -1 : STEPS.findIndex((x) => x.key === current);
    const steps = h(
      'ol',
      { class: 'steps', testid: 'steps', 'data-current': current ?? s },
      ...STEPS.map((step, i) =>
        h(
          'li',
          {
            class: i < idx ? 'done' : i === idx ? 'current' : 'todo',
            'data-step': step.key,
            'aria-current': i === idx ? 'step' : undefined,
            testid: i === idx && step.key === s ? 'article-status' : undefined,
          },
          step.label,
        ),
      ),
    );
    box.append(
      h(
        'div',
        { class: 'flow-head' },
        // Stanje je na traci kad je korak isti kao stanje; inače (ispravljeno,
        // odbijeno, povučeno) stoji kao oznaka uz traku.
        current === s ? null : h('span', { class: `badge s-${s}`, testid: 'article-status' }, STATUS_LABEL[s]),
        current === null ? null : steps,
        ['published', 'corrected', 'retracted'].includes(s)
          ? h('a', { href: `${this.cfg.portalBase}/${article.slug}`, target: '_blank', rel: 'noopener', testid: 'public-link' }, 'javna stranica')
          : null,
      ),
    );
    if (this.editing) {
      box.append(h('p', { class: 'muted' }, 'Uređuješ članak. Spremanje stvara novu verziju koju zatim provjerava engine.'));
      return box;
    }

    const note = h('input', { testid: 'action-note', placeholder: 'Bilješka uz radnju (neobavezno, ide u dnevnik)', 'aria-label': 'Bilješka' });
    const noteVal = () => (note.value.trim() === '' ? null : note.value.trim());
    const run = (action: NextAction | 'reject' | 'to-review-back') => {
      switch (action) {
        case 'to-review':
          return this.act('Članak je u pregledu.', () => api.transition(article.id, 'review', noteVal()));
        case 'to-review-back':
          return this.act('Članak je vraćen u pregled.', () => api.transition(article.id, 'review', noteVal()));
        case 'approve':
          return this.act('Verzija je odobrena.', () => api.approve(article.id, latest.id, noteVal()));
        case 'publish':
          return this.act('Članak je objavljen.', () => api.publish(article.id, noteVal()));
        case 'to-draft':
          return this.act('Članak je vraćen u nacrt.', () => api.transition(article.id, 'draft', noteVal()));
        case 'reject':
          return this.act('Članak je odbijen.', () => api.transition(article.id, 'rejected', noteVal()));
      }
    };

    const next = nextStep(b);
    if (next.action) {
      const action = next.action;
      const primary = button(next.label, action, () => void run(action), 'primary');
      const blocked = next.blockers.length > 0;
      if (blocked) {
        primary.disabled = true;
        primary.setAttribute('aria-describedby', 'next-blockers');
      }
      const blockers = blocked
        ? h(
            'ul',
            { class: 'blockers', id: 'next-blockers', testid: 'blockers' },
            ...next.blockers.map((bl) => {
              const li = h('li', { testid: 'blocker', 'data-kind': bl.kind }, `Ne može još: ${blockerText(bl)}.`);
              if (bl.kind === 'sentences') {
                li.append(' ', button('Prijeđi na prvu', 'goto-pending', () => {
                  this.scrollToSentence(bl.first);
                }, 'link'));
              } else {
                li.append(
                  ' ',
                  bl.byEditor
                    ? 'Spremljena je u adminu, pa je engine mora ponovno provjeriti prije odobravanja. Provjeru pokreće dnevni posao vijesti; kad završi, ovdje se pojave rečenice za potvrdu.'
                    : 'Provjeru pokreće dnevni posao vijesti; kad završi, ovdje se pojave rečenice za potvrdu.',
                );
              }
              return li;
            }),
          )
        : null;
      box.append(
        h(
          'div',
          { class: `next${blocked ? ' blocked' : ''}`, testid: 'next-step', 'data-action': action, 'data-blocked': blocked ? 'true' : 'false' },
          h('p', { class: 'next-label' }, 'Sljedeći korak'),
          h('div', { class: 'next-row' }, primary, h('span', { class: 'muted next-hint' }, next.hint)),
          blockers,
        ),
      );
    } else if (s === 'published' || s === 'corrected') {
      box.append(h('p', { class: 'muted', testid: 'next-step', 'data-action': 'none' }, 'Članak je objavljen. Promjena ide kao ispravak (ispod), uz javni zapis.'));
    } else if (s === 'retracted') {
      box.append(h('p', { class: 'muted', testid: 'next-step', 'data-action': 'none' }, 'Članak je povučen. Javna stranica pokazuje razlog povlačenja.'));
    }

    const more = h('div', { class: 'more' });
    if (s !== 'rejected' && s !== 'retracted') {
      more.append(
        button('Uredi tekst', 'edit', () => {
          this.startEditing();
        }),
      );
    }
    if (s === 'review') more.append(button('Vrati u nacrt', 'to-draft', () => void run('to-draft')));
    if (s === 'approved') more.append(button('Vrati u pregled', 'to-review', () => void run('to-review-back')));
    if (s === 'draft' || s === 'review') more.append(button('Odbij', 'reject', () => void run('reject'), 'danger'));
    if (more.childElementCount > 0 || next.action) {
      more.append(note);
      box.append(more);
    }

    const corr = correctionState(b);
    if (corr !== null) box.append(this.renderCorrection(corr));
    return box;
  }

  private renderCorrection(corr: CorrectionState): HTMLElement {
    const b = this.bundle;
    const api = this.api;
    if (!b || !api) return h('div');
    const { article, latest } = b;
    // Ispravak objavljuje NOVU verziju (odluka 514): bez nje gumb bi samo
    // vratio „verzija je već objavljena”, pa se nudi tek kad je ima.
    const correctRow =
      corr === 'needs_edit'
        ? null
        : (() => {
            const kind = h('select', { testid: 'correct-kind', 'aria-label': 'Vrsta ispravka' }, ...CORRECTION_KINDS.map(([v, l]) => h('option', { value: v }, l)));
            const desc = h('input', { testid: 'correct-description', placeholder: 'Što je ispravljeno i zašto (javno)', 'aria-label': 'Opis ispravka' });
            const correct = button(
              `Objavi v${String(latest.version)} kao ispravak`,
              'correct',
              () => void this.act('Ispravak je objavljen.', () => api.correct(article.id, latest.id, kind.value, desc.value)),
              'primary',
            );
            if (corr !== 'ready') correct.disabled = true;
            return h('div', { class: 'row' }, kind, desc, correct);
          })();
    const reason = h('input', { testid: 'retract-reason', placeholder: 'Razlog povlačenja (javno)', 'aria-label': 'Razlog povlačenja' });
    const retract = button('Povuci članak', 'retract', () => void this.act('Članak je povučen.', () => api.retract(article.id, reason.value)), 'danger');
    return h(
      'div',
      { class: 'correction' },
      h('h2', {}, 'Ispravak'),
      h('p', { class: 'muted', testid: 'correct-hint', 'data-state': corr }, CORRECTION_HINT[corr]),
      correctRow,
      h('h2', {}, 'Povlačenje'),
      h('div', { class: 'row' }, reason, retract),
    );
  }

  private startEditing(): void {
    const latest = this.bundle?.latest;
    if (!latest) return;
    this.editing = {
      title: latest.title,
      lead: latest.lead ?? '',
      category: latest.category ?? 'drustvo',
      blocks: editableBlocks(latest),
    };
    this.viewed = null;
    this.clearMessages();
    this.renderArticle();
    window.scrollTo({ top: 0 });
  }

  private scrollToSentence(n: number): void {
    const el = this.root.querySelector<HTMLElement>(`[data-testid=sentence][data-n="${String(n)}"]`);
    if (!el) return;
    el.scrollIntoView({ behavior: 'smooth', block: 'center' });
    el.querySelector<HTMLElement>('input, select, button')?.focus({ preventScroll: true });
  }

  // ---------------------------------------------------------------- članak s rečenicama

  private renderVersion(v: EditorVersion, isLatest: boolean): HTMLElement {
    const b = this.bundle;
    const content = v.content;
    const blocks = content?.blocks ?? [];
    const byPlace = sentencesByPlace(v.verify?.sentences ?? []);
    const resolved = new Map(isLatest && b ? b.resolutions.filter((r) => r.version_id === v.id).map((r) => [r.n, r]) : []);
    const ctx: SentenceCtx = { v, isLatest, resolved };

    const wrap = h(
      'div',
      { testid: 'version-view', 'data-version-id': v.id, 'data-version': v.version },
      isLatest ? null : h('p', { class: 'notice', testid: 'old-version' }, `Gledaš stariju verziju v${String(v.version)}. Radnje se odnose na zadnju verziju.`),
      v.verify ? this.renderLegend(v, isLatest) : h('p', { class: 'notice', testid: 'verify-missing' }, `Verzija v${String(v.version)} još nema automatsku provjeru, pa rečenice nisu označene.`),
      h('p', { class: 'kicker' }, categoryLabel(v.category)),
    );
    wrap.append(...this.placed('h1', { testid: 'admin-title' }, v.title, byPlace.get('title') ?? [], ctx));
    wrap.append(...this.placed('p', { class: 'lead', testid: 'admin-lead' }, v.lead ?? '', byPlace.get('lead') ?? [], ctx));
    const body = h('div', { class: 'body', testid: 'admin-body' });
    blocks.forEach((blk, i) => {
      if (blk.type === 'p') {
        body.append(...this.placed('p', {}, blk.text, byPlace.get(`block:${String(i)}`) ?? [], ctx));
        return;
      }
      const m = blk.moment_id === null ? undefined : this.momentById(blk.moment_id);
      body.append(
        h(
          'figure',
          { class: 'quote-block', 'data-moment-id': blk.moment_id ?? '' },
          h('blockquote', {}, this.quoteLine(m, `[citat ${blk.ref}: trenutak ne postoji]`)),
          m ? h('figcaption', {}, this.listenControls(m)) : null,
        ),
      );
    });
    wrap.append(body);
    return wrap;
  }

  private renderLegend(v: EditorVersion, isLatest: boolean): HTMLElement {
    const verify = v.verify;
    if (!verify) return h('div');
    const pending = isLatest && this.bundle ? pendingSentences(v, this.bundle.resolutions).length : 0;
    return h(
      'p',
      { class: 'legend muted', testid: 'verify' },
      `${String(verify.summary.supported)} od ${String(verify.summary.sentences)} rečenica ima potporu u snimci. `,
      pending > 0
        ? h('span', { class: 'mark pending' }, `${String(pending)} ${plural(pending, 'označena čeka', 'označene čekaju', 'označenih čeka')} tvoju potvrdu`)
        : null,
      pending > 0 ? ': poslušaj izvor ispod rečenice i potvrdi je ili je uredi. ' : '',
      'Klik na bilo koju rečenicu pokazuje iz kojeg je trenutka snimke.',
    );
  }

  /**
   * Element s tekstom razlomljenim na rečenice provjere, a ispod njega kartice
   * označenih (i otvorenih) rečenica. Ako se tekst i provjera ne poklapaju,
   * tekst ostaje običan, a kartice svih rečenica s problemom idu ispod.
   */
  private placed(
    tag: 'h1' | 'p',
    attrs: Record<string, string>,
    text: string,
    sentences: readonly SentenceCheck[],
    ctx: SentenceCtx,
  ): HTMLElement[] {
    const el = h(tag, attrs);
    const segs = sentences.length > 0 ? segmentText(text, sentences) : null;
    if (!segs) el.append(text);
    else {
      for (const seg of segs) {
        if (seg.kind === 'text') el.append(seg.text);
        else el.append(this.sentenceMark(seg.sentence, ctx));
      }
    }
    const cards = sentences
      .filter((s) => this.sentenceState(s, ctx) !== 'supported' || this.openSentences.has(s.n))
      .map((s) => this.sentenceCard(s, ctx));
    return cards.length > 0 ? [el, h('div', { class: 'sent-cards' }, ...cards)] : [el];
  }

  private sentenceState(s: SentenceCheck, ctx: SentenceCtx): 'supported' | 'resolved' | 'pending' {
    if (s.status === 'supported') return 'supported';
    return ctx.resolved.has(s.n) || !ctx.isLatest ? 'resolved' : 'pending';
  }

  private sentenceMark(s: SentenceCheck, ctx: SentenceCtx): HTMLElement {
    const state = this.sentenceState(s, ctx);
    const open = state !== 'supported' || this.openSentences.has(s.n);
    const mark = h(
      'span',
      { class: `mark ${state}${open ? ' open' : ''}`, testid: 'sentence-mark', 'data-n': s.n, role: 'button', tabindex: 0, 'aria-expanded': open ? 'true' : 'false', title: 'Iz kojeg je trenutka snimke' },
      s.text,
    );
    const toggle = () => {
      if (state === 'supported') {
        if (this.openSentences.has(s.n)) this.openSentences.delete(s.n);
        else this.openSentences.add(s.n);
        this.renderArticle();
      }
      this.scrollToSentence(s.n);
    };
    mark.addEventListener('click', toggle);
    mark.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        toggle();
      }
    });
    return mark;
  }

  private sentenceCard(s: SentenceCheck, ctx: SentenceCtx): HTMLElement {
    const state = this.sentenceState(s, ctx);
    const r = ctx.resolved.get(s.n);
    const head =
      state === 'pending'
        ? 'čeka tvoju potvrdu'
        : state === 'resolved'
          ? r
            ? r.resolution === 'verified'
              ? 'potvrđena'
              : 'nije činjenična tvrdnja'
            : 'bez potpore u provjeri'
          : s.metadata
            ? 'potpora: podaci o epizodi'
            : 'ima potporu u snimci';
    const card = h(
      'div',
      { class: `sent-card ${state}`, testid: 'sentence', 'data-n': s.n, 'data-state': state },
      h('p', { class: 'sent-head' }, h('strong', {}, `Rečenica ${String(s.n)}`), ` · ${head}`),
    );
    if (state !== 'supported' && s.problems.length > 0) {
      card.append(h('p', { class: 'sent-why' }, `Zašto je označena: ${s.problems.map(problemText).join('; ')}.`));
    }
    if (r) card.append(h('p', { class: 'sent-note' }, `Bilješka: ${r.note}`));
    if (state !== 'resolved' || !r) {
      const sources = s.supported_by.map((id) => this.momentById(id));
      if (s.metadata && sources.length === 0) {
        card.append(h('p', { class: 'muted' }, 'Tvrdnja dolazi iz podataka o epizodi (naslov, kanal, datum), ne iz govora.'));
      } else if (sources.length === 0) {
        const vid = ctx.v.content?.episode.videoId;
        card.append(
          h(
            'p',
            { class: 'muted' },
            'Provjera nije navela trenutak snimke. ',
            vid ? h('a', { href: appEpisodeUrl(this.cfg.appBase, vid), target: '_blank', rel: 'noopener' }, 'Poslušaj epizodu u aplikaciji') : null,
          ),
        );
      } else {
        card.append(
          h('p', { class: 'sent-sub' }, state === 'pending' ? 'Poslušaj što je rečeno:' : 'Izvor:'),
          ...s.supported_by.map((id, i) => {
            const m = sources[i];
            return m ? this.sourceItem(m) : h('p', { class: 'muted' }, `[trenutak ${String(id)} nije u popisu potvrđenih citata]`);
          }),
        );
      }
    }
    if (state === 'pending') card.append(this.resolveForm(ctx.v, s.n));
    if (state === 'supported') {
      card.append(
        button('Zatvori', 'sentence-close', () => {
          this.openSentences.delete(s.n);
          this.renderArticle();
        }, 'link'),
      );
    }
    return card;
  }

  private sourceItem(m: EditorMoment): HTMLElement {
    return h(
      'div',
      { class: 'source', testid: 'source', 'data-moment-id': m.id },
      h('p', { class: 'source-quote' }, `„${m.quote}”`),
      h('p', { class: 'source-meta' }, this.listenControls(m)),
    );
  }

  /** „Poslušaj” (jedan player na dnu ekrana) + vrijeme + poveznica u aplikaciju na tu sekundu. */
  private listenControls(m: EditorMoment): HTMLElement {
    const file = this.media.get(m.video_id) ?? null;
    const label = `${m.speaker_name ?? m.speaker} · ${clock(m.start_ms)}–${clock(m.end_ms)}`;
    const app = h(
      'a',
      { href: appEpisodeUrl(this.cfg.appBase, m.video_id, m.start_ms), target: '_blank', rel: 'noopener', testid: 'listen-app' },
      'u aplikaciji',
    );
    const play = file
      ? button('Poslušaj', 'listen', () => {
          this.play(m, file);
        }, 'listen')
      : null;
    return h('span', { class: 'listen-row' }, play, play ? ' ' : null, h('span', { class: 'muted' }, label), ' · ', app);
  }

  private play(m: EditorMoment, file: string): void {
    const bar = this.playerBar;
    const audio = this.player;
    audio.src = clipUrl(this.cfg.cdnBase, m.video_id, file, m.start_ms, m.end_ms);
    audio.dataset.momentId = String(m.id);
    this.playerLabel.textContent = `${m.speaker_name ?? m.speaker} · ${clock(m.start_ms)}–${clock(m.end_ms)}: „${m.quote}”`;
    bar.hidden = false;
    void audio.play().catch(() => {
      // Autoplay politika ili mreža: kontrole su vidljive, urednik pokrene sam.
    });
  }

  private resolveForm(v: EditorVersion, n: number): HTMLElement {
    const select = h(
      'select',
      { testid: 'resolve-kind', 'aria-label': 'Razrješenje' },
      h('option', { value: 'verified' }, 'Rečeno je u snimci (poslušao sam)'),
      h('option', { value: 'no_claim' }, 'Nije činjenična tvrdnja'),
    );
    const note = h('input', { testid: 'resolve-note', placeholder: 'Bilješka: gdje si provjerio (npr. 3:45)', 'aria-label': 'Bilješka', required: true });
    const edit = button('Uredi tekst', 'resolve-edit', () => {
      this.startEditing();
    }, 'link');
    const form = h(
      'form',
      { class: 'resolve', testid: 'resolve-form', 'data-n': n },
      select,
      note,
      h('button', { type: 'submit', testid: 'resolve-submit', class: 'primary' }, 'Potvrdi'),
      edit,
    );
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

  private renderVerifyNotes(v: EditorVersion): HTMLElement | null {
    const verify = v.verify;
    if (!verify || (verify.removed.length === 0 && verify.style.length === 0)) return null;
    return h(
      'section',
      { class: 'panel', testid: 'verify-notes' },
      verify.removed.length > 0
        ? h('div', {}, h('h2', {}, 'Provjera je uklonila'), h('ul', {}, ...verify.removed.map((r) => h('li', {}, `${r.text} (${r.detail})`))))
        : null,
      verify.style.length > 0 ? h('div', {}, h('h2', {}, 'Stil (savjet)'), h('ul', {}, ...verify.style.map((s) => h('li', {}, s.detail)))) : null,
    );
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
        const m = this.momentById(blk.moment_id);
        blocks.append(
          h(
            'li',
            { testid: 'editor-block', 'data-type': 'quote', 'data-moment-id': blk.moment_id },
            h('blockquote', {}, this.quoteLine(m, `[trenutak ${String(blk.moment_id)}]`)),
            m ? h('p', {}, this.listenControls(m)) : null,
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
      h(
        'p',
        { class: 'muted' },
        'Nova verzija prije odobravanja ponovno prolazi automatsku provjeru. Citat se ne piše rukom: dodaješ ga iz snimke (ispod).',
      ),
      h('label', {}, 'Naslov', title),
      h('label', {}, 'Uvod', lead),
      h('label', {}, 'Kategorija ', cat),
      blocks,
      h('p', {}, addP),
      this.renderMomentPicker(),
      h('p', { class: 'editor-save' }, save, ' ', cancel),
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

  /** Citati iz snimke za uređivanje: filtar po tekstu, „Poslušaj” i „Dodaj”. */
  private renderMomentPicker(): HTMLElement {
    const b = this.bundle;
    const ed = this.editing;
    if (!b || !ed) return h('div');
    const quoted = new Set(ed.blocks.flatMap((x) => (x.type === 'quote' ? [x.moment_id] : [])));
    const filter = h('input', { testid: 'moment-filter', placeholder: 'Traži u citatima (riječ, govornik)', 'aria-label': 'Traži citat', value: this.momentFilter });
    const list = h('ol', { class: 'moment-list', testid: 'moments' });
    const fill = () => {
      const q = this.momentFilter.trim().toLowerCase();
      const items = b.moments.filter(
        (m) => q === '' || m.quote.toLowerCase().includes(q) || (m.speaker_name ?? m.speaker).toLowerCase().includes(q),
      );
      list.replaceChildren(
        ...items.map((m) => {
          const inArticle = quoted.has(m.id);
          return h(
            'li',
            { testid: 'moment', 'data-moment-id': m.id, 'data-quoted': inArticle ? 'true' : 'false', class: inArticle ? 'quoted' : '' },
            h('p', { class: 'source-quote' }, `„${m.quote}”`),
            h(
              'p',
              { class: 'source-meta' },
              this.listenControls(m),
              ' ',
              inArticle
                ? h('span', { class: 'badge s-approved' }, 'u članku')
                : button('Dodaj u članak', 'moment-add', () => {
                    ed.blocks.push({ type: 'quote', moment_id: m.id });
                    this.renderArticle();
                  }),
            ),
          );
        }),
      );
    };
    filter.addEventListener('input', () => {
      this.momentFilter = filter.value;
      fill();
    });
    fill();
    return h(
      'details',
      { class: 'picker', testid: 'moment-picker' },
      h('summary', {}, `Dodaj citat iz snimke (${String(b.moments.length)} potvrđenih trenutaka)`),
      filter,
      list,
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
    return h(
      'details',
      { class: 'panel history-box', testid: 'history', open: this.viewed !== null },
      h('summary', {}, `Povijest: ${String(b.versions.length)} ${plural(b.versions.length, 'verzija', 'verzije', 'verzija')}, dnevnik, ispravci`),
      h('h2', {}, 'Verzije'),
      versions,
      h('h2', {}, 'Dnevnik'),
      events,
      corrections,
    );
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
