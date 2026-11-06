import 'dart:convert';

import 'catalog_card.dart';

/// Jedna stranica `GET /days/:date` (ugovor `katalog/contract/v1/days.schema.json`):
/// epizode jednog dana (`date` = `published_date`), oba tiera, bez varijanti.
///
/// [items] je prazan kad za dan još nema epizoda — to je odgovor, ne kvar
/// (pipeline radi noću, pa je današnji dan do jutra prazan).
class CatalogDayPage {
  /// Dan stranice, `YYYY-MM-DD` (kako je zatražen).
  final String date;
  final List<CatalogCard> items;

  /// Neproziran keyset kursor za sljedeću stranicu; `null` na zadnjoj.
  final String? next;

  /// ID zadnjeg uvoza (`catalog`) — samo za log.
  final String? catalog;

  const CatalogDayPage({
    required this.date,
    required this.items,
    this.next,
    this.catalog,
  });

  bool get isEmpty => items.isEmpty;
  bool get hasMore => next != null;

  /// Tijelo odgovora → stranica, ili `null` kad tijelo nije JSON, verzija
  /// nije [CatalogCard.supportedVersion] ili `items` nije lista. Pojedina
  /// nečitljiva stavka se preskače (ostatak stranice vrijedi). Kursor koji
  /// nije neprazan string znači „nema dalje”. Nikad ne baca.
  static CatalogDayPage? tryParse(String body, {required String date}) {
    try {
      final json = jsonDecode(body);
      if (json is! Map) return null;
      if (json['version'] != CatalogCard.supportedVersion) return null;
      final rawItems = json['items'];
      if (rawItems is! List) return null;
      final catalog = json['catalog'];
      final catalogId = catalog is String ? catalog : null;
      final items = <CatalogCard>[
        for (final raw in rawItems)
          ?CatalogCard.fromItem(raw, catalog: catalogId),
      ];
      final next = json['next'];
      return CatalogDayPage(
        date: date,
        items: items,
        next: next is String && next.isNotEmpty ? next : null,
        catalog: catalogId,
      );
    } catch (_) {
      return null;
    }
  }
}

final RegExp _isoDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// `YYYY-MM-DD` → lokalni datum (ponoć), ili `null` kad oblik nije točan ili
/// datum ne postoji (`2026-02-30`, `2026-13-01`). Strogo: bez vremena, bez
/// zona, bez jednoznamenkastih dijelova — isti oblik koji katalog prihvaća.
DateTime? parseCatalogDate(String raw) {
  final m = _isoDate.firstMatch(raw);
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  final date = DateTime(y, mo, d);
  if (date.year != y || date.month != mo || date.day != d) return null;
  return date;
}

/// Lokalni datum → `YYYY-MM-DD`.
String formatCatalogDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Dan pomaknut za [days] kalendarskih dana. Ide kroz konstruktor, ne kroz
/// `Duration`, da prijelaz na ljetno/zimsko vrijeme ne pomakne datum.
DateTime shiftCatalogDate(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

/// Današnji lokalni datum (ponoć).
DateTime catalogToday([DateTime? now]) {
  final n = now ?? DateTime.now();
  return DateTime(n.year, n.month, n.day);
}
