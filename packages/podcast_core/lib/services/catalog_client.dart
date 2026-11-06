/// Klijent servisa kataloga (`katalog/`, Cloudflare Worker + D1 na
/// `domovina.ai/api/katalog/v1`). Za sada samo kartica jedne epizode
/// (`GET /episodes/:id/card`), koju ekran epizode pita kad kanal ne zna iz
/// `episode.json` ni iz `index.json` (Tier 2 epizode), i ekran epizode u
/// obradi umjesto skidanja svih listinga.
///
/// Katalog je ubrzanje, ne uvjet: brend bez `Endpoints.catalog`, greška,
/// timeout i 404 daju „nema odgovora” i pozivatelj ide starim, statičnim
/// putem. Odluke: `katalog/docs/decisions.md` 800–808.
library;

import 'dart:async';

import '../brand/app_brand.dart';
import '../models/catalog_card.dart';
import '../src/log.dart' show log;
import 'cdn_json_cache.dart';
import 'cdn_store.dart' show StoreBucket;

export '../models/catalog_card.dart';

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
}
