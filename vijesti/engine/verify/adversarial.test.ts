// Pokušaj rušenja provjere citata nad STVARNIM fixtureima (S2, odluke 210–213).
// Iz pravih cueova se sustavno (deterministički, više cueova po fixtureu)
// rade pokvareni citati; nijedan ne smije proći kao exact/fuzzy/srt_only.
// Kontrola: doslovni citati istih cueova prolaze, pa test ne prolazi samo
// zato što sve pada.
import { beforeAll, describe, expect, it } from 'vitest';
import { createCdnClient } from '../cdn/loader.js';
import type { TimedCue } from '../cdn/words.js';
import { decideQuoteLang, QuoteLangError } from '../extract/lang.js';
import { createFakeCdn } from '../test/fake-cdn.js';
import { loadFixtureCues, MEASURE_FIXTURES } from './measure.js';
import { normalizeWords } from './normalize.js';
import {
  DEFAULT_WINDOW_MS,
  FILLERS,
  NEGATIONS,
  oneCharTailEdit,
  verifyQuote,
  type QuoteClaim,
  type RejectReason,
  type VerifyResult,
} from './quote.js';

const cues = new Map<string, TimedCue[]>();
beforeAll(async () => {
  for (const f of MEASURE_FIXTURES) cues.set(f.id, await loadFixtureCues(f));
  // Hrvatski PRIJEVOD engleske epizode (diarized.srt), za test zamjene jezika.
  const cdn = createCdnClient({ fetch: createFakeCdn().fetch });
  cues.set('x3w2BVZJ9vQ:hr', (await cdn.loadEpisode('x3w2BVZJ9vQ')).cues);
});

const get = (id: string): TimedCue[] => {
  const c = cues.get(id);
  if (!c) throw new Error(`nema ${id}`);
  return c;
};

/** Izmišljene, uvjerljive rečenice iste teme (riječi iz epizode, rečenica ne postoji). */
const FABRICATED: Record<string, string[]> = {
  'pIx_7N-6HJ4': [
    'Židovi su Pashu uvijek slavili u četvrtak navečer, a ne u petak.',
    'Isus je posljednju večeru blagovao sa svojim učenicima u srijedu navečer.',
  ],
  'P9sLks-f2mQ': [
    'Djeca u Africi nemaju pristup školama i zato smo otišli tamo volontirati.',
    'Moj tata me nikad nije podržavao u odluci da idem u Afriku.',
  ],
  'x3w2BVZJ9vQ': [
    'Social media is the most important tool for evangelization in the Church today.',
    'We have more than one million followers on TikTok right now.',
  ],
  'MGLq9v3AtvE': [
    'Senko je prvi put instalirao Flutter i sve je radilo bez ijedne greške.',
    'Claude je potrošio dvjesto dolara za jedan sat rada na aplikaciji.',
  ],
  'b-nls1ck8EE': [
    'ZEF je osnovan prije dvanaest godina kao banka za hrvatske poduzetnike.',
    'Zadruga je u prvoj godini prikupila više od milijun eura depozita.',
  ],
};

const NUMBER_WORDS: Record<string, string> = {
  jedan: 'dva', dva: 'tri', dvije: 'tri', tri: 'četiri', četiri: 'pet', pet: 'šest', deset: 'dvadeset',
  dvadeset: 'trideset', sto: 'dvjesto', tisuću: 'dvije tisuće', milijun: 'milijardu',
  one: 'two', two: 'three', three: 'four', ten: 'twenty', hundred: 'thousand', thousand: 'million',
};

const content = (w: string) => normalizeWords(w).filter((n) => !FILLERS.has(n.t)).length;
const letters = (w: string) => w.replace(/[^\p{L}\p{M}\p{N}]/gu, '');
const endsSentence = (c: TimedCue | undefined) => !c || /[.!?…:]["”»]?$/.test(c.text.trim());

/**
 * Cueovi za napad: s govornikom, ≥ 10 riječi, cue počinje rečenicu (prethodni
 * cue završava rečenicu ili je drugi govornik). Do 12, ravnomjerno po titlu.
 */
function pick(cs: readonly TimedCue[]): number[] {
  const ok = cs
    .map((c, i) => ({ c, i }))
    .filter(({ c, i }) => {
      const prev = cs[i - 1];
      return (
        c.speaker !== null &&
        content(c.text) >= 10 &&
        (prev?.speaker !== c.speaker || endsSentence(prev))
      );
    })
    .map(({ i }) => i);
  const step = Math.max(1, Math.floor(ok.length / 12));
  return ok.filter((_, k) => k % step === 0).slice(0, 12);
}

interface Attack {
  kind: string;
  claim: QuoteClaim;
  /** Očekivani razlog, kad je određen; inače bilo koji `failed`. */
  reason?: RejectReason;
}

function midContentIndex(ws: string[]): number {
  const mid = Math.floor(ws.length / 2);
  for (let d = 0; d < ws.length; d++) {
    for (const k of [mid + d, mid - d]) {
      const w = ws[k];
      if (k <= 0 || k >= ws.length - 1 || !w) continue;
      const t = normalizeWords(w)[0]?.t;
      const prev = normalizeWords(ws[k - 1] ?? '')[0]?.t;
      const next = normalizeWords(ws[k + 1] ?? '')[0]?.t;
      if (t && !FILLERS.has(t) && letters(w).length >= 3 && t !== prev && t !== next) return k;
    }
  }
  return mid;
}

/** Napadi na jedan cue. `vocab` su riječi fixturea (bez interpunkcije) po normaliziranom obliku. */
function attacks(id: string, cs: readonly TimedCue[], i: number, vocab: Map<string, string>, en: boolean): Attack[] {
  const c = cs[i];
  if (!c?.speaker) return [];
  const sp = c.speaker;
  const ws = [...c.tokens];
  const at = (quote: string, kind: string, reason?: RejectReason, over: Partial<QuoteClaim> = {}): Attack => ({
    kind,
    claim: { cueFrom: i, cueTo: i, speaker: sp, quote, ...over },
    ...(reason && { reason }),
  });
  const out: Attack[] = [];
  const m = midContentIndex(ws);

  // Zamjena sadržajne riječi najduljom riječi drugog cuea.
  const longest = (xs: readonly string[]) =>
    xs.reduce((a, b) => (letters(b).length > letters(a).length ? b : a), '');
  const victim = longest(ws);
  const repl = cs
    .map((o) => letters(longest(o.tokens)))
    .find((w, k) => k !== i && w.length >= 5 && w.toLowerCase() !== letters(victim).toLowerCase());
  if (repl) out.push(at(ws.map((w) => (w === victim ? repl : w)).join(' '), 'zamjena riječi'));

  // Broj: znamenke +1, ili broj riječima.
  const numIdx = ws.findIndex((w) => /\d/.test(w));
  if (numIdx >= 0) {
    const bumped = ws.map((w, k) => (k === numIdx ? w.replace(/\d+/, (d) => String(Number(d) + 1)) : w));
    out.push(at(bumped.join(' '), 'zamjena broja'));
  }
  const nwIdx = ws.findIndex((w) => NUMBER_WORDS[letters(w).toLowerCase()] !== undefined);
  if (nwIdx >= 0) {
    const r = NUMBER_WORDS[letters(ws[nwIdx] ?? '').toLowerCase()] ?? '';
    out.push(at(ws.map((w, k) => (k === nwIdx ? r : w)).join(' '), 'zamjena broja riječima'));
  }

  // Jedan znak u nastavku (riječ iz rječnika fixturea), dijakritika.
  for (const [k, w] of ws.entries()) {
    const n = normalizeWords(w);
    const t = n[0]?.t;
    if (n.length !== 1 || !t) continue;
    const alt = [...vocab.keys()].find((v) => oneCharTailEdit(t, v));
    if (alt) {
      out.push(at(ws.map((x, j) => (j === k ? (vocab.get(alt) ?? alt) : x)).join(' '), 'nastavak riječi', 'word_form'));
      break;
    }
  }
  const diaIdx = ws.findIndex((w) => /[čćšžđ]/i.test(w));
  if (diaIdx >= 0) {
    const ascii = ws.map((w, k) => (k === diaIdx ? w.normalize('NFD').replace(/\p{M}/gu, '').replace(/đ/g, 'd') : w));
    out.push(at(ascii.join(' '), 'dijakritika skinuta', 'word_form'));
  }
  const addIdx = ws.findIndex((w) => /^[a-z]*[csz][a-z]*$/.test(letters(w)) && letters(w).length >= 3);
  if (addIdx >= 0 && !en) {
    const hacek = ws.map((w, k) =>
      k === addIdx ? w.replace(/[csz]/, (ch) => ({ c: 'č', s: 'š', z: 'ž' })[ch] ?? ch) : w,
    );
    out.push(at(hacek.join(' '), 'dijakritika dodana', 'word_form'));
  }

  // Umetanje i brisanje.
  const neg1 = en ? 'not' : 'ne';
  const neg2 = en ? 'never' : 'nije';
  out.push(at([...ws.slice(0, m), neg1, ...ws.slice(m)].join(' '), `umetnut „${neg1}”`));
  out.push(at([...ws.slice(0, m), neg2, ...ws.slice(m)].join(' '), `umetnut „${neg2}”`));
  out.push(at([...ws.slice(0, m), ...ws.slice(m + 1)].join(' '), 'izbačena riječ'));
  const negIdx = ws.findIndex((w, k) => k > 0 && NEGATIONS.has(normalizeWords(w)[0]?.t ?? ''));
  if (negIdx > 0) out.push(at([...ws.slice(0, negIdx), ...ws.slice(negIdx + 1)].join(' '), 'izbačena niječnica'));
  if (numIdx > 0) out.push(at([...ws.slice(0, numIdx), ...ws.slice(numIdx + 1)].join(' '), 'izbačen broj'));

  // Red riječi: dvije susjedne riječi zamijenjene.
  const sw = [...ws];
  const a = sw[m];
  const b = sw[m + 1];
  if (a && b && letters(a).toLowerCase() !== letters(b).toLowerCase()) {
    sw[m] = b;
    sw[m + 1] = a;
    out.push(at(sw.join(' '), 'zamijenjen red riječi'));
  }

  // Izmišljena rečenica iste teme, uz ovaj cue.
  for (const f of FABRICATED[id] ?? []) out.push(at(f, 'izmišljena rečenica', 'not_found'));

  // Doslovan citat iz drugog dijela epizode: model navodi daleki cue.
  const far = cs.findIndex(
    (o, k) => k !== i && Math.abs(o.startMs - c.startMs) > 10 * DEFAULT_WINDOW_MS && o.endMs - o.startMs < 120_000,
  );
  if (far >= 0) out.push(at(c.text, 'drugi dio epizode', 'outside_window', { cueFrom: far, cueTo: far }));

  // Drugi govornik.
  const otherSp = cs.find((o) => o.speaker && o.speaker !== sp)?.speaker;
  if (otherSp) out.push(at(c.text, 'krivi govornik', 'speaker_mismatch', { speaker: otherSp }));

  // Spoj dva neuzastopna komada (cue i i cue i+2), bez znaka i s „…”.
  const z = cs[i + 2];
  if (z && z.endMs - c.startMs < 120_000) {
    const left = ws.slice(0, Math.ceil(ws.length / 2)).join(' ');
    const right = z.tokens.slice(Math.floor(z.tokens.length / 2)).join(' ');
    const sp2 = { cueTo: i + 2 };
    out.push(at(`${left} ${right}`, 'spoj bez znaka', undefined, sp2));
    out.push(at(`${left} … ${right}`, 'spoj s „…”', undefined, sp2));
  }
  return out;
}

function vocabOf(cs: readonly TimedCue[]): Map<string, string> {
  const v = new Map<string, string>();
  for (const c of cs) {
    for (const w of c.tokens) {
      const n = normalizeWords(w);
      if (n.length === 1 && n[0]) v.set(n[0].t, letters(w));
    }
  }
  return v;
}

const passed = (r: VerifyResult) => r.check !== 'failed';

describe('napad na provjeru citata nad stvarnim fixtureima', () => {
  for (const f of MEASURE_FIXTURES) {
    const okCheck = f.id === 'P9sLks-f2mQ' ? 'srt_only' : 'exact';

    it(`${f.id}: kontrola — doslovni citati odabranih cueova prolaze (${okCheck})`, () => {
      const cs = get(f.id);
      const ids = pick(cs);
      expect(ids.length).toBeGreaterThanOrEqual(8);
      for (const i of ids) {
        const c = cs[i];
        const r = verifyQuote(cs, { cueFrom: i, cueTo: i, speaker: c?.speaker ?? '', quote: c?.text ?? '' });
        expect(r, `c${String(i)}: ${c?.text ?? ''}`).toMatchObject({ check: okCheck });
      }
    });

    it(`${f.id}: nijedan pokvaren citat ne prolazi`, () => {
      const cs = get(f.id);
      const vocab = vocabOf(cs);
      const kinds = new Map<string, number>();
      for (const i of pick(cs)) {
        for (const a of attacks(f.id, cs, i, vocab, f.lang === 'en')) {
          const r = verifyQuote(cs, a.claim);
          const label = `${a.kind} c${String(i)}: ${a.claim.quote}`;
          expect(passed(r), label).toBe(false);
          if (a.reason) expect(r, label).toMatchObject({ check: 'failed', reason: a.reason });
          kinds.set(a.kind, (kinds.get(a.kind) ?? 0) + 1);
        }
      }
      // Svaka vrsta napada stvarno se dogodila (test nije prazan).
      for (const k of [
        'zamjena riječi',
        'nastavak riječi',
        'umetnut „ne”',
        'izbačena riječ',
        'izmišljena rečenica',
        'drugi dio epizode',
        'krivi govornik',
        'spoj bez znaka',
        'spoj s „…”',
      ]) {
        const key = f.lang === 'en' ? k.replace('„ne”', '„not”') : k;
        expect(kinds.get(key) ?? 0, `${f.id}: ${key}`).toBeGreaterThan(0);
      }
      if (f.lang !== 'en') expect(kinds.get('dijakritika skinuta') ?? 0).toBeGreaterThan(0);
    });

    it(`${f.id}: citat koji počinje odmah iza niječnice istog govornika je negation_cut`, () => {
      const cs = get(f.id);
      let n = 0;
      cs.forEach((c, i) => {
        if (!c.speaker) return;
        const ws = c.tokens;
        ws.forEach((w, k) => {
          const t = normalizeWords(w);
          if (t.length !== 1 || !NEGATIONS.has(t[0]?.t ?? '') || /[^\p{L}\p{N}'’]$/u.test(w)) return;
          const rest = ws.slice(k + 1).join(' ');
          if (content(rest) < 4) return;
          const r = verifyQuote(cs, { cueFrom: i, cueTo: i, speaker: c.speaker ?? '', quote: rest });
          expect(r, `c${String(i)}: [${w}] ${rest}`).toMatchObject({ check: 'failed', reason: 'negation_cut' });
          // Isti citat s niječnicom prolazi, osim kad je i ispred nje niječnica
          // („nisam nikad bio”, „nikad nije vidio”): i tada je rez uz niječnicu.
          const prev = ws[k - 1];
          const prevNeg = prev !== undefined && NEGATIONS.has(normalizeWords(prev).at(-1)?.t ?? '') && !/[^\p{L}\p{N}'’]$/u.test(prev);
          const whole = verifyQuote(cs, { cueFrom: i, cueTo: i, speaker: c.speaker ?? '', quote: `${w} ${rest}` });
          expect(whole, `c${String(i)}: ${w} ${rest}`).toMatchObject(
            prevNeg ? { check: 'failed', reason: 'negation_cut' } : { check: f.id === 'P9sLks-f2mQ' ? 'srt_only' : 'exact' },
          );
          n++;
        });
      });
      expect(n).toBeGreaterThan(0);
    });
  }

  it('x3w2BVZJ9vQ: hrvatski prijevod nije izvornik, ni obrnuto', async () => {
    const en = get('x3w2BVZJ9vQ');
    const hr = get('x3w2BVZJ9vQ:hr');
    const nearest = (cs: readonly TimedCue[], ms: number) =>
      cs.reduce((best, c, k) => (Math.abs(c.startMs - ms) < Math.abs((cs[best]?.startMs ?? 0) - ms) ? k : best), 0);
    let n = 0;
    for (const i of pick(hr)) {
      const c = hr[i];
      if (!c?.speaker) continue;
      const j = nearest(en, c.startMs);
      // Prijevod ponuđen kao citat engleskog izvornika.
      const r1 = verifyQuote(en, { cueFrom: j, cueTo: j, speaker: en[j]?.speaker ?? '', quote: c.text });
      expect(r1, c.text).toMatchObject({ check: 'failed', reason: 'not_found' });
      // Izvornik provjeren nad prijevodom (kao da je prijevod titl snimke).
      const e = en[j];
      if (e && content(e.text) >= 4) {
        const r2 = verifyQuote(hr, { cueFrom: i, cueTo: i, speaker: c.speaker, quote: e.text });
        expect(r2, e.text).toMatchObject({ check: 'failed', reason: 'not_found' });
      }
      n++;
    }
    expect(n).toBeGreaterThanOrEqual(8);
    // A do provjere ni ne dođe: `--lang hr` nad epizodom s engleskim izvornim parom je greška.
    const cdn = createCdnClient({ fetch: createFakeCdn().fetch });
    const bundle = await cdn.bundle('x3w2BVZJ9vQ');
    expect(() => decideQuoteLang({ bundle, explicit: 'hr' })).toThrow(QuoteLangError);
    expect(decideQuoteLang({ bundle })).toMatchObject({ lang: 'en', source: 'pair' });
  });
});
