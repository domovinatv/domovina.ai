import 'dart:async';
import 'dart:math' show Random;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../brand/app_brand.dart';
import '../../src/log.dart' show log;
import '../../models/channel_index.dart';
import '../../models/person_hub.dart';
import '../../screens/home/home_feed.dart';
import '../../services/cdn_config.dart';
import '../../services/channel_cache.dart';
import '../../services/channel_visibility_filters.dart';
import '../../services/person_channel_flag.dart';
import '../../services/person_index_cache.dart';
import '../../services/watch_progress_service.dart';
import '../../widgets/person_monogram.dart';
import 'widgets/tv_channel_card.dart';
import 'widgets/tv_episode_card.dart';
import 'widgets/tv_focus.dart';
import 'widgets/tv_hero.dart';
import 'widgets/tv_boot_splash.dart';
import 'widgets/tv_metrics.dart';
import 'widgets/tv_rail.dart';
import 'widgets/tv_row_traversal.dart';
import '../../router/nav.dart';

/// Faza 2 TV home screen.
///
/// Layout (vertikalan scroll, jer EON SDSTB02 daje 540 dp visine pa hero +
/// 3 rail-a ne stane bez scrolla):
///
///   AppBar (kompaktan: wordmark + Pretraga gumb)
///   Hero (45% min(540, height), HomeFeed.pickFeatured) — autofocus PLAY
///   Rail: "Nastavi slušati" (samo ako WatchProgress ima itema)
///   Rail: "Najnovije epizode" (HomeFeed.latestEpisodes, 12 itema)
///   Rail: "Kanali" (sortirano po videoCount desc)
///
/// Sve interakcije su navigation:
/// - Hero PLAY → `/v/<id>`
/// - Episode card → `/v/<id>`
/// - Channel card → `/c/<slug>`
///
/// Pretraga je placeholder za Fazu 2.5 (vidi docs/android-tv.md).
class TvHomeScreen extends StatefulWidget {
  const TvHomeScreen({super.key});

  @override
  State<TvHomeScreen> createState() => _TvHomeScreenState();
}

class _TvHomeScreenState extends State<TvHomeScreen> {
  final _channelCache = channelCache;

  late final Future<ChannelIndex> _indexFuture = _channelCache.loadIndex();

  // "Nastavi slušati" rail — uživo iz WatchProgressService.
  List<WatchProgress> _continueWatching = [];

  // Drzimo loading screen (tips) sve dok cijela startup sekvenca ne zavrsi:
  //   1. channel index ucitan (FutureBuilder vec hendla)
  //   2. ChannelCache.done — svih 40 kanala prefetchano
  //   3. HomeFeed.pickFeatured vrati featured pick (algoritam)
  //   4. Thumbnail tog feature pick-a je preloadan (precacheImage)
  // Bez ovoga korisnik vidi tips → onda hero skeleton → onda featured popne
  // gore (dvostruki "flash"). S ovime: tips → instant featured.
  bool _bootReady = false;
  bool _preloadingFeatured = false;

  // FocusNode-ovi za stabilan focus restore (npr. kad se vratimo sa episode
  // screena). U Faza 2 ne implementiramo restore — to je Faza 5 polish — ali
  // node-ove drzimo da fokus nije lost between rebuilds.
  final _searchFocus = FocusNode(debugLabel: 'tv-appbar-search');
  final _heroPlayFocus = FocusNode(debugLabel: 'tv-hero-play');

  // Channel grid sort state. Default: shuffle — fair je za male/nove kanale
  // jer ih svaka sesija stavi na drugu poziciju (count desc bi ih trajno
  // prikovao na dno popisa).
  _ChannelSort _channelSort = _ChannelSort.shuffle;
  List<ChannelSummary>? _shuffledOrder;
  final _shuffleRandom = Random();

  // Lane "Osobe" (virtualni kanali) — iza PersonChannelFlaga. Flag se NE čita
  // prvi put u build(): `isOn` pri prvom čitanju pokrene učitavanje koje u
  // `?vk=1` grani sinkrono zove notifyListeners(), pa bi poziv iz build faze
  // srušio frame. Zato lokalna kopija koju pune initState + listener.
  bool _vkOn = false;
  final _personIndexCache = personIndexCache;

  @override
  void initState() {
    super.initState();
    log('TvHomeScreen.init (Faza 2 — real data wiring)');
    _channelCache.addListener(_onCacheUpdate);
    WatchProgressService.instance.addListener(_loadContinueWatching);
    PersonChannelFlag.instance.addListener(_onFlagChanged);
    _personIndexCache.addListener(_onPersonIndexUpdate);
    _loadContinueWatching();
    unawaited(Future.microtask(_initPersonChannelFlag));
  }

  @override
  void dispose() {
    _channelCache.removeListener(_onCacheUpdate);
    WatchProgressService.instance.removeListener(_loadContinueWatching);
    PersonChannelFlag.instance.removeListener(_onFlagChanged);
    _personIndexCache.removeListener(_onPersonIndexUpdate);
    _searchFocus.dispose();
    _heroPlayFocus.dispose();
    super.dispose();
  }

  Future<void> _initPersonChannelFlag() async {
    await PersonChannelFlag.instance.init();
    _onFlagChanged();
  }

  /// Indeks osoba se dohvaća SAMO kad je flag upaljen — bez njega je to
  /// nepotreban mrežni poziv na endpoint koji do F2 ionako vraća 404.
  void _onFlagChanged() {
    if (!mounted) return;
    final on = PersonChannelFlag.instance.isOn;
    if (on != _vkOn) setState(() => _vkOn = on);
    if (on && !_personIndexCache.loaded) {
      unawaited(_personIndexCache.loadIndex());
    }
  }

  void _onPersonIndexUpdate() {
    if (mounted) setState(() {});
  }

  void _onCacheUpdate() {
    if (!mounted) return;
    setState(() {});
    _maybeBootstrapFeatured();
  }

  /// Pri svakom cache update-u provjeri jesmo li dosegli boot-ready state.
  /// Kada `_channelCache.done` AND `pickFeatured != null`, preload-aj thumb
  /// i tek tad postavi `_bootReady = true` — UI prebaci na pravi content.
  Future<void> _maybeBootstrapFeatured() async {
    if (_bootReady || _preloadingFeatured) return;
    if (!_channelCache.done) return;
    final all = _channelCache.allVideos;
    final pick = HomeFeed.pickFeatured(all);
    if (pick == null) return;
    _preloadingFeatured = true;
    final thumbUrl = CdnConfig.thumbnailUrl(pick.video.video.id);
    log('TvHome: featured ${pick.video.video.id} — preloading thumbnail');
    try {
      // CachedNetworkImageProvider — keeps disk cache warm + ensures the
      // bytes are decoded before TvHero renders, eliminating placeholder
      // blink na boot-ready transition.
      await precacheImage(CachedNetworkImageProvider(thumbUrl), context);
    } catch (e) {
      log('TvHome: featured thumbnail preload failed: $e');
      // Ne blokiramo bootstrap na ovome — radije nudi content sa fallback
      // ikonom nego da forever zaglavi na loading screenu.
    }
    if (!mounted) return;
    setState(() => _bootReady = true);
    log('TvHome: boot ready — switching to content');
  }

  Future<void> _loadContinueWatching() async {
    final list = await WatchProgressService.instance.continueWatching(
      limit: 12,
    );
    if (mounted) setState(() => _continueWatching = list);
  }

  void _openEpisode(String videoId) {
    log('TvHome: navigate /v/$videoId');
    drillDown(context, '/v/$videoId');
  }

  void _openChannel(ChannelSummary channel) {
    final slug = channel.id.replaceAll('_', '-');
    log('TvHome: navigate /c/$slug');
    drillDown(context, '/c/$slug');
  }

  /// Person slug ide DOSLOVNO (bez `-`↔`_` transformacije koju rade kanali).
  void _openPerson(PersonSummary person) {
    log('TvHome: navigate ${person.routePath}');
    drillDown(context, person.routePath);
  }

  bool _loggedDimensions = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = TvMetrics.of(context);
    final l = AppLocalizations.of(context);

    // Jednokratan log MediaQuery dimenzija — pomaze pri kalibraciji TvMetrics
    // na pravim Android TV uredjajima (svaki TV moze imati drugaciji density).
    if (!_loggedDimensions) {
      _loggedDimensions = true;
      final mq = MediaQuery.of(context);
      log(
        'TvHome: screen ${mq.size.width.toStringAsFixed(0)}×'
        '${mq.size.height.toStringAsFixed(0)} dp, '
        'dpr=${mq.devicePixelRatio.toStringAsFixed(2)}, '
        'textScale=${mq.textScaler.scale(1.0).toStringAsFixed(2)}, '
        'tvMetrics.scale=${metrics.scale.toStringAsFixed(2)}',
      );
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      // Klamp textScaler na 1.0 za TV layout. Android TV-i ponekad imaju
      // system "Display size / Font size" postavljen na large/largest
      // (textScaler 1.5-2.0×), sto bodySmall 12sp pretvara u 24sp+ pa rail
      // height + 3-line title overflowa (vidi screencap 2026-05-28).
      // TV typography je vec kalibrirana za 3m couch viewing — system
      // override se ne honor-a, jednako kao sto rade Netflix/YouTube TV.
      body: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: SafeArea(
          // Flutter web ne mapira arrow keys na DirectionalFocusIntent po
          // defaultu (native Android TV salje DPAD_* keyeve koji Flutter okvir
          // sam hendla, ali u Chrome buildu samo Tab radi). Eksplicitno
          // bindamo arrow keys ovdje da TV layout radi i u Chrome/Mac dev
          // okruzenju. WidgetsApp.defaultShortcuts ne pokriva ovo na webu.
          child: Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.arrowUp):
                  DirectionalFocusIntent(TraversalDirection.up),
              SingleActivator(LogicalKeyboardKey.arrowDown):
                  DirectionalFocusIntent(TraversalDirection.down),
              SingleActivator(LogicalKeyboardKey.arrowLeft):
                  DirectionalFocusIntent(TraversalDirection.left),
              SingleActivator(LogicalKeyboardKey.arrowRight):
                  DirectionalFocusIntent(TraversalDirection.right),
            },
            // Retkovna D-pad politika: GORE/DOLJE uvijek ide na susjedni rail
            // (bez nje se lane s malo kartica uz lijevi rub — „Osobe" — nikad
            // ne dosegne kad se silazi iz sredine šireg raila). LIJEVO/DESNO
            // ostaje default, pa kretanje unutar railova i mreže kanala nije
            // dirano. Vidi widgets/tv_row_traversal.dart.
            child: FocusTraversalGroup(
              policy: TvRowTraversalPolicy(),
              child: FutureBuilder<ChannelIndex>(
                future: _indexFuture,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return _buildLoading(theme, metrics);
                  }
                  if (snap.hasError) {
                    return _buildError(theme, l, snap.error);
                  }
                  // Index ucitan — kick off per-channel prefetch.
                  // Trenutno vidljivi index: postavke kanala mogu stići
                  // nakon indexa (povučen kanal tada ispada iz lanea).
                  final channels =
                      _channelCache.index?.channels ?? snap.data!.channels;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _channelCache.prefetchAll(channels);
                    _maybeBootstrapFeatured();
                  });
                  // Tips karousel ostaje vidljiv sve dok featured nije picked
                  // I thumbnail preloadan — vidi `_maybeBootstrapFeatured`.
                  if (!_bootReady) return _buildLoading(theme, metrics);
                  return _buildContent(theme, l, metrics, channels);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // States
  // ---------------------------------------------------------------------------

  Widget _buildLoading(ThemeData theme, TvMetrics metrics) {
    // Channel index prefetch + featured pick + thumbnail preload trazi 3-10s.
    // Koristimo TvBootSplash umjesto TvLoadingTips za vizualni kontinuitet
    // s Android native splash-om — identicna slika (Mt 10,26-28) + diskretni
    // "Učitavanje…" progress na dnu. Korisnik samo nastavi citati isti
    // citat sa native -> Flutter handoff-a bez frame promjene.
    return const TvBootSplash(progressDuration: Duration(seconds: 10));
  }

  Widget _buildError(ThemeData theme, AppLocalizations l, Object? err) {
    log('TvHomeScreen: index ERROR — $err');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Text(
          l.tvChannelLoadError('$err'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
      ),
    );
  }

  Widget _buildContent(
    ThemeData theme,
    AppLocalizations l,
    TvMetrics metrics,
    List<ChannelSummary> channels,
  ) {
    final allVids = _channelCache.allVideos;
    // Lane "Osobe": samo osobe koje backend proglasi virtualnim kanalom (prag
    // + opt-out); prazno dok je flag ugašen ili indeks nije stigao.
    final persons =
        _vkOn ? _personIndexCache.virtualChannels : const <PersonSummary>[];
    // Cekamo full prefetch prije nego pick-amo featured — bez ovoga
    // HomeFeed.pickFeatured se rebuilda na svakom channel cache update-u
    // (30% threshold pa onda done), pa korisnik vidi flash izmedju kandidata
    // 1-2s nakon load-a. S done-gate-om hero ostaje skeleton dok ne stigne
    // stabilan izbor.
    final cacheReady = _channelCache.done;
    final featured = cacheReady ? HomeFeed.pickFeatured(allVids) : null;
    final latest = featured != null
        ? HomeFeed.latestEpisodes(
            allVids,
            limit: 12,
            excludeFeatured: featured.video,
          )
        : <FeedVideo>[];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildAppBar(theme, l, metrics),
          if (featured != null)
            TvHero(
              featured: featured,
              metrics: metrics,
              playFocusNode: _heroPlayFocus,
              autofocusPlay: true,
              onPlay: () => _openEpisode(featured.video.video.id),
            )
          else
            _buildHeroSkeleton(theme, metrics),

          // Razmak izmedju hero-a i prvog rail-a — focused card scale 1.18
          // + glow shadow s `Clip.none` na rail-u overflowa vertikalno, pa
          // bez ovog prostora gornji rub kartice udara u hero ispod.
          SizedBox(height: metrics.heroToRailGap),

          if (visibleContinueWatching(_continueWatching).isNotEmpty) ...[
            TvRail(
              eyebrow: l.tvRailContinueListening,
              height: metrics.episodeRailHeight,
              cardSpacing: metrics.cardSpacing,
              horizontalPadding: EdgeInsets.symmetric(
                horizontal: metrics.pagePadH,
              ),
              cards: [
                for (final wp in visibleContinueWatching(_continueWatching))
                  TvEpisodeCard(
                    episodeId: wp.episodeId,
                    title: wp.episodeTitle ?? wp.episodeId,
                    progress: wp.durationSeconds > 0
                        ? wp.positionSeconds / wp.durationSeconds
                        : null,
                    width: metrics.episodeCardWidth,
                    onTap: () => _openEpisode(wp.episodeId),
                  ),
              ],
            ),
            SizedBox(height: metrics.sectionGap),
          ],

          if (latest.isNotEmpty)
            TvRail(
              eyebrow: l.tvRailLatestEpisodes,
              height: metrics.episodeRailHeight,
              cardSpacing: metrics.cardSpacing,
              horizontalPadding: EdgeInsets.symmetric(
                horizontal: metrics.pagePadH,
              ),
              cards: [
                for (final fv in latest)
                  TvEpisodeCard(
                    episodeId: fv.video.id,
                    title: fv.video.displayTitle,
                    subtitle: fv.channelName,
                    magisteriumScore: fv.video.magisteriumScore,
                    width: metrics.episodeCardWidth,
                    onTap: () => _openEpisode(fv.video.id),
                  ),
              ],
            )
          else if (!cacheReady)
            _buildRailSkeleton(theme, metrics, l.tvRailLatestEpisodes),

          SizedBox(height: metrics.sectionGap),

          // Lane "Osobe" — virtualni kanali (osoba koja gostuje kroz tuđe
          // kanale). Prazan dok flag nije upaljen ILI dok backend nema
          // /api/persons; tada se sekcija jednostavno ne crta.
          if (persons.isNotEmpty) ...[
            TvRail(
              eyebrow: l.tvRailPersons,
              height: metrics.channelRailHeight,
              cardSpacing: metrics.cardSpacing,
              horizontalPadding: EdgeInsets.symmetric(
                horizontal: metrics.pagePadH,
              ),
              cards: [
                for (final p in persons)
                  _TvPersonCard(
                    person: p,
                    size: metrics.channelCardSize,
                    onTap: () => _openPerson(p),
                  ),
              ],
            ),
            SizedBox(height: metrics.sectionGap),
          ],

          if (channels.isNotEmpty)
            _buildChannelsSection(theme, l, metrics, channels),

          SizedBox(height: metrics.sectionGap),
          _buildCacheStatus(theme, l, metrics),
          SizedBox(height: metrics.sectionGap),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // App bar
  // ---------------------------------------------------------------------------

  Widget _buildAppBar(ThemeData theme, AppLocalizations l, TvMetrics metrics) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        metrics.pagePadH,
        metrics.pagePadV,
        metrics.pagePadH,
        metrics.pagePadV * 0.4,
      ),
      child: Row(
        children: [
          Text(
            AppBrand.config.appName,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
              fontSize:
                  (theme.textTheme.titleLarge?.fontSize ?? 22) * metrics.scale,
            ),
          ),
          const Spacer(),
          TvFocusable(
            style: TvFocusStyle.subtleButton,
            focusNode: _searchFocus,
            borderRadius: BorderRadius.circular(12),
            onActivate: () => log('TvHome: pretraga (Faza 2.5)'),
            builder: (context, focused) => AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: EdgeInsets.symmetric(
                horizontal: 16 * metrics.scale,
                vertical: 10 * metrics.scale,
              ),
              decoration: BoxDecoration(
                color: focused
                    ? theme.colorScheme.primaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.search,
                    size: 20 * metrics.scale,
                    color: theme.colorScheme.onSurface,
                  ),
                  SizedBox(width: 8 * metrics.scale),
                  Text(l.tvSearch, style: theme.textTheme.titleSmall),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Skeletons (minimal — full editorial skeleton je u home_screen.dart;
  // za TV cilj je tek 'nije prazno' indikacija dok prefetch traje).
  // ---------------------------------------------------------------------------

  /// Skeleton koji prati `TvHero` shape (max metrics.heroMaxWidth, slika
  /// lijevo / blok desno) — bez ovoga bi layout poskocio kad real hero stigne.
  Widget _buildHeroSkeleton(ThemeData theme, TvMetrics metrics) {
    final maxHeight = metrics.heroMaxHeight;
    final compact = maxHeight < 260;
    final imageWidth = (maxHeight * 16 / 9).clamp(320.0, 480.0);
    final block = theme.colorScheme.surfaceContainerHighest;

    return Padding(
      padding: EdgeInsets.fromLTRB(metrics.pagePadH, 8, metrics.pagePadH, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: metrics.heroMaxWidth),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Material(
              color: theme.colorScheme.surfaceContainerLowest,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: imageWidth,
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Container(
                          color: block,
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              color: theme.colorScheme.primary,
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          compact ? 24 : 36,
                          compact ? 20 : 28,
                          compact ? 24 : 36,
                          compact ? 20 : 28,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _SkeletonBar(width: 140, height: 14, color: block),
                            SizedBox(height: compact ? 14 : 18),
                            _SkeletonBar(
                              width: double.infinity,
                              height: 22,
                              color: block,
                            ),
                            const SizedBox(height: 10),
                            _SkeletonBar(width: 260, height: 22, color: block),
                            SizedBox(height: compact ? 14 : 18),
                            _SkeletonBar(width: 200, height: 14, color: block),
                            SizedBox(height: compact ? 18 : 26),
                            _SkeletonBar(width: 180, height: 44, color: block),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRailSkeleton(
    ThemeData theme,
    TvMetrics metrics,
    String eyebrow,
  ) {
    // Kao u TvRail: lista je edge-to-edge, pagePadH je content padding
    // UNUTAR liste, ne vanjska margina koja bi rezala scroll.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: metrics.pagePadH),
          child: Row(
            children: [
              Container(
                width: 28 * metrics.scale,
                height: 3,
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
              ),
              SizedBox(width: 10 * metrics.scale),
              Text(
                eyebrow.toUpperCase(),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 1.6,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 12 * metrics.scale),
        SizedBox(
          height: metrics.episodeRailHeight - 18,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: metrics.pagePadH),
            itemCount: 4,
            separatorBuilder: (_, _) => SizedBox(width: metrics.cardSpacing),
            itemBuilder: (context, i) => Container(
              width: metrics.episodeCardWidth,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Channel sort / grid
  // ---------------------------------------------------------------------------

  List<ChannelSummary> _orderChannels(List<ChannelSummary> input) {
    switch (_channelSort) {
      case _ChannelSort.shuffle:
        // Shuffle se cache-a (`_shuffledOrder`) da redoslijed bude STABILAN
        // izmedju setState rebuilda. Re-shuffle se dogadja samo kad user
        // tapne Shuffle button (vidi `_setSort`).
        return _shuffledOrder ??= List<ChannelSummary>.from(input)
          ..shuffle(_shuffleRandom);
      case _ChannelSort.alpha:
        return List<ChannelSummary>.from(
          input,
        )..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case _ChannelSort.countDesc:
        return List<ChannelSummary>.from(input)
          ..sort((a, b) => b.videoCount.compareTo(a.videoCount));
      case _ChannelSort.countAsc:
        return List<ChannelSummary>.from(input)
          ..sort((a, b) => a.videoCount.compareTo(b.videoCount));
    }
  }

  void _setSort(_ChannelSort sort) {
    setState(() {
      if (sort == _ChannelSort.shuffle) {
        // Re-shuffle UVIJEK kad user tapne Shuffle, cak i ako je vec shuffle
        // mode. Daje pravu randomness ako zeli "jos jednom".
        _shuffledOrder = null;
      }
      _channelSort = sort;
    });
  }

  Widget _buildChannelsSection(
    ThemeData theme,
    AppLocalizations l,
    TvMetrics metrics,
    List<ChannelSummary> channels,
  ) {
    final ordered = _orderChannels(channels);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: metrics.pagePadH),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: eyebrow naslov + sort chips u istom redu. Sort chips se
          // wrappaju u novi red ako nema dovoljno prostora.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12 * metrics.scale,
            runSpacing: 8 * metrics.scale,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 28,
                    height: 3,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    l.tvChannelsWithCount(ordered.length).toUpperCase(),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.6,
                    ),
                  ),
                ],
              ),
              _buildSortChip(
                theme: theme,
                metrics: metrics,
                sort: _ChannelSort.countDesc,
                icon: Icons.arrow_downward,
                label: l.tvSortEpisodes,
              ),
              _buildSortChip(
                theme: theme,
                metrics: metrics,
                sort: _ChannelSort.countAsc,
                icon: Icons.arrow_upward,
                label: l.tvSortEpisodes,
              ),
              _buildSortChip(
                theme: theme,
                metrics: metrics,
                sort: _ChannelSort.alpha,
                icon: Icons.sort_by_alpha,
                label: l.tvSortAlpha,
              ),
              _buildSortChip(
                theme: theme,
                metrics: metrics,
                sort: _ChannelSort.shuffle,
                icon: Icons.shuffle,
                label: l.tvSortShuffle,
              ),
            ],
          ),
          SizedBox(height: 16 * metrics.scale),
          // Wrap grid — auto-flow po broju kolona koji stane u dostupnu
          // sirinu. Channel cards su consistent width (metrics.channelCardSize)
          // pa Wrap producira regularan grid bez explicit-nog GridView-a (koji
          // ima problema s D-pad fokus traversal-om kod variable item-height-a).
          Wrap(
            spacing: metrics.cardSpacing,
            runSpacing: 24 * metrics.scale,
            children: [
              for (final c in ordered)
                TvChannelCard(
                  channel: c,
                  size: metrics.channelCardSize,
                  onTap: () => _openChannel(c),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSortChip({
    required ThemeData theme,
    required TvMetrics metrics,
    required _ChannelSort sort,
    required IconData icon,
    required String label,
  }) {
    final active = _channelSort == sort;
    // Pill shape (radius 100 → Flutter clamp na pola visine) i na outer
    // (TvFocusable focus outline) i na inner (chip bg). Tako outer i inner
    // radius razlikuju se TOCNO za 5dp (border width), pa fokus prsten leži
    // savrseno koncentricno oko chip-a. Radius 20 (fixed) bio je problem
    // jer su inner i outer imali ISTI radius ali na razlicitim dimensijama
    // — inner je izgledao previse zaobljen relativno na svoj manji rect.
    return TvFocusable(
      style: TvFocusStyle.subtleButton,
      borderRadius: BorderRadius.circular(100),
      onActivate: () => _setSort(sort),
      builder: (context, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(
          horizontal: 10 * metrics.scale,
          vertical: 6 * metrics.scale,
        ),
        decoration: BoxDecoration(
          color: active
              ? theme.colorScheme.tertiary
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14 * metrics.scale,
              color: active
                  ? theme.colorScheme.onTertiary
                  : theme.colorScheme.onSurface,
            ),
            SizedBox(width: 5 * metrics.scale),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: active
                    ? theme.colorScheme.onTertiary
                    : theme.colorScheme.onSurface,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCacheStatus(
    ThemeData theme,
    AppLocalizations l,
    TvMetrics metrics,
  ) {
    if (_channelCache.done) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: metrics.pagePadH),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            l.tvLoadingChannels(_channelCache.loaded, _channelCache.total),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

enum _ChannelSort { shuffle, alpha, countDesc, countAsc }

/// Kartica osobe u laneu "Osobe" — vizualno blizanac [TvChannelCard] (isti
/// kvadrat, ista tipografija), jer osoba mora stajati ravnopravno uz kanal.
///
/// Razlika: avatar je [PersonMonogram] (osoba nema cover — odluka O5 u
/// `docs/plans/virtualni-kanali.md`), a to da je riječ o osobi nosi eyebrow
/// naslov rail-a. Meta redak ostaje broj epizoda kao kod kanala — puni
/// „Osoba · N ep · Xh Ym" ne stane u širinu TV kartice bez odsijecanja.
class _TvPersonCard extends StatelessWidget {
  final PersonSummary person;
  final double size;
  final VoidCallback onTap;

  const _TvPersonCard({
    required this.person,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return TvFocusable(
      onActivate: onTap,
      builder: (context, focused) => SizedBox(
        width: size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            PersonMonogram(
              name: person.name,
              avatarUrl: person.avatarUrl,
              size: size,
              radius: 0,
            ),
            const SizedBox(height: 8),
            // Do 3 reda imena bez ellipsis-a — isto pravilo kao TvChannelCard
            // (duga imena se prelijevaju, ne odsijecaju).
            Text(
              person.name,
              maxLines: 3,
              softWrap: true,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              l.tvEpisodeCountPlural(person.episodeCount),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  final double width;
  final double height;
  final Color color;

  const _SkeletonBar({
    required this.width,
    required this.height,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
