import 'package:flutter/material.dart';

import '../../../router/nav.dart';
import '../../../services/cdn_config.dart';
import '../../../services/person_index_cache.dart';
import '../../../services/watch_progress_service.dart';
import '../../../theme/typography.dart';
import '../../../widgets/cached_thumbnail.dart';
import '../../../widgets/prefetch_on_intent.dart';
import '../episodes_rail.dart';
import '../footer.dart';
import '../home_app_bar.dart';
import '../persons_rail.dart';
import '../skeletons.dart';
import 'home_variant_data.dart';
import 'variant_strings.dart';
import 'variant_widgets.dart';

/// Varijanta C — „Prvo ti”. Povratnik s nedovršenom epizodom na vrhu vidi
/// veliku karticu „Nastavi” (jedan tap do reprodukcije), a hero se sažme u
/// red od tri „Istaknuto danas”. Gost bez povijesti dobiva hero kao danas.
/// „Otkrij” su tri pločice. Na mobitelu donja navigacija — SAMO ovdje, iza
/// `?home=c`; globalni chrome aplikacije se ne dira.
class HomeVariantC extends StatelessWidget {
  final HomeVariantData data;

  const HomeVariantC({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final isMobile = data.isMobile;
    final resuming = data.continueWatching.isNotEmpty;

    final scroll = CustomScrollView(
      controller: data.scrollController,
      slivers: [
        HomeAppBar(onSearchTap: data.onSearchTap),
        if (resuming) ...[
          SliverToBoxAdapter(child: _ContinueSpotlight(data: data)),
          SliverToBoxAdapter(child: _FeaturedRow(data: data)),
        ] else
          SliverToBoxAdapter(child: VariantHero(data: data)),

        SliverToBoxAdapter(
          child: PersonalScope(
            continueWatching: data.continueWatching,
            builder: (context, personal) => NewZone(
              data: data,
              // Kad je hero sažet u red od tri, te tri ne ponavljamo u „Novo”.
              exclude: resuming
                  ? {
                      for (final p in (data.featuredPicks ?? const []).take(
                        isMobile ? 5 : 3,
                      ))
                        p.video.video.id,
                    }
                  : const {},
              filters: [
                if (personal.hasFollows) NewFilter.followed,
                NewFilter.processed,
                NewFilter.processing,
                NewFilter.corpus,
              ],
            ),
          ),
        ),

        const SliverToBoxAdapter(
          child: ZoneHeader(title: VariantStrings.zoneDiscover),
        ),
        SliverToBoxAdapter(child: _DiscoverTiles(data: data)),
        // Osobe ostaju i kao rail: pločica vodi na popis, rail daje lica.
        SliverToBoxAdapter(child: PersonsRail(isMobile: isMobile)),

        SliverToBoxAdapter(child: HomeFooter(channels: data.channels)),
      ],
    );

    if (!isMobile) return scroll;
    return Column(
      children: [
        Expanded(child: scroll),
        _BottomNav(data: data),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

String _clock(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

class _ContinueSpotlight extends StatelessWidget {
  final HomeVariantData data;

  const _ContinueSpotlight({required this.data});

  @override
  Widget build(BuildContext context) {
    final isMobile = data.isMobile;
    final first = data.continueWatching.first;
    final rest = data.continueWatching.skip(1).take(3).toList();
    final card = _ResumeCard(wp: first, data: data);
    final more = rest.isEmpty
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionLabel(
                VariantStrings.alsoStarted,
                padding: EdgeInsets.fromLTRB(
                  isMobile ? kVariantGutter : 0,
                  8,
                  kVariantGutter,
                  4,
                ),
              ),
              ContinueCompactList(
                items: rest,
                onVideoTap: data.onVideoTap,
                thumbWidth: isMobile ? 112 : 132,
                padding: EdgeInsets.only(
                  left: isMobile ? kVariantGutter : 0,
                  right: kVariantGutter,
                ),
              ),
            ],
          );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [card, ?more],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 16, child: card),
        if (more != null) ...[
          const SizedBox(width: 16),
          Expanded(flex: 10, child: more),
        ],
      ],
    );
  }
}

class _ResumeCard extends StatelessWidget {
  final WatchProgress wp;
  final HomeVariantData data;

  const _ResumeCard({required this.wp, required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isMobile = data.isMobile;
    final progress = wp.durationSeconds > 0
        ? (wp.positionSeconds / wp.durationSeconds).clamp(0.0, 1.0)
        : 0.0;
    final remainingMin = ((wp.durationSeconds - wp.positionSeconds) / 60)
        .ceil();

    Widget thumb(double width) => ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: CachedThumbnail(
              url: CdnConfig.thumbnailUrl(wp.episodeId),
              width: width,
              fit: BoxFit.cover,
              errorIcon: Icons.ondemand_video,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              color: cs.tertiary,
              backgroundColor: Colors.black.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          VariantStrings.continueWhereStopped.toUpperCase(),
          style: AppTypography.eyebrowStyle(cs).copyWith(color: cs.tertiary),
        ),
        const SizedBox(height: 10),
        Text(
          wp.episodeTitle ?? wp.episodeId,
          style:
              (isMobile
                      ? theme.textTheme.titleLarge
                      : theme.textTheme.headlineSmall)
                  ?.copyWith(fontWeight: FontWeight.w700),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Text(
          VariantStrings.remaining(remainingMin),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => data.onVideoTap(wp.episodeId),
          style: FilledButton.styleFrom(
            backgroundColor: cs.tertiary,
            foregroundColor: cs.onTertiary,
            minimumSize: const Size(0, 48),
          ),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(
            '${VariantStrings.resume} · ${_clock(wp.positionSeconds)}',
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kVariantGutter,
        16,
        0,
        8,
      ).copyWith(right: isMobile ? kVariantGutter : 0),
      child: PrefetchOnIntent(
        episodeId: wp.episodeId,
        child: Material(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => data.onVideoTap(wp.episodeId),
            child: Padding(
              padding: EdgeInsets.all(isMobile ? 14 : 24),
              child: isMobile
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        thumb(data.width - 2 * kVariantGutter - 28),
                        const SizedBox(height: 14),
                        text,
                      ],
                    )
                  : LayoutBuilder(
                      builder: (context, c) {
                        final w = (c.maxWidth - 28) / 2;
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(width: w, child: thumb(w)),
                            const SizedBox(width: 28),
                            Expanded(child: text),
                          ],
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hero sažet u red od tri (kad je vrh zauzela kartica „Nastavi”).
class _FeaturedRow extends StatelessWidget {
  final HomeVariantData data;

  const _FeaturedRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final picks = data.featuredPicks;
    if (picks == null) return RailSkeleton(isMobile: data.isMobile);
    if (picks.isEmpty) return const SizedBox.shrink();
    final videos = picks.map((p) => p.video).take(data.isMobile ? 5 : 3);
    if (data.isMobile) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: EpisodesRail(
          eyebrow: VariantStrings.featuredToday,
          isMobile: true,
          cards: [
            for (final fv in videos) feedCard(context, fv, data, width: 260),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ZoneHeader(title: VariantStrings.featuredToday),
        EpisodeGrid(videos: videos.toList(), data: data, maxColumns: 3),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _DiscoverTiles extends StatelessWidget {
  final HomeVariantData data;

  const _DiscoverTiles({required this.data});

  @override
  Widget build(BuildContext context) {
    final shows = data.featuredShows(limit: 4);
    // Širine se računaju unaprijed (bez LayoutBuilder-a), jer pločice stoje u
    // IntrinsicHeight da budu jednako visoke, a LayoutBuilder intrinsics nema.
    final tileInner =
        (data.isMobile
            ? data.width - 2 * kVariantGutter
            : (data.width - 2 * kVariantGutter - 40) / 3) -
        40;
    final thumbW = ((tileInner - 8) / 2).floorToDouble();
    final tiles = [
      // Brend bez istaknutih emisija (DOMOVINA danas) → pločice nema.
      if (shows.isNotEmpty)
        _Tile(
          label: VariantStrings.shows,
          cta: VariantStrings.featuredShows,
          onTap: () => drillDown(context, '/channels'),
          preview: shows.isEmpty
              ? null
              : Builder(
                  builder: (context) {
                    final w = thumbW;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final fv in shows)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              width: w,
                              child: AspectRatio(
                                aspectRatio: 16 / 9,
                                child: CachedThumbnail(
                                  url: CdnConfig.thumbnailUrl(fv.video.id),
                                  width: w,
                                  fit: BoxFit.cover,
                                  errorIcon: Icons.ondemand_video,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
        ),
      _Tile(
        label: VariantStrings.persons,
        cta: VariantStrings.allPersons,
        onTap: () => drillDown(context, '/channels?prikaz=osobe'),
        preview: ListenableBuilder(
          listenable: personIndexCache,
          builder: (context, _) {
            final people = personIndexCache.virtualChannels.take(8).toList();
            final cs = Theme.of(context).colorScheme;
            if (people.isEmpty) {
              return Icon(
                Icons.groups_outlined,
                size: 40,
                color: cs.onSurfaceVariant,
              );
            }
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in people)
                  Tooltip(
                    message: p.name,
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor: cs.surfaceContainerHighest,
                      child: Text(
                        p.name
                            .split(' ')
                            .where((w) => w.isNotEmpty)
                            .take(2)
                            .map((w) => w[0])
                            .join(),
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      _Tile(
        label: VariantStrings.channels,
        cta: VariantStrings.allChannels(data.channels.length),
        onTap: () => drillDown(context, '/channels'),
        preview: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final ch in data.channels.take(4))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.podcasts_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ch.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(kVariantGutter, 0, kVariantGutter, 16),
      child: data.isMobile
          ? Column(
              children: [
                for (final t in tiles)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: IntrinsicHeight(child: t),
                  ),
              ],
            )
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < tiles.length; i++) ...[
                    if (i > 0) const SizedBox(width: 20),
                    Expanded(child: tiles[i]),
                  ],
                ],
              ),
            ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final String cta;
  final VoidCallback onTap;
  final Widget? preview;

  const _Tile({
    required this.label,
    required this.cta,
    required this.onTap,
    this.preview,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(), style: AppTypography.eyebrowStyle(cs)),
              const SizedBox(height: 14),
              if (preview != null) ...[preview!, const SizedBox(height: 14)],
              const Spacer(),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      cta,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: cs.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.arrow_forward, size: 16, color: cs.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Donja navigacija — skica iz plana, živi SAMO u varijanti C na mobitelu.
class _BottomNav extends StatelessWidget {
  final HomeVariantData data;

  const _BottomNav({required this.data});

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: 0,
      height: 64,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      onDestinationSelected: (i) {
        switch (i) {
          case 0:
            if (data.scrollController.hasClients) {
              data.scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          case 1:
            data.onSearchTap();
          case 2:
            drillDown(context, '/favorites');
          case 3:
            drillDown(context, '/account');
        }
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: VariantStrings.navHome,
        ),
        NavigationDestination(
          icon: Icon(Icons.search),
          label: VariantStrings.navSearch,
        ),
        NavigationDestination(
          icon: Icon(Icons.bookmark_outline),
          label: VariantStrings.navSaved,
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          label: VariantStrings.navAccount,
        ),
      ],
    );
  }
}
