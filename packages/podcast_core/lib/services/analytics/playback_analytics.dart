/// Događaji reprodukcije za vlastitu analitiku: start, pauza/nastavak, skok,
/// pragovi napretka i koliko je stvarno odslušano.
///
/// Sluša `player.stream.playing` i `player.stream.position` iz istog razloga
/// kao `services/seek_undo.dart` i `services/playback_intent.dart`: pauza i
/// seek idu kroz pet putanja bez zajedničkog callbacka (naše trake,
/// media_kitov tap, tipkovnica, lock screen), a stream ih hvata sve.
///
/// Čista logika bez `media_kit`a — prima streamove i sink, pa je testabilna
/// (`test/playback_analytics_test.dart`). Popis događaja i polja:
/// `domovina-analytics/docs/ugovor.md`.
library;

import 'dart:async';

import 'analytics.dart';

typedef PlaybackEventSink = void Function(
  String name,
  Map<String, Object?> props,
);

class PlaybackAnalytics {
  PlaybackAnalytics({
    required Stream<bool> playingStream,
    required Stream<Duration> positionStream,
    required this.videoId,
    required this.surface,
    required int durationSeconds,
    PlaybackEventSink? sink,
    this.jumpThreshold = const Duration(seconds: 2),
    this.seekSettle = const Duration(milliseconds: 1500),
    this.openWindow = const Duration(seconds: 8),
    DateTime Function()? clock,
  })  : _duration = durationSeconds,
        _clock = clock ?? DateTime.now {
    _sink = sink ?? _toAnalytics;
    _openedAt = _clock();
    _subs = [
      playingStream.listen(_onPlaying),
      positionStream.listen(_onPosition),
    ];
  }

  /// Pragovi napretka u postotcima trajanja; svaki se javlja jednom po
  /// otvaranju epizode.
  static const milestones = [10, 25, 50, 75, 90];

  final String videoId;

  /// Gdje je player: `v` (detaljni ekran), `m` (jednostavni), `tv`.
  final String surface;

  /// Kao `SeekUndo`: position fira ~5×/s, pri 2,0× je prirodni korak ~0,4 s.
  final Duration jumpThreshold;

  /// Povlačenje slidera daje niz skokova; javlja se jedan, kad se smiri.
  final Duration seekSettle;

  /// Resume-seek pri otvaranju (`openAndResume` čeka duration do 5 s) nije
  /// korisnikov skok.
  final Duration openWindow;

  final DateTime Function() _clock;
  late final PlaybackEventSink _sink;
  late final List<StreamSubscription<Object?>> _subs;
  late final DateTime _openedAt;

  int _duration;
  bool _playing = false;
  bool _started = false;
  Duration? _last;
  final Set<int> _reached = {};

  /// Stvarno odslušano: zbroj prirodnih pomaka pozicije dok svira. Skok se
  /// ne zbraja, pa „odslušano" ne raste kad korisnik premota na kraj.
  double _listened = 0;

  Duration? _seekFrom;
  Duration? _seekTo;
  Timer? _seekTimer;
  bool _disposed = false;

  int get listenedSeconds => _listened.round();

  /// Trajanje stigne kasnije od otvaranja (`player.stream.duration`).
  set durationSeconds(int seconds) {
    if (seconds > 0) _duration = seconds;
  }

  static void _toAnalytics(String name, Map<String, Object?> props) {
    Analytics.instance.track(
      name,
      videoId: props.remove('video_id') as String?,
      props: props,
    );
  }

  void _emit(String name, [Map<String, Object?> extra = const {}]) {
    _sink(name, {
      'video_id': videoId,
      'surface': surface,
      'position_s': (_last ?? Duration.zero).inSeconds,
      ...extra,
    });
  }

  void _onPlaying(bool playing) {
    if (_disposed || playing == _playing) return;
    _playing = playing;
    if (playing && !_started) {
      _started = true;
      _emit('playback_start', {
        'duration_s': _duration,
        'wait_ms': _clock().difference(_openedAt).inMilliseconds,
      });
    } else if (_started) {
      // `listened_s` je kumulativan i na pauzi: zatvoren tab ne stigne do
      // `playback_end`, pa je zadnja pauza ili prag najbolja donja granica.
      _emit(
        playing ? 'playback_resume' : 'playback_pause',
        playing ? const {} : {'listened_s': listenedSeconds},
      );
    }
  }

  void _onPosition(Duration position) {
    if (_disposed) return;
    final last = _last;
    _last = position;
    if (last == null) return;
    final delta = position - last;
    if (delta.abs() > jumpThreshold) {
      if (_clock().difference(_openedAt) > openWindow) _noteSeek(last, position);
      // Prag preskočen skokom (resume, premotavanje) nije dosegnut slušanjem.
      _checkMilestones(position, silent: true);
      return;
    }
    if (_playing && delta > Duration.zero) {
      _listened += delta.inMicroseconds / Duration.microsecondsPerSecond;
    }
    _checkMilestones(position);
  }

  void _noteSeek(Duration from, Duration to) {
    _seekFrom ??= from;
    _seekTo = to;
    _seekTimer?.cancel();
    _seekTimer = Timer(seekSettle, _flushSeek);
  }

  void _flushSeek() {
    _seekTimer?.cancel();
    _seekTimer = null;
    final from = _seekFrom;
    final to = _seekTo;
    _seekFrom = null;
    _seekTo = null;
    if (from == null || to == null) return;
    if ((to - from).abs() <= jumpThreshold) return;
    _sink('playback_seek', {
      'video_id': videoId,
      'surface': surface,
      'from_s': from.inSeconds,
      'to_s': to.inSeconds,
    });
  }

  void _checkMilestones(Duration position, {bool silent = false}) {
    if (_duration <= 0) return;
    final pct = position.inSeconds * 100 / _duration;
    for (final m in milestones) {
      if (pct >= m && _reached.add(m) && !silent) {
        _emit('playback_progress', {'pct': m, 'listened_s': listenedSeconds});
      }
    }
  }

  /// Zatvaranje epizode. Ako je reprodukcija uopće krenula, javlja koliko je
  /// odslušano — glavna brojka za „vrijeme slušanja".
  void dispose() {
    if (_disposed) return;
    _flushSeek();
    _disposed = true;
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    if (_started) {
      _emit('playback_end', {
        'listened_s': listenedSeconds,
        'duration_s': _duration,
        'end_pct': _duration > 0
            ? ((_last ?? Duration.zero).inSeconds * 100 / _duration).round()
            : 0,
      });
    }
  }
}
