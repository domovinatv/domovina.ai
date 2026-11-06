import 'package:podcast_core/services/catalog_client.dart';

/// Lažni klijent kataloga za popis kanala (`/directory`), zaglavlje kanala
/// (`/channels/:slug`) i njegove epizode (`/channels/:slug/episodes`), S10.
///
/// Stranice su po kursoru: ključ `''` je prva stranica, inače kursor.
/// Kanal kojeg nema u [channels] je 404; [unavailable] = svaki upit je
/// „nedostupno”. [asked] bilježi upite redom (`directory|<kursor>`,
/// `channel|<slug>`, `episodes|<slug>|<kursor>`).
class FakeCatalogChannels extends CatalogClient {
  FakeCatalogChannels({
    Map<String, CatalogDirectoryLookup>? directoryPages,
    Map<String, CatalogChannelInfo>? channels,
    Map<String, CatalogChannelEpisodesLookup>? episodePages,
    this.unavailable = false,
    String baseUrl = 'https://domovina.ai/api/katalog/v1',
  }) : directoryPages = directoryPages ?? {},
       channels = channels ?? {},
       episodePages = episodePages ?? {},
       super(baseUrl: baseUrl);

  final Map<String, CatalogDirectoryLookup> directoryPages;
  final Map<String, CatalogChannelInfo> channels;

  /// Ključ `<slug>` za prvu stranicu, `<slug>|<kursor>` za sljedeće.
  final Map<String, CatalogChannelEpisodesLookup> episodePages;
  bool unavailable;
  final List<String> asked = [];

  @override
  Future<CatalogDirectoryLookup> directory({
    int limit = 30,
    String? after,
    int? tier,
    void Function(CatalogDirectoryPage page)? onUpdate,
  }) async {
    if (!enabled) return const CatalogDirectoryUnavailable();
    asked.add('directory|${after ?? ''}');
    if (unavailable) return const CatalogDirectoryUnavailable();
    return directoryPages[after ?? ''] ??
        const CatalogDirectoryFound(CatalogDirectoryPage(items: []));
  }

  @override
  Future<CatalogChannelLookup> channel(String slug) async {
    if (!enabled) return const CatalogChannelUnavailable();
    asked.add('channel|$slug');
    if (unavailable) return const CatalogChannelUnavailable();
    final c = channels[slug];
    return c == null ? const CatalogChannelNotFound() : CatalogChannelFound(c);
  }

  @override
  Future<CatalogChannelEpisodesLookup> channelEpisodes(
    String slug, {
    int limit = 30,
    String? after,
    void Function(CatalogChannelEpisodesPage page)? onUpdate,
  }) async {
    if (!enabled) return const CatalogChannelEpisodesUnavailable();
    asked.add('episodes|$slug|${after ?? ''}');
    if (unavailable) return const CatalogChannelEpisodesUnavailable();
    final key = after == null ? slug : '$slug|$after';
    final page = episodePages[key];
    if (page != null) return page;
    return channels.containsKey(slug)
        ? CatalogChannelEpisodesFound(
            CatalogChannelEpisodesPage(slug: slug, items: const []),
          )
        : const CatalogChannelEpisodesNotFound();
  }
}

/// Kanal iz kataloga za testove; zadano Tier 2 bez slike, kao `tribina`.
CatalogChannelInfo fakeCatalogChannel(
  String slug, {
  String? name,
  int tier = 2,
  int processedCount = 6,
  String? latest = '2026-11-05',
  String? avatar,
  String? youtubeChannelId,
}) => CatalogChannelInfo(
  slug: slug,
  name: name ?? 'Kanal $slug',
  tier: tier,
  processedCount: processedCount,
  latestPublishedDate: latest,
  avatar: avatar,
  youtubeChannelId: youtubeChannelId,
);

CatalogDirectoryLookup fakeDirectoryPage(
  List<CatalogChannelInfo> items, {
  String? next,
}) => CatalogDirectoryFound(CatalogDirectoryPage(items: items, next: next));

CatalogChannelEpisodesLookup fakeEpisodesPage(
  String slug,
  List<CatalogCard> items, {
  String? next,
}) => CatalogChannelEpisodesFound(
  CatalogChannelEpisodesPage(slug: slug, items: items, next: next),
);
