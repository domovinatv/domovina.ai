/**
 * Redoslijed bitova pipeline zastavica: bit i = PIPELINE_BITS[i].
 *
 * UGOVOR, ne naš izbor. Isti niz je `PIPELINE_BITS` u
 * `../fetch.domovina.tv/generate_channel_index.js` (iz njega nastaje `p` u
 * `home.json`) i tablica u `VideoPipeline.fromBits`
 * (`packages/podcast_core/lib/models/channel_detail.dart`). Smije se samo
 * nadopunjavati na kraju; promjena redoslijeda tiho mijenja značenje svakog
 * `flags` u D1 i svakog `p` koji stari build čita. `npm run fixtures:refresh`
 * uspoređuje ovaj niz s fetch repoom i pada na razlici.
 */
export const PIPELINE_BITS = [
  "has_transcript",
  "has_diarized",
  "has_summary",
  "has_article",
  "has_magisterium",
  "has_translation_en",
  "has_summary_en",
  "has_article_en",
  "has_magisterium_en",
] as const;

export type PipelineBit = (typeof PIPELINE_BITS)[number];

/** Zastavice kako ih nosi listing (`videos[].pipeline`). */
export type PipelineFlags = Readonly<Record<PipelineBit, boolean>>;

/** Sve zastavice podignute: 511 za 9 bitova. Gornja granica `CHECK` na `episodes.flags`. */
export const ALL_PIPELINE_FLAGS = (1 << PIPELINE_BITS.length) - 1;

/** Zastavice → bitmaska, kao `pipelineBits()` u `generate_channel_index.js`. */
export function flagsFromPipeline(pipeline: PipelineFlags): number {
  let flags = 0;
  PIPELINE_BITS.forEach((bit, i) => {
    if (pipeline[bit]) flags |= 1 << i;
  });
  return flags;
}

/** Bitmaska → zastavice. Obrat od [flagsFromPipeline]; bitovi iznad 8 se ne čitaju. */
export function pipelineFromFlags(flags: number): PipelineFlags {
  const out = {} as Record<PipelineBit, boolean>;
  PIPELINE_BITS.forEach((bit, i) => {
    out[bit] = (flags & (1 << i)) !== 0;
  });
  return out;
}
