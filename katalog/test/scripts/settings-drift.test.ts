// Drift postavki kanala (scripts/lib/settings-drift.ts): očekivano stanje iz
// izvora, usporedba s `GET /settings`, slugovi, exit kodovi. Bez mreže.
import { describe, expect, it } from "vitest";
import { EXIT_DRIFT, EXIT_OK, EXIT_UNKNOWN } from "../../scripts/lib/drift.ts";
import {
  combineExit,
  compareSettings,
  expectedSettings,
  formatSettingsReport,
  parseKatalogSettings,
  runSettingsDrift,
  type SettingsDriftDeps,
} from "../../scripts/lib/settings-drift.ts";
import { SETTING_KEYS } from "../../src/settings/keys.ts";

const urlOf = (input: RequestInfo | URL): string =>
  typeof input === "string" ? input : input instanceof URL ? input.href : input.url;

const UC_A = "UCaaaaaaaaaaaaaaaaaaaaaa";
const UC_W = "UCwwwwwwwwwwwwwwwwwwwwww";
const UC_D = "UCdddddddddddddddddddddd";
const UC_ON = "UCoooooooooooooooooooooo";
const KEY = "anon-key-0123456789";
const DELETED_AT = "2026-11-11T10:00:00.123456+00:00";

function eff(off: readonly string[]): Record<string, boolean> {
  const o: Record<string, boolean> = {};
  for (const k of SETTING_KEYS) o[k] = !off.includes(k);
  return o;
}

const sourceSettings = [
  { youtube_channel_id: UC_A, effective: eff(["ebook", "donations"]), updated_at: "2026-11-11T09:00:00+00:00", tombstoned: false },
  { youtube_channel_id: UC_W, effective: eff([...SETTING_KEYS]), updated_at: "2026-11-11T09:01:00+00:00", tombstoned: false },
  { youtube_channel_id: UC_D, effective: eff([...SETTING_KEYS]), updated_at: DELETED_AT, tombstoned: true },
  // Vlasnik je sve vratio: redak postoji, ali u `/settings` ga nema.
  { youtube_channel_id: UC_ON, effective: eff([]), updated_at: "2026-11-11T09:02:00+00:00", tombstoned: false },
];
const sourceTombstones = [
  { youtube_channel_id: UC_D, channel_title: "Obrisan", slugs: ["obrisan"], requested_at: null, phone_confirmed_at: null, deleted_at: DELETED_AT },
];
const allOff = [...SETTING_KEYS].sort();

const aligned = {
  [UC_A]: { status: "active", off: ["donations", "ebook"] },
  [UC_W]: { status: "withdrawn", off: allOff },
  // Katalog vraća trenutak u svom obliku (milisekunde, Z): isti trenutak, nije drift.
  [UC_D]: { status: "deleted", off: [], deleted_at: "2026-11-11T10:00:00.123Z" },
};

describe("expectedSettings", () => {
  it("samo UC-ovi s isključenim ključem ili tombstoneom; withdrawn = channel_enabled false", () => {
    const e = expectedSettings(sourceSettings, sourceTombstones);
    expect([...e.keys()].sort()).toEqual([UC_A, UC_D, UC_W].sort());
    expect(e.get(UC_A)).toEqual({ status: "active", off: ["donations", "ebook"] });
    expect(e.get(UC_W)?.status).toBe("withdrawn");
    expect(e.get(UC_D)).toMatchObject({ status: "deleted", deleted_at: DELETED_AT });
  });

  it("tombstoned bez tombstonea baca", () => {
    expect(() => expectedSettings(sourceSettings, [])).toThrow(/tombstone/);
  });
});

describe("compareSettings", () => {
  const expected = expectedSettings(sourceSettings, sourceTombstones);

  it("poravnato", () => {
    const c = compareSettings(expected, parseKatalogSettings({ version: "1", settings: aligned }));
    expect(c).toMatchObject({ missing: [], extra: [], mismatched: [] });
  });

  it("missing, extra, različit off, različit deleted_at", () => {
    const c = compareSettings(
      expected,
      parseKatalogSettings({
        version: "1",
        settings: {
          [UC_A]: { status: "active", off: ["ebook"] },
          [UC_D]: { status: "deleted", off: [], deleted_at: "2026-11-12T00:00:00Z" },
          [UC_ON]: { status: "active", off: ["ebook"] },
        },
      }),
    );
    expect(c.missing).toEqual([UC_W]);
    expect(c.extra).toEqual([UC_ON]);
    expect(c.mismatched.map((m) => m.uc).sort()).toEqual([UC_A, UC_D].sort());
  });

  it.each([
    ["bez version", { settings: {} }],
    ["nepoznat status", { version: "1", settings: { [UC_A]: { status: "hidden", off: [] } } }],
    ["deleted bez deleted_at", { version: "1", settings: { [UC_A]: { status: "deleted", off: [] } } }],
    ["off nije polje", { version: "1", settings: { [UC_A]: { status: "active", off: "ebook" } } }],
  ])("nevaljan odgovor kataloga (%s) baca", (_n, body) => {
    expect(() => parseKatalogSettings(body)).toThrow();
  });
});

describe("combineExit", () => {
  it("ne znam > drift > ok", () => {
    expect(combineExit(EXIT_OK, EXIT_OK)).toBe(EXIT_OK);
    expect(combineExit(EXIT_OK, EXIT_DRIFT)).toBe(EXIT_DRIFT);
    expect(combineExit(EXIT_DRIFT, EXIT_UNKNOWN)).toBe(EXIT_UNKNOWN);
    expect(combineExit(EXIT_UNKNOWN, EXIT_OK)).toBe(EXIT_UNKNOWN);
  });
});

interface World {
  katalogSettings?: unknown;
  katalogStatus?: number;
  slugs: { slug: string; youtube_channel_id: string }[];
  apiStatus?: number;
}

function deps(w: World, over: Partial<SettingsDriftDeps> = {}): SettingsDriftDeps {
  const f = ((input: RequestInfo | URL) => {
    const url = new URL(urlOf(input));
    const path = url.pathname;
    if (path.startsWith("/rest/v1/") && w.apiStatus !== undefined) {
      return Promise.resolve(new Response(`odbijeno ${KEY}`, { status: w.apiStatus }));
    }
    const after = url.searchParams.get("youtube_channel_id")?.replace(/^gt\./, "");
    const page = (rows: readonly { youtube_channel_id: string }[]) =>
      Response.json(after === undefined ? rows : rows.filter((r) => r.youtube_channel_id > after));
    if (path === "/rest/v1/public_channel_settings") return Promise.resolve(page(sourceSettings));
    if (path === "/rest/v1/public_channel_tombstones") return Promise.resolve(page(sourceTombstones));
    if (path === "/rest/v1/channel_slugs") return Promise.resolve(Response.json(w.slugs));
    if (path === "/api/katalog/v1/settings") {
      if (w.katalogStatus !== undefined) return Promise.resolve(Response.json({ ok: false, error: "not_found" }, { status: w.katalogStatus }));
      return Promise.resolve(Response.json(w.katalogSettings ?? { version: "1", catalog: "1", settings: aligned, meta: {} }));
    }
    if (path === "/api/katalog/v1/channels") {
      return Promise.resolve(
        Response.json({
          items: [
            { slug: "kanal_a", youtube_channel_id: UC_A },
            { slug: "launched", youtube_channel_id: null },
            { slug: "dijalog", youtube_channel_id: null },
          ],
          next: null,
        }),
      );
    }
    return Promise.resolve(new Response("?", { status: 404 }));
  }) as typeof fetch;
  return {
    katalogBase: "https://k.test",
    apiBase: "https://api.test",
    anonKey: KEY,
    fetch: f,
    registryUc: () => Promise.resolve(new Map([["launched", UC_W]])),
    ...over,
  };
}

const allSlugs = [
  { slug: "kanal_a", youtube_channel_id: UC_A },
  { slug: "launched", youtube_channel_id: UC_W },
];

describe("runSettingsDrift", () => {
  it("poravnato → exit 0", async () => {
    const r = await runSettingsDrift(deps({ slugs: allSlugs }));
    expect(r.error).toBeUndefined();
    expect(r).toMatchObject({ status: "ok", exitCode: EXIT_OK, slugs: { catalog: 2, missing: [], wrongUc: [] } });
  });

  it("slug bez retka u channel_slugs (i registry pad) → drift", async () => {
    const r = await runSettingsDrift(deps({ slugs: [{ slug: "kanal_a", youtube_channel_id: UC_W }] }));
    expect(r).toMatchObject({ status: "drift", exitCode: EXIT_DRIFT, slugs: { missing: ["launched"], wrongUc: ["kanal_a"] } });
  });

  it("drift postavki → exit 1", async () => {
    const r = await runSettingsDrift(deps({ slugs: allSlugs, katalogSettings: { version: "1", settings: {} } }));
    expect(r.exitCode).toBe(EXIT_DRIFT);
    expect(r.settings?.missing).toHaveLength(3);
    expect(formatSettingsReport(r).join("\n")).toContain("DRIFT");
  });

  it("katalog još nema /settings (404) → exit 2, ne drift", async () => {
    const r = await runSettingsDrift(deps({ slugs: allSlugs, katalogStatus: 404 }));
    expect(r).toMatchObject({ status: "unknown", exitCode: EXIT_UNKNOWN });
    expect(r.settings).toBeUndefined();
  });

  it("401 izvora → exit 2, ključ se ne ispisuje", async () => {
    const r = await runSettingsDrift(deps({ slugs: allSlugs, apiStatus: 401 }));
    expect(r.exitCode).toBe(EXIT_UNKNOWN);
    expect(r.error).toContain("HTTP 401");
    expect(r.error).not.toContain(KEY);
  });

  it("bez ključa → exit 2 bez mreže", async () => {
    let calls = 0;
    const r = await runSettingsDrift(
      deps({ slugs: allSlugs }, {
        anonKey: null,
        fetch: () => {
          calls += 1;
          return Promise.reject(new Error("ne smije"));
        },
      }),
    );
    expect(r.exitCode).toBe(EXIT_UNKNOWN);
    expect(calls).toBe(0);
  });
});
