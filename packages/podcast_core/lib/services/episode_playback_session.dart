import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../src/log.dart' show log;
import 'analytics/playback_analytics.dart';
import 'cdn_config.dart';
import 'data_service.dart' show EpisodeData;
import 'player_resume.dart';
import 'watch_progress_service.dart';

/// Jedna reprodukcija jedne epizode, dijeljena među ekranima.
///
/// Životni ciklus playera (otvaranje, resume, spremanje napretka, analitika,
/// mpv postavke) bio je napisan u svakom ekranu zasebno, pa je svaka nova
/// stvar oko reprodukcije stizala samo u neke od njih. Sesija ga drži na
/// jednom mjestu; ekran crta stanje i šalje naredbe.
///
/// Ekrani istog videa dijele ISTU sesiju ([acquire] / [release], brojanje
/// referenci). Bez toga je TV epizoda — koja nakon `drillDown` u čitač ostaje
/// montirana ispod — svirala dalje dok je čitač pokretao drugi player: dva
/// zvuka istovremeno i dva neusklađena napretka.
///
/// Danas je koriste TV ekrani (`TvEpisodeScreen`, `TvEpisodeReaderScreen`);
/// `EpisodeScreen` prelazi na nju u zasebnom koraku
/// (docs/plans/2026-10-17-tv-uskladivanje-i-refaktor.md, R1).
class EpisodePlaybackSession extends ChangeNotifier {
  EpisodePlaybackSession._(this.videoId, this.surface);

  static final Map<String, EpisodePlaybackSession> _live = {};

  /// Vrati živu sesiju za [videoId] ili napravi novu. Svaki [acquire] traži
  /// svoj [release].
  static EpisodePlaybackSession acquire(
    String videoId, {
    required String surface,
  }) {
    final s = _live.putIfAbsent(
      videoId,
      () => EpisodePlaybackSession._(videoId, surface),
    );
    s._refs++;
    return s;
  }

  /// Za testove.
  @visibleForTesting
  static EpisodePlaybackSession? liveFor(String videoId) => _live[videoId];

  /// mpv `hwdec` za ovaj build (`--dart-define=MPV_HWDEC=no|auto-safe|…`).
  /// Prazno = default media_kita (`auto-safe`). Služi za mjerenje dekodera na
  /// uređaju bez mijenjanja koda.
  static const _hwdecOverride = String.fromEnvironment('MPV_HWDEC');

  /// Kodeci koje mpv smije dati hardverskom dekoderu. media_kit na Androidu
  /// navodi i `av1`, ali EON SDSTB02 (Amlogic, Android 11) AV1 mediacodec
  /// prijavi pa ga ne dekodira („Unsupported or unknown profile"). AV1 je
  /// samo stari `video.mp4` (640×360, softverski trivijalan); H.264 iz
  /// `video_h264(_fmp4).mp4` ostaje na hardveru.
  static const _hwdecCodecs = 'h264,hevc,mpeg4,mpeg2video,vp8,vp9';

  final String videoId;

  /// Oznaka površine za analitiku (`tv`, …).
  final String surface;

  int _refs = 0;
  bool _disposed = false;

  EpisodeData? _data;
  Player? _player;
  VideoController? _controller;
  Future<void>? _opening;
  PlaybackAnalytics? _analytics;
  final List<StreamSubscription<Object?>> _subs = [];
  Timer? _saveTimer;
  Timer? _pollTimer;
  Timer? _statsTimer;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;
  bool _playing = false;
  bool _buffering = true;
  bool _firstFrame = false;
  DateTime? _loadStartedAt;

  EpisodeData? get data => _data;
  Player? get player => _player;

  /// Postavljen čim je [open] krenuo — ekran tada može montirati `Video`
  /// widget (mpv-u treba surface prije `open()` medije, vidi [open]).
  VideoController? get controller => _controller;
  Duration get position => _position;
  Duration get duration => _duration;
  Duration get buffer => _buffer;
  bool get playing => _playing;
  bool get buffering => _buffering;

  /// True kad su frameovi stvarno krenuli (ne samo poslan play).
  bool get firstFrame => _firstFrame;
  DateTime? get loadStartedAt => _loadStartedAt;

  /// Je li reprodukcija već otvorena (drugi ekran istog videa ju je pokrenuo).
  bool get isOpen => _opening != null;

  /// Otvori medij i krene reprodukciju. Idempotentno: ako je sesija već
  /// otvorena (čitač nad živom epizodom), ne radi ništa i [startAtSeconds]
  /// se ignorira — reprodukcija se nastavlja gdje jest.
  ///
  /// Resume: [startAtSeconds] (URL `t=`) ima prednost, inače spremljeni
  /// napredak ako je > 5 s i epizoda nije odgledana.
  Future<void> open(EpisodeData data, {int? startAtSeconds}) =>
      _opening ??= _open(data, startAtSeconds);

  Future<void> _open(EpisodeData data, int? startAtSeconds) async {
    _data = data;
    int? startAt = startAtSeconds;
    if (startAt == null) {
      final saved = WatchProgressService.instance.getSync(videoId);
      if (saved != null && !saved.completed && saved.positionSeconds > 5) {
        startAt = saved.positionSeconds;
        log('PlaybackSession: resume from ${saved.positionSeconds}s');
      }
    }

    // logLevel warn — libmpv warninzi (TLS, demuxer, codec) stižu u
    // `stream.log`, pa se u logcatu vidi zašto video ne kreće.
    final player = Player(
      configuration: const PlayerConfiguration(logLevel: MPVLogLevel.warn),
    );
    _player = player;
    _controller = VideoController(player);
    _analytics = PlaybackAnalytics(
      playingStream: player.stream.playing,
      positionStream: player.stream.position,
      videoId: videoId,
      surface: surface,
      durationSeconds: data.info.duration,
    );
    // Error/log PRIJE open-a — open već može propucati error.
    _subs.add(player.stream.error.listen((e) => log('mpv ERROR: $e')));
    _subs.add(player.stream.log
        .listen((e) => log('mpv [${e.level}] ${e.prefix}: ${e.text.trim()}')));
    notifyListeners();

    // Redoslijed je ključan: ekran montira `Video` čim vidi [controller], a
    // mpv-u treba native surface prije `open()` — na surface=NULL hardverski
    // kodeci daju „Both surface and native_window are NULL" i drugi load zna
    // visjeti na „Priprema…". Zato jedan frame čekanja.
    await WidgetsBinding.instance.endOfFrame;
    if (_disposed) return;

    await _configureMpv(player);
    if (_disposed) return;

    log('PlaybackSession: opening ${data.videoUri}');
    _loadStartedAt = DateTime.now();
    await openAndResume(player, uri: data.videoUri, startAtSeconds: startAt);
    if (_disposed) return;

    _subs.add(player.stream.position.listen((p) {
      _position = p;
      if (!_firstFrame && _playing && !_buffering) _firstFrame = true;
      notifyListeners();
    }));
    _subs.add(player.stream.duration.listen((d) {
      _duration = d;
      notifyListeners();
    }));
    _subs.add(player.stream.buffer.listen((b) {
      _buffer = b;
      notifyListeners();
    }));
    _subs.add(player.stream.playing.listen((p) {
      _playing = p;
      if (p && !_buffering) _firstFrame = true;
      notifyListeners();
    }));
    _subs.add(player.stream.buffering.listen((b) {
      _buffering = b;
      if (!b && _playing) _firstFrame = true;
      notifyListeners();
    }));

    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) => save());
    _startPoll();
  }

  Future<void> _configureMpv(Player player) async {
    final platform = player.platform;
    if (platform == null) return;
    try {
      final p = platform as dynamic;
      await p.setProperty('hwdec-codecs', _hwdecCodecs);
      if (_hwdecOverride.isNotEmpty) {
        await p.setProperty('hwdec', _hwdecOverride);
      }
      // Suprimira „Failed to create file cache" (Android sandbox).
      await p.setProperty('cache', 'no');
      log('PlaybackSession: mpv hwdec-codecs=$_hwdecCodecs'
          '${_hwdecOverride.isEmpty ? '' : ' hwdec=$_hwdecOverride'}');
    } catch (e) {
      log('PlaybackSession: setProperty failed (web?): $e');
    }
  }

  /// libmpv na Androidu ne emitira `stream.buffer`/`position` pouzdano prije
  /// prvog framea (buffer stoji na 0 pa skoči), pa se do tada stanje čita
  /// izravno iz `player.state`. Ekran iz [loadStartedAt] crta i vremenski
  /// fallback napretka.
  void _startPoll() {
    var ticks = 0;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final p = _player;
      if (p == null) return;
      final s = p.state;
      ticks++;
      _buffer = s.buffer;
      _position = s.position;
      _buffering = s.buffering;
      _playing = s.playing;
      if (s.playing && !s.buffering) _firstFrame = true;
      notifyListeners();
      if (!_firstFrame && ticks % 5 == 0) {
        log('PlaybackSession poll #$ticks: buffer=${s.buffer.inMilliseconds}ms '
            'pos=${s.position.inMilliseconds}ms '
            'buffering=${s.buffering} playing=${s.playing}');
      }
      if (_firstFrame) {
        _pollTimer?.cancel();
        _pollTimer = null;
        log('PlaybackSession: first frame after ${ticks * 200}ms');
        _logDecoderStats();
        _statsTimer = Timer.periodic(
            const Duration(seconds: 60), (_) => _logDecoderStats());
      }
    });
  }

  /// Trag u logcatu kojim se dekoder mjeri na uređaju: koji je stvarno
  /// izabran i koliko frameova pada.
  Future<void> _logDecoderStats() async {
    final platform = _player?.platform;
    if (platform == null) return;
    try {
      final p = platform as dynamic;
      final hw = await p.getProperty('hwdec-current');
      final codec = await p.getProperty('video-codec');
      final drop = await p.getProperty('frame-drop-count');
      final decDrop = await p.getProperty('decoder-frame-drop-count');
      log('PlaybackSession stats: codec=$codec hwdec-current=$hw '
          'frame-drop=$drop decoder-drop=$decDrop '
          'pos=${_position.inSeconds}s');
    } catch (_) {}
  }

  Future<void> togglePlay() async {
    final p = _player;
    if (p == null) return;
    p.state.playing ? await p.pause() : await p.play();
  }

  Future<void> seek(Duration to) async => _player?.seek(to);

  /// Spremi napredak (debounce i remote upsert radi [WatchProgressService]).
  void save() {
    final data = _data;
    if (data == null || _position.inSeconds < 5) return;
    WatchProgressService.instance.scheduleSave(
      episodeId: videoId,
      positionSeconds: _position.inSeconds,
      durationSeconds:
          _duration.inSeconds > 0 ? _duration.inSeconds : data.info.duration,
      channelId: data.info.channelId,
      episodeTitle: data.displayTitle,
      episodeThumbnailUrl: CdnConfig.thumbnailUrl(videoId),
    );
  }

  /// Otpusti referencu; zadnja spremi napredak i ugasi player.
  void release() {
    if (_disposed) return;
    _refs--;
    if (_refs > 0) return;
    _live.remove(videoId);
    _disposed = true;
    _saveTimer?.cancel();
    _pollTimer?.cancel();
    _statsTimer?.cancel();
    save();
    unawaited(WatchProgressService.instance.flush());
    for (final s in _subs) {
      s.cancel();
    }
    _analytics?.dispose();
    _player?.dispose();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }
}
