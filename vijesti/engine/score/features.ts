// Deterministička obilježja konkretnosti citata (odluka 309): brojka, broj
// riječima, datum, imenovani entitet, najava ili odluka. Zatvoreni popisi, bez
// modela; LLM daje svoj sud odvojeno, a formula ih spaja.

function fold(s: string): string {
  return s.toLowerCase().replace(/đ/g, 'd').normalize('NFD').replace(/\p{M}/gu, '');
}

function words(text: string): string[] {
  return fold(text)
    .split(/[^\p{L}\p{N}]+/u)
    .filter(Boolean);
}

/**
 * Brojevi riječima. „jedan/jedna/one” namjerno NISU na popisu („jedan od nas”,
 * „one of the”), kao ni „prvi” (redni brojevi su češće retorika).
 */
const NUMBER_WORDS = new Set([
  // hr (bez dijakritike, nakon fold)
  'dva', 'dvije', 'tri', 'cetiri', 'pet', 'sest', 'sedam', 'osam', 'devet', 'deset',
  'jedanaest', 'dvanaest', 'petnaest', 'dvadeset', 'trideset', 'cetrdeset', 'pedeset',
  'sezdeset', 'sedamdeset', 'osamdeset', 'devedeset', 'sto', 'stotinu', 'stotine',
  'tisucu', 'tisuca', 'tisuce', 'milijun', 'milijuna', 'milijardu', 'milijarde', 'milijardi',
  'posto', 'postotak', 'postotaka', 'polovica', 'polovicu', 'trecina', 'trecinu', 'cetvrtina',
  // en
  'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'twelve', 'fifteen',
  'twenty', 'thirty', 'forty', 'fifty', 'hundred', 'hundreds', 'thousand', 'thousands',
  'million', 'millions', 'billion', 'billions', 'percent', 'half', 'third', 'quarter',
]);

/**
 * Mjeseci: hr osnove (svi padeži) i en. „studeni” ne smije uhvatiti „student”,
 * ni „siječanj” glagol „siječe”; engleski „may” je izostavljen (modalni glagol).
 */
const MONTH_RE =
  /^(sijecanj|sijecnj|veljac|ozujak|ozujk|travan|travnj|svibanj|svibnj|lipan|lipnj|srpan|srpnj|kolovoz|rujan|rujn|listopad|studen(i|og|oga|om|ome)?$|prosin|january|february|march|april|june|july|august|september|october|november|december)/;

/** Godina 1900–2099 ili znamenkasti datum (12. 3. / 3/12). */
const YEAR_RE = /^(19|20)\d{2}$/;
const NUMERIC_DATE_RE = /\b\d{1,2}\s*[./]\s*\d{1,2}\s*[./]/;

/** Najava, odluka, mjera: osnove (nakon fold) i kratke engleske riječi u cijelosti. */
const ANNOUNCE_RE =
  /^(najav|odluc|odluk|pokrec|pokren|zakon|uredb|potpis|raspis|ostavk|imenova|izabran|izglasa|uvodim|uvest|zabran|referendum|prosvjed|tuzb|presud|announc|decid|decision|launch|resign|appoint|lawsuit|verdict|ruling)/;
const ANNOUNCE_WORDS = new Set(['ban', 'bans', 'banned', 'law', 'laws', 'bill', 'bills', 'sued', 'elect', 'elected', 'election', 'elections']);

export interface ConcreteFeatures {
  /** Tokeni sa znamenkom. */
  numbers: number;
  numberWords: number;
  dates: number;
  /** Različiti entiteti iz izvlačenja (odluka 208). */
  entities: number;
  announcement: boolean;
}

export function concreteFeatures(quote: string, entities: readonly string[]): ConcreteFeatures {
  const ws = words(quote);
  const numbers = ws.filter((w) => /\d/.test(w) && !YEAR_RE.test(w)).length;
  const years = ws.filter((w) => YEAR_RE.test(w)).length;
  const months = ws.filter((w) => MONTH_RE.test(w)).length;
  const numericDates = NUMERIC_DATE_RE.test(quote) ? 1 : 0;
  const uniq = new Set(entities.map((e) => fold(e).trim()).filter(Boolean));
  return {
    numbers,
    numberWords: ws.filter((w) => NUMBER_WORDS.has(w)).length,
    dates: years + months + numericDates,
    entities: uniq.size,
    announcement: ws.some((w) => ANNOUNCE_RE.test(w) || ANNOUNCE_WORDS.has(w)),
  };
}

/** Udjeli u determinističkoj konkretnosti (zbroj 1). */
export const FEATURE_WEIGHTS = { number: 0.35, date: 0.25, entities: 0.2, announcement: 0.2 } as const;

export function concreteFeatureScore(f: ConcreteFeatures): number {
  const w = FEATURE_WEIGHTS;
  const s =
    (f.numbers + f.numberWords > 0 ? w.number : 0) +
    (f.dates > 0 ? w.date : 0) +
    w.entities * Math.min(f.entities, 2) / 2 +
    (f.announcement ? w.announcement : 0);
  return Math.round(Math.min(1, s) * 1000) / 1000;
}
