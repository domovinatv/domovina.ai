#!/usr/bin/env node
// Osvježava test/fixtures/ iz stvarnih podataka: CDN (`cdn.domovina.ai`) i
// registry iz fetch repoa (samo čitanje). Skraćuje po pravilima iz
// test/fixtures/README.md i piše deterministički (izvorni redoslijed ključeva,
// 2 razmaka, `\n` na kraju), pa dva pokretanja bez promjene izvora daju prazan
// `git diff`. Na kraju sve zapisano provuče kroz parsere iz src/input/.
//
//   npm run fixtures:refresh
//   KATALOG_REGISTRY_PATH=/put/do/podcasts_registry.json npm run fixtures:refresh
//
// Node 24+ (parseri se uvoze kao .ts, odluka 118).
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

// ---- Izbor (popisi i razlozi: test/fixtures/README.md) ---------------------

const CDN = "https://cdn.domovina.ai/";
/**
 * Tier 1 kanali čiji se listing uzima. `slijedi_svoj_poziv_1`/`_2` dijele YouTube
 * channel_id s `na_kavi_sa_svetim_ignacijem` (S2); `podcast_cuspajz` drži osnovni ID
 * varijante `UM2MWlNUp_1`; `subclub` je kanal Tier 2 epizode bez `info.json`.
 * Plan uvoza (S2) traži listing za svaki kanal iz `index.json`, pa ih index ima isto.
 */
const LISTING_SLUGS = [
  "40_dana_za_zivot", "dijalog", "nanovoroeni", "slijedi_svoj_poziv_1", "slijedi_svoj_poziv_2",
  "podcast_cuspajz", "subclub",
];
/** Dodatno u `index.json` (bez listinga). */
const INDEX_EXTRA_SLUGS = [];
/** Epizode koje listing fixture MORA zadržati. */
const PINNED_VIDEOS = { nanovoroeni: ["KLPD-Meu4e8"], podcast_cuspajz: ["UM2MWlNUpqg"] };
const MAX_VIDEOS = 20;
/**
 * `_unlisted` epizode (Tier 2). S2 dodaje: `A-oDNz3nvdQ` (Nova Eva: registry ima
 * `type: channel` + playlistu), `0sxT3NF8yFg` (VTV: tri playliste, dvosmisleno),
 * `UM2MWlNUp_1` (eksperimentalna varijanta Tier 1 epizode, Tier 1 kanal po channel_id).
 */
const UNLISTED_IDS = [
  "kYwKrihe2K0", "7N0gyXAfA4M", "KLPD-Meu4e8", "CUJmOc91C64", "hmM9f_3Mqm4",
  "A-oDNz3nvdQ", "0sxT3NF8yFg", "UM2MWlNUp_1",
];
/** Tier 2 epizode bez `info.json` na R2: uzima se samo `summary.json` (S2). */
const NO_INFO_IDS = ["6dcab9c9837"];
/** Njihov kanal NE smije biti u registryju (S2: „kanal kojeg nema u registryju”). */
const NOT_IN_REGISTRY_IDS = ["CUJmOc91C64", "hmM9f_3Mqm4"];
/** Registry unosi uzeti po slugu (nemaju `channel_id` pa ih channel_id ne nađe). */
const REGISTRY_EXTRA_SLUGS = ["nanovoroeni", "dijalog"];

const INFO_KEYS = [
  "id", "title", "channel", "channel_id", "upload_date", "duration", "extractor",
  "timestamp", "webpage_url", "uploader", "language",
];
const REGISTRY_DROP_KEYS = new Set(["quality_score", "notes", "sources", "discovery", "revision"]);
const TEXT_MAX = 160;
const LIST_MAX = 3;
const TAGS_MAX = 5;
const CONCURRENCY = 4;

// ---- Putanje ---------------------------------------------------------------

const KATALOG = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const OUT = join(KATALOG, "test", "fixtures");
const FETCH_REPO = resolve(KATALOG, "../../fetch.domovina.tv");
const REGISTRY_PATH = process.env.KATALOG_REGISTRY_PATH
  ? resolve(process.env.KATALOG_REGISTRY_PATH)
  : join(FETCH_REPO, "data", "podcasts_registry.json");
const CHANNEL_INDEX_JS = join(FETCH_REPO, "generate_channel_index.js");
const KEY_CACHE_PATH = process.env.KATALOG_KEY_CACHE_PATH
  ? resolve(process.env.KATALOG_KEY_CACHE_PATH)
  : join(FETCH_REPO, ".r2_keys_cache.json");

// ---- Dohvat ----------------------------------------------------------------

async function getJson(path) {
  const url = CDN + path;
  let res = await fetch(url);
  // Pravilo `DataService._get`: CDN cachira i 404, druga adresa ide na origin.
  if (res.status === 404) res = await fetch(`${url}?cb=${Date.now()}`);
  if (!res.ok) throw new Error(`${url}: HTTP ${res.status}`);
  return res.json();
}

async function pool(items, limit, fn) {
  const out = new Array(items.length);
  let next = 0;
  async function worker() {
    while (next < items.length) {
      const i = next++;
      out[i] = await fn(items[i]);
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
  return out;
}

// ---- Skraćivanje -----------------------------------------------------------

function shortText(s) {
  if (typeof s !== "string") return s;
  const chars = Array.from(s);
  return chars.length <= TEXT_MAX ? s : `${chars.slice(0, TEXT_MAX).join("")}…`;
}

function shortList(a, max) {
  return Array.isArray(a) ? a.slice(0, max) : a;
}

function pick(obj, keys) {
  const out = {};
  for (const k of keys) if (Object.hasOwn(obj, k)) out[k] = obj[k];
  return out;
}

function omit(obj, drop) {
  return Object.fromEntries(Object.entries(obj).filter(([k]) => !drop.has(k)));
}

const BITS_ORDER = [
  "has_transcript", "has_diarized", "has_summary", "has_article", "has_magisterium",
  "has_translation_en", "has_summary_en", "has_article_en", "has_magisterium_en",
];
const flagsKey = (v) => BITS_ORDER.map((b) => (v.pipeline?.[b] ? "1" : "0")).join("");

/**
 * ≤ MAX_VIDEOS epizoda, izvorni redoslijed: obavezne, sve s magisterium
 * ocjenom, prva sa svakom različitom kombinacijom zastavica, pa redom od vrha.
 */
function selectVideos(slug, videos) {
  const keep = new Set(PINNED_VIDEOS[slug] ?? []);
  for (const id of keep) {
    if (!videos.some((v) => v.id === id)) throw new Error(`${slug}: nema obavezne epizode ${id}`);
  }
  const add = (v) => keep.size < MAX_VIDEOS && keep.add(v.id);
  for (const v of videos) if (v.magisterium_score !== null && v.magisterium_score !== undefined) add(v);
  const seenFlags = new Set();
  for (const v of videos) {
    const k = flagsKey(v);
    if (!seenFlags.has(k)) {
      seenFlags.add(k);
      add(v);
    }
  }
  for (const v of videos) add(v);
  return videos.filter((v) => keep.has(v.id));
}

function shortVideo(v) {
  const out = { ...v };
  if ("abstract" in out) out.abstract = shortText(out.abstract);
  if ("topics" in out) out.topics = shortList(out.topics, LIST_MAX);
  if ("speakers" in out) out.speakers = shortList(out.speakers, LIST_MAX);
  return out;
}

function shortListing(slug, listing) {
  const out = {};
  for (const [k, v] of Object.entries(listing)) {
    if (k === "description") out[k] = shortText(v);
    else if (k === "tags") out[k] = shortList(v, TAGS_MAX);
    else if (k === "videos") out[k] = selectVideos(slug, v).map(shortVideo);
    else out[k] = v;
  }
  return out;
}

function shortIndex(index) {
  const want = new Set([...LISTING_SLUGS, ...INDEX_EXTRA_SLUGS]);
  const channels = index.channels.filter((c) => want.has(c.id));
  const missing = [...want].filter((s) => !channels.some((c) => c.id === s));
  if (missing.length) throw new Error(`index.json: nema kanala ${missing.join(", ")}`);
  return { ...index, channels };
}

function shortSummary(s) {
  const out = { ...s };
  if (s.summary && typeof s.summary === "object") {
    // Samo skalari: dugi popisi (key_topics, speakers, mentioned_*) parseru ne trebaju.
    out.summary = Object.fromEntries(
      Object.entries(s.summary).filter(([, v]) => v === null || typeof v !== "object"),
    );
  }
  return out;
}

const shortManifest = (e) => pick(e, ["version", "generated_at", "files"]);

const UC = /\/channel\/(UC[0-9A-Za-z_-]{22})(?:\/|$)/;

function shortRegistry(registry, wantedChannelIds, forbiddenChannelIds) {
  const podcasts = registry.podcasts;
  for (const e of podcasts) {
    const id = e.youtube?.channel_id;
    if (id && forbiddenChannelIds.has(id)) {
      throw new Error(`registry: ${e.slug} ima channel_id ${id}, a fixture tvrdi da taj kanal nije u registryju`);
    }
  }
  const slugs = new Set(REGISTRY_EXTRA_SLUGS);
  const chosen = podcasts.filter((e) => slugs.has(e.slug) || wantedChannelIds.has(e.youtube?.channel_id));
  for (const s of slugs) if (!chosen.some((e) => e.slug === s)) throw new Error(`registry: nema unosa ${s}`);
  return { version: registry.version, podcasts: chosen.map((e) => omit(e, REGISTRY_DROP_KEYS)) };
}

/**
 * Key cache sveden na ključeve `data/<id>/…` epizoda iz fixturea, plus prvi
 * `images/` i prvi `channels/` ključ (uvoznik ih mora preskočiti). Sortirano po
 * ključu, veličine doslovne.
 */
function shortKeyCache(cache, ids) {
  if (cache.v !== 2) throw new Error(`key cache: nepoznata verzija ${cache.v}`);
  const keys = Object.keys(cache.sizes).sort();
  const keep = keys.filter((k) => {
    const m = /^data\/([^/]+)\//.exec(k);
    return m !== null && ids.has(m[1]);
  });
  for (const prefix of ["images/", "channels/"]) {
    const k = keys.find((x) => x.startsWith(prefix));
    if (k) keep.push(k);
  }
  for (const id of ids) {
    if (!keep.some((k) => k.startsWith(`data/${id}/`))) throw new Error(`key cache: nema ključeva za ${id}`);
  }
  keep.sort();
  return { v: cache.v, sizes: Object.fromEntries(keep.map((k) => [k, cache.sizes[k]])) };
}

// ---- Tripwire: PIPELINE_BITS ----------------------------------------------

async function checkPipelineBits(ours) {
  let src;
  try {
    src = await readFile(CHANNEL_INDEX_JS, "utf8");
  } catch {
    console.warn(`upozorenje: ${CHANNEL_INDEX_JS} nije dostupan, PIPELINE_BITS nije uspoređen`);
    return;
  }
  const m = /const PIPELINE_BITS = \[([^\]]*)\]/.exec(src);
  if (!m) throw new Error(`${CHANNEL_INDEX_JS}: ne nalazim PIPELINE_BITS`);
  const theirs = [...m[1].matchAll(/'([^']+)'|"([^"]+)"/g)].map((x) => x[1] ?? x[2]);
  if (JSON.stringify(theirs) !== JSON.stringify([...ours])) {
    throw new Error(`PIPELINE_BITS se razlikuje od fetch repoa:\n  naš:   ${ours.join(",")}\n  fetch: ${theirs.join(",")}`);
  }
}

// ---- Glavni tok ------------------------------------------------------------

async function main() {
  const P = await import("../src/input/index.ts");
  if (JSON.stringify(BITS_ORDER) !== JSON.stringify([...P.PIPELINE_BITS])) {
    throw new Error("BITS_ORDER u skripti ≠ PIPELINE_BITS u src/input/pipeline-bits.ts");
  }
  await checkPipelineBits(P.PIPELINE_BITS);

  const jobs = [
    { path: "channels/data/index.json", out: "channels/index.json", shorten: shortIndex, parse: P.parseChannelIndex },
    ...LISTING_SLUGS.map((slug) => ({
      path: `channels/data/${slug}.json`,
      out: `channels/${slug}.json`,
      shorten: (x) => shortListing(slug, x),
      parse: P.parseChannelListing,
    })),
    ...UNLISTED_IDS.flatMap((id) => [
      { path: `data/${id}/info.json`, out: `data/${id}/info.json`, shorten: (x) => pick(x, INFO_KEYS), parse: P.parseEpisodeInfo },
      { path: `data/${id}/summary.json`, out: `data/${id}/summary.json`, shorten: shortSummary, parse: P.parseEpisodeSummary },
      { path: `data/${id}/episode.json`, out: `data/${id}/episode.json`, shorten: shortManifest, parse: P.parseEpisodeManifest },
    ]),
    ...NO_INFO_IDS.map((id) => ({
      path: `data/${id}/summary.json`, out: `data/${id}/summary.json`, shorten: shortSummary, parse: P.parseEpisodeSummary,
    })),
  ];

  const fetched = await pool(jobs, CONCURRENCY, async (job) => {
    const raw = await getJson(job.path);
    return { ...job, data: job.shorten(raw) };
  });

  // channel_id-evi svih kanala u fixtureima: iz index URL-ova i iz info.json.
  const wanted = new Set();
  const forbidden = new Set();
  for (const f of fetched) {
    if (f.out === "channels/index.json") {
      for (const c of f.data.channels) {
        const m = UC.exec(c.youtube_channel_url ?? "");
        if (m) wanted.add(m[1]);
      }
    } else if (f.out.endsWith("/info.json")) {
      const id = f.data.id;
      if (NOT_IN_REGISTRY_IDS.includes(id)) forbidden.add(f.data.channel_id);
      else wanted.add(f.data.channel_id);
    }
  }
  const registry = JSON.parse(await readFile(REGISTRY_PATH, "utf8"));
  const keyCache = JSON.parse(await readFile(KEY_CACHE_PATH, "utf8"));
  const fixtureIds = new Set([...UNLISTED_IDS, ...NO_INFO_IDS]);
  for (const f of fetched) if (f.out.startsWith("channels/") && f.data.videos) for (const v of f.data.videos) fixtureIds.add(v.id);
  for (const id of NO_INFO_IDS) {
    if (Object.hasOwn(keyCache.sizes, `data/${id}/info.json`)) throw new Error(`key cache: ${id} ima info.json, a fixture tvrdi da nema`);
  }
  const files = [
    ...fetched,
    { out: "registry/podcasts_registry.json", data: shortRegistry(registry, wanted, forbidden), parse: P.parseRegistry },
    { out: "r2_keys_cache.json", data: shortKeyCache(keyCache, fixtureIds), parse: (await import("../src/ingest/keys.ts")).parseKeyCache },
  ];

  // Stari generirani sadržaj van (README ostaje), pa upis.
  for (const dir of ["channels", "data", "registry"]) await rm(join(OUT, dir), { recursive: true, force: true });
  await rm(join(OUT, "r2_keys_cache.json"), { force: true });
  for (const f of files) {
    const text = `${JSON.stringify(f.data, null, 2)}\n`;
    f.parse(JSON.parse(text)); // baca InputError s putanjom ako fixture ne prolazi parser
    const dest = join(OUT, f.out);
    await mkdir(dirname(dest), { recursive: true });
    await writeFile(dest, text);
    console.log(`${f.out}  ${Buffer.byteLength(text)} B`);
  }
  console.log(`${files.length} datoteka u ${OUT}`);
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
