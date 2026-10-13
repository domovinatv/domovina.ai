# Worklog: Pretraga + mobilni episode header (svibanj/lipanj 2026)

Trajni zapis rada na pretrazi i mobilnom headeru. Sve dolje je **commitano i
pushano** na `origin/main` (osim gdje je naznačeno). Deployano: **v2.0.36+58**.

---

## 1. Semantička pretraga (Tier 1) — RAG `/api/search`

**Backend (`domovina-rag`, repo `domovinatv/domovina-rag`):**
- Novi public REST endpoint `GET/POST /api/search` (`services/mcp/src/public-api.ts`)
  — tanak NE-MCP omotač oko iste `searchPodcasts()` funkcije. Vraća čisti JSON
  (`{query, count, results[]}`), **bez LLM-a**. CORS allow-lista + per-IP
  rate-limit, bez OAuth.
- Env: `PUBLIC_SEARCH_ENABLED` (default true), `PUBLIC_SEARCH_ALLOWED_ORIGINS`
  (default `domovina.ai, www.domovina.ai, localhost:5173`),
  `PUBLIC_SEARCH_RATE_PER_MINUTE` (default 30).
- **Live na `https://mcp.domovina.ai/api/search`** (Coolify redeploy).
- `score = 1 − cosineDistance` (~0.40–0.65 za dobre pogotke), rezultati već
  silazno sortirani.
- Commit: `a2b993b` (pushano).

**Frontend (Flutter):**
- `lib/services/search_service.dart` — `SemanticResult` model + `SearchService`
  (debounce, graceful fallback na [] kad endpoint nedostupan, defenzivni sort).

## 2. Lokalna pretraga (Tier 0) + zajednički UI

- `lib/utils/text_search.dart` — dijakritik-neosjetljiv (č→c, š→s, ž→z, đ→d)
  `foldText` (length-preserving), `localMatchScore` (token-AND),
  `highlightRanges` (word-level **stem/prefix** matching → hvata sklonjene
  oblike: demografska↔demografsku), `snippetAround` (isječak oko pogotka).
- `lib/widgets/highlight_text.dart` — `QueryHighlightText` (crveno+bold).
- `lib/widgets/episode_age.dart` — `EpisodeAgeChip` (color-coded starost:
  zelena→žuta→narančasta→crvena + relativna oznaka "prije 3 dana"…).
- `lib/screens/home/search_overlay.dart` (Cmd+K overlay):
  - **Desktop (≥760px): dvostupčani** — lijevo PO NASLOVU (kanali+epizode),
    desno U SADRŽAJU (semantika). Mobitel: složeno u jedan scroll.
  - **Keyboard:** ↑/↓ kroz aktivni stupac, ←/→ između stupaca, Enter odabir.
    `onKeyEvent` na samom `FocusNode`-u (hvata ←/→ prije text-editing shortcuta).
  - Relevance metar (bar+score) uz semantičke rezultate; višelinijski naslovi;
    isječci centrirani na pogodak; age chip u oba stupca.
  - Mobitel: `autofocus: true` (diže on-screen tipkovnicu na iOS PWA).
- Testovi: `test/text_search_test.dart` (folding, stem highlight, snippet, age).
- Commitovi: `039bb1d`, `19901be`, `e8aeb96`, `4113869`, `4162580`, `08f77ab`,
  `74d1de4`, `f093762` (sve pushano).

## 3. Meilisearch keyword PoC (KOMPLEMENTARNO, trenutno ONEMOGUĆENO)

Keyword (egzaktno + typo-tolerantno) search, odvojen od semantike.

- Indexer: `domovina-rag/scripts/meili-poc-index.py` (2562 dok, 1 po epizodi;
  searchable: title, section_titles, article_text; filter: channel, upload_date).
- Flutter: `lib/services/meili_client.dart`, `lib/widgets/em_highlight_text.dart`
  (parsira Meili `<em>` tagove), `lib/screens/search/meili_search_screen.dart`
  (instant search, facet chipovi po kanalu, stats "N rezultata u M ms",
  crop+highlight snippet, EpisodeAgeChip).
- **Ruta `/search` je ZAKOMENTIRANA** u `lib/router/app_router.dart`. Reaktivirati
  kad Meili bude na serveru + integrirati u homepage tražilicu.
- PoC zahtijeva `article_text` u Meili `displayedAttributes` (za snippet).
- Lokalno: Meili v1.11 na `localhost:7700` (master key `poc_master_key_domovina_2026`),
  CORS `*`. Android emu host = `10.0.2.2:7700`.
- Commitovi: `cfd3a2f` (PoC), `b0f086b` (disable rute).

## 4. Mobilni episode header (responsive, dva reda)

Problem: na uskom ekranu breadcrumb + 6-7 akcija (ID, Favorite, HR/EN, Share,
YouTube, Jednostavni, Video) se prelijevalo — "većina buttona se ne vidi".

- `_episodeAppBar` helper (`lib/screens/episode_screen.dart`) — dijele ga sve
  tri `SliverAppBar` varijante. Na **<600px**: breadcrumb gornji red, akcije
  drugi red (`bottom`), **oba horizontalno skrolabilna**. Desktop/tablet: inline.
- `_Breadcrumb` u scrollable modu (<600px) prikazuje **puni put**
  (Početna › Kanal › Epizoda) bez `Flexible` (unbounded width).
- Commitovi: `e02e88d` (dva reda), `7dda4a4` (breadcrumb scroll).

## 5. Deploy

`./scripts/deploy.sh` → `flutter build web --release --wasm` → wrangler pages
deploy → CDN purge → verify. Auto-bumpa verziju.
- v2.0.34+56 (`847cf9f`), v2.0.35+57 (`39991f6`), v2.0.36+58 (`8c632d1`).
- Napomena: `deploy.sh` zove goli `wrangler`; ako nije na PATH-u → `npx wrangler`.

---

**Vidi i memoriju:** `search_architecture.md` (~/.claude/.../memory/).


## Nastavak

- 13. 10. 2026.: Mali GPU kvar crtanja, mobilni ekran pretrage i pametni search (lokalno + Meili + semantika) — `docs/2026-10-13-pretraga-mali-gpu-i-pametni-search.md`
