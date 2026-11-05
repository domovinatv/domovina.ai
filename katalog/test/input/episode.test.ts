import { describe, expect, it } from "vitest";
import {
  type EpisodeInfo,
  parseEpisodeInfo,
  parseEpisodeManifest,
  parseEpisodeSummary,
} from "../../src/input/index.ts";
import { clone, fixtures, NO_INFO_IDS, UNLISTED_IDS, inputError } from "./fixtures.ts";

function raw(map: Map<string, unknown>, id: string): Record<string, unknown> {
  const v = map.get(id);
  if (v === undefined) throw new Error(`nema fixturea ${id}`);
  return clone(v) as Record<string, unknown>;
}

describe("parseEpisodeInfo", () => {
  const infos = new Map<string, EpisodeInfo>([...fixtures.infos()].map(([id, r]) => [id, parseEpisodeInfo(r)]));

  it("čita svih 5, id = ime direktorija, datum pretvoren u YYYY-MM-DD", () => {
    expect([...infos.keys()].sort()).toEqual(UNLISTED_IDS);
    for (const [id, info] of infos) {
      expect(info.id).toBe(id);
      expect(info.uploadDate).toMatch(/^\d{4}-\d{2}-\d{2}$/);
      expect(info.channelId).not.toBeNull();
    }
  });

  it("YouTube epizoda registriranog kanala", () => {
    expect(infos.get("kYwKrihe2K0")).toEqual({
      id: "kYwKrihe2K0",
      title: "Argumenti - 01.10.2018.",
      channel: "Hrvatska katolička mreža",
      channelId: "UCrfV3uhCoHNBaqiva1wCB4Q",
      uploader: "Hrvatska katolička mreža",
      uploadDate: "2018-10-01",
      durationSeconds: 2017,
      extractor: "youtube",
    });
  });

  it("KLPD-Meu4e8: Tier 1 kanal (nanovoroeni) u _unlisted", () => {
    expect(infos.get("KLPD-Meu4e8")).toMatchObject({
      channel: "Nanovo rođeni",
      channelId: "UCiXXRMlzoA-MKPHVe5V7YdQ",
      uploadDate: "2020-02-08",
      durationSeconds: 4179,
    });
  });

  it("CUJmOc91C64 (X/Twitter): decimalno trajanje, bez kanala, numerički channel_id", () => {
    expect(infos.get("CUJmOc91C64")).toMatchObject({
      channel: null,
      channelId: "1973380383166050304",
      uploadDate: "2026-07-16",
      durationSeconds: 245.295,
      extractor: "twitter",
    });
    // U izvoru ključa `channel` NEMA (nije `null`): isto značenje za parser.
    expect(raw(fixtures.infos(), "CUJmOc91C64")).not.toHaveProperty("channel");
  });

  it("hmM9f_3Mqm4: trajanje nepoznato → null (ključa nema)", () => {
    expect(infos.get("hmM9f_3Mqm4")?.durationSeconds).toBeNull();
    expect(raw(fixtures.infos(), "hmM9f_3Mqm4")).not.toHaveProperty("duration");
  });

  describe("negativni", () => {
    it.each([
      ["20260230", /nepostojeći datum/],
      ["2026-07-16", /YYYYMMDD/],
      [20260716, /očekivan string/],
    ])("upload_date %s", (date, msg) => {
      const r = raw(fixtures.infos(), "CUJmOc91C64");
      r.upload_date = date;
      const err = inputError(() => parseEpisodeInfo(r));
      expect(err.path).toBe("upload_date");
      expect(err.message).toMatch(msg);
    });

    it("trajanje kao string", () => {
      const r = raw(fixtures.infos(), "kYwKrihe2K0");
      r.duration = "2017";
      expect(inputError(() => parseEpisodeInfo(r)).path).toBe("duration");
    });

    it("negativno trajanje", () => {
      const r = raw(fixtures.infos(), "kYwKrihe2K0");
      r.duration = -1;
      expect(inputError(() => parseEpisodeInfo(r)).path).toBe("duration");
    });

    it("bez id-a", () => {
      const r = raw(fixtures.infos(), "kYwKrihe2K0");
      delete r.id;
      expect(inputError(() => parseEpisodeInfo(r)).path).toBe("id");
    });

    it("numerički channel_id kao broj, ne string", () => {
      const r = raw(fixtures.infos(), "CUJmOc91C64");
      r.channel_id = 1973380383166050304;
      expect(inputError(() => parseEpisodeInfo(r)).path).toBe("channel_id");
    });
  });
});

describe("parseEpisodeSummary", () => {
  const summaries = new Map([...fixtures.summaries()].map(([id, r]) => [id, parseEpisodeSummary(r)]));

  it("čita svih 9; jezik hr, naslov iz source.title", () => {
    expect([...summaries.keys()].sort()).toEqual([...UNLISTED_IDS, ...NO_INFO_IDS].sort());
    for (const s of summaries.values()) {
      expect(s.language).toBe("hr");
      expect(s.title).not.toBeNull();
      expect(s.titleHr).not.toBeNull();
      expect(s.abstractHr).not.toBeNull();
    }
  });

  it("trajanje prati info.json: 245.295, null, cijeli broj", () => {
    expect(summaries.get("CUJmOc91C64")?.durationSeconds).toBe(245.295);
    expect(summaries.get("hmM9f_3Mqm4")?.durationSeconds).toBeNull();
    expect(summaries.get("KLPD-Meu4e8")).toMatchObject({
      title: "Goran Ćurković | Svjedočanstvo/Testimony (Eng. sub)",
      titleHr: "Goran Ćurković – svjedočanstvo",
      durationSeconds: 4179,
    });
  });

  it("naslov u summary.json = title u info.json", () => {
    const infos = fixtures.infos();
    for (const [id, s] of summaries) {
      if (NO_INFO_IDS.includes(id)) continue;
      expect(s.title).toBe(parseEpisodeInfo(infos.get(id)).title);
    }
  });

  it("bez source/summary objekta → sve null", () => {
    expect(parseEpisodeSummary({ version: "1.0" })).toEqual({
      title: null,
      titleHr: null,
      abstractHr: null,
      language: null,
      durationSeconds: null,
      uploadDate: null,
      sourceChannel: null,
    });
  });

  it("krivi tip u summary.title_hr", () => {
    const r = raw(fixtures.summaries(), "kYwKrihe2K0");
    (r.summary as Record<string, unknown>).title_hr = ["niz"];
    expect(inputError(() => parseEpisodeSummary(r)).path).toBe("summary.title_hr");
  });

  it("jezik izvan 2–16 znakova", () => {
    const r = raw(fixtures.summaries(), "kYwKrihe2K0");
    (r.summary as Record<string, unknown>).language = "h";
    expect(inputError(() => parseEpisodeSummary(r)).path).toBe("summary.language");
  });

  it("source.duration_seconds kao string", () => {
    const r = raw(fixtures.summaries(), "CUJmOc91C64");
    (r.source as Record<string, unknown>).duration_seconds = "245.295";
    expect(inputError(() => parseEpisodeSummary(r)).path).toBe("source.duration_seconds");
  });
});

describe("parseEpisodeManifest", () => {
  const manifests = new Map([...fixtures.manifests()].map(([id, r]) => [id, parseEpisodeManifest(r)]));

  it("čita svih 5; files uvijek nosi info.json i summary.json", () => {
    expect([...manifests.keys()].sort()).toEqual(UNLISTED_IDS);
    for (const m of manifests.values()) {
      expect(m.files).toContain("info.json");
      expect(m.files).toContain("summary.json");
      expect(m.generatedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);
    }
  });

  it("inline se ignorira", () => {
    const r = raw(fixtures.manifests(), "KLPD-Meu4e8");
    r.inline = { "info.json": { id: "KLPD-Meu4e8" } };
    expect(Object.keys(parseEpisodeManifest(r))).toEqual(["generatedAt", "files"]);
  });

  it.each([2, "1", undefined])("verzija %s se odbija (klijent čita samo 1)", (version) => {
    const r = raw(fixtures.manifests(), "kYwKrihe2K0");
    r.version = version;
    expect(inputError(() => parseEpisodeManifest(r)).path).toBe("version");
  });

  it("files nije niz stringova", () => {
    const r = raw(fixtures.manifests(), "kYwKrihe2K0");
    r.files = ["info.json", 7];
    expect(inputError(() => parseEpisodeManifest(r)).path).toBe("files[1]");
  });

  it("bez files", () => {
    const r = raw(fixtures.manifests(), "kYwKrihe2K0");
    delete r.files;
    expect(inputError(() => parseEpisodeManifest(r)).path).toBe("files");
  });

  it("generated_at koji nije ISO vrijeme", () => {
    const r = raw(fixtures.manifests(), "kYwKrihe2K0");
    r.generated_at = "9.10.2026.";
    expect(inputError(() => parseEpisodeManifest(r)).path).toBe("generated_at");
  });
});
