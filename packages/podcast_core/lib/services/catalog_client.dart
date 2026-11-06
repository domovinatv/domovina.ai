/// Klijent servisa kataloga (`katalog/`, Cloudflare Worker + D1 na
/// `domovina.ai/api/katalog/v1`). Kartica jedne epizode
/// (`GET /episodes/:id/card`), koju ekran epizode pita kad kanal ne zna iz
/// `episode.json` ni iz `index.json` (Tier 2 epizode), i ekran epizode u
/// obradi umjesto skidanja svih listinga; te epizode jednog dana
/// (`GET /days/:date`) za rail „Danas u korpusu” i ekran `/dani/:datum`.
///
/// Katalog je ubrzanje, ne uvjet: brend bez `Endpoints.catalog`, greška,
/// timeout i 404 daju „nema odgovora” i pozivatelj ide starim, statičnim
/// putem. Odluke: `katalog/docs/decisions.md` 800–808.
library;

import 'dart:async';

import '../brand/app_brand.dart';
import '../models/catalog_card.dart';
import '../models/catalog_day.dart';
import '../src/log.dart' show log;
import 'cdn_json_cache.dart';
import 'cdn_store.dart' show StoreBucket;

export '../models/catalog_card.dart';
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

  /// `GET {baseUrl}/days/<date>?limit=N[&after=<cursor>]`. [limit] se
  /// stisne na 1–[maxDayLimit].
  String dayUrl(String date, {int limit = 30, String? after}) {
    final n = limit.clamp(1, maxDayLimit);
    final cursor = after == null || after.isEmpty
        ? ''
        : '&after=${Uri.encodeQueryComponent(after)}';
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
}
