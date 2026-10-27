import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import '../models/channel_index.dart';
import '../models/channel_detail.dart';
import '../models/home_snapshot.dart';
import '../models/search_corpus.dart';
import '../models/podcast_info.dart';
import '../models/podcast_summary.dart';
import '../models/podcast_outline.dart';
import '../models/podcast_article.dart';
import '../models/magisterium_data.dart';
import '../models/magisterium_full_data.dart';
import '../models/episode_bundle.dart';
import '../models/episode_status.dart';
import '../models/magisterium_full_v2_data.dart';
import '../models/speaker_timeline.dart';
import '../brand/app_brand.dart';
import '../models/episode_reels.dart';
import '../models/sponsors_in_video.dart';
import 'cdn_config.dart';
import 'mobile_web_detect.dart' show isWebKitBrowser;
import 'cdn_json_cache.dart';
import 'cdn_store.dart' show StoreBucket;
import '../src/log.dart' show log;

/// Bačen kad info.json za dani YouTube ID ne postoji na CDN-u (HTTP 404).
class VideoNotFoundException implements Exception {
  final String youtubeId;
  const VideoNotFoundException(this.youtubeId);

  @override
  String toString() => 'VideoNotFoundException: $youtubeId';
}

/// Učitava channel index i detail s CDN-a.
///
/// Sve ide kroz [CdnJsonCache.getMutable]: pri ponovnom otvaranju vraća se
/// spremljena verzija odmah, a nova (ako je ima) stiže kroz `onUpdate`.
class ChannelService {
  static Future<ChannelIndex> loadIndex({
    void Function(ChannelIndex index)? onUpdate,
  }) async {
    final body = await CdnJsonCache.instance.getMutable(
      CdnConfig.channelsIndexUrl(),
      onUpdate: onUpdate == null ? null : (b) => onUpdate(_parseIndex(b)),
    );
    return _parseIndex(body);
  }

  static ChannelIndex _parseIndex(String body) =>
      ChannelIndex.fromJson(jsonDecode(body) as Map<String, dynamic>);

  static Future<ChannelDetail> loadChannel(
    String channelId, {
    void Function(ChannelDetail detail)? onUpdate,
  }) async {
    final body = await CdnJsonCache.instance.getMutable(
      CdnConfig.channelUrl(channelId),
      onUpdate: onUpdate == null ? null : (b) => onUpdate(_parseChannel(b)),
    );
    return _parseChannel(body);
  }

  static ChannelDetail _parseChannel(String body) =>
      ChannelDetail.fromJson(jsonDecode(body) as Map<String, dynamic>);

  /// `home.json` — `null` kad ga nema (404 dok ga pipeline ne generira),
  /// kad je nepoznate verzije ili kad dohvat padne. Nikad ne baca: naslovnica
  /// tada ide starim putem preko svih listinga.
  static Future<HomeSnapshot?> loadHomeSnapshot({
    void Function(HomeSnapshot snapshot)? onUpdate,
  }) async {
    try {
      final body = await CdnJsonCache.instance.getMutable(
        CdnConfig.homeSnapshotUrl(),
        onUpdate: onUpdate == null
            ? null
            : (b) {
                final snap = _parseSnapshot(b);
                if (snap != null) onUpdate(snap);
              },
      );
      return _parseSnapshot(body);
    } catch (_) {
      return null;
    }
  }

  static HomeSnapshot? _parseSnapshot(String body) {
    try {
      return HomeSnapshot.tryParse(jsonDecode(body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// `search.json` — `null` kad ga nema (listinzi su još v1 i tekst nose
  /// sami), kad je nepoznate verzije ili kad dohvat padne. Nikad ne baca.
  /// Bez `onUpdate`: pretraga u sesiji radi s verzijom koju je dobila.
  static Future<SearchCorpus?> loadSearchCorpus() async {
    try {
      final body =
          await CdnJsonCache.instance.getMutable(CdnConfig.searchCorpusUrl());
      return SearchCorpus.tryParse(jsonDecode(body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

/// Učitava podatke za konkretni YouTube video ID s CDN-a (cdn.domovina.ai).
class DataService {
  final String youtubeId;

  const DataService({required this.youtubeId});

  /// Brend bez domenske ocjene (`flags.domainScore == false`) ne dohvaća
  /// `article.magisterium*` assete — svaki `loadMagisterium*` odmah vraća
  /// `null`, pa je `EpisodeData.hasMagisterium` false bez ijednog zahtjeva
  /// (9 od 17 paralelnih dohvata po epizodi manje).
  static bool get domainScoreEnabled => AppBrand.config.flags.domainScore;

  /// GET koji NE vjeruje 404-u iz prve.
  ///
  /// Per-epizoda datoteke su na CDN-u `immutable` pa se dohvaćaju bez
  /// cache-bustera — ali Cloudflare cachira i **404** od prije nego ih je
  /// pipeline uploadao, i to u zasebnom `Vary: Origin` zapisu. Preglednik na
  /// svaki cross-origin fetch šalje `Origin`, `dart:io` klijent (iOS/Android/
  /// macOS) ga ne šalje — pa ista epizoda čita DVA različita cache zapisa i
  /// vidi dva različita odgovora.
  ///
  /// Izmjereno 19.9.2026. na `aue1GuuMsbA` i `70uXR4DDZiE`: `info.json`,
  /// `summary.json`, `outline.json`, `article.json` i `diarized.srt` vraćali su
  /// uz `Origin: https://domovina.ai` **404** (`cf-cache-status: HIT`, `age`
  /// 20 972 s uz `cache-control: max-age=3600`), a bez tog zaglavlja 200.
  /// Posljedica: `loadInfo` je na webu bacao [VideoNotFoundException] pa je
  /// epizoda padala na `EpisodeStage.queued` („epizoda još nije preuzeta") uz
  /// YouTube embed, dok je u iOS aplikaciji radila normalno — iste datoteke,
  /// isti Dart izvor. Napomena: `purge_cache` po golom URL-u taj zapis NE
  /// briše; varijantu čisti samo purge s `headers: {"Origin": …}`.
  ///
  /// Zato: na 404 ponovi zahtjev s cache-busterom (isti 5-minutni bucket kao
  /// probe-ovi u [CdnConfig]). To je druga cache adresa, pa ide na origin i
  /// zaobilazi otrovani zapis. Tek ako i ona vrati 404, datoteke doista nema.
  /// Cijena je jedan dodatni zahtjev po assetu koji ionako nedostaje; na
  /// uspješnom dohvatu nula. Probe putanje ([_exists], `EbookService.probe`)
  /// cache-buster nose oduvijek i ne trebaju retry.
  ///
  /// Na nativeu ide kroz [CdnJsonCache.getImmutable]: jednom dohvaćena
  /// datoteka čita se s diska (i offline). 404 se ne sprema.
  ///
  /// Isti URL koji je već u letu (predučitavanje pa klik, ili dva ekrana
  /// odjednom) dijeli jedan zahtjev, a nedavni 200 odgovori ostaju u maloj
  /// memoriji ([_recent]) — epizoda predučitana na naslovnici otvara se bez
  /// mreže i u pregledniku koji HTTP cache cross-origin JSON-a ne drži
  /// pouzdano. Vidi `EpisodePrefetch`.
  Future<http.Response> _get(String url) async {
    final bundle = await _bundle();
    if (bundle != null) {
      final name = url.substring(url.lastIndexOf('/') + 1);
      final body = bundle.inlineBody(name);
      if (body != null) {
        return http.Response.bytes(utf8.encode(body), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      // Popis je izmjeren na R2, pa ovdje 404 bez mreže JEST istina — za
      // razliku od 404 s CDN-a, koji je mogao biti cachiran prije uploada.
      if (!bundle.has(name)) return http.Response('', 404);
    }
    return _network(url);
  }

  Future<http.Response> _network(String url) {
    final hit = _recent.remove(url);
    if (hit != null) {
      _recent[url] = hit; // LRU: osvježi redoslijed
      return Future.value(hit);
    }
    final inflight = _inflight[url];
    if (inflight != null) return inflight;
    final f = CdnJsonCache.instance.getImmutable(url, () async {
      final first = await http.get(Uri.parse(url));
      if (first.statusCode != 404) return first;
      return http.get(Uri.parse(CdnConfig.bustCache(url)));
    }).then((r) {
      if (r.statusCode == 200 && r.bodyBytes.length <= _recentMaxBytes) {
        _recent[url] = r;
        while (_recent.length > _recentMaxEntries) {
          _recent.remove(_recent.keys.first);
        }
      }
      return r;
    }).whenComplete(() {
      // Blok, ne strelica: `remove` vraća baš ovaj future, a `whenComplete`
      // čeka future koji callback vrati — strelica bi čekala samu sebe.
      _inflight.remove(url);
    });
    _inflight[url] = f;
    return f;
  }

  /// `data/<id>/episode.json` ([EpisodeBundle]) — jednom po epizodi i sesiji.
  /// `null` (404, mreža, nepoznata verzija) znači stari put: datoteku po
  /// datoteku, s retryjem na 404. Promjenjiv je (pipeline ga prepisuje kad
  /// stigne nova datoteka), pa ide kroz [CdnJsonCache.getMutable] kao listinzi:
  /// bez bustera, s diska na nativeu (offline), revalidacija u pozadini.
  Future<EpisodeBundle?> _bundle() {
    final cached = _bundles.remove(youtubeId);
    if (cached != null) {
      _bundles[youtubeId] = cached;
      return cached;
    }
    final f = CdnJsonCache.instance
        .getMutable(CdnConfig.episodeBundleUrl(youtubeId),
            bucket: StoreBucket.episode)
        .then(EpisodeBundle.tryParse, onError: (_) => null)
        .then((b) {
      if (b != null && b.has('screenshots_webp.json')) {
        CdnConfig.markScreenshotWebp(youtubeId);
      }
      return b;
    });
    _bundles[youtubeId] = f;
    while (_bundles.length > _bundlesMax) {
      _bundles.remove(_bundles.keys.first);
    }
    return f;
  }

  static final Map<String, Future<EpisodeBundle?>> _bundles = {};
  static const int _bundlesMax = 24;

  static final Map<String, Future<http.Response>> _inflight = {};

  /// Zadnji uspješni odgovori, LRU. ~7 datoteka po epizodi → desetak epizoda.
  static final Map<String, http.Response> _recent = {};
  static const int _recentMaxEntries = 80;
  static const int _recentMaxBytes = 512 * 1024;

  /// Samo za testove: memorija iz [_get] inače preživi između testova.
  @visibleForTesting
  static void resetMemoryForTest() {
    _inflight.clear();
    _recent.clear();
    _bundles.clear();
  }

  /// Predučitava datoteke koje ekran epizode treba za PRVI prikaz (info,
  /// sažetak, poglavlja, članak). Titlovi, vrijeme po riječi i Magisterium
  /// varijante namjerno ne — oni su 2/3 bajtova, a trebaju tek kasnije.
  /// Greške se gutaju: ovo je samo nagovještaj.
  Future<void> prefetchFirstPaint() async {
    // S objedinjenom datotekom je sve za prvi prikaz već u njoj.
    if (await _bundle() != null) return;
    await Future.wait([
      for (final url in [
        CdnConfig.infoUrl(youtubeId),
        CdnConfig.summaryUrl(youtubeId),
        CdnConfig.outlineUrl(youtubeId),
        CdnConfig.articleUrl(youtubeId),
      ])
        _get(url).then((_) {}, onError: (_) {}),
    ]);
  }

  Future<String> _fetch(String url) async {
    final response = await _get(url);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: $url');
    }
    return response.body;
  }

  Future<PodcastInfo> loadInfo() async {
    final url = CdnConfig.infoUrl(youtubeId);
    final response = await _get(url);
    if (response.statusCode == 404) throw VideoNotFoundException(youtubeId);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: $url');
    }
    return PodcastInfo.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Summary — vraca null ako fajl ne postoji (AI pipeline jos nije gotov).
  /// Prave HTTP greske propagira dalje.
  Future<PodcastSummary?> loadSummary() async {
    final url = CdnConfig.summaryUrl(youtubeId);
    final response = await _get(url);
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: $url');
    }
    return PodcastSummary.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// EN-overlay verzija summary.json — sadrzi HR polja + dodana `_en` polja.
  /// Vraca null ako prijevod za ovaj video jos nije producran (404).
  Future<PodcastSummary?> loadSummaryEn() async {
    final url = CdnConfig.summaryEnUrl(youtubeId);
    final response = await _get(url);
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: $url');
    }
    return PodcastSummary.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Outline — vraca null ako fajl ne postoji (AI pipeline jos nije gotov).
  Future<PodcastOutline?> loadOutline() async {
    final url = CdnConfig.outlineUrl(youtubeId);
    final response = await _get(url);
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: $url');
    }
    return PodcastOutline.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Article — vraca null ako fajl ne postoji (AI pipeline jos nije gotov).
  Future<PodcastArticle?> loadArticle() async {
    final url = CdnConfig.articleUrl(youtubeId);
    final response = await _get(url);
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: $url');
    }
    return PodcastArticle.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// EN-overlay verzija article.json — vraca null ako prijevod ne postoji.
  Future<PodcastArticle?> loadArticleEn() async {
    final url = CdnConfig.articleEnUrl(youtubeId);
    final response = await _get(url);
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: $url');
    }
    return PodcastArticle.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Magisterium teološko obogaćivanje — opcionalno (nije obavezan asset).
  Future<MagisteriumData?> loadMagisterium() async {
    if (!domainScoreEnabled) return null;
    try {
      final raw = await _fetch(CdnConfig.magisteriumUrl(youtubeId));
      return MagisteriumData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// EN-overlay verzija article.magisterium.json — opcionalno.
  Future<MagisteriumData?> loadMagisteriumEn() async {
    if (!domainScoreEnabled) return null;
    try {
      final raw = await _fetch(CdnConfig.magisteriumEnUrl(youtubeId));
      return MagisteriumData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Magisterium batch varijanta — opcionalno.
  Future<MagisteriumData?> loadMagisteriumBatch() async {
    if (!domainScoreEnabled) return null;
    try {
      final raw = await _fetch(CdnConfig.magisteriumBatchUrl(youtubeId));
      return MagisteriumData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// EN-overlay verzija article.magisterium_batch.json — opcionalno.
  Future<MagisteriumData?> loadMagisteriumBatchEn() async {
    if (!domainScoreEnabled) return null;
    try {
      final raw = await _fetch(CdnConfig.magisteriumBatchEnUrl(youtubeId));
      return MagisteriumData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Magisterium full evaluacija (Magisterium AI API) — opcionalno.
  Future<MagisteriumFullData?> loadMagisteriumFull() async {
    if (!domainScoreEnabled) return null;
    try {
      final raw = await _fetch(CdnConfig.magisteriumFullUrl(youtubeId));
      return MagisteriumFullData.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  /// Magisterium full prompt (markdown) — opcionalno.
  Future<String?> loadMagisteriumFullPrompt() async {
    if (!domainScoreEnabled) return null;
    try {
      return await _fetch(CdnConfig.magisteriumFullPromptUrl(youtubeId));
    } catch (_) {
      return null;
    }
  }

  /// Magisterium full v2 evaluacija — novi format s `prompt_version`. Opcionalno.
  Future<MagisteriumFullV2Data?> loadMagisteriumFullV2() async {
    if (!domainScoreEnabled) return null;
    try {
      final raw = await _fetch(CdnConfig.magisteriumFullV2Url(youtubeId));
      return MagisteriumFullV2Data.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  /// EN-overlay verzija article.magisterium_full_v2.json — opcionalno.
  Future<MagisteriumFullV2Data?> loadMagisteriumFullV2En() async {
    if (!domainScoreEnabled) return null;
    try {
      final raw = await _fetch(CdnConfig.magisteriumFullV2EnUrl(youtubeId));
      return MagisteriumFullV2Data.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  /// Magisterium full v2 prompt (markdown) — opcionalno.
  Future<String?> loadMagisteriumFullV2Prompt() async {
    if (!domainScoreEnabled) return null;
    try {
      return await _fetch(CdnConfig.magisteriumFullV2PromptUrl(youtubeId));
    } catch (_) {
      return null;
    }
  }

  /// Sponzori ugrađeni u snimku — opcionalno, i nikad ne ruši ekran: 404,
  /// mreža, CORS ili nečitljiv JSON daju null pa se sekcija jednostavno ne
  /// prikaže. Namjerno bez memorije preko sesije: pipeline datoteku prepisuje
  /// i purgea kad se detektor poboljša, pa je obični HTTP cache dovoljan.
  /// 404 prolazi kroz [_get] (jedan retry s cache-busterom, nikad petlja).
  Future<SponsorsInVideo?> loadSponsorsInVideo() async {
    try {
      final raw = await _fetch(CdnConfig.sponsorsInVideoUrl(youtubeId));
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      return SponsorsInVideo.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Istaknuti trenuci epizode (`reels.json`) — opcionalno, kao i sponzori:
  /// null na svaku grešku, i sekcije nema.
  ///
  /// Traži se samo kad ga `episode.json` navodi u `files`: datoteka postoji
  /// za malo epizoda, a bez bundlea bi svaka druga epizoda platila 404 (i
  /// retry s cache-busterom). Bez bundlea (stara epizoda) — nema ni reelova.
  ///
  /// Za razliku od ostalih per-epizoda datoteka NIJE nepromjenjiva: pipeline
  /// je prepisuje kad doda poster ili renderira sljedeći kandidat, pa ide
  /// kroz stale-while-revalidate ([CdnJsonCache.getMutable]), ne kroz [_get].
  Future<EpisodeReels?> loadReels() async {
    try {
      final bundle = await _bundle();
      if (bundle == null || !bundle.has('reels.json')) return null;
      final raw = await CdnJsonCache.instance.getMutable(
        CdnConfig.reelsUrl(youtubeId),
        bucket: StoreBucket.episode,
      );
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      final reels = EpisodeReels.fromJson(json);
      return reels.isEmpty ? null : reels;
    } catch (e) {
      log('DataService.loadReels($youtubeId): $e');
      return null;
    }
  }

  /// HEAD probe — true ako resurs vraća 200. Mreža/CORS greška → false.
  /// HEAD (ne GET) da ne skidamo cijeli media file.
  Future<bool> _exists(String url) async {
    try {
      final r = await http.head(Uri.parse(url));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Razrješava playabilnu mediju po OBAVEZNOM redoslijedu iz data_contract.md
  /// §8.1 (HEAD probe, cache-buster zbog 4h CDN 404 cache-a):
  ///   1. `video_h264.mp4` → VIDEO (univerzalni HW-decode, sve platforme)
  ///   2. `audio.mp3`      → AUDIO (audio-only beamly/transistor epizode)
  ///   3. legacy `video.mp4` → VIDEO (može biti AV1/VP9; stariji HW ne dekodira)
  ///   4. ništa od navedenog → [EpisodeMediaKind.none] (graceful "nema medije")
  ///
  /// NB: oslanjamo se na CDN realnost (probe), NE na info.json `_sound_link`
  /// koji POSTOJI i na video epizodama (yt-matched) pa nije audio-only signal.
  ///
  /// S [EpisodeBundle] nema probe-a: njegov popis datoteka je izmjeren na R2,
  /// pa vrijedi isti redoslijed nad popisom (tri HEAD-a manje, i oni idu
  /// jedan za drugim). Ispred svega ide `video_h264_fmp4.mp4` (isti video,
  /// brži start — [CdnConfig.videoH264FragmentedUrl]); njega bira samo bundle,
  /// put s probe-ovima ostaje na `video_h264.mp4`.
  Future<({String uri, EpisodeMediaKind kind})> resolveMedia() async {
    final bundle = await _bundle();
    if (bundle != null) {
      // WebKit (Safari, svi iOS preglednici) fmp4 još nije isproban na pravom
      // uređaju — dok ne bude, ostaje na video_h264.mp4. Native (libmpv) i
      // Chromium su izmjereni.
      if (bundle.has('video_h264_fmp4.mp4') && !isWebKitBrowser()) {
        return (
          uri: CdnConfig.videoH264FragmentedUrl(youtubeId),
          kind: EpisodeMediaKind.video,
        );
      }
      if (bundle.has('video_h264.mp4')) {
        return (
          uri: CdnConfig.videoH264Url(youtubeId),
          kind: EpisodeMediaKind.video,
        );
      }
      if (bundle.has('audio.mp3')) {
        return (
          uri: CdnConfig.audioUrl(youtubeId),
          kind: EpisodeMediaKind.audio,
        );
      }
      if (bundle.has('video.mp4')) {
        return (
          uri: CdnConfig.videoUrl(youtubeId),
          kind: EpisodeMediaKind.video,
        );
      }
      return (uri: '', kind: EpisodeMediaKind.none);
    }
    if (await _exists(CdnConfig.videoH264ProbeUrl(youtubeId))) {
      return (
        uri: CdnConfig.videoH264Url(youtubeId),
        kind: EpisodeMediaKind.video,
      );
    }
    if (await _exists(CdnConfig.audioProbeUrl(youtubeId))) {
      return (uri: CdnConfig.audioUrl(youtubeId), kind: EpisodeMediaKind.audio);
    }
    if (await _exists(CdnConfig.videoProbeUrl(youtubeId))) {
      return (uri: CdnConfig.videoUrl(youtubeId), kind: EpisodeMediaKind.video);
    }
    return (uri: '', kind: EpisodeMediaKind.none);
  }

  /// Ucitaj diariziran SRT i parsiraj u SpeakerTimeline.
  /// Vraća null ako fajl ne postoji (nije obavezan asset).
  ///
  /// Uz SRT paralelno vuče i `words.json` (vrijeme po riječi). Njega nema za
  /// starije epizode, pa njegov izostanak ili kvar samo gasi isticanje riječi.
  Future<SpeakerTimeline?> loadSpeakerTimeline() async {
    final wordsF = _loadWordTimings();
    try {
      final raw = await _fetch(CdnConfig.diarizedSrtUrl(youtubeId));
      return _parseSrt(raw).withWordTimings(await wordsF);
    } catch (_) {
      return null;
    }
  }

  Future<Map<int, List<WordTiming>>> _loadWordTimings() async {
    try {
      final raw = await _fetch(CdnConfig.wordsUrl(youtubeId));
      return parseWordTimings(json.decode(raw));
    } catch (_) {
      return const {};
    }
  }
}

// ---------------------------------------------------------------------------
// SRT parser
// ---------------------------------------------------------------------------

final _tsRegex = RegExp(
  r'(\d{2}):(\d{2}):(\d{2}),(\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2}),(\d{3})',
);
final _speakerRegex = RegExp(r'^\[(\w+)\]');

int _srtTimeToMs(int h, int m, int s, int ms) =>
    h * 3600000 + m * 60000 + s * 1000 + ms;

SpeakerTimeline _parseSrt(String raw) {
  final segments = <SpeakerSegment>[];
  final blocks = raw.trim().split(RegExp(r'\r?\n\s*\r?\n'));

  for (final block in blocks) {
    final lines = block.trim().split(RegExp(r'\r?\n'));
    if (lines.length < 3) continue;

    final tsMatch = _tsRegex.firstMatch(lines[1]);
    if (tsMatch == null) continue;

    final startMs = _srtTimeToMs(
      int.parse(tsMatch.group(1)!),
      int.parse(tsMatch.group(2)!),
      int.parse(tsMatch.group(3)!),
      int.parse(tsMatch.group(4)!),
    );
    final endMs = _srtTimeToMs(
      int.parse(tsMatch.group(5)!),
      int.parse(tsMatch.group(6)!),
      int.parse(tsMatch.group(7)!),
      int.parse(tsMatch.group(8)!),
    );

    final text = lines.sublist(2).join(' ').trimLeft();
    final speakerMatch = _speakerRegex.firstMatch(text);
    if (speakerMatch == null) continue;

    segments.add(
      SpeakerSegment(
        startMs: startMs,
        endMs: endMs,
        speakerId: speakerMatch.group(1)!,
        text: text.replaceFirst(_speakerRegex, '').trim(),
      ),
    );
  }

  return SpeakerTimeline(segments: segments);
}

/// Vrsta playabilne medije razriješena probe-om (vidi [DataService.resolveMedia]).
enum EpisodeMediaKind { video, audio, none }

/// Svi podaci za jednu podcast epizodu, ucitani s CDN-a.
///
/// `info` i `videoUri` su uvijek prisutni — to su minimum za reprodukciju.
/// Ostali AI-generirani asseti (`summary`, `outline`, `article`, magisterium*,
/// speakerTimeline) su nullable jer pipeline zna kasniti za par sati/dana
/// nakon sto se video pojavi na YouTube-u. Screens trebaju gracefully
/// renderirati basic view (samo player + osnovne info) kad ovih nema.
class EpisodeData {
  final String youtubeId;
  final PodcastInfo info;
  final PodcastSummary? summary;
  final PodcastSummary? summaryEn;
  final PodcastOutline? outline;
  final PodcastArticle? article;
  final PodcastArticle? articleEn;
  final MagisteriumData? magisterium;
  final MagisteriumData? magisteriumEn;
  final MagisteriumData? magisteriumBatch;
  final MagisteriumData? magisteriumBatchEn;
  final MagisteriumFullData? magisteriumFull;
  final String? magisteriumFullPrompt;
  final MagisteriumFullV2Data? magisteriumFullV2;
  final MagisteriumFullV2Data? magisteriumFullV2En;
  final String? magisteriumFullV2Prompt;
  final SpeakerTimeline? speakerTimeline;

  /// Playabilni media URI razriješen probe-om: `video_h264.mp4` / `audio.mp3` /
  /// legacy `video.mp4`. Prazan string kad nema medije ([hasMedia] == false).
  final String videoUri;

  /// Vrsta medije iz probe-a. Driver za UI (audio cover-art vs video render).
  final EpisodeMediaKind mediaKind;

  const EpisodeData({
    required this.youtubeId,
    required this.info,
    this.mediaKind = EpisodeMediaKind.video,
    this.summary,
    this.summaryEn,
    this.outline,
    this.article,
    this.articleEn,
    this.magisterium,
    this.magisteriumEn,
    this.magisteriumBatch,
    this.magisteriumBatchEn,
    this.magisteriumFull,
    this.magisteriumFullPrompt,
    this.magisteriumFullV2,
    this.magisteriumFullV2En,
    this.magisteriumFullV2Prompt,
    this.speakerTimeline,
    required this.videoUri,
  });

  /// YouTube video ID za player/embed, ytimg i youtube.com linkove. Za
  /// varijantu epizode (`_variant_of` u info.json) [youtubeId] je SINTETIČKI
  /// (`OspwepfLO_2`) i YouTube ga ne zna — tada je ovo pravi ID izvorne
  /// epizode. CDN podaci, share i domovina.ai rute ostaju na [youtubeId].
  String get youtubeVideoId => info.variantOf ?? youtubeId;

  /// True kad AI pipeline (clanak) nije produkcijski gotov. UI tada pokazuje
  /// samo player + basic info i opcionalno YouTube chapters iz info.json.
  bool get hasAiContent => article != null;

  /// Faza obrade izvedena iz IZMJERENOG stanja — `info.json` je po definiciji
  /// tu (bez njega [EpisodeData] ne postoji), medija iz probe-a, tekstualni
  /// sloj iz prisutnosti pojedinog artefakta. Vidi [EpisodeStatus].
  EpisodeStatus get status => EpisodeStatus.measured(
        hasInfo: true,
        hasMedia: hasMedia,
        hasTranscript: speakerTimeline != null,
        hasSummary: summary != null,
        hasArticle: article != null,
        hasMagisterium: magisteriumPrimary != null || magisteriumFullV2 != null,
      );

  /// True kad je razriješena media AUDIO (`audio.mp3` na CDN-u). Autoritativno
  /// iz probe-a ([DataService.resolveMedia]), NE iz info.json flagova. UI tada
  /// prikazuje cover-art umjesto video površine i sakriva video/YT akcije.
  bool get isAudioOnly => mediaKind == EpisodeMediaKind.audio;

  /// False kad nijedan media asset ne postoji (sva 3 probe-a 404) — UI tada
  /// prikazuje jasnu poruku umjesto beskonačnog spinnera.
  bool get hasMedia => mediaKind != EpisodeMediaKind.none;

  /// True kad za ovaj video postoji EN prijevod na CDN-u. Trigger za toggle UI.
  /// Article je core artifact — bez njega nema sto prevodi. Summary je nice-to-have
  /// ali ne kriticno (worst case summary section pokazuje HR).
  bool get hasTranslationEn => articleEn != null;

  /// Vraca summary varijantu za dani jezik. EN je superset (sadrzi i HR polja),
  /// pa kad postoji koristi se i za HR-only fields. Kad EN ne postoji, fallback
  /// na HR summary.
  PodcastSummary? summaryFor(bool wantEn) {
    if (wantEn && summaryEn != null) return summaryEn;
    return summary;
  }

  PodcastArticle? articleFor(bool wantEn) {
    if (wantEn && articleEn != null) return articleEn;
    return article;
  }

  /// Helper za naslov: preferira HR summary, fallback na YouTube info.title.
  String get displayTitle {
    final hr = summary?.summary.titleHr;
    if (hr != null && hr.isNotEmpty) return hr;
    return info.title;
  }

  /// Naslov na jeziku sadržaja: EN iz `summary.en.json` (`title_en`), inače
  /// [displayTitle]. Isto pravilo kao `HeroSection` — breadcrumb, `<title>` i
  /// Media Session ne smiju ostati na hrvatskom dok naslov ispod piše engleski.
  String titleFor(bool wantEn) {
    if (wantEn) {
      final en = summaryEn?.summary.titleEn;
      if (en != null && en.isNotEmpty) return en;
    }
    return displayTitle;
  }

  /// All available Magisterium variants as (label, data) pairs.
  /// [wantEn] swap-a u EN-superset verziju ako postoji prijevod.
  List<(String, MagisteriumData)> magisteriumVariantsFor({
    bool wantEn = false,
  }) {
    final mag = wantEn ? (magisteriumEn ?? magisterium) : magisterium;
    final magBatch = wantEn
        ? (magisteriumBatchEn ?? magisteriumBatch)
        : magisteriumBatch;
    return [
      if (mag != null) ('Po sekciji', mag),
      if (magBatch != null) ('Po bloku', magBatch),
    ];
  }

  /// Backwards-compatible getter (HR only). Postojeci pozivi ne moraju znati za jezik.
  List<(String, MagisteriumData)> get magisteriumVariants =>
      magisteriumVariantsFor(wantEn: false);

  /// Preferred (first available) Magisterium data for inline enrichment.
  /// [wantEn] swap-a u EN-superset verziju (sadrzi HR + _en polja) ako postoji.
  MagisteriumData? magisteriumPrimaryFor({bool wantEn = false}) {
    if (wantEn) {
      return (magisteriumBatchEn ?? magisteriumBatch) ??
          (magisteriumEn ?? magisterium);
    }
    return magisteriumBatch ?? magisterium;
  }

  MagisteriumData? get magisteriumPrimary => magisteriumPrimaryFor();

  MagisteriumFullV2Data? magisteriumFullV2For({bool wantEn = false}) {
    if (wantEn && magisteriumFullV2En != null) return magisteriumFullV2En;
    return magisteriumFullV2;
  }

  static Future<EpisodeData> load({required String youtubeId}) async {
    final svc = DataService(youtubeId: youtubeId);
    final results = await Future.wait([
      svc.loadInfo(), // 0 — required (VideoNotFoundException ako 404)
      svc.loadSummary(), // 1 — nullable (404 → null)
      svc.loadOutline(), // 2 — nullable
      svc.loadArticle(), // 3 — nullable
      svc.loadMagisterium(), // 4
      svc.loadMagisteriumBatch(), // 5
      svc.loadSpeakerTimeline(), // 6
      svc.loadMagisteriumFull(), // 7
      svc.loadMagisteriumFullPrompt(), // 8
      svc.loadMagisteriumFullV2(), // 9
      svc.loadMagisteriumFullV2Prompt(), // 10
      // EN overlays — 404 → null kad prijevod nije producran.
      svc.loadSummaryEn(), // 11
      svc.loadArticleEn(), // 12
      svc.loadMagisteriumEn(), // 13
      svc.loadMagisteriumBatchEn(), // 14
      svc.loadMagisteriumFullV2En(), // 15
      svc.resolveMedia(), // 16 — video_h264 → audio.mp3 → legacy video probe
    ]);
    final info = results[0] as PodcastInfo;
    final media = results[16] as ({String uri, EpisodeMediaKind kind});
    return EpisodeData(
      youtubeId: youtubeId,
      info: info,
      mediaKind: media.kind,
      summary: results[1] as PodcastSummary?,
      outline: results[2] as PodcastOutline?,
      article: results[3] as PodcastArticle?,
      magisterium: results[4] as MagisteriumData?,
      magisteriumBatch: results[5] as MagisteriumData?,
      speakerTimeline: results[6] as SpeakerTimeline?,
      magisteriumFull: results[7] as MagisteriumFullData?,
      magisteriumFullPrompt: results[8] as String?,
      magisteriumFullV2: results[9] as MagisteriumFullV2Data?,
      magisteriumFullV2Prompt: results[10] as String?,
      summaryEn: results[11] as PodcastSummary?,
      articleEn: results[12] as PodcastArticle?,
      magisteriumEn: results[13] as MagisteriumData?,
      magisteriumBatchEn: results[14] as MagisteriumData?,
      magisteriumFullV2En: results[15] as MagisteriumFullV2Data?,
      videoUri: media.uri,
    );
  }

  /// Progressive loader — reports per-asset status via [onProgress].
  /// Assets load in parallel; callback fires as each completes.
  ///
  /// [onTimeline] (opcionalno): epizoda s člankom vraća se čim stigne sve
  /// OSIM titlova (`diarized.srt` + `words.json`, ~66 KB od ~106 KB brotli),
  /// a puni podaci stižu kroz [onTimeline] kad i oni dođu. Titlovi trebaju tek
  /// kad krene reprodukcija, a članak se može čitati odmah. Epizoda bez članka
  /// čeka sve, jer bi joj kartica faze bez transkripta krivo rekla „u obradi".
  static Future<EpisodeData> loadWithProgress({
    required String youtubeId,
    required void Function(String asset, bool done, bool ok) onProgress,
    void Function(EpisodeData full)? onTimeline,
  }) async {
    final svc = DataService(youtubeId: youtubeId);

    Future<T> track<T>(String name, Future<T> future) async {
      onProgress(name, false, true);
      try {
        final result = await future;
        onProgress(name, true, true);
        return result;
      } catch (e) {
        onProgress(name, true, false);
        rethrow;
      }
    }

    Future<T?> trackOptional<T>(String name, Future<T?> future) async {
      onProgress(name, false, true);
      try {
        final result = await future;
        onProgress(name, true, result != null);
        return result;
      } catch (_) {
        onProgress(name, true, false);
        return null;
      }
    }

    // Start all in parallel — info je jedini required, AI asseti su nullable
    // (404 → null = pipeline jos nije obradio video).
    final infoF = track('Info', svc.loadInfo());
    final summaryF = trackOptional('Sažetak', svc.loadSummary());
    final outlineF = trackOptional('Poglavlja', svc.loadOutline());
    final articleF = trackOptional('Članak', svc.loadArticle());
    // Magisterium redovi se ne prijavljuju kad brend nema domensku ocjenu —
    // loader bi ih inače prikazao kao „nedostaje”.
    final domainScore = DataService.domainScoreEnabled;
    Future<T?> trackDomain<T>(String name, Future<T?> future) =>
        domainScore ? trackOptional(name, future) : future;
    final magF = trackDomain('Magisterium', svc.loadMagisterium());
    final magBatchF = trackDomain(
      'Magisterium batch',
      svc.loadMagisteriumBatch(),
    );
    final magFullF = trackDomain(
      'Magisterium full',
      svc.loadMagisteriumFull(),
    );
    final magPromptF = trackDomain(
      'Magisterium prompt',
      svc.loadMagisteriumFullPrompt(),
    );
    final magFullV2F = trackDomain(
      'Magisterium v2',
      svc.loadMagisteriumFullV2(),
    );
    final magV2PromptF = trackDomain(
      'Magisterium v2 prompt',
      svc.loadMagisteriumFullV2Prompt(),
    );
    final srtF = trackOptional('Transkript', svc.loadSpeakerTimeline());
    var srtDone = false;
    unawaited(srtF.whenComplete(() => srtDone = true));
    // EN overlays — kreni paralelno; 404 → null kad prijevod nije producran.
    final summaryEnF = trackOptional('Sažetak (EN)', svc.loadSummaryEn());
    final articleEnF = trackOptional('Članak (EN)', svc.loadArticleEn());
    final magEnF = trackDomain('Magisterium (EN)', svc.loadMagisteriumEn());
    final magBatchEnF = trackDomain(
      'Magisterium batch (EN)',
      svc.loadMagisteriumBatchEn(),
    );
    final magFullV2EnF = trackDomain(
      'Magisterium v2 (EN)',
      svc.loadMagisteriumFullV2En(),
    );
    final mediaF = svc.resolveMedia();

    // Await all (required ones may throw)
    final info = await infoF;
    final summary = await summaryF;
    final outline = await outlineF;
    final article = await articleF;
    final mag = await magF;
    final magBatch = await magBatchF;
    final magFull = await magFullF;
    final magPrompt = await magPromptF;
    final magFullV2 = await magFullV2F;
    final magV2Prompt = await magV2PromptF;
    final summaryEn = await summaryEnF;
    final articleEn = await articleEnF;
    final magEn = await magEnF;
    final magBatchEn = await magBatchEnF;
    final magFullV2En = await magFullV2EnF;
    final media = await mediaF;

    EpisodeData build(SpeakerTimeline? srt) => EpisodeData(
      youtubeId: youtubeId,
      info: info,
      mediaKind: media.kind,
      summary: summary,
      summaryEn: summaryEn,
      outline: outline,
      article: article,
      articleEn: articleEn,
      magisterium: mag,
      magisteriumEn: magEn,
      magisteriumBatch: magBatch,
      magisteriumBatchEn: magBatchEn,
      magisteriumFull: magFull,
      magisteriumFullPrompt: magPrompt,
      magisteriumFullV2: magFullV2,
      magisteriumFullV2En: magFullV2En,
      magisteriumFullV2Prompt: magV2Prompt,
      speakerTimeline: srt,
      videoUri: media.uri,
    );

    if (onTimeline != null && article != null && !srtDone) {
      // Odgoda za jedan event-loop krug: pozivatelj mora stići postaviti
      // prvi rezultat prije nego mu javimo zamjenu.
      unawaited(srtF.then((srt) => Future<void>.delayed(Duration.zero, () {
            if (srt != null) onTimeline(build(srt));
          })));
      return build(null);
    }
    return build(await srtF);
  }
}
