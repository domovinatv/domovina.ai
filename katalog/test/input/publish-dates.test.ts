import { describe, expect, it } from "vitest";
import { parsePublishDates, parsePublishTimes, zagrebDay } from "../../src/input/index.ts";

describe("parsePublishDates (backfill.json)", () => {
  it("skuplja originals svih kanala, preskače neispravne zapise", () => {
    const m = parsePublishDates({
      generated_at: "2026-11-10T02:45:00Z",
      channels: {
        "hrt-otvoreno": { originals: { kO2ILIGJiIU: { date: "2026-11-09", published_at: "2026-11-09T20:27:27Z" } } },
        "ora-et-labora": {
          originals: {
            cvEZWm_ZlWU: { date: "2026-11-09" },
            bad_date_01: { date: "2026-02-30" },
            bad_form_01: { date: "20261109" },
            no_date_001: {},
          },
        },
        broken: { error: "quota" },
        nul: null,
      },
    });
    expect([...m.entries()]).toEqual([
      ["kO2ILIGJiIU", "2026-11-09"],
      ["cvEZWm_ZlWU", "2026-11-09"],
    ]);
  });

  it("čita i extras (Tier 1 izvan originala); original pobjeđuje isti ID", () => {
    const m = parsePublishDates({
      channels: {
        "budi-frajer": {
          originals: { sameId_0001: { date: "2026-11-09" } },
          extras: { short_ep_01: { date: "2026-10-01", published_at: "2026-10-01T08:00:00Z" } },
        },
        other: { extras: { sameId_0001: { date: "2026-11-08" }, bad_extra1: { date: "x" } } },
      },
    });
    expect(Object.fromEntries(m)).toEqual({ short_ep_01: "2026-10-01", sameId_0001: "2026-11-09" });
    expect(parsePublishTimes({ channels: { a: { extras: { short_ep_01: { published_at: "2026-10-01T08:00:00Z" } } } } }).get("short_ep_01")).toBe(
      "2026-10-01T08:00:00Z",
    );
  });

  it("bez channels → prazna mapa; korijen mora biti objekt", () => {
    expect(parsePublishDates({}).size).toBe(0);
    expect(() => parsePublishDates([])).toThrow();
  });
});

describe("parsePublishTimes (backfill.json)", () => {
  it("published_at u kanonskom UTC obliku; neispravan ili bez njega se preskače", () => {
    const m = parsePublishTimes({
      channels: {
        a: {
          originals: {
            kO2ILIGJiIU: { date: "2026-11-09", published_at: "2026-11-09T20:27:27Z" },
            ms_________: { published_at: "2026-11-09T20:27:27.500Z" },
            cvEZWm_ZlWU: { date: "2026-11-09" },
            bad_day_001: { published_at: "2026-02-30T10:00:00Z" },
            bad_zone_01: { published_at: "2026-11-09T20:27:27+01:00" },
          },
        },
      },
    });
    expect([...m.entries()]).toEqual([
      ["kO2ILIGJiIU", "2026-11-09T20:27:27Z"],
      ["ms_________", "2026-11-09T20:27:27Z"],
    ]);
  });
});

describe("zagrebDay", () => {
  it("23:00Z zimi je sljedeći dan, 21:59Z ljeti isti, 22:00Z ljeti sljedeći", () => {
    expect(zagrebDay(Date.parse("2026-11-08T23:00:06Z") / 1000)).toBe("2026-11-09");
    expect(zagrebDay(Date.parse("2026-07-01T21:59:59Z") / 1000)).toBe("2026-07-01");
    expect(zagrebDay(Date.parse("2026-07-01T22:00:00Z") / 1000)).toBe("2026-07-02");
  });
});
