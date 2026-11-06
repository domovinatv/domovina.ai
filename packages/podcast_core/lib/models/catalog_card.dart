import 'dart:convert';

/// Kanal epizode kako ga vidi katalog (`katalog/`, odluke 705–707):
/// `{slug, name, tier}`. Isti oblik dolazi iz `GET /episodes/:id/card`
/// (`item.channel`) i iz `data/<id>/episode.json` (`channel`, od 6. 11. 2026.
/// samo za nove epizode).
///
/// [tier] je tier KANALA, ne epizode: Tier 2 epizoda na praćenom kanalu ima
/// `tier: 1`. Slug Tier 1 kanala je ID kanala s podvlakom (`iva_kraljevic`),
/// a ruta `/c/:slug` ga piše s crticom ([routeSlug]). Tier 2 kanal (`tribina`)
/// rute još nema (dolazi u S10), pa [hasChannelRoute] vraća `false`.
class CatalogChannel {
  final String slug;
  final String name;
  final int tier;

  const CatalogChannel({
    required this.slug,
    required this.name,
    required this.tier,
  });

  /// Postoji li za kanal ekran `/c/:slug`. Danas samo Tier 1 (odluka 802).
  bool get hasChannelRoute => tier == 1;

  /// Slug u obliku rute (`iva-kraljevic`), kao `_resolveChannelSlug` na
  /// ekranu epizode.
  String get routeSlug => slug.replaceAll('_', '-');

  /// `null` za sve što nije objekt s nepraznim `slug`/`name` (string) i
  /// cjelobrojnim `tier`. Nepoznati ključevi se ignoriraju. Nikad ne baca.
  static CatalogChannel? tryParse(Object? json) {
    if (json is! Map) return null;
    final slug = json['slug'];
    final name = json['name'];
    final tier = json['tier'];
    if (slug is! String || slug.isEmpty) return null;
    if (name is! String || name.isEmpty) return null;
    if (tier is! num || tier != tier.toInt()) return null;
    return CatalogChannel(slug: slug, name: name, tier: tier.toInt());
  }

  @override
  bool operator ==(Object other) =>
      other is CatalogChannel &&
      other.slug == slug &&
      other.name == name &&
      other.tier == tier;

  @override
  int get hashCode => Object.hash(slug, name, tier);

  @override
  String toString() => 'CatalogChannel($slug, $name, tier $tier)';
}

/// Kartica epizode iz `GET /episodes/:id/card` (ugovor
/// `katalog/contract/v1/card.schema.json`). Klijent čita samo polja koja
/// ekran treba; ostala (`p`, `magisterium_score`, `variant_of`…) ignorira.
class CatalogCard {
  final String id;
  final String title;
  final String? titleHr;

  /// `YYYY-MM-DD` ili `null` kad datum nije poznat.
  final String? date;

  /// Tier EPIZODE (1 = u listingu praćenog kanala, 2 = ad hoc / `_unlisted`).
  final int tier;

  /// `null` = katalog epizodu ima, ali bez kanala.
  final CatalogChannel? channel;

  /// Osnovni ID kad je epizoda eksperimentalna varijanta (katalog odluka
  /// 302): [id] je tada sintetički (`OspwepfLO_2`), a YouTube zna samo ovaj.
  final String? variantOf;

  /// `version` odgovora i ID zadnjeg uvoza (`catalog`) — samo za log.
  final String? catalog;

  const CatalogCard({
    required this.id,
    required this.title,
    required this.tier,
    this.titleHr,
    this.date,
    this.channel,
    this.variantOf,
    this.catalog,
  });

  /// Naslov za prikaz — isto pravilo kao `ChannelVideo.displayTitle`.
  String get displayTitle => titleHr ?? title;

  static const String supportedVersion = '1';

  /// Tijelo odgovora `GET /episodes/:id/card` → kartica, ili `null` kad
  /// tijelo nije JSON, verzija nije [supportedVersion] ili obavezna polja
  /// (`item.id`, `item.title`, `item.tier`) nedostaju ili imaju krivi tip.
  /// Neobavezna polja krivog tipa postaju `null`. Nikad ne baca.
  static CatalogCard? tryParse(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map) return null;
      if (json['version'] != supportedVersion) return null;
      final catalog = json['catalog'];
      return fromItem(json['item'], catalog: catalog is String ? catalog : null);
    } catch (_) {
      return null;
    }
  }

  /// Jedna kartica (`card.schema.json`) — `item` iz `/episodes/:id/card` ili
  /// stavka iz `items` popisa (`/days/:date`). Ista pravila kao [tryParse]:
  /// `null` kad obavezna polja nedostaju, neobavezna krivog tipa → `null`.
  static CatalogCard? fromItem(Object? item, {String? catalog}) {
    if (item is! Map) return null;
    final id = item['id'];
    final title = item['title'];
    final tier = item['tier'];
    if (id is! String || id.isEmpty) return null;
    if (title is! String || title.isEmpty) return null;
    if (tier is! num || tier != tier.toInt()) return null;
    final titleHr = item['title_hr'];
    final date = item['date'];
    final variantOf = item['variant_of'];
    return CatalogCard(
      id: id,
      title: title,
      titleHr: titleHr is String && titleHr.isNotEmpty ? titleHr : null,
      date: date is String && date.isNotEmpty ? date : null,
      tier: tier.toInt(),
      channel: CatalogChannel.tryParse(item['channel']),
      variantOf: variantOf is String && variantOf.isNotEmpty ? variantOf : null,
      catalog: catalog,
    );
  }
}
