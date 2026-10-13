import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/speaker_timeline.dart';
import '../models/sponsored_moment.dart';
import '../models/sponsors_in_video.dart';
import '../services/sponsored_moments_controller.dart';
import '../models/podcast_summary.dart';
import '../services/seek_undo.dart';
import '../theme/app_theme.dart';
import 'audio_poster.dart';
import 'episode_video.dart';
import 'subtitle_caption.dart';
import 'playback_controls.dart';
import 'sponsored_moment_widgets.dart';
import 'sponsors_in_video_section.dart';
import 'youtube_embed.dart';

/// Marker za jedno poglavlje u video playeru (timestamp + label)
class VideoChapterMark {
  final Duration position;
  final String timestamp; // "HH:MM:SS" — kao u article.json
  final String label;

  const VideoChapterMark({
    required this.position,
    required this.timestamp,
    required this.label,
  });
}

/// Fiksni video panel — prikazuje player s kontrolama i chapter markerima.
/// Player i VideoController su vanjski (owned by _EpisodeContentState).
/// Ispod ove visine panel scrolla u cjelini (vidi `build`). Fiksni dio
/// (slika + kontrole + sponzori) je ~390 px; iznad praga poglavljima ostaje
/// bar ~130 px vlastitog scrolla.
const double _kCompactPanelHeight = 520;

class VideoPanel extends StatefulWidget {
  final Player player;
  final VideoController controller;
  final List<VideoChapterMark> chapters;
  final String? activeTimestamp;
  final String? scrollTimestamp;
  final void Function(String timestamp) onChapterTap;
  final int totalDurationSeconds;
  final SpeakerTimeline? speakerTimeline;
  final List<SummarySpeaker> speakers;
  final double? width;
  final void Function(Duration position)? onSeek;

  /// Pouzdani rasponi poruka sponzora u snimci (`SponsorsInVideo`) — crtaju
  /// se diskretno na seek baru da korisnik vidi gdje su.
  final List<({Duration start, Duration end})> sponsorRanges;

  /// Sponzori u snimci za traku iznad poglavlja + „Poslušaj" (vlasnik
  /// playera i praćenja kraja poruke je ekran).
  final SponsorsInVideo? sponsorsInVideo;
  final void Function(SponsorInVideoSegment segment)? onSponsorListen;

  /// PLAĆENI sponzorski trenuci (`SponsoredMoment`) — zaseban sloj od
  /// [sponsorsInVideo]: traka „Sponzorirano · {brand}" i zlatni pojas na
  /// seek baru. Vlasnik kontrolera (i pozicije) je ekran.
  final SponsoredMomentsController? sponsoredMoments;
  final void Function(SponsoredMoment moment)? onSponsoredListen;

  /// YouTube ID epizode — omogućuje in-app YouTube embed mode (web).
  final String? youtubeId;

  /// True kad je epizoda audio-only — umjesto video površine prikazuje
  /// [AudioPoster] (cover-art), bez YouTube embed gumba.
  final bool audioOnly;

  /// Cover-art URL za audio-only mod (CORS-safe channel avatar).
  final String? posterUrl;

  /// Ponuda „vrati me gdje sam bio" nakon ručnog skoka. Vlasnik je ekran;
  /// panel je samo prikazuje iznad seek bara. Ovo je jedina putanja do pilule
  /// za **audio-only** epizode, gdje [EpisodeVideo] ne postoji.
  final SeekUndo? seekUndo;

  const VideoPanel({
    super.key,
    required this.player,
    required this.controller,
    required this.chapters,
    this.activeTimestamp,
    this.scrollTimestamp,
    required this.onChapterTap,
    required this.totalDurationSeconds,
    this.speakerTimeline,
    this.speakers = const [],
    this.width = 360,
    this.onSeek,
    this.sponsorRanges = const [],
    this.sponsorsInVideo,
    this.onSponsorListen,
    this.sponsoredMoments,
    this.onSponsoredListen,
    this.youtubeId,
    this.audioOnly = false,
    this.posterUrl,
    this.seekUndo,
  });

  @override
  State<VideoPanel> createState() => _VideoPanelState();
}

class _VideoPanelState extends State<VideoPanel> {
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _seeking = false;
  double _sliderValue = 0;

  /// In-app YouTube embed mode — native player pauziran, iframe preuzima.
  bool _ytMode = false;
  late final Map<String, GlobalKey> _chapterKeys = {
    for (final ch in widget.chapters) ch.timestamp: GlobalKey(),
  };

  @override
  void didUpdateWidget(VideoPanel old) {
    super.didUpdateWidget(old);
    if (widget.activeTimestamp != null &&
        widget.activeTimestamp != old.activeTimestamp) {
      _scheduleScrollTo(widget.activeTimestamp!);
    }
    if (widget.scrollTimestamp != null &&
        widget.scrollTimestamp != old.scrollTimestamp &&
        widget.scrollTimestamp != widget.activeTimestamp) {
      _scheduleScrollTo(widget.scrollTimestamp!);
    }
  }

  void _scheduleScrollTo(String timestamp) {
    // Odgodi na post-frame kad je layout zavrsen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _chapterKeys[timestamp];
      final ctx = key?.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(ctx, duration: Duration.zero, alignment: 0.3);
    });
  }

  @override
  void initState() {
    super.initState();
    // Inicijaliziraj iz trenutnog stanja playera (bitno kad se widget
    // rekreira, npr. sidebar → EndDrawer pri resize-u)
    _position = widget.player.state.position;
    _duration = widget.player.state.duration;
    _playing = widget.player.state.playing;
    if (_duration.inMilliseconds > 0) {
      _sliderValue = _position.inMilliseconds / _duration.inMilliseconds;
    }

    widget.player.stream.position.listen((p) {
      if (!_seeking && mounted) {
        setState(() {
          _position = p;
          _sliderValue = _duration.inMilliseconds > 0
              ? p.inMilliseconds / _duration.inMilliseconds
              : 0;
        });
      }
    });
    widget.player.stream.duration.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    widget.player.stream.playing.listen((p) {
      if (mounted) setState(() => _playing = p);
    });
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Boje govornika — dijeljena paleta s EpisodeVideo (fullscreen badge).
  Map<String, Color> _speakerColors(ThemeData theme) =>
      speakerColorsFor(theme, widget.speakers);

  void _enterYtMode() {
    widget.player.pause();
    setState(() => _ytMode = true);
  }

  void _exitYtMode() {
    setState(() => _ytMode = false);
  }

  SummarySpeaker? _currentSpeaker() {
    final timeline = widget.speakerTimeline;
    if (timeline == null) return null;
    final id = timeline.speakerAt(_position);
    if (id == null) return null;
    for (final s in widget.speakers) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final totalMs = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds
        : widget.totalDurationSeconds * 1000;
    final colors = _speakerColors(theme);
    final speaker = _currentSpeaker();

    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: widget.width != null
            ? Border(left: BorderSide(color: theme.colorScheme.outlineVariant))
            : null,
      ),
      // Nizak panel (mobitel u landscapeu: 360 × 354) ne stane ni bez
      // poglavlja — slika, kontrole i sponzori su viši od visine, pa je
      // stupac probijao dno (smoke test 13.10.2026.). Tada scrolla CIJELI
      // panel, a poglavlja nisu `Expanded`. Put do `EpisodeVideo` je u oba
      // načina isti (LayoutBuilder → scroll → SizedBox → Column), da se
      // video pri rotaciji ne remontira — na webu bi re-parent `<video>`
      // elementa pauzirao reprodukciju.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < _kCompactPanelHeight;
          final chapters = Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final ch in widget.chapters)
                  _ChapterListItem(
                    key: _chapterKeys[ch.timestamp],
                    chapter: ch,
                    isPlaying: ch.timestamp == widget.activeTimestamp,
                    isScrolled:
                        ch.timestamp == widget.scrollTimestamp &&
                        ch.timestamp != widget.activeTimestamp,
                    onTap: () => widget.onChapterTap(ch.timestamp),
                  ),
              ],
            ),
          );
          return SingleChildScrollView(
            physics: compact ? null : const NeverScrollableScrollPhysics(),
            child: SizedBox(
              height: compact ? null : constraints.maxHeight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Video display (16:9) — native player ili YouTube embed mode
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      children: [
                        Container(
                          color: Colors.black,
                          child: widget.audioOnly
                              ? AudioPoster(artUrl: widget.posterUrl)
                              : _ytMode && widget.youtubeId != null
                              ? YouTubeEmbed(
                                  videoId: widget.youtubeId!,
                                  startSeconds: _position.inSeconds,
                                )
                              : EpisodeVideo(
                                  player: widget.player,
                                  controller: widget.controller,
                                  speakerTimeline: widget.speakerTimeline,
                                  speakers: widget.speakers,
                                  seekUndo: widget.seekUndo,
                                  sponsoredMoments: widget.sponsoredMoments,
                                  onYouTubeMode:
                                      youTubeEmbedSupported &&
                                          widget.youtubeId != null
                                      ? _enterYtMode
                                      : null,
                                ),
                        ),
                        // Unmute CTA za muted autoplay (browser politika) — SAMO na
                        // audio-only putanji: kod videa isti overlay već crta
                        // `EpisodeVideo` kroz `controls:` builder (i u fullscreenu),
                        // pa bi se ovdje udvostručio. Stanje ide kroz `PlayerMute`
                        // singleton, ne kroz parametre — prošla izvedba ga je
                        // provlačila propovima i ispustila baš na mobilnim pozivima.
                        // Paused overlay je uklonjen — klik na video sad toggle-a
                        // play/pause (playAndPauseOnTap u EpisodeVideo).
                        if (widget.audioOnly)
                          Positioned.fill(
                            child: UnmuteOverlay(
                              onUnmuted: () {
                                if (!_playing) widget.player.play();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),

                  if (_ytMode) YouTubeModeBar(onExit: _exitYtMode),

                  // Mobitel u portraitu: titl ispod slike umjesto preko nje (overlay
                  // se tada sam skloni, osim u fullscreenu — vidi `EpisodeVideo`).
                  if (!_ytMode &&
                      !widget.audioOnly &&
                      widget.speakerTimeline != null &&
                      subtitlesBelowPlayer(context))
                    SubtitleStrip(
                      player: widget.player,
                      timeline: widget.speakerTimeline!,
                    ),

                  // Controls
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Column(
                      children: [
                        // Speaker timeline bar
                        if (widget.speakerTimeline != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  return SizedBox(
                                    height: 6,
                                    width: constraints.maxWidth,
                                    child: CustomPaint(
                                      painter: _SpeakerBarPainter(
                                        segments:
                                            widget.speakerTimeline!.segments,
                                        totalMs: totalMs,
                                        colors: colors,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),

                        // Undo skoka — samo na audio-only putanji. Kod videa istu
                        // pilulu već crta EpisodeVideo preko slike (i u fullscreenu),
                        // pa bi je ovdje dobili dvaput.
                        if (widget.seekUndo != null && widget.audioOnly)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Center(
                              child: SeekUndoPill(
                                undo: widget.seekUndo!,
                                onUndo: widget.player.seek,
                              ),
                            ),
                          ),

                        // Seek bar s chapter markerima
                        _SeekBar(
                          value: _sliderValue,
                          chapters: widget.chapters,
                          sponsorRanges: widget.sponsorRanges,
                          paidRanges:
                              widget.sponsoredMoments?.moments.ranges ??
                              const [],
                          totalMs: totalMs,
                          onChangeStart: (_) => setState(() => _seeking = true),
                          onChanged: (v) => setState(() => _sliderValue = v),
                          onChangeEnd: (v) async {
                            final ms = (v * totalMs).round();
                            final dur = Duration(milliseconds: ms);
                            await widget.player.seek(dur);
                            widget.onSeek?.call(dur);
                            if (mounted) setState(() => _seeking = false);
                          },
                        ),

                        // Vrijeme
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _fmt(_position),
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontFamily: 'monospace',
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _fmt(_duration),
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontFamily: 'monospace',
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),

                        // Play/Pause + skip + brzina + zvuk + „u pozadini".
                        // media_kitov control bar preko slike se sam sakriva (i ne
                        // postoji na audio-only putanji), pa je ovo uvijek vidljivi
                        // ulaz u iste postavke — uključujući jedini unmute na
                        // audio-only epizodama.
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            const SpeedCycleButton(),
                            const MuteToggleButton(),
                            IconButton(
                              icon: const Icon(Icons.replay_10),
                              onPressed: () => widget.player.seek(
                                _position - const Duration(seconds: 10),
                              ),
                              tooltip: '-10s',
                            ),
                            IconButton(
                              iconSize: 40,
                              icon: Icon(
                                _playing
                                    ? Icons.pause_circle_filled
                                    : Icons.play_circle_filled,
                              ),
                              color: theme.colorScheme.primary,
                              tooltip: _playing ? l.mediaPause : l.mediaPlay,
                              onPressed: () => _playing
                                  ? widget.player.pause()
                                  : widget.player.play(),
                            ),
                            IconButton(
                              icon: const Icon(Icons.forward_10),
                              onPressed: () => widget.player.seek(
                                _position + const Duration(seconds: 10),
                              ),
                              tooltip: '+10s',
                            ),
                            const BackgroundPlaybackButton(),
                          ],
                        ),

                        // Trenutni govornik
                        if (speaker != null)
                          _CurrentSpeakerRow(
                            speaker: speaker,
                            color:
                                colors[speaker.id] ?? theme.colorScheme.outline,
                          ),
                      ],
                    ),
                  ),

                  // Sponzori u snimci — ovdje jer je panel playera (na mobitelu
                  // ladica) površina koju korisnik stvarno gleda.
                  if (widget.sponsorsInVideo?.hasNamed ?? false) ...[
                    Divider(height: 1, color: theme.colorScheme.outlineVariant),
                    SponsorsInVideoPlayerStrip(
                      data: widget.sponsorsInVideo,
                      onListen: widget.onSponsorListen,
                    ),
                  ],

                  // Plaćeni trenuci — odmah ispod autorovih sponzora, ali kao
                  // zaseban blok s „Sponzorirano · {brand}".
                  if (widget.sponsoredMoments?.moments.isNotEmpty ?? false) ...[
                    Divider(height: 1, color: theme.colorScheme.outlineVariant),
                    SponsoredMomentsPlayerStrip(
                      controller: widget.sponsoredMoments,
                      onListen: widget.onSponsoredListen,
                    ),
                  ],

                  Divider(height: 1, color: theme.colorScheme.outlineVariant),

                  // Chapter lista — scrollable
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Text(
                      l.mediaChapters,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  if (compact)
                    chapters
                  else
                    Expanded(child: SingleChildScrollView(child: chapters)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _SeekBar extends StatelessWidget {
  final double value;
  final List<VideoChapterMark> chapters;
  final List<({Duration start, Duration end})> sponsorRanges;

  /// Plaćeni trenuci — crtaju se ISTOM geometrijom, ali [AppTheme
  /// .sponsoredAccent] bojom, da se oglas razlikuje od autorovog sponzora.
  final List<({Duration start, Duration end})> paidRanges;
  final int totalMs;
  final ValueChanged<double> onChangeStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _SeekBar({
    required this.value,
    required this.chapters,
    this.sponsorRanges = const [],
    this.paidRanges = const [],
    required this.totalMs,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      alignment: Alignment.center,
      children: [
        // Chapter markers (renderiraju se ispod Slidera)
        LayoutBuilder(
          builder: (context, constraints) {
            return SizedBox(
              height: 24,
              width: constraints.maxWidth,
              child: CustomPaint(
                painter: _ChapterMarkerPainter(
                  chapters: chapters,
                  sponsorRanges: sponsorRanges,
                  paidRanges: paidRanges,
                  totalMs: totalMs,
                  color: theme.colorScheme.primary.withAlpha(120),
                  sponsorColor: theme.colorScheme.tertiary.withAlpha(110),
                  paidColor: AppTheme.sponsoredAccent(theme.brightness),
                ),
              ),
            );
          },
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: value.clamp(0.0, 1.0),
            onChangeStart: onChangeStart,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ],
    );
  }
}

class _ChapterMarkerPainter extends CustomPainter {
  final List<VideoChapterMark> chapters;
  final List<({Duration start, Duration end})> sponsorRanges;
  final List<({Duration start, Duration end})> paidRanges;
  final int totalMs;
  final Color color;
  final Color sponsorColor;
  final Color paidColor;

  const _ChapterMarkerPainter({
    required this.chapters,
    this.sponsorRanges = const [],
    this.paidRanges = const [],
    required this.totalMs,
    required this.color,
    required this.sponsorColor,
    required this.paidColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (totalMs <= 0) return;
    // Rasponi poruka sponzora: tanka traka ispod tracka, najmanje 3 px da se
    // kratak spot (45 s u 2 h) uopće vidi.
    void bands(List<({Duration start, Duration end})> ranges, Color c) {
      final band = Paint()..color = c;
      for (final r in ranges) {
        final x0 = r.start.inMilliseconds / totalMs * size.width;
        var x1 = r.end.inMilliseconds / totalMs * size.width;
        if (x1 - x0 < 3) x1 = x0 + 3;
        canvas.drawRRect(
          RRect.fromLTRBR(
            x0,
            size.height * 0.62,
            x1.clamp(0, size.width),
            size.height * 0.62 + 3,
            const Radius.circular(1.5),
          ),
          band,
        );
      }
    }

    bands(sponsorRanges, sponsorColor);
    // Plaćeni preko autorovih: ako se preklope, oglas mora biti vidljiv.
    bands(paidRanges, paidColor);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (final ch in chapters) {
      final x = ch.position.inMilliseconds / totalMs * size.width;
      canvas.drawLine(
        Offset(x, size.height * 0.1),
        Offset(x, size.height * 0.9),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ChapterMarkerPainter old) =>
      old.chapters != chapters ||
      old.sponsorRanges != sponsorRanges ||
      old.paidRanges != paidRanges ||
      old.paidColor != paidColor ||
      old.totalMs != totalMs;
}

// ---------------------------------------------------------------------------

class _SpeakerBarPainter extends CustomPainter {
  final List<SpeakerSegment> segments;
  final int totalMs;
  final Map<String, Color> colors;

  const _SpeakerBarPainter({
    required this.segments,
    required this.totalMs,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (totalMs <= 0) return;
    for (final seg in segments) {
      final x1 = seg.startMs / totalMs * size.width;
      final x2 = seg.endMs / totalMs * size.width;
      final color = colors[seg.speakerId] ?? const Color(0x40808080);
      canvas.drawRect(
        Rect.fromLTWH(x1, 0, (x2 - x1).clamp(0.5, size.width), size.height),
        Paint()..color = color.withAlpha(180),
      );
    }
  }

  @override
  bool shouldRepaint(_SpeakerBarPainter old) =>
      old.segments != segments || old.totalMs != totalMs;
}

// ---------------------------------------------------------------------------

class _CurrentSpeakerRow extends StatelessWidget {
  final SummarySpeaker speaker;
  final Color color;

  const _CurrentSpeakerRow({required this.speaker, required this.color});

  String get _initials {
    final name = speaker.displayName ?? speaker.roleLabel;
    if (name.isEmpty) return '?';
    final parts = name.split(' ');
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = speaker.displayName;
    final roleLabel = speaker.roleLabel;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color.withAlpha(40),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: color, width: 1.5),
            ),
            child: Center(
              child: Text(
                _initials,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // Anonymous host (suggested_name == role) → samo roleLabel.
                  name ?? roleLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                if (name != null && roleLabel.isNotEmpty)
                  Text(
                    roleLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
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
}

// ---------------------------------------------------------------------------

class _ChapterListItem extends StatelessWidget {
  final VideoChapterMark chapter;
  final bool isPlaying;
  final bool isScrolled;
  final VoidCallback onTap;

  const _ChapterListItem({
    super.key,
    required this.chapter,
    required this.isPlaying,
    required this.isScrolled,
    required this.onTap,
  });

  static const _scrollColor = Color(0xFFEF6C00);

  String get _shortTs {
    final parts = chapter.timestamp.split(':');
    if (parts.length == 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      if (h == 0) return '${parts[1]}:${parts[2]}';
      return '$h:${parts[1]}:${parts[2]}';
    }
    return chapter.timestamp;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isHighlighted = isPlaying || isScrolled;
    final accentColor = isPlaying ? theme.colorScheme.primary : _scrollColor;

    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: isHighlighted
            ? BoxDecoration(
                color: accentColor.withAlpha(isPlaying ? 120 : 40),
                border: Border(left: BorderSide(color: accentColor, width: 3)),
              )
            : null,
        padding: EdgeInsets.fromLTRB(isHighlighted ? 9 : 12, 6, 8, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.play_arrow,
              size: 14,
              color: isHighlighted ? accentColor : theme.colorScheme.outline,
            ),
            const SizedBox(width: 4),
            Text(
              _shortTs,
              style: theme.textTheme.labelSmall?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                color: isHighlighted ? accentColor : theme.colorScheme.outline,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                chapter.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isHighlighted
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: isHighlighted
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
