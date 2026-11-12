import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../src/log.dart' show log;
import '../../models/channel_detail.dart';
import '../../services/channel_cache.dart';
import '../../services/channel_visibility.dart';
import '../../widgets/channel_gone_view.dart';
import '../../widgets/cached_thumbnail.dart';
import 'widgets/tv_episode_card.dart';
import 'widgets/tv_focus.dart';
import '../../router/nav.dart';

/// TV channel detail screen. Pokazuje sve epizode kanala kao responzivan grid
/// fokusiranih kartica.
///
/// Layout:
///   AppBar (NATRAG + channel avatar/name + meta)
///   Grid: TvEpisodeCard (2-6 stupaca ovisno o sirini ekrana)
///
/// D-pad ponasanje:
/// - Autofocus na prvu karticu u gridu (NATRAG ostaje dostupan UP-om).
/// - LEFT/RIGHT prolazi kroz redove.
/// - UP iz prvog reda fokusira NATRAG.
/// - OK/Enter na karticu → `/v/<id>`; OK na NATRAG → `/`
///
/// `Shortcuts` wrapper za arrow-key → DirectionalFocusIntent je obavezan jer
/// Flutter Web ne mapira arrow keys na directional focus po defaultu (vidi
/// komentar u tv_home_screen.dart). Bez ovoga D-pad u Chrome/Mac dev okruzenju
/// (i potencijalno na non-Leanback Android TV launcherima) ne radi.
class TvChannelScreen extends StatefulWidget {
  final String channelId;

  const TvChannelScreen({super.key, required this.channelId});

  @override
  State<TvChannelScreen> createState() => _TvChannelScreenState();
}

class _TvChannelScreenState extends State<TvChannelScreen> {
  late final Future<ChannelDetail> _detailFuture;
  final _backFocus = FocusNode(debugLabel: 'tv-channel-back');

  @override
  void initState() {
    super.initState();
    log('TvChannelScreen.init channelId=${widget.channelId}');
    // Postavke kanala čekaju se najviše 1,5 s (fail-open), da povučen kanal
    // ne bljesne epizodama prije nego se zamijeni prikazom povučenog.
    _detailFuture = channelCache.loadChannel(widget.channelId).then((d) async {
      await ChannelVisibility.instance.ready();
      return d;
    });
  }

  @override
  void dispose() {
    _backFocus.dispose();
    super.dispose();
  }

  /// D-pad BACK popa stog kad ga ima. Prije 6.9.2026. je uvijek skakao na
  /// home, pa je korisnik gubio poziciju u gridu — na 10-foot UI-ju to znači
  /// desetke pritisaka D-pada da se vrati gdje je bio.
  void _back() {
    log('TvChannel: back');
    backUp(context);
  }

  void _openEpisode(String videoId) {
    log('TvChannel: open /v/$videoId');
    drillDown(context, '/v/$videoId');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
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
            SingleActivator(LogicalKeyboardKey.escape): _BackIntent(),
            SingleActivator(LogicalKeyboardKey.goBack): _BackIntent(),
            SingleActivator(LogicalKeyboardKey.browserBack): _BackIntent(),
          },
          child: Actions(
            actions: {
              _BackIntent: CallbackAction<_BackIntent>(
                onInvoke: (_) {
                  _back();
                  return null;
                },
              ),
            },
            child: FutureBuilder<ChannelDetail>(
              future: _detailFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return _buildLoading(theme, l);
                }
                if (snap.hasError) {
                  return _buildError(theme, l, snap.error);
                }
                final detail = snap.data!;
                final vis = ChannelVisibility.instance;
                final uc = detail.youtubeChannelId;
                if (vis.isGone(uc)) {
                  return ChannelGoneView(
                    ucId: uc,
                    isDeleted: vis.isDeleted(uc),
                    deletedAt: vis.deletedAt(uc),
                    autofocus: true,
                  );
                }
                return _buildContent(theme, l, detail);
              },
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // States
  // ---------------------------------------------------------------------------

  Widget _buildLoading(ThemeData theme, AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAppBar(theme, l, name: null, episodeCount: null, avatar: null),
        const Expanded(
          child: Center(child: CircularProgressIndicator()),
        ),
      ],
    );
  }

  Widget _buildError(ThemeData theme, AppLocalizations l, Object? err) {
    log('TvChannelScreen: load ERROR — $err');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAppBar(theme, l, name: null, episodeCount: null, avatar: null),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(48),
              child: Text(
                l.tvChannelLoadError('$err'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(
      ThemeData theme, AppLocalizations l, ChannelDetail detail) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAppBar(
          theme,
          l,
          name: detail.name,
          episodeCount: detail.videos.length,
          avatar: detail.avatarSquare,
        ),
        Expanded(
          child: detail.videos.isEmpty
              ? Center(
                  child: Text(
                    l.tvChannelNoEpisodes,
                    style: theme.textTheme.bodyLarge,
                  ),
                )
              : _buildGrid(theme, detail.videos),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // App bar (NATRAG + channel info)
  // ---------------------------------------------------------------------------

  Widget _buildAppBar(
    ThemeData theme,
    AppLocalizations l, {
    required String? name,
    required int? episodeCount,
    required String? avatar,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 20, 48, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          TvFocusable(
            style: TvFocusStyle.subtleButton,
            focusNode: _backFocus,
            borderRadius: BorderRadius.circular(12),
            onActivate: _back,
            builder: (context, focused) => AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: focused
                    ? theme.colorScheme.tertiaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_back,
                    size: 22,
                    color: theme.colorScheme.onSurface,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l.commonBack.toUpperCase(),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 24),
          if (avatar != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedThumbnail(
                url: avatar,
                width: 48,
                height: 48,
                errorIcon: Icons.podcasts_outlined,
                errorIconSize: 24,
              ),
            ),
          if (avatar != null) const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name ?? widget.channelId.replaceAll('_', ' '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (episodeCount != null)
                  Text(
                    l.tvEpisodeCountPlural(episodeCount),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Grid
  // ---------------------------------------------------------------------------

  Widget _buildGrid(ThemeData theme, List<ChannelVideo> videos) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 48.0;
        const columnSpacing = 24.0;
        const rowSpacing = 32.0;

        // Target card width ~220; clamp columns 2-6 da kartice ne postanu ni
        // premale ni prevelike na ekstremima (EON 960dp → 3-4, 1920dp → 6).
        final available = constraints.maxWidth - horizontalPadding * 2;
        final targetCardWidth = 220.0;
        final columns = ((available + columnSpacing) /
                (targetCardWidth + columnSpacing))
            .floor()
            .clamp(2, 6);
        final cardWidth =
            (available - (columns - 1) * columnSpacing) / columns;

        // Visina kartice: thumbnail (9/16) + tekst region (~80dp za 3 linije
        // titla bez ellipsis-a + paddings).
        final cardHeight = cardWidth * 9 / 16 + 82;

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(
            horizontalPadding,
            12,
            horizontalPadding,
            48,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: columnSpacing,
            mainAxisSpacing: rowSpacing,
            mainAxisExtent: cardHeight,
          ),
          itemCount: videos.length,
          itemBuilder: (context, i) {
            final v = videos[i];
            return TvEpisodeCard(
              episodeId: v.id,
              title: v.displayTitle,
              magisteriumScore: v.magisteriumScore,
              width: cardWidth,
              // Autofocus prva kartica — D-pad UP iz nje fokusira NATRAG.
              autofocus: i == 0,
              onTap: () => _openEpisode(v.id),
            );
          },
        );
      },
    );
  }
}

/// Intent za hardware BACK / ESC keyeve — Android TV remote BACK obicno salje
/// `goBack` ili `browserBack` kod, a Mac/Chrome dev koristi ESC.
class _BackIntent extends Intent {
  const _BackIntent();
}
