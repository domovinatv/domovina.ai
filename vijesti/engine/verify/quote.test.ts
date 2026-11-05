import { describe, expect, it } from 'vitest';
import type { TimedCue } from '../cdn/words.js';
import { cueTokens } from '../cdn/srt.js';
import { normalizeText, normalizeTokens } from './normalize.js';
import { FILLERS, oneCharTailEdit, verifyQuote, type QuoteClaim } from './quote.js';

/** Cue s jednoliko raspoređenim vremenima riječi (ili bez njih). */
function cue(startMs: number, endMs: number, speaker: string | null, text: string, timed = true): TimedCue {
  const tokens = cueTokens(text);
  const step = (endMs - startMs) / Math.max(tokens.length, 1);
  const words = timed
    ? tokens.map((t, i) => ({
        text: t,
        startMs: Math.round(startMs + i * step),
        endMs: Math.round(startMs + (i + 1) * step),
      }))
    : null;
  return {
    index: 0,
    startMs,
    endMs,
    speaker,
    text,
    tokens,
    words,
    wordsStatus: timed ? 'ok' : 'missing',
    anchored: null,
  };
}

const claim = (over: Partial<QuoteClaim>): QuoteClaim => ({
  cueFrom: 0,
  cueTo: 0,
  speaker: 'SPEAKER_00',
  quote: '',
  ...over,
});

describe('normalizacija', () => {
  it('mala slova, dijakritika, đ, interpunkcija, apostrofi, razmaci', () => {
    expect(normalizeTokens('Đuro  Đaković, ŠTO?! Čćžš')).toEqual(['duro', 'dakovic', 'sto', 'cczs']);
    expect(normalizeTokens("Don't — it’s")).toEqual(['dont', 'its']);
    expect(normalizeTokens('e-pošta, 2.000 kn')).toEqual(['e', 'posta', '2000', 'kn']);
    // Odluka 213: razdjelnik tisućica se briše, decimale i vrijeme ostaju.
    expect(normalizeTokens('300,000 i 1.000.000')).toEqual(['300000', 'i', '1000000']);
    expect(normalizeTokens('3,5 posto u 12.30')).toEqual(['3', '5', 'posto', 'u', '12', '30']);
    expect(normalizeTokens('2026.')).toEqual(['2026']);
    expect(normalizeText('„Vjera blijedi, nestat će...”')).toBe('vjera blijedi nestat ce');
    expect(normalizeTokens(' … ')).toEqual([]);
  });

  it('popis poštapalica nema riječi koje nose značenje', () => {
    for (const w of ['ne', 'ovaj', 'ono', 'dakle', 'znaci', 'mislim', 'kao', 'mhm', 'aha', 'em', 'er', 'e', 'a', 'i', 'no']) {
      expect(FILLERS.has(w)).toBe(false);
    }
  });
});

describe('oneCharTailEdit', () => {
  it('nastavak riječi ≥ 6 znakova prolazi', () => {
    expect(oneCharTailEdit('napravili', 'napravila')).toBe(true);
    expect(oneCharTailEdit('milijun', 'milijuna')).toBe(true);
    expect(oneCharTailEdit('napraviti', 'napravit')).toBe(true);
  });
  it('početak, sredina, kratke riječi, znamenke i dvije razlike ne prolaze', () => {
    expect(oneCharTailEdit('legalno', 'ilegalno')).toBe(false);
    expect(oneCharTailEdit('prodati', 'predati')).toBe(false);
    expect(oneCharTailEdit('kupio', 'kupia')).toBe(false);
    expect(oneCharTailEdit('1000000', '1000001')).toBe(false);
    expect(oneCharTailEdit('napravili', 'napravile0')).toBe(false);
    expect(oneCharTailEdit('napravili', 'napravimo')).toBe(false);
    expect(oneCharTailEdit('isto', 'isto')).toBe(false);
  });
});

describe('verifyQuote', () => {
  const two = [
    cue(10_000, 14_000, 'SPEAKER_00', 'Ovo je prvi dio rečenice,'),
    cue(14_000, 18_000, 'SPEAKER_00', 'a ovo je drugi dio.'),
  ];

  it('exact: vrijeme iz riječi (riječ-indeks unutar cuea), ne granice cuea', () => {
    const r = verifyQuote(two, claim({ quote: 'je prvi dio rečenice' }));
    expect(r).toMatchObject({ check: 'exact', match: 'exact', span: { cueFrom: 0, cueTo: 0 } });
    if (r.check === 'failed') throw new Error('očekivan uspjeh');
    expect(r.span.startMs).toBe(10_800);
    expect(r.span.endMs).toBe(14_000);
  });

  it('exact preko dva cuea, velika slova i interpunkcija ne smetaju', () => {
    const r = verifyQuote(two, claim({ cueTo: 1, quote: 'DIO REČENICE — a ovo je drugi' }));
    expect(r).toMatchObject({ check: 'exact', span: { cueFrom: 0, cueTo: 1, startMs: 12_400, endMs: 17_200 } });
  });

  it('dijakritika mora biti ista (odluka 210): kriza/križa, nas/naš su druge riječi', () => {
    expect(verifyQuote(two, claim({ cueTo: 1, quote: 'dio recenice a ovo je drugi' }))).toMatchObject({
      check: 'failed',
      reason: 'word_form',
      detail: 'rečenice→recenice',
    });
    const cues = [cue(0, 5000, 'SPEAKER_00', 'to je znak križa za naš narod')];
    expect(verifyQuote(cues, claim({ quote: 'to je znak kriza za naš narod' }))).toMatchObject({
      reason: 'word_form',
      detail: 'križa→kriza',
    });
    expect(verifyQuote(cues, claim({ quote: 'to je znak križa za nas narod' }))).toMatchObject({
      reason: 'word_form',
    });
  });

  it('fuzzy: poštapalica iz titla smije izostati', () => {
    const cues = [cue(0, 5000, 'SPEAKER_01', 'ja sam hm rekao da je to istina')];
    const r = verifyQuote(cues, claim({ speaker: 'SPEAKER_01', quote: 'Ja sam rekao da je to istina.' }));
    expect(r).toMatchObject({ check: 'fuzzy', match: 'fuzzy', fillersSkipped: 1 });
  });

  it('fuzzy ne dopušta izostavljanje riječi sa značenjem, umetanje ni zamjenu', () => {
    const cues = [cue(0, 5000, 'SPEAKER_01', 'ja nisam ovaj rekao da je to ne istina')];
    const v = (quote: string) => verifyQuote(cues, claim({ speaker: 'SPEAKER_01', quote }));
    expect(v('ja nisam rekao da je to ne istina')).toMatchObject({ check: 'failed', reason: 'not_found' });
    expect(v('ja nisam ovaj rekao da je to istina')).toMatchObject({ check: 'failed', reason: 'not_found' });
    expect(v('ja nisam ovaj rekao da je to sigurno ne istina')).toMatchObject({ reason: 'not_found' });
    expect(v('ja sam ovaj rekao da je to ne istina')).toMatchObject({ reason: 'not_found' });
  });

  it('razlika u nastavku riječi ne prolazi (odluka 210), ni na 10 riječi; razlog word_form', () => {
    const text = 'mi smo to napravili jer smo tako odlučili prije dvije godine';
    const cues = [cue(0, 8000, 'SPEAKER_00', text)];
    const ten = verifyQuote(cues, claim({ quote: 'mi smo to napravila jer smo tako odlučili prije dvije' }));
    expect(ten).toMatchObject({ check: 'failed', reason: 'word_form', detail: 'napravili→napravila' });
    const nine = verifyQuote(cues, claim({ quote: 'smo to napravila jer smo tako odlučili prije dvije' }));
    expect(nine).toMatchObject({ check: 'failed', reason: 'word_form' });
    // Dvije izmjene u 10 riječi su iznad dijagnostičkog budžeta: not_found.
    const two = verifyQuote(cues, claim({ quote: 'mi smo to napravila jer smo tako odlučila prije dvije' }));
    expect(two).toMatchObject({ check: 'failed', reason: 'not_found' });
  });

  it('nastavak koji mijenja lice, vrijeme, broj ili riječ (parovi iz fixturea) ne prolazi', () => {
    const pairs: [string, string][] = [
      ['mislim', 'mislis'],
      ['trebamo', 'trebalo'],
      ['svijest', 'svijet'],
      ['postoje', 'postaje'],
      ['probao', 'prosao'],
      ['thousand', 'thousands'],
      ['influence', 'influencer'],
      ['dvadeset', 'dvadesete'],
    ];
    for (const [said, quoted] of pairs) {
      expect(oneCharTailEdit(said, quoted)).toBe(true);
      const cues = [cue(0, 8000, 'SPEAKER_00', `jedan dva tri četiri ${said} pet šest sedam osam devet`)];
      const r = verifyQuote(cues, claim({ quote: `jedan dva tri četiri ${quoted} pet šest sedam osam devet` }));
      expect(r, `${said}/${quoted}`).toMatchObject({ check: 'failed', reason: 'word_form' });
    }
  });

  it('negation_cut: citat ne smije početi odmah iza niječnice istog govornika (odluka 211)', () => {
    const cues = [
      cue(0, 4000, 'SPEAKER_00', 'Ja ne mislim da je crkva prazna, nego'),
      cue(4000, 8000, 'SPEAKER_00', 'da nije istina da su mladi otišli iz nje'),
      cue(8000, 12_000, 'SPEAKER_01', 'Ne. Mislim da je to bilo prije'),
      cue(12_000, 16_000, 'SPEAKER_00', 'i nikad'),
      cue(16_000, 20_000, 'SPEAKER_00', 'hm nisu otišli svi mladi ljudi'),
      cue(20_000, 24_000, 'SPEAKER_00', 'I do not hm believe the church is empty'),
    ];
    const v = (cueFrom: number, quote: string, speaker = 'SPEAKER_00') =>
      verifyQuote(cues, claim({ cueFrom, cueTo: cueFrom, speaker, quote }));
    expect(v(0, 'mislim da je crkva prazna')).toMatchObject({ check: 'failed', reason: 'negation_cut', detail: 'ne' });
    expect(v(0, 'ja ne mislim da je crkva prazna')).toMatchObject({ check: 'exact' });
    expect(v(1, 'istina da su mladi otišli')).toMatchObject({ reason: 'negation_cut', detail: 'nije' });
    // Interpunkcija odvaja: „Ne. Mislim …” smije se citirati od „Mislim”.
    expect(v(2, 'Mislim da je to bilo prije', 'SPEAKER_01')).toMatchObject({ check: 'exact' });
    // Preko granice cuea i preko poštapalice.
    expect(v(4, 'nisu otišli svi mladi ljudi')).toMatchObject({ reason: 'negation_cut', detail: 'nikad' });
    expect(v(4, 'otišli svi mladi ljudi')).toMatchObject({ reason: 'negation_cut', detail: 'nisu' });
    expect(v(5, 'believe the church is empty')).toMatchObject({ reason: 'negation_cut', detail: 'not' });
    // Iza kraja: „… pa možda i ne” → „… pa možda i” (MGLq9v3AtvE c71: „… pa možda i nije”).
    const tail = [cue(0, 4000, 'SPEAKER_00', 'ja sam to čula pa možda i ne.'), cue(4000, 8000, 'SPEAKER_00', 'Ne, nije.')];
    expect(verifyQuote(tail, claim({ quote: 'ja sam to čula pa možda i' }))).toMatchObject({
      reason: 'negation_cut',
      detail: 'ne',
    });
    expect(verifyQuote(tail, claim({ quote: 'ja sam to čula pa možda i ne' }))).toMatchObject({ check: 'exact' });
    // Zarez odvaja: „… vrijedilo je, ne?” smije se citirati bez „ne”.
    const comma = [cue(0, 4000, 'SPEAKER_00', 'to je stvarno vrijedilo truda, ne?')];
    expect(verifyQuote(comma, claim({ quote: 'to je stvarno vrijedilo truda' }))).toMatchObject({ check: 'exact' });
  });

  it('srt_only: bez vremena riječi u nekom cueu spana → granice cueova', () => {
    const cues = [two[0] ?? cue(0, 1, null, ''), cue(14_000, 18_000, 'SPEAKER_00', 'a ovo je drugi dio.', false)];
    const r = verifyQuote(cues, claim({ cueTo: 1, quote: 'rečenice a ovo je' }));
    expect(r).toMatchObject({
      check: 'srt_only',
      match: 'exact',
      span: { cueFrom: 0, cueTo: 1, startMs: 10_000, endMs: 18_000 },
    });
    // Isti titl, citat samo u cueu s vremenima: exact.
    expect(verifyQuote(cues, claim({ quote: 'ovo je prvi dio' }))).toMatchObject({ check: 'exact' });
  });

  it('srt_only: cue od 0 ms dobiva kraj = početak + 1', () => {
    const cues = [cue(5000, 5000, 'SPEAKER_00', 'ovo su četiri riječi', false)];
    expect(verifyQuote(cues, claim({ quote: 'ovo su četiri riječi' }))).toMatchObject({
      check: 'srt_only',
      span: { startMs: 5000, endMs: 5001 },
    });
  });

  it('bad_cue_ref: nepostojeći ili obrnut raspon', () => {
    expect(verifyQuote(two, claim({ cueFrom: 2, cueTo: 2, quote: 'ovo je prvi dio' }))).toMatchObject({
      check: 'failed',
      reason: 'bad_cue_ref',
      range: null,
    });
    expect(verifyQuote(two, claim({ cueFrom: 1, cueTo: 0, quote: 'ovo je prvi dio' }))).toMatchObject({
      reason: 'bad_cue_ref',
    });
  });

  it('too_short: manje od 4 riječi bez poštapalica', () => {
    expect(verifyQuote(two, claim({ quote: 'hm prvi dio rečenice' }))).toMatchObject({
      check: 'failed',
      reason: 'too_short',
      range: { startMs: 10_000, endMs: 14_000 },
    });
  });

  it('speaker_mismatch: span prelazi u cue drugog govornika', () => {
    const cues = [two[0] ?? cue(0, 1, null, ''), cue(14_000, 18_000, 'SPEAKER_01', 'a ovo je drugi dio.')];
    expect(verifyQuote(cues, claim({ cueTo: 1, quote: 'dio rečenice a ovo je' }))).toMatchObject({
      check: 'failed',
      reason: 'speaker_mismatch',
    });
  });

  it('prozor: susjedni cue unutar 5 s se pretražuje, dalji je outside_window', () => {
    const cues = [
      cue(0, 4000, 'SPEAKER_00', 'prva rečenica koju nitko ne citira'),
      cue(8000, 12_000, 'SPEAKER_00', 'druga rečenica je ovdje negdje'),
      cue(40_000, 44_000, 'SPEAKER_00', 'treća rečenica je daleko od ostalih'),
    ];
    expect(verifyQuote(cues, claim({ quote: 'druga rečenica je ovdje' }))).toMatchObject({
      check: 'exact',
      span: { cueFrom: 1 },
    });
    expect(verifyQuote(cues, claim({ quote: 'treća rečenica je daleko' }))).toMatchObject({
      check: 'failed',
      reason: 'outside_window',
    });
    expect(verifyQuote(cues, claim({ quote: 'četvrta rečenica ne postoji nigdje' }))).toMatchObject({
      reason: 'not_found',
    });
  });

  it('isti niz dvaput u prozoru: uzima se prvi', () => {
    const cues = [
      cue(0, 4000, 'SPEAKER_00', 'to je bila naša odluka'),
      cue(4000, 8000, 'SPEAKER_00', 'i to je bila naša odluka'),
    ];
    expect(verifyQuote(cues, claim({ cueFrom: 1, cueTo: 1, quote: 'to je bila naša odluka' }))).toMatchObject({
      span: { cueFrom: 0, startMs: 0 },
    });
  });

  it('span_too_long: raspon cueova dulji od 120 s', () => {
    const cues = [cue(0, 4000, 'SPEAKER_00', 'prva rečenica je ovdje'), cue(200_000, 204_000, 'SPEAKER_00', 'kraj')];
    expect(verifyQuote(cues, claim({ cueTo: 1, quote: 'prva rečenica je ovdje' }))).toMatchObject({
      check: 'failed',
      reason: 'span_too_long',
    });
  });

  it('span_too_long i za NAĐENI citat: dugi susjedni cueovi u prozoru (odluka 214)', () => {
    const cues = [
      cue(0, 60_000, 'SPEAKER_00', 'prvi dugi cue ima puno riječi'),
      cue(60_000, 61_000, 'SPEAKER_00', 'kratki srednji cue'),
      cue(61_000, 121_000, 'SPEAKER_00', 'treći dugi cue opet ima riječi'),
    ];
    const whole = 'prvi dugi cue ima puno riječi kratki srednji cue treći dugi cue opet ima riječi';
    expect(verifyQuote(cues, claim({ cueFrom: 1, cueTo: 1, quote: whole }))).toMatchObject({
      check: 'failed',
      reason: 'span_too_long',
      detail: 'nađeni citat',
    });
    // Unutar 120 s isti prozor prolazi.
    expect(verifyQuote(cues, claim({ cueFrom: 1, cueTo: 1, quote: 'puno riječi kratki srednji cue treći' }))).toMatchObject({
      check: 'exact',
      span: { cueFrom: 0, cueTo: 2 },
    });
  });

  it('prazan citat i citat od same interpunkcije su too_short', () => {
    for (const quote of ['', '   ', '… — „”', 'hm, eh, mm']) {
      expect(verifyQuote(two, claim({ quote }))).toMatchObject({ check: 'failed', reason: 'too_short' });
    }
  });

  it('citat = cijeli prozor (oba cuea u potpunosti) prolazi s rasponom oba cuea', () => {
    expect(verifyQuote(two, claim({ quote: 'Ovo je prvi dio rečenice, a ovo je drugi dio.' }))).toMatchObject({
      check: 'exact',
      span: { cueFrom: 0, cueTo: 1, startMs: 10_000, endMs: 18_000 },
    });
  });

  it('tri točke: smiju samo ako ih titl ima u tom rasponu', () => {
    const cues = [
      cue(0, 4000, 'SPEAKER_00', 'Vjera blijedi, nestat će...'),
      cue(4000, 8000, 'SPEAKER_00', 'ja to ne vjerujem uopće danas'),
    ];
    expect(verifyQuote(cues, claim({ quote: 'Vjera blijedi, nestat će...' }))).toMatchObject({ check: 'exact' });
    expect(verifyQuote(cues, claim({ cueFrom: 1, cueTo: 1, quote: 'ja to ne vjerujem…' }))).toMatchObject({
      check: 'failed',
      reason: 'ellipsis',
    });
  });
});
