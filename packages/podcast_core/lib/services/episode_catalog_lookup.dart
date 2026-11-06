/// Odluke ekrana epizode koje se oslanjaju na katalog, izvučene iz widgeta da
/// se daju testirati bez `EpisodeScreen` (šav: [CatalogClient.instance] i
/// parametri funkcija). Odluke `katalog/docs/decisions.md` 800–808.
library;

import '../models/channel_detail.dart' show ChannelVideo;
import '../models/episode_bundle.dart';
import '../src/log.dart' show log;
import 'catalog_client.dart';

/// Kanal epizode iz kataloga, za ekran epizode kad ga `index.json` po imenu
/// ne zna (odluka 801). Redom: `episode.json` `channel` (bez mreže; `null`
/// u bundleu = katalog zna da kanala nema, pa kartica ne bi rekla ništa
/// novo), pa `GET /episodes/:id/card`. `null` kad ništa od toga ne zna ili
/// brend nema katalog.
Future<CatalogChannel?> catalogChannelFor(
  String id, {
  required Future<EpisodeBundle?> Function() bundle,
  CatalogClient? catalog,
}) async {
  final client = catalog ?? CatalogClient.instance;
  if (!client.enabled) return null;
  EpisodeBundle? b;
  try {
    b = await bundle();
  } catch (_) {
    b = null;
  }
  if (b != null && b.channelKnown) {
    log(
      'catalogChannelFor($id): episode.json → ${b.channel?.slug ?? 'bez kanala'}',
    );
    return b.channel;
  }
  return (await client.card(id))?.channel;
}

/// Epizoda bez `info.json` koju smo potvrdili u svom katalogu ili listingu
/// kanala: što ekran u obradi prikazuje. [channelSlug] je oblik za rutu
/// `/c/:slug`, ili `null` kad kanal rute nema (Tier 2, odluka 802) ili nije
/// poznat — tada breadcrumb pokazuje samo ime.
class QueuedEpisodeListing {
  final String title;
  final String? date;
  final String channelName;
  final String? channelSlug;

  /// Odakle je potvrda — za log, testove i breadcrumb (kanal iz kataloga
  /// smije biti bez linka).
  final QueuedEpisodeSource source;

  /// YouTube video koji ekran smije ugraditi i otvoriti na youtube.com, ili
  /// `null` kad je ID epizode sintetički (X, RSS, beamly bez YouTubea) ili to
  /// ne možemo isključiti — tada nema ni embeda ni poveznice (katalog odluka
  /// 808, [queuedYouTubeVideoIdForCard] / [queuedYouTubeVideoIdForListing]).
  /// Za varijantu je to osnovni ID, ne ID epizode.
  final String? youtubeVideoId;

  const QueuedEpisodeListing({
    required this.title,
    required this.channelName,
    required this.source,
    this.date,
    this.channelSlug,
    this.youtubeVideoId,
  });
}

/// Oblik YouTube video ID-a: 11 znakova base64url.
final RegExp _youtubeIdShape = RegExp(r'^[A-Za-z0-9_-]{11}$');

/// Sintetički ID-evi audio izvora: RSS (`sha1(guid)[:11]`) i beamly
/// (zadnjih 11 znakova MongoDB ObjectId-a) su mala heksadecimalna slova.
/// Pravi YouTube ID takav je s vjerojatnošću (16/64)^11 ≈ 2·10⁻⁷.
final RegExp _hexSyntheticId = RegExp(r'^[0-9a-f]{11}$');

bool _passesIdShape(String id) =>
    _youtubeIdShape.hasMatch(id) && !_hexSyntheticId.hasMatch(id);

/// YouTube ID za embed iz kartice kataloga, ili `null` (odluka 808).
/// Kartica ne nosi izvor epizode, pa se sintetika hvata po onome što ima:
/// `variant_of` (varijanta → osnovni ID), slug kanala `x-…` (neregistrirani
/// X autor, `katalog/src/ingest/resolve.ts`) i oblik ID-a (RSS/beamly).
/// X ID (sha256 → 11 znakova) se po obliku ne razlikuje od YouTubeovog, ali
/// X epizode imaju `info.json` i na ekran u obradi ne dolaze, a praćenih X
/// kanala nema.
String? queuedYouTubeVideoIdForCard(CatalogCard card) {
  final slug = card.channel?.slug;
  if (slug != null && slug.startsWith('x-')) return null;
  final id = card.variantOf ?? card.id;
  return _passesIdShape(id) ? id : null;
}

/// YouTube ID za embed iz reda listinga, ili `null` (odluka 808). Listing
/// nosi `youtube_url` = `info.webpage_url`, pa X (`x.com/…`), beamly
/// (`launchedfm.com/…`) i RSS epizode imaju ne-YouTube host; `source` se
/// gleda kad ga pipeline upiše. Oblik ID-a hvata RSS/beamly bez poveznice.
String? queuedYouTubeVideoIdForListing(ChannelVideo video) {
  final source = video.source;
  if (source != null && source.isNotEmpty && source != 'youtube') return null;
  final url = video.youtubeUrl;
  if (url != null && url.isNotEmpty && !_isYouTubeHost(url)) return null;
  return _passesIdShape(video.id) ? video.id : null;
}

bool _isYouTubeHost(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  return host == 'youtu.be' ||
      host == 'youtube.com' ||
      host.endsWith('.youtube.com');
}

/// Čvor kanala u breadcrumbu ekrana epizode: ime i ruta (`null` = ime bez
/// linka, katalog odluka 802).
class EpisodeBreadcrumbChannel {
  final String name;
  final String? route;
  const EpisodeBreadcrumbChannel(this.name, this.route);
}

/// Pokazuje li breadcrumb kanal i kako. Bez [showUnlinked] (zadano, i uvijek
/// kad brend nema katalog) isto kao prije S8: čvor samo uz ime i slug.
/// [showUnlinked]: kanal je poznat iz kataloga, ali nema `/c/` rutu (Tier 2)
/// — ime bez linka.
EpisodeBreadcrumbChannel? episodeBreadcrumbChannel({
  required String name,
  required String? slug,
  bool showUnlinked = false,
}) {
  if (name.isEmpty) return null;
  final linked = slug != null && slug.isNotEmpty;
  if (linked) return EpisodeBreadcrumbChannel(name, '/c/$slug');
  return showUnlinked ? EpisodeBreadcrumbChannel(name, null) : null;
}

enum QueuedEpisodeSource { catalog, listing }

typedef FindListedVideo =
    Future<({String channelId, String channelName, ChannelVideo video})?>
    Function(String id);

/// Ekran epizode u obradi (odluke 803–804): prvo kartica iz kataloga; bez
/// pogotka [findVideo] (`channelCache.findVideoAsync`, skida listinge) — i
/// kad katalog nije dostupan i kad je odgovorio 404, jer katalog za listingom
/// smije kasniti do idućeg ingesta / drift-checka. `null` = prava 404.
Future<QueuedEpisodeListing?> findQueuedEpisode(
  String id, {
  required FindListedVideo findVideo,
  CatalogClient? catalog,
}) async {
  final client = catalog ?? CatalogClient.instance;
  if (client.enabled) {
    final hit = await client.lookup(id);
    final card = hit.card;
    if (card != null) {
      final ch = card.channel;
      return QueuedEpisodeListing(
        title: card.displayTitle,
        date: card.date,
        channelName: ch?.name ?? '',
        channelSlug: ch != null && ch.hasChannelRoute ? ch.routeSlug : null,
        source: QueuedEpisodeSource.catalog,
        youtubeVideoId: queuedYouTubeVideoIdForCard(card),
      );
    }
    log(
      'findQueuedEpisode($id): katalog bez pogotka '
      '(${hit is CatalogNotFound ? '404' : 'nedostupan'}), listinzi',
    );
  }
  final listed = await findVideo(id);
  if (listed == null) return null;
  return QueuedEpisodeListing(
    title: listed.video.displayTitle,
    date: listed.video.date,
    channelName: listed.channelName,
    // Isto kao prije: ID kanala iz listinga, bez pretvaranja u crticu
    // (`/c/:slug` ionako vraća crticu u podvlaku).
    channelSlug: listed.channelId,
    source: QueuedEpisodeSource.listing,
    youtubeVideoId: queuedYouTubeVideoIdForListing(listed.video),
  );
}
