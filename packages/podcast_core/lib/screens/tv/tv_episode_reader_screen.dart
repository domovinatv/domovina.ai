import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../l10n/app_localizations.dart';
import '../../src/log.dart' show log;
import '../../models/magisterium_data.dart';
import '../../models/podcast_article.dart';
import '../../services/cdn_config.dart';
import '../../services/data_service.dart';
import '../../services/episode_playback_session.dart';
import '../../services/watch_progress_service.dart';
import '../../theme/markdown_brand.dart';
import '../../widgets/cached_thumbnail.dart';
import 'widgets/tv_focus.dart';
import 'widgets/tv_key_hint.dart';
import '../../router/nav.dart';

/// "Čitaj kao blog" mode za TV — paginirani reader s PiP videom.
///
/// Layout: lijevo content (subtitle + markdown + screenshot), desno mini
/// video player + Magisterium AI kartica. Listanje po sekcijama: D-pad
/// LEFT/RIGHT s glavnog content focus-a → seek video na taj timestamp.
///
/// Sync model (bidirectional + soft-lock): video position automatski
/// prebaci vidljivu sekciju kako podcast napreduje; ručni LEFT/RIGHT lock-a
/// auto-update 2.2s da preroll/buffer ne flicka nazad na prethodnu sekciju.
///
/// Magisterium per-section komentar: preview-kartica desno (score + 5 redaka
/// assessment), OK otvara full-screen overlay s cijelim teološkim komentarom
/// uključujući citacije.
class TvEpisodeReaderScreen extends StatefulWidget {
  final String youtubeId;
  final int? startAtSeconds;

  const TvEpisodeReaderScreen({
    super.key,
    required this.youtubeId,
    this.startAtSeconds,
  });

  @override
  State<TvEpisodeReaderScreen> createState() => _TvEpisodeReaderScreenState();
}

class _TvEpisodeReaderScreenState extends State<TvEpisodeReaderScreen> {
  EpisodeData? _data;
  Object? _error;

  // Ista sesija kao TvEpisodeScreen ispod u stogu — čitač ne pokreće svoj
  // player, nego nastavlja onaj koji već svira (vidi EpisodePlaybackSession).
  late final EpisodePlaybackSession _session;

  Player? get _player => _session.player;
  VideoController? get _controller => _session.controller;
  bool get _firstFrame => _session.firstFrame;
  Duration get _position => _session.position;
  Duration get _duration => _session.duration;
  bool get _playing => _session.playing;

  // Flat kronološka lista sekcija (preferira HR varijantu članka).
  List<PodcastSection> _sections = const [];
  // Per-section magisterium lookup: timestamp → SectionMagisterium.
  Map<String, SectionMagisterium> _magBySection = const {};

  int _currentIdx = 0;

  // Nakon ručnog LEFT/RIGHT, ignoriraj video-driven section update 2.2s da
  // preroll/buffer ne vrati pointer na prethodnu sekciju prije nego seek
  // efektivno preskoči. Isti pattern kao na webu (`_seekLock`).
  DateTime? _navLock;
  static const _navLockDuration = Duration(milliseconds: 2200);

  final ScrollController _contentScroll = ScrollController();
  final FocusNode _contentFocus = FocusNode(debugLabel: 'reader-content');
  final FocusNode _magFocus = FocusNode(debugLabel: 'reader-magisterium');

  @override
  void initState() {
    super.initState();
    log('TvReader.init id=${widget.youtubeId} startAt=${widget.startAtSeconds}');
    _contentFocus.addListener(_onAnyFocusChange);
    _magFocus.addListener(_onAnyFocusChange);
    _session = EpisodePlaybackSession.acquire(widget.youtubeId, surface: 'tv')
      ..addListener(_onSession);
    _load();
  }

  void _onAnyFocusChange() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final data = await EpisodeData.load(youtubeId: widget.youtubeId);
      if (!mounted) return;
      final article = data.article;
      if (article == null) {
        setState(() => _error = StateError('not-ai-processed'));
        return;
      }
      final sections = <PodcastSection>[];
      for (final it in article.iterations) {
        sections.addAll(it.sections);
      }
      sections.sort((a, b) => _parseTs(a.screenshotTimestamp)
          .compareTo(_parseTs(b.screenshotTimestamp)));

      final magMap = <String, SectionMagisterium>{};
      final mag = data.magisteriumPrimary;
      if (mag != null) {
        for (final it in mag.iterations) {
          for (final s in it.sections) {
            if (s.magisterium != null) {
              magMap[s.screenshotTimestamp] = s.magisterium!;
            }
          }
        }
      }

      // Nad živom sesijom (došli smo s epizode) sekcija prati stvarnu
      // poziciju; `?t=` je tada samo informacija iste vrijednosti.
      final startSec = _session.isOpen
          ? _session.position.inSeconds
          : widget.startAtSeconds ??
              WatchProgressService.instance
                  .getSync(widget.youtubeId)
                  ?.positionSeconds ??
              0;

      setState(() {
        _data = data;
        _sections = sections;
        _magBySection = magMap;
        _currentIdx = _indexForSecond(startSec);
      });

      await _session.open(data, startAtSeconds: startSec > 5 ? startSec : null);
      if (mounted) _contentFocus.requestFocus();
    } catch (e) {
      log('TvReader.load error: $e');
      if (mounted) setState(() => _error = e);
    }
  }

  Duration _parseTs(String ts) {
    final parts = ts.split(':');
    if (parts.length != 3) return Duration.zero;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final s = int.tryParse(parts[2]) ?? 0;
    return Duration(hours: h, minutes: m, seconds: s);
  }

  int _indexForSecond(int sec) {
    if (_sections.isEmpty) return 0;
    int idx = 0;
    for (int i = 0; i < _sections.length; i++) {
      if (sec >= _parseTs(_sections[i].screenshotTimestamp).inSeconds) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }

  void _onSession() {
    if (!mounted) return;
    setState(() {});
    final pos = _session.position;
    final lock = _navLock;
    if (lock != null && DateTime.now().difference(lock) < _navLockDuration) {
      return;
    }
    final newIdx = _indexForSecond(pos.inSeconds);
    if (newIdx != _currentIdx) {
      setState(() => _currentIdx = newIdx);
      if (_contentScroll.hasClients) _contentScroll.jumpTo(0);
    }
  }

  void _gotoSection(int idx) {
    if (_sections.isEmpty) return;
    final clamped = idx.clamp(0, _sections.length - 1);
    if (clamped == _currentIdx) return;
    final ts = _sections[clamped].screenshotTimestamp;
    final secs = _parseTs(ts).inSeconds;
    _navLock = DateTime.now();
    setState(() => _currentIdx = clamped);
    if (_contentScroll.hasClients) _contentScroll.jumpTo(0);
    _player?.seek(Duration(seconds: secs));
    if (!(_player?.state.playing ?? false)) _player?.play();
  }

  void _togglePlay() {
    final p = _player;
    if (p == null) return;
    if (p.state.playing) {
      p.pause();
    } else {
      p.play();
    }
  }

  void _openMagisteriumOverlay() {
    if (_sections.isEmpty) return;
    final ts = _sections[_currentIdx].screenshotTimestamp;
    final mag = _magBySection[ts];
    if (mag == null) return;
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (ctx) => _MagisteriumOverlay(
        magisterium: mag,
        sectionSubtitle: _sections[_currentIdx].subtitle,
        sectionTimestamp: ts,
      ),
    );
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    _session.release();
    _contentScroll.dispose();
    _contentFocus.removeListener(_onAnyFocusChange);
    _magFocus.removeListener(_onAnyFocusChange);
    _contentFocus.dispose();
    _magFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop || !mounted) return;
          // BACK → klasični player screen na trenutnoj poziciji
          // (watch progress je vec spremljen kroz _save).
          // Reader je pushan NAD epizodom, pa je BACK pop — time se epizoda
          // ispod vraća živa (player, scroll), umjesto da se gradi iznova.
          // Bez stoga (deep-link na /read) padamo na epizodu s trenutnom
          // pozicijom.
          final sec = _position.inSeconds;
          final target = sec > 5
              ? '/v/${widget.youtubeId}/t/$sec'
              : '/v/${widget.youtubeId}';
          back(context, fallback: target);
        },
        child: SafeArea(
          child: Shortcuts(
            // Web/Chrome dev fallback — native Android TV salje DPAD_*
            // direktno, ovo pokriva FORCE_TV=true desktop testing.
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
            child: _error != null
                ? _buildError(theme, l)
                : (_data == null
                    ? _buildLoading(theme, l)
                    : _buildReader(theme, l, _data!)),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading(ThemeData theme, AppLocalizations l) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              color: theme.colorScheme.primary,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 18),
          Text(l.tvReaderPreparing, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            widget.youtubeId,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(ThemeData theme, AppLocalizations l) {
    final notAi = _error is StateError &&
        (_error as StateError).message == 'not-ai-processed';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              notAi ? Icons.menu_book_outlined : Icons.error_outline,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              notAi
                  ? l.tvReaderNotAiProcessed
                  : l.tvLoadError('$_error'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            TvFocusable(
              autofocus: true,
              style: TvFocusStyle.primaryButton,
              onActivate: () =>
                  back(context, fallback: '/v/${widget.youtubeId}'),
              builder: (_, focused) => Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 16),
                color: theme.colorScheme.tertiary,
                child: Text(
                  l.tvReaderOpenClassic,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onTertiary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReader(ThemeData theme, AppLocalizations l, EpisodeData data) {
    if (_sections.isEmpty) return _buildError(theme, l);
    final section = _sections[_currentIdx];
    final ts = section.screenshotTimestamp;
    final mag = _magBySection[ts];

    return Column(
      children: [
        _buildTopBar(theme, l, data),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(40, 12, 40, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 62,
                  child: _buildContent(theme, data, section),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 38,
                  child: _buildSidePanel(theme, l, data, mag),
                ),
              ],
            ),
          ),
        ),
        _buildFooter(theme, l),
      ],
    );
  }

  Widget _buildTopBar(ThemeData theme, AppLocalizations l, EpisodeData data) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 12, 40, 6),
      child: Row(
        children: [
          Container(width: 4, height: 30, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  data.info.channel.toUpperCase(),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.tertiary,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  data.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            color: theme.colorScheme.surfaceContainerHighest,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_stories_rounded,
                    size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  l.tvReaderSectionOf(_currentIdx + 1, _sections.length),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    fontFeatures: const [FontFeature('tnum')],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
      ThemeData theme, EpisodeData data, PodcastSection section) {
    final focused = _contentFocus.hasPrimaryFocus;
    return Focus(
      focusNode: _contentFocus,
      autofocus: true,
      onKeyEvent: _handleContentKey,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          border: Border.all(
            color: focused
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: 3,
          ),
        ),
        child: SingleChildScrollView(
          controller: _contentScroll,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    color: theme.colorScheme.primary,
                    child: Text(
                      section.screenshotTimestamp,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontFeatures: const [FontFeature('tnum')],
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      section.subtitle,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: CachedThumbnail(
                    url: CdnConfig.screenshotUrl(
                        data.youtubeId, section.screenshotTimestamp),
                    errorIcon: Icons.image_outlined,
                    errorIconSize: 40,
                  ),
                ),
              ),
              if (section.screenshotDescription.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  section.screenshotDescription,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              // Markdown s TV-friendly tipografijom: body je titleMedium
              // (~16pt na 1.0 DPR, čitljivo s 3m razdaljine na 540dp panelu).
              MarkdownBody(
                data: section.content,
                styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                  p: theme.textTheme.titleMedium?.copyWith(
                    height: 1.55,
                    color: theme.colorScheme.onSurface,
                  ),
                  h2: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                  h3: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  blockquote: theme.textTheme.titleMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.tertiary,
                    height: 1.5,
                  ),
                  blockquoteDecoration: BoxDecoration(
                    color: theme.colorScheme.tertiaryContainer
                        .withValues(alpha: 0.3),
                    border: Border(
                      left: BorderSide(
                        color: theme.colorScheme.tertiary,
                        width: 4,
                      ),
                    ),
                  ),
                  blockquotePadding:
                      const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  listBullet: theme.textTheme.titleMedium,
                  strong: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (section.keywords.isNotEmpty) ...[
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: section.keywords
                      .map((k) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            color: theme.colorScheme.secondaryContainer,
                            child: Text(
                              k,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: theme
                                    .colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ],
              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }

  KeyEventResult _handleContentKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.mediaRewind ||
        k == LogicalKeyboardKey.mediaTrackPrevious) {
      _gotoSection(_currentIdx - 1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.mediaFastForward ||
        k == LogicalKeyboardKey.mediaTrackNext) {
      _gotoSection(_currentIdx + 1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      if (_contentScroll.hasClients) {
        final pos = _contentScroll.position;
        // Na dnu sadržaja, DOWN prebaci focus na Magisterium karticu
        // (ako sekcija ima Magisterium). Inače stay.
        if (pos.pixels >= pos.maxScrollExtent - 4) {
          final ts = _sections[_currentIdx].screenshotTimestamp;
          if (_magBySection.containsKey(ts)) {
            _magFocus.requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.handled;
        }
        _contentScroll.animateTo(
          (pos.pixels + 260).clamp(0.0, pos.maxScrollExtent),
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      if (_contentScroll.hasClients) {
        final pos = _contentScroll.position;
        if (pos.pixels <= 4) return KeyEventResult.handled;
        _contentScroll.animateTo(
          (pos.pixels - 260).clamp(0.0, pos.maxScrollExtent),
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.mediaPlayPause) {
      _togglePlay();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaPlay) {
      _player?.play();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaPause) {
      _player?.pause();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildSidePanel(ThemeData theme, AppLocalizations l, EpisodeData data,
      SectionMagisterium? mag) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPip(theme, l, data),
        const SizedBox(height: 10),
        _buildTransport(theme),
        const SizedBox(height: 16),
        Expanded(child: _buildMagisteriumCard(theme, l, mag)),
      ],
    );
  }

  Widget _buildPip(ThemeData theme, AppLocalizations l, EpisodeData data) {
    final controller = _controller;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.black),
            if (!_firstFrame)
              CachedThumbnail(
                url: CdnConfig.thumbnailUrl(data.youtubeId),
              ),
            if (controller != null)
              Video(
                controller: controller,
                controls: NoVideoControls,
                fit: BoxFit.contain,
              ),
            if (!_firstFrame)
              Container(
                color: Colors.black.withValues(alpha: 0.55),
                alignment: Alignment.center,
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    color: theme.colorScheme.tertiary,
                    strokeWidth: 3,
                  ),
                ),
              ),
            // "LIVE / READING" chip — diskretno gore-desno kao tally light
            // na TV-u: korisnik zna da je video aktivan dok čita.
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                color: _playing
                    ? theme.colorScheme.tertiary
                    : Colors.black.withValues(alpha: 0.65),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _playing
                          ? Icons.fiber_manual_record_rounded
                          : Icons.pause_rounded,
                      size: 11,
                      color: _playing
                          ? theme.colorScheme.onTertiary
                          : Colors.white,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _playing
                          ? l.tvLive.toUpperCase()
                          : l.tvPaused.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _playing
                            ? theme.colorScheme.onTertiary
                            : Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransport(ThemeData theme) {
    final total = _duration.inSeconds > 0
        ? _duration.inSeconds
        : (_data?.info.duration ?? 0);
    final progress =
        total > 0 ? (_position.inSeconds / total).clamp(0.0, 1.0) : 0.0;
    return Row(
      children: [
        Icon(
          _playing ? Icons.play_arrow_rounded : Icons.pause_rounded,
          color: theme.colorScheme.onSurface,
          size: 22,
        ),
        const SizedBox(width: 8),
        Text(
          _fmt(_position),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface,
            fontFeatures: const [FontFeature('tnum')],
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              color: theme.colorScheme.tertiary,
              backgroundColor:
                  theme.colorScheme.onSurface.withValues(alpha: 0.18),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          _fmt(Duration(seconds: total)),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontFeatures: const [FontFeature('tnum')],
          ),
        ),
      ],
    );
  }

  Widget _buildMagisteriumCard(
      ThemeData theme, AppLocalizations l, SectionMagisterium? mag) {
    if (mag == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined,
                size: 28,
                color: theme.colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.5)),
            const SizedBox(height: 8),
            Text(
              l.tvReaderNoCommentary,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }
    final focused = _magFocus.hasPrimaryFocus;
    return Focus(
      focusNode: _magFocus,
      onKeyEvent: _handleMagKey,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.95),
          border: Border(
            left: BorderSide(
              color: focused
                  ? theme.colorScheme.onTertiaryContainer
                  : theme.colorScheme.tertiary,
              width: focused ? 8 : 4,
            ),
            top: BorderSide(
              color: focused
                  ? theme.colorScheme.tertiary
                  : Colors.transparent,
              width: focused ? 2 : 0,
            ),
            right: BorderSide(
              color: focused
                  ? theme.colorScheme.tertiary
                  : Colors.transparent,
              width: focused ? 2 : 0,
            ),
            bottom: BorderSide(
              color: focused
                  ? theme.colorScheme.tertiary
                  : Colors.transparent,
              width: focused ? 2 : 0,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.menu_book_rounded,
                    color: theme.colorScheme.onTertiaryContainer, size: 20),
                const SizedBox(width: 8),
                Text(
                  'MAGISTERIUM AI',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
                const Spacer(),
                if (mag.score != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    color: theme.colorScheme.tertiary,
                    child: Text(
                      '${mag.score}/10',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onTertiary,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature('tnum')],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              l.tvReaderChurchTeaching,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                mag.assessment,
                maxLines: 6,
                overflow: TextOverflow.fade,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onTertiaryContainer,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.arrow_forward_rounded,
                  color: focused
                      ? theme.colorScheme.onTertiaryContainer
                      : theme.colorScheme.tertiary,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  l.tvReaderOpenFullCommentary,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: focused
                        ? theme.colorScheme.onTertiaryContainer
                        : theme.colorScheme.tertiary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  KeyEventResult _handleMagKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.space) {
      _openMagisteriumOverlay();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      _contentFocus.requestFocus();
      return KeyEventResult.handled;
    }
    // LEFT/RIGHT na Magisterium kartici i dalje listaju sekcije —
    // korisnik ne mora vracati focus na content da promijeni sekciju.
    if (k == LogicalKeyboardKey.arrowLeft) {
      _gotoSection(_currentIdx - 1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      _gotoSection(_currentIdx + 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildFooter(ThemeData theme, AppLocalizations l) {
    final prevSub =
        _currentIdx > 0 ? _sections[_currentIdx - 1].subtitle : null;
    final nextSub = _currentIdx < _sections.length - 1
        ? _sections[_currentIdx + 1].subtitle
        : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(40, 10, 40, 12),
      color: theme.colorScheme.surfaceContainerLow,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: _NavLabel(
              theme: theme,
              icon: Icons.chevron_left,
              text: prevSub,
              align: TextAlign.left,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: TvKeyHint(
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.4,
              ),
              entries: [
                TvHintEntry(const ['OK'], l.tvHintPlayPause),
                TvHintEntry(
                  const [Icons.chevron_left, Icons.chevron_right],
                  l.tvHintSections,
                ),
                TvHintEntry(const [Icons.expand_more], 'Magisterium'),
                TvHintEntry(const ['BACK'], l.tvHintVideo),
              ],
            ),
          ),
          Expanded(
            child: _NavLabel(
              theme: theme,
              icon: Icons.chevron_right,
              text: nextSub,
              align: TextAlign.right,
              suffix: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// Susjedni odlomak u footeru čitača — strelica + njegov podnaslov.
///
/// Strelica je [Icon], ne znak `◀`/`▶` u stringu: vidi `TvKeyHint` za razlog.
class _NavLabel extends StatelessWidget {
  final ThemeData theme;
  final IconData icon;
  final String? text;
  final TextAlign align;
  final bool suffix;

  const _NavLabel({
    required this.theme,
    required this.icon,
    required this.text,
    required this.align,
    this.suffix = false,
  });

  @override
  Widget build(BuildContext context) {
    final label = text;
    final color = label == null
        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.35)
        : theme.colorScheme.onSurface;
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: color,
      fontWeight: FontWeight.w700,
    );
    // Nema susjeda: crtica stoji sama, bez strelice koja nikamo ne vodi.
    if (label == null) {
      return Text('—', textAlign: align, style: style);
    }
    final arrow = Icon(icon, size: 20, color: color);
    final title = Flexible(
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        style: style,
      ),
    );
    return Row(
      mainAxisAlignment:
          suffix ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: suffix
          ? [title, const SizedBox(width: 6), arrow]
          : [arrow, const SizedBox(width: 6), title],
    );
  }
}

// ---------------------------------------------------------------------------
// Magisterium full-screen overlay
// ---------------------------------------------------------------------------

class _MagisteriumOverlay extends StatelessWidget {
  final SectionMagisterium magisterium;
  final String sectionSubtitle;
  final String sectionTimestamp;

  const _MagisteriumOverlay({
    required this.magisterium,
    required this.sectionSubtitle,
    required this.sectionTimestamp,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 80, vertical: 36),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.arrowUp):
              DirectionalFocusIntent(TraversalDirection.up),
          SingleActivator(LogicalKeyboardKey.arrowDown):
              DirectionalFocusIntent(TraversalDirection.down),
        },
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.menu_book_rounded,
                      color: theme.colorScheme.tertiary, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    'MAGISTERIUM AI',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.tertiary,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  if (magisterium.score != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      color: theme.colorScheme.tertiary,
                      child: Text(
                        '${magisterium.score}/10',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onTertiary,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature('tnum')],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '$sectionTimestamp · $sectionSubtitle',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Heading(theme, l.tvReaderHeadingAssessment,
                          theme.colorScheme.tertiary),
                      MarkdownBody(
                        data: magisterium.assessment,
                        styleSheet: MarkdownStyleSheet.fromTheme(theme)
                            .copyWith(
                              p: theme.textTheme.bodyLarge?.copyWith(
                                height: 1.6,
                                color: theme.colorScheme.onSurface,
                              ),
                            )
                            .withBrandBlockquote(theme),
                      ),
                      if (magisterium.concerns.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        _Heading(theme, l.tvReaderHeadingConcerns,
                            theme.colorScheme.error),
                        ...magisterium.concerns.map((c) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.warning_amber_rounded,
                                      size: 20,
                                      color: theme.colorScheme.error),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(c,
                                        style: theme.textTheme.bodyLarge
                                            ?.copyWith(height: 1.5)),
                                  ),
                                ],
                              ),
                            )),
                      ],
                      if (magisterium.enrichment.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        _Heading(theme, l.tvReaderHeadingEnrichment,
                            theme.colorScheme.tertiary),
                        MarkdownBody(
                          data: magisterium.enrichment,
                          styleSheet: MarkdownStyleSheet.fromTheme(theme)
                              .copyWith(
                                p: theme.textTheme.bodyLarge?.copyWith(
                                  height: 1.6,
                                  color: theme.colorScheme.onSurface,
                                ),
                              )
                              .withBrandBlockquote(theme),
                        ),
                      ],
                      if (magisterium.citations.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        _Heading(theme, l.tvReaderHeadingCitations,
                            theme.colorScheme.primary),
                        ...magisterium.citations.map((c) => Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: theme.colorScheme
                                    .surfaceContainerHigh
                                    .withValues(alpha: 0.6),
                                border: Border(
                                  left: BorderSide(
                                    color: theme.colorScheme.primary,
                                    width: 3,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '"${c.citedText}"',
                                    style: theme.textTheme.bodyLarge
                                        ?.copyWith(
                                      fontStyle: FontStyle.italic,
                                      height: 1.5,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _formatCitation(c),
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                      color: theme.colorScheme
                                          .onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            )),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Text(
                    l.tvReaderCloseHint,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  TvFocusable(
                    autofocus: true,
                    style: TvFocusStyle.primaryButton,
                    onActivate: () => Navigator.of(context).pop(),
                    builder: (_, focused) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 26, vertical: 12),
                      color: theme.colorScheme.tertiary,
                      child: Text(
                        l.commonClose,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onTertiary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatCitation(MagisteriumCitation c) {
    final parts = <String>[c.documentTitle];
    if (c.documentAuthor.isNotEmpty) parts.add(c.documentAuthor);
    if (c.documentYear.isNotEmpty) parts.add(c.documentYear);
    return '— ${parts.join(", ")}';
  }
}

class _Heading extends StatelessWidget {
  final ThemeData theme;
  final String text;
  final Color color;
  const _Heading(this.theme, this.text, this.color);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(width: 3, height: 18, color: color),
          const SizedBox(width: 8),
          Text(
            text.toUpperCase(),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

String _fmt(Duration d) {
  if (d <= Duration.zero) return '00:00';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (h > 0) return '$h:$m:$s';
  return '$m:$s';
}
