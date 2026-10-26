import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../l10n/app_localizations.dart';
import '../brand/app_brand.dart';
import '../models/episode_reels.dart';
import '../models/person_hub.dart';
import '../models/sponsored_moment.dart';
import '../pinka_sdk/pinka_sdk.dart';
import '../services/background_audio.dart';
import '../services/background_playback.dart';
import '../services/cdn_config.dart';
import '../services/ebook_service.dart';
import '../services/channel_cache.dart';
import '../services/data_service.dart';
import '../services/episode_language.dart';
import '../services/share_links.dart';
import '../services/media_session.dart';
import '../services/notification_art.dart';
import '../services/open_url.dart';
import '../services/playback_intent.dart';
import '../services/playback_speed.dart';
import '../services/player_mute.dart';
import '../services/remote_playback.dart';
import '../services/player_resume.dart';
import '../services/page_meta.dart';
import '../services/seek_undo.dart';
import '../services/analytics/playback_analytics.dart';
import '../services/sponsored_moments_controller.dart';
import '../services/sponsored_moments_service.dart';
import '../services/url_sync.dart';
import '../services/view_mode.dart';
import '../services/watch_progress_service.dart';
import '../widgets/ebook_sheet.dart';
import '../widgets/episode_status_card.dart';
import '../widgets/anonymous_signin_bar.dart';
import '../widgets/audio_poster.dart';
import '../widgets/clip_share_sheet.dart';
import '../widgets/episode_reels.dart';
import '../widgets/episode_video.dart';
import '../widgets/sponsored_moment_widgets.dart';
import '../widgets/subtitle_caption.dart';
import '../widgets/favorite_button.dart';
import '../widgets/language_toggle_chip.dart';
import '../widgets/magisterium_v2_view.dart';
import '../widgets/playback_controls.dart';
import '../widgets/resume_hint_banner.dart';
import '../widgets/speaker_chip.dart';
import '../widgets/view_mode_toggle_button.dart';
import '../widgets/youtube_embed.dart';
import '../router/nav.dart';

/// Pojednostavljeni mobile-first ekran za reprodukciju podcast epizode.
/// Optimiziran za slušanje u autu — 3 taba: Player, Poglavlja, Info.
class EpisodeSimpleScreen extends StatefulWidget {
  final String youtubeId;

  /// True kad URL ima `/en` sufix (npr. `/m/<id>/en`).
  final bool initialLanguageEn;

  /// Eksplicitni start timestamp iz URL-a (`/m/<id>/t/<sec>`). Ima prednost
  /// nad saved watch progress-om. null → resume na zadnju poziciju.
  final int? startAtSeconds;

  const EpisodeSimpleScreen({
    super.key,
    required this.youtubeId,
    this.initialLanguageEn = false,
    this.startAtSeconds,
  });

  @override
  State<EpisodeSimpleScreen> createState() => _EpisodeSimpleScreenState();
}

class _EpisodeSimpleScreenState extends State<EpisodeSimpleScreen> {
  EpisodeData? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Pandan `_EpisodeScreenState.didUpdateWidget` — ključ rute više ne nosi
  /// `startAt` (vidi app_router.dart), pa isti State može preživjeti promjenu
  /// propova. Novi `youtubeId` mora ponovno učitati epizodu.
  @override
  void didUpdateWidget(EpisodeSimpleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.youtubeId != widget.youtubeId) {
      _data = null;
      _error = null;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final data = await EpisodeData.load(youtubeId: widget.youtubeId);
      if (mounted) {
        setState(() => _data = data);
        // Isti format naslova kao worker edge-inject za /v/ i /m/.
        setPageMeta(
          title: data.displayTitle,
          description: data.summary?.summary.abstractHr,
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_data != null) {
      return _SimpleEpisodeContent(
        data: _data!,
        initialLanguageEn: widget.initialLanguageEn,
        startAtSeconds: widget.startAtSeconds,
      );
    }

    if (_error != null) {
      final notFound = _error is VideoNotFoundException;
      final theme = Theme.of(context);
      final l = AppLocalizations.of(context);
      return Scaffold(
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    notFound ? Icons.video_file_outlined : Icons.error_outline,
                    size: 48,
                    color: notFound ? null : Colors.red,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    notFound
                        ? l.episodeNotFound(widget.youtubeId)
                        : l.episodeLoadError('$_error'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => context.go('/'),
                    icon: const Icon(Icons.arrow_back),
                    label: Text(l.commonBack),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Loading
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}

// ---------------------------------------------------------------------------
// Content - 3-tab layout
// ---------------------------------------------------------------------------

class _SimpleEpisodeContent extends StatefulWidget {
  final EpisodeData data;
  final bool initialLanguageEn;
  final int? startAtSeconds;

  const _SimpleEpisodeContent({
    required this.data,
    this.initialLanguageEn = false,
    this.startAtSeconds,
  });

  @override
  State<_SimpleEpisodeContent> createState() => _SimpleEpisodeContentState();
}

class _SimpleEpisodeContentState extends State<_SimpleEpisodeContent>
    with WidgetsBindingObserver {
  int _tabIndex = 0;
  EpisodeLanguage _language = EpisodeLanguage.hr;

  // Video
  Player? _player;
  VideoController? _videoController;
  bool _videoReady = false;
  StreamSubscription<Duration>? _positionSub;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;

  /// „Želi li korisnik da ovo svira?" — čuva izričitu Pauzu od framework
  /// pauza (odlazak u pozadinu). Vidi services/playback_intent.dart.
  PlaybackIntent? _intent;

  /// „Vrati me gdje sam bio" nakon ručnog skoka po timelineu. Programske
  /// skokove (resume pri otvaranju, tap na poglavlje — odluka D2) najavljujemo
  /// kroz `suppress()`. Vidi services/seek_undo.dart.
  SeekUndo? _seekUndo;
  PlaybackAnalytics? _playbackAnalytics;

  /// In-app YouTube embed mode — native player pauziran, iframe preuzima.
  bool _ytMode = false;

  /// Cover-art za audio-only epizode (CORS-safe channel avatar square).
  /// Razrješava se u [_initVideo] iz channel cachea.
  String? _audioArtUrl;

  /// URL sync — zadnja sekunda za koju smo update-ali address bar.
  int _lastUrlSyncedSec = -1;

  /// Inline resume hint — vidi episode_screen.dart za razlog (SnackBar lingera).
  int? _resumeHintSeconds;
  Timer? _resumeHintTimer;
  static const _resumeHintDuration = Duration(seconds: 4);

  /// Flat lista svih poglavlja iz outline-a za brz pristup.
  late final List<({String timestamp, String topic, int totalSeconds})>
  _chapters;

  /// EPUB e-knjiga — MJERI se HEAD probe-om (vidi [EbookService]), izvan
  /// kritičnog puta učitavanja epizode.
  EbookAvailability _ebook = EbookAvailability.none;

  /// PLAĆENI sponzorski trenuci — traka „Sponzorirano · {brand}" u
  /// [_PlayerTab]. Na audio-only epizodi je to JEDINO mjesto gdje se vidi
  /// tko je platio (oznake preko slike nema).
  SponsoredMomentsController? _sponsored;

  /// Istaknuti trenuci (`reels.json`) — trake na seek baru i popis u
  /// [_PlayerTab]. Null dok ne stignu i zauvijek kad ih nema.
  EpisodeReels? _reels;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chapters = _buildChapters();
    EbookService.probe(widget.data.youtubeId).then((found) {
      if (!mounted || !found.any) return;
      setState(() => _ebook = found);
    });
    SponsoredMomentsService.instance.loadLive(widget.data.youtubeId).then((
      found,
    ) {
      if (!mounted || found == null) return;
      setState(() => _sponsored = SponsoredMomentsController(found));
    });
    DataService(youtubeId: widget.data.youtubeId).loadReels().then((found) {
      if (!mounted || found == null) return;
      setState(() => _reels = found);
    });

    if (widget.initialLanguageEn && widget.data.hasTranslationEn) {
      _language = EpisodeLanguage.en;
    } else {
      loadPreferredLanguage().then((saved) {
        if (!mounted) return;
        if (saved == EpisodeLanguage.en && widget.data.hasTranslationEn) {
          setState(() => _language = EpisodeLanguage.en);
          _syncLanguageUrl(EpisodeLanguage.en);
        }
      });
    }
    // Brzina je globalna postavka (D1) — gumb je mijenja na singletonu, ekran
    // je odavde prenosi na svoj Player. Jedan smjer, bez dvostrukog puta.
    PlaybackSpeed.instance.addListener(_applyPlaybackRate);
    _initVideo();
  }

  /// Nova ciljna sekunda iz URL-a se primjenjuje na ŽIVOM playeru — ključ rute
  /// od 6.9.2026. ne nosi `startAt`, pa promjena timestampa više ne remounta
  /// ekran. Vidi isti komentar u episode_screen.dart.
  @override
  void didUpdateWidget(_SimpleEpisodeContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final startAt = widget.startAtSeconds;
    if (startAt != oldWidget.startAtSeconds && startAt != null) {
      final player = _player;
      if (player != null) {
        _seekUndo?.suppress();
        player.seek(Duration(seconds: startAt));
      }
    }
  }

  /// Primijeni trenutnu globalnu brzinu na player + osvježi media sesiju.
  void _applyPlaybackRate() {
    final player = _player;
    if (player == null) return;
    final rate = PlaybackSpeed.instance.rate;
    player.setRate(rate);
    // Native media sesiju ažurira `background_audio.dart` preko
    // `player.stream.rate`; web nema takav stream pa gura odmah.
    MediaSession.setPositionState(
      duration: Duration(seconds: widget.data.info.duration),
      position: player.state.position,
      playbackRate: rate,
    );
  }

  void _onLanguageChanged(EpisodeLanguage lang) {
    if (lang == _language) return;
    setState(() => _language = lang);
    savePreferredLanguage(lang);
    _syncLanguageUrl(lang);
  }

  void _syncLanguageUrl(EpisodeLanguage lang) {
    final sec = _position.inSeconds;
    replaceLanguage(
      '/m/${widget.data.youtubeId}',
      isEn: lang == EpisodeLanguage.en,
      seconds: sec,
    );
    _lastUrlSyncedSec = sec;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PlaybackSpeed.instance.removeListener(_applyPlaybackRate);
    _positionSub?.cancel();
    _resumeHintTimer?.cancel();
    WatchProgressService.instance.flush();
    BackgroundAudio.instance.detach();
    MediaSession.clear();
    _intent?.dispose();
    _seekUndo?.dispose();
    _playbackAnalytics?.dispose();
    _sponsored?.dispose();
    final player = _player;
    if (player != null) {
      PlayerMute.instance.detach(player);
      RemotePlayback.instance.detach(player);
      player.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden) {
      return;
    }
    final intent = _intent;
    // Prozor tolerancije otvaramo PRIJE ikakvog čekanja: framework pauza
    // (media_kitov SurfaceView teardown na Androidu, browserov hidden tab)
    // ne smije proći kao korisnikova.
    intent?.suppress();
    // Korisnik je sam pauzirao — odlazak u pozadinu to ne poništava.
    if (intent != null && !intent.wantsPlayback) return;
    if (!BackgroundPlayback.instance.enabled) {
      _player?.pause();
      return;
    }
    // Web: ne force-playamo — browser sam drži audio (Media Session).
    if (kIsWeb) return;
    // Android kill-a SurfaceView kad Video widget (u _PlayerTab) ode u bg
    // pa media_kit auto-pauzira. Force-play kratko nakon tranzicije —
    // foreground service iz audio_service-a drzi process zivim.
    Future<void>.delayed(const Duration(milliseconds: 150), () {
      _player?.play();
    });
  }

  List<({String timestamp, String topic, int totalSeconds})> _buildChapters() {
    final outline = widget.data.outline;
    if (outline == null) return const [];
    final list = <({String timestamp, String topic, int totalSeconds})>[];
    for (final iter in outline.iterations) {
      for (final ch in iter.chapters) {
        list.add((
          timestamp: ch.timestamp,
          topic: ch.topic,
          totalSeconds: ch.totalSeconds,
        ));
      }
    }
    list.sort((a, b) => a.totalSeconds.compareTo(b.totalSeconds));
    return list;
  }

  Future<void> _initVideo() async {
    // Nema playabilne medije (sva 3 probe-a 404) — ne otvaraj player; _PlayerTab
    // prikazuje jasnu poruku umjesto beskonačnog spinnera.
    if (!widget.data.hasMedia || widget.data.videoUri.isEmpty) {
      return;
    }
    // URL explicit timestamp (`/m/<id>/t/<sec>`) ima prednost nad saved
    // progress-om. Inače resume na zadnju poziciju ako > 5s i nije completed
    // (rewatch konvencija — kreni od početka).
    int? startAt = widget.startAtSeconds;
    bool resumedFromSaved = false;
    if (startAt == null) {
      final saved = WatchProgressService.instance.getSync(
        widget.data.youtubeId,
      );
      if (saved != null && !saved.completed && saved.positionSeconds > 5) {
        startAt = saved.positionSeconds;
        resumedFromSaved = true;
      }
    }

    try {
      final player = Player();
      final controller = VideoController(player);

      // VAZNO: subscribe-i moraju biti registrirani PRIJE open/play.
      // media_kit streamovi su broadcast (ne replay) — ako se prvi
      // playing=true event ispali prije nego sto smo se pretplatili (npr.
      // pri brzoj internoj navigaciji s vec keshanim Player resursima),
      // izgubimo event i Play/Pause gumb ostaje u krivom stanju.
      _positionSub = player.stream.position.listen((pos) {
        if (mounted) setState(() => _position = pos);
        _sponsored?.onPosition(pos);
        // URL sync: adresna traka prati player na 1Hz (sec granularity).
        // Stream fira ~5×/s — preskačemo update kad se sec nije promijenio.
        final sec = pos.inSeconds;
        if (sec != _lastUrlSyncedSec) {
          _lastUrlSyncedSec = sec;
          replaceTimestamp(
            '/m/${widget.data.youtubeId}',
            sec,
            langSuffix: _language == EpisodeLanguage.en ? '/en' : null,
          );
          // Media Session position update — drži lock screen scrub bar u
          // syncu. Throttled na sec granularnost (isti gate kao URL sync).
          // playbackRate: bez stvarne brzine scrub bar na lock screenu
          // ekstrapolira na 1,0× i vidno drifta pri 1,5×.
          MediaSession.setPositionState(
            duration: Duration(seconds: widget.data.info.duration),
            position: pos,
            playbackRate: PlaybackSpeed.instance.rate,
          );
          // CDN URL (ne i.ytimg.com) da home rail "Nastavi slusati" moze
          // renderati thumbnail bez CORS bloka.
          WatchProgressService.instance.scheduleSave(
            episodeId: widget.data.youtubeId,
            positionSeconds: sec,
            durationSeconds: widget.data.info.duration,
            channelId: widget.data.info.channelId,
            episodeTitle: widget.data.displayTitle,
            episodeThumbnailUrl: CdnConfig.thumbnailUrl(widget.data.youtubeId),
          );
        }
      });

      player.stream.duration.listen((dur) {
        if (mounted) setState(() => _duration = dur);
      });

      player.stream.playing.listen((playing) {
        // mounted guard i za MediaSession: player.dispose() emitira zadnji
        // `false` nakon što smo već pozvali MediaSession.clear().
        if (!mounted) return;
        setState(() => _isPlaying = playing);
        // Web lock screen / Now Playing stanje. No-op na nativeu.
        MediaSession.setPlaybackState(playing);
      });

      // Namjera reprodukcije — pretplaćuje se na isti `playing` stream (jedini
      // izvor koji hvata i media_kitove interne kontrole: playAndPauseOnTap,
      // tipkovničke kratice, Material gumbe).
      _intent = PlaybackIntent(
        playingStream: player.stream.playing,
        isPlayingNow: () => player.state.playing,
      );

      // Detekcija skoka sluša isti položajni stream — i ona mora biti gore,
      // prije open/seeka.
      _seekUndo = SeekUndo(positionStream: player.stream.position);
      _playbackAnalytics = PlaybackAnalytics(
        playingStream: player.stream.playing,
        positionStream: player.stream.position,
        videoId: widget.data.youtubeId,
        surface: 'm',
        durationSeconds: widget.data.info.duration,
      );
      // Resume-seek pri otvaranju NIJE korisnikov skok. Prozor je namjerno
      // dug: `openAndResume` čeka duration (do 5 s) prije nego seekne, pa bi
      // standardnih 1,2 s isteklo prije samog skoka.
      _seekUndo!.suppress(window: const Duration(seconds: 8));

      // Otvori + pouzdano resume-seek (čeka duration prije seeka — inače libmpv
      // na iOS odbaci seek pa video kreće od 0). Web fallback na muted autoplay
      // je u helperu.
      await openAndResume(
        player,
        uri: widget.data.videoUri,
        startAtSeconds: startAt,
      );

      if (mounted) {
        // Otvaranje je gotovo → skrati prozor natrag na normalnu duljinu.
        _seekUndo?.suppress();
        // Zapamćena brzina (D1: globalna za uređaj) vrijedi od prve sekunde.
        await player.setRate(PlaybackSpeed.instance.rate);
      }

      if (mounted) {
        setState(() {
          _player = player;
          _videoController = controller;
          _videoReady = true;
          // Safety snapshot — ako je playing event procurio kroz timing
          // gap (rijetko, ali moguce), sinkroniziraj iz player.state.
          _isPlaying = player.state.playing;
          _position = player.state.position;
          _duration = player.state.duration;
        });

        if (resumedFromSaved && startAt != null) {
          _showResumeHint(startAt);
        }

        // Background audio session — vidi episode_screen.dart za strategiju artworka.
        await channelCache.loadIndex();
        final channelName = widget.data.info.channel;
        final squareUrl = channelCache.avatarSquareForChannelName(channelName);
        if (mounted && squareUrl != null) {
          setState(() => _audioArtUrl = squareUrl);
        }
        final thumbUrl = widget.data.info.thumbnail;
        final composed = squareUrl != null
            ? await NotificationArt.composeForAndroid(
                videoId: widget.data.youtubeId,
                avatarSquareUrl: squareUrl,
                thumbnail16x9Url: thumbUrl,
              )
            : null;
        BackgroundAudio.instance.attach(
          player: player,
          title: widget.data.displayTitle,
          artist: channelName,
          artUri: composed ?? squareUrl ?? thumbUrl,
          duration: Duration(seconds: widget.data.info.duration),
        );

        // Media Session API — web ekvivalent background audija: signal OS-u
        // da je tab "playing media" pa zvuk nastavlja kad se zaslon zaključa
        // ili korisnik prijeđe na drugi tab, uz lock-screen kontrole. No-op
        // na nativeu (tamo isto radi audio_service, gore).
        // Artwork: 1:1 avatar kanala (Now Playing je kvadratan), fallback
        // thumbnail. Android-kompozicija (`composed`) je samo za notifikaciju.
        MediaSession.attachMetadata(
          title: widget.data.displayTitle,
          artist: channelName,
          artUrl: squareUrl ?? thumbUrl,
        );
        MediaSession.setActionHandlers(
          onPlay: () => _player?.play(),
          onPause: () => _player?.pause(),
          onSeekTo: (pos) => _player?.seek(pos),
          onSeekBackward: (off) {
            final cur = _player?.state.position ?? Duration.zero;
            _player?.seek(cur - off);
          },
          onSeekForward: (off) {
            final cur = _player?.state.position ?? Duration.zero;
            _player?.seek(cur + off);
          },
        );
      }
    } catch (e) {
      debugPrint('SimpleEpisode: video init failed — $e');
    }
  }

  void _showResumeHint(int positionSeconds) {
    if (!mounted) return;
    _resumeHintTimer?.cancel();
    setState(() => _resumeHintSeconds = positionSeconds);
    _resumeHintTimer = Timer(_resumeHintDuration, () {
      if (mounted) setState(() => _resumeHintSeconds = null);
    });
  }

  Future<void> _seekTo(int seconds) async {
    // Tap na poglavlje je namjerna navigacija — Undo se NE nudi (odluka D2).
    _seekUndo?.suppress(window: const Duration(seconds: 2));
    await _player?.seek(Duration(seconds: seconds));
    if (!(_player?.state.playing ?? false)) {
      await _player?.play();
    }
    // Switch to player tab after seeking
    if (_tabIndex != 0) {
      setState(() => _tabIndex = 0);
    }
  }

  /// „Pogledaj" na renderiranom trenutku — isti tok kao na detaljnom ekranu:
  /// epizoda stoji dok isječak svira, a „Pogledaj u cijeloj epizodi" skoči.
  Future<void> _watchReel(EpisodeReel reel) async {
    final player = _player;
    final wasPlaying = player?.state.playing ?? false;
    await player?.pause();
    if (!mounted) return;
    final jump = await showReelViewer(
      context,
      reel: reel,
      youtubeId: widget.data.youtubeId,
      language: _language,
    );
    if (!mounted) return;
    if (jump) {
      await _seekTo(reel.startSeconds);
    } else if (wasPlaying) {
      await _player?.play();
    }
  }

  /// Kopira share link na trenutnu poziciju playera (path-based `/v/<id>/t/<sec>`).
  /// Vidi web/_worker.js — chapter-aware OG injection na ovaj path.
  void _copyMomentLink(BuildContext context, String youtubeId) {
    final pos = _player?.state.position ?? Duration.zero;
    final sec = pos.inSeconds;
    final url = episodeShareUrl(youtubeId, seconds: sec, lang: _language);
    Clipboard.setData(ClipboardData(text: url));
    String label;
    if (sec > 5) {
      final h = sec ~/ 3600;
      final m = (sec % 3600) ~/ 60;
      final s = sec % 60;
      String p(int n) => n.toString().padLeft(2, '0');
      label = h > 0 ? '$h:${p(m)}:${p(s)}' : '$m:${p(s)}';
    } else {
      label = AppLocalizations.of(context).episodeWholeEpisode;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).episodeLinkCopied(label)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Pronađi koji je chapter aktivan na temelju pozicije.
  int _activeChapterIndex() {
    int active = -1;
    final posSec = _position.inSeconds;
    for (int i = 0; i < _chapters.length; i++) {
      if (posSec >= _chapters[i].totalSeconds) {
        active = i;
      }
    }
    return active;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final data = widget.data;
    final wantEn = _language == EpisodeLanguage.en;
    final magV2 = data.magisteriumFullV2For(wantEn: wantEn);

    // Dinamicke tabove — Magisterium tab se prikazuje samo ako postoji v2 JSON.
    final tabs = <Widget>[
      _PlayerTab(
        data: data,
        player: _player,
        videoController: _videoController,
        videoReady: _videoReady,
        position: _position,
        duration: _duration,
        isPlaying: _isPlaying,
        ytMode: _ytMode,
        audioOnly: data.isAudioOnly,
        hasMedia: data.hasMedia,
        posterUrl: _audioArtUrl,
        seekUndo: _seekUndo,
        sponsoredMoments: _sponsored,
        onSponsoredListen: (m) => _seekTo(m.start),
        reels: _reels,
        onReelJump: (r) => _seekTo(r.startSeconds),
        onReelWatch: _watchReel,
        onEnterYtMode: () {
          _player?.pause();
          setState(() => _ytMode = true);
        },
        onExitYtMode: () => setState(() => _ytMode = false),
        onPlayPause: () {
          if (_isPlaying) {
            _player?.pause();
          } else {
            _player?.play();
          }
        },
        onSeek: (d) => _player?.seek(d),
      ),
      _ChaptersTab(
        chapters: _chapters,
        activeIndex: _activeChapterIndex(),
        onChapterTap: (seconds) => _seekTo(seconds),
        videoId: widget.data.isAudioOnly ? null : widget.data.youtubeId,
        episodeDurationSec: widget.data.info.duration,
      ),
      if (magV2 != null)
        SingleChildScrollView(child: MagisteriumV2View(data: magV2)),
      _InfoTab(data: data, ebook: _ebook),
    ];

    final destinations = <NavigationDestination>[
      NavigationDestination(
        icon: const Icon(Icons.play_circle_outline),
        selectedIcon: const Icon(Icons.play_circle_filled),
        label: l.episodeTabPlayer,
      ),
      NavigationDestination(
        icon: const Icon(Icons.list_outlined),
        selectedIcon: const Icon(Icons.list),
        label: l.episodeTabChapters,
      ),
      if (magV2 != null)
        const NavigationDestination(
          icon: Icon(Icons.menu_book_outlined),
          selectedIcon: Icon(Icons.menu_book),
          label: 'Magisterium',
        ),
      NavigationDestination(
        icon: const Icon(Icons.info_outline),
        selectedIcon: const Icon(Icons.info),
        label: l.episodeTabInfo,
      ),
    ];

    // Clamp selected index ako se broj tabova promjeni (npr. v2 loada nakon rebuilda).
    final safeIndex = _tabIndex.clamp(0, tabs.length - 1);

    return EpisodeLanguageScope(
      language: _language,
      hasTranslationEn: data.hasTranslationEn,
      child: Scaffold(
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: l.commonBack,
            // Bio tvrdi `go('/')` iako app bar nosi ime kanala. Sada popa stog;
            // bez stoga ide na kanal preko `upTarget` (razriješen slug niže).
            onPressed: () => back(
              context,
              fallback: upTarget(
                '/m/${data.youtubeId}',
                channelSlug:
                    channelCache.channelIdForName(data.info.channel)
                        ?.replaceAll('_', '-'),
              ),
            ),
          ),
          title: Text(
            data.info.channel,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Text(
                  data.info.id,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            FavoriteButton(
              episodeId: data.youtubeId,
              episodeTitle: data.displayTitle,
              channelName: data.info.channel,
            ),
            if (data.hasTranslationEn)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Center(
                  child: LanguageToggleChip(
                    current: _language,
                    onChanged: _onLanguageChanged,
                    compact: true,
                  ),
                ),
              ),
            EbookAction(
              availability: _ebook,
              title: data.displayTitle,
              preferEn: _language == EpisodeLanguage.en,
              episodeUrl: episodeShareUrl(data.youtubeId, lang: _language),
            ),
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: l.episodeCopyMomentLink,
              onPressed: () => _copyMomentLink(context, data.youtubeId),
            ),
            if (data.info.sourceUrl != null)
              IconButton(
                // X/Twitter izvor → 𝕏 (sourceUrl vodi na webpage_url, ne YT).
                icon: data.info.isX
                    ? const Text('𝕏', style: TextStyle(fontSize: 18))
                    : data.isAudioOnly
                        ? const Icon(Icons.open_in_new)
                        : const Icon(Icons.smart_display,
                            color: Color(0xFFFF0000)),
                tooltip: data.info.isX
                    ? l.episodeOpenOnX
                    : data.isAudioOnly
                        ? l.commonOpenSource
                        : l.episodeOpenOnYouTube,
                onPressed: () => openUrl(data.info.sourceUrl!),
              ),
            ViewModeToggleButton(
              toSimple: false,
              onPressed: () async {
                await saveSimpleModePref(false);
                if (!context.mounted) return;
                final target = _language == EpisodeLanguage.en
                    ? '/v/${data.youtubeId}/en'
                    : '/v/${data.youtubeId}';
                // Isti sadržaj, druga prezentacija → NE novi history entry.
                swapPresentation(context, target);
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                // Responzivnost: koliko tabova stane side-by-side?
                // ~440px je minimum prije nego sadrzaj (video 16:9, lista poglavlja,
                // markdown clanak) postane previse skucen.
                const minPanelWidth = 440.0;
                final visibleCount = (constraints.maxWidth / minPanelWidth)
                    .floor()
                    .clamp(1, tabs.length);
                return _ResponsiveTabLayout(
                  tabs: tabs,
                  destinations: destinations,
                  selectedIndex: safeIndex,
                  visibleCount: visibleCount,
                  onSelect: (i) => setState(() => _tabIndex = i),
                  theme: theme,
                );
              },
            ),
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, -0.2),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: _resumeHintSeconds == null
                        ? const SizedBox.shrink()
                        : ResumeHintBanner(
                            key: ValueKey(_resumeHintSeconds),
                            seconds: _resumeHintSeconds!,
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
        // Dno: "gost" traka (samo neprijavljenima) + sticky "Zid podrške"
        // (sam se sakrije bez aktivne kampanje). Donji safe area primjenjuje
        // samo vanjski SafeArea — obje trake se nezavisno pale/gase.
        bottomNavigationBar: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AnonymousSignInBar(applyBottomSafeArea: false),
              if (AppBrand.config.flags.pinka)
                PinkaSupportBar.episode(
                  youtubeId: data.youtubeId,
                  applyBottomSafeArea: false,
                  // Fallback na kampanju kanala — vidi episode_screen.dart.
                  channelRefs: [
                    ?data.info.youtubeChannelId,
                    ?channelCache.channelIdForName(data.info.channel),
                  ],
                  onOpen: (_, viaChannel) {
                    if (!viaChannel) {
                      drillDown(context, Uri(
                        path: '/v/${data.youtubeId}/support',
                        queryParameters: {'name': data.displayTitle},
                      ).toString());
                      return;
                    }
                    final slug = channelCache
                        .channelIdForName(data.info.channel)
                        ?.replaceAll('_', '-');
                    final uc = data.info.youtubeChannelId;
                    drillDown(context, Uri(
                      path: '/c/${slug ?? 'kanal'}/support',
                      queryParameters: {
                        'uc': ?uc,
                        'name': data.info.channel,
                      },
                    ).toString());
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Responsive layout — switcha izmedju single-tab+bottom-nav (mobile portrait)
// i multi-column rasporeda (desktop landscape) ovisno o dostupnoj sirini.
//
// visibleCount == 1: jedan tab + bottom nav s svim destinacijama, max-width 720
// visibleCount == tabs.length: Row sa svim tabovima side-by-side, bez bottom nava
// inace: pinanih (visibleCount - 1) tabova s lijeva, zadnji slot je preklopni
//        preko bottom nava (samo preostali tabovi su u nav-u)
// ---------------------------------------------------------------------------

class _ResponsiveTabLayout extends StatelessWidget {
  final List<Widget> tabs;
  final List<NavigationDestination> destinations;
  final int selectedIndex;
  final int visibleCount;
  final ValueChanged<int> onSelect;
  final ThemeData theme;

  const _ResponsiveTabLayout({
    required this.tabs,
    required this.destinations,
    required this.selectedIndex,
    required this.visibleCount,
    required this.onSelect,
    required this.theme,
  });

  Widget _columnDivider() => VerticalDivider(
    width: 1,
    thickness: 1,
    color: theme.colorScheme.outlineVariant.withAlpha(80),
  );

  Widget _navBar({
    required int idx,
    required ValueChanged<int> onTap,
    required List<NavigationDestination> dests,
  }) {
    return NavigationBar(
      selectedIndex: idx,
      onDestinationSelected: onTap,
      height: 64,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: dests,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (visibleCount == 1) {
      return Column(
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: IndexedStack(index: selectedIndex, children: tabs),
              ),
            ),
          ),
          _navBar(idx: selectedIndex, onTap: onSelect, dests: destinations),
        ],
      );
    }

    if (visibleCount >= tabs.length) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < tabs.length; i++) ...[
            if (i > 0) _columnDivider(),
            Expanded(child: tabs[i]),
          ],
        ],
      );
    }

    final pinnedCount = visibleCount - 1;
    final swapStart = pinnedCount;
    final swapTabs = tabs.sublist(swapStart);
    final swapDestinations = destinations.sublist(swapStart);
    final swapIndex = (selectedIndex - swapStart).clamp(0, swapTabs.length - 1);

    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < pinnedCount; i++) ...[
                if (i > 0) _columnDivider(),
                Expanded(child: tabs[i]),
              ],
              _columnDivider(),
              Expanded(
                child: IndexedStack(index: swapIndex, children: swapTabs),
              ),
            ],
          ),
        ),
        _navBar(
          idx: swapIndex,
          onTap: (i) => onSelect(swapStart + i),
          dests: swapDestinations,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 1: Player
// ---------------------------------------------------------------------------

class _PlayerTab extends StatelessWidget {
  final EpisodeData data;
  final Player? player;
  final VideoController? videoController;
  final bool videoReady;
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final bool ytMode;
  final bool audioOnly;
  final bool hasMedia;
  final String? posterUrl;

  /// Ponuda „vrati me gdje sam bio" nakon ručnog skoka. Vlasnik je ekran.
  final SeekUndo? seekUndo;

  /// Plaćeni sponzorski trenuci (vlasnik je ekran) i „Poslušaj" za njih.
  final SponsoredMomentsController? sponsoredMoments;
  final void Function(SponsoredMoment moment)? onSponsoredListen;

  /// Istaknuti trenuci; skok i isječak vodi ekran.
  final EpisodeReels? reels;
  final void Function(EpisodeReel reel)? onReelJump;
  final void Function(EpisodeReel reel)? onReelWatch;
  final VoidCallback onEnterYtMode;
  final VoidCallback onExitYtMode;
  final VoidCallback onPlayPause;
  final void Function(Duration) onSeek;

  const _PlayerTab({
    required this.data,
    required this.player,
    required this.videoController,
    required this.videoReady,
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.ytMode,
    required this.audioOnly,
    required this.hasMedia,
    required this.posterUrl,
    required this.seekUndo,
    this.sponsoredMoments,
    this.onSponsoredListen,
    this.reels,
    this.onReelJump,
    this.onReelWatch,
    required this.onEnterYtMode,
    required this.onExitYtMode,
    required this.onPlayPause,
    required this.onSeek,
  });

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final info = data.info;
    final lang = EpisodeLanguageScope.of(context);
    final summaryHr = data.summary?.summary;
    final summary = lang == EpisodeLanguage.en
        ? (data.summaryEn?.summary ?? summaryHr)
        : summaryHr;
    // Lokalizirani naslov: prefer EN summary.titleEn → HR summary.titleHr → YouTube original.
    String displayTitle = data.displayTitle;
    if (lang == EpisodeLanguage.en && summary != null) {
      final en = summary.titleEn;
      if (en != null && en.isNotEmpty) displayTitle = en;
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Video player (native ili YouTube embed), audio cover-art or thumbnail
          AspectRatio(
            aspectRatio: 16 / 9,
            child: audioOnly
                // Unmute CTA samo ovdje — kod videa ga crta `EpisodeVideo`
                // kroz `controls:` builder, pa bi se udvostručio.
                ? Stack(
                    children: [
                      Positioned.fill(child: AudioPoster(artUrl: posterUrl)),
                      Positioned.fill(
                        child: UnmuteOverlay(
                          onUnmuted: () {
                            final p = player;
                            if (p != null && !p.state.playing) p.play();
                          },
                        ),
                      ),
                    ],
                  )
                : ytMode
                ? YouTubeEmbed(
                    videoId: data.youtubeVideoId,
                    startSeconds: position.inSeconds,
                  )
                : videoReady && videoController != null && player != null
                ? EpisodeVideo(
                    player: player!,
                    controller: videoController!,
                    speakerTimeline: data.speakerTimeline,
                    speakers: summary?.speakers ?? const [],
                    seekUndo: seekUndo,
                    sponsoredMoments: sponsoredMoments,
                    onYouTubeMode: youTubeEmbedSupported ? onEnterYtMode : null,
                  )
                : !hasMedia
                // Medije kod nas nema — umjesto mrtve crne plohe ponudi
                // ugradeni YouTube (na nativeu facade otvori youtube.com).
                // Sinteticki ID-evi (X / ne-YT izvori) nemaju sto ugraditi.
                ? (!data.info.isX && data.info.ytMatched
                    ? InAppYouTubePlayer(
                        videoId: data.youtubeVideoId,
                        posterUrl: CdnConfig.thumbnailUrl(data.youtubeId),
                        playableInEmbed: data.info.playableInEmbed,
                      )
                    : ColoredBox(
                        color: Colors.black,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.music_off,
                                color: Colors.white54,
                                size: 40,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                l.episodeMediaUnavailable,
                                style: const TextStyle(color: Colors.white70),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ))
                : Container(
                    color: Colors.black,
                    child: info.thumbnail.isNotEmpty
                        ? Stack(
                            alignment: Alignment.center,
                            children: [
                              Image.network(
                                info.thumbnail,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                                errorBuilder: (c, e, s) => const SizedBox(),
                              ),
                              const CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            ],
                          )
                        : const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                  ),
          ),

          if (ytMode) YouTubeModeBar(onExit: onExitYtMode),

          // Mobitel u portraitu: titl ispod slike (isto kao u `VideoPanel`).
          if (videoReady &&
              !ytMode &&
              !audioOnly &&
              player != null &&
              data.speakerTimeline != null &&
              subtitlesBelowPlayer(context))
            SubtitleStrip(player: player!, timeline: data.speakerTimeline!),

          // Seek bar
          if (videoReady && !ytMode) ...[
            // Undo skoka — samo na audio-only putanji. Kod videa istu pilulu
            // već crta EpisodeVideo preko slike (i u fullscreenu), pa bi je
            // ovdje dobili dvaput.
            if (seekUndo != null && audioOnly)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: SeekUndoPill(undo: seekUndo!, onUndo: onSeek),
                ),
              ),
            // Istaknuti trenuci iznad tracka; uvlaka = radijus overlaya (16),
            // koliko Slider uvuče track od ruba.
            Stack(
              alignment: Alignment.center,
              children: [
                if (reels?.isNotEmpty ?? false)
                  ReelTimelineMarks(
                    reels: reels!.reels,
                    totalMs: duration.inMilliseconds,
                    inset: 16,
                  ),
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                    activeTrackColor: theme.colorScheme.primary,
                    inactiveTrackColor: theme.colorScheme.primary.withAlpha(40),
                    thumbColor: theme.colorScheme.primary,
                  ),
                  child: Slider(
                    value: duration.inMilliseconds > 0
                        ? position.inMilliseconds
                              .clamp(0, duration.inMilliseconds)
                              .toDouble()
                        : 0,
                    max: duration.inMilliseconds > 0
                        ? duration.inMilliseconds.toDouble()
                        : 1,
                    onChanged: (v) => onSeek(Duration(milliseconds: v.toInt())),
                  ),
                ),
              ],
            ),

            // Time + controls
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    _formatDuration(position),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  // Rewind 15s
                  IconButton(
                    icon: const Icon(Icons.replay_10),
                    iconSize: 32,
                    onPressed: () => onSeek(
                      Duration(
                        seconds: (position.inSeconds - 10).clamp(0, 999999),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Play/Pause
                  IconButton.filled(
                    icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                    iconSize: 40,
                    onPressed: onPlayPause,
                  ),
                  const SizedBox(width: 8),
                  // Forward 30s
                  IconButton(
                    icon: const Icon(Icons.forward_30),
                    iconSize: 32,
                    onPressed: () =>
                        onSeek(Duration(seconds: position.inSeconds + 30)),
                  ),
                  const Spacer(),
                  Text(
                    _formatDuration(duration),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            // Brzina + „u pozadini" u zasebnom redu: transportni red je na
            // 360 px već pun, a ovo je jedini ulaz u obje postavke na
            // audio-only epizodi (gdje media_kitova traka ne postoji).
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                SpeedCycleButton(),
                SizedBox(width: 8),
                MuteToggleButton(),
                SizedBox(width: 8),
                BackgroundPlaybackButton(),
                RemotePlaybackButton(),
              ],
            ),
          ],

          // Plaćeni trenuci — ispod kontrola, i na audio-only putanji.
          SponsoredMomentsPlayerStrip(
            controller: sponsoredMoments,
            onListen: videoReady ? onSponsoredListen : null,
          ),

          // Istaknuti trenuci — i na audio-only putanji (skok u epizodu).
          EpisodeReelsPlayerStrip(
            reels: reels,
            position: position,
            onJump: videoReady ? onReelJump : null,
            onWatch: onReelWatch,
          ),

          const SizedBox(height: 16),

          // Episode info
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.podcasts,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        info.channel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.schedule,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      info.durationString,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (summary != null && summary.speakers.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: summary.speakers
                        .map((s) => SpeakerChip(speaker: s))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 8),
          // "Zid podrške" za epizodu — sam se sakrije ako epizoda nema aktivnu
          // pinka kampanju. SEPA QR + on-chain EURe (Gnosis Safe) + in-app wallet.
          if (AppBrand.config.flags.pinka)
            PinkaSupportCard.episode(
              youtubeId: data.youtubeId,
              onOpen: (_) => drillDown(
                context,
                Uri(
                  path: '/v/${data.youtubeId}/support',
                  queryParameters: {'name': data.displayTitle},
                ).toString(),
              ),
            ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 2: Chapters
// ---------------------------------------------------------------------------

class _ChaptersTab extends StatelessWidget {
  final List<({String timestamp, String topic, int totalSeconds})> chapters;
  final int activeIndex;
  final void Function(int seconds) onChapterTap;

  /// Non-null → each chapter row gets a download/share clip action. Null for
  /// audio-only episodes (the cutter needs `video_h264.mp4`).
  final String? videoId;
  final int episodeDurationSec;

  const _ChaptersTab({
    required this.chapters,
    required this.activeIndex,
    required this.onChapterTap,
    this.videoId,
    this.episodeDurationSec = 0,
  });

  String _formatTime(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    if (chapters.isEmpty) {
      return Center(
        child: Text(
          l.episodeNoChapters,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    // Uniformna širina timestamp chipa za CIJELU listu — mm:ss i h:mm:ss
    // redovi dijele istu širinu pa naslovi poglavlja ostaju poravnati, a
    // h:mm:ss se nikad ne prelama u dva reda (chapters su sortirani pa je
    // zadnji ujedno i najdulji format).
    final hasHours =
        chapters.isNotEmpty && chapters.last.totalSeconds >= 3600;
    final timeChipWidth = hasHours ? 68.0 : 56.0;

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: chapters.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        indent: 16,
        endIndent: 16,
        color: theme.colorScheme.outlineVariant.withAlpha(80),
      ),
      itemBuilder: (context, i) {
        final ch = chapters[i];
        final isActive = i == activeIndex;

        return ListTile(
          // Razmak među redovima — chip se rasteže na visinu retka pa bez
          // ovoga vizualno "lijepi" za divider iznad/ispod.
          minVerticalPadding: 10,
          leading: Container(
            width: timeChipWidth,
            alignment: Alignment.center,
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: isActive
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            // FittedBox: i kad OS font-scaling povisi tekst preko širine
            // chipa, timestamp se smanji umjesto da se prelomi u dva reda.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _formatTime(ch.totalSeconds),
                maxLines: 1,
                softWrap: false,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  color: isActive
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          title: Text(
            ch.topic,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: () {
            // Clip window: this chapter's start → next chapter's start, or the
            // episode end for the last chapter.
            final startSec = ch.totalSeconds;
            final endSec = i + 1 < chapters.length
                ? chapters[i + 1].totalSeconds
                : episodeDurationSec;
            final chevron = Icon(
              isActive ? Icons.play_arrow : Icons.chevron_right,
              color: isActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              size: 20,
            );
            if (videoId == null || endSec <= startSec) return chevron;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipShareButton(
                  videoId: videoId!,
                  startSec: startSec,
                  endSec: endSec,
                  title: ch.topic,
                ),
                chevron,
              ],
            );
          }(),
          onTap: () => onChapterTap(ch.totalSeconds),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 3: Info
// ---------------------------------------------------------------------------

class _InfoTab extends StatelessWidget {
  final EpisodeData data;
  final EbookAvailability ebook;

  const _InfoTab({required this.data, required this.ebook});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final info = data.info;
    final lang = EpisodeLanguageScope.of(context);
    final isEn = lang == EpisodeLanguage.en;
    final summaryHr = data.summary?.summary;
    final summary = isEn ? (data.summaryEn?.summary ?? summaryHr) : summaryHr;
    String displayTitle = data.displayTitle;
    if (isEn && summary != null) {
      final en = summary.titleEn;
      if (en != null && en.isNotEmpty) displayTitle = en;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Title
        Text(
          displayTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),

        // E-knjiga: ista ponuda kao na detaljnom ekranu, pa oba pogleda o istoj
        // epizodi nude isto. Kartica se sama sakrije kad knjige nema.
        EbookCard(
          availability: ebook,
          title: displayTitle,
          preferEn: isEn,
          episodeUrl: episodeShareUrl(data.youtubeId, lang: lang),
        ),

        // Napredak obrade — ista kartica kao na detaljnom ekranu, pa oba
        // pogleda o istoj epizodi kazu istu stvar.
        if (summary == null) ...[
          EpisodeStatusCard(
            status: data.status,
            audioOnly: data.isAudioOnly,
          ),
          const SizedBox(height: 16),
        ],

        // Abstract
        if (summary != null) ...[
          Builder(
            builder: (_) {
              final abstractText = pickLang(
                lang,
                summary.abstractHr,
                summary.abstractEn,
              );
              if (abstractText.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withAlpha(120),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      abstractText,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        ],

        // Key topics
        if (summary != null) ...[
          Builder(
            builder: (_) {
              final topics = pickLangList(
                lang,
                summary.keyTopics,
                summary.keyTopicsEn,
              );
              if (topics.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionTitle(icon: Icons.topic, label: l.episodeKeyTopics),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: topics.map((t) {
                      return Chip(
                        label: Text(t, style: const TextStyle(fontSize: 12)),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        ],

        // Key points
        if (summary != null && summary.keyPoints.isNotEmpty) ...[
          _SectionTitle(
            icon: Icons.format_list_bulleted,
            label: l.episodeKeyTakeaways,
          ),
          const SizedBox(height: 8),
          ...pickLangList(lang, summary.keyPoints, summary.keyPointsEn).map(
            (kp) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Icon(
                      Icons.circle,
                      size: 6,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      kp,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Speakers
        if (summary != null && summary.speakers.isNotEmpty) ...[
          _SectionTitle(icon: Icons.people, label: l.episodeSpeakers),
          const SizedBox(height: 8),
          ...summary.speakers.map((s) {
            final roleLabel = isEn ? s.roleLabelEn() : s.roleLabel;
            final name = s.displayName;
            final row = Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(
                    Icons.person,
                    size: 18,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        // Ako pipeline nije izvukao pravo ime (host se ne
                        // predstavlja), suggested_name je == role — tada
                        // prikazi samo capitalized roleLabel.
                        name ?? roleLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (name != null && s.role.isNotEmpty)
                        Text(
                          roleLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
            // Govornik s pravim imenom → tap na profil (/p/:slug). Anonimni
            // role-labeli nisu u bazi pa se ne linkaju.
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: name == null
                  ? row
                  : InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () =>
                          drillDown(context, '/p/${personSlug(name)}'),
                      child: row,
                    ),
            );
          }),
          const SizedBox(height: 16),
        ],

        // Metadata
        Divider(color: theme.colorScheme.outlineVariant),
        const SizedBox(height: 8),
        _MetaRow(
          icon: Icons.calendar_today,
          label: l.episodeMetaDate,
          value: _formatDate(info.uploadDate),
          theme: theme,
        ),
        _MetaRow(
          icon: Icons.schedule,
          label: l.episodeMetaDuration,
          value: info.durationString,
          theme: theme,
        ),
        // YouTube view/like counts hidden — snapshot data, not live-synced.
        // Re-enable once we have our own internal statistics.
        // _MetaRow(
        //   icon: Icons.visibility,
        //   label: 'Pregledi',
        //   value: _formatCount(info.viewCount),
        //   theme: theme,
        // ),
        // _MetaRow(
        //   icon: Icons.thumb_up,
        //   label: 'Lajkovi',
        //   value: _formatCount(info.likeCount),
        //   theme: theme,
        // ),
        const SizedBox(height: 24),
      ],
    );
  }

  String _formatDate(String yyyymmdd) {
    if (yyyymmdd.length == 8) {
      return '${yyyymmdd.substring(6, 8)}.${yyyymmdd.substring(4, 6)}.${yyyymmdd.substring(0, 4)}.';
    }
    return yyyymmdd;
  }

  // ignore: unused_element
  String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionTitle({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ThemeData theme;

  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
