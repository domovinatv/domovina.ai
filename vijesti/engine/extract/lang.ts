// Jezik citata = jezik snimke (odluka 200). Engine nikad ne citira prijevod:
// izvor citata je titl koji je nastao iz zvuka, a jezik se provjerava i na
// samom tekstu prije nego išta ode modelu.
import type { EpisodeBundle } from '../cdn/schemas.js';
import { normalizeTokens } from '../verify/normalize.js';

export type LangSource = 'explicit' | 'pair' | 'channel' | 'default';

export interface LangDecision {
  lang: string;
  source: LangSource;
}

export class QuoteLangError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'QuoteLangError';
  }
}

const LANG_RE = /^[a-z]{2}$/;
const PAIR_RE = /^diarized\.([a-z]{2})\.srt$/;

function listed(bundle: EpisodeBundle, name: string): boolean {
  const inline = bundle.inline[name];
  return bundle.files.includes(name) || (inline !== undefined && inline !== null);
}

/**
 * Jezici `xx ≠ hr` za koje episode.json navodi PAR `diarized.<xx>.srt` +
 * `words.<xx>.json`. Vrijeme po riječi postoji samo za titl koji je nastao iz
 * zvuka; prijevod (`diarized.en.srt` hrvatske epizode u fazi 3 plana
 * 2026-10-29) ga nema. Zato je par znak izvornika, a goli titl nije.
 */
export function originalPairs(bundle: EpisodeBundle | null): string[] {
  if (!bundle) return [];
  const names = [...bundle.files, ...Object.keys(bundle.inline)];
  const langs = new Set<string>();
  for (const n of names) {
    const m = PAIR_RE.exec(n);
    const xx = m?.[1];
    if (xx && xx !== 'hr' && listed(bundle, n) && listed(bundle, `words.${xx}.json`)) langs.add(xx);
  }
  return [...langs].sort();
}

/** `diarized.<xx>.srt` s popisa, bez obzira na words (i prijevodi). */
function listedSrtLangs(bundle: EpisodeBundle | null): string[] {
  if (!bundle) return [];
  const out = new Set<string>();
  for (const n of [...bundle.files, ...Object.keys(bundle.inline)]) {
    const xx = PAIR_RE.exec(n)?.[1];
    if (xx && listed(bundle, n)) out.add(xx);
  }
  return [...out].sort();
}

/**
 * Redoslijed: `--lang` → par izvornika iz episode.json → jezik kanala → `hr`.
 * `--lang` ne smije proturječiti paru: par kaže da je izvornik drugog jezika,
 * pa bi `--lang hr` citirao prijevod (`x3w2BVZJ9vQ`). Kad jezik nije izričit,
 * a uz goli `diarized.srt` bez `words.json` postoji titl na drugom jeziku, ne
 * zna se koji je izvornik: greška, ne nagađanje.
 */
export function decideQuoteLang(input: {
  bundle: EpisodeBundle | null;
  explicit?: string | undefined;
  channelLang?: string | null | undefined;
}): LangDecision {
  const { bundle } = input;
  const pairs = originalPairs(bundle);
  if (pairs.length > 1) {
    throw new QuoteLangError(
      `episode.json navodi više izvornih parova (${pairs.join(', ')}); jezik snimke nije jednoznačan`,
    );
  }
  const pair = pairs[0];
  if (input.explicit !== undefined) {
    const lang = input.explicit.toLowerCase();
    if (!LANG_RE.test(lang)) throw new QuoteLangError(`neispravan --lang: ${input.explicit}`);
    if (pair && pair !== lang) {
      throw new QuoteLangError(
        `--lang ${lang}, a episode.json navodi izvorni par diarized.${pair}.srt + words.${pair}.json; ` +
          `citat bi bio iz prijevoda`,
      );
    }
    return { lang, source: 'explicit' };
  }
  if (pair) return { lang: pair, source: 'pair' };
  const channel = input.channelLang?.toLowerCase();
  const decision: LangDecision =
    channel && LANG_RE.test(channel)
      ? { lang: channel, source: 'channel' }
      : { lang: 'hr', source: 'default' };
  if (bundle && !listed(bundle, 'words.json')) {
    const others = listedSrtLangs(bundle).filter((x) => x !== decision.lang);
    const ownFile = listed(bundle, `diarized.${decision.lang}.srt`);
    if (others.length > 0 && !ownFile) {
      throw new QuoteLangError(
        `uz diarized.srt bez words.json postoji diarized.${others.join('/')}.srt; ` +
          `ne zna se koji je izvornik, navedi --lang`,
      );
    }
  }
  return decision;
}

// Česte funkcijske riječi (normalizirane: mala slova, bez dijakritike). Riječi
// koje postoje u oba jezika (i, a, to, u, on, no, do, me) su izostavljene.
const HR_WORDS = new Set(
  (
    'je da se su sam smo ste si nije nisu koji koja koje sto kako ali ili za od iz na ne bi ' +
    'biti jer vec samo tako ovo taj mi vi oni ja ti kad kada gdje jos sve li pa bio bila bilo ' +
    'ima moze treba zato nego jako onda sada sad'
  ).split(' '),
);
const EN_WORDS = new Set(
  (
    'the and of is that it you we they this was are have has be not with but for what there ' +
    'about if can just like know so he she his her would will from our your my all people ' +
    'think because very which when been were'
  ).split(' '),
);

export interface LangCounts {
  hr: number;
  en: number;
  tokens: number;
}

export function countLangWords(text: string): LangCounts {
  const counts: LangCounts = { hr: 0, en: 0, tokens: 0 };
  for (const t of normalizeTokens(text)) {
    counts.tokens++;
    if (HR_WORDS.has(t)) counts.hr++;
    else if (EN_WORDS.has(t)) counts.en++;
  }
  return counts;
}

/** Najmanje pogodaka (hr + en) da bi se jezik uopće procjenjivao. */
export const LANG_MIN_HITS = 30;
/** Udio pogodaka traženog jezika koji tekst mora imati. */
export const LANG_MIN_SHARE = 0.8;

/**
 * Je li tekst titla na jeziku `lang`. Heuristika zna samo `hr` i `en`; za
 * druge jezike baca (zatvoreno, dok ne dobije popis riječi).
 */
export function assertTextLang(text: string, lang: string): LangCounts {
  if (lang !== 'hr' && lang !== 'en') {
    throw new QuoteLangError(`provjera jezika ne zna jezik „${lang}”; epizoda se ne obrađuje`);
  }
  const c = countLangWords(text);
  const hits = c.hr + c.en;
  if (hits < LANG_MIN_HITS) {
    throw new QuoteLangError(
      `premalo teksta za provjeru jezika (${String(hits)} pogodaka < ${String(LANG_MIN_HITS)})`,
    );
  }
  const share = c[lang] / hits;
  if (share < LANG_MIN_SHARE) {
    const other = lang === 'hr' ? 'en' : 'hr';
    throw new QuoteLangError(
      `titl nije na jeziku ${lang} (${lang} ${String(c[lang])}, ${other} ${String(c[other])}); ` +
        `epizoda se ne obrađuje, citat se nikad ne uzima iz prijevoda`,
    );
  }
  return c;
}
