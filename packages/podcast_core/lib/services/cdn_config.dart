import '../brand/app_brand.dart';

/// Centralna definicija svih CDN URL-ova (host iz branda, npr. cdn.domovina.ai).
///
/// Svi asseti (JSON podaci, slike, video) loadaju se u runtimeu iz CDN-a
/// na temelju YouTube ID-a epizode — bez lokalnih bundlanih fajlova.
class CdnConfig {
  /// Host CDN-a aktivnog brenda (`AppBrand.config.endpoints.cdn`).
  static String get base => AppBrand.config.endpoints.cdn;

  /// Origin the pipeline writes into absolute URLs inside the CDN data
  /// (`avatar_square`, `avatar_cover`, `thumbnail` in channel and info JSON).
  static const String dataOrigin = 'https://cdn.domovina.ai';

  /// Serves an absolute CDN URL from the data through the active brand's CDN
  /// host, so a brand with its own CDN name (cdn.podcasterium.com, the same
  /// bucket) never loads from [dataOrigin]. Other URLs pass unchanged.
  static String rebase(String url) =>
      url.startsWith('$dataOrigin/') && base != dataOrigin
          ? base + url.substring(dataOrigin.length)
          : url;

  static String? rebaseOrNull(String? url) => url == null ? null : rebase(url);

  // 5-minutni cache-buster. Danas služi SAMO za probe URL-ove i drugi pokušaj
  // nakon 404 (CDN cachira 404 do 4 h) — NE za listinge kanala, vidi
  // [channelsIndexUrl].
  static String _channelCacheBuster() {
    final bucket = DateTime.now().millisecondsSinceEpoch ~/ 300000;
    return 'v=$bucket';
  }

  /// Lijepi isti 5-minutni cache-buster na proizvoljan CDN URL.
  ///
  /// Per-epizoda datoteke ga u normalnom dohvatu NEMAJU (pravo su immutable),
  /// pa ovo služi samo za drugi pokušaj nakon 404 — vidi `DataService._get`.
  static String bustCache(String url) =>
      '$url${url.contains('?') ? '&' : '?'}${_channelCacheBuster()}';

  // Channels
  //
  // Listinzi su BEZ cache-bustera. Origin šalje
  // `Cache-Control: public, max-age=60, must-revalidate` + ETag, i edge to
  // poštuje (izmjereno 9.10.2026.: `HIT` uz `age: 34`, nakon isteka
  // `REVALIDATED`). Preglednik zato nakon 60 s pošalje `If-None-Match` i za
  // nepromijenjen listing dobije 304 s 0 bajtova. Do v2.0.172 je ovdje stajao
  // 5-minutni `?v=` (iz vremena kad je uploader stavljao `immutable` na sve) —
  // novi URL svakih 5 min značio je novi cache zapis bez ETag-a, tj. svih
  // 1,3 MB listinga iznova na svakom posjetu. Najgori slučaj sada: novi video
  // vidljiv ~2 min kasnije (60 s edge + 60 s preglednik).
  // Vidi `docs/2026-10-08-brzina-ucitavanja-naslovnice.md` §2.3 i Q1.
  static String channelsIndexUrl() => '$base/channels/data/index.json';
  static String channelUrl(String channelId) =>
      '$base/channels/data/$channelId.json';

  /// Gotov izbor epizoda za naslovnicu (vidi `HomeSnapshot`). Ista cache
  /// pravila kao listinzi: bez bustera, revalidacija preko ETag-a.
  static String homeSnapshotUrl() => '$base/channels/data/home.json';

  /// Tekst za pretragu koji skraćeni listing ne nosi (vidi `SearchCorpus`).
  static String searchCorpusUrl() => '$base/channels/data/search.json';
  static String channelAvatarUrl(String channelId) =>
      '$base/channels/images/$channelId/avatar_square.jpg?${_channelCacheBuster()}';
  static String channelCoverUrl(String channelId) =>
      '$base/channels/images/$channelId/avatar_cover.jpg?${_channelCacheBuster()}';

  // JSON podaci

  /// Objedinjena datoteka epizode (vidi `EpisodeBundle`): popis postojećih
  /// datoteka + sadržaj za prvi prikaz. Promjenjiva, pa bez `?v=` kao
  /// listinzi (origin `max-age=60` + ETag).
  static String episodeBundleUrl(String ytId) =>
      '$base/data/$ytId/episode.json';
  static String infoUrl(String ytId) => '$base/data/$ytId/info.json';
  static String summaryUrl(String ytId) => '$base/data/$ytId/summary.json';
  static String outlineUrl(String ytId) => '$base/data/$ytId/outline.json';
  static String articleUrl(String ytId) => '$base/data/$ytId/article.json';
  static String magisteriumUrl(String ytId) =>
      '$base/data/$ytId/article.magisterium.json';
  static String magisteriumBatchUrl(String ytId) =>
      '$base/data/$ytId/article.magisterium_batch.json';
  static String magisteriumFullUrl(String ytId) =>
      '$base/data/$ytId/article.magisterium_full.json';
  static String magisteriumFullPromptUrl(String ytId) =>
      '$base/data/$ytId/article.magisterium_full_prompt.md';
  static String magisteriumFullV2Url(String ytId) =>
      '$base/data/$ytId/article.magisterium_full_v2.json';
  static String magisteriumFullV2PromptUrl(String ytId) =>
      '$base/data/$ytId/article.magisterium_full_v2_prompt.md';

  // English translation overlays — superset HR + dodana `_en` polja.
  // 404 dok pipeline jos nije producirao prijevod za dani video.
  static String summaryEnUrl(String ytId) => '$base/data/$ytId/summary.en.json';
  static String articleEnUrl(String ytId) => '$base/data/$ytId/article.en.json';
  static String magisteriumEnUrl(String ytId) =>
      '$base/data/$ytId/article.magisterium.en.json';
  static String magisteriumBatchEnUrl(String ytId) =>
      '$base/data/$ytId/article.magisterium_batch.en.json';
  static String magisteriumFullV2EnUrl(String ytId) =>
      '$base/data/$ytId/article.magisterium_full_v2.en.json';
  /// Titl. [lang] traži `diarized.<lang>.srt` (titl na tom jeziku uz zadani
  /// `diarized.srt`; docs/plans/2026-10-29-titlovi-na-dva-jezika.md).
  static String diarizedSrtUrl(String ytId, {String? lang}) =>
      '$base/data/$ytId/diarized${lang == null ? '' : '.$lang'}.srt';

  /// Vrijeme po riječi za cue-ove iz `diarized.srt` (Speechmatics, poravnato
  /// s tekstom koji je Gemini uredio). Postoji samo za novije epizode.
  /// [lang] je par za `diarized.<lang>.srt`.
  static String wordsUrl(String ytId, {String? lang}) =>
      '$base/data/$ytId/words${lang == null ? '' : '.$lang'}.json';

  /// Sponzori ugrađeni u snimku (KORAK 9.85) — postoji za svaku objavljenu
  /// epizodu; `sponsors: []` znači da ih nema. Vidi `SponsorsInVideo`.
  static String sponsorsInVideoUrl(String ytId) =>
      '$base/data/$ytId/sponsors_in_video.json';

  /// Istaknuti trenuci i 9:16 isječci (`reels.json`). Postoji samo za
  /// epizode kanala s pristankom; traži se SAMO kad ga `episode.json` navodi.
  /// Vidi `EpisodeReels`.
  static String reelsUrl(String ytId) => '$base/data/$ytId/reels.json';

  /// EPUB e-knjiga epizode (pipeline KORAK 9.8, `generate_ebook.js`).
  /// Postoji samo za epizode koje imaju članak; englesko izdanje samo kad
  /// postoji i `article.en.json`. Ime na CDN-u je `book.epub` / `book.en.epub`
  /// bez obzira na ime datoteke u pipelineu (`upload_to_r2.js` ih mapira).
  static String ebookUrl(String ytId) => '$base/data/$ytId/book.epub';
  static String ebookEnUrl(String ytId) => '$base/data/$ytId/book.en.epub';

  /// Probe URL-ovi za postojanje knjige — cache-buster je OBAVEZAN: CDN cachira
  /// 404 četiri sata, a knjiga se generira nakon članka (i englesko izdanje tek
  /// nakon prijevoda), pa bi jedan prerani probe sakrio knjigu do kraja tog
  /// prozora. Ista zamka kao kod [videoH264ProbeUrl].
  /// Preuzimanje ide preko čistog URL-a (immutable cache je tu poželjan).
  static String ebookProbeUrl(String ytId) =>
      '$base/data/$ytId/book.epub?${_channelCacheBuster()}';
  static String ebookEnProbeUrl(String ytId) =>
      '$base/data/$ytId/book.en.epub?${_channelCacheBuster()}';

  /// Video MP4 — CDN podržava HTTP 206 range requeste za seeking.
  /// Ovo je izvorni codec (može biti AV1/VP9 — ne dekodira se HW svugdje).
  static String videoUrl(String ytId) => '$base/data/$ytId/video.mp4';

  /// H.264 transcode — univerzalno HW-dekodirajuć (Android 4+, svi browseri,
  /// iOS). Pipeline producira ovo paralelno s `video.mp4`. Postoji samo za
  /// epizode koje su prošle transcode korak; vidi [DataService.resolveMedia]
  /// koji probe-a postojanje i fallback-a na [videoUrl] ako 404.
  static String videoH264Url(String ytId) => '$base/data/$ytId/video_h264.mp4';

  /// Iste H.264/AAC struje kao [videoH264Url], prepakirane u fragmentirani MP4
  /// sa `sidx` indeksom: zaglavlje ~11 KB umjesto ~2,7 MB `moov`-a za sat
  /// epizode, pa prvi frame na „Slow 4G" stigne za ~2,6 s umjesto ~16 s.
  /// Postoji samo za epizode od 11.10.2026. i bira se SAMO kad ga
  /// `episode.json` navodi (bez probe-a). Vidi
  /// `docs/2026-10-11-brzi-start-videa-fmp4.md`.
  ///
  /// `?g=` je generacija datoteke, ne cache-buster: fajl je `immutable` na
  /// godinu dana, a pipeline ga prepisuje na istom R2 ključu. Bez novog
  /// ključa preglednik koji je epizodu već gledao vadi stare range-ove iz
  /// svog cachea (Cloudflare purge do njih ne dopire) i slaže ih s novima.
  /// Kad pipeline opet prepiše fmp4, podigni broj — tek NAKON uploada, inače
  /// se pod novim ključem cachira stari fajl.
  ///
  /// 3 = remux s `+cmaf`. Generacija 2 (`-frag_interleave 25`
  /// bez `cmaf`, 24.10.) ruši Chromium već na jednom skoku
  /// (`PIPELINE_ERROR_DECODE`, `PPXbSP14H4Y` @3403 s) — vidi
  /// `docs/2026-10-26-fmp4-seek-decode-error.md`.
  static const _fmp4Generation = 3;

  static String videoH264FragmentedUrl(String ytId) =>
      '$base/data/$ytId/video_h264_fmp4.mp4?g=$_fmp4Generation';

  /// Fragmentirani MP4 za Chromium: isti remux kao [videoH264FragmentedUrl]
  /// (`+cmaf`), ali BEZ `-frag_interleave`. Interleavani fajl ruši Chromium
  /// nakon niza skokova (`PIPELINE_ERROR_DECODE`, zvuk i slika se raziđu,
  /// player zapne u „buffering") — vidi
  /// `docs/2026-10-28-fmp4-interleave-chromium-seek.md`. `?g=` ima isto
  /// značenje kao kod [videoH264FragmentedUrl]; nova datoteka kreće od 1.
  static const _fmp4WebGeneration = 1;

  static String videoH264FragmentedWebUrl(String ytId) =>
      '$base/data/$ytId/video_h264_fmp4_web.mp4?g=$_fmp4WebGeneration';

  /// Probe URL za H.264 postojanje — s cache-busterom da stale 404 (od prije
  /// nego je transcode završio) ne zaglavi fallback na izvorni video.
  /// Playback i dalje koristi čisti [videoH264Url] (immutable cache OK).
  static String videoH264ProbeUrl(String ytId) =>
      '$base/data/$ytId/video_h264.mp4?${_channelCacheBuster()}';

  /// Probe URL za legacy `video.mp4` postojanje (cache-buster zbog 404 cache-a).
  static String videoProbeUrl(String ytId) =>
      '$base/data/$ytId/video.mp4?${_channelCacheBuster()}';

  /// Audio MP3 — AUDIO-ONLY epizode (beamly/transistor kanali bez YouTube
  /// videa, npr. subclub/launched). Pipeline uploada `audio.mp3` (audio/mpeg,
  /// immutable) za epizode kojima je `_yt_matched === false`. Podržava HTTP 206
  /// range requeste (seek). Vidi data_contract.md §8.1 + [DataService.resolveMedia].
  static String audioUrl(String ytId) => '$base/data/$ytId/audio.mp3';

  /// Probe URL za `audio.mp3` postojanje — s cache-busterom (CDN cache-ira 404
  /// 4h, pa stale 404 od prije uploada ne smije zaglaviti detekciju).
  /// Playback koristi čisti [audioUrl] (immutable cache OK).
  static String audioProbeUrl(String ytId) =>
      '$base/data/$ytId/audio.mp3?${_channelCacheBuster()}';

  /// Thumbnail epizode — full-res PNG original (1280×720, tipično ~800 KB).
  ///
  /// Za PRIKAZ radije koristi [CachedThumbnail], koji ovaj URL automatski
  /// zamijeni WebP varijantom primjerenom render-širini (vidi
  /// [thumbnailVariantUrl]) i pada natrag na ovaj PNG ako varijanta ne postoji.
  /// Ovaj URL ostaje kanonski identitet slike i fallback.
  static String thumbnailUrl(String ytId) => '$base/images/$ytId/thumbnail.png';

  /// Širine WebP varijanti koje pipeline generira
  /// (`fetch.domovina.tv/generate_webp_thumbs.js`). Mora ostati sortirano
  /// uzlazno — [pickThumbWidth] se oslanja na to.
  static const List<int> thumbVariantWidths = [320, 640, 1280];

  /// WebP varijanta thumbnaila. [width] mora biti iz [thumbVariantWidths].
  ///
  /// Zašto uopće: PNG original je ~800 KB po epizodi, pa lista od 20 epizoda
  /// povuče ~16 MB. Ista slika kao WebP q80 @320px je ~13 KB — 61× manje.
  /// Varijante su unaprijed generirane i leže na R2 kao obični statični fajlovi
  /// (nema resize servisa u request pathu), immutable, cachirane na CF edgeu.
  static String thumbnailVariantUrl(String ytId, int width) =>
      '$base/images/$ytId/thumb-$width.webp';

  /// Najmanja varijanta koja pokriva [targetPx] fizičkih piksela.
  ///
  /// [targetPx] je render-širina u logičkim pikselima × devicePixelRatio.
  /// Ako ništa nije dovoljno veliko (vrlo širok layout na DPR 3), vraća najveću
  /// — bolje blago skaliranje prema dolje nego 800 KB PNG.
  static int pickThumbWidth(double targetPx) {
    for (final w in thumbVariantWidths) {
      if (w >= targetPx) return w;
    }
    return thumbVariantWidths.last;
  }

  /// Regex za prepoznavanje kanonskog thumbnail URL-a → hvata YouTube ID.
  /// Koristi [CachedThumbnail] da automatski nadogradi URL na WebP varijantu
  /// bez da ijedan call-site mora znati za varijante.
  static final RegExp thumbnailUrlPattern =
      RegExp(r'/images/([A-Za-z0-9_-]{11})/thumbnail\.png$');

  /// Screenshot za dani timestamp ("HH:MM:SS" → "HH-MM-SS.png")
  static String screenshotUrl(String ytId, String timestamp) {
    final ts = timestamp.replaceAll(':', '-');
    return '$base/images/$ytId/screenshots/$ts.png';
  }

  /// Epizode kojima `episode.json` navodi `screenshots_webp.json` — pipeline
  /// je uz svaki PNG (1920×1080, ~1,3 MB) uploadao `{ts}-960.webp` (~20 KB).
  /// Puni ga [DataService] pri učitavanju bundlea; stari katalog ga nema.
  static final Set<String> _screenshotWebp = {};
  static void markScreenshotWebp(String ytId) => _screenshotWebp.add(ytId);

  /// WebP varijanta screenshota ili `null` kad je epizoda nema. Pojedini kadar
  /// koji ipak fali pokriva [CachedThumbnail] padom na [screenshotUrl].
  static String? screenshotWebpUrl(String ytId, String timestamp) {
    if (!_screenshotWebp.contains(ytId)) return null;
    final ts = timestamp.replaceAll(':', '-');
    return '$base/images/$ytId/screenshots/$ts-960.webp';
  }
}
