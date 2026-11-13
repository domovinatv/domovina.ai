// Vlasnikove postavke kanala u API-ju v1 (lanac `postavke-kanala/`, S3, odluke
// 105, 107, 108, 200, 203). Svaki odgovor prolazi JSON Schemu u `api()`.
//
// Kanali, epizode, postavke i tombstonei su sintetički, s UC-ovima `UCs3set_*`:
// postavke nisu po brendu, pa fixture UC-ovi (koje koriste drugi testovi) ostaju
// netaknuti. Kanal bez retka postavki mora izgledati točno kao prije (tvrdi
// uvjet 4); to za fixturee čuvaju i postojeći testovi (`v1.test.ts`).
import { env, exports } from "cloudflare:workers";
import { beforeAll, describe, expect, it } from "vitest";
import { SETTING_KEYS } from "../../src/api/v1.ts";
import {
  allChannelSettings,
  allChannels,
  channelBySlug,
  channelDirectory,
  episodeCard,
  episodesOnDay,
  prepare,
  type SqlQuery,
} from "../../src/db/queries.ts";
import {
  api,
  type Card,
  type Channel,
  type ItemBody,
  type ListBody,
  measure,
  okRun,
  ROWS_READ_CONSTANT,
} from "./helpers.ts";

const BRAND = "s3-settings";
const HOST = `${BRAND}.test`;
const OTHER_HOST = "s3-settings-drugi.test";
const DAY = "2026-10-01";
const NOW = "2026-11-11T10:00:00.000Z";
const DELETED_AT = "2026-11-10T09:30:00.000Z";

const allOff = (): Record<string, boolean> => Object.fromEntries(SETTING_KEYS.map((k) => [k, false]));
const allOn = (): Record<string, boolean> => Object.fromEntries(SETTING_KEYS.map((k) => [k, true]));
const ALL_SORTED = [...SETTING_KEYS].sort();

interface Ch {
  readonly slug: string;
  readonly uc: string | null;
  readonly tier: 1 | 2;
  readonly score: number | null;
}

// Svaki kanal ima jednu epizodu `ep_<slug>` na DAY.
const CHANNELS: readonly Ch[] = [
  { slug: "aktivan", uc: "UCs3set_aktivan", tier: 1, score: 80 },
  { slug: "povucen", uc: "UCs3set_povucen", tier: 1, score: 70 },
  // Isti UC kao `povucen` (playlist slug): jedan redak postavki vrijedi za oba.
  { slug: "povucen_playlist", uc: "UCs3set_povucen", tier: 2, score: null },
  { slug: "povucen_min", uc: "UCs3set_povucen_min", tier: 2, score: null },
  { slug: "obrisan", uc: "UCs3set_obrisan", tier: 2, score: 60 },
  { slug: "bez_hera", uc: "UCs3set_bez_hera", tier: 1, score: 90 },
  { slug: "sve_ukljuceno", uc: "UCs3set_sve", tier: 2, score: 50 },
  { slug: "bez_uc", uc: null, tier: 2, score: 40 },
  { slug: "kasni", uc: "UCs3set_kasni", tier: 2, score: 30 },
];

/** Kanali koji ostaju u popisima i u danu (`bez_hera` je u popisima, ne u danu). */
const VISIBLE = ["aktivan", "bez_hera", "sve_ukljuceno", "bez_uc", "kasni"];

function setting(uc: string, effective: Record<string, unknown>): D1PreparedStatement {
  return env.DB.prepare(
    `INSERT INTO channel_settings (youtube_channel_id, effective, source_updated_at, synced_at)
     VALUES (?1, ?2, ?3, ?3)
     ON CONFLICT (youtube_channel_id) DO UPDATE SET effective = excluded.effective`,
  ).bind(uc, JSON.stringify(effective), NOW);
}

function tombstone(uc: string, title: string, slugs: string[]): D1PreparedStatement {
  return env.DB.prepare(
    `INSERT INTO channel_tombstones (youtube_channel_id, channel_title, slugs, requested_at,
       phone_confirmed_at, deleted_at, synced_at)
     VALUES (?1, ?2, ?3, ?4, ?4, ?5, ?6)`,
  ).bind(uc, title, JSON.stringify(slugs), "2026-11-09T08:00:00.000Z", DELETED_AT, NOW);
}

beforeAll(async () => {
  const stmts: D1PreparedStatement[] = [
    env.DB.prepare("INSERT INTO brands (id, host) VALUES (?1, ?2)").bind(BRAND, HOST),
    env.DB.prepare("INSERT INTO brands (id, host) VALUES (?1, ?2)").bind("s3-settings-drugi", OTHER_HOST),
  ];
  for (const c of CHANNELS) {
    stmts.push(
      env.DB.prepare(
        `INSERT INTO channels (brand, slug, youtube_channel_id, name, tier, lang, avatar,
           processed_count, latest_published_date)
         VALUES (?1, ?2, ?3, ?4, ?5, 'hr', ?6, 1, ?7)`,
      ).bind(BRAND, c.slug, c.uc, `Kanal ${c.slug}`, c.tier, `https://cdn.test/${c.slug}.jpg`, DAY),
      env.DB.prepare(
        `INSERT INTO episodes (brand, id, channel_slug, title, title_hr, published_date,
           duration_seconds, tier, lang, magisterium_score, flags, updated_at)
         VALUES (?1, ?2, ?3, ?4, NULL, ?5, 3600, ?6, 'hr', ?7, 15, ?8)`,
      ).bind(BRAND, `ep_${c.slug}`, c.slug, `Epizoda ${c.slug}`, DAY, c.tier, c.score, NOW),
    );
  }
  stmts.push(
    // Razriješen `effective` iz domovina-api: master off → sve off.
    setting("UCs3set_povucen", allOff()),
    // Minimalan zapis (samo master): stanje je i dalje „povučen”.
    setting("UCs3set_povucen_min", { channel_enabled: false }),
    // Tombstone pobjeđuje i kad je zadnji redak postavki „sve uključeno”.
    setting("UCs3set_obrisan", allOn()),
    tombstone("UCs3set_obrisan", "Obrisani kanal", ["obrisan"]),
    // Kanala više nema u katalogu; slug je samo u tombstoneu.
    tombstone("UCs3set_nestao", "Nestali kanal", ["nestao", "nestao-alias"]),
    setting("UCs3set_bez_hera", {
      ...allOn(),
      home_featured: false,
      magisterium: false,
      // Nepoznat ključ se ignorira (nije u ugovoru od 20 ključeva).
      buduci_kljuc: false,
    }),
    setting("UCs3set_sve", { ...allOn(), buduci_kljuc: false }),
  );
  await env.DB.batch(stmts);
  await okRun();
});

const card = (id: string) => api<ItemBody<Card & Record<string, unknown>>>(HOST, `episodes/${id}/card`, "card-response");
const channel = (slug: string) =>
  api<ItemBody<Channel & { settings?: Record<string, false> }> & { state?: string; deleted_at?: string }>(
    HOST,
    `channels/${slug}`,
    "channel-response",
  );
const channelEps = (slug: string) =>
  api<ListBody<Card> & { state?: string; deleted_at?: string }>(HOST, `channels/${slug}/episodes`, "channel-episodes");

describe("popisi: povučen i obrisan kanal izostaju", () => {
  it("/channels oba tiera, tier 1, tier 2 i /directory", async () => {
    const slugs = async (path: string, contract: "channels" | "directory") =>
      (await api<ListBody<Channel>>(HOST, path, contract)).body.items.map((c) => c.slug).sort();
    const tierOf = new Map(CHANNELS.map((c) => [c.slug, c.tier]));
    expect(await slugs("channels", "channels")).toEqual([...VISIBLE].sort());
    expect(await slugs("directory", "directory")).toEqual([...VISIBLE].sort());
    expect(await slugs("channels?tier=1", "channels")).toEqual(VISIBLE.filter((s) => tierOf.get(s) === 1).sort());
    expect(await slugs("channels?tier=2", "channels")).toEqual(VISIBLE.filter((s) => tierOf.get(s) === 2).sort());
  });

  it("/days: bez povučenih, obrisanih i `home_featured=false` epizoda", async () => {
    const { body } = await api<ListBody<Card>>(HOST, `days/${DAY}`, "days");
    expect(body.items.map((c) => c.id).sort()).toEqual(
      ["aktivan", "sve_ukljuceno", "bez_uc", "kasni"].map((s) => `ep_${s}`).sort(),
    );
    // Paginacija preko skrivenih redaka: unija stranica je isti skup, bez rupa.
    const first = await api<ListBody<Card>>(HOST, `days/${DAY}?limit=2`, "days");
    const second = await api<ListBody<Card>>(HOST, `days/${DAY}?limit=2&cursor=${first.body.next ?? ""}`, "days");
    expect([...first.body.items, ...second.body.items].map((c) => c.id)).toEqual(body.items.map((c) => c.id));
    expect(second.body.next).toBeNull();
  });

  it("`settings` u popisu: samo isključeni poznati ključevi; bez polja kad ih nema", async () => {
    const { body } = await api<ListBody<Channel & { settings?: unknown }>>(HOST, "channels", "channels");
    const bySlug = new Map(body.items.map((c) => [c.slug, c]));
    expect(bySlug.get("bez_hera")?.settings).toEqual({ home_featured: false, magisterium: false });
    for (const slug of ["aktivan", "sve_ukljuceno", "bez_uc", "kasni"]) {
      expect(bySlug.get(slug), slug).not.toHaveProperty("settings");
    }
  });
});

describe("GET /channels/:slug i epizode: stanje umjesto 404", () => {
  it("aktivan kanal bez postavki: odgovor kao prije (bez state, bez settings)", async () => {
    const { res, body } = await channel("aktivan");
    expect(res.status).toBe(200);
    expect(Object.keys(body).sort()).toEqual(["catalog", "item", "meta", "version"]);
    expect(body.item).toEqual({
      slug: "aktivan",
      name: "Kanal aktivan",
      tier: 1,
      lang: "hr",
      avatar: "https://cdn.test/aktivan.jpg",
      youtube_channel_id: "UCs3set_aktivan",
      processed_count: 1,
      latest_published_date: DAY,
      unregistered: false,
    });
    const eps = await channelEps("aktivan");
    expect(Object.keys(eps.body).sort()).toEqual(["catalog", "items", "meta", "next", "version"]);
    expect(eps.body.items.map((c) => c.id)).toEqual(["ep_aktivan"]);
  });

  it("povučen: 200, state withdrawn, item je cijeli kanal; epizode prazne", async () => {
    for (const slug of ["povucen", "povucen_playlist", "povucen_min"]) {
      const { res, body } = await channel(slug);
      expect(res.status, slug).toBe(200);
      expect(body.state, slug).toBe("withdrawn");
      expect(body, slug).not.toHaveProperty("deleted_at");
      expect(body.item.slug, slug).toBe(slug);
      expect(body.item.avatar, slug).toBe(`https://cdn.test/${slug}.jpg`);
      expect(body.item.settings?.channel_enabled, slug).toBe(false);
      const eps = await channelEps(slug);
      expect(eps.res.status, slug).toBe(200);
      expect(eps.body.state, slug).toBe("withdrawn");
      expect(eps.body.items, slug).toEqual([]);
      expect(eps.body.next, slug).toBeNull();
    }
    // `effective` se preslikava, ne nadopunjuje: minimalan zapis ima samo master.
    expect((await channel("povucen_min")).body.item.settings).toEqual({ channel_enabled: false });
    expect(Object.keys((await channel("povucen")).body.item.settings ?? {})).toEqual(ALL_SORTED);
  });

  it("obrisan (tombstone po UC-u): state deleted + deleted_at, item samo identitet", async () => {
    const { res, body } = await channel("obrisan");
    expect(res.status).toBe(200);
    expect(body.state).toBe("deleted");
    expect(body.deleted_at).toBe(DELETED_AT);
    expect(body.item).toEqual({
      slug: "obrisan",
      name: "Obrisani kanal",
      tier: 2,
      lang: "hr",
      avatar: null,
      youtube_channel_id: "UCs3set_obrisan",
      processed_count: 0,
      latest_published_date: null,
      unregistered: false,
    });
    const eps = await channelEps("obrisan");
    expect(eps.body).toMatchObject({ state: "deleted", deleted_at: DELETED_AT, items: [], next: null });
  });

  it("obrisan bez retka kanala: pogodak po slugu iz tombstonea (i drugom slugu)", async () => {
    for (const slug of ["nestao", "nestao-alias"]) {
      const { res, body } = await channel(slug);
      expect(res.status, slug).toBe(200);
      expect(body.state, slug).toBe("deleted");
      expect(body.deleted_at, slug).toBe(DELETED_AT);
      expect(body.item, slug).toMatchObject({
        slug,
        name: "Nestali kanal",
        tier: 2,
        avatar: null,
        youtube_channel_id: "UCs3set_nestao",
        processed_count: 0,
      });
      const eps = await channelEps(slug);
      expect(eps.res.status, slug).toBe(200);
      expect(eps.body).toMatchObject({ state: "deleted", items: [], next: null });
    }
  });

  it("nepoznat slug i dalje 404", async () => {
    const res = await exports.default.fetch(`https://${HOST}/api/katalog/v1/channels/nikad_nije_postojao`);
    expect(res.status).toBe(404);
    expect(await res.json()).toEqual({ ok: false, error: "channel_not_found" });
  });

  it("home_featured=false: kanal i epizode dostupni, settings rijetki, ocjena maskirana", async () => {
    const { body } = await channel("bez_hera");
    expect(body).not.toHaveProperty("state");
    expect(body.item.settings).toEqual({ home_featured: false, magisterium: false });
    const eps = await channelEps("bez_hera");
    expect(eps.body).not.toHaveProperty("state");
    expect(eps.body.items).toHaveLength(1);
    expect(eps.body.items[0]).toMatchObject({ id: "ep_bez_hera", magisterium_score: null, magisterium_off: true });
    expect(eps.body.items[0]).not.toHaveProperty("status");
  });
});

describe("GET /episodes/:id/card: status i maskirana ocjena", () => {
  it("aktivan kanal: kartica kao prije", async () => {
    const { body } = await card("ep_aktivan");
    expect(body.item).toEqual({
      id: "ep_aktivan",
      title: "Epizoda aktivan",
      title_hr: null,
      date: DAY,
      duration_seconds: 3600,
      magisterium_score: 80,
      p: 15,
      tier: 1,
      lang: "hr",
      variant_of: null,
      published_at: null,
      channel: { slug: "aktivan", name: "Kanal aktivan", tier: 1 },
    });
  });

  it("nepoznat ključ u effective se ignorira", async () => {
    const { body } = await card("ep_sve_ukljuceno");
    expect(body.item.magisterium_score).toBe(50);
    expect(body.item).not.toHaveProperty("magisterium_off");
    expect(body.item).not.toHaveProperty("status");
  });

  it("magisterium=false: score null, magisterium_off true, bez statusa", async () => {
    const { body } = await card("ep_bez_hera");
    expect(body.item).toMatchObject({ magisterium_score: null, magisterium_off: true });
    expect(body.item).not.toHaveProperty("status");
  });

  it("povučen i obrisan: 200 sa statusom (`/v/<id>` ne pada na 404)", async () => {
    const withdrawn = await card("ep_povucen");
    expect(withdrawn.res.status).toBe(200);
    expect(withdrawn.body.item).toMatchObject({
      id: "ep_povucen",
      status: "withdrawn",
      magisterium_score: null,
      magisterium_off: true,
    });
    // Minimalan zapis (samo master): kanal je povučen, procjena se ne pokazuje.
    expect((await card("ep_povucen_min")).body.item).toMatchObject({ status: "withdrawn", magisterium_off: true });
    const deleted = await card("ep_obrisan");
    expect(deleted.res.status).toBe(200);
    expect(deleted.body.item).toMatchObject({ status: "deleted", magisterium_score: null, magisterium_off: true });
  });

  it("epizoda bez UC-a kanala: kartica kao prije", async () => {
    const { body } = await card("ep_bez_uc");
    expect(body.item.magisterium_score).toBe(40);
    expect(body.item).not.toHaveProperty("status");
    expect(body.item).not.toHaveProperty("magisterium_off");
  });
});

interface SettingsBody {
  readonly version: string;
  readonly catalog: string | null;
  readonly settings: Record<string, { status: string; off: string[]; deleted_at?: string; slugs: string[] }>;
  readonly meta: { readonly rows_read: number };
}

describe("GET /settings", () => {
  it("oblik i filtar: samo UC-ovi s isključenim ključem ili tombstoneom", async () => {
    const { res, body } = await api<SettingsBody>(HOST, "settings", "settings");
    expect(res.status).toBe(200);
    expect(res.headers.get("cache-control")).toBe("public, max-age=60, stale-while-revalidate=600");
    expect(Object.keys(body).sort()).toEqual(["catalog", "meta", "settings", "version"]);
    const s = body.settings;
    // Više slugova po UC-u (kanal + playlista): oba, abecedno.
    expect(s.UCs3set_povucen).toEqual({ status: "withdrawn", off: ALL_SORTED, slugs: ["povucen", "povucen_playlist"] });
    expect(s.UCs3set_povucen_min).toEqual({ status: "withdrawn", off: ["channel_enabled"], slugs: ["povucen_min"] });
    expect(s.UCs3set_bez_hera).toEqual({ status: "active", off: ["home_featured", "magisterium"], slugs: ["bez_hera"] });
    // Tombstone: slug je i u tablici kanala i u tombstoneu, bez ponavljanja.
    expect(s.UCs3set_obrisan).toEqual({ status: "deleted", off: ALL_SORTED, deleted_at: DELETED_AT, slugs: ["obrisan"] });
    // Kanala više nema u katalogu: slugovi samo iz tombstonea.
    expect(s.UCs3set_nestao).toEqual({
      status: "deleted",
      off: ALL_SORTED,
      deleted_at: DELETED_AT,
      slugs: ["nestao", "nestao-alias"],
    });
    // Sve uključeno (i nepoznat ključ false) i kanal bez retka: nema ih.
    expect(s).not.toHaveProperty("UCs3set_sve");
    expect(s).not.toHaveProperty("UCs3set_aktivan");
    // UC-ovi abecedno (stabilno tijelo za cache i usporedbu).
    expect(Object.keys(s)).toEqual(Object.keys(s).sort());
  });

  it("nije po brendu: isti sadržaj na drugom brendu; rows_read = postavke + tombstonei + njihovi kanali", async () => {
    // R = retci postavki + tombstonei; M = retci kanala koje podupit `slugs`
    // nađe po retku (UC s retkom postavki i tombstoneom broji se dvaput).
    const counts = await env.DB.prepare(
      `SELECT (SELECT count(*) FROM channel_settings) + (SELECT count(*) FROM channel_tombstones) AS r,
         (SELECT count(*) FROM channels c JOIN
           (SELECT youtube_channel_id FROM channel_settings
            UNION ALL SELECT youtube_channel_id FROM channel_tombstones) u
           ON c.youtube_channel_id = u.youtube_channel_id) AS m`,
    ).first<{ r: number; m: number }>();
    const r = counts?.r ?? 0;
    const m = counts?.m ?? 0;
    const own = await api<SettingsBody>(HOST, "settings", "settings");
    // Drugi brend nema nijedan od ovih kanala; postavke su vlasnikove, po UC-u.
    const rows = await measure(OTHER_HOST, "settings", "settings");
    const other = await api<SettingsBody>(OTHER_HOST, "settings", "settings");
    expect(other.body.settings).toEqual(own.body.settings);
    // Upit brenda i verzije (≤ 3) + jedan sken obje tablice + po retku jedno
    // traženje u `channels_by_uc` (pogoci + jedno čitanje kraja raspona).
    // Izmjereno 13. 11. 2026.: r = 7, m = 7, rows = 21 = r + m + r.
    expect(rows).toBeLessThanOrEqual(r + m + r + 3);
    expect(rows).toBeGreaterThanOrEqual(r + m);
  });
});

describe("GET /settings: slugs", () => {
  it("slugovi preko brendova i iz tombstonea, spojeni i sortirani; bez N+1 (plan po channels_by_uc)", async () => {
    await env.DB.batch([
      // Isti UC pod drugim brendom i drugim slugom (crtica umjesto podvlake).
      env.DB.prepare(
        `INSERT INTO channels (brand, slug, youtube_channel_id, name, tier, lang, avatar,
           processed_count, latest_published_date)
         VALUES ('s3-settings-drugi', 'bez-hera', 'UCs3set_bez_hera', 'Kanal bez-hera', 2, 'hr', 'https://cdn.test/b.jpg', 1, ?1)`,
      ).bind(DAY),
      // Tombstone čiji su stari slugovi nestali iz kataloga, a novi je još tamo
      // (drugi brend, da popisi glavnog brenda i izmjereni rows_read ostanu isti).
      env.DB.prepare(
        `INSERT INTO channels (brand, slug, youtube_channel_id, name, tier, lang, avatar,
           processed_count, latest_published_date)
         VALUES ('s3-settings-drugi', 'z_nestao_novi', 'UCs3set_nestao', 'Nestali novi', 2, 'hr', 'https://cdn.test/n.jpg', 1, ?1)`,
      ).bind(DAY),
    ]);
    // Novi ok uvoz mijenja ključ cachea (kao u testu cachea niže).
    await okRun();
    const { body } = await api<SettingsBody>(OTHER_HOST, "settings", "settings");
    expect(body.settings.UCs3set_bez_hera?.slugs).toEqual(["bez-hera", "bez_hera"]);
    expect(body.settings.UCs3set_nestao?.slugs).toEqual(["nestao", "nestao-alias", "z_nestao_novi"]);
    for (const [uc, v] of Object.entries(body.settings)) {
      expect(v.slugs, uc).toEqual([...new Set(v.slugs)].sort());
    }
    const q = allChannelSettings();
    const plan = (await env.DB.prepare(`EXPLAIN QUERY PLAN ${q.sql}`).all<{ detail: string }>()).results
      .map((r) => r.detail)
      .join("\n");
    expect(plan).toMatch(/SEARCH c USING COVERING INDEX channels_by_uc \(youtube_channel_id=\?\)/);
    expect(plan).not.toMatch(/SCAN c\b/);
  });
});

describe("cache i rows_read", () => {
  it("promjena postavki se vidi tek s novim ok uvozom (poller ga dodaje), tada odmah", async () => {
    const before = await channel("kasni");
    expect(before.body.item).not.toHaveProperty("settings");
    await env.DB.batch([setting("UCs3set_kasni", { ...allOn(), magisterium: false })]);
    // Ista verzija kataloga: rubni cache vraća staro tijelo (nema invalidacije po retku).
    let hit: Response | undefined;
    for (let i = 0; i < 50 && hit === undefined; i++) {
      const res = await exports.default.fetch(`https://${HOST}/api/katalog/v1/channels/kasni`);
      if (res.headers.get("x-katalog-cache") === "hit") hit = res;
      else await res.arrayBuffer();
    }
    expect(hit).toBeDefined();
    expect(((await hit?.json()) as { item: unknown }).item).toEqual(before.body.item);
    await okRun();
    const after = await channel("kasni");
    expect(after.res.headers.get("x-katalog-cache")).toBe("miss");
    expect(after.body.item.settings).toEqual({ magisterium: false });
  });

  it("rows_read: skriveni retci se čitaju i odbacuju, svaki ≤ 5 čitanja", async () => {
    // Povučen/obrisan kanal (i `home_featured=false` u danu) filtrira se u SQL-u
    // nakon raspona indeksa, pa redak ispred stranice košta kao vidljiv: unos
    // indeksa, epizoda/kanal po PK, redak postavki i tombstone kad postoje.
    // Kanal bez retka postavki ne plaća ništa (LEFT JOIN promašaj = 0, isti
    // brojevi kao prije u `rows-read.test.ts`). U produkciji je skrivenih
    // kanala malo, pa granica 3 × limit + konstanta praktično vrijedi i dalje.
    const HIDDEN = 5;
    const limit = 1;
    const out: string[] = [];
    for (const [path, contract] of [
      [`days/${DAY}?limit=${limit}`, "days"],
      [`channels?limit=${limit}`, "channels"],
      [`channels?tier=2&limit=${limit}`, "channels"],
      [`directory?limit=${limit}`, "directory"],
      [`channels/povucen/episodes?limit=${limit}`, "channel-episodes"],
    ] as const) {
      const n = await measure(HOST, path, contract);
      out.push(`${path}: ${n}`);
      expect(n, path).toBeLessThanOrEqual(ROWS_READ_CONSTANT + 5 * (limit + 1 + HIDDEN));
    }
    // Izmjereno 11. 11. 2026. nad ovim podacima (nakon testa cachea `kasni` ima
    // redak postavki): promjena obračuna u D1 ili plana mora se vidjeti.
    expect(out).toEqual([
      `days/${DAY}?limit=1: 21`,
      "channels?limit=1: 15",
      "channels?tier=2&limit=1: 13",
      "directory?limit=1: 15",
      "channels/povucen/episodes?limit=1: 8",
    ]);
  });

  it("plan: postavke i tombstone po PK u LEFT JOIN-u, bez SCAN i TEMP B-TREE", async () => {
    const plan = async (q: SqlQuery) =>
      (await env.DB.prepare(`EXPLAIN QUERY PLAN ${q.sql}`).bind(...q.params).all<{ detail: string }>()).results
        .map((r) => r.detail)
        .join("\n");
    const queries = [
      episodesOnDay(BRAND, DAY, 10),
      episodesOnDay(BRAND, DAY, 10, "ep_x"),
      episodeCard(BRAND, "ep_aktivan"),
      allChannels(BRAND, 10),
      channelDirectory(BRAND, 1, 10),
      channelBySlug(BRAND, "aktivan"),
    ];
    for (const q of queries) {
      const text = await plan(q);
      expect(text).toMatch(/^SEARCH s USING PRIMARY KEY \(youtube_channel_id=\?\) LEFT-JOIN$/m);
      expect(text).toMatch(/^SEARCH t USING PRIMARY KEY \(youtube_channel_id=\?\) LEFT-JOIN$/m);
      expect(text).not.toMatch(/\bSCAN\b/);
      expect(text).not.toMatch(/TEMP B-TREE/);
    }
    // Kanal bez retka postavki ne troši čitanje (LEFT JOIN promašaj = 0 redaka).
    const { meta } = await prepare(env.DB, channelBySlug(BRAND, "aktivan")).all();
    expect(meta.rows_read).toBe(1);
  });
});
