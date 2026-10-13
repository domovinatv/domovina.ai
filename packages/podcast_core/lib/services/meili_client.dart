import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../brand/app_brand.dart';
import '../src/log.dart' show log;

/// Klijent za Meilisearch keyword (egzaktna riječ + typo-tolerant) pretragu
/// podcast epizoda. KOMPLEMENTARNO semantičkoj MCP pretrazi (vidi
/// search_service.dart), ne miješati.
///
/// Konfiguracija preko --dart-define (deploy.sh embeda u build):
///   MEILI_URL         — npr. https://search.domovina.ai (default: lokalni dev)
///   MEILI_SEARCH_KEY  — READ-ONLY search-only ključ (actions:[search]).
///                       NIKAD master key. Siguran za frontend bundle jer ne
///                       može pisati/admin. Generira se preko
///                       domovina-rag/scripts/meili-provision-keys.sh.
///
/// Search-only ključ je deterministički (HMAC master+uid) pa je IDENTIČAN na
/// lokalnom i cloud Meiliju — default ispod radi protiv oba.
class MeiliClient {
  // Default = lokalni dev search-only key (deterministički, uid 39ed0b6b…).
  // Override u prod buildu: --dart-define=MEILI_SEARCH_KEY=...
  static const String _searchKey = String.fromEnvironment(
    'MEILI_SEARCH_KEY',
    defaultValue:
        'd4e39f13270b43c3210cfa005d80fdd3390fc7948be0db0c0f03d3cffa4a780f',
  );

  /// Override: --dart-define=MEILI_URL=https://search.domovina.ai
  static const String _urlOverride = String.fromEnvironment('MEILI_URL');

  static const String _pre = '<em>';
  static const String _post = '</em>';

  static final http.Client _http = http.Client();

  /// `--dart-define=MEILI_URL` (lokalni dev: `http://localhost:7700`, na
  /// Android emulatoru `http://10.0.2.2:7700`), inače Meili aktivnog brenda.
  ///
  /// Do 13.10.2026. je bez define-a gađao localhost. Web deploy ga postavlja
  /// iz `.env`, ali svaki build bez njega (nightly za storeove, `flutter run`)
  /// tiho je imao mrtvu full-text pretragu.
  static String get baseUrl =>
      _urlOverride.isNotEmpty ? _urlOverride : AppBrand.config.endpoints.meili;

  static Map<String, String> get _headers => {
        'Authorization': 'Bearer $_searchKey',
        'Content-Type': 'application/json',
      };

  /// Keyword pretraga. [channel] filtrira po slugu kanala (npr. 'ad_deum_podcast').
  static Future<MeiliResponse> search(
    String q, {
    String? channel,
    int limit = 20,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final body = <String, dynamic>{
      'q': q,
      'limit': limit,
      // Ne dohvaćaj puni article_text (velik) — samo croppani _formatted snippet.
      'attributesToRetrieve': [
        'youtube_id',
        'title',
        'channel',
        'upload_date',
        'section_titles',
        'deep_link',
      ],
      'attributesToHighlight': ['title', 'article_text', 'section_titles'],
      'attributesToCrop': ['article_text'],
      'cropLength': 32,
      'highlightPreTag': _pre,
      'highlightPostTag': _post,
      if (channel != null) 'filter': "channel = '$channel'",
    };

    final resp = await _http
        .post(
          Uri.parse('$baseUrl/indexes/episodes/search'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(timeout);

    if (resp.statusCode != 200) {
      throw MeiliException('HTTP ${resp.statusCode}: ${resp.body}');
    }
    final json = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    return MeiliResponse.fromJson(json);
  }

  /// Distribucija po kanalu (za facet chipove). Vraća slug → broj epizoda.
  static Future<Map<String, int>> channelFacets() async {
    final resp = await _http
        .post(
          Uri.parse('$baseUrl/indexes/episodes/search'),
          headers: _headers,
          body: jsonEncode({
            'q': '',
            'facets': ['channel'],
            'limit': 0,
          }),
        )
        .timeout(const Duration(seconds: 5));
    if (resp.statusCode != 200) {
      throw MeiliException('HTTP ${resp.statusCode}: ${resp.body}');
    }
    final json = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final dist = (json['facetDistribution']
            as Map<String, dynamic>?)?['channel'] as Map<String, dynamic>? ??
        {};
    return dist.map((k, v) => MapEntry(k, (v as num).toInt()));
  }

  /// Health check — vraća false ako Meili ne sluša (npr. docker nije gore).
  static Future<bool> ping() async {
    try {
      final r = await _http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 3));
      return r.statusCode == 200;
    } catch (e) {
      log('MeiliClient.ping fail: $e');
      return false;
    }
  }
}

class MeiliException implements Exception {
  final String message;
  MeiliException(this.message);
  @override
  String toString() => 'MeiliException: $message';
}

class MeiliResponse {
  final List<MeiliHit> hits;
  final int estimatedTotalHits;
  final int processingTimeMs;
  final Map<String, int> channelFacets;

  const MeiliResponse({
    required this.hits,
    required this.estimatedTotalHits,
    required this.processingTimeMs,
    this.channelFacets = const {},
  });

  factory MeiliResponse.fromJson(Map<String, dynamic> json) {
    final dist = (json['facetDistribution']
        as Map<String, dynamic>?)?['channel'] as Map<String, dynamic>?;
    return MeiliResponse(
      hits: (json['hits'] as List<dynamic>? ?? [])
          .map((e) => MeiliHit.fromJson(e as Map<String, dynamic>))
          .toList(),
      estimatedTotalHits: (json['estimatedTotalHits'] as num?)?.toInt() ?? 0,
      processingTimeMs: (json['processingTimeMs'] as num?)?.toInt() ?? 0,
      channelFacets:
          dist?.map((k, v) => MapEntry(k, (v as num).toInt())) ?? const {},
    );
  }
}

class MeiliHit {
  final String youtubeId;
  final String title;
  final String channel;
  final String uploadDate;
  final List<String> sectionTitles;
  final String deepLink;
  // `_formatted` polja s <em> highlight tagovima (i croppani article_text).
  final String formattedTitle;
  final String formattedArticleSnippet;
  // Naslovi sekcija s <em> tagovima. `article_text` NIJE u displayedAttributes
  // indeksa, pa je `formattedArticleSnippet` u praksi prazan — pogođeni
  // naslovi sekcija su jedini pokazatelj GDJE u epizodi je pogodak.
  final List<String> formattedSectionTitles;

  const MeiliHit({
    required this.youtubeId,
    required this.title,
    required this.channel,
    required this.uploadDate,
    required this.sectionTitles,
    required this.deepLink,
    required this.formattedTitle,
    required this.formattedArticleSnippet,
    this.formattedSectionTitles = const [],
  });

  factory MeiliHit.fromJson(Map<String, dynamic> json) {
    final fmt = json['_formatted'] as Map<String, dynamic>? ?? const {};
    return MeiliHit(
      youtubeId: json['youtube_id'] as String? ?? json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      channel: json['channel'] as String? ?? '',
      uploadDate: json['upload_date'] as String? ?? '',
      sectionTitles: (json['section_titles'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      deepLink: json['deep_link'] as String? ?? '',
      formattedTitle: fmt['title'] as String? ?? json['title'] as String? ?? '',
      formattedArticleSnippet: fmt['article_text'] as String? ?? '',
      formattedSectionTitles: (fmt['section_titles'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}
