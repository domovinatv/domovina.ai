import 'package:flutter/widgets.dart';

import '../../../models/channel_index.dart';
import '../../../services/watch_progress_service.dart';
import '../home_feed.dart';

/// Sve što varijanta naslovnice smije znati — podaci koje `HomeScreen` već
/// ima izračunate u buildu. Varijante NE pokreću nijedan novi mrežni poziv;
/// samo drukčije slažu ovo i reuseaju postojeće railove.
class HomeVariantData {
  /// Latchani hero izbor; `null` = bazen još nije konačan (crtaj skeleton).
  final List<FeaturedPick>? featuredPicks;
  final List<FeedVideo> allVids;
  final List<WatchProgress> continueWatching;

  /// Tek pristigle, neobrađene (isto kao rail „Upravo stiglo”).
  final List<FeedVideo> freshlyArrived;
  final List<ChannelSummary> channels;
  final bool hasMinData;
  final double width;
  final ScrollController scrollController;
  final VoidCallback onSearchTap;
  final void Function(String videoId) onVideoTap;

  const HomeVariantData({
    required this.featuredPicks,
    required this.allVids,
    required this.continueWatching,
    required this.freshlyArrived,
    required this.channels,
    required this.hasMinData,
    required this.width,
    required this.scrollController,
    required this.onSearchTap,
    required this.onVideoTap,
  });

  bool get isMobile => width < 600;

  FeaturedPick? get featured {
    final picks = featuredPicks;
    return (picks == null || picks.isEmpty) ? null : picks.first;
  }

  /// „Najnovije” (obrađene), bez latchane hero epizode — isti izračun kao
  /// rail na postojećoj naslovnici. Prazno dok hero nije latchan.
  List<FeedVideo> latest({int limit = 12}) {
    final f = featured;
    if (f == null || allVids.isEmpty) return const [];
    return HomeFeed.latestEpisodes(
      allVids,
      limit: limit,
      excludeFeatured: f.video,
    );
  }

  List<FeedVideo> featuredShows({int limit = 12}) {
    final f = featured;
    if (f == null || allVids.isEmpty) return const [];
    return HomeFeed.featuredShows(
      allVids,
      limit: limit,
      excludeFeatured: f.video,
    );
  }

  /// Obrađene i neobrađene zajedno, najnovije prve (filtar „Sve” u B).
  List<FeedVideo> latestAll({int limit = 12}) {
    final merged = [...latest(limit: limit), ...freshlyArrived]
      ..sort(HomeFeed.newestFirst);
    return merged.take(limit).toList();
  }
}
