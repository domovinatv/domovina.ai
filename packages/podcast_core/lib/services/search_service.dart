import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../brand/app_brand.dart';
import '../src/log.dart' show log;

/// Jedan rezultat semantičke pretrage (chunk transkripta/sažetka).
///
/// Mapira se 1:1 na `SearchResult` iz domovina-rag `/api/search` endpointa.
class SemanticResult {
  final String chunkId;
  final String youtubeId;
  final String channel;
  final String uploadDate;
  final String? episodeTitle;
  final List<String> speakers;
  final double startTs;
  final double endTs;
  final String text;
  final double score;
  final String deepLink;

  const SemanticResult({
    required this.chunkId,
    required this.youtubeId,
    required this.channel,
    required this.uploadDate,
    required this.episodeTitle,
    required this.speakers,
    required this.startTs,
    required this.endTs,
    required this.text,
    required this.score,
    required this.deepLink,
  });

  /// Početak u sekundama (zaokruženo) — za `/v/:id/t/:sec` navigaciju.
  int get startSeconds => startTs.floor().clamp(0, 1 << 30);

  /// True za article_summary chunkove (start=end=0, bez govornika i timestampa).
  bool get isSummary => startTs == 0 && endTs == 0;

  /// Kratki snippet za prikaz — sažetci imaju "Naslov:\n\nSažetak:" prefiks
  /// koji izbacujemo, dijaloški chunkovi imaju "[Govornik] ..." koji čistimo.
  String get snippet {
    var t = text.trim();
    // Sažetak: uzmi tekst nakon "Sažetak:" ako postoji.
    final sazIdx = t.indexOf('Sažetak:');
    if (sazIdx >= 0) {
      t = t.substring(sazIdx + 'Sažetak:'.length).trim();
    } else {
      // Dijalog: makni "Tema: ..." prvi red ako postoji.
      final temaMatch = RegExp(r'^Tema:.*\n+', multiLine: false).firstMatch(t);
      if (temaMatch != null) t = t.substring(temaMatch.end).trim();
    }
    // Očisti markdown bold/italic markere (sažeci ih sadrže) i višak razmaka.
    t = t.replaceAll('**', '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  factory SemanticResult.fromJson(Map<String, dynamic> json) {
    final rawSpeakers = json['speakers'] as List<dynamic>? ?? [];
    return SemanticResult(
      chunkId: json['chunk_id'] as String? ?? '',
      youtubeId: json['youtube_id'] as String? ?? '',
      channel: json['channel'] as String? ?? '',
      uploadDate: json['upload_date'] as String? ?? '',
      episodeTitle: json['episode_title'] as String?,
      speakers: rawSpeakers.map((s) => s.toString()).toList(),
      startTs: (json['start_ts'] as num?)?.toDouble() ?? 0,
      endTs: (json['end_ts'] as num?)?.toDouble() ?? 0,
      text: json['text'] as String? ?? '',
      score: (json['score'] as num?)?.toDouble() ?? 0,
      deepLink: json['deep_link'] as String? ?? '',
    );
  }
}

/// Klijent za deterministički semantic search endpoint (domovina-rag).
///
/// NE koristi LLM — vraća rankirane chunkove direktno iz vektorskog indeksa.
/// Endpoint je čisti HTTP GET, pa radi i na webu (--wasm) i na native-u.
class SearchService {
  /// Base URL semantic search API-ja — host je `endpoints.rag` aktivnog brenda.
  static String get _endpoint => '${AppBrand.config.endpoints.rag}/api/search';

  static final http.Client _client = http.Client();

  /// Semantička pretraga. Vraća praznu listu na grešku/timeout (graceful) —
  /// pozivatelj može fallbackati na lokalne rezultate.
  ///
  /// [includeSummaries] false → samo dijaloški chunkovi (s timestampom).
  ///
  /// Kad se [abortTrigger] završi, zahtjev se prekida (korisnik je u
  /// međuvremenu promijenio upit) i vraća se prazna lista. Inače bi svaki
  /// zastarjeli upit i dalje držao vezu dok embedder ne odgovori.
  static Future<List<SemanticResult>> search(
    String query, {
    int limit = 12,
    String? channel,
    bool includeSummaries = true,
    Duration timeout = const Duration(seconds: 8),
    Future<void>? abortTrigger,
  }) async {
    final q = query.trim();
    if (q.length < 2) return [];

    final params = <String, String>{
      'q': q,
      'limit': '$limit',
      'channel': ?channel,
      if (!includeSummaries) 'include_summaries': 'false',
    };
    final uri = Uri.parse(_endpoint).replace(queryParameters: params);

    try {
      final req = http.AbortableRequest('GET', uri, abortTrigger: abortTrigger);
      final resp = await _client
          .send(req)
          .then(http.Response.fromStream)
          .timeout(timeout);
      if (resp.statusCode != 200) {
        log('SearchService: HTTP ${resp.statusCode} za "$q"');
        return [];
      }
      final body = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final results = (body['results'] as List<dynamic>? ?? [])
          .map((e) => SemanticResult.fromJson(e as Map<String, dynamic>))
          .toList();
      // Server već vraća silazno po score (ORDER BY cosineDistance ASC), ali
      // defenzivno re-sortiramo da UI ranking bude zajamčen.
      results.sort((a, b) => b.score.compareTo(a.score));
      log('SearchService: ${results.length} rezultata za "$q"');
      return results;
    } on http.RequestAbortedException {
      return [];
    } on TimeoutException {
      log('SearchService: timeout za "$q"');
      return [];
    } catch (e) {
      log('SearchService: greška za "$q": $e');
      return [];
    }
  }
}
