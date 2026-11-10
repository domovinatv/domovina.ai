import { describe, expect, it } from "vitest";
import { parsePublishDates, zagrebDay } from "../../src/input/index.ts";

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

  it("bez channels → prazna mapa; korijen mora biti objekt", () => {
    expect(parsePublishDates({}).size).toBe(0);
    expect(() => parsePublishDates([])).toThrow();
  });
});

describe("zagrebDay", () => {
  it("23:00Z zimi je sljedeći dan, 21:59Z ljeti isti, 22:00Z ljeti sljedeći", () => {
    expect(zagrebDay(Date.parse("2026-11-08T23:00:06Z") / 1000)).toBe("2026-11-09");
    expect(zagrebDay(Date.parse("2026-07-01T21:59:59Z") / 1000)).toBe("2026-07-01");
    expect(zagrebDay(Date.parse("2026-07-01T22:00:00Z") / 1000)).toBe("2026-07-02");
  });
});
