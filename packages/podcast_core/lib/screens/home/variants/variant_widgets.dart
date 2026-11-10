import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/channel_index.dart';
import '../../../models/episode_status.dart';
import '../../../router/nav.dart';
import '../../../services/catalog_client.dart';
import '../../../services/cdn_config.dart';
import '../../../services/favorites_service.dart';
import '../../../services/follow_service.dart';
import '../../../services/share_language.dart';
import '../../../services/share_links.dart';
import '../../../services/watch_progress_service.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/typography.dart';
import '../../../widgets/cached_thumbnail.dart';
import '../../../widgets/magisterium_section.dart';
import '../../../widgets/prefetch_on_intent.dart';
import '../catalog_day_rail.dart';
import '../episode_rail_card.dart';
import '../followed_rail.dart';
import '../hero_carousel.dart';
import '../home_feed.dart';
import '../skeletons.dart';
import 'home_variant_data.dart';
import 'variant_strings.dart';

/// Rubni razmak sadržaja — isti 16 px koji nose postojeći railovi
/// ([EpisodesRail] padding unutar scrolla), da zone i railovi stoje u liniji.
const double kVariantGutter = 16;

// ---------------------------------------------------------------------------
// Hero (isti latch ugovor kao postojeća naslovnica)
// ---------------------------------------------------------------------------

/// Kopija hero slota iz `home_screen.dart`: skeleton dok izbor nije latchan,
/// pa jedan fade. Skeleton je iste visine kao karusel
/// (`test/hero_slot_layout_test.dart`), pa zamjena ne pomiče ništa ispod.
class VariantHero extends StatelessWidget {
  final HomeVariantData data;
  final bool? isMobileOverride;

  const VariantHero({super.key, required this.data, this.isMobileOverride});

  @override
  Widget build(BuildContext context) {
    final picks = data.featuredPicks;
    final isMobile = isMobileOverride ?? data.isMobile;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOut,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topCenter,
        children: [...previousChildren, ?currentChild],
      ),
      child: picks == null
          ? HeroSkeleton(
              key: const ValueKey('hero-skeleton'),
              isMobile: isMobile,
            )
          : picks.isEmpty
          ? const SizedBox.shrink(key: ValueKey('hero-none'))
          : HeroCarousel(
              key: const ValueKey('hero-carousel'),
              picks: picks,
              isMobile: isMobile,
              onPlay: data.onVideoTap,
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Zaglavlja
// ---------------------------------------------------------------------------

/// Zaglavlje zone („Za tebe” / „Novo” / „Otkrij”): crta iznad, naslov u
/// Playfairu, podnaslov, opcionalno nešto desno (filtar).
class ZoneHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool divider;

  const ZoneHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.divider = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style:
              (isMobile
                      ? theme.textTheme.headlineSmall
                      : theme.textTheme.headlineMedium)
                  ?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        kVariantGutter,
        divider ? 24 : 8,
        kVariantGutter,
        12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (divider) ...[
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
            SizedBox(height: isMobile ? 20 : 32),
          ],
          if (trailing == null || isMobile) ...[
            heading,
            if (trailing != null) ...[const SizedBox(height: 12), trailing!],
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: heading),
                const SizedBox(width: 16),
                trailing!,
              ],
            ),
        ],
      ),
    );
  }
}

/// Manji naslov unutar zone ili bočne trake (eyebrow stil kao railovi).
class SectionLabel extends StatelessWidget {
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsets padding;

  const SectionLabel(
    this.text, {
    super.key,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(
      kVariantGutter,
      8,
      kVariantGutter,
      10,
    ),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Container(width: 24, height: 2, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: AppTypography.eyebrowStyle(
                cs,
              ).copyWith(color: cs.onSurface),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                actionLabel!,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Kartice (isti EpisodeRailCard kao postojeći railovi)
// ---------------------------------------------------------------------------

double _progressOf(WatchProgress wp) =>
    wp.durationSeconds > 0 ? wp.positionSeconds / wp.durationSeconds : 0;

List<Widget> continueCards(HomeVariantData data, {double? width}) => [
  for (final wp in data.continueWatching)
    EpisodeRailCard(
      title: wp.episodeTitle ?? wp.episodeId,
      thumbnailUrl: CdnConfig.thumbnailUrl(wp.episodeId),
      progress: wp.durationSeconds > 0 ? _progressOf(wp) : null,
      width: width ?? (data.isMobile ? 180 : 220),
      shareUrl: () => episodeShareUrl(
        wp.episodeId,
        lang: shareLanguageForVideo(wp.episodeId),
      ),
      prefetchEpisodeId: wp.episodeId,
      onTap: () => data.onVideoTap(wp.episodeId),
    ),
];

Widget feedCard(
  BuildContext context,
  FeedVideo fv,
  HomeVariantData data, {
  required double width,
  bool processing = false,
}) {
  final l = AppLocalizations.of(context);
  return EpisodeRailCard(
    title: fv.video.displayTitle,
    subtitle: fv.channelName,
    thumbnailUrl: CdnConfig.thumbnailUrl(fv.video.id),
    dateLabel: fv.video.date,
    magisteriumScore: processing ? null : fv.video.magisteriumScore,
    statusBadge: processing
        ? EpisodeStatus.fromPipeline(fv.video.pipeline).badge(l) ??
              l.homeStatusProcessing
        : null,
    width: width,
    shareUrl: () =>
        episodeShareUrl(fv.video.id, lang: shareLanguageForVideo(fv.video.id)),
    prefetchEpisodeId: fv.video.id,
    onTap: () => data.onVideoTap(fv.video.id),
  );
}

/// Mreža kartica preko širine (desktop „Novo”): broj stupaca po širini,
/// širina kartice izračunata pa proslijeđena (CachedThumbnail bira varijantu).
class EpisodeGrid extends StatelessWidget {
  final List<FeedVideo> videos;
  final HomeVariantData data;
  final bool processing;
  final int maxColumns;

  const EpisodeGrid({
    super.key,
    required this.videos,
    required this.data,
    this.processing = false,
    this.maxColumns = 5,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final inner = c.maxWidth - 2 * kVariantGutter;
        const gap = 16.0;
        final cols =
            (inner >= 1100
                    ? 5
                    : inner >= 820
                    ? 4
                    : inner >= 560
                    ? 3
                    : 2)
                .clamp(1, maxColumns);
        final w = ((inner - gap * (cols - 1)) / cols).floorToDouble();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: kVariantGutter),
          child: Wrap(
            spacing: gap,
            runSpacing: 20,
            children: [
              for (final fv in videos)
                feedCard(context, fv, data, width: w, processing: processing),
            ],
          ),
        );
      },
    );
  }
}

/// Gusti redak epizode (B „Najnovije”, mobilna „Novo” lista u A i C):
/// mali thumb + naslov u 2 retka + kanal · datum · trajanje + oznaka.
class EpisodeListTile extends StatelessWidget {
  final FeedVideo fv;
  final VoidCallback onTap;
  final double thumbWidth;

  /// `null` = odluči po `pipeline` (neobrađena → oznaka faze).
  final bool? processing;

  const EpisodeListTile({
    super.key,
    required this.fv,
    required this.onTap,
    this.thumbWidth = 136,
    this.processing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);
    final v = fv.video;
    final isProcessing = processing ?? HomeFeed.isFreshUnprocessed(fv);
    final meta = [
      fv.channelName,
      if (v.date != null) v.date!,
      if (v.durationDisplay != null) v.durationDisplay!,
    ].join(' · ');
    final score = v.magisteriumScore;

    Widget? badge;
    if (isProcessing) {
      badge = _pill(
        theme,
        EpisodeStatus.fromPipeline(v.pipeline).badge(l) ??
            l.homeStatusProcessing,
        AppTheme.sponsoredAccent(theme.brightness),
      );
    } else if (score != null) {
      badge = _pill(
        theme,
        'Magisterium $score',
        MagisteriumSection.scoreColor(score),
      );
    }

    return PrefetchOnIntent(
      episodeId: v.id,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: kVariantGutter,
            vertical: 10,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: thumbWidth,
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: CachedThumbnail(
                      url: CdnConfig.thumbnailUrl(v.id),
                      width: thumbWidth,
                      fit: BoxFit.cover,
                      errorIcon: Icons.ondemand_video,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v.displayTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 4),
                    Text(
                      meta,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (badge != null) ...[SizedBox(height: 6), badge],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _pill(ThemeData theme, String text, Color color) => Container(
    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: color.withValues(alpha: 0.45)),
    ),
    child: Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Zona „Novo” s filtrom
// ---------------------------------------------------------------------------

enum NewFilter { all, followed, processed, processing, corpus }

String newFilterLabel(
  BuildContext context,
  NewFilter f,
  HomeVariantData data,
) => switch (f) {
  NewFilter.all => VariantStrings.of(context).filterAll,
  NewFilter.followed => VariantStrings.of(context).filterFollowed,
  NewFilter.processed => VariantStrings.of(context).filterProcessed,
  NewFilter.processing =>
    data.freshlyArrived.isEmpty
        ? VariantStrings.of(context).filterProcessing
        : '${VariantStrings.of(context).filterProcessing} · ${data.freshlyArrived.length}',
  NewFilter.corpus => VariantStrings.of(context).filterCorpus,
};

/// Filtar čipovi (horizontalno klizni na mobitelu, padding unutar scrolla).
class FilterChips extends StatelessWidget {
  final List<NewFilter> filters;
  final NewFilter selected;
  final HomeVariantData data;
  final ValueChanged<NewFilter> onSelected;
  final bool scrollable;

  const FilterChips({
    super.key,
    required this.filters,
    required this.selected,
    required this.data,
    required this.onSelected,
    this.scrollable = false,
  });

  @override
  Widget build(BuildContext context) {
    final chips = [
      for (final f in filters)
        Padding(
          padding: EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(newFilterLabel(context, f, data)),
            selected: f == selected,
            showCheckmark: false,
            onSelected: (_) => onSelected(f),
          ),
        ),
    ];
    if (!scrollable) {
      return Row(mainAxisSize: MainAxisSize.min, children: chips);
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: kVariantGutter),
      child: Row(children: chips),
    );
  }
}

/// Zona „Novo”: JEDNO mjesto za ono što su do sada bila tri raila
/// (Najnovije, Upravo stiglo, U korpusu). „Danas u korpusu” i „Od praćenih”
/// mijenjaju IZVOR (katalog / praćenja), ne samo predikat — zato su to
/// postojeći railovi, ne filtrirana lista.
class NewZone extends StatefulWidget {
  final HomeVariantData data;
  final List<NewFilter> filters;
  final bool showHeader;

  /// `null` = „Novo” s podnaslovom zone; zadan naslov ide sa [subtitle].
  final String? title;
  final String? subtitle;
  final bool divider;

  /// Gusta lista i na desktopu (B „Najnovije”) umjesto mreže kartica.
  final bool preferList;

  /// Epizode koje su već prikazane iznad (C: „Istaknuto danas”).
  final Set<String> exclude;

  const NewZone({
    super.key,
    required this.data,
    required this.filters,
    this.showHeader = true,
    this.title,
    this.subtitle,
    this.divider = true,
    this.preferList = false,
    this.exclude = const {},
  });

  @override
  State<NewZone> createState() => _NewZoneState();
}

class _NewZoneState extends State<NewZone> {
  late NewFilter _selected = widget.filters.first;

  @override
  void didUpdateWidget(NewZone old) {
    super.didUpdateWidget(old);
    if (!widget.filters.contains(_selected)) _selected = widget.filters.first;
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final isMobile = data.isMobile;
    final chips = FilterChips(
      filters: widget.filters,
      selected: _selected,
      data: data,
      scrollable: isMobile,
      onSelected: (f) => setState(() => _selected = f),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeader)
          ZoneHeader(
            title: widget.title ?? VariantStrings.of(context).zoneNew,
            subtitle: widget.title == null
                ? VariantStrings.of(context).zoneNewSub
                : widget.subtitle,
            divider: widget.divider,
            trailing: isMobile ? null : chips,
          ),
        if (isMobile || !widget.showHeader) ...[
          isMobile
              ? chips
              : Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: kVariantGutter,
                  ),
                  child: Align(alignment: Alignment.centerLeft, child: chips),
                ),
          const SizedBox(height: 12),
        ],
        _body(context),
        if (_selected != NewFilter.corpus &&
            _selected != NewFilter.followed &&
            CatalogClient.instance.enabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              kVariantGutter - 8,
              4,
              kVariantGutter,
              8,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => drillDown(
                  context,
                  '/dani/${formatCatalogDate(catalogToday())}',
                ),
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: Text(VariantStrings.of(context).allNewByDay),
              ),
            ),
          ),
      ],
    );
  }

  Widget _body(BuildContext context) {
    final data = widget.data;
    switch (_selected) {
      case NewFilter.corpus:
        return CatalogDayRail(
          isMobile: data.isMobile,
          onVideoTap: data.onVideoTap,
        );
      case NewFilter.followed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FollowedRail(isMobile: data.isMobile, onVideoTap: data.onVideoTap),
            _hint(context, VariantStrings.of(context).followedHint),
          ],
        );
      case NewFilter.all:
      case NewFilter.processed:
      case NewFilter.processing:
        final processing = _selected == NewFilter.processing;
        final pool = switch (_selected) {
          NewFilter.all => data.latestAll(limit: 10 + widget.exclude.length),
          NewFilter.processing => data.freshlyArrived,
          _ => data.latest(limit: 10 + widget.exclude.length),
        };
        final videos = pool
            .where((fv) => !widget.exclude.contains(fv.video.id))
            .take(10)
            .toList();
        if (videos.isEmpty) {
          if (data.featuredPicks == null || !data.hasMinData) {
            return RailSkeleton(isMobile: data.isMobile);
          }
          return _hint(context, VariantStrings.of(context).emptyFilter);
        }
        if (data.isMobile || widget.preferList) {
          return Column(
            children: [
              for (final fv in videos.take(data.isMobile ? 6 : 10))
                EpisodeListTile(
                  fv: fv,
                  thumbWidth: data.isMobile ? 136 : 168,
                  processing: _selected == NewFilter.all ? null : processing,
                  onTap: () => data.onVideoTap(fv.video.id),
                ),
            ],
          );
        }
        return EpisodeGrid(videos: videos, data: data, processing: processing);
    }
  }

  Widget _hint(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(kVariantGutter, 4, kVariantGutter, 8),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Osobno: ima li korisnik išta „svoje”
// ---------------------------------------------------------------------------

/// Sluša praćenja i spremljeno (lokalni podaci, isti servisi kao railovi) i
/// javlja ima li korisnik išta osobnog. Gost bez povijesti → zona „Za tebe”
/// se ne crta.
class PersonalScope extends StatefulWidget {
  final List<WatchProgress> continueWatching;
  final Widget Function(BuildContext context, PersonalState state) builder;

  const PersonalScope({
    super.key,
    required this.continueWatching,
    required this.builder,
  });

  @override
  State<PersonalScope> createState() => _PersonalScopeState();
}

class PersonalState {
  final bool hasContinue;
  final bool hasFollows;
  final List<FavoriteEntry> favorites;

  const PersonalState({
    required this.hasContinue,
    required this.hasFollows,
    required this.favorites,
  });

  bool get hasAnything => hasContinue || hasFollows || favorites.isNotEmpty;
}

class _PersonalScopeState extends State<PersonalScope> {
  List<FavoriteEntry> _favorites = const [];

  @override
  void initState() {
    super.initState();
    FollowService.instance.addListener(_onChanged);
    FavoritesService.instance.addListener(_reloadFavorites);
    unawaited(FollowService.instance.ensureLoaded().then((_) => _onChanged()));
    unawaited(_reloadFavorites());
  }

  @override
  void dispose() {
    FollowService.instance.removeListener(_onChanged);
    FavoritesService.instance.removeListener(_reloadFavorites);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _reloadFavorites() async {
    final list = await FavoritesService.instance.entries();
    if (mounted) setState(() => _favorites = list);
  }

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    PersonalState(
      hasContinue: widget.continueWatching.isNotEmpty,
      hasFollows: FollowService.instance.all.isNotEmpty,
      favorites: _favorites,
    ),
  );
}

/// Kartica „Tvoja polica” (A): broj spremljenih + 3 sličice, vodi na
/// `/favorites`. Spremljeno time prestaje živjeti na dnu naslovnice.
class FavoritesShelfCard extends StatelessWidget {
  final List<FavoriteEntry> favorites;
  final bool compact;

  const FavoritesShelfCard({
    super.key,
    required this.favorites,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    void open() => drillDown(context, '/favorites');
    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          kVariantGutter,
          4,
          kVariantGutter,
          8,
        ),
        child: Material(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            onTap: open,
            leading: Icon(Icons.bookmark_outline, color: cs.primary),
            title: Text(
              VariantStrings.of(context).savedCount(favorites.length),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing: const Icon(Icons.arrow_forward),
          ),
        ),
      );
    }
    final thumbs = favorites.take(3).toList();
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                VariantStrings.of(context).shelf.toUpperCase(),
                style: AppTypography.eyebrowStyle(cs),
              ),
              const SizedBox(height: 8),
              Text(
                VariantStrings.of(context).savedCount(favorites.length),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, c) {
                  final w = ((c.maxWidth - 16) / 3).floorToDouble();
                  return Row(
                    children: [
                      for (int i = 0; i < thumbs.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: w,
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: CachedThumbnail(
                                url: CdnConfig.thumbnailUrl(
                                  thumbs[i].episodeId,
                                ),
                                width: w,
                                fit: BoxFit.cover,
                                errorIcon: Icons.ondemand_video,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    VariantStrings.of(context).openShelf,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: cs.primary,
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
// Nastavi slušati — kompaktna lista (B bočna traka, B mobitel, C „također”)
// ---------------------------------------------------------------------------

class ContinueCompactList extends StatelessWidget {
  final List<WatchProgress> items;
  final void Function(String videoId) onVideoTap;
  final double thumbWidth;
  final EdgeInsets padding;

  const ContinueCompactList({
    super.key,
    required this.items,
    required this.onVideoTap,
    this.thumbWidth = 112,
    this.padding = const EdgeInsets.symmetric(horizontal: kVariantGutter),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      children: [
        for (final wp in items)
          PrefetchOnIntent(
            episodeId: wp.episodeId,
            child: InkWell(
              onTap: () => onVideoTap(wp.episodeId),
              child: Padding(
                padding: padding.add(const EdgeInsets.symmetric(vertical: 8)),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: thumbWidth,
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: CachedThumbnail(
                            url: CdnConfig.thumbnailUrl(wp.episodeId),
                            width: thumbWidth,
                            fit: BoxFit.cover,
                            errorIcon: Icons.ondemand_video,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            wp.episodeTitle ?? wp.episodeId,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: _progressOf(wp).clamp(0.0, 1.0),
                              minHeight: 3,
                              color: AppTheme.brandAccent,
                              backgroundColor: cs.surfaceContainerHighest,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            VariantStrings.of(context).remaining(
                              ((wp.durationSeconds - wp.positionSeconds) / 60)
                                  .ceil(),
                            ),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Kanali — mali popis + „Svi kanali”
// ---------------------------------------------------------------------------

class ChannelTiles extends StatelessWidget {
  final List<ChannelSummary> channels;
  final int limit;
  final int columns;

  const ChannelTiles({
    super.key,
    required this.channels,
    this.limit = 6,
    this.columns = 3,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final shown = channels.take(limit).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kVariantGutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              const gap = 10.0;
              final w = ((c.maxWidth - gap * (columns - 1)) / columns)
                  .floorToDouble();
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final ch in shown)
                    SizedBox(
                      width: w,
                      child: Material(
                        color: cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => drillDown(
                            context,
                            '/c/${ch.id.replaceAll('_', '-')}',
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.podcasts_outlined,
                                  size: 20,
                                  color: cs.onSurfaceVariant,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    ch.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelLarge,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => drillDown(context, '/channels'),
            icon: const Icon(Icons.grid_view_rounded, size: 18),
            label: Text(
              VariantStrings.of(context).allChannels(channels.length),
            ),
          ),
        ],
      ),
    );
  }
}
