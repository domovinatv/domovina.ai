import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../l10n/app_localizations.dart';
import '../../brand/app_brand.dart';
import '../../src/log.dart' show log;
import '../../models/podcast_outline.dart';
import '../../services/cdn_config.dart';
import '../../services/data_service.dart';
import '../../services/analytics/playback_analytics.dart';
import '../../services/player_resume.dart';
import '../../services/watch_progress_service.dart';
import '../../widgets/cached_thumbnail.dart';
import 'widgets/tv_focus.dart';
import 'widgets/tv_key_hint.dart';
import '../../router/nav.dart';

/// Faza 4 — TV episode screen.
///
/// Standalone 10-foot UI za prikaz epizode. Layout je vertikalan jer EON SDSTB02
/// daje 540 dp visine — hero player + meta + chapter rail moraju stati u scroll
/// view bez side-by-side stiskanja:
///
///   Hero player (62% min(540, h)) — video + D-pad transport overlay
///   Title + channel/duration
///   Abstract (kompaktan, 4 retka clamp)
///   "Poglavlja" rail — focusable cards, OK = seek
///
/// D-pad model:
///   - OK na playeru = play/pause
///   - ◀▲▶▼ = default focus traversal (UP → toolbar Čitaj/Fullscreen)
///   - MEDIA_PLAY_PAUSE podržan
///   - BACK = popa stog (kanal/osoba s koje si došao); bez stoga → home
///
/// Seek je NAMJERNO maknut s D-pad arrow keys jer je bio nepredvidljiv —
/// korisnik bi pokušao navigirati do toolbar gumba i slučajno seek-ao.
/// Ako seek bude trebao, eksplicitni -10s/+10s gumbi idu u toolbar.
///
/// Reuse: ista `EpisodeData.load` data layer kao `EpisodeScreen`, isti
/// `WatchProgressService.scheduleSave` resume/save flow. Magisterium panel
/// i EN toggle dolaze u Fazi 4.5 — Magisterium je tezi za 10-foot pa zasluzuje
/// vlastiti side panel umjesto da se trpa u inline list.
class TvEpisodeScreen extends StatefulWidget {
  final String youtubeId;

  /// Start at position in seconds (`/v/<id>/t/<sec>` ili `?t=`). Override
  /// resume-saved-position-a, ako je oba.
  final int? startAtSeconds;

  const TvEpisodeScreen({
    super.key,
    required this.youtubeId,
    this.startAtSeconds,
  });

  @override
  State<TvEpisodeScreen> createState() => _TvEpisodeScreenState();
}

class _TvEpisodeScreenState extends State<TvEpisodeScreen> {
  EpisodeData? _data;
  Object? _error;

  Player? _player;
  VideoController? _controller;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;
  bool _playing = false;
  bool _buffering = true;

  // Target koliko sekundi unaprijed mora biti buffered prije nego se UI prebaci
  // u playing state. 5s je razuman trade-off — dovoljno da ne stutter na
  // sporijem TV mreznom adapteru, dovoljno malo da percipirano vrijeme do
  // playback-a ostane ispod 10s na 5-10 Mbps vezi.
  static const _bufferTargetSec = 5.0;

  // Time-based fallback target. libmpv Android backend zna ne emitati
  // `state.buffer` granular updateove tijekom inicijalnog prebuffera — stoji
  // 0 sve dok video ne pocne, pa skoci. Bez fallbacka, progress ring visi
  // na 0%. Time fallback estimira da prvi frame dođe za ~8s na prosjecnoj
  // TV mrezi (5-10 Mbps); progress = (elapsed-500ms) / 8000ms. Uzimamo max
  // od (real, time) pa ako buffer napredak postoji, real ga overrideuje.
  static const _timeFallbackTargetMs = 8000;
  DateTime? _loadStartedAt;

  // True nakon sto je prvi frame stvarno renderirao. Drzimo thumbnail backdrop
  // dok ovo nije true — bez ovoga TV pokazuje crni rect 5-10s na prosjecnom
  // internetu, sto izgleda kao da je app crashao. Postavlja se na true prvi
  // put kad `playing=true && position > 0` (znaci media_kit je zapocelo
  // dekodirati i prikazivati frameove, ne samo poslati play komandu).
  bool _firstFrame = false;

  // Overlay kontrola se gasi 4s nakon zadnje interakcije — TV konvencija
  // (Netflix, YouTube TV) da se ne ometa gledanje. Bilo koji D-pad event
  // (seek, toggle) je ponovno upali.
  bool _showOverlay = true;
  Timer? _overlayHideTimer;

  // Periodicni save 5s — WatchProgressService.scheduleSave dalje debounceuje
  // remote upsert (ne saljemo Supabase upsert svake sekunde).
  Timer? _saveTimer;

  // Poll `player.state.buffer` svake 250ms tijekom inicijalnog loadinga jer
  // media_kit Android backend (libmpv) ne emitira `stream.buffer` updateove
  // konzistentno — buffer u logu zna ostati 0s dok video nije gotov pa skoci
  // odjednom. Bez polla, progress ring bi visio na 0% dok ne kresne 100%.
  // Stopiramo polling jednom kad _firstFrame=true (player vise nije u
  // "punim se" stanju).
  Timer? _pollTimer;

  final FocusNode _playerFocus = FocusNode(debugLabel: 'tv-episode-player');
  // Fullscreen gumb u overlay-u ima vlastiti focusNode da je dohvatljiv
  // D-pad-om: korisnik na playeru pritisne UP, fokus se prebaci na ovaj
  // gumb. DOWN s gumba vraca focus playeru. LEFT/RIGHT na playeru su
  // zauzeti seek-om pa je UP/DOWN jedini razuman put do overlay action-a.
  final FocusNode _fullscreenFocus =
      FocusNode(debugLabel: 'tv-episode-fullscreen-btn');
  // "Čitaj" gumb — vodi u TvEpisodeReaderScreen ("blog reader" mode). Isti
  // D-pad pattern kao fullscreen (UP s playera → toolbar, LEFT/RIGHT
  // izmedju toolbar buttona). Vidljiv samo kad data.hasAiContent.
  final FocusNode _readerFocus =
      FocusNode(debugLabel: 'tv-episode-reader-btn');

  // Fullscreen toggle — gumb u overlay-u + key 'F'. U fullscreen modu skrivamo
  // title/abstract/chapter list i video popunjava cijeli SafeArea. BACK u
  // fullscreen-u izlazi iz fullscreen-a umjesto na home.
  bool _fullscreen = false;

  // Scroll controller za vertical chapter list — auto-scroll active chapter u
  // centar viewport-a kako player napreduje. Bez ovoga, aktivno poglavlje
  // moze pasti izvan vidljivog dijela liste tijekom dugih epizoda.
  final ScrollController _chaptersScroll = ScrollController();
  int _activeChapterIndex = -1;
  // GlobalKey-evi za svaki chapter item — koristimo ih za ensureVisible
  // animaciju kad se aktivni chapter promijeni.
  final Map<int, GlobalKey> _chapterKeys = {};

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<Duration>? _bufferSub;
  StreamSubscription<bool>? _playingSub;
  PlaybackAnalytics? _playbackAnalytics;
  StreamSubscription<bool>? _bufferingSub;

  @override
  void initState() {
    super.initState();
    log('TvEpisodeScreen.init id=${widget.youtubeId} startAt=${widget.startAtSeconds}');
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await EpisodeData.load(youtubeId: widget.youtubeId);
      if (!mounted) return;
      setState(() => _data = data);
      await _initPlayer(data);
    } catch (e) {
      log('TvEpisodeScreen.load error: $e');
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _initPlayer(EpisodeData data) async {
    // Resume policy: URL t= ima prednost. Inače saved progress ako > 5s i
    // epizoda nije completed. Identično EpisodeScreen-u.
    int? startAt = widget.startAtSeconds;
    if (startAt == null) {
      final saved = WatchProgressService.instance.getSync(widget.youtubeId);
      if (saved != null && !saved.completed && saved.positionSeconds > 5) {
        startAt = saved.positionSeconds;
        log('TvEpisode: resume from ${saved.positionSeconds}s');
      }
    }

    // logLevel warn — propusta libmpv internal warnings (TLS, demuxer, codec
    // errors) u `stream.log` da debug build moze vidjeti zasto video ne kreće.
    final player = Player(
      configuration: const PlayerConfiguration(
        logLevel: MPVLogLevel.warn,
      ),
    );
    final controller = VideoController(player);
    _playbackAnalytics = PlaybackAnalytics(
      playingStream: player.stream.playing,
      positionStream: player.stream.position,
      videoId: widget.youtubeId,
      surface: 'tv',
      durationSeconds: _data?.info.duration ?? 0,
    );

    // Subscribe na error/log streamove PRIJE open-a — open async vec moze
    // propucnuti error event ako URI nije validan ili TLS handshake padne.
    player.stream.error.listen((e) {
      log('TvEpisode mpv ERROR: $e');
    });
    player.stream.log.listen((e) {
      log('TvEpisode mpv [${e.level}] ${e.prefix}: ${e.text.trim()}');
    });

    // KLJUCNI redoslijed: setState({player, controller}) MORA biti PRIJE
    // `await player.open(...)`. Razlog: Video widget se mounta iz buildera
    // tek kad je `_controller != null`. Mpv-u treba native surface za
    // dekoder — open() na surface=NULL daje "Both surface and native_window
    // are NULL" za hardware codec-e, i na nekim Android backendovima open()
    // visi na sljedecem otvaranju (zato je drugi load zapinjao na "Priprema…").
    // Mount-a se Video widget najprije, surface se attacha, pa open() radi.
    if (!mounted) {
      await player.dispose();
      return;
    }
    setState(() {
      _player = player;
      _controller = controller;
    });
    // Cekamo jedan frame da Video widget bude u tree-u i texture surface
    // bude attached prije nego se zovne open().
    await WidgetsBinding.instance.endOfFrame;

    // AV1 fallback: EON SDSTB02 (Amlogic, Android 11) reportira AV1
    // mediacodec ali stvarno ga ne dekodira — "Unsupported or unknown
    // profile". Svi video.mp4 na CDN-u su AV1 Main @ 640×360 (libaom).
    // Forsiramo software decode (`hwdec=no`) — pri 640×360 bitrate-u
    // CPU-decode je trivijalan i za stare Amlogic SoC-ove. `cache=no`
    // suprimira "Failed to create file cache" warning (Android sandbox).
    final platform = player.platform;
    if (platform != null) {
      try {
        await (platform as dynamic).setProperty('hwdec', 'no');
        await (platform as dynamic).setProperty('cache', 'no');
        log('TvEpisode: mpv hwdec=no, cache=no');
      } catch (e) {
        log('TvEpisode: setProperty failed (web?): $e');
      }
    }

    log('TvEpisode: opening ${data.videoUri}');
    _loadStartedAt = DateTime.now();
    // Otvori + pouzdano resume-seek (čeka duration prije seeka — inače libmpv
    // odbaci seek prije prvog frame-a pa video kreće od 0).
    await openAndResume(
      player,
      uri: data.videoUri,
      startAtSeconds: startAt,
    );
    log('TvEpisode: open() returned');

    _positionSub = player.stream.position.listen((pos) {
      if (!mounted) return;
      setState(() {
        _position = pos;
        if (!_firstFrame && _playing && !_buffering) _firstFrame = true;
      });
      // Update active chapter + auto-scroll na novu poziciju.
      final d = _data;
      if (d != null) _updateActiveChapter(_flatChapters(d.outline));
    });
    _durationSub = player.stream.duration.listen((dur) {
      if (!mounted) return;
      setState(() => _duration = dur);
      log('TvEpisode: duration ${dur.inSeconds}s');
    });
    _bufferSub = player.stream.buffer.listen((buf) {
      if (!mounted) return;
      setState(() => _buffer = buf);
    });
    _playingSub = player.stream.playing.listen((p) {
      if (!mounted) return;
      log('TvEpisode: playing=$p');
      setState(() {
        _playing = p;
        if (p && !_buffering) _firstFrame = true;
      });
    });
    _bufferingSub = player.stream.buffering.listen((b) {
      if (!mounted) return;
      log('TvEpisode: buffering=$b buffer=${_buffer.inSeconds}s pos=${_position.inSeconds}s');
      setState(() {
        _buffering = b;
        if (!b && _playing) _firstFrame = true;
      });
    });

    if (!mounted) return;
    _playerFocus.requestFocus();
    _scheduleOverlayHide();
    _startSaveTimer();
    _startPollTimer();
  }

  /// Polira live PlayerState dok video ne pocne renderirati frameove + tick
  /// za time-based progress fallback. Vidi komentare uz `_pollTimer` i
  /// `_timeFallbackTargetMs` zasto je ovo potrebno.
  void _startPollTimer() {
    _pollTimer?.cancel();
    int tickCount = 0;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final p = _player;
      if (p == null || !mounted) return;
      final s = p.state;
      tickCount++;
      // setState svaki tick — UI prsten cita _buffer/_position i time-based
      // progress se rebuilda iz `_loadStartedAt`. Drzimo setState i kad
      // nista nije promijenjeno jer time fallback raste s vremenom.
      setState(() {
        _buffer = s.buffer;
        _position = s.position;
        _buffering = s.buffering;
        _playing = s.playing;
        if (s.playing && !s.buffering) _firstFrame = true;
      });
      // Active chapter update i kroz poll (jer pre-firstFrame `stream.position`
      // ne emitira na svim backendovima).
      final d = _data;
      if (d != null) _updateActiveChapter(_flatChapters(d.outline));
      // Log svake sekunde (5 tickova × 200ms) da logcat ima trag bez spama.
      if (!_firstFrame && tickCount % 5 == 0) {
        log('TvEpisode poll #$tickCount: buffer=${s.buffer.inMilliseconds}ms '
            'pos=${s.position.inMilliseconds}ms '
            'buffering=${s.buffering} playing=${s.playing}');
      }
      if (_firstFrame) {
        _pollTimer?.cancel();
        _pollTimer = null;
        log('TvEpisode: polling stopped — first frame rendered '
            'after ${tickCount * 200}ms');
      }
    });
  }

  void _scheduleOverlayHide() {
    _overlayHideTimer?.cancel();
    if (!_showOverlay) setState(() => _showOverlay = true);
    _overlayHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showOverlay = false);
    });
  }

  void _startSaveTimer() {
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _save());
  }

  void _save() {
    final data = _data;
    if (data == null || _position.inSeconds < 5) return;
    WatchProgressService.instance.scheduleSave(
      episodeId: data.youtubeId,
      positionSeconds: _position.inSeconds,
      durationSeconds: _duration.inSeconds > 0
          ? _duration.inSeconds
          : data.info.duration,
      channelId: data.info.channelId,
      episodeTitle: data.displayTitle,
      episodeThumbnailUrl: CdnConfig.thumbnailUrl(data.youtubeId),
    );
  }

  @override
  void dispose() {
    _overlayHideTimer?.cancel();
    _saveTimer?.cancel();
    _pollTimer?.cancel();
    _save();
    WatchProgressService.instance.flush();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferSub?.cancel();
    _playingSub?.cancel();
    _bufferingSub?.cancel();
    _playbackAnalytics?.dispose();
    _player?.dispose();
    _playerFocus.dispose();
    _fullscreenFocus.dispose();
    _readerFocus.dispose();
    _chaptersScroll.dispose();
    super.dispose();
  }

  /// Pronalazi index aktivnog chaptera za trenutnu poziciju + scroll-uje
  /// chapter list tako da je aktivni vidljiv u sredini viewport-a. Pozvano
  /// iz _onPositionChanged (svaki position update tijekom playback-a).
  void _updateActiveChapter(List<OutlineChapter> chapters) {
    if (chapters.isEmpty) return;
    final posSec = _position.inSeconds;
    int idx = -1;
    for (int i = 0; i < chapters.length; i++) {
      if (posSec >= chapters[i].totalSeconds) {
        idx = i;
      } else {
        break;
      }
    }
    if (idx == _activeChapterIndex) return;
    _activeChapterIndex = idx;
    if (idx < 0) return;
    // ensureVisible se moze pozvati kad widget jos nije mounted u tree-u
    // (npr. tijekom inicijalnog loada). GlobalKey.currentContext == null
    // tada — samo skipnemo, sljedeci position update ce uhvatiti.
    final key = _chapterKeys[idx];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.3,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Player commands
  // ---------------------------------------------------------------------------

  Future<void> _togglePlay() async {
    final p = _player;
    if (p == null) return;
    if (p.state.playing) {
      await p.pause();
    } else {
      await p.play();
    }
    _scheduleOverlayHide();
  }

  void _toggleFullscreen() {
    setState(() => _fullscreen = !_fullscreen);
    _scheduleOverlayHide();
    // Vrati fokus na player kad mijenjamo fullscreen — chapter list je
    // unmounted u fullscreen modu pa bi izgubili fokus inace.
    _playerFocus.requestFocus();
    log('TvEpisode: fullscreen=$_fullscreen');
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      // PopScope: BACK gumb ili swipe → home, nikad nazad u prazno (TvHome je
      // prvi screen u stack-u, ali u edge case-u deep-link load-a ovo cuva).
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop || !mounted) return;
          // BACK u fullscreen-u izlazi iz fullscreen-a, ne na home.
          if (_fullscreen) {
            setState(() => _fullscreen = false);
            _playerFocus.requestFocus();
            return;
          }
          // Popa stog kad ga ima — epizoda otvorena S KANALA vraća na kanal,
          // ne na home. Prije 6.9.2026. je uvijek skakalo na home.
          backUp(context);
        },
        child: SafeArea(
          // Web/Chrome dev: arrow keys ne mapiraju u DirectionalFocusIntent
          // bez ovoga. Native Android TV salje DPAD_* keyeve koje WidgetsApp
          // sam hendla, pa je ovo harmless redundancy ali bitno za FORCE_TV
          // testing na Mac/Chrome.
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
            child: _buildBody(theme, l),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, AppLocalizations l) {
    if (_error != null) return _buildError(theme, l);
    final data = _data;
    if (data == null) return _buildLoading(theme, l);

    final chapters = _flatChapters(data.outline);

    // Fullscreen mode: video popunjava cijeli SafeArea, sve ostalo skriveno.
    if (_fullscreen) {
      return _buildHero(theme, l, data, double.infinity,
          hasChaptersBeside: false);
    }

    // Fixed-frame layout (YouTube/Netflix TV konvencija): player se nikad ne
    // scrolla off-screen. Toolbar pinned top, meta footer pinned bottom, a
    // sredina (player + chapter rail) popunjava Expanded. Chapter ListView
    // scrolla SAMO interno — `Scrollable.ensureVisible` u
    // `_updateActiveChapter` nema vise outer scrollable ancestor pa ne
    // pomice cijeli screen kad aktivni chapter dođe izvan viewport-a.
    final hasChapters = chapters.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Pinned top: toolbar s "Čitaj" i Fullscreen gumbima. Mora ziviti
        // izvan player-ovog Focus subtree-a (vidi `_buildFullscreenButton`)
        // — inace OK na gumb prvo okine action, a onda key event bubbla u
        // player-ov `onKeyEvent` koji okine `_togglePlay`, pa video pauzira.
        Padding(
          padding: const EdgeInsets.fromLTRB(48, 8, 48, 4),
          child: Row(
            children: [
              const Spacer(),
              if (data.hasAiContent) ...[
                _buildReaderButton(theme, l),
                const SizedBox(width: 12),
              ],
              _buildFullscreenButton(theme, l),
            ],
          ),
        ),
        // Sredina: player + chapter rail side-by-side. Expanded uzima sve
        // izmedju toolbar-a i footera; Row crossAxisAlignment.stretch daje
        // oba child-a punu visinu (bez IntrinsicHeight jer parent je bounded).
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: hasChapters ? 65 : 100,
                  child: _buildHero(
                    theme,
                    l,
                    data,
                    double.infinity,
                    hasChaptersBeside: hasChapters,
                  ),
                ),
                if (hasChapters) ...[
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 35,
                    child: _buildChaptersVertical(theme, l, chapters),
                  ),
                ],
              ],
            ),
          ),
        ),
        // Pinned bottom: kompaktan meta footer. Title + channel/duration u
        // jednom retku, abstract clamped na 2 retka (bilo 4) jer 10-foot
        // viewer ne cita duge paragraphe — kratak description je dovoljan
        // dok je player vidljiv. Fix-an layout = nema scroll-jump-a.
        const SizedBox(height: 10),
        _buildTitle(theme, data),
        const SizedBox(height: 6),
        _buildAbstract(theme, data),
        const SizedBox(height: 12),
      ],
    );
  }

  /// "Čitaj" gumb — vodi u TvEpisodeReaderScreen. Cuva trenutnu poziciju
  /// kroz query param `?t=` da reader starta na istoj sekciji koju korisnik
  /// trenutno gleda. Vidljiv samo kad epizoda ima AI sadržaj.
  Widget _buildReaderButton(ThemeData theme, AppLocalizations l) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _playerFocus.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TvFocusable(
        focusNode: _readerFocus,
        style: TvFocusStyle.subtleButton,
        onActivate: () {
          final sec = _position.inSeconds;
          final target = sec > 5
              ? '/v/${widget.youtubeId}/read?t=$sec'
              : '/v/${widget.youtubeId}/read';
          drillDown(context, target);
        },
        builder: (context, focused) => AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: focused
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHigh,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_stories_rounded,
                color: theme.colorScheme.onSurface,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                l.tvRead,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Fullscreen toggle gumb — zivi u toolbar-u IZNAD playera (izvan
  /// player-ovog Focus subtree-a). D-pad UP s playera fokusira ovaj gumb;
  /// DOWN s gumba vraca focus na player. OK okine samo `_toggleFullscreen`
  /// (vise se ne propagira u player jer `_handlePlayerKey` ima
  /// `hasPrimaryFocus` guard, a i strukturno gumb vise nije unutar player
  /// Focus-a).
  Widget _buildFullscreenButton(ThemeData theme, AppLocalizations l) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _playerFocus.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TvFocusable(
        focusNode: _fullscreenFocus,
        style: TvFocusStyle.subtleButton,
        onActivate: _toggleFullscreen,
        builder: (context, focused) => AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: focused
              ? theme.colorScheme.tertiaryContainer
              : theme.colorScheme.surfaceContainerHigh,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _fullscreen
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                color: theme.colorScheme.onSurface,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                _fullscreen ? l.tvExitFullscreen : l.tvFullscreen,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ],
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
          const SizedBox(height: 20),
          Text(l.tvLoadingEpisode, style: theme.textTheme.titleMedium),
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
    final notFound = _error is VideoNotFoundException;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              notFound ? Icons.video_file_outlined : Icons.error_outline,
              size: 64,
              color: notFound ? theme.colorScheme.onSurfaceVariant : Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              notFound
                  ? l.tvEpisodeNotFound(widget.youtubeId)
                  : l.tvLoadError('$_error'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            TvFocusable(
              autofocus: true,
              style: TvFocusStyle.primaryButton,
              onActivate: () => context.go('/'),
              builder: (_, focused) => Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  l.commonGoHome,
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

  // ---------------------------------------------------------------------------
  // Hero player
  // ---------------------------------------------------------------------------

  Widget _buildHero(
    ThemeData theme,
    AppLocalizations l,
    EpisodeData data,
    double height, {
    bool hasChaptersBeside = false,
  }) {
    final controller = _controller;
    final ready = controller != null;
    final progress = _duration.inSeconds > 0
        ? (_position.inSeconds / _duration.inSeconds).clamp(0.0, 1.0)
        : 0.0;

    // Backdrop / loading layer: thumbnail s CDN-a se prikazuje dok prvi frame
    // ne dođe (TV preko Tailscale/3G zna trebati 5-10s za buffer prvog frame-a).
    // Bez ovoga korisnik vidi crni pravokutnik i misli da je app pukao.
    final showBackdrop = !ready || !_firstFrame;
    final showBufferingSpinner = !_firstFrame || _buffering;

    // U fullscreen modu pad-ovi i radius su 0 (video popunjava cijeli ekran).
    // U side-by-side layout-u, _buildBody vec daje vanjski padding, pa
    // ovdje samo radimo bez dodatnog horizontalnog padding-a.
    final outerPadding = _fullscreen
        ? EdgeInsets.zero
        : (hasChaptersBeside
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 48));
    final radius = _fullscreen ? 0.0 : 16.0;

    return Padding(
      padding: outerPadding,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          height: height,
          child: Focus(
            focusNode: _playerFocus,
            autofocus: true,
            onKeyEvent: _handlePlayerKey,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Crni fallback ispod thumbnaila (za slucaj da thumb ne ucita).
                Container(color: Colors.black),

                // Thumbnail backdrop — fade-outa kad prvi frame dođe.
                AnimatedOpacity(
                  opacity: showBackdrop ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 400),
                  child: CachedThumbnail(
                    url: CdnConfig.thumbnailUrl(data.youtubeId),
                  ),
                ),

                // Video — uvijek mounted čim controller postoji, samo je
                // ispod thumb-a dok nije ready. Tako media_kit decoder
                // pocne pripremati frameove sto ranije.
                if (ready)
                  Video(
                    controller: controller,
                    controls: NoVideoControls,
                    fit: BoxFit.contain,
                  ),

                // Loading veil + interaktivni 0-100% prsten. Tri faze:
                //   1. !ready — player jos nije instanciran. Indeterminate.
                //   2. ready && !_firstFrame — buffering inicijalne sekunde.
                //      Determinate, progress = buffer/5s.
                //   3. _firstFrame && _buffering — mid-playback re-buffer.
                //      Determinate, progress = (buffer-position)/5s.
                if (showBufferingSpinner)
                  Container(
                    color: Colors.black.withValues(alpha: 0.55),
                    alignment: Alignment.center,
                    child: _buildBufferRing(theme, l, ready),
                  ),

                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      _playerFocus.requestFocus();
                      _togglePlay();
                    },
                  ),
                ),

                // Transport controls overlay — skrivamo dok prvi frame ne
                // dođe da se ne mijesa s buffer prstenom (oboje cijelo na
                // gornjoj polovici hero-a, izgleda kao bug).
                AnimatedOpacity(
                  opacity: (_showOverlay && _firstFrame) ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: IgnorePointer(
                    ignoring: !(_showOverlay && _firstFrame),
                    child: _buildOverlay(theme, l, progress),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Interaktivni 0-100% buffer ring s tekst-postotkom u sredini.
  /// Faze i target:
  ///   - Pre-ready (player jos nije instanciran): indeterminate
  ///   - Initial buffering: ciljano `_bufferTargetSec` sekundi unaprijed
  ///   - Mid-playback re-buffer: cilj isti, ali baseline je trenutna pozicija
  Widget _buildBufferRing(ThemeData theme, AppLocalizations l, bool ready) {
    final indeterminate = !ready;
    double? value;
    String label;
    String hint;

    if (indeterminate) {
      value = null;
      // Prazan label tijekom indeterminate spinnera — "Priprema…" je sirok
      // i prelazi 110px container pa overflowa preko prstena. Hint tekst
      // ispod prstena vec govori sto se dogada.
      label = '';
      hint = l.tvBufferStartingEngine;
    } else {
      // Real buffer signal (libmpv): koliko sekundi unaprijed je decoded.
      final ahead = (_buffer.inMilliseconds - _position.inMilliseconds)
          .clamp(0, 1 << 30);
      final realRatio =
          (ahead / (_bufferTargetSec * 1000)).clamp(0.0, 1.0);

      // Time-based fallback: ako libmpv ne emitira buffer updateove (cesto
      // na Android backendu dok download ne dosegne prebuffer threshold),
      // koristimo elapsed-since-open kao proxy. 500ms head start da prsten
      // ne starta na 0% dok je network handshake u tijeku.
      double timeRatio = 0.0;
      final started = _loadStartedAt;
      if (started != null) {
        final elapsed = DateTime.now().difference(started).inMilliseconds - 500;
        timeRatio = (elapsed / _timeFallbackTargetMs).clamp(0.0, 1.0);
      }

      // Uzmi vecu vrijednost — bilo koji signal koji se mice gura prsten
      // naprijed. Time progress je floor, real progress je override kad
      // libmpv pocne reportati.
      final ratio = realRatio > timeRatio ? realRatio : timeRatio;
      value = ratio;
      label = '${(ratio * 100).round()}%';
      hint = !_firstFrame ? l.tvBufferLoadingVideo : l.tvBufferFilling;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 110,
          height: 110,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Background trag — uvijek full krug u tlumljenoj boji.
              SizedBox(
                width: 110,
                height: 110,
                child: CircularProgressIndicator(
                  value: 1.0,
                  strokeWidth: 7,
                  color: Colors.white.withValues(alpha: 0.15),
                ),
              ),
              // Foreground — actual progress (animated by Flutter automatically
              // jer mijenjamo `value` na rebuild-u).
              SizedBox(
                width: 110,
                height: 110,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: value ?? 0),
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  builder: (context, animated, _) {
                    return CircularProgressIndicator(
                      value: indeterminate ? null : animated,
                      strokeWidth: 7,
                      color: theme.colorScheme.tertiary,
                      strokeCap: StrokeCap.round,
                    );
                  },
                ),
              ),
              // Center label — postotak ili "Priprema…".
              Text(
                label,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature('tnum')],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          hint,
          style: theme.textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          Uri.parse(CdnConfig.base).host,
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.55),
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  KeyEventResult _handlePlayerKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // KRITICNI GUARD: Flutter zove `onKeyEvent` na nodeu cak i kad descendant
    // ima primary focus. Bez ovoga, OK na bilo kojem child gumbu (npr.
    // Fullscreen) prvo aktivira gumb a onda OPET pada kroz ovaj handler i
    // okida `_togglePlay`, pa video instant pauzira. Reagiraj samo kad je
    // sam player ima primary focus.
    if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
    final k = event.logicalKey;
    // D-pad navigacija (◀▲▶▼) i seekanje su NAMJERNO ne-hendlani na playeru.
    // Ranija verzija je mapirala LEFT/RIGHT na seek ±10s — bilo je
    // nepredvidljivo (slučajni seek pri pokušaju navigacije do toolbar
    // gumba) i blokiralo prirodan focus traversal. Sada arrow keys pusti
    // u default DirectionalFocusIntent: UP s playera traversira na toolbar
    // (Čitaj / Fullscreen), DOWN/LEFT/RIGHT ostaju na playeru (nema drugih
    // focusable widgeta u tom smjeru — chapter rail je read-only). Ako
    // seek bude trebao, dodat ćemo eksplicitne -10s / +10s gumbe pored
    // Fullscreen-a u toolbar-u. Media keys (FF/rewind/track) su isto skinuti
    // jer su podvarijanta seeka — držimo samo play/pause skup.
    if (k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.mediaPlayPause) {
      _togglePlay();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaPlay) {
      _player?.play();
      _scheduleOverlayHide();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaPause) {
      _player?.pause();
      _scheduleOverlayHide();
      return KeyEventResult.handled;
    }
    // 'F' = toggle fullscreen. Mac/Chrome dev convention.
    if (k == LogicalKeyboardKey.keyF) {
      _toggleFullscreen();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildOverlay(ThemeData theme, AppLocalizations l, double progress) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.5),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withValues(alpha: 0.75),
          ],
          stops: const [0.0, 0.22, 0.55, 1.0],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top row: chip + pause indicator. Fullscreen gumb je premjesten
          // IZVAN player-ove Focus podstabla (vidi `_buildFullscreenButton`
          // u toolbar-u iznad playera) — bez toga OK click na fullscreen je
          // prosao kroz player-ov onKeyEvent i pauzirao video.
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                color: theme.colorScheme.tertiary,
                child: Text(
                  AppBrand.config.appName,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onTertiary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const Spacer(),
              if (!_playing && _player != null)
                Icon(
                  Icons.pause_circle_outline_rounded,
                  color: Colors.white.withValues(alpha: 0.95),
                  size: 28,
                ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Icon(
                _playing ? Icons.play_arrow_rounded : Icons.pause_rounded,
                color: Colors.white,
                size: 36,
              ),
              const SizedBox(width: 12),
              Text(
                _fmt(_position),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontFeatures: const [FontFeature('tnum')],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    color: theme.colorScheme.tertiary,
                    backgroundColor: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _fmt(_duration),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontFeatures: const [FontFeature('tnum')],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TvKeyHint(
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.7),
              letterSpacing: 0.5,
            ),
            entries: [
              TvHintEntry(const ['OK'], l.tvHintPlayPause),
              if (_fullscreen)
                TvHintEntry(const ['BACK', '/', 'F'], l.tvHintExit)
              else
                TvHintEntry(const [Icons.expand_less], l.tvHintRead),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Below-fold meta + chapters
  // ---------------------------------------------------------------------------

  Widget _buildTitle(ThemeData theme, EpisodeData data) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.displayTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            children: [
              Text(
                data.info.channel,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (data.info.duration > 0)
                Text(
                  '•  ${_fmtDurationLabel(Duration(seconds: data.info.duration))}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAbstract(ThemeData theme, EpisodeData data) {
    final abstract = data.summary?.summary.abstractHr;
    if (abstract == null || abstract.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Text(
        abstract,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.4,
        ),
      ),
    );
  }

  /// Vertikalna chapter lista — pratimo player. ScrollController + GlobalKey
  /// per item drive-aju Scrollable.ensureVisible animaciju iz
  /// _updateActiveChapter (pozvano iz position stream + poll).
  Widget _buildChaptersVertical(
      ThemeData theme, AppLocalizations l, List<OutlineChapter> chapters) {
    // Maintain stable GlobalKey-eve za svaki chapter index. Rebuilds ne
    // mijenjaju identity pa ensureVisible animacija nije razbijena.
    for (int i = 0; i < chapters.length; i++) {
      _chapterKeys.putIfAbsent(i, () => GlobalKey(debugLabel: 'chapter-$i'));
    }
    return Container(
      color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.4),
      // Veci horizontalni padding (16 → 20) da focus ring + glow na chapter
      // rowu ima prostor unutar panela; clipBehavior na ListView je Clip.none
      // pa shadow moze cak i lagano otici izvan panela bez odsijecanja.
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Row(
              children: [
                Container(
                    width: 28, height: 3, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l.tvChaptersWithCount(chapters.length).toUpperCase(),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              controller: _chaptersScroll,
              clipBehavior: Clip.none,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: chapters.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                return _ChapterRow(
                  key: _chapterKeys[i],
                  chapter: chapters[i],
                  active: i == _activeChapterIndex,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<OutlineChapter> _flatChapters(PodcastOutline? outline) {
    if (outline == null) return const [];
    final out = <OutlineChapter>[];
    for (final it in outline.iterations) {
      out.addAll(it.chapters);
    }
    return out;
  }
}

// ---------------------------------------------------------------------------
// Chapter card
// ---------------------------------------------------------------------------

/// Vertical chapter kartica za TvEpisodeScreen side-panel — passive
/// indikator napretka (NIJE D-pad target).
///
/// Zašto bez focus-a: u Reader-less verziji TV episode screena, chapter rail
/// je krao D-pad fokus prema desno i blokirao put do "Čitaj" gumba u
/// toolbar-u. Sada se po sekcijama lista samo u Reader modu (`/v/<id>/read`);
/// ovdje su kartice read-only vizualni cue koje se same osvjezavaju kako
/// player napreduje (vidi `_updateActiveChapter`).
///
/// Layout: 2-row kartica — timestamp + icon na vrhu (compact chip),
/// naslov poglavlja ispod kao multi-line tekst do 3 retka.
class _ChapterRow extends StatelessWidget {
  final OutlineChapter chapter;
  final bool active;

  const _ChapterRow({
    super.key,
    required this.chapter,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: active
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.9)
            : theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.55),
        border: Border(
          left: BorderSide(
            color: active
                ? theme.colorScheme.primary
                : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: icon + timestamp (compact header)
          Row(
            children: [
              Icon(
                active
                    ? Icons.play_arrow_rounded
                    : Icons.access_time_rounded,
                size: 16,
                color: active
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                chapter.timestamp,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontFeatures: const [FontFeature('tnum')],
                  color: active
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Row 2: multi-line naslov poglavlja
          Text(
            chapter.topic,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface,
              height: 1.3,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Formatting helpers
// ---------------------------------------------------------------------------

String _fmt(Duration d) {
  if (d <= Duration.zero) return '00:00';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (h > 0) return '$h:$m:$s';
  return '$m:$s';
}

String _fmtDurationLabel(Duration d) {
  if (d.inHours > 0) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return '${h}h ${m}m';
  }
  return '${d.inMinutes}m';
}
