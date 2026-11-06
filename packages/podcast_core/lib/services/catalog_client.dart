/// Klijent servisa kataloga (`katalog/`, Cloudflare Worker + D1 na
/// `domovina.ai/api/katalog/v1`). Kartica jedne epizode
/// (`GET /episodes/:id/card`), koju ekran epizode pita kad kanal ne zna iz
/// `episode.json` ni iz `index.json` (Tier 2 epizode), i ekran epizode u
/// obradi umjesto skidanja svih listinga; te epizode jednog dana
/// (`GET /days/:date`) za rail „Danas u korpusu” i ekran `/dani/:datum`; te
/// od S10 popis svih kanala (`GET /directory`, filtar „Svi” na `/channels`),
/// zaglavlje kanala (`GET /channels/:slug`) i njegove epizode
/// (`GET /channels/:slug/episodes`) za `/c/:slug` bez statičnog listinga.
///
/// Katalog je ubrzanje, ne uvjet: brend bez `Endpoints.catalog`, greška,
/// timeout i 404 daju „nema odgovora” i pozivatelj ide starim, statičnim
/// putem. Odluke: `katalog/docs/decisions.md` 800–808.
library;

import 'dart:async';

import '../brand/app_brand.dart';
import '../models/catalog_card.dart';
import '../models/catalog_channel_page.dart';
import '../models/catalog_day.dart';
import '../src/log.dart' show log;
import 'cdn_json_cache.dart';
import 'cdn_store.dart' show StoreBucket;

export '../models/catalog_card.dart';
export '../models/catalog_channel_page.dart';
export '../models/catalog_day.dart';

/// Ishod upita za karticu. [unavailable] (nema endpointa, mreža, timeout,
/// 5xx, nečitljiv odgovor) i [notFound] (katalog je odgovorio 404) pozivatelj
/// smije tretirati različito: na [notFound] katalog je dostupan, ali može
/// kasniti za listingom (odluka 804).
sealed class CatalogLookup {
  const CatalogLookup();

  /// Kartica kad je pronađena, inače `null`.
  CatalogCard? get card => null;
}

class CatalogFound extends CatalogLookup {
  const CatalogFound(this.found);
  final CatalogCard found;

  @override
  CatalogCard? get card => found;
}

class CatalogNotFound extends CatalogLookup {
  const CatalogNotFound();
}

class CatalogUnavailable extends CatalogLookup {
  const CatalogUnavailable();
}

/// Ishod upita za epizode dana. Prazan dan je [CatalogDayFound] s praznom
/// stranicom ([CatalogDayPage.isEmpty]), ne posebna grana: katalog je
/// odgovorio, samo još nema epizoda. [CatalogDayBadDate] je datum koji
/// klijent ili katalog (HTTP 400 `bad_date`) ne prihvaća, a
/// [CatalogDayUnavailable] sve ostalo (nema endpointa, mreža, timeout, 5xx,
/// nečitljiv odgovor).
sealed class CatalogDayLookup {
  const CatalogDayLookup();

  /// Stranica kad je katalog odgovorio, inače `null`.
  CatalogDayPage? get page => null;
}

class CatalogDayFound extends CatalogDayLookup {
  const CatalogDayFound(this.found);
  final CatalogDayPage found;

  @override
  CatalogDayPage? get page => found;
}

class CatalogDayBadDate extends CatalogDayLookup {
  const CatalogDayBadDate();
}

class CatalogDayUnavailable extends CatalogDayLookup {
  const CatalogDayUnavailable();
}

/// Ishod upita za stranicu popisa kanala (`/directory`, `/channels?tier=`).
/// Prazan popis je [CatalogDirectoryFound]; sve ostalo (nema endpointa,
/// mreža, timeout, 4xx/5xx, nečitljiv odgovor) je [CatalogDirectoryUnavailable].
sealed class CatalogDirectoryLookup {
  const CatalogDirectoryLookup();

  CatalogDirectoryPage? get page => null;
}

class CatalogDirectoryFound extends CatalogDirectoryLookup {
  const CatalogDirectoryFound(this.found);
  final CatalogDirectoryPage found;

  @override
  CatalogDirectoryPage? get page => found;
}

class CatalogDirectoryUnavailable extends CatalogDirectoryLookup {
  const CatalogDirectoryUnavailable();
}

/// Ishod upita za zaglavlje kanala. [CatalogChannelNotFound] je HTTP 404
/// (`channel_not_found`): katalog je odgovorio da kanala nema.
sealed class CatalogChannelLookup {
  const CatalogChannelLookup();

  CatalogChannelInfo? get channel => null;
}

class CatalogChannelFound extends CatalogChannelLookup {
  const CatalogChannelFound(this.found);
  final CatalogChannelInfo found;

  @override
  CatalogChannelInfo? get channel => found;
}

class CatalogChannelNotFound extends CatalogChannelLookup {
  const CatalogChannelNotFound();
}

class CatalogChannelUnavailable extends CatalogChannelLookup {
  const CatalogChannelUnavailable();
}

/// Ishod upita za stranicu epizoda kanala; ista podjela kao
/// [CatalogChannelLookup].
sealed class CatalogChannelEpisodesLookup {
  const CatalogChannelEpisodesLookup();

  CatalogChannelEpisodesPage? get page => null;
}

class CatalogChannelEpisodesFound extends CatalogChannelEpisodesLookup {
  const CatalogChannelEpisodesFound(this.found);
  final CatalogChannelEpisodesPage found;

  @override
  CatalogChannelEpisodesPage? get page => found;
}

class CatalogChannelEpisodesNotFound extends CatalogChannelEpisodesLookup {
  const CatalogChannelEpisodesNotFound();
}

class CatalogChannelEpisodesUnavailable extends CatalogChannelEpisodesLookup {
  const CatalogChannelEpisodesUnavailable();
}

/// Šav za testove: [instance] se smije zamijeniti podklasom koja prepisuje
/// [lookup] (ili instancom s vlastitim [baseUrl]/[cache]). Isti obrazac kao
/// `CdnJsonCache.instance`.
class CatalogClient {
  CatalogClient({
    String? baseUrl,
    CdnJsonCache? cache,
    this.timeout = const Duration(seconds: 4),
  }) : _baseUrl = baseUrl,
       _cache = cache;

  /// Zamjenjiv u testovima (`CatalogClient.instance = FakeCatalog()`).
  static CatalogClient instance = CatalogClient();

  /// `null` = čitaj `AppBrand.config.endpoints.catalog` pri svakom pozivu
  /// (brend se postavlja u `runPodcastApp`, poslije statičke inicijalizacije).
  final String? _baseUrl;
  final CdnJsonCache? _cache;
  final Duration timeout;

  String get baseUrl => _baseUrl ?? AppBrand.config.endpoints.catalog;

  /// Ima li brend katalog. `false` → [lookup] odmah vraća
  /// [CatalogUnavailable] bez ikakvog zahtjeva.
  bool get enabled => baseUrl.isNotEmpty;

  String cardUrl(String id) =>
      '$baseUrl/episodes/${Uri.encodeComponent(id)}/card';

  /// Najveća stranica koju katalog daje (`days.schema.json` `maxItems`).
  static const int maxDayLimit = 100;

  /// `GET {baseUrl}/days/<date>?limit=N[&cursor=<cursor>]`. [limit] se
  /// stisne na 1–[maxDayLimit].
  String dayUrl(String date, {int limit = 30, String? after}) {
    final n = limit.clamp(1, maxDayLimit);
    final cursor = after == null || after.isEmpty
        ? ''
        : '&cursor=${Uri.encodeQueryComponent(after)}';
    return '$baseUrl/days/${Uri.encodeComponent(date)}?limit=$n$cursor';
  }

  /// Kartica epizode [id], ili `null` kad je nema ili katalog nije dostupan.
  Future<CatalogCard?> card(String id) async => (await lookup(id)).card;

  /// Kartica s razlikom „nema je” / „ne znam”. Nikad ne baca.
  ///
  /// Ide kroz [CdnJsonCache.getMutable] (bucket `episode`, kao
  /// `episode.json`): spremljena kartica vraća se odmah i revalidira u
  /// pozadini; 404 i greške se ne spremaju.
  Future<CatalogLookup> lookup(String id) async {
    if (!enabled) return const CatalogUnavailable();
    final url = cardUrl(id);
    log('CatalogClient.card($id)');
    try {
      final body = await (_cache ?? CdnJsonCache.instance)
          .getMutable(url, bucket: StoreBucket.episode)
          .timeout(timeout);
      final card = CatalogCard.tryParse(body);
      if (card == null) {
        log('CatalogClient.card($id): nečitljiv odgovor');
        return const CatalogUnavailable();
      }
      log(
        'CatalogClient.card($id): ok, kanal ${card.channel?.slug ?? '-'} '
        '(tier ${card.channel?.tier ?? '-'}), katalog ${card.catalog}',
      );
      return CatalogFound(card);
    } on CdnHttpException catch (e) {
      if (e.statusCode == 404) {
        log('CatalogClient.card($id): 404');
        return const CatalogNotFound();
      }
      log('CatalogClient.card($id): HTTP ${e.statusCode}');
      return const CatalogUnavailable();
    } on TimeoutException {
      log('CatalogClient.card($id): timeout ${timeout.inMilliseconds} ms');
      return const CatalogUnavailable();
    } catch (e) {
      log('CatalogClient.card($id): greška $e');
      return const CatalogUnavailable();
    }
  }

  /// Epizode dana [date] (`YYYY-MM-DD`), stranica po stranica ([after] =
  /// [CatalogDayPage.next] prethodne). Nikad ne baca.
  ///
  /// Neispravan [date] vraća [CatalogDayBadDate] bez zahtjeva. Ide kroz
  /// [CdnJsonCache.getMutable] (bucket `episode`, ograničen broj zapisa, jer
  /// je svaki dan i svaki kursor svoj URL): spremljena stranica vraća se
  /// odmah i revalidira u pozadini, a [onUpdate] dobije novu kad se
  /// razlikuje (današnji dan se puni tijekom noći). 4xx i greške se ne
  /// spremaju.
  Future<CatalogDayLookup> day(
    String date, {
    int limit = 30,
    String? after,
    void Function(CatalogDayPage page)? onUpdate,
  }) async {
    if (!enabled) return const CatalogDayUnavailable();
    if (parseCatalogDate(date) == null) {
      log('CatalogClient.day($date): neispravan datum');
      return const CatalogDayBadDate();
    }
    final url = dayUrl(date, limit: limit, after: after);
    final tag = after == null ? date : '$date, after';
    log('CatalogClient.day($tag)');
    try {
      final body = await (_cache ?? CdnJsonCache.instance)
          .getMutable(
            url,
            bucket: StoreBucket.episode,
            onUpdate: onUpdate == null
                ? null
                : (fresh) {
                    final page = CatalogDayPage.tryParse(fresh, date: date);
                    if (page != null) onUpdate(page);
                  },
          )
          .timeout(timeout);
      final page = CatalogDayPage.tryParse(body, date: date);
      if (page == null) {
        log('CatalogClient.day($tag): nečitljiv odgovor');
        return const CatalogDayUnavailable();
      }
      log(
        'CatalogClient.day($tag): ${page.items.length} epizoda'
        '${page.hasMore ? ', ima dalje' : ''}, katalog ${page.catalog}',
      );
      return CatalogDayFound(page);
    } on CdnHttpException catch (e) {
      log('CatalogClient.day($tag): HTTP ${e.statusCode}');
      return e.statusCode == 400
          ? const CatalogDayBadDate()
          : const CatalogDayUnavailable();
    } on TimeoutException {
      log('CatalogClient.day($tag): timeout ${timeout.inMilliseconds} ms');
      return const CatalogDayUnavailable();
    } catch (e) {
      log('CatalogClient.day($tag): greška $e');
      return const CatalogDayUnavailable();
    }
  }

  /// Najveća stranica popisa kanala i epizoda kanala (`maxItems` u
  /// `directory.schema.json` i `channel-episodes.schema.json`).
  static const int maxListLimit = 100;

  static String _page(int limit, String? after) {
    final n = limit.clamp(1, maxListLimit);
    final cursor = after == null || after.isEmpty
        ? ''
        : '&cursor=${Uri.encodeQueryComponent(after)}';
    return 'limit=$n$cursor';
  }

  /// `GET {baseUrl}/directory?limit=N[&cursor=…]` (oba tiera), ili
  /// `GET {baseUrl}/channels?tier=T&limit=N[&cursor=…]` kad je [tier] zadan.
  String directoryUrl({int limit = 30, String? after, int? tier}) =>
      tier == null
      ? '$baseUrl/directory?${_page(limit, after)}'
      : '$baseUrl/channels?tier=$tier&${_page(limit, after)}';

  /// `GET {baseUrl}/channels/<slug>`; slug ide doslovno (enkodiran).
  String channelUrl(String slug) =>
      '$baseUrl/channels/${Uri.encodeComponent(slug)}';

  /// `GET {baseUrl}/channels/<slug>/episodes?limit=N[&cursor=…]`.
  String channelEpisodesUrl(String slug, {int limit = 30, String? after}) =>
      '${channelUrl(slug)}/episodes?${_page(limit, after)}';

  /// Zajednički put novih upita: [CdnJsonCache.getMutable] (bucket
  /// `episode`, ograničen broj zapisa jer je svaka stranica svoj URL),
  /// timeout, parser. `value` je pročitan odgovor; inače `status` nosi HTTP
  /// kod kad ga ima (404 pozivatelj čita kao „nema ga”). Nikad ne baca.
  Future<({T? value, int? status})> _getParsed<T>(
    String url,
    String tag,
    T? Function(String body) parse, {
    void Function(T value)? onUpdate,
  }) async {
    try {
      final body = await (_cache ?? CdnJsonCache.instance)
          .getMutable(
            url,
            bucket: StoreBucket.episode,
            onUpdate: onUpdate == null
                ? null
                : (fresh) {
                    final v = parse(fresh);
                    if (v != null) onUpdate(v);
                  },
          )
          .timeout(timeout);
      final value = parse(body);
      if (value == null) log('$tag: nečitljiv odgovor');
      return (value: value, status: null);
    } on CdnHttpException catch (e) {
      log('$tag: HTTP ${e.statusCode}');
      return (value: null, status: e.statusCode);
    } on TimeoutException {
      log('$tag: timeout ${timeout.inMilliseconds} ms');
      return (value: null, status: null);
    } catch (e) {
      log('$tag: greška $e');
      return (value: null, status: null);
    }
  }

  /// Stranica popisa kanala s barem jednom obrađenom epizodom, najsvježiji
  /// prvi ([after] = [CatalogDirectoryPage.next] prethodne). [tier] suzi na
  /// `/channels?tier=`. Nikad ne baca; brend bez kataloga ne šalje ništa.
  Future<CatalogDirectoryLookup> directory({
    int limit = 30,
    String? after,
    int? tier,
    void Function(CatalogDirectoryPage page)? onUpdate,
  }) async {
    if (!enabled) return const CatalogDirectoryUnavailable();
    final tag =
        'CatalogClient.directory(${tier == null ? '' : 'tier $tier'}'
        '${after == null ? '' : ', after'})';
    log(tag);
    final got = await _getParsed(
      directoryUrl(limit: limit, after: after, tier: tier),
      tag,
      CatalogDirectoryPage.tryParse,
      onUpdate: onUpdate,
    );
    final page = got.value;
    if (page == null) return const CatalogDirectoryUnavailable();
    log(
      '$tag: ${page.items.length} kanala'
      '${page.hasMore ? ', ima dalje' : ''}, katalog ${page.catalog}',
    );
    return CatalogDirectoryFound(page);
  }

  /// Zaglavlje kanala [slug] (doslovno, kako ga katalog zna). Nikad ne baca.
  Future<CatalogChannelLookup> channel(String slug) async {
    if (!enabled) return const CatalogChannelUnavailable();
    if (slug.isEmpty) return const CatalogChannelNotFound();
    final tag = 'CatalogClient.channel($slug)';
    log(tag);
    final got = await _getParsed(
      channelUrl(slug),
      tag,
      CatalogChannelInfo.tryParseResponse,
    );
    final info = got.value;
    if (info != null) {
      log('$tag: ok, tier ${info.tier}, ${info.processedCount} epizoda');
      return CatalogChannelFound(info);
    }
    return got.status == 404
        ? const CatalogChannelNotFound()
        : const CatalogChannelUnavailable();
  }

  /// Epizode kanala [slug], stranica po stranica. Nikad ne baca.
  Future<CatalogChannelEpisodesLookup> channelEpisodes(
    String slug, {
    int limit = 30,
    String? after,
    void Function(CatalogChannelEpisodesPage page)? onUpdate,
  }) async {
    if (!enabled) return const CatalogChannelEpisodesUnavailable();
    if (slug.isEmpty) return const CatalogChannelEpisodesNotFound();
    final tag =
        'CatalogClient.channelEpisodes($slug${after == null ? '' : ', after'})';
    log(tag);
    final got = await _getParsed(
      channelEpisodesUrl(slug, limit: limit, after: after),
      tag,
      (body) => CatalogChannelEpisodesPage.tryParse(body, slug: slug),
      onUpdate: onUpdate,
    );
    final page = got.value;
    if (page != null) {
      log(
        '$tag: ${page.items.length} epizoda'
        '${page.hasMore ? ', ima dalje' : ''}, katalog ${page.catalog}',
      );
      return CatalogChannelEpisodesFound(page);
    }
    return got.status == 404
        ? const CatalogChannelEpisodesNotFound()
        : const CatalogChannelEpisodesUnavailable();
  }
}
