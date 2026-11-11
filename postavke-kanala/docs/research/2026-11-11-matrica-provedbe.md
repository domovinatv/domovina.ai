# Matrica provedbe — 20 prekidača kanala (S1, 2026-11-11)

## Zaključak

1. **Aplikacija danas NE čita katalog za naslovnicu, popis kanala ni pretragu.**
   `ChannelCache` vuče `channels/data/index.json`, per-kanal listinge, `home.json` i
   `search.json` s CDN-a (`lib/services/cdn_config.dart` r. 52-61), a sve to generira fetch
   pipeline u KORAKU 13 (`fetch.domovina.tv/generate_channel_index.js`). Katalog API
   koristi samo `/dani`, `/channels` filtar „Svi”, `/c/` bez listinga i karticu epizode
   (`lib/services/catalog_client.dart`). Arhitektura iz plana („K → APP”) zato ne pokriva
   `channel_enabled`, `home_featured` ni `in_app_search` bez **novog** kompaktnog
   endpointa stanja u katalogu (prijedlog: `GET /v1/settings` → `{UC: {status, off:[ključevi]}}`,
   samo kanali s barem jednim isključenim ključem). To mijenja opseg S3 i S5.
2. **Katalog nema poller ni cron.** `katalog/wrangler.jsonc` nema `triggers`; jedini
   raspored je drift-check u 08:45 (`katalog/launchd/ai.domovina.katalog-drift.plist`), a
   ingest je push iz pipelinea (KORAK 13.5). Poller domovina-api → D1 je nov posao u S3.
   Uz `CACHE_LIST = max-age=60, stale-while-revalidate=600` (`katalog/src/api/v1.ts:52`)
   najgori zastoj na rubu je ~11 min nakon što poller upiše.
3. **Pozadinski potrošači imaju vrlo različite cikluse:** push 10 min (cron), pipeline 90 s
   (priority) do 24 h (nightly 03:00), Magisterium 10 min / EN 2 min, reels render 30 min,
   RAG + oba Meili indeksa jednom dnevno u 04:00, OG HTML na rubu 1 h, sitemap 1 h + Google.
   „Isključeno” za postojeće epizode zato mora ići kroz **čitače** (app, worker, MCP API),
   a ne kroz regeneraciju indeksa, inače kasni do 24 h.
4. **Nepredviđeni potrošači** (detalj u §A): `domovina-cutter` (isječci po poglavlju),
   `og:video` u workeru (CDN `video.mp4`), `home.json`/`search.json`/`index.json` iz
   pipelinea, Cast receiver, TV ekrani (5 ekrana + 2 widgeta), Vertex AI RAG import (KORAK 11),
   ručni `share_to_whatsapp.js`, glasački bazen (`sync_voting_candidates.mjs`),
   `/yt/:videoId` gumb na obrađenu epizodu, Magisterium ocjena na karticama i u
   sortiranju naslovnice (21 datoteka u `screens/` + `widgets/`).
5. **Ovisnosti među AI ključevima nisu u odluci 1:** članak je ulaz za e-knjigu, OG po
   trenutku, isječke (cutter reže po `iteration_number` iz `article.json`), Magisterium,
   prijevod i vijesti; transkript je ulaz za sve AI korake. Treba odluka (§C, pitanja 1–2).

Konvencije: `lib/…` = `packages/podcast_core/lib/…` (tako ga prihvaća
`scripts/verify-doc-refs.sh`). Putanje u drugim repoima pišu se `repo: putanja` i
provjerene su grepom 11. 11. 2026. (naredbe na dnu). „Postojeće” = epizoda već obrađena
prije isključivanja; „nove” = epizoda koja tek ulazi u pipeline.

Predloženi izvori stanja (stupac 5) koriste tri oznake:

- **K** = katalog D1, novi `GET /v1/settings` (+ `status` na postojećem `/channels/:slug`);
  worker preko bindinga `KATALOG` (već postoji, `fetchCatalogChannel` u `web/_worker.js` r. 1965).
- **A** = izravno u domovina-api Postgresu (ista baza kao `channel_settings`, nula kašnjenja).
- **K-batch** = isto što K, ali ga čita skripta izvan Cloudflarea (pipeline, RAG, vijesti)
  jednim GET-om na početku runa.

---

## Matrica (redoslijed iz odluke 1)

<!-- matrica-start -->

### 1. `channel_enabled` (glavni)

- **Potrošači:** svi ostali redci, plus površine kanala kao cjeline:
  - app: `lib/services/channel_cache.dart` (`loadIndex`, `allVideos`, bazen naslovnice),
    `lib/screens/channels/all_channels_screen.dart`, `lib/screens/channels/catalog_directory_view.dart`,
    `lib/screens/channel/channel_screen.dart`, `lib/screens/channel/catalog_channel_body.dart`,
    `lib/screens/episode_screen.dart` (`_EpisodeScreenState` r. 111, `_QueuedEpisodeScreen` r. 239),
    `lib/screens/episode_simple_screen.dart`, `lib/screens/youtube_watch/youtube_watch_screen.dart`
    (gumb na obrađenu epizodu), `lib/screens/favorites/favorites_resolver.dart`,
    TV: `lib/screens/tv/tv_home_screen.dart`, `lib/screens/tv/tv_channel_screen.dart`,
    `lib/screens/tv/tv_episode_screen.dart`, `lib/screens/tv/tv_episode_reader_screen.dart`;
  - worker: `web/_worker.js` rute `/v/` `/m/` (r. 441-444), `/c/` (r. 572-575), sitemap
    `buildSitemap` (r. 804) i `channelEpisodeFragment` (r. 894), `injectChannelTags` (r. 1609),
    `injectCatalogChannelTags` (r. 2002);
  - katalog: `katalog/src/api/v1.ts` `matchRoute` (r. 111: `channels`, `directory`, `days`,
    `channel`, `channelEpisodes`, `card`), upiti u `katalog/src/db/queries.ts`
    (`latestEpisodes`, `episodesOnDay`, `channelEpisodes`, `episodeCard`, `channelDirectory`,
    `allChannels`, `channelBySlug`);
  - pipeline: `fetch.domovina.tv: generate_channel_index.js` (`index.json`, `home.json`,
    `search.json`), `automatic/enqueue_all_new.js`, `run_pipeline.sh`;
  - ostali repoi: vidi retke 3–20 (push, RAG, Meili, vijesti, cutter, domovina-api).
- **Nove epizode:** pipeline ih ne otkriva ni ne obrađuje (`processing` implicitno off);
  ništa se ne uploada, nema ingesta u katalog, nema pusha.
- **Postojeće:** kanal izostaje iz `/channels`, naslovnice, pretrage, `/dani`, osoba, TV-a;
  `/c/<slug>` i `/v/<id>` NISU 404 nego prikaz „vlasnik je povukao sadržaj” + poveznica na
  YouTube (tvrdi uvjet 3 plana); OG isto, uz `noindex`; obrisan kanal kaže datum brisanja.
  Favoriti i „Nastavi slušati” korisnika: kartica prelazi u isti povučen prikaz (otvoreno §C-6).
- **Izvor:** app i worker **K** (`/v1/settings` + `status` na `/channels/:slug` i
  `/episodes/:id/card`); pipeline **K-batch** (isti odgovor nosi tombstone, pa je jedan izvor
  za odluku 6); domovina-api **A**.
- **Latencija:** poller (S3, nov; prijedlog cron 1 min) + `CACHE_LIST` 60 s / SWR 600 s →
  app ≤ ~12 min, worker OG `s-maxage=3600` (`web/_worker.js` r. 517) → ≤ 1 h bez purgea; sitemap
  `__cache/sitemap.xml` 1 h. Mjeri S3 (`katalog/scripts/latency.ts` već postoji kao uzor).
- **Sesija:** S3 (projekcija, `withdrawn`/`deleted`), S5 (svi ekrani + TV), S6 (OG, sitemap,
  noindex), S7 (otkrivanje, `index.json`), S8 (push, RAG, Meili, vijesti).

### 2. `processing`

- **Potrošači:** `fetch.domovina.tv: run_pipeline.sh` (KORAK 1/10 r. 753 `fetch.js`,
  KORAK 1b r. 790/801 `ingest_beamly.mjs`/`ingest_rss.mjs`), `automatic/enqueue_all_new.js`
  (već ima ogradu `tracking.process === false`, r. 104-111), `automatic/priority_pipeline.sh`,
  `automatic/nightly_pipeline.sh`, `automatic/watch_candidates.js`, `data/podcasts_registry.json`.
  U appu nema potrošača (ne skriva ništa postojeće).
- **Nove epizode:** ne preuzimaju se i ne obrađuju; ad-hoc (`priority`) zahtjev za epizodu
  tog kanala odbija se s porukom u logu.
- **Postojeće:** ništa se ne sakriva (namjerno: `processing` je samo za buduće). Postojeće
  ostaju vidljive dok ih ne sakrije `channel_enabled` ili AI ključ.
- **Izvor:** **K-batch** na početku svakog runa (nightly, priority). Postojeća ograda
  `tracking.process` u registryju je ručna i ostaje; settings je drugi, vlasnikov uvjet.
- **Latencija:** sljedeći run: priority 90 s (`automatic/launchd/tv.domovina.fetch.priority.plist`),
  nightly u 03:00 (`tv.domovina.fetch.nightly.plist`). Run koji je već krenuo dovrši započetu
  epizodu (otvoreno §C-4).
- **Sesija:** S7.

### 3. `home_featured`

- **Potrošači:**
  - app: `lib/screens/home/home_feed.dart` (`pickFeatured` r. 140, `pickFeaturedCarousel`
    r. 191, `latestEpisodes` r. 407, `featuredShows` r. 425, `freshlyArrived` r. 465),
    `lib/screens/home/home_screen.dart` (`HeroCarousel` r. 538, `EpisodesRail` r. 562/604/632/668,
    `CatalogDayRail` r. 704), `lib/screens/home/hero_carousel.dart`,
    `lib/screens/home/catalog_day_rail.dart`, `lib/screens/home/variants/variant_widgets.dart`
    (A/B/C naslovnica), `lib/screens/catalog_day/catalog_day_screen.dart` (`/dani/:datum`),
    `lib/services/channel_cache.dart` (bazen iz `home.json`, r. 92-118),
    TV: `lib/screens/tv/tv_home_screen.dart` (`pickFeatured` r. 148/320, `latestEpisodes` r. 322);
  - katalog: `/days/:date` (`episodesOnDay`), `/channels` (popis po tieru);
  - pipeline: `fetch.domovina.tv: generate_channel_index.js` `buildHomeEpisodes` (r. 189) →
    `channels/data/home.json`;
  - worker: `/dani/:datum` OG (`injectDayTags` r. 2066) nabraja epizode dana.
- **Nove:** ne ulaze u `home.json` ni u `/days`; push nije pod ovim ključem.
- **Postojeće:** izostaju iz hera, „Upravo stiglo”, ostalih railova, „Danas u korpusu”,
  `/dani/`, TV hera i railova. Ostaju na `/c/<slug>`, u pretrazi i u korisnikovim
  favoritima / „Nastavi slušati” / „Pratim” (`FollowedRail`) jer je to korisnikov izbor
  (otvoreno §C-6). Kanal ostaje u `/channels`.
- **Izvor:** app **K** (filter u `HomeFeed` nad `/v1/settings` mapom, jer `home.json` dolazi s
  CDN-a); katalog filtrira `/days` u SQL-u nad projekcijom; pipeline **K-batch** u KORAKU 13
  kao druga linija.
- **Latencija:** app ≤ ~12 min (vidi redak 1); `home.json` tek na sljedećem KORAKU 13.
- **Sesija:** S3 (`/days`), S5 (`HomeFeed`, TV), S7 (`home.json`).

### 4. `in_app_search`

- **Potrošači:**
  - app: `lib/services/unified_search.dart` (`isHiddenChannel` r. 173 — već postoji filtar
    po slugu, `mergeSearchResults` r. 232), `lib/screens/home/search_overlay.dart` (lokalni,
    Meili, semantika r. 141-147), `lib/screens/search/meili_search_screen.dart`,
    `lib/services/meili_client.dart`, `lib/services/search_service.dart`, lokalni sloj
    `lib/services/channel_cache.dart` (`search.json`, r. 149-171);
  - Meili indeks `episodes`: `domovina-rag: scripts/meili-poc-index.py` (puni ga
    `domovina-rag: scripts/sync-meili.sh` iz `domovina-rag: scripts/sync-cron.sh`, r. 171/173);
  - semantika: `domovina-rag: services/mcp/src/public-api.ts` `/api/search` (r. 210);
  - pipeline: `fetch.domovina.tv: generate_channel_index.js` `buildSearchEpisodes` (r. 217).
- **Nove:** ne ulaze u `search.json`, Meili `episodes` ni semantički indeks za pretragu.
- **Postojeće:** paleta ih ne prikazuje ni iz jednog od tri izvora; filtar je u
  `mergeSearchResults` (jedno mjesto za sva tri izvora), proširenjem `isHiddenChannel` s
  mapom stanja.
- **Izvor:** app **K**; Meili/RAG **K-batch** pri dnevnom syncu (druga linija).
- **Latencija:** klijentski filtar ≤ ~12 min; Meili/RAG reindeks do 24 h (04:00,
  `domovina-rag: infra/launchd/tv.domovina.rag.sync.plist`).
- **Sesija:** S5 (klijentski filtar), S8 (Meili, semantika), S7 (`search.json`).

### 5. `search_engines`

- **Potrošači:** `web/_worker.js` `buildSitemap` (r. 804) i `channelEpisodeFragment`
  (r. 894, čita per-kanal listing s CDN-a), `noindex()` (r. 1886), `sitemapDayUrls` (r. 1892),
  `injectEpisodeTags` (r. 1087), `injectChannelTags` (r. 1609), `injectPersonTags` (r. 1291),
  `jsonLdVideoObject` (r. 2145); `web/robots.txt`; portal vijesti
  `vijesti/portal/src/lib/seo.test.ts` (SEO portala, članci izvedeni iz epizoda). Flutter
  `lib/services/page_meta_web.dart` nema `robots` meta (grep), pa app nije potrošač.
- **Nove:** ne ulaze u sitemap; `/v/<id>` i `/c/<slug>` dobivaju `X-Robots-Tag: noindex`.
- **Postojeće:** isto, uz izbacivanje iz per-kanal fragmenta sitemapa; `/p/` profil osobe
  ostaje indeksiran (nije sadržaj kanala), ali JSON-LD ne nabraja epizode tog kanala.
- **Izvor:** worker **K** (binding `KATALOG`, jedan upit po buildu sitemapa i po OG
  zahtjevu; odgovor se cacheira uz sitemap).
- **Latencija:** OG HTML `s-maxage=3600` → ≤ 1 h (ili purge obje `Vary: Origin` varijante);
  sitemap 1 h (`sitemapCacheUrl`, r. 740) + vrijeme ponovnog crawla tražilice (dani, izvan
  naše kontrole). Mjeri S6 `curl -sI` na `X-Robots-Tag`.
- **Sesija:** S6.

### 6. `push_notifications`

- **Potrošači:** `domovina-push: src/index.ts` (čita `channels/data/index.json` s R2, r. 48;
  `scheduled` r. 106), `domovina-push: src/select.ts` (`candidatesFromListing` r. 52,
  `channelTopic` r. 33); app: `lib/services/push_topics.dart`, `lib/widgets/follow_button.dart`
  (`FollowButton` r. 22), `lib/screens/notifications/notifications_screen.dart`,
  `lib/screens/account/account_screen.dart`.
- **Nove:** cron ih ne šalje (ni na temu `all`, ni na temu kanala).
- **Postojeće:** nema „postojećih” obavijesti za povući; u appu `FollowButton` ne nudi
  zvonce za taj kanal (pretplata na temu ostaje u FCM-u, bez poruka).
- **Izvor:** **K** preko service bindinga ili HTTP-a (push je Cloudflare Worker, isti račun).
- **Latencija:** cron `*/10 * * * *` (`domovina-push: wrangler.jsonc` r. 12) → ≤ 10 min +
  katalog. Napomena: `DRY_RUN: "1"` (r. 25) — push u produkciji još ne šalje.
- **Sesija:** S8 (Worker), S5 (`FollowButton`).

### 7. `cdn_playback`

- **Potrošači:**
  - app: `lib/services/data_service.dart` `resolveMedia` (r. 581) i `EpisodeData.load`
    (r. 880) / `loadWithProgress` (r. 937), `lib/models/episode_status.dart`
    (`needsExternalSource` r. 210), `lib/services/episode_playback_session.dart`,
    `lib/widgets/episode_video.dart` (`EpisodeVideo` r. 64), `lib/widgets/video_panel.dart`,
    `lib/screens/episode_simple_screen.dart` (`_PlayerTab` r. 1061, `InAppYouTubePlayer`
    r. 1183), `lib/screens/episode_screen.dart` (`InAppYouTubePlayer` r. 328/474/3619,
    uvjet r. 3541), `lib/widgets/youtube_embed.dart` (`InAppYouTubePlayer` r. 100),
    `lib/services/cast_receiver.dart`, `lib/services/background_audio.dart`,
    TV `lib/screens/tv/tv_episode_screen.dart` (r. 141);
  - worker: `og:video` na CDN `video.mp4` (`web/_worker.js` r. 1195-1229), Cast receiver
    `handleCastReceiver` (r. 322) + `web/cast-receiver.html`;
  - pipeline: KORAK 12 (r. 1908, `upload_to_r2.js`), 12.5 H.264/fmp4 (r. 1982), 12.6
    `upload_audio_only.js` (r. 2023), KORAK 1 preuzimanje medija;
  - `domovina-cutter: src/index.ts` reže iz CDN medija (vidi `share_clips`).
- **Nove:** medij se može preuzeti za AI obradu, ali se NE uploada na R2 kao javni
  `video_h264*.mp4`/`audio.mp3` (otvoreno §C-3: smije li se uopće preuzeti).
- **Postojeće:** `resolveMedia` vraća „nema medije” → `needsExternalSource` = true →
  službeni YouTube embed (već postojeći put); worker izostavlja `og:video` i `contentUrl`;
  Cast i TV padaju na YouTube ili poruku; isječci i reels renderi nestaju (ovise o mediju).
- **Izvor:** app **K** (provjera prije `resolveMedia`, jedno mjesto u `DataService`);
  worker **K**; pipeline **K-batch**.
- **Latencija:** app ≤ ~12 min; već pokrenuta reprodukcija se ne prekida (otvoreno §C-5);
  worker ≤ 1 h.
- **Sesija:** S5, S6, S7. Cutter: izvan plana (§A).

### 8. `share_clips`

- **Potrošači:**
  - app: `lib/services/clip_service.dart` (`ClipService`, host `endpoints.cutter`),
    `lib/widgets/clip_share_sheet.dart` (`ClipShareButton` r. 13, `showClipShareSheet` r. 50),
    `lib/widgets/chapters_section.dart` (`ChaptersSection` r. 7), `lib/widgets/article_section.dart`,
    `lib/widgets/parallel_article_view.dart`, `lib/widgets/reel_share_sheet.dart`
    (`showReelShareSheet` r. 24, 9:16 i 16:9);
  - `domovina-cutter: src/index.ts` + `service/server.js` (reže poglavlje iz CDN medija na
    zahtjev, sprema na R2 `clips/…`);
  - pipeline: KORAK 9.6 `generate_og_sections.py` (r. 1704, `og-t-<sec>.jpg` +
    `og-sections.json`), `render_reels.js` / `render_reel_premium.js` (launchd
    `tv.domovina.fetch.reels.plist`, 1800 s, `automatic/reels_render.sh`),
    ručno `share_to_whatsapp.js` (šalje `/v/<id>/t/<sec>` po poglavlju);
  - worker: `og-sections.json` + `sections_en` (`web/_worker.js` r. 490-498) za `/v/<id>/t/<sec>`.
- **Nove:** nema `og-t-*.jpg`, `og-sections.json`, 9:16 rendera; cutter odbija rezanje.
- **Postojeće:** nestaju gumbi „Podijeli isječak” (poglavlja) i dijeljenje reela kao videa;
  `/v/<id>/t/<sec>` i dalje radi kao link (to je dijeljenje trenutka, ne isječka), ali OG
  pada na opću sliku epizode (`og-share`, KORAK 9.5, nije isječak). Datoteke ostaju na R2
  (odluka 8); cutter za taj kanal vraća 403/410 umjesto 302 na CDN.
- **Izvor:** app **K**; worker **K**; cutter **K** (Cloudflare Worker, binding ili HTTP);
  pipeline **K-batch**.
- **Latencija:** app ≤ ~12 min; worker ≤ 1 h; cutter: već izrezan isječak je na CDN-u
  `immutable` i dostupan svakome tko ima izravan `cdn.domovina.ai/clips/…` URL dok se ne
  obriše (odluka 8 to dopušta).
- **Sesija:** S5, S6, S7; cutter nema sesiju (§A).

### 9. `ebook`

- **Potrošači:** `lib/services/ebook_service.dart` (`EbookService.probe` r. 68), `lib/widgets/ebook_sheet.dart`
  (`EbookAction` r. 27, `EbookCard` r. 62, `showEbookSheet` r. 167), `lib/screens/episode_screen.dart`
  (probe r. 905, `EbookAction` r. 2716, `EbookCard` r. 2809/2942), `lib/screens/episode_simple_screen.dart`
  (`EbookAction` r. 808, `EbookCard` r. 1647); pipeline KORAK 9.8 `generate_ebook.js`
  (r. 1736), KORAK 12.66 `tools/force_upload_epubs.js` (r. 2082).
- **Nove:** nema `book.epub` ni `book.en.epub`.
- **Postojeće:** nema kartice, ikone ni sheeta; jedno mjesto: `EbookService.probe` vraća
  „nema” (bez HEAD-a) kad je ključ isključen.
- **Izvor:** app **K**; pipeline **K-batch**.
- **Latencija:** app ≤ ~12 min; pipeline sljedeći run.
- **Sesija:** S5, S7.

### 10. `article_summary`

- **Potrošači:**
  - app: `lib/services/data_service.dart` (`loadSummary` r. 320, `loadOutline` r. 347,
    `loadArticle` r. 360, `EpisodeData.load` r. 880), `lib/models/episode_bundle.dart`,
    `lib/widgets/article_section.dart`, `lib/widgets/parallel_article_view.dart`,
    `lib/widgets/chapters_section.dart`, `lib/widgets/entities_section.dart` (`EntitiesSection` r. 9),
    `lib/screens/episode_screen.dart` (`ArticleSection` r. 2829, `ParallelArticleView` r. 2993,
    `ChaptersSection` r. 2820/2958), `lib/screens/episode_simple_screen.dart` (`_ChaptersTab`
    r. 1464, `_InfoTab` r. 1612), `lib/screens/youtube_watch/youtube_watch_screen.dart`,
    `lib/screens/person/person_screen.dart`, TV `lib/screens/tv/tv_episode_reader_screen.dart`
    (r. 99-107) i `lib/screens/tv/tv_episode_screen.dart` (`_buildAbstract` r. 983);
    kartice s „ima poglavlja” (`HomeFeed.hasChapters` r. 109, `completeness` r. 118);
  - worker: `injectEpisodeTags` (opis iz `summary.json`, naslov sekcije iz `article.json`,
    `web/_worker.js` r. 471-490, `pickDescription` r. 956);
  - pipeline: KORAK 7 `summarize_gemini.js` (r. 1473), KORAK 8 `generate_article_gemini.js`
    (r. 1507), `generate_channel_index.js` (`search.json` nosi sažetak/teme);
  - Meili `episodes` (sekcije članka, `domovina-rag: scripts/meili-poc-index.py`);
  - vijesti: `vijesti/engine/cdn/loader.ts` (r. 274-275 `summary.json`, `article.json`);
  - cutter: poglavlja su `iteration_number` iz `article.json` (`lib/services/clip_service.dart`).
- **Nove:** ne generira se ni sažetak ni članak (osim ako je potreban kao ulaz za drugi
  uključen ključ — §C-1).
- **Postojeće:** ekran epizode prikazuje stanje bez AI teksta (naslov i opis s YouTubea,
  player); nema poglavlja, entiteta, članka u oba prikaza i na TV-u; OG opis iz `info.json`
  (YouTube opis). Ostali AI ključevi koji ovise o članku (ebook, Magisterium, prijevod,
  isječci, vijesti) u UI-u efektivno nestaju.
- **Izvor:** app **K** (provjera u `EpisodeData.load`, prije dohvata, ne poslije);
  worker **K**; pipeline **K-batch**.
- **Latencija:** app ≤ ~12 min; worker ≤ 1 h; Meili do 24 h; `search.json` sljedeći KORAK 13.
- **Sesija:** S5, S6, S7, S8.

### 11. `transcript_subtitles`

- **Potrošači:**
  - app: `lib/services/data_service.dart` (`loadSpeakerTimeline` r. 637, `diarized.srt` +
    `words.json`), `lib/models/speaker_timeline.dart`, `lib/widgets/subtitle_caption.dart`
    (`CaptionClock` r. 50, `SubtitleStrip` r. 296), `lib/widgets/episode_video.dart` (r. 807),
    `lib/screens/episode_simple_screen.dart` (`SubtitleStrip` r. 1244), `lib/services/subtitle_prefs.dart`,
    `lib/widgets/find_in_episode_section.dart` (`FindInEpisodeSection` r. 16),
    `lib/services/transcript_search.dart` (`TranscriptSearch.search` r. 30),
    `lib/screens/episode_screen.dart` (`_findInEpisodeSection` r. 2550, r. 3635);
  - Meili indeks `segments`: `domovina-rag: scripts/meili-segments-index.py`
    (`domovina-rag: scripts/sync-meili-segments.sh`, `domovina-rag: scripts/sync-cron.sh` r. 184/189);
  - MCP alat `find_in_transcript`: `domovina-rag: services/mcp/src/tools/find-in-transcript.ts`;
  - pipeline: KORACI 2.6-6 (ASR, diarizacija), KORAK 9.87 `generate_words_json.js` (r. 1810),
    KORAK 12.8 `automatic/fetch_youtube_subs.js` (r. 2126, ručni YouTube titlovi);
  - vijesti: `vijesti/engine/cdn/loader.ts` (r. 286, `srt`, `words`).
- **Nove:** ne objavljuju se `diarized.srt`, `words.json`, segmenti u Meiliju; transkripcija
  kao interni ulaz za druge AI ključeve — §C-1.
- **Postojeće:** nema titla (overlay, `SubtitleStrip`, fullscreen), nema „Pronađi u epizodi”,
  MCP `find_in_transcript` ne vraća pogotke za kanal.
- **Izvor:** app **K**; MCP i Meili **K-batch**/**K**; pipeline **K-batch**.
- **Latencija:** app ≤ ~12 min; Meili `segments` do 24 h (filtar u klijentu ga pokriva odmah:
  `TranscriptSearch` se zove samo s ekrana epizode koji već zna stanje).
- **Sesija:** S5, S7, S8.

### 12. `english_translation`

- **Potrošači:**
  - app: `lib/services/data_service.dart` (`loadSummaryEn` r. 334, `loadArticleEn` r. 373,
    `loadMagisteriumEn` r. 397, `loadMagisteriumBatchEn` r. 419), `lib/services/episode_language.dart`,
    `lib/widgets/language_toggle_chip.dart` (`LanguageToggleChip` r. 18; pozivi
    `lib/screens/episode_screen.dart` r. 2709/2798/2929, `lib/screens/episode_simple_screen.dart` r. 801),
    `lib/services/share_language.dart` (`shareLanguageForVideo`), `lib/services/share_links.dart`,
    `lib/router/app_router.dart` (rute `/v/:videoId/en` r. 340, `/t/:seconds/en` r. 396,
    `/m/…/en` r. 433/463), `lib/models/episode_reels.dart` (`forLanguage`, `reels.en.json`),
    `lib/services/ebook_service.dart` (`book.en.epub`);
  - worker: `/en` matcheri (`web/_worker.js` r. 441-444), `hreflang` (r. 1177-1188), `summary.en.json` /
    `article.en.json` (r. 480-481), `sections_en` (r. 498);
  - pipeline: `fetch.domovina.tv: translate_to_english.js` preko `automatic/enqueue_en_new.js`
    i `automatic/magisterium_pipeline.sh` (launchd `tv.domovina.fetch.magisterium-en.plist`, 120 s);
    `generate_og_sections.py` (`og-t-<sec>-en.jpg`).
- **Nove:** nema `*.en.json`, `book.en.epub`, `reels.en.json`, EN OG slika.
- **Postojeće:** nema prekidača jezika; `/v/<id>/en` se ponaša kao za neprevedenu epizodu
  (HR sadržaj) — ili preusmjerava na `/v/<id>` (otvoreno §C-7); worker ne šalje `hreflang`
  na EN i za `/en` daje HR OG + canonical na HR.
- **Izvor:** app **K**; worker **K**; pipeline **K-batch**.
- **Latencija:** app ≤ ~12 min; worker ≤ 1 h; EN red u pipelineu 2 min.
- **Sesija:** S5, S6, S7.

### 13. `magisterium`

- **Potrošači:** 50 datoteka u `lib/` spominje Magisterium (naredba na dnu). Bitni:
  - ekran epizode: `lib/widgets/magisterium_panel.dart` (`MagisteriumPanel` r. 36; pozivi
    `lib/screens/episode_screen.dart` r. 2862/3111/3137), `lib/widgets/magisterium_section.dart`,
    `lib/widgets/magisterium_article_section.dart`, `lib/widgets/magisterium_v2_view.dart`
    (`lib/screens/episode_simple_screen.dart` r. 676-739, tab „Magisterium”),
    `lib/widgets/parallel_article_view.dart`, `lib/widgets/citation_helpers.dart`;
  - ocjena na karticama: `lib/screens/home/channel_card.dart`, `lib/screens/home/episode_rail_card.dart`,
    `lib/screens/home/hero_section.dart`, `lib/screens/home/person_card.dart`,
    `lib/screens/catalog_day/catalog_card_meta.dart`, `lib/screens/tv/widgets/tv_episode_card.dart`,
    `lib/screens/tv/widgets/tv_hero.dart`, `lib/screens/tv/tv_home_screen.dart` (r. 388),
    `lib/screens/tv/tv_channel_screen.dart` (r. 320), `lib/screens/tv/tv_episode_reader_screen.dart`
    (r. 1147-1191), `lib/screens/channel/channel_screen.dart`;
  - rangiranje: `lib/screens/home/home_feed.dart` (`magisteriumScore` r. 100, ulazi u izbor
    hera), `lib/screens/home/sort_mode.dart` (sortiranje po ocjeni);
  - modeli s ocjenom iz kataloga/CDN-a: `lib/models/catalog_card.dart`, `lib/models/home_snapshot.dart`,
    `lib/models/channel_detail.dart`, `lib/models/person_hub.dart`;
  - pipeline: KORAK 8.5 `enrich_magisterium_full.js` (r. 1521), `enrich_magisterium_batch.js`,
    `automatic/enqueue_magisterium_backfill.js`, `automatic/magisterium_pipeline.sh`
    (launchd `tv.domovina.fetch.magisterium.plist` 600 s, `-en` 120 s);
  - katalog: ocjena u kartici epizode (`/episodes/:id/card`, `/days`) — 11. 11. dodana na `/dani`.
- **Nove:** nema poziva Magisterium AI ni `magisterium*.json`.
- **Postojeće:** na mjestu ocjene i panela stoji „Vlasnik je isključio procjenu” (odluka 2) na
  ekranu epizode (oba prikaza, TV čitač). Na karticama: prijedlog je bez značke (tekst ne
  stane), ali to treba potvrditi (§C-8). Epizoda ispada iz sortiranja po ocjeni i ocjena ne
  ulazi u izbor hera.
- **Izvor:** app **K**; katalog maskira polje ocjene u SQL-u projekcije (kartice iz kataloga
  tada su ispravne bez klijenta); pipeline **K-batch**.
- **Latencija:** app ≤ ~12 min; kartice iz `home.json`/listinga nose ocjenu do sljedećeg
  KORAKA 13, pa klijentski filtar mora pokriti i njih.
- **Sesija:** S3 (maska u kartici), S5 (najviše pozivnih mjesta), S7.

### 14. `highlights_reels`

- **Potrošači:** `lib/services/data_service.dart` (`loadReels` r. 515), `lib/models/episode_reels.dart`,
  `lib/widgets/episode_reels.dart` (`ReelTimelineMarks` r. 76, `EpisodeReelsPlayerStrip` r. 149,
  `showReelViewer` r. 412), `lib/widgets/video_panel.dart` (`_showChapterList` r. 54,
  `EpisodeReelsPlayerStrip` r. 268), `lib/screens/episode_screen.dart` (`loadReels` r. 921,
  `reels:` r. 3188/3227/3282/3356/3780/3816), `lib/screens/episode_simple_screen.dart`
  (r. 268, `ReelTimelineMarks` r. 1264, `EpisodeReelsPlayerStrip` r. 1366); pipeline KORAK 9.9
  `select_reels.js` (r. 1845), KORAK 12.68 (r. 2107), `render_reels.js`, `render_reel_premium.js`.
- **Nove:** nema `reels.json`, `reels.en.json` ni rendera.
- **Postojeće:** nema markera na seek baru, „Istaknutih trenutaka” ni 9:16 modala; u
  `VideoPanel` se zato vraća popis poglavlja (`_showChapterList` gleda `reels`) — to mora
  ostati tako (test u §B).
- **Izvor:** app **K** (jedno mjesto: `loadReels` vraća `null`); pipeline **K-batch**.
- **Latencija:** app ≤ ~12 min; render red 30 min.
- **Sesija:** S5, S7.

### 15. `persons_mentions`

- **Potrošači:**
  - app: `lib/services/person_service.dart` (`/api/person`, `/api/persons`, r. 18-30),
    `lib/services/person_index_cache.dart`, `lib/services/person_channel_flag.dart`,
    `lib/screens/person/person_screen.dart` (`/p/:slug`), `lib/screens/home/persons_rail.dart`
    (`PersonsRail` r. 27), `lib/screens/home/person_card.dart`, `lib/models/person_hub.dart`
    (`allAppearances`, `episodes`, `cameo_episodes`, `mentions`), TV `lib/screens/tv/tv_person_screen.dart`,
    pretraga osoba u `lib/screens/home/search_overlay.dart`; na epizodi `PeopleRail`
    (`lib/widgets/entities_section.dart` r. 80; `lib/screens/episode_screen.dart` r. 2768/2901)
    i `?p=<slug>` sidro;
  - RAG: `domovina-rag: services/mcp/src/tools/person-channel.ts` (pravilo uvrštavanja),
    `services/mcp/src/tools/get-person.ts`, `services/mcp/src/tools/count-mentions.ts`,
    `services/mcp/src/public-api.ts` (`/api/person/:slug` r. 244, `/api/persons` r. 270),
    `domovina-rag: scripts/emit_person_mentions_sql.py`, `domovina-rag: scripts/sync-person-map.sh`,
    `services/etl/etl/sources.py` (`read_mentioned_people` r. 182);
  - worker: `/p/` OG (`injectPersonTags` r. 1291) i `/p/` u sitemapu (r. 834-839);
  - vijesti: `vijesti/engine/score/persons.ts`.
- **Nove:** epizode kanala ne ulaze u person map ni u spomene.
- **Postojeće:** izostaju iz `episodes[]`, `cameo_episodes[]` i `mentions[]` svih profila;
  brojevi uvrštavanja (≥ 3 epizode, ≥ 3 kanala, ≤ 60 %) računaju se bez njih, pa osoba može
  ispasti iz virtualnih kanala. `PeopleRail` na epizodi tog kanala: prijedlog je da imena
  ostanu kao tekst bez poveznice na `/p/` (otvoreno §C-9).
- **Izvor:** RAG **K-batch** (prag je u backendu i mora se računati bez kanala — klijentski
  filtar ne može ispravno preračunati `is_virtual_channel`); app **K** kao privremeni
  filtar nad `episodes[]`/`mentions[]` dok RAG ne preračuna.
- **Latencija:** RAG sync jednom dnevno u 04:00 → do 24 h za pragove; klijentski filtar ≤ ~12 min.
- **Sesija:** S8 (RAG), S5 (klijentski filtar, `PeopleRail`), S6 (`/p/` OG ne nabraja epizode).

### 16. `news_portal`

- **Potrošači:** `vijesti/engine/cdn/loader.ts` (popis kanala iz `channels/data/index.json`
  r. 257, per-kanal listing r. 264, `article.json`/`summary.json` r. 274-275),
  `vijesti/engine/score/run.ts`, `vijesti/engine/rag/related.ts` („ista tema u drugim
  podcastima” preko `mcp.domovina.ai/api/search`), `vijesti/db/export-to-prod.ts`
  (prijenos u produkciju), portal `vijesti/portal/`; worker `handleVijesti`
  (`web/_worker.js` r. 2233).
- **Nove:** engine ne bira epizode tog kanala ni kao izvor članka ni kao „povezano”.
- **Postojeće:** već objavljeni članci portala koji citiraju epizodu: povlače se ili ostaju
  (urednička odluka, §C-10); `related.ts` ih više ne nudi.
- **Izvor:** **K-batch** (engine je Node skripta); pravilo i ugovor piše S8, provodi lanac
  vijesti (plan, odluka 9: ovaj lanac ne mijenja kod `vijesti/` sam).
- **Latencija:** sljedeći run enginea (raspored određuje lanac vijesti; danas ručno/po
  sesiji, nije mjereno).
- **Sesija:** S8 (ugovor) → lanac vijesti.

### 17. `ai_assistants`

- **Potrošači:** `domovina-rag: services/mcp/src/server.ts` alati (r. 112-196:
  `search_podcasts`, `list_channels`, `list_episodes`, `get_episode`, `count_mentions`,
  `get_person`, `find_in_transcript`), `services/mcp/src/public-api.ts` `/api/search`
  (r. 210; isti endpoint koristi i semantika u paleti pretrage i `vijesti/engine/rag/related.ts`),
  `services/etl/etl/load.py` + `sources.py` (`discover_jsonl` s `channel_filter`, r. 95),
  `domovina-rag: scripts/sync-incremental.sh`; pipeline KORAK 9 `prepare_rag*.js` (r. 1546-1555) i KORAK 11
  `import_to_vertex.js` (r. 1874, Vertex AI RAG, opt-in `--with-vertex-import`).
- **Nove:** ne chunkaju se ni ne embedaju; ne idu u Vertex.
- **Postojeće:** MCP alati i `/api/search` ih ne vraćaju (filtar u upitu nad ClickHouseom
  odmah), a sljedeći sync ih briše iz `rag_chunks`.
- **Izvor:** **K** u MCP serveru (kratki cache, npr. 60 s) za upite; **K-batch** u ETL-u.
- **Latencija:** upitni filtar ≤ ~1-2 min uz cache; fizičko uklanjanje do 24 h (04:00).
  Napomena: `/api/search` je zajednički za `ai_assistants` i `in_app_search` — trebaju dva
  parametra ili dvije provjere (§C-11).
- **Sesija:** S8; Vertex izvan plana (§A).

### 18. `donations`

- **Potrošači:** app: `lib/pinka_sdk/src/widgets/pinka_support_bar.dart` (`PinkaSupportBar.episode`
  u `lib/screens/episode_screen.dart` r. 3431/3880 i `lib/screens/episode_simple_screen.dart`
  r. 910), `lib/pinka_sdk/src/widgets/pinka_support_card.dart` (`PinkaSupportCard.channel` u
  `lib/screens/channel/channel_screen.dart` r. 217), `lib/pinka_sdk/src/widgets/pinka_grid_wall.dart`,
  `lib/pinka_sdk/src/widgets/pinka_contribute_panel.dart`, `lib/pinka_sdk/src/screens/pinka_campaign_screen.dart`,
  `lib/widgets/support_episode_panel.dart`, rute `/c/:slug/doniraj|support`
  (`lib/router/app_router.dart` r. 131), vlasnikove kampanje
  `lib/screens/ownership/campaigns/channel_campaigns_screen.dart`; worker `cSupportMatch`
  (`web/_worker.js` r. 572) i `injectSupportTags` (r. 1694); domovina-api:
  `supabase/functions/pinka-contribute/`, `pinka_finance.create_contribution`
  (`supabase/migrations/20260530120300_pinka_finance_rpcs.sql`), `pinka-webhook`,
  `pinka-onchain-ingest`.
- **Nove:** nema novih doprinosa: `pinka-contribute` odbija s kodom (npr.
  `donations_disabled:<uc>`), nezavisno od klijenta.
- **Postojeće:** nema trake, kartice ni zida; `/c/<slug>/doniraj` kaže da je vlasnik
  isključio donacije. Već plaćeni doprinosi i isplate ostaju (financijski zapis se ne
  skriva vlasniku; javni zid se skriva).
- **Izvor:** domovina-api **A** (ista baza, provjera u RPC-u/edge funkciji, nula kašnjenja);
  app i worker **K**.
- **Latencija:** naplata odmah (A); UI ≤ ~12 min; OG ≤ 1 h.
- **Sesija:** S2 (provjera u RPC-u — nije u opisu S2, §A), S5, S6.

### 19. `paid_sponsor_moments`

- **Potrošači:** app: `lib/screens/sponsor/sponsor_store_screen.dart` (`/c/:slug/oglasi`),
  `lib/screens/sponsor/sponsor_episode_screen.dart` (`/v/:videoId/sponzoriraj`),
  `lib/screens/sponsor/sponsor_checkout_form.dart`, `lib/services/sponsored_moments_service.dart`
  (`loadLive` r. 77; pozivi `lib/screens/episode_screen.dart` r. 915, `lib/screens/episode_simple_screen.dart`
  r. 262), `lib/services/sponsored_moments_controller.dart`, `lib/widgets/sponsored_moment_widgets.dart`
  (`SponsoredMomentVideoBadge` r. 35 u `lib/widgets/episode_video.dart` r. 612,
  `SponsoredMomentsPlayerStrip` r. 97 u `lib/widgets/video_panel.dart` r. 556 i
  `lib/screens/episode_simple_screen.dart` r. 1360, `SponsoredMomentCard` r. 139,
  `SponsoredMomentSectionMark` r. 262), `lib/services/cast_receiver.dart`; worker
  `cAdsMatch` (`web/_worker.js` r. 574, `injectSponsorStoreTags` r. 1781), `sponsorVMatch`
  (r. 527, `injectSponsorEpisodeTags` r. 1793); domovina-api:
  `pinka_finance.public_live_moments` i `public_sponsor_moments`
  (`supabase/migrations/20261007120000_sponzorski_trenuci.sql` r. 492/525),
  `create_sponsor_contribution` (r. 245), `supabase/functions/sponsor-cron/`,
  `supabase/functions/sponsor-moderate/`, `pinka-contribute`.
- **Nove:** nema izloga ni checkouta; `create_sponsor_contribution` odbija.
- **Postojeće:** već plaćeni i živi trenuci — otvoreno (§C-12): ugovor sa sponzorom vs.
  vlasnikova odluka. Prijedlog: prikaz prestaje (pogled `public_live_moments` filtrira),
  a povrat/obračun ide ručno.
- **Izvor:** **A** (filtar u pogledu i RPC-u); app i worker **K** za izlog i OG.
- **Latencija:** odmah za checkout i živi prikaz (pogled); izlog ≤ ~12 min.
- **Sesija:** S2 (pogled + RPC — nije u opisu S2), S5, S6.

### 20. `sponsors_in_video`

- **Potrošači:** `lib/services/data_service.dart` (`loadSponsorsInVideo` r. 493),
  `lib/models/sponsors_in_video.dart`, `lib/widgets/sponsors_in_video_section.dart`
  (`SponsorsInVideoSection` r. 21, `SponsorsInVideoPlayerStrip` r. 417, `SponsorListenChip` r. 505,
  `SponsorsInVideoSectionMark` r. 549), `lib/screens/episode_screen.dart` (r. 909, r. 2541),
  `lib/widgets/video_panel.dart` (r. 546), `lib/widgets/article_section.dart`; pipeline
  KORAK 9.85 `detect_sponsors.js` (r. 1773).
  `lib/screens/episode_simple_screen.dart` nema ovu sekciju (grep) — nema potrošača ondje.
- **Nove:** nema `sponsors_in_video.json`.
- **Postojeće:** nema sekcije „Uz podršku”, trake u panelu ni oznake u članku. Sam sponzorski
  spot ostaje u snimci (to je autorov sadržaj).
- **Izvor:** app **K** (jedno mjesto: `loadSponsorsInVideo` vraća `null`); pipeline **K-batch**.
- **Latencija:** app ≤ ~12 min.
- **Sesija:** S5, S7.

<!-- matrica-end -->

---

## A. Potrošači koje plan nije predvidio

| potrošač | ključevi | zašto je izvan plana | prijedlog |
|---|---|---|---|
| CDN `channels/data/index.json`, per-kanal listinzi, `home.json`, `search.json` (`fetch.domovina.tv: generate_channel_index.js`, KORAK 13) | 1, 3, 4, 13 | plan pretpostavlja da app čita katalog; app ih čita s CDN-a | S3 dodaje `GET /v1/settings`; S5 filtrira u `ChannelCache`/`HomeFeed`/`mergeSearchResults`; S7 filtrira u KORAKU 13 kao drugu liniju |
| Katalog poller (domovina-api → D1) | svi | katalog nema cron ni poller (`katalog/wrangler.jsonc` bez `triggers`) | S3: Cron Trigger + kursor `updated_at`; izmjeriti zastoj |
| `domovina-cutter` (`src/index.ts`, `service/server.js`) | 1, 7, 8, 10 | zaseban repo i Worker, nije u odluci 9 | dodati u S8 ili novu malu sesiju; provjera **K** prije rezanja |
| `og:video` / `contentUrl` u workeru (`web/_worker.js` r. 1195-1229) | 7 | S6 pokriva OG/noindex/sitemap, ne medij | S6 |
| Cast receiver (`web/cast-receiver.html`, `handleCastReceiver` r. 322, `lib/services/cast_receiver.dart`) | 1, 7, 19 | odluka 1: „Cast nije prekidač” — ali pušta CDN medij i sponzorske trenutke | S5 (pošiljatelj ne castira), S6 (receiver) |
| TV ekrani (`lib/screens/tv/` — 5 ekrana + `widgets/tv_hero.dart`, `widgets/tv_episode_card.dart`) | 1, 3, 7, 10, 13, 15 | plan spominje TV samo kao rizik S5 | S5 eksplicitno; TV nema `EpisodeVideo` ni `VideoPanel` |
| `/yt/:videoId` (`lib/screens/youtube_watch/youtube_watch_screen.dart`) | 1, 10 | nudi gumb na obrađenu epizodu i čita `summary.json` | S5 |
| Magisterium ocjena na karticama i u rangiranju (`HomeFeed.magisteriumScore`, `sort_mode.dart`, katalog kartica) | 13 | odluka 2 opisuje samo panel na epizodi | S3 (maska u kartici), S5; odluka o kartici (§C-8) |
| Vertex AI RAG import (KORAK 11, `import_to_vertex.js`) | 17 | opt-in, izvan RAG repoa | S7 |
| `share_to_whatsapp.js` (ručna skripta, WhatsApp grupa) | 1, 8 | ručni alat izvan pipelinea | S7: skripta odbija kanal s isključenim ključem |
| Glasački bazen (`fetch.domovina.tv: sync_voting_candidates.mjs`, `domovina_ai.vote_candidates`) | 1 | glasanje skriveno od 26. 10., ali tripwire sinkronizira svako jutro | S7 ili S8: povučen kanal → `withdrawn` u bazenu |
| domovina-api provjera u `pinka-contribute`, `create_contribution`, `create_sponsor_contribution`, `public_live_moments` | 18, 19 | S2 je „shema, RPC, RLS” za postavke; S8 ne spominje pinku | proširiti S2 (ista baza, ista migracija) |
| Vlasnikov ekran kampanja (`lib/screens/ownership/campaigns/`) | 18 | vlasnik koji isključi donacije ne bi trebao moći otvoriti kampanju | S4 |
| Analitika (`lib/services/analytics/`) | — | odluka 1: nije prekidač | bez promjene; ali događaji na povučenim epizodama i dalje idu (OK) |
| `vijesti/engine/rag/related.ts` preko `/api/search` | 4, 16, 17 | dijeli endpoint s pretragom i MCP-om | S8: endpoint prima namjenu (`purpose=search|assistant|news`) |

## B. Testovi po prekidaču vidljivi u aplikaciji (za S5)

Pretpostavka: S4 uvodi servis stanja (npr. `ChannelSettingsService`) s lažnom
implementacijom za testove (mapa UC → isključeni ključevi). Svaki test ima par: ključ
isključen → element nema; bez retka postavki → element je tu (tvrdi uvjet 4 plana).

| ključ | widget/ekran | provjera u widget testu |
|---|---|---|
| `channel_enabled` | `EpisodeScreen`, `ChannelScreen`, `AllChannelsScreen`, TV `TvChannelScreen` | `find.text(l.<povučeno>)` i link na YouTube; nema `EpisodeVideo`; kanal nema karticu u popisu |
| `home_featured` | `HomeFeed.pickFeaturedCarousel`, `freshlyArrived`, `latestEpisodes` (čiste funkcije) | unit test: epizoda kanala nije u izlazu; `CatalogDayRail` s lažnim klijentom |
| `in_app_search` | `mergeSearchResults` | unit test: pogodak iz sva tri izvora (`local`, `meili`, `semantic`) za kanal izostaje |
| `push_notifications` | `FollowButton` | nema opcije obavijesti za kanal; praćenje (favorit) ostaje |
| `cdn_playback` | `EpisodeScreen`, `_PlayerTab` | `find.byType(InAppYouTubePlayer)` umjesto `EpisodeVideo`; `resolveMedia` se ne zove (lažni `DataService`) |
| `share_clips` | `ChaptersSection`, reel share | `find.byType(ClipShareButton)` = 0; u reel vieweru nema dijeljenja videa |
| `ebook` | `EbookCard`, `EbookAction` | oba = 0, i `EbookService.probe` nije pozvan |
| `article_summary` | `EpisodeScreen`, `_ChaptersTab`, `_InfoTab` | `find.byType(ArticleSection)` / `ChaptersSection` / `EntitiesSection` = 0; naslov i player postoje |
| `transcript_subtitles` | `EpisodeVideo` (overlay), `SubtitleStrip`, `FindInEpisodeSection` | sve = 0; `loadSpeakerTimeline` nije pozvan |
| `english_translation` | `LanguageToggleChip` | = 0 na oba prikaza; `episodeShareUrl` ne vraća `/en` |
| `magisterium` | `MagisteriumPanel`, `MagisteriumV2View` tab, TV čitač, kartica | tekst „Vlasnik je isključio procjenu” umjesto ocjene; nema taba „Magisterium” |
| `highlights_reels` | `VideoPanel`, `_PlayerTab`, `ReelTimelineMarks` | nema `EpisodeReelsPlayerStrip`; **popis poglavlja se pojavljuje** (`_showChapterList`) |
| `persons_mentions` | `PersonScreen` (lažni `PersonService`), `PeopleRail` | epizoda kanala nema u nastupima; imena na epizodi bez poveznice |
| `donations` | `PinkaSupportBar.episode`, `PinkaSupportCard.channel`, `/c/:slug/doniraj` | = 0; ruta prikazuje poruku o isključenju |
| `paid_sponsor_moments` | `SponsoredMomentsPlayerStrip`, `SponsoredMomentVideoBadge`, `SponsorStoreScreen` | = 0; izlog kaže da je isključeno |
| `sponsors_in_video` | `SponsorsInVideoSection`, `SponsorsInVideoPlayerStrip` | = 0 |

Bez vidljivog efekta u Flutteru (ne idu u S5 testove): `processing`, `search_engines`,
`news_portal`, `ai_assistants`. To je 16 vidljivih ključeva.

Preporuka za mjesto provjere: većinu AI ključeva provesti **na mjestu dohvata**
(`DataService`, `EbookService.probe`, `SponsoredMomentsService.loadLive`), ne u widgetima —
tada sva tri stabla playera (video traka, `VideoPanel`, `_PlayerTab`) i TV dobiju isto
ponašanje bez prop drillinga (isto pravilo kao „stanje kontrole ide kroz singleton” u
korijenskom `CLAUDE.md`). Iznimke koje trebaju widget: `magisterium` (tekst umjesto
ocjene), `channel_enabled` (povučen prikaz), `donations`/`paid_sponsor_moments` (rute).

## C. Otvorena pitanja

1. **Ovisnosti AI ključeva.** Ako je `article_summary` off, a `ebook`/`magisterium`/
   `english_translation`/`share_clips`/`news_portal` on: generira li pipeline članak
   interno (ne objavljuje ga) ili ovisni ključevi efektivno padaju? Prijedlog: ovisni padaju,
   a ekran postavki to pokazuje (siva sklopka s objašnjenjem).
2. **Transkript kao interni ulaz.** `transcript_subtitles` off: smije li se ASR raditi za
   članak/Magisterium ako se ne objavljuje? Isto za `cdn_playback` off: smije li se medij
   preuzeti za obradu (pitanje 3)?
3. **`cdn_playback` off za nove epizode:** preuzimanje medija za AI obradu je dopušteno,
   samo se ne objavljuje? Ili se kanal tada obrađuje iz YouTube titlova (KORAK 12.8)?
4. **Run u tijeku:** epizoda koja je u pipelineu kad vlasnik isključi `processing` — dovršiti
   ili prekinuti prije uploada (KORAK 12)? Prijedlog: provjera i neposredno prije uploada.
5. **Reprodukcija u tijeku** kad `cdn_playback` ili `channel_enabled` padne: prekinuti ili
   pustiti do kraja sesije? Prijedlog: pustiti; provjera samo pri otvaranju ekrana.
6. **Korisnikovi popisi** (favoriti, „Nastavi slušati”, „Pratim”): pod `home_featured` ostaju;
   pod `channel_enabled` kartica postaje „povučeno” ili nestaje?
7. **`/v/<id>/en` uz `english_translation` off:** HR sadržaj na EN URL-u ili preusmjerenje na
   HR URL? Preusmjerenje je čišće za tražilice (canonical).
8. **Magisterium na karticama:** odluka 2 traži vidljiv tekst umjesto ocjene; na kartici od
   ~180 px tekst ne stane. Značka „—” s tooltipom, ili ništa?
9. **`PeopleRail` na epizodi** uz `persons_mentions` off: imena kao tekst, ili cijela traka
   nestaje? Imena su dio članka (`article_summary`), ne profila.
10. **Već objavljeni članci portala vijesti** koji citiraju povučen kanal: povući, ili ostaju
    jer su urednički tekst domovina.ai?
11. **`/api/search` dijele tri ključa** (`in_app_search`, `ai_assistants`, `news_portal`).
    Treba li namjena kao parametar ili zasebni endpointi?
12. **Plaćeni živi sponzorski trenutak** kad vlasnik isključi `paid_sponsor_moments`: prestaje
    odmah (povrat sponzoru) ili traje do isteka slota?
13. **Izvor stanja za pipeline:** plan dopušta domovina-api ili katalog. Prijedlog je katalog
    (jedan odgovor nosi i tombstone iz odluke 6). Ako katalog ne odgovori: fail-open (obradi
    kao danas, uvjet 4) ili fail-closed za kanale s poznatim retkom postavki?
14. **Kanali bez UC id-a** (odluka 7): `extractUcId` u workeru (`web/_worker.js` r. 1418) i
    `PodcastInfo.youtubeChannelId` (`lib/models/podcast_info.dart` r. 184) vraćaju null za
    ne-UC izvore (X, RSS, beamly). Ti kanali uvijek rade kao danas; S1 mjeri koliko ih je.

## Reprodukcija

Iz korijena `domovina.ai` (osim gdje piše drugi repo):

```bash
# 50 datoteka u lib/ spominje Magisterium (bez l10n)
grep -rli magisterium packages/podcast_core/lib | grep -v l10n/ | wc -l
# 21 datoteka u screens/ + widgets/ crta ocjenu
cd packages/podcast_core/lib && grep -rlE "magisteriumScore|overall_score|\.score\b" screens widgets | wc -l; cd -
# katalog rute (6) i cache-control
grep -nE "return \{ kind" katalog/src/api/v1.ts
grep -nE "^const CACHE_[A-Z_]+ =" katalog/src/api/v1.ts
# katalog nema cron
grep -nE "triggers|crons" katalog/wrangler.jsonc || echo "nema"
# KORACI pipelinea
grep -nE 'korak "' ../fetch.domovina.tv/run_pipeline.sh
# rasporedi pipelinea (StartInterval / Hour)
grep -nE "<integer>" ../fetch.domovina.tv/automatic/launchd/*.plist
# RAG + Meili sync u 04:00
grep -nA4 StartCalendarInterval ../domovina-rag/infra/launchd/tv.domovina.rag.sync.plist
# push cron i DRY_RUN
grep -nE "crons|DRY_RUN" ../domovina-push/wrangler.jsonc
# app čita listinge s CDN-a, ne iz kataloga
grep -nE "channels/data" packages/podcast_core/lib/services/cdn_config.dart
# OG HTML cache epizode
grep -nE "s-maxage=3600" web/_worker.js
```
