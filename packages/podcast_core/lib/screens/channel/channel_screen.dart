import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/app_localizations.dart';
import '../../brand/app_brand.dart';
import '../../models/episode_status.dart';
import '../../models/channel_detail.dart';
import '../../pinka_sdk/pinka_sdk.dart';
import '../../services/catalog_client.dart';
import '../../services/channel_cache.dart';
import '../../services/follow_service.dart';
import '../../services/page_meta.dart';
import '../../services/view_mode.dart';
import '../../services/scroll_memory.dart';
import '../../widgets/follow_button.dart';
import '../../widgets/magisterium_section.dart';
import '../../widgets/share_context_menu.dart';
import '../../widgets/cached_thumbnail.dart';
import '../../router/nav.dart';
import '../../services/share_language.dart';
import '../../services/share_links.dart';
import '../../services/sponsored_moments_service.dart' show SponsorCampaign;
import '../../src/log.dart' show log;
import 'catalog_channel_body.dart';

/// Channel detail screen — prikazuje listu video zapisa za određeni kanal.
///
/// Ruta: `/c/:slug` (slug = channel ID s `-` umjesto `_`).
///
/// Razdvojeno iz `lib/screens/home_screen.dart` u Korak 2 redizajna kao
/// move-only refactor. Funkcionalno identično `_VideoGridView` widgetu koji
/// je prije bio dio HomeScreen-a.
///
/// Kanal bez statičnog listinga (Tier 2, katalog S10): kad `loadChannel`
/// padne, a brend ima katalog, tijelo crta [CatalogChannelBody] za
/// [catalogSlug]. Tier 1 ide istim putem kao prije (prvo listing).
class ChannelScreen extends StatefulWidget {
  final String channelId;

  /// Slug doslovno iz URL-a (`sbs-croatian`, `yt-UCfT_PJ…`), za katalog.
  /// `channelId` ga ne može vratiti: ruter u njemu crtice pretvara u
  /// podvlake. `null` = bez kataloškog fallbacka (staro ponašanje).
  final String? catalogSlug;

  const ChannelScreen({super.key, required this.channelId, this.catalogSlug});

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen> {
  late final Future<ChannelDetail> _detailFuture;

  /// Jednostavni prikaz — isti pref koji čita naslovnica (`view_mode.dart`).
  bool _simpleMode = false;
  String? _resolvedName;
  // Kanonski UC… ID kanala (kad ga channel.json nosi) → otključava "Preuzmi
  // vlasništvo" akciju. Null dok pipeline ne upiše youtube_channel_id.
  String? _resolvedUcId;

  /// Statični listing nije stigao, a kanal crta katalog. Tada nema ni
  /// praćenja, ni izloga oglasa, ni preuzimanja vlasništva: sve to radi nad
  /// ID-em listinga, kojeg Tier 2 kanal nema.
  bool _catalogMode = false;

  bool get _catalogFallback =>
      widget.catalogSlug != null && CatalogClient.instance.enabled;

  @override
  void initState() {
    super.initState();
    _detailFuture = channelCache.loadChannel(widget.channelId);
    if (_catalogFallback) {
      _detailFuture.then((_) {}, onError: (Object e) {
        log('ChannelScreen(${widget.catalogSlug}): listing pao ($e), katalog');
        if (mounted) setState(() => _catalogMode = true);
      });
    }
    loadSimpleModePref().then((saved) {
      if (mounted && saved != null) setState(() => _simpleMode = saved);
    });
    // Runtime <title>/og meta — isti format kao worker edge-inject za /c/.
    _detailFuture.then((d) {
      if (!mounted) return;
      setPageMeta(
        title: '${d.name} — AI obrada podcasta',
        description: d.description,
      );
    }).catchError((_) {});
  }

  /// ← popa stog kad ga ima; inače ide na semantičkog roditelja (`/channels`),
  /// ne na naslovnicu. Prije 6.9.2026. je bio tvrdi `go('/')` — jedini ekran
  /// koji nije ni provjeravao `canPop()`.
  void _back() => backUp(context);

  /// Prikaz epizode prati korisnikov pref, isto kao naslovnica.
  ///
  /// Do 6.9.2026. je kanal UVIJEK otvarao `/v/` i ignorirao `simpleMode`, pa je
  /// korisnik koji je odabrao jednostavni prikaz dobivao detaljni čim je ušao
  /// preko kanala umjesto preko naslovnice.
  void _openVideo(String videoId) {
    drillDown(context, _simpleMode ? '/m/$videoId' : '/v/$videoId');
  }

  void _onCatalogChannel(CatalogChannelInfo info) {
    setPageMeta(title: '${info.name} — AI obrada podcasta');
    setState(() => _resolvedName = info.name);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: l.commonBack,
                    onPressed: _back,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _resolvedName ?? widget.channelId.replaceAll('_', ' '),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // „Prati" — lokalni popis praćenja (isti namespace kao osobe).
                  // Sam se sakrije dok je PersonChannelFlag ugašen.
                  if (!_catalogMode)
                    FollowButton(
                      followKey: channelFollowKey(widget.channelId),
                      followLabel: l.channelFollow,
                      followingLabel: l.channelFollowing,
                    ),
                  // Izlog sponzorskih trenutaka — samo kanal s kampanjom.
                  if (!_catalogMode &&
                      AppBrand.config.flags.pinka &&
                      SponsorCampaign.forChannel(widget.channelId) != null)
                    IconButton(
                      icon: const Icon(Icons.campaign_outlined),
                      tooltip: l.sponsorStoreEntry,
                      onPressed: () => drillDown(
                        context,
                        '/c/${widget.channelId.replaceAll('_', '-')}/oglasi',
                      ),
                    ),
                  // "Preuzmi vlasništvo" — vidljivo samo kad kanal ima kanonski
                  // UC… ID (Faza 0). Vodi na claim flow (/c/<slug>/claim).
                  if (!_catalogMode &&
                      AppBrand.config.flags.channelOwnership &&
                      _resolvedUcId != null)
                    IconButton(
                      icon: const Icon(Icons.verified_user_outlined),
                      tooltip: l.channelClaimOwnership,
                      onPressed: () => drillDown(
                        context,
                        '/c/${widget.channelId.replaceAll('_', '-')}/claim',
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<ChannelDetail>(
                future: _detailFuture,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError && _catalogFallback) {
                    return CatalogChannelBody(
                      slug: widget.catalogSlug!,
                      onVideoTap: _openVideo,
                      onChannel: _onCatalogChannel,
                    );
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Text(
                        l.commonErrorWithDetails('${snap.error}'),
                      ),
                    );
                  }
                  final detail = snap.data!;
                  if (detail.name != _resolvedName ||
                      detail.youtubeChannelId != _resolvedUcId) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          _resolvedName = detail.name;
                          _resolvedUcId = detail.youtubeChannelId;
                        });
                      }
                    });
                  }
                  final slug = widget.channelId.replaceAll('_', '-');
                  return Column(
                    children: [
                      // "Zid podrške" — sama se sakrije ako kanal nema aktivnu
                      // pinka kampanju (vidi lib/pinka_sdk/). Match po internom
                      // channel id-u ILI kanonskom UC… id-u.
                      if (AppBrand.config.flags.pinka)
                        PinkaSupportCard.channel(
                          channelId: widget.channelId,
                          youtubeChannelId: detail.youtubeChannelId,
                          onOpen: (_) => context.push(
                            Uri(
                              path: '/c/$slug/support',
                              queryParameters: {
                                if (detail.youtubeChannelId != null)
                                  'uc': detail.youtubeChannelId!,
                                'name': detail.name,
                              },
                            ).toString(),
                          ),
                        ),
                      Expanded(
                        child: _ResponsiveVideoList(
                          videos: detail.videos,
                          onVideoTap: _openVideo,
                          isAudioSource: detail.isAudioSource,
                          routeKey: '/c/$slug',
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResponsiveVideoList extends StatefulWidget {
  final List<ChannelVideo> videos;
  final void Function(String videoId) onVideoTap;

  /// Kanal je audio-only izvor → kartice bez thumbnaila pokazuju "Audio Only".
  final bool isAudioSource;

  /// Ruta kanala — ključ za pamćenje pozicije u listi epizoda.
  final String routeKey;

  const _ResponsiveVideoList({
    required this.videos,
    required this.onVideoTap,
    required this.isAudioSource,
    required this.routeKey,
  });

  @override
  State<_ResponsiveVideoList> createState() => _ResponsiveVideoListState();
}

class _ResponsiveVideoListState extends State<_ResponsiveVideoList> {
  static const double _maxCardWidth = 300;

  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final videos = widget.videos;
    final onVideoTap = widget.onVideoTap;
    final isAudioSource = widget.isAudioSource;
    return ScrollRestorer(
      storageKey: widget.routeKey,
      controller: _scrollCtrl,
      child: LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width < 600) {
          return ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            itemCount: videos.length,
            itemBuilder: (context, i) => _VideoCard(
              video: videos[i],
              onTap: () => onVideoTap(videos[i].id),
              isAudioSource: isAudioSource,
            ),
          );
        }
        final availableWidth = width - 32;
        final columns = (availableWidth / _maxCardWidth).floor().clamp(2, 99);
        final cardWidth = (availableWidth - (columns - 1) * 12) / columns;
        return SingleChildScrollView(
          controller: _scrollCtrl,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: videos
                .map(
                  (v) => SizedBox(
                    width: cardWidth,
                    child: _VideoGridCard(
                      video: v,
                      onTap: () => onVideoTap(v.id),
                      isAudioSource: isAudioSource,
                    ),
                  ),
                )
                .toList(),
          ),
        );
      },
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  final ChannelVideo video;
  final VoidCallback onTap;
  final bool isAudioSource;

  const _VideoCard({
    required this.video,
    required this.onTap,
    this.isAudioSource = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final hasArticle = video.pipeline?.hasArticle ?? false;
    // Audio-only kanali: nedostatak thumbnaila = audio epizoda → "Audio Only".
    Widget placeholder() => isAudioSource
        ? audioPlaceholder(theme, l, 120, 68)
        : videoPlaceholder(theme, 120, 68);

    return ShareContextMenu.lazy(
      urlBuilder: () =>
          episodeShareUrl(video.id, lang: shareLanguageForVideo(video.id)),
      child: Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: video.thumbnail != null
                    ? CachedThumbnail(
                        url: video.thumbnail!,
                        width: 120,
                        height: 68,
                        fit: BoxFit.cover,
                        errorFallbackBuilder: (_) => placeholder(),
                      )
                    : placeholder(),
              ),
              const SizedBox(width: 12),
              Expanded(child: videoMeta(theme, l, video, hasArticle)),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _VideoGridCard extends StatelessWidget {
  final ChannelVideo video;
  final VoidCallback onTap;
  final bool isAudioSource;

  const _VideoGridCard({
    required this.video,
    required this.onTap,
    this.isAudioSource = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final hasArticle = video.pipeline?.hasArticle ?? false;
    // Audio-only kanali: nedostatak thumbnaila = audio epizoda → "Audio Only".
    Widget placeholder() =>
        isAudioSource ? audioPlaceholder(theme, l) : videoPlaceholder(theme);

    return ShareContextMenu.lazy(
      urlBuilder: () =>
          episodeShareUrl(video.id, lang: shareLanguageForVideo(video.id)),
      child: Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: video.thumbnail != null
                  ? CachedThumbnail(
                      url: video.thumbnail!,
                      fit: BoxFit.cover,
                      errorFallbackBuilder: (_) => placeholder(),
                    )
                  : placeholder(),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: videoMeta(theme, l, video, hasArticle),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared video card helpers — koriste se i u channel screenu i u home search
// rezultatima. Public da `lib/screens/home/*` može isto reusati.
// ---------------------------------------------------------------------------

Widget videoPlaceholder(ThemeData theme, [double? w, double? h]) => Container(
  width: w,
  height: h,
  color: theme.colorScheme.surfaceContainerHighest,
  child: Center(
    child: Icon(
      Icons.ondemand_video,
      color: theme.colorScheme.onSurfaceVariant,
    ),
  ),
);

/// "Audio Only" placeholder za epizode bez thumbnaila na audio-only kanalima
/// (vidi [ChannelDetail.isAudioSource]). Mali list-card ([h] ~68) prikazuje
/// samo ikonu; veći (grid 16:9) i tekst.
Widget audioPlaceholder(ThemeData theme, AppLocalizations l,
    [double? w, double? h]) {
  final compact = h != null && h < 90;
  return Container(
    width: w,
    height: h,
    color: theme.colorScheme.surfaceContainerHighest,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.podcasts, color: theme.colorScheme.onSurfaceVariant),
          if (!compact) ...[
            const SizedBox(height: 6),
            Text(
              l.channelAudioOnly,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

Widget videoMeta(
  ThemeData theme,
  AppLocalizations l,
  ChannelVideo video,
  bool hasArticle,
) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(
      video.displayTitle,
      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    const SizedBox(height: 4),
    Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        if (video.date != null)
          videoMetaChip(theme, Icons.calendar_today, video.date!),
        if (video.durationDisplay != null)
          videoMetaChip(theme, Icons.schedule, video.durationDisplay!),
      ],
    ),
    const SizedBox(height: 4),
    if (video.speakers.isNotEmpty)
      Text(
        video.speakers.join(', '),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    const SizedBox(height: 6),
    Row(
      children: [
        if (video.magisteriumScore != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: MagisteriumSection.scoreColor(
                video.magisteriumScore,
              ).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: MagisteriumSection.scoreColor(
                  video.magisteriumScore,
                ).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.church,
                  size: 11,
                  color: MagisteriumSection.scoreColor(video.magisteriumScore),
                ),
                const SizedBox(width: 3),
                Text(
                  '${video.magisteriumScore}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: MagisteriumSection.scoreColor(
                      video.magisteriumScore,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
        ],
        // Oznaka nosi FAZU obrade, ne samo "nije gotovo" — epizoda kojoj
        // je prijepis gotov i ona koja jos ceka preuzimanje su korisniku
        // bitno razlicite stvari. Izvor je `pipeline` iz listinga, koji je
        // slabiji vantage od izmjerenog stanja na episode ekranu.
        if (!hasArticle)
          Builder(
            builder: (_) {
              final badge =
                  EpisodeStatus.fromPipeline(video.pipeline).badge(l) ??
                      l.channelInProcessing;
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            },
          ),
      ],
    ),
  ],
);

Widget videoMetaChip(ThemeData theme, IconData icon, String text) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Icon(icon, size: 12, color: theme.colorScheme.onSurfaceVariant),
    const SizedBox(width: 3),
    Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  ],
);
