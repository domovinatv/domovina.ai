import '../../l10n/app_localizations.dart';
import '../../models/catalog_card.dart';

/// Brojač na vrhu `/dani/:datum`: „30 novih epizoda iz 28 kanala · 30 h
/// slušanja”, po istom pravilu kao podcast.domovina.ai/dani/
/// (`scripts/build-catalog.mjs`, `[date].astro`), da se dva brojača za isti
/// dan poklapaju. Razlike su samo u tome ŠTO se broji: katalog nosi obrađene
/// epizode i ne nosi kanale koje je vlasnik povukao ili maknuo s naslovnice
/// (`FEATURED` u `katalog/src/db/queries.ts`).
///
/// Kanal se broji po podcastu iz registra (`CatalogCard.podcast`), kao na
/// podcast.domovina.ai: jedan YouTube kanal nosi više podcasta (HRT ih je
/// 19. 11. 2026. imao četiri). Bez podcasta (epizoda još nije u backfillu,
/// stari odgovor) pada se na `channel.slug`, a bez kanala epizoda je zaseban
/// kanal. Izmjereno 23. 11. za 16.–22. 11.: po podcastu svih 7 dana isti broj
/// kao ondje; po kanalu 13 umjesto 17 (18. 11.).
///
/// Trajanje: minute po epizodi zaokružene pa zbrojene; od 90 min naviše sati
/// zaokruženi na cijeli broj (`hoursLabel`).
class CatalogDaySummary {
  final int episodes;
  final int channels;
  final int minutes;

  const CatalogDaySummary({
    required this.episodes,
    required this.channels,
    required this.minutes,
  });

  factory CatalogDaySummary.of(Iterable<CatalogCard> cards) {
    final channelKeys = <String>{};
    var episodes = 0;
    var minutes = 0;
    for (final c in cards) {
      episodes++;
      channelKeys.add(
        c.podcast != null
            ? 'podcast:${c.podcast}'
            : c.channel != null
            ? 'channel:${c.channel!.slug}'
            : 'episode:${c.id}',
      );
      final s = c.durationSeconds;
      if (s != null && s > 0) minutes += (s / 60).round();
    }
    return CatalogDaySummary(
      episodes: episodes,
      channels: channelKeys.length,
      minutes: minutes,
    );
  }

  /// „30 h” ili „45 min”.
  String get durationLabel =>
      minutes >= 90 ? '${(minutes / 60).round()} h' : '$minutes min';

  String label(AppLocalizations l) {
    final buf = StringBuffer(l.catalogDaySummaryEpisodes(episodes));
    if (episodes > 0) {
      buf.write(' ${l.catalogDaySummaryChannels(channels)}');
      if (minutes > 0) {
        buf.write(' · ${l.catalogDaySummaryListening(durationLabel)}');
      }
    }
    return buf.toString();
  }
}
