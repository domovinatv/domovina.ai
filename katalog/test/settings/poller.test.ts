import { createScheduledController } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import type { Env } from "../../src/env.ts";
import worker from "../../src/index.ts";
import { INGEST_SOURCE, LOOKBACK_MS, POLL_SOURCE, pollSettings, type PollDeps } from "../../src/settings/poller.ts";
import { SETTING_KEYS } from "../../src/settings/keys.ts";
import { fakeSource, type FakeSettings, type FakeSource, type FakeTombstone } from "./fake-source.ts";

// Svaki test ima svoj redak `settings_poll_state` (`source`) i svoje UC-ove:
// D1 se dijeli unutar datoteke, a tombstone se ne da obrisati.

const API = "https://api.test";
const KEY = "anon-test-key";

/** UC od 24 znaka (isti CHECK kao domovina-api). */
function uc(tag: string): string {
  return `UC${tag}`.padEnd(24, "0");
}

function settings(id: string, at: string, off: readonly string[] = [], extra: Partial<FakeSettings> = {}): FakeSettings {
  const effective: Record<string, boolean> = {};
  for (const k of SETTING_KEYS) effective[k] = !off.includes(k);
  return { youtube_channel_id: id, effective, updated_at: at, tombstoned: false, ...extra };
}

function deps(source: string, src: FakeSource, over: Partial<PollDeps> = {}): PollDeps {
  return {
    db: env.DB,
    apiUrl: API,
    anonKey: KEY,
    fetch: src.fetch,
    source,
    now: () => new Date("2026-11-11T12:00:00Z"),
    ...over,
  };
}

async function catalogVersion(): Promise<number | null> {
  const row = await env.DB.prepare("SELECT max(id) AS v FROM ingest_runs WHERE status = 'ok'").first<{ v: number | null }>();
  return row?.v ?? null;
}

async function state(source: string): Promise<{ cursor: string | null; status: string } | null> {
  return env.DB.prepare("SELECT cursor, status FROM settings_poll_state WHERE source = ?1")
    .bind(source)
    .first<{ cursor: string | null; status: string }>();
}

async function stored(id: string): Promise<{ effective: Record<string, boolean>; source_updated_at: string } | null> {
  const row = await env.DB.prepare("SELECT effective, source_updated_at FROM channel_settings WHERE youtube_channel_id = ?1")
    .bind(id)
    .first<{ effective: string; source_updated_at: string }>();
  return row === null ? null : { effective: JSON.parse(row.effective) as Record<string, boolean>, source_updated_at: row.source_updated_at };
}

describe("poller postavki", () => {
  it("bez ključa ne zove mrežu i bilježi disabled", async () => {
    const src = fakeSource({ settings: [settings(uc("dis1"), "2026-11-11T10:00:00.000001+00:00", ["ebook"])] });
    const r = await pollSettings(deps("t-disabled", src, { anonKey: undefined }));
    expect(r.status).toBe("disabled");
    expect(src.requests).toHaveLength(0);
    expect(await state("t-disabled")).toEqual({ cursor: null, status: "disabled" });
    expect(await stored(uc("dis1"))).toBeNull();
  });

  it("bez URL-a isto disabled", async () => {
    const src = fakeSource();
    const r = await pollSettings(deps("t-disabled-url", src, { apiUrl: "" }));
    expect(r.status).toBe("disabled");
    expect(src.requests).toHaveLength(0);
  });

  it("prvi poziv upiše postavke, tombstone i podigne verziju kataloga", async () => {
    const a = uc("first1");
    const d = uc("first2");
    const tomb: FakeTombstone = {
      youtube_channel_id: d,
      channel_title: "Obrisani kanal",
      slugs: ["obrisani_kanal"],
      requested_at: "2026-11-11T09:00:00.1+00:00",
      phone_confirmed_at: "2026-11-11T09:30:00+00:00",
      deleted_at: "2026-11-11T10:00:00.000002+00:00",
    };
    // `a` nema ključ `ebook` (nedostaje = true) i ima nepoznat ključ (čuva se).
    const rowA = settings(a, "2026-11-11T10:00:00.000001+00:00", ["home_featured"]);
    delete rowA.effective.ebook;
    rowA.effective.future_key = false;
    const src = fakeSource({
      settings: [rowA, settings(d, tomb.deleted_at, [...SETTING_KEYS], { tombstoned: true })],
      tombstones: [tomb],
    });
    const before = await catalogVersion();
    const r = await pollSettings(deps("t-first", src));
    expect(r).toMatchObject({ status: "ok", fetched: 2, settingsWritten: 2, effectiveChanged: 2, tombstonesInserted: 1 });
    expect(r.catalog).not.toBeNull();
    expect(await catalogVersion()).toBe(r.catalog);
    expect(r.catalog).toBeGreaterThan(before ?? 0);

    const sa = await stored(a);
    expect(sa?.effective.home_featured).toBe(false);
    expect(sa?.effective.ebook).toBe(true);
    expect(sa?.effective.future_key).toBe(false);
    expect(Object.keys(sa?.effective ?? {})).toHaveLength(SETTING_KEYS.length + 1);
    expect(sa?.source_updated_at).toBe("2026-11-11T10:00:00.000001+00:00");

    const t = await env.DB.prepare("SELECT channel_title, slugs, deleted_at FROM channel_tombstones WHERE youtube_channel_id = ?1")
      .bind(d)
      .first();
    expect(t).toEqual({ channel_title: "Obrisani kanal", slugs: '["obrisani_kanal"]', deleted_at: tomb.deleted_at });
    expect(await state("t-first")).toEqual({ cursor: tomb.deleted_at, status: "ok" });

    const run = await env.DB.prepare("SELECT source, counts FROM ingest_runs WHERE id = ?1").bind(r.catalog).first();
    expect(run).toEqual({ source: INGEST_SOURCE, counts: JSON.stringify({ settings: 2, effective_changed: 2, tombstones: 1 }) });

    // Zaglavlja: shema domovina_ai i anon ključ; prvi poziv bez kursora.
    const first = src.requests[0];
    expect(first?.headers.get("accept-profile")).toBe("domovina_ai");
    expect(first?.headers.get("apikey")).toBe(KEY);
    expect(first?.url.searchParams.get("updated_at")).toBeNull();
  });

  it("ponovni poziv bez promjene: ništa se ne piše, nema novog ingest_runs", async () => {
    const a = uc("same1");
    const src = fakeSource({ settings: [settings(a, "2026-11-11T10:00:00.5+00:00", ["ebook"])] });
    const first = await pollSettings(deps("t-same", src));
    expect(first.catalog).not.toBeNull();
    const version = await catalogVersion();
    // Isti redak, isti `updated_at` (kursor je `gte`, pa se redak ponovno pročita).
    const again = await pollSettings(deps("t-same", src));
    expect(again).toMatchObject({ status: "ok", fetched: 1, settingsWritten: 0, effectiveChanged: 0, catalog: null });
    expect(await catalogVersion()).toBe(version);
    expect(await state("t-same")).toEqual({ cursor: "2026-11-11T10:00:00.5+00:00", status: "ok" });
  });

  it("kursor ide naprijed, upit traži gte kursor − LOOKBACK, promjena diže verziju", async () => {
    const a = uc("adv1");
    const src = fakeSource({ settings: [settings(a, "2026-11-11T10:00:00+00:00", ["ebook"])] });
    await pollSettings(deps("t-adv", src));
    const v1 = await catalogVersion();

    src.settings = [settings(a, "2026-11-11T10:05:00.123456+00:00", ["ebook", "donations"])];
    const r = await pollSettings(deps("t-adv", src));
    expect(r).toMatchObject({ status: "ok", settingsWritten: 1, effectiveChanged: 1 });
    const since = src.requests.at(-1)?.url.searchParams.get("updated_at");
    expect(since).toBe(`gte.${new Date(Date.parse("2026-11-11T10:00:00Z") - LOOKBACK_MS).toISOString()}`);
    expect(r.catalog).toBeGreaterThan(v1 ?? 0);
    expect((await stored(a))?.effective.donations).toBe(false);
    expect((await state("t-adv"))?.cursor).toBe("2026-11-11T10:05:00.123456+00:00");
  });

  it("samo novi updated_at uz isto stanje: upiše se, verzija ostaje", async () => {
    const a = uc("ts1");
    const src = fakeSource({ settings: [settings(a, "2026-11-11T10:00:00+00:00", ["ebook"])] });
    await pollSettings(deps("t-ts", src));
    const v = await catalogVersion();
    src.settings = [settings(a, "2026-11-11T10:01:00+00:00", ["ebook"])];
    const r = await pollSettings(deps("t-ts", src));
    expect(r).toMatchObject({ settingsWritten: 1, effectiveChanged: 0, catalog: null });
    expect(await catalogVersion()).toBe(v);
    expect((await stored(a))?.source_updated_at).toBe("2026-11-11T10:01:00+00:00");
  });

  it("stariji redak od onoga u D1 se ne upisuje", async () => {
    const a = uc("old1");
    const src = fakeSource({ settings: [settings(a, "2026-11-11T10:10:00+00:00", ["ebook"])] });
    await pollSettings(deps("t-old", src));
    src.settings = [settings(a, "2026-11-11T10:09:00+00:00", [])];
    const r = await pollSettings(deps("t-old", src));
    expect(r.settingsWritten).toBe(0);
    expect((await stored(a))?.effective.ebook).toBe(false);
  });

  it("stranice s istim updated_at: keyset ne preskače ni ne ponavlja", async () => {
    const at = "2026-11-11T11:00:00.000007+00:00";
    const ids = ["pg1", "pg2", "pg3", "pg4", "pg5"].map(uc);
    const src = fakeSource({ settings: ids.map((id) => settings(id, at, ["magisterium"])) });
    const r = await pollSettings(deps("t-pages", src, { pageSize: 2 }));
    expect(r).toMatchObject({ status: "ok", fetched: 5, pages: 3, settingsWritten: 5 });
    for (const id of ids) expect((await stored(id))?.effective.magisterium).toBe(false);
    expect(src.requests[1]?.url.searchParams.get("or")).toBe(
      `(updated_at.gt."${at}",and(updated_at.eq."${at}",youtube_channel_id.gt.${ids[1] ?? ""}))`,
    );
  });

  it("tombstone se upiše jednom i nikad ne mijenja; trigger odbija UPDATE i DELETE", async () => {
    const d = uc("tomb1");
    const tomb: FakeTombstone = {
      youtube_channel_id: d,
      channel_title: "Prvo ime",
      slugs: ["prvo_ime"],
      requested_at: null,
      phone_confirmed_at: null,
      deleted_at: "2026-11-11T10:00:00+00:00",
    };
    const src = fakeSource({
      settings: [settings(d, tomb.deleted_at, [...SETTING_KEYS], { tombstoned: true })],
      tombstones: [tomb],
    });
    expect((await pollSettings(deps("t-tomb", src))).tombstonesInserted).toBe(1);

    // Izvor (hipotetski) promijeni ime: D1 ga već ima, pa se tombstone više ne traži.
    src.tombstones = [{ ...tomb, channel_title: "Drugo ime" }];
    const tombRequests = (): number => src.requests.filter((q) => q.url.pathname.endsWith("/public_channel_tombstones")).length;
    const before = tombRequests();
    const again = await pollSettings(deps("t-tomb", src));
    expect(again).toMatchObject({ status: "ok", tombstonesInserted: 0, catalog: null });
    expect(tombRequests()).toBe(before);
    const t = await env.DB.prepare("SELECT channel_title FROM channel_tombstones WHERE youtube_channel_id = ?1").bind(d).first();
    expect(t).toEqual({ channel_title: "Prvo ime" });

    await expect(
      env.DB.prepare("UPDATE channel_tombstones SET channel_title = 'x' WHERE youtube_channel_id = ?1").bind(d).run(),
    ).rejects.toThrow(/trajan/);
    await expect(env.DB.prepare("DELETE FROM channel_tombstones WHERE youtube_channel_id = ?1").bind(d).run()).rejects.toThrow(
      /trajan/,
    );
  });

  it("tombstoned bez retka tombstonea: invalid_response, ništa upisano", async () => {
    const d = uc("lost1");
    const src = fakeSource({ settings: [settings(d, "2026-11-11T10:00:00+00:00", [...SETTING_KEYS], { tombstoned: true })] });
    const r = await pollSettings(deps("t-lost", src));
    expect(r.status).toBe("invalid_response");
    expect(await stored(d)).toBeNull();
  });

  it("HTTP greška: kod u stanju, kursor ostaje, ništa upisano", async () => {
    const a = uc("http1");
    const src = fakeSource({ settings: [settings(a, "2026-11-11T10:00:00+00:00", ["ebook"])] });
    await pollSettings(deps("t-http", src));
    const v = await catalogVersion();

    src.settings = [settings(a, "2026-11-11T10:30:00+00:00", [])];
    src.failWith = 503;
    const r = await pollSettings(deps("t-http", src));
    expect(r.status).toBe("http_503");
    expect(await state("t-http")).toEqual({ cursor: "2026-11-11T10:00:00+00:00", status: "http_503" });
    expect((await stored(a))?.effective.ebook).toBe(false);
    expect(await catalogVersion()).toBe(v);

    // Oporavak: sljedeći poziv pokupi promjenu.
    delete src.failWith;
    const ok = await pollSettings(deps("t-http", src));
    expect(ok.status).toBe("ok");
    expect((await stored(a))?.effective.ebook).toBe(true);
  });

  it("mreža pada: status network", async () => {
    const r = await pollSettings(
      deps("t-net", fakeSource(), { fetch: () => Promise.reject(new TypeError("fetch failed")) }),
    );
    expect(r.status).toBe("network");
    expect((await state("t-net"))?.status).toBe("network");
  });

  it.each([
    ["vrijednost nije boolean", { effective: { ebook: "false" } }],
    ["effective nije objekt", { effective: [true] }],
    ["UC nije valjan", { youtube_channel_id: "kanal" }],
    ["updated_at nije vrijeme", { updated_at: "jučer" }],
  ])("strogo: %s → invalid_response, ništa upisano", async (_name, bad) => {
    const good = settings(uc("strict1"), "2026-11-11T10:00:00+00:00", ["ebook"]);
    const src = fakeSource({ settings: [good, { ...settings(uc("strict2"), "2026-11-11T10:00:01+00:00"), ...bad } as FakeSettings] });
    const r = await pollSettings(deps("t-strict", src));
    expect(r.status).toBe("invalid_response");
    expect(await stored(uc("strict1"))).toBeNull();
  });

  it("scheduled bez SETTINGS_ANON_KEY bilježi disabled u retku domovina-api", async () => {
    // `Cloudflare.Env` u testu ne deklarira `DEFAULT_BRAND` (var iz wrangler.jsonc), a
    // ovdje je u runtimeu; handler ga ionako ne čita.
    await worker.scheduled(createScheduledController({ cron: "* * * * *" }), env as unknown as Env);
    expect((await state(POLL_SOURCE))?.status).toBe("disabled");
  });
});
