import { describe, expect, it } from "vitest";
import {
  parseChannelIndex,
  parseChannelListing,
  PIPELINE_BITS,
  youtubeChannelIdFromUrl,
} from "../../src/input/index.ts";
import { clone, fixtures, LISTING_SLUGS, inputError } from "./fixtures.ts";

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;
const SHARED_UC = "UCuk9D5H9mx7birJ1-S22nyQ";

interface RawVideo {
  id: string;
  date: unknown;
  magisterium_score: unknown;
  duration_seconds: unknown;
  title: unknown;
  pipeline: Record<string, unknown> | null;
}
interface RawListing {
  videos: RawVideo[];
  [k: string]: unknown;
}
interface RawIndex {
  channels: Record<string, unknown>[];
}

function rawListing(slug: string): RawListing {
  const raw = fixtures.listings().get(slug);
  if (raw === undefined) throw new Error(`nema fixturea ${slug}`);
  return clone(raw as RawListing);
}

function rawVideo(listing: RawListing, i: number): RawVideo {
  const v = listing.videos[i];
  if (v === undefined) throw new Error(`nema videos[${i}]`);
  return v;
}

describe("parseChannelIndex", () => {
  const index = parseChannelIndex(fixtures.index());
  const bySlug = new Map(index.channels.map((c) => [c.slug, c]));

  it("čita svih 7 kanala iz fixturea (svaki ima listing)", () => {
    expect([...bySlug.keys()].sort()).toEqual(LISTING_SLUGS);
    expect(index.generatedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);
  });

  it("youtubeChannelId samo iz /channel/UC… URL-a; dijalog (Spotify) → null", () => {
    expect(bySlug.get("40_dana_za_zivot")?.youtubeChannelId).toBe("UChgVPEqmTeG0na3u8VfY3PQ");
    expect(bySlug.get("nanovoroeni")?.youtubeChannelId).toBe("UCiXXRMlzoA-MKPHVe5V7YdQ");
    expect(bySlug.get("dijalog")?.youtubeChannelUrl).toMatch(/^https:\/\/open\.spotify\.com\//);
    expect(bySlug.get("dijalog")?.youtubeChannelId).toBeNull();
  });

  it("dva playlist-kanala dijele isti YouTube channel_id", () => {
    const shared = index.channels.filter((c) => c.youtubeChannelId === SHARED_UC).map((c) => c.slug);
    expect(shared).toEqual(["slijedi_svoj_poziv_1", "slijedi_svoj_poziv_2"]);
  });

  it("polja zaglavlja: ime, avatar, broj epizoda, datum zadnje (iz latest_video.date)", () => {
    for (const c of index.channels) {
      expect(c.name.length).toBeGreaterThan(0);
      expect(c.avatarSquare).toMatch(/^https:\/\/cdn\.domovina\.ai\/channels\/images\//);
      expect(c.videoCount).toBeGreaterThan(0);
      expect(c.latestVideoDate).toMatch(ISO_DATE);
      expect(c.youtubePlaylistUrl).toBeNull();
    }
  });

  it("kanal koji se ponavlja → InputError", () => {
    const raw = clone(fixtures.index()) as RawIndex;
    const first = raw.channels[0];
    if (first === undefined) throw new Error("prazan index");
    raw.channels.push(first);
    expect(inputError(() => parseChannelIndex(raw)).path).toBe("channels[7].id");
  });

  it("krivi tip video_count → InputError s putanjom", () => {
    const raw = clone(fixtures.index()) as RawIndex;
    const c = raw.channels[2];
    if (c === undefined) throw new Error("nema channels[2]");
    c.video_count = "320";
    expect(inputError(() => parseChannelIndex(raw)).path).toBe("channels[2].video_count");
  });
});

describe("youtubeChannelIdFromUrl", () => {
  it.each([
    ["https://www.youtube.com/channel/UChgVPEqmTeG0na3u8VfY3PQ", "UChgVPEqmTeG0na3u8VfY3PQ"],
    ["https://www.youtube.com/channel/UChgVPEqmTeG0na3u8VfY3PQ/videos", "UChgVPEqmTeG0na3u8VfY3PQ"],
    ["https://www.youtube.com/@nanovoroeni3392/videos", null],
    ["https://www.youtube.com/playlist?list=PLxkKGjCBwZTIHoy-VRgCjF7rgSyOJVeNm", null],
    ["https://open.spotify.com/show/1uLNzddcxKWG5Qz8LDWXD6", null],
    ["https://evil.example/channel/UChgVPEqmTeG0na3u8VfY3PQ", null],
    ["https://www.youtube.com/channel/UCkratko", null],
    ["nije url", null],
    [null, null],
  ])("%s → %s", (url, id) => {
    expect(youtubeChannelIdFromUrl(url)).toBe(id);
  });
});

describe("parseChannelListing", () => {
  const listings = new Map([...fixtures.listings()].map(([slug, raw]) => [slug, { raw, parsed: parseChannelListing(raw) }]));

  it("čita sva 3 listinga, slug = ime datoteke, ≤ 20 epizoda", () => {
    expect([...listings.keys()].sort()).toEqual(LISTING_SLUGS);
    for (const [slug, { parsed }] of listings) {
      expect(parsed.slug).toBe(slug);
      expect(parsed.videos.length).toBeGreaterThan(0);
      expect(parsed.videos.length).toBeLessThanOrEqual(20);
      expect(parsed.latestVideoDate).toMatch(ISO_DATE);
      // Fixture je skraćen, zaglavlje nije: video_count je pipelineov broj.
      expect(parsed.videoCount).toBeGreaterThanOrEqual(parsed.videos.length);
    }
  });

  it("svaka epizoda: datum YYYY-MM-DD, trajanje ≥ 0, ocjena cijeli broj 0–100 ili null", () => {
    for (const { parsed } of listings.values()) {
      for (const v of parsed.videos) {
        expect(v.date).toMatch(ISO_DATE);
        expect(v.durationSeconds).toBeGreaterThanOrEqual(0);
        if (v.magisteriumScore !== null) {
          expect(Number.isInteger(v.magisteriumScore)).toBe(true);
          expect(v.magisteriumScore).toBeGreaterThanOrEqual(0);
          expect(v.magisteriumScore).toBeLessThanOrEqual(100);
        }
      }
    }
  });

  it("flags = zbroj podignutih bitova iz sirovog pipeline objekta", () => {
    let checked = 0;
    for (const { raw, parsed } of listings.values()) {
      (raw as RawListing).videos.forEach((rv, i) => {
        const expected = PIPELINE_BITS.reduce((acc, b, bit) => (rv.pipeline?.[b] === true ? acc | (1 << bit) : acc), 0);
        expect(parsed.videos[i]?.flags).toBe(expected);
        checked++;
      });
    }
    expect(checked).toBe(119);
  });

  it("nanovoroeni drži KLPD-Meu4e8 (ista epizoda je i u _unlisted)", () => {
    const klpd = listings.get("nanovoroeni")?.parsed.videos.find((v) => v.id === "KLPD-Meu4e8");
    expect(klpd).toMatchObject({
      id: "KLPD-Meu4e8",
      title: "Goran Ćurković | Svjedočanstvo/Testimony (Eng. sub)",
      titleHr: "Goran Ćurković – svjedočanstvo",
      date: "2020-02-08",
      durationSeconds: 4179,
      magisteriumScore: 76,
      flags: 511,
    });
  });

  it("dijalog: ID-evi epizoda nisu YouTube ID-evi (11 hex znakova)", () => {
    const ids = listings.get("dijalog")?.parsed.videos.map((v) => v.id) ?? [];
    expect(ids.length).toBeGreaterThan(0);
    for (const id of ids) expect(id).toMatch(/^[0-9a-f]{11}$/);
    expect(listings.get("dijalog")?.parsed.youtubeChannelId).toBeNull();
  });

  it("40_dana_za_zivot: ocjene iz listinga, i zastavice 511 i 31", () => {
    const videos = listings.get("40_dana_za_zivot")?.parsed.videos ?? [];
    expect(videos.find((v) => v.id === "35Oq01CmGWE")).toMatchObject({ magisteriumScore: 87, flags: 31 });
    expect(videos.find((v) => v.id === "vq65cKlbMjs")).toMatchObject({ magisteriumScore: 95, flags: 511 });
  });

  describe("negativni", () => {
    it("decimalna magisterium ocjena se odbija, ne zaokružuje (odluka 107)", () => {
      const raw = rawListing("nanovoroeni");
      rawVideo(raw, 1).magisterium_score = 83.5;
      const err = inputError(() => parseChannelListing(raw));
      expect(err.path).toBe("videos[1].magisterium_score");
      expect(err.message).toMatch(/cijeli broj/);
    });

    it("ocjena izvan 0–100", () => {
      const raw = rawListing("nanovoroeni");
      rawVideo(raw, 0).magisterium_score = 101;
      expect(inputError(() => parseChannelListing(raw)).path).toBe("videos[0].magisterium_score");
    });

    it.each([
      ["2026-02-30", /nepostojeći datum/],
      ["20260211", /YYYY-MM-DD/],
      ["2026-2-1", /YYYY-MM-DD/],
      [20260211, /očekivan string/],
    ])("nevaljan datum %s", (date, msg) => {
      const raw = rawListing("dijalog");
      rawVideo(raw, 3).date = date;
      const err = inputError(() => parseChannelListing(raw));
      expect(err.path).toBe("videos[3].date");
      expect(err.message).toMatch(msg);
    });

    it("trajanje kao string je greška, ne pretvorba", () => {
      const raw = rawListing("40_dana_za_zivot");
      rawVideo(raw, 2).duration_seconds = "3790";
      expect(inputError(() => parseChannelListing(raw)).path).toBe("videos[2].duration_seconds");
    });

    it("zastavica koja nije boolean", () => {
      const raw = rawListing("40_dana_za_zivot");
      const p = rawVideo(raw, 0).pipeline;
      if (p === null) throw new Error("fixture bez pipelinea");
      p.has_article = 1;
      expect(inputError(() => parseChannelListing(raw)).path).toBe("videos[0].pipeline.has_article");
    });

    it("prazan naslov", () => {
      const raw = rawListing("dijalog");
      rawVideo(raw, 0).title = "";
      expect(inputError(() => parseChannelListing(raw)).path).toBe("videos[0].title");
    });

    it("epizoda koja se ponavlja", () => {
      const raw = rawListing("dijalog");
      raw.videos.push(rawVideo(raw, 0));
      expect(inputError(() => parseChannelListing(raw)).path).toBe(`videos[${raw.videos.length - 1}].id`);
    });

    it("bez videos niza", () => {
      const raw = rawListing("dijalog");
      raw.videos = null as unknown as RawVideo[];
      expect(inputError(() => parseChannelListing(raw)).path).toBe("videos");
    });

    it("korijen nije objekt", () => {
      expect(inputError(() => parseChannelListing([])).path).toBe("$");
    });
  });

  describe("izostanak", () => {
    it("ocjena/datum/trajanje koji nedostaju → null; pipeline koji nedostaje → flags 0", () => {
      const raw = rawListing("nanovoroeni");
      const v = rawVideo(raw, 1) as unknown as Record<string, unknown>;
      delete v.magisterium_score;
      delete v.date;
      v.duration_seconds = null;
      delete v.pipeline;
      const parsed = parseChannelListing(raw).videos[1];
      expect(parsed).toMatchObject({ magisteriumScore: null, date: null, durationSeconds: null, pipeline: null, flags: 0 });
    });

    it("zastavica koja nedostaje nije podignuta", () => {
      const raw = rawListing("40_dana_za_zivot");
      const idx = raw.videos.findIndex((v) => v.id === "vq65cKlbMjs");
      const p = rawVideo(raw, idx).pipeline;
      if (p === null) throw new Error("fixture bez pipelinea");
      delete p.has_magisterium_en;
      expect(parseChannelListing(raw).videos[idx]?.flags).toBe(255);
    });
  });
});
