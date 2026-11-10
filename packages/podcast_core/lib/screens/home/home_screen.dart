import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../src/log.dart' show log;
import '../../brand/app_brand.dart';
import '../../models/episode_status.dart';
import '../../models/channel_index.dart';
import '../../services/app_install_banner.dart';
import '../../services/cdn_config.dart';
import '../../services/episode_prefetch.dart';
import '../../services/channel_cache.dart';
import '../../services/local_prefs.dart';
import '../../services/page_meta.dart';
import '../../services/scroll_memory.dart';
import '../../services/view_mode.dart';
import '../../services/watch_progress_service.dart';
import '../../widgets/founder_booking.dart';
import '../../l10n/app_localizations.dart';
import 'episode_rail_card.dart';
import 'episodes_rail.dart';
import 'favorites_rail.dart';
import 'catalog_day_rail.dart';
import 'followed_rail.dart';
import 'footer.dart';
import 'home_app_bar.dart';
import 'home_feed.dart';
import 'hero_carousel.dart';
import 'persons_rail.dart';
import 'search_overlay.dart';
import 'skeletons.dart';
import 'sort_mode.dart';
import 'voting_rail.dart';
import 'variants/home_variants.dart';
import '../../router/nav.dart';
import '../../services/share_language.dart';
import '../../services/share_links.dart';

const _channelOrderKey = 'channel_order';

// ---------------------------------------------------------------------------
// Channel order persistence
// ---------------------------------------------------------------------------
// Web: SharedPreferences throws MissingPluginException in release builds
//      (dart2js strips the method channel registration). Use localStorage.
// Native (iOS/Android/macOS): SharedPreferences works normally.
// ---------------------------------------------------------------------------

List<String>? _loadOrderWeb() {
  final raw = getLocalStorageString(_channelOrderKey);
  if (raw == null) return null;
  return raw.split(',');
}

void _saveOrderWeb(List<String> ids) {
  setLocalStorageString(_channelOrderKey, ids.join(','));
}

/// Home screen — channel grid + search + manual YouTube ID input.
///
/// Razdvojeno iz monolitnog `lib/screens/home_screen.dart` u Korak 2 redizajna.
/// Channel detail view (`/c/:slug`) sad ima vlastiti `ChannelScreen` widget
/// (vidi `lib/screens/channel/channel_screen.dart`).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _channelCache = channelCache;

  late Future<ChannelIndex> _indexFuture;

  // Ordered channel list (shuffled once, persisted).
  //
  // Živi u `ChannelCache` singletonu, NE u ovom State-u — vidi komentar uz
  // `ChannelCache.orderedChannels`. Time naslovnica u PRVOM frameu nakon
  // povratka crta puni sadržaj umjesto skeletona, pa joj visina ne raste u
  // asinkronim skokovima i vraćanje scroll pozicije ima stabilnu metu.

  // Simple/Detailed mode — auto-defaults to simple on mobile
  bool _simpleMode = false;

  // "Nastavi slušati" rail data — live from WatchProgressService.
  List<WatchProgress> _continueWatching = [];

  // Sort mode za channel grid.
  ChannelSortMode _sortMode = ChannelSortMode.custom;

  @override
  void initState() {
    super.initState();
    // Povratak na home vraća default <title>/og meta (episode/channel ekrani
    // su ih runtime-overridali — vidi services/page_meta.dart).
    resetPageMeta();
    _indexFuture = _channelCache.loadIndex();
    // `home.json` paralelno s indexom: kad stigne (~10 KB), hero i railovi
    // se crtaju bez čekanja listinga. Bez njega (404 dok ga pipeline ne
    // generira) sve ide starim putem — vidi `HomeSnapshot`.
    unawaited(_channelCache.loadHomeSnapshot());
    // Prefetch svih channel detalja čim index stigne — DETERMINISTIČKI, neovisno
    // o build timingu i simpleMode pref-u. (Ranije se zvao iz onChannelsLoaded
    // iza `if (!_simpleModeLoaded) return;`, što je preskakalo prefetch kad bi
    // index stigao prije simpleMode pref-a → hero/thumbnaili ostali prazni.)
    // prefetchAll ima vlastiti guard protiv dvostrukog pokretanja.
    _indexFuture.then((index) => _channelCache.prefetchAll(index.channels));
    _channelCache.addListener(_onCacheUpdate);
    WatchProgressService.instance.addListener(_loadContinueWatching);
    _loadSimpleMode();
    _loadContinueWatching();
    _initSortMode();
    // App-install nudge (Android + iOS non-Safari) — nakon prvog framea da
    // padne preko već iscrtane naslovnice, ne blokira boot. iOS Safari pokriva
    // Apple Smart App Banner (meta u index.html).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowAppInstallBanner(context);
    });
  }

  Future<void> _initSortMode() async {
    final saved = await loadSortMode();
    if (saved != null) {
      if (mounted) setState(() => _sortMode = saved);
      return;
    }
    // Migracija s legacy channel_order — ako postoji, znaci da je user
    // ranije imao shuffle redoslijed; nemoj mu ga resetirati.
    List<String>? legacy;
    if (kIsWeb) {
      legacy = _loadOrderWeb();
    } else {
      final prefs = await SharedPreferences.getInstance();
      legacy = prefs.getStringList(_channelOrderKey);
    }
    final initial = (legacy != null && legacy.isNotEmpty)
        ? ChannelSortMode.custom
        : ChannelSortMode.newest;
    await saveSortMode(initial);
    if (mounted) setState(() => _sortMode = initial);
  }

  Future<void> _loadContinueWatching() async {
    final list =
        await WatchProgressService.instance.continueWatching(limit: 12);
    if (mounted) setState(() => _continueWatching = list);
  }

  Future<void> _loadSimpleMode() async {
    final saved = await loadSimpleModePref();
    if (mounted) {
      setState(() => _simpleMode = saved ?? false);
    }
  }

  List<ChannelSummary>? get _orderedChannels => _channelCache.orderedChannels;

  void _onCacheUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _channelCache.removeListener(_onCacheUpdate);
    WatchProgressService.instance.removeListener(_loadContinueWatching);
    super.dispose();
  }

  /// Otvara search overlay modal — koristi se i za app bar search trigger
  /// i za Cmd+K shortcut.
  Future<void> _openSearchOverlay() async {
    final index = _channelCache.index;
    if (index == null) return; // index jos nije ucitan
    await showSearchOverlay(
      context,
      channels: index.channels,
      onSelectChannel: _selectChannel,
      onSelectVideo: _openVideo,
      onSelectVideoAt: _openVideoAt,
    );
  }

  /// Otvori epizodu na zadanom timestampu (semantic search deep link).
  void _openVideoAt(String videoId, int seconds) {
    drillDown(context, '/v/$videoId/t/$seconds');
  }

  /// Primijeni aktivni sort mode na kanale. Za 'custom' mode koristi spremljen
  /// channel_order; ako ga nema, prvi put generira shuffle i sprema.
  Future<List<ChannelSummary>> _applyOrder(
      List<ChannelSummary> channels) async {
    List<String>? savedOrder;
    if (kIsWeb) {
      savedOrder = _loadOrderWeb();
    } else {
      final prefs = await SharedPreferences.getInstance();
      savedOrder = prefs.getStringList(_channelOrderKey);
    }

    if (_sortMode == ChannelSortMode.custom) {
      if (savedOrder != null && savedOrder.isNotEmpty) {
        return applySortMode(channels, ChannelSortMode.custom,
            customOrder: savedOrder);
      }
      // First visit s custom mode — shuffle and persist.
      final shuffled = List<ChannelSummary>.from(channels)..shuffle(Random());
      final ids = shuffled.map((c) => c.id).toList();
      if (kIsWeb) {
        _saveOrderWeb(ids);
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_channelOrderKey, ids);
      }
      return shuffled;
    }

    return applySortMode(channels, _sortMode, customOrder: savedOrder);
  }

  void _selectChannel(ChannelSummary channel) {
    final slug = channel.id.replaceAll('_', '-');
    drillDown(context, '/c/$slug');
  }

  /// Naslovnica → epizoda je drill-down: `push` zadrži OVAJ ekran živ ispod,
  /// pa se na `pop()` vraća ista instanca sa svojim scrollom. Prije 6.9.2026.
  /// je bio `go()`, koji je `HomeScreen` uništio — zato se scroll nije vraćao.
  void _openVideo(String videoId) {
    drillDown(context, _simpleMode ? '/m/$videoId' : '/v/$videoId');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      // „15 min s osnivačem” — samo brendovi s Cal.com integracijom.
      floatingActionButton: AppBrand.config.flags.calBooking
          ? const FounderBookingBubble()
          : null,
      body: SafeArea(
        child: CallbackShortcuts(
          bindings: {
            // Cmd+K (macOS) / Ctrl+K (Windows/Linux) → otvara search overlay.
            const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
                _openSearchOverlay,
            const SingleActivator(LogicalKeyboardKey.keyK, control: true):
                _openSearchOverlay,
          },
          child: Focus(
            autofocus: true,
            child: _ChannelGridView(
              indexFuture: _indexFuture,
              orderedChannels: _orderedChannels,
              channelCache: _channelCache,
              continueWatching: _continueWatching,
              onChannelsLoaded: (channels) async {
                // Samo izračun redoslijeda za prikaz. Prefetch je premješten u
                // initState (vezan na index load) da se ne preskoči zbog race-a.
                final ordered = await _applyOrder(channels);
                _channelCache.setOrderedChannels(ordered);
                if (mounted) setState(() {});
              },
              onSearchTap: _openSearchOverlay,
              onVideoTap: _openVideo,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Channel grid
// ---------------------------------------------------------------------------

class _ChannelGridView extends StatefulWidget {
  final Future<ChannelIndex> indexFuture;
  final List<ChannelSummary>? orderedChannels;
  final ChannelCache channelCache;
  final List<WatchProgress> continueWatching;
  final Future<void> Function(List<ChannelSummary>) onChannelsLoaded;
  final VoidCallback onSearchTap;
  final void Function(String videoId) onVideoTap;

  const _ChannelGridView({
    required this.indexFuture,
    required this.orderedChannels,
    required this.channelCache,
    required this.continueWatching,
    required this.onChannelsLoaded,
    required this.onSearchTap,
    required this.onVideoTap,
  });

  @override
  State<_ChannelGridView> createState() => _ChannelGridViewState();
}

/// Drži **latch** hero izbora.
///
/// `channelCache` javlja svakim učitanim kanalom, a `pickFeaturedCarousel`
/// rangira po TRENUTNO učitanom bazenu — dok prefetch teče, hero je zato
/// mijenjao epizode svakih par stotina ms (vidljivo kao bljeskanje i skakanje
/// stranice). Sada se izbor izračuna **jednom**, kad je bazen konačan, i više
/// se ne dira; do tada stoji [HeroSkeleton] iste visine.
///
/// Konačan bazen = [HomeFeed.heroPoolComplete]: svi kanali koji mogu nositi
/// tier 1 kandidata su učitani (ili je prefetch gotov). Sigurnosni ventil je [_graceWindow]:
/// ako se prefetch zaglavi na jednom kanalu, nakon njega se latcha ono što
/// imamo (uz [HomeFeed.hasMinimumData]) da hero ne ostane skeleton zauvijek.
class _ChannelGridViewState extends State<_ChannelGridView> {
  static const _graceWindow = Duration(seconds: 6);

  List<FeaturedPick>? _lockedPicks;
  bool _graceElapsed = false;
  Timer? _graceTimer;

  /// Naslovnica do 6.9.2026. nije imala NIJEDAN `ScrollController` — pa se
  /// pozicija nije imala odakle ni pročitati. Glavni mehanizam za povratak
  /// scrolla je `push` (naslovnica ostaje živa ispod), a ovaj kontroler pokriva
  /// slučajeve u kojima se ekran stvarno gradi iznova — vidi `ScrollMemory`.
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _graceTimer = Timer(_graceWindow, () {
      if (mounted) setState(() => _graceElapsed = true);
    });
  }

  @override
  void dispose() {
    _graceTimer?.cancel();
    _idlePrefetchTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// Vrati latchani izbor, ili ga latchaj ako je bazen konačan. `null` znači
  /// "još ne znamo" → crtaj skeleton.
  List<FeaturedPick>? _featuredPicks(ChannelCache cache) {
    final locked = _lockedPicks;
    if (locked != null) return locked;
    final poolFinal = HomeFeed.heroPoolComplete(cache) ||
        (_graceElapsed && HomeFeed.hasMinimumData(cache));
    if (!poolFinal) return null;
    final picks = HomeFeed.pickFeaturedCarousel(cache.feedVideos);
    _scheduleIdlePrefetch(picks);
    return _lockedPicks = picks;
  }

  /// Kad se hero smiri, predučitaj epizodu koju korisnik najvjerojatnije
  /// otvara: prvi hero pick i prve iz „Nastavi slušati". Odgoda pušta slike
  /// naslovnice ispred. Vidi [EpisodePrefetch].
  void _scheduleIdlePrefetch(List<FeaturedPick> picks) {
    _idlePrefetchTimer?.cancel();
    _idlePrefetchTimer = Timer(_idlePrefetchDelay, () {
      EpisodePrefetch.instance.idle([
        if (picks.isNotEmpty) picks.first.video.video.id,
        for (final wp in widget.continueWatching.take(3)) wp.episodeId,
      ]);
    });
  }

  static const _idlePrefetchDelay = Duration(seconds: 2);
  Timer? _idlePrefetchTimer;

  @override
  Widget build(BuildContext context) {
    final indexFuture = widget.indexFuture;
    final orderedChannels = widget.orderedChannels;
    final channelCache = widget.channelCache;
    final continueWatching = widget.continueWatching;
    final onChannelsLoaded = widget.onChannelsLoaded;
    final onSearchTap = widget.onSearchTap;
    final onVideoTap = widget.onVideoTap;

    // Restorer omata SVE grane odjednom (loading / greška / skeleton / puni
    // sadržaj) jer sve dijele isti kontroler — pozicija se ne smije izgubiti
    // pri prelasku između njih dok podaci pristižu.
    return ScrollRestorer(
      storageKey: '/',
      controller: _scrollController,
      child: FutureBuilder<ChannelIndex>(
        future: indexFuture,
        builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return CustomScrollView(
            controller: _scrollController,
            slivers: [
              HomeAppBar(onSearchTap: onSearchTap),
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          );
        }
        if (snap.hasError) {
          log('ChannelIndex ERROR: ${snap.error}');
          return CustomScrollView(
            controller: _scrollController,
            slivers: [
              HomeAppBar(onSearchTap: onSearchTap),
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                        AppLocalizations.of(context)
                            .homeChannelsLoadError('${snap.error}'),
                        textAlign: TextAlign.center),
                  ),
                ),
              ),
            ],
          );
        }

        // Trigger order computation once
        final raw = snap.data!.channels;
        if (orderedChannels == null) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => onChannelsLoaded(raw));
          return LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 600;
              return CustomScrollView(
                controller: _scrollController,
                slivers: [
                  HomeAppBar(onSearchTap: onSearchTap),
                  SliverToBoxAdapter(
                      child: HeroSkeleton(isMobile: isMobile)),
                  SliverToBoxAdapter(
                      child: RailSkeleton(isMobile: isMobile)),
                  SliverToBoxAdapter(
                      child: ChannelGridSkeleton(isMobile: isMobile)),
                ],
              );
            },
          );
        }

        final channels = orderedChannels;

        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final isMobile = width < 600;
            final l = AppLocalizations.of(context);

            // Search rezultati su sada u overlay-u (Cmd+K). Channel grid
            // uvijek pokazuje pun listing po aktivnom sort modu.
            final allVids = channelCache.feedVideos;
            final hasMinData = HomeFeed.hasMinimumData(channelCache);
            // Uži izbor (do 5) za hero karusel; prvi je dnevni pick. `null` =
            // bazen još nije konačan, hero stoji na skeletonu (vidi
            // [_ChannelGridViewState]). Rail-ovi ispod iz istog razloga
            // izuzimaju baš latchanu epizodu, nikad "trenutno najbolju".
            final featuredPicks = _featuredPicks(channelCache);
            final featured = (featuredPicks == null || featuredPicks.isEmpty)
                ? null
                : featuredPicks.first;
            // "Upravo stiglo" — tek pristigle, još neobrađene epizode.
            final freshlyArrived = featured != null
                ? HomeFeed.freshlyArrived(allVids,
                    limit: 12, excludeFeatured: featured.video)
                : const <FeedVideo>[];

            // Eksperimentalne varijante layouta (`?home=a|b|c`) — bez
            // parametra ova grana ne postoji i crta se naslovnica ispod.
            // Plan: docs/plans/2026-11-10-naslovnica-varijante-abc.md.
            final variant = HomeVariantFlag.current;
            if (variant != null) {
              return buildHomeVariant(
                variant,
                HomeVariantData(
                  featuredPicks: featuredPicks,
                  allVids: allVids,
                  continueWatching: continueWatching,
                  freshlyArrived: freshlyArrived,
                  channels: channels,
                  hasMinData: hasMinData,
                  width: width,
                  scrollController: _scrollController,
                  onSearchTap: onSearchTap,
                  onVideoTap: onVideoTap,
                ),
              );
            }

            return CustomScrollView(
              controller: _scrollController,
              slivers: [
                HomeAppBar(onSearchTap: onSearchTap),
                SliverToBoxAdapter(
                  child: _HomeHeader(
                    cacheProgress: channelCache.done ||
                            channelCache.homeSnapshot != null
                        ? null
                        : (channelCache.loaded, channelCache.total),
                    isMobile: isMobile,
                  ),
                ),

                // Hero — uži izbor istaknutih epizoda u karuselu. Skeleton
                // stoji dok izbor nije konačan, pa se hero otkrije jednim
                // fadeom. Skeleton je iste visine (uklj. kontrolnu traku), pa
                // zamjena ne pomiče ništa ispod sebe; `layoutBuilder` slaže
                // stari i novi u Stack da AnimatedSwitcher ne animira veličinu.
                SliverToBoxAdapter(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOut,
                    layoutBuilder: (currentChild, previousChildren) => Stack(
                      alignment: Alignment.topCenter,
                      children: [
                        ...previousChildren,
                        ?currentChild,
                      ],
                    ),
                    child: featuredPicks == null
                        ? HeroSkeleton(
                            key: const ValueKey('hero-skeleton'),
                            isMobile: isMobile,
                          )
                        : featuredPicks.isEmpty
                            ? const SizedBox.shrink(key: ValueKey('hero-none'))
                            : HeroCarousel(
                                key: const ValueKey('hero-carousel'),
                                picks: featuredPicks,
                                isMobile: isMobile,
                                onPlay: (id) => onVideoTap(id),
                              ),
                  ),
                ),

                // Rail „Izborni dan" — vrh ljestvice kandidata za sljedeći
                // kanal (plan §8.6). Stoji IZNAD „Nastavi slušati" jer je za
                // većinu korisnika jedini susret s glasanjem: `/glasanje` je
                // inače dostupan samo s trake na dnu `/channels`, a chip u
                // zaglavlju vidi tek onaj tko je već potvrđen e-Osobnom. Sam
                // se sakrije kad kola nema ili ljestvica ne stigne.
                if (AppBrand.config.flags.voting)
                  SliverToBoxAdapter(child: VotingRail(isMobile: isMobile)),

                // "Nastavi slušati" rail — samo ako ima itema.
                // Thumbnail uvijek konstruiramo iz CDN-a (ignoriraj denorm
                // episodeThumbnailUrl ako pokazuje na i.ytimg.com — stari
                // zapisi prije fix-a). Sad smo deterministicki.
                if (continueWatching.isNotEmpty)
                  SliverToBoxAdapter(
                    child: EpisodesRail(
                      eyebrow: l.homeRailContinue,
                      isMobile: isMobile,
                      cards: continueWatching
                          .map((wp) => EpisodeRailCard(
                                title: wp.episodeTitle ?? wp.episodeId,
                                thumbnailUrl:
                                    CdnConfig.thumbnailUrl(wp.episodeId),
                                progress: wp.durationSeconds > 0
                                    ? wp.positionSeconds / wp.durationSeconds
                                    : null,
                                width: isMobile ? 180 : 220,
                                shareUrl: () => episodeShareUrl(
                                  wp.episodeId,
                                  lang: shareLanguageForVideo(wp.episodeId),
                                ),
                                prefetchEpisodeId: wp.episodeId,
                                onTap: () => onVideoTap(wp.episodeId),
                              ))
                          .toList(),
                    ),
                  ),

                // Rail "Novo od praćenih" — po jedna neviđena epizoda za svaki
                // praćeni kanal/osobu. Osobni je pa stoji uz "Nastavi slušati",
                // iznad uredničkih railova. Sam se sakrije bez flaga, bez
                // praćenja ili kad nema ničeg novog. Vidi followed_rail.dart.
                SliverToBoxAdapter(
                  child: FollowedRail(
                    isMobile: isMobile,
                    onVideoTap: onVideoTap,
                  ),
                ),

                // Istaknuti kanali brenda (BrandConfig.featuredChannels) —
                // prazno i nevidljivo kad brend ništa ne ističe.
                if (featured != null && allVids.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Builder(builder: (context) {
                      final shows = HomeFeed.featuredShows(allVids,
                          limit: 12, excludeFeatured: featured.video);
                      if (shows.isEmpty) return const SizedBox.shrink();
                      return EpisodesRail(
                        eyebrow: l.homeRailFeaturedShows,
                        isMobile: isMobile,
                        cards: shows
                            .map((fv) => EpisodeRailCard(
                                  title: fv.video.displayTitle,
                                  subtitle: fv.channelName,
                                  thumbnailUrl:
                                      CdnConfig.thumbnailUrl(fv.video.id),
                                  dateLabel: fv.video.date,
                                  magisteriumScore: fv.video.magisteriumScore,
                                  width: isMobile ? 180 : 220,
                                  shareUrl: () => episodeShareUrl(
                                    fv.video.id,
                                    lang: shareLanguageForVideo(fv.video.id),
                                  ),
                                  onTap: () => onVideoTap(fv.video.id),
                                ))
                            .toList(),
                      );
                    }),
                  ),

                // "Najnovije epizode" rail — cross-channel po datumu desc.
                // CDN URL eksplicitno (`fv.video.thumbnail` moze biti ytimg
                // URL iz pipeline-a, sto blokira CORS na web build-u).
                if (featured != null && allVids.isNotEmpty)
                  SliverToBoxAdapter(
                    child: EpisodesRail(
                      eyebrow: l.homeRailLatest,
                      isMobile: isMobile,
                      cards: HomeFeed.latestEpisodes(allVids,
                              limit: 12, excludeFeatured: featured.video)
                          .map((fv) => EpisodeRailCard(
                                title: fv.video.displayTitle,
                                subtitle: fv.channelName,
                                thumbnailUrl:
                                    CdnConfig.thumbnailUrl(fv.video.id),
                                dateLabel: fv.video.date,
                                magisteriumScore: fv.video.magisteriumScore,
                                width: isMobile ? 180 : 220,
                                shareUrl: () => episodeShareUrl(
                                  fv.video.id,
                                  lang: shareLanguageForVideo(fv.video.id),
                                ),
                                prefetchEpisodeId: fv.video.id,
                                onTap: () => onVideoTap(fv.video.id),
                              ))
                          .toList(),
                    ),
                  )
                // Skeleton stoji i dok hero izbor nije latchan — rail izuzima
                // baš tu epizodu, pa ga ne smijemo crtati prije nje (a ni
                // ostaviti prazninu na njezinu mjestu).
                else if (featuredPicks == null || !hasMinData)
                  SliverToBoxAdapter(child: RailSkeleton(isMobile: isMobile)),

                // "Upravo stiglo" rail — tek pristigle epizode bez članka
                // (has_article:false). Kronološki su među najnovijima, ali ih
                // "Najnovije" sakriva jer nemaju AI obradu. Surfamo ih gledljive
                // uz "U obradi" oznaku; tap vodi na basic episode layout
                // (video + YouTube, bez članka).
                if (freshlyArrived.isNotEmpty)
                  SliverToBoxAdapter(
                    child: EpisodesRail(
                      eyebrow: l.homeRailFreshlyArrived,
                      isMobile: isMobile,
                      cards: freshlyArrived
                          .map((fv) => EpisodeRailCard(
                                title: fv.video.displayTitle,
                                subtitle: fv.channelName,
                                thumbnailUrl:
                                    CdnConfig.thumbnailUrl(fv.video.id),
                                dateLabel: fv.video.date,
                                // Faza obrade iz `pipeline` zastavica listinga
                                // ("U redu cekanja" / "Prepisujemo" / …) —
                                // preciznije od jedinstvenog "U obradi".
                                statusBadge:
                                    EpisodeStatus.fromPipeline(fv.video.pipeline)
                                            .badge(l) ??
                                        l.homeStatusProcessing,
                                width: isMobile ? 180 : 220,
                                shareUrl: () => episodeShareUrl(
                                  fv.video.id,
                                  lang: shareLanguageForVideo(fv.video.id),
                                ),
                                prefetchEpisodeId: fv.video.id,
                                onTap: () => onVideoTap(fv.video.id),
                              ))
                          .toList(),
                    ),
                  ),

                // Rail „Danas u korpusu" — epizode koje su danas (ili, dok
                // pipeline noću ne prođe, jučer i do 3 dana unatrag) ušle u
                // katalog, oba tiera. Uz „Upravo stiglo" jer je isto pitanje
                // „što je novo", ali iz kataloga, ne iz listinga. Sam se
                // sakrije bez kataloga (Podcasterium) ili kad je sve prazno.
                // Vidi catalog_day_rail.dart.
                SliverToBoxAdapter(
                  child: CatalogDayRail(
                    isMobile: isMobile,
                    onVideoTap: onVideoTap,
                  ),
                ),

                // Rail "Osobe" — virtualni kanali (osobe). Sam se sakrije kad je
                // PersonChannelFlag ugašen ili indeks nije dostupan, pa home
                // bez flaga izgleda točno kao prije. Vidi persons_rail.dart.
                SliverToBoxAdapter(child: PersonsRail(isMobile: isMobile)),

                // Rail „Tvoje spremljeno" — lajkane epizode, najnovija prvo.
                // Stoji pri dnu (podsjetnik na vlastitu policu, ne urednički
                // izbor) i sam se sakrije kad nema nijednog favorita. „Prikaži
                // sve" vodi na /favorites. Vidi favorites_rail.dart.
                SliverToBoxAdapter(
                  child: FavoritesRail(
                    isMobile: isMobile,
                    onVideoTap: onVideoTap,
                  ),
                ),

                // Puni popis kanala je premjesten s home-a na zaseban surface
                // (lazy lista + filter) radi scroll-perf-a — na home-u sad samo
                // lagani CTA. Vidi all_channels_screen.dart.
                if (channels.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _AllChannelsCta(count: channels.length),
                  ),

                SliverToBoxAdapter(child: HomeFooter(channels: channels)),
              ],
            );
          },
          );
        },
      ),
    );
  }

}

// ---------------------------------------------------------------------------
// "Svi kanali" CTA
// ---------------------------------------------------------------------------

/// Lagani ulaz na zaseban "Svi kanali" surface (`/channels` ruta).
/// Zamjenjuje stari eager channel grid.
class _AllChannelsCta extends StatelessWidget {
  final int count;

  const _AllChannelsCta({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 24, height: 2, color: cs.primary),
              const SizedBox(width: 10),
              Text(
                l.homeChannelsEyebrow.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Material(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => drillDown(context, '/channels'),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.grid_view_rounded,
                          color: cs.primary, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.homeAllChannelsTitle,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l.homeAllChannelsSubtitle(count),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward,
                        color: cs.onSurfaceVariant, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

/// Minimalan sub-bar ispod app bara — prikazuje samo progres ucitavanja
/// kanala. Kad je cache gotov, kolabira na nista (bez praznog paddinga).
///
/// View-mode prebacivanje (Detaljno/Jednostavno) je maknuto odavde — sada
/// zivi samo na episode ekranima (vidi episode_screen.dart / episode_simple_screen.dart),
/// gdje je jasno labelirano. Search i YouTube ID input su u Cmd+K overlay-u.
class _HomeHeader extends StatelessWidget {
  final (int, int)? cacheProgress; // (loaded, total) — null kad je gotovo
  final bool isMobile;

  const _HomeHeader({
    this.cacheProgress,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (cacheProgress == null) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, isMobile ? 4 : 8),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: theme.colorScheme.onSurfaceVariant
                  .withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            AppLocalizations.of(context).homeLoadingChannels(
                cacheProgress!.$1, cacheProgress!.$2),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
