import { describe, expect, it } from "vitest";
import { decodeCursor, encodeCursor, isIsoDate } from "../../src/api/cursor.ts";

describe("kursor", () => {
  it("base64url bez paddinga, povratno", () => {
    for (const [d, k] of [
      ["2026-11-05", "UM2MWlNUp_1"],
      ["2018-10-01", "yt-UCckHqySbfy5FcPP6MD_S-Yg"],
      ["2026-01-01", "a"],
      ["2026-01-01", "čšž/+?"],
    ] as const) {
      const c = encodeCursor(d, k);
      expect(c).toMatch(/^[A-Za-z0-9_-]+$/);
      expect(decodeCursor(c)).toEqual([d, k]);
    }
  });

  it.each([
    ["prazan", ""],
    ["znak izvan abecede", "ab+c"],
    ["padding", `${encodeCursor("2026-01-01", "ab")}=`],
    ["nije JSON", "bmlqZQ"],
    ["objekt", btoa('{"a":1}').replace(/=+$/, "")],
    ["tri elementa", btoa('["2026-01-01","a","b"]').replace(/=+$/, "")],
    ["broj kao ključ", btoa('["2026-01-01",1]').replace(/=+$/, "")],
    ["prazan ključ", btoa('["2026-01-01",""]').replace(/=+$/, "")],
    ["nepostojeći datum", btoa('["2026-02-30","a"]').replace(/=+$/, "")],
    ["YYYYMMDD", btoa('["20260101","a"]').replace(/=+$/, "")],
    ["razmak u JSON-u (nije kanonski)", btoa('["2026-01-01", "a"]').replace(/=+$/, "")],
  ])("odbija: %s", (_name, c) => {
    expect(decodeCursor(c)).toBeNull();
  });

  it("isIsoDate", () => {
    expect(isIsoDate("2024-02-29")).toBe(true);
    expect(isIsoDate("2026-02-29")).toBe(false);
    expect(isIsoDate("2026-1-01")).toBe(false);
    expect(isIsoDate("+02026-01-01")).toBe(false);
  });
});
