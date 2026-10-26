import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../l10n/app_localizations.dart';
import '../models/episode_reels.dart';
import '../router/nav.dart' show closeOnRouteChange;
import '../services/episode_language.dart';
import '../services/share_links.dart';
import '../src/log.dart' show log;
import 'cached_thumbnail.dart';
import 'reel_share_sheet.dart' show showReelShareSheet;
import 'sponsors_in_video_section.dart' show formatSponsorClock;

/// Istaknuti trenuci (`reels.json`) u playeru: trake na seek baru, popis u
/// panelu playera i vertikalni (9:16) player za renderirane isječke.
///
/// Vlasnik glavnog playera je ekran: popis samo javlja [onJump] / [onWatch],
/// a ekran odlučuje kako se skače i što se događa s epizodom dok isječak
/// svira (vidi `_watchReel` u ekranima epizode).

/// Crta raspone trenutaka IZNAD tracka seek bara (poruke sponzora su ispod).
/// Renderirani isječak je puna traka, kandidat bez videa tanja i prigušena.
///
/// [inset] je vodoravni razmak tracka od ruba (kod Slidera = radijus
/// overlaya), da raspon sjedne točno na vrijeme koje predstavlja.
void paintReelBands(
  Canvas canvas,
  Size size, {
  required List<EpisodeReel> reels,
  required int totalMs,
  required Color rendered,
  required Color candidate,
  double inset = 0,
}) {
  if (totalMs <= 0 || reels.isEmpty) return;
  final w = size.width - 2 * inset;
  if (w <= 0) return;
  // Iznad tracka i preko vrha crta poglavlja (počinju na 10 % visine), da
  // se kratak trenutak (66 s u satu = ~6 px) ne izgubi među njima.
  final bottom = size.height * 0.32;
  for (final pass in const [false, true]) {
    // Renderirani zadnji, da preko preklopljenog kandidata ostane vidljiv.
    for (final r in reels) {
      if (r.isRendered != pass) continue;
      final x0 = inset + r.startPosition.inMilliseconds / totalMs * w;
      var x1 = inset + r.endPosition.inMilliseconds / totalMs * w;
      if (x1 - x0 < 6) x1 = x0 + 6;
      final h = pass ? 4.0 : 3.0;
      canvas.drawRRect(
        RRect.fromLTRBR(
          x0,
          bottom - h,
          x1.clamp(0, size.width),
          bottom,
          const Radius.circular(1.5),
        ),
        Paint()..color = pass ? rendered : candidate,
      );
    }
  }
}

/// Boje traka — iste u panelu playera i u `_PlayerTab`. `onSurface`, ne
/// `primary`: primary je boja tracka i crta poglavlja, pa bi se trenutak u
/// njima utopio; crvena (tertiary) i zlatna su zauzete za sponzore.
({Color rendered, Color candidate}) reelBandColors(ThemeData theme) => (
  rendered: theme.colorScheme.onSurface,
  candidate: theme.colorScheme.onSurface.withAlpha(110),
);

/// Samostalan sloj traka za seek bar koji nema svoj painter (`_PlayerTab`).
class ReelTimelineMarks extends StatelessWidget {
  final List<EpisodeReel> reels;
  final int totalMs;
  final double inset;
  final double height;

  const ReelTimelineMarks({
    super.key,
    required this.reels,
    required this.totalMs,
    this.inset = 0,
    this.height = 24,
  });

  @override
  Widget build(BuildContext context) {
    final colors = reelBandColors(Theme.of(context));
    return IgnorePointer(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _ReelBandsPainter(
            reels: reels,
            totalMs: totalMs,
            inset: inset,
            rendered: colors.rendered,
            candidate: colors.candidate,
          ),
        ),
      ),
    );
  }
}

class _ReelBandsPainter extends CustomPainter {
  final List<EpisodeReel> reels;
  final int totalMs;
  final double inset;
  final Color rendered;
  final Color candidate;

  const _ReelBandsPainter({
    required this.reels,
    required this.totalMs,
    required this.inset,
    required this.rendered,
    required this.candidate,
  });

  @override
  void paint(Canvas canvas, Size size) => paintReelBands(
    canvas,
    size,
    reels: reels,
    totalMs: totalMs,
    rendered: rendered,
    candidate: candidate,
    inset: inset,
  );

  @override
  bool shouldRepaint(_ReelBandsPainter old) =>
      old.reels != reels ||
      old.totalMs != totalMs ||
      old.inset != inset ||
      old.rendered != rendered ||
      old.candidate != candidate;
}

/// Popis trenutaka u panelu playera, poredan po vremenu. Tap na redak skoči
/// u epizodu; renderirani trenutak ima i „Pogledaj" (vertikalni isječak).
/// Redak koji upravo svira je istaknut.
class EpisodeReelsPlayerStrip extends StatelessWidget {
  final EpisodeReels? reels;
  final Duration position;
  final void Function(EpisodeReel reel)? onJump;
  final void Function(EpisodeReel reel)? onWatch;

  const EpisodeReelsPlayerStrip({
    super.key,
    required this.reels,
    required this.position,
    this.onJump,
    this.onWatch,
  });

  @override
  Widget build(BuildContext context) {
    final list = reels?.reels ?? const <EpisodeReel>[];
    if (list.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final active = reels!.activeAt(position);

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(Icons.auto_awesome_outlined, size: 14, color: muted),
                const SizedBox(width: 6),
                Text(
                  l.reelsTitle,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: muted,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          for (final r in list)
            _ReelRow(
              reel: r,
              active: identical(r, active),
              onJump: onJump == null ? null : () => onJump!(r),
              onWatch: onWatch == null || !r.isRendered
                  ? null
                  : () => onWatch!(r),
            ),
        ],
      ),
    );
  }
}

class _ReelRow extends StatelessWidget {
  final EpisodeReel reel;
  final bool active;
  final VoidCallback? onJump;
  final VoidCallback? onWatch;

  const _ReelRow({
    required this.reel,
    required this.active,
    this.onJump,
    this.onWatch,
  });

  static const double _posterW = 36;
  static const double _posterH = 64;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final time = formatSponsorClock(reel.startSeconds);
    final meta = [
      formatSponsorClock(reel.durationSeconds),
      ?reel.speaker,
    ].join(' · ');

    final Widget leading;
    if (reel.isRendered) {
      final poster = reel.render!.posterUrl;
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: _posterW,
          height: _posterH,
          child: poster == null
              ? ColoredBox(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.smart_display_outlined,
                    size: 18,
                    color: muted,
                  ),
                )
              : CachedThumbnail(
                  url: poster,
                  width: _posterW,
                  height: _posterH,
                  useVariants: false,
                  errorIcon: Icons.smart_display_outlined,
                  errorIconSize: 18,
                ),
        ),
      );
    } else {
      leading = SizedBox(
        width: _posterW,
        child: Icon(
          Icons.play_circle_outline,
          size: 20,
          color: theme.colorScheme.primary,
        ),
      );
    }

    return Material(
      color: active
          ? theme.colorScheme.primaryContainer.withAlpha(90)
          : Colors.transparent,
      child: Tooltip(
        message: l.reelsJumpTo(time),
        child: InkWell(
          onTap: onJump,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        reel.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(
                          children: [
                            if (reel.isPremium)
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: _DirectedBadge(l: l),
                                ),
                              ),
                            TextSpan(
                              text: time,
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                            TextSpan(
                              text: ' · $meta',
                              style: TextStyle(color: muted),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                if (onWatch != null) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: l.reelsWatch,
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      icon: const Icon(Icons.play_arrow, size: 16),
                      label: Text(l.reelsWatchShort),
                      onPressed: onWatch,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Oznaka režiranog isječka (`render.premium`). Namjerno NE „Premium":
/// u aplikaciji s Plus pretplatom ta riječ obećava zaključan sadržaj.
class _DirectedBadge extends StatelessWidget {
  final AppLocalizations l;

  const _DirectedBadge({required this.l});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // WidgetSpan ne nasljeđuje stil retka, pa veličina ide eksplicitno.
    final size = theme.textTheme.labelSmall?.fontSize ?? 11;
    return Tooltip(
      message: l.reelsDirectedHint,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_awesome,
                size: size,
                color: scheme.onSecondaryContainer,
              ),
              const SizedBox(width: 3),
              Text(
                l.reelsDirected,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Otvara vertikalni isječak preko ekrana. Vraća `true` kad je korisnik
/// izabrao „Pogledaj u cijeloj epizodi" — tada ekran skoči na početak
/// trenutka; inače ekran vraća epizodu u stanje prije otvaranja.
///
/// Otvara se fadeom, ne scaleom: tekst pod scale transformom se na Mali GPU-u
/// krivo crta (CLAUDE.md, pretraga naslovnice).
Future<bool> showReelViewer(
  BuildContext context, {
  required EpisodeReel reel,
  required String youtubeId,
  EpisodeLanguage language = EpisodeLanguage.hr,
}) async {
  assert(reel.isRendered);
  final l = AppLocalizations.of(context);
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: l.commonClose,
    barrierColor: Colors.black87,
    transitionDuration: const Duration(milliseconds: 180),
    transitionBuilder: (_, anim, _, child) =>
        FadeTransition(opacity: anim, child: child),
    pageBuilder: (_, _, _) =>
        _ReelViewer(reel: reel, youtubeId: youtubeId, language: language),
  );
  return result ?? false;
}

class _ReelViewer extends StatefulWidget {
  final EpisodeReel reel;
  final String youtubeId;
  final EpisodeLanguage language;

  const _ReelViewer({
    required this.reel,
    required this.youtubeId,
    required this.language,
  });

  @override
  State<_ReelViewer> createState() => _ReelViewerState();
}

class _ReelViewerState extends State<_ReelViewer> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  StreamSubscription<String>? _errors;
  VoidCallback? _stopRouteListener;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final url = widget.reel.render!.url;
    log('Reels: open #${widget.reel.rank} $url');
    // Greška prije prvog kadra = isječak se ne da pustiti. Kasnije poruke
    // (npr. prolazni mrežni prekid) ne ruše prikaz — player ih sam pokuša.
    _errors = _player.stream.error.listen((e) {
      log('Reels: player error: $e');
      if (!mounted || _player.state.position > Duration.zero) return;
      setState(() => _failed = true);
    });
    _player.open(Media(url));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Na webu browserov Back mijenja stranicu ISPOD modala — zatvori ga.
    _stopRouteListener ??= closeOnRouteChange(context, () {
      if (mounted) Navigator.of(context).maybePop(false);
    });
  }

  @override
  void dispose() {
    _stopRouteListener?.call();
    _errors?.cancel();
    _player.dispose();
    super.dispose();
  }

  void _copyLink(BuildContext context) {
    final l = AppLocalizations.of(context);
    final sec = widget.reel.startSeconds;
    final url = episodeShareUrl(
      widget.youtubeId,
      seconds: sec,
      lang: widget.language,
    );
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.episodeLinkCopied(formatSponsorClock(sec))),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 9:16 isječak kao datoteka + 16:9 isti raspon s cuttera.
  ///
  /// Reel se pauzira dok je list otvoren: `<video>` inače vuče isti 35 MB
  /// fajl usporedno s preuzimanjem za dijeljenje.
  Future<void> _share(BuildContext context) async {
    final wasPlaying = _player.state.playing;
    if (wasPlaying) _player.pause();
    await showReelShareSheet(
      context,
      reel: widget.reel,
      youtubeId: widget.youtubeId,
      episodeUrl: episodeShareUrl(
        widget.youtubeId,
        seconds: widget.reel.startSeconds,
        lang: widget.language,
      ),
      messenger: ScaffoldMessenger.of(context),
    );
    if (wasPlaying && mounted) _player.play();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // Vlastiti messenger: snackbar korijenskog Scaffolda bi ostao ispod modala.
    return ScaffoldMessenger(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Builder(
            builder: (context) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.reel.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        color: Colors.white,
                        tooltip: l.commonClose,
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 9 / 16,
                      child: _failed
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  l.reelsPlaybackError,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            )
                          : Video(controller: _controller),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.ios_share),
                        label: Text(l.commonShare),
                        onPressed: () => _share(context),
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.smart_display_outlined),
                        label: Text(l.reelsWatchInEpisode),
                        onPressed: () => Navigator.of(context).pop(true),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                        ),
                        icon: const Icon(Icons.link),
                        label: Text(l.commonCopyLink),
                        onPressed: () => _copyLink(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
