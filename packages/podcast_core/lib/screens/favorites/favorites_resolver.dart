import '../../models/channel_detail.dart';
import '../../services/channel_cache.dart';
import '../../services/channel_visibility_filters.dart';
import '../../services/favorites_service.dart';

/// Spremljena epizoda spremna za prikaz — spoj lokalnog zapisa
/// ([FavoriteEntry]) i kataloga (`channelCache`).
///
/// Katalog je kanonski izvor naslova/kanala/datuma; denorm polja iz zapisa su
/// fallback dok se `channelCache` puni (ili ako epizoda više nije u katalogu).
typedef ResolvedFavorite = ({
  FavoriteEntry entry,
  String episodeId,
  String title,
  String? channelName,
  String? date,
  int? magisteriumScore,
});

/// Razriješi popis favorita (već sortiran, najnoviji prvi) protiv kataloga.
///
/// Jedan prolaz kroz `channelCache.allVideos` po pozivu — isti red veličine
/// kao `HomeFeed.latestEpisodes`, koji također skenira cijeli katalog u buildu.
List<ResolvedFavorite> resolveFavorites(List<FavoriteEntry> entries) {
  if (entries.isEmpty) return const [];
  final wanted = {for (final e in entries) e.episodeId};
  final byId = <String, ({String channelName, ChannelVideo video})>{};
  for (final fv in channelCache.allVideos) {
    if (wanted.contains(fv.video.id)) {
      byId[fv.video.id] = (channelName: fv.channelName, video: fv.video);
    }
  }

  return [
    for (final e in entries)
      // Povučen/obrisan kanal: kartica nestaje, zapis ostaje (odluka 502).
      if (!isEpisodeChannelGone(e.episodeId, channelName: e.channelName))
      () {
        final hit = byId[e.episodeId];
        final title = hit?.video.displayTitle ?? e.title;
        return (
          entry: e,
          episodeId: e.episodeId,
          title: (title != null && title.isNotEmpty) ? title : e.episodeId,
          channelName: hit?.channelName ?? e.channelName,
          date: hit?.video.date,
          magisteriumScore: hit?.video.magisteriumScore,
        );
      }(),
  ];
}
