import 'package:podcast_core/services/catalog_client.dart';

/// Lažni klijent kataloga za `/days/:date` (rail „Danas u korpusu” i ekran
/// `/dani/:datum`). Odgovori po datumu i kursoru: ključ je `datum` za prvu
/// stranicu, `datum|kursor` za sljedeće. Datum kojeg nema → prazan dan.
/// [unavailable] = svaki upit vraća [CatalogDayUnavailable].
class FakeCatalogDays extends CatalogClient {
  FakeCatalogDays({
    Map<String, CatalogDayLookup>? pages,
    this.unavailable = false,
    String baseUrl = 'https://domovina.ai/api/katalog/v1',
  }) : pages = pages ?? {},
       super(baseUrl: baseUrl);

  final Map<String, CatalogDayLookup> pages;
  bool unavailable;

  /// Revalidacija: stranica koju [day] preda kroz `onUpdate` nakon što je
  /// vratio onu iz [pages] (kao `CdnJsonCache.getMutable` kad se mreža
  /// razlikuje od diska). Ključ isti kao u [pages].
  final Map<String, CatalogDayPage> revalidated = {};

  /// Zadnji `onUpdate` po ključu, da test revalidaciju okine kad hoće.
  final Map<String, void Function(CatalogDayPage)> onUpdates = {};

  /// Upiti redom, u obliku ključa iz [pages].
  final List<String> asked = [];

  @override
  Future<CatalogDayLookup> day(
    String date, {
    int limit = 30,
    String? after,
    void Function(CatalogDayPage page)? onUpdate,
  }) async {
    if (!enabled) return const CatalogDayUnavailable();
    final key = after == null ? date : '$date|$after';
    asked.add(key);
    if (unavailable) return const CatalogDayUnavailable();
    if (parseCatalogDate(date) == null) return const CatalogDayBadDate();
    if (onUpdate != null) onUpdates[key] = onUpdate;
    final fresh = revalidated[key];
    if (fresh != null && onUpdate != null) {
      Future<void>.delayed(Duration.zero, () => onUpdate(fresh));
    }
    return pages[key] ??
        CatalogDayFound(CatalogDayPage(date: date, items: const []));
  }
}

CatalogCard fakeDayCard(
  String id, {
  String? title,
  String? channel,
  String date = '2026-11-05',
  int tier = 1,
}) => CatalogCard(
  id: id,
  title: title ?? 'Epizoda $id',
  tier: tier,
  date: date,
  channel: channel == null
      ? null
      : CatalogChannel(slug: channel.toLowerCase(), name: channel, tier: tier),
);

CatalogDayLookup fakeDayPage(
  String date,
  List<CatalogCard> items, {
  String? next,
}) => CatalogDayFound(CatalogDayPage(date: date, items: items, next: next));
