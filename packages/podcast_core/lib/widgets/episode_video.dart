/// Zajednički video player wrapper za episode ekrane (web/mobile).
///
/// Nadogradnje nad golim media_kit `Video` widgetom — YouTube-like UX:
///  - klik na video toggle-a play/pause (media_kit default je OFF)
///  - dvoklik toggle-a fullscreen (desktop) / ±10s seek (mobile rubovi)
///  - titlovi iz diarized.srt (CC gumb, persisted pref) — rendamo ih SAMI
///    jer media_kit web subtitle path traži VTT i označen je "UNTESTED"
///  - fullscreen fix #1: ulazak u fullscreen na webu pauzira video jer se
///    <video> element re-parenta u novu Flutter rutu (DOM remove+insert =
///    pauza po HTML spec-u) → auto-resume nakon tranzicije
///  - fullscreen fix #2: Esc izađe iz browser fullscreena, ali media_kit
///    Flutter ruta ostane → fullscreenchange listener je sinkronizira
///  - fullscreen u portretu: tri putanje (T4) — pravi landscape na nativeu
///    (`SystemChrome`), `screen.orientation.lock` gdje web to daje, inače
///    vizualna rotacija kroz `rotated_fullscreen.dart`
///  - YouTube keyboard kratice: Space/K, J/L ±10s, ←/→ ±5s, ↑/↓ glasnoća,
///    F fullscreen, M mute, C titlovi, Esc izlaz
///
/// Koriste ga VideoPanel (episode_screen) i _PlayerTab (episode_simple_screen).
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:floating/floating.dart';

import '../l10n/app_localizations.dart';
import '../models/podcast_summary.dart';
import '../models/speaker_timeline.dart';
import '../services/browser_fullscreen.dart';
import '../services/player_mute.dart';
import '../services/screen_orientation.dart';
import '../services/seek_undo.dart';
import '../services/sponsored_moments_controller.dart';
import '../services/subtitle_prefs.dart';
import 'playback_controls.dart';
import 'sponsored_moment_widgets.dart';
import 'subtitle_caption.dart';
import 'rotated_fullscreen.dart';

/// Boje govornika po redoslijedu iz speakers liste — dijeli se s
/// VideoPanel speaker barom da fullscreen badge i bar budu konzistentni.
Map<String, Color> speakerColorsFor(
  ThemeData theme,
  List<SummarySpeaker> speakers,
) {
  final palette = [
    theme.colorScheme.primary,
    theme.colorScheme.tertiary,
    theme.colorScheme.secondary,
    theme.colorScheme.error,
  ];
  return {
    for (var i = 0; i < speakers.length; i++)
      speakers[i].id: palette[i % palette.length],
  };
}

class EpisodeVideo extends StatefulWidget {
  final Player player;
  final VideoController controller;

  /// Diarizirani transkript — izvor titlova i fullscreen speaker badge-a.
  final SpeakerTimeline? speakerTimeline;
  final List<SummarySpeaker> speakers;

  /// Ako je set, u control bar se dodaje gumb za YouTube embed mode
  /// (viša kvaliteta preko službenog YouTube playera).
  final VoidCallback? onYouTubeMode;

  /// Ponuda „vrati me gdje sam bio" nakon ručnog skoka po timelineu. Kad je
  /// zadana, pilula se renderira kroz `controls:` builder pa postoji i u
  /// media_kitovoj fullscreen ruti. Vlasnik je ekran (drži `Player`).
  final SeekUndo? seekUndo;

  /// Postavljeno **samo** na instanci koja živi unutar naše rotacijske
  /// fullscreen rute (putanja C). Tada gumb i Esc izlaze iz te rute umjesto da
  /// diraju media_kitov fullscreen, a kontrole dobiju fullscreen raspored
  /// (speaker badge gore). Vanjska instanca ovo NIKAD ne postavlja.
  final VoidCallback? onExitRotatedFullscreen;

  /// Plaćeni sponzorski trenuci — oznaka „Sponzorirano · {brand}" preko slike
  /// dok trenutak svira. Kroz `controls:` builder pa je vidljiva i u
  /// fullscreenu, gdje panela i trake ispod slike nema.
  final SponsoredMomentsController? sponsoredMoments;

  const EpisodeVideo({
    super.key,
    required this.player,
    required this.controller,
    this.speakerTimeline,
    this.speakers = const [],
    this.onYouTubeMode,
    this.seekUndo,
    this.onExitRotatedFullscreen,
    this.sponsoredMoments,
  });

  @override
  State<EpisodeVideo> createState() => _EpisodeVideoState();
}

class _EpisodeVideoState extends State<EpisodeVideo> {
  final GlobalKey<VideoState> _videoKey = GlobalKey<VideoState>();

  void Function()? _removeFsListener;

  /// Zatvarač naše rotacijske rute dok je otvorena (null = nije otvorena).
  VoidCallback? _closeRotated;

  /// Jesmo li MI zaključali orijentaciju (putanja A/B). Otključavamo isključivo
  /// ono što smo sami zaključali — desktop i landscape putanje ne diraju
  /// sistemsko stanje pa ga ne smiju ni „vraćati".
  bool _lockedOrientation = false;

  @override
  void initState() {
    super.initState();
    _removeFsListener = addFullscreenChangeListener(_onBrowserFullscreenChange);
    _setupAutoPip();
  }

  void _setupAutoPip() async {
    if (!pipPluginSupported) return;
    final floating = Floating();
    if (await floating.isPipAvailable) {
      floating.enable(const OnLeavePiP(aspectRatio: Rational.landscape()));
    }
  }

  @override
  void dispose() {
    _removeFsListener?.call();
    // Ekran se rastavlja s bravom orijentacije na sebi (npr. deep-link
    // navigacija iz fullscreena) — ne ostavljaj uređaj zaključan u landscapeu.
    if (_lockedOrientation) {
      _lockedOrientation = false;
      unlockOrientation();
    }
    if (pipPluginSupported) {
      Floating().cancelOnLeavePiP().catchError((_) {});
    }
    super.dispose();
  }

  /// Esc u browseru izađe iz native fullscreena bez znanja Fluttera —
  /// media_kit fullscreen ruta (ili naša rotacijska) ostane "zarobljena".
  /// Detektiraj i popaj.
  void _onBrowserFullscreenChange() {
    if (isBrowserFullscreen) return;
    // Rotacijska ruta ima prednost: kad je ona na ekranu, media_kit fullscreen
    // nije aktivan pa niže provjere nemaju što raditi.
    final exitRotated = _rotatedExit;
    if (exitRotated != null) {
      exitRotated();
      return;
    }
    final vs = _videoKey.currentState;
    if (vs == null) return;
    try {
      if (vs.isFullscreen()) vs.exitFullscreen();
    } catch (_) {
      // contextNotifier još nije inicijaliziran — ignore.
    }
  }

  /// Izlaz iz rotacijskog fullscreena, gledano s bilo koje strane: vanjska
  /// instanca ga zna preko `_closeRotated`, ona unutar rute preko
  /// `widget.onExitRotatedFullscreen`. `null` = rotacijska ruta nije u igri.
  VoidCallback? get _rotatedExit =>
      widget.onExitRotatedFullscreen ?? _closeRotated;

  /// Web: re-parent <video> elementa u fullscreen rutu browser tretira kao
  /// remove+insert iz DOM-a i pauzira playback (HTML spec). Resume kratko
  /// nakon tranzicije ako je korisnik prije nje slušao. Dva pokušaja jer
  /// timing pause eventa ovisi o frame schedulingu.
  void _resumeAfterTransition(bool wasPlaying) {
    if (!wasPlaying) return;
    for (final delay in const [300, 900]) {
      Future<void>.delayed(Duration(milliseconds: delay), () {
        if (!mounted) return;
        try {
          if (!widget.player.state.playing) widget.player.play();
        } catch (_) {}
      });
    }
  }

  Future<void> _onEnterFullscreen() async {
    final wasPlaying = widget.player.state.playing;
    try {
      await defaultEnterNativeFullscreen();
    } catch (_) {
      // iPhone Safari ne podržava Element.requestFullscreen — Flutter
      // fullscreen ruta svejedno radi (in-app fullscreen).
    }
    _resumeAfterTransition(wasPlaying);
  }

  Future<void> _onExitFullscreen() async {
    final wasPlaying = widget.player.state.playing;
    try {
      await defaultExitNativeFullscreen();
    } catch (_) {}
    // Nakon media_kitovog restorea (on vraća `manual` + sve overlaye), da
    // završno stanje bude naše: sve orijentacije + edge-to-edge.
    if (_lockedOrientation) {
      _lockedOrientation = false;
      await unlockOrientation();
    }
    _resumeAfterTransition(wasPlaying);
  }

  // -------------------------------------------------------------------------
  // Fullscreen: tri putanje (T4)
  //
  //  A  native iOS/Android → `SystemChrome` forsira pravi landscape i probija
  //     sistemsku bravu rotacije (D3), pa ide media_kitova ruta;
  //  B  web koji ima `screen.orientation.lock` i pusti ga (Android Chrome) →
  //     browser fullscreen, brava, pa media_kitova ruta;
  //  C  sve ostalo u portretu (iPhone Safari/Chrome — nema `lock`; desktop
  //     Chrome u device toolbaru — `lock` odbije) → naša rotacijska ruta.
  //
  // Landscape/široki viewport (desktop) NE ulazi u ovu granu uopće: ide
  // `vs.enterFullscreen()` kao i dosad, bez ikakvog diranja orijentacije.
  // -------------------------------------------------------------------------

  /// Portretni viewport — jedini slučaj u kojem fullscreen traži rotaciju.
  /// Blagi faktor da gotovo kvadratni viewport ne skače između putanja.
  bool get _viewportIsPortrait {
    final size = MediaQuery.sizeOf(context);
    return size.height > size.width * 1.05;
  }

  Future<void> _toggleFullscreen() async {
    // Unutar rotacijske rute (ili s njom otvorenom) gumb i kratice samo izlaze.
    final exitRotated = _rotatedExit;
    if (exitRotated != null) {
      exitRotated();
      return;
    }

    final vs = _videoKey.currentState;
    if (vs == null) return;

    bool alreadyFullscreen = false;
    try {
      alreadyFullscreen = vs.isFullscreen();
    } catch (_) {}
    if (alreadyFullscreen) {
      try {
        vs.exitFullscreen();
      } catch (_) {}
      return;
    }

    if (!_viewportIsPortrait) {
      // Današnja putanja, netaknuta.
      try {
        vs.enterFullscreen();
      } catch (_) {}
      return;
    }

    await _enterLandscapeFullscreen(vs);
  }

  Future<void> _enterLandscapeFullscreen(VideoState vs) async {
    if (canLockOrientation) {
      // Web: brava legne SAMO unutar browser fullscreena → prvo fullscreen,
      // pa lock. Na nativeu je poredak nevažan.
      if (kIsWeb) {
        try {
          await defaultEnterNativeFullscreen();
        } catch (_) {
          // iPhone Safari ne podržava requestFullscreen — svejedno probaj
          // bravu, pa padni na putanju C.
        }
      }
      if (await lockLandscape()) {
        _lockedOrientation = true;
        if (!mounted) return;
        // Putanja A/B: pravi landscape + media_kitova ruta. Resume playbacka i
        // izlaz iz browser fullscreena rješavaju `_onEnterFullscreen` /
        // `_onExitFullscreen`, isto kao za desktop.
        try {
          vs.enterFullscreen();
        } catch (_) {}
        return;
      }
    }

    if (!mounted) return;
    _pushRotatedFullscreen();
  }

  /// Putanja C. Naša ruta re-parenta `<video>` element u DOM-u isto kao
  /// media_kitova → browser to čita kao remove+insert i pauzira (CLAUDE.md,
  /// media_kit zamka #1), pa ide isti `_resumeAfterTransition`.
  void _pushRotatedFullscreen() {
    final wasPlaying = widget.player.state.playing;
    unawaited(
      showRotatedFullscreen(
        context: context,
        onOpened: (exit) => _closeRotated = exit,
        builder: (_, exit) => EpisodeVideo(
          player: widget.player,
          controller: widget.controller,
          speakerTimeline: widget.speakerTimeline,
          speakers: widget.speakers,
          onYouTubeMode: widget.onYouTubeMode,
          seekUndo: widget.seekUndo,
          onExitRotatedFullscreen: exit,
          sponsoredMoments: widget.sponsoredMoments,
        ),
        onClosed: _onRotatedFullscreenClosed,
      ),
    );
    _resumeAfterTransition(wasPlaying);
  }

  void _onRotatedFullscreenClosed() {
    _closeRotated = null;
    final wasPlaying = widget.player.state.playing;
    // Ako smo pri ulasku uspjeli u browser fullscreen (desktop Chrome, device
    // toolbar), izađi. Kad je izlaz i došao od Esc-a, fullscreena više nema.
    if (kIsWeb && isBrowserFullscreen) {
      unawaited(defaultExitNativeFullscreen());
    }
    _resumeAfterTransition(wasPlaying);
  }

  void _exitFullscreenIfAny() {
    final exitRotated = _rotatedExit;
    if (exitRotated != null) {
      exitRotated();
      return;
    }
    final vs = _videoKey.currentState;
    if (vs == null) return;
    try {
      if (vs.isFullscreen()) vs.exitFullscreen();
    } catch (_) {}
  }

  void _seekRelative(Duration offset) {
    final pos = widget.player.state.position + offset;
    widget.player.seek(pos < Duration.zero ? Duration.zero : pos);
  }

  void _changeVolume(double delta) {
    final volume = (widget.player.state.volume + delta).clamp(0.0, 100.0);
    widget.player.setVolume(volume);
  }

  /// M kratica ide kroz isti singleton kao gumbi — inače bi tipkovnica i traka
  /// pokazivale različito stanje, a na webu bi `setVolume` još i skinuo `muted`
  /// flag (vidi `services/media_element_mute_web.dart`).
  void _toggleMute() => PlayerMute.instance.toggle();

  /// CC stanje je singleton ([SubtitlesEnabled]): dijele ga overlay, gumb,
  /// njihove kopije u media_kitovoj fullscreen ruti i [SubtitleStrip] ispod
  /// playera, koji živi izvan ovog widgeta.
  void _toggleSubtitles() => SubtitlesEnabled.instance.toggle();

  /// YouTube kratice: https://support.google.com/youtube/answer/7631406
  Map<ShortcutActivator, VoidCallback> get _keyboardShortcuts => {
        const SingleActivator(LogicalKeyboardKey.mediaPlay): () =>
            widget.player.play(),
        const SingleActivator(LogicalKeyboardKey.mediaPause): () =>
            widget.player.pause(),
        const SingleActivator(LogicalKeyboardKey.mediaPlayPause): () =>
            widget.player.playOrPause(),
        const SingleActivator(LogicalKeyboardKey.space): () =>
            widget.player.playOrPause(),
        const SingleActivator(LogicalKeyboardKey.keyK): () =>
            widget.player.playOrPause(),
        const SingleActivator(LogicalKeyboardKey.keyJ): () =>
            _seekRelative(const Duration(seconds: -10)),
        const SingleActivator(LogicalKeyboardKey.keyL): () =>
            _seekRelative(const Duration(seconds: 10)),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _seekRelative(const Duration(seconds: -5)),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _seekRelative(const Duration(seconds: 5)),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _changeVolume(5),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _changeVolume(-5),
        const SingleActivator(LogicalKeyboardKey.keyF): _toggleFullscreen,
        const SingleActivator(LogicalKeyboardKey.keyM): _toggleMute,
        const SingleActivator(LogicalKeyboardKey.keyC): _toggleSubtitles,
        const SingleActivator(LogicalKeyboardKey.escape): _exitFullscreenIfAny,
      };

  Widget _subtitleButton() => _SubtitleToggleButton(
        enabled: SubtitlesEnabled.instance,
        onToggle: _toggleSubtitles,
      );

  Widget? _youTubeButton() {
    final cb = widget.onYouTubeMode;
    if (cb == null) return null;
    final l = AppLocalizations.of(context);
    return IconButton(
      icon: const Icon(Icons.hd_outlined, color: Colors.white),
      tooltip: l.mediaYouTubeHigherQuality,
      onPressed: cb,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = speakerColorsFor(theme, widget.speakers);
    final timeline = widget.speakerTimeline;
    final ytButton = _youTubeButton();
    final undo = widget.seekUndo;

    // Brzina i „u pozadini" stoje lijevo od CC gumba, u obje trake; isti popis
    // ide i u `fullscreen:` varijantu teme pa kontrole postoje i u fullscreenu.
    //
    // PRELJEV — media_kit slaže `bottomButtonBar` u goli `Row` bez ikakve
    // zaštite, a desktop traka živi u 360 dp `VideoPanel` stupcu: sedam gumba
    // po 48 dp je 336 dp u 328 dp prostora (izmjereno: preljev od točno 8 dp,
    // vidi `test/playback_bar_layout_test.dart`). Zato tri mjere:
    //
    //  1. indikator pozicije umjesto `Spacer`-a dobiva `Expanded` +
    //     `scaleDown` — jedini elastičan element, skupi se umjesto da traka
    //     pukne (na 360 dp panelu praktički nestane; isto vrijeme piše i u
    //     panelovu redu odmah ispod slike, a u fullscreenu je cijelo);
    //  2. naša dva gumba idu u fiksnih 40 dp uz `scaleDown` — `VisualDensity`
    //     ovdje NE pomaže (M3 `IconButton` uzima gustoću iz svojih defaulta,
    //     ne iz `ThemeData`; izmjereno: ostaje 48 dp), a fiksna širina usput
    //     rješava i to što label brzine raste s vrijednošću („1×" vs „1,75×").
    Widget positionSlot(Widget indicator) => Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: indicator,
          ),
        );

    Widget compactSlot(Widget child) => SizedBox(
          width: 40,
          child: FittedBox(fit: BoxFit.scaleDown, child: child),
        );

    final speedButton = compactSlot(const SpeedCycleButton(onVideo: true));
    final backgroundButton = compactSlot(
      const BackgroundPlaybackButton(onVideo: true),
    );
    final pipButton = compactSlot(
      const PictureInPictureButton(onVideo: true),
    );
    // SAMO u mobilnoj traci: desktop varijanta već ima
    // `MaterialDesktopVolumeButton` (klizač), a osmi gumb bi joj razbio
    // širinski budžet od 328 dp — vidi `test/playback_bar_layout_test.dart`.
    final muteButton = compactSlot(const MuteToggleButton(onVideo: true));

    // Gumb za fullscreen je NAŠ jer bira putanju A/B/C (T4) — media_kitov
    // `Material*FullscreenButton` zove njihov `toggleFullscreen` bez hooka.
    // Izgled je namjerno identičan njihovom (ista ikona, ista veličina iz
    // defaulta teme, bijela), da desktop ostane bit-za-bit isti.
    final inRotated = widget.onExitRotatedFullscreen != null;
    Widget fullscreenButton(double iconSize) => _FullscreenPathButton(
          onPressed: _toggleFullscreen,
          forceExitIcon: inRotated,
          iconSize: iconSize,
        );

    final desktopBottomBar = <Widget>[
      const MaterialDesktopPlayOrPauseButton(),
      const MaterialDesktopVolumeButton(),
      positionSlot(const MaterialDesktopPositionIndicator()),
      speedButton,
      backgroundButton,
      pipButton,
      ?ytButton,
      if (timeline != null) _subtitleButton(),
      fullscreenButton(28),
    ];

    final mobileBottomBar = <Widget>[
      positionSlot(const MaterialPositionIndicator()),
      muteButton,
      speedButton,
      backgroundButton,
      pipButton,
      ?ytButton,
      if (timeline != null) _subtitleButton(),
      fullscreenButton(24),
    ];

    final fullscreenTopBar = <Widget>[
      if (timeline != null)
        _SpeakerBadge(
          player: widget.player,
          speakerTimeline: timeline,
          speakers: widget.speakers,
          speakerColors: colors,
        ),
    ];

    // U rotacijskoj ruti media_kit ne zna da je fullscreen (nije njegova ruta)
    // pa bi vrijedila `normal` tema — zato joj tu dodajemo fullscreen top bar,
    // da speaker badge postoji i u rotiranoj slici.
    final normalTopBar = inRotated ? fullscreenTopBar : const <Widget>[];

    return MaterialDesktopVideoControlsTheme(
      normal: MaterialDesktopVideoControlsThemeData(
        playAndPauseOnTap: true,
        keyboardShortcuts: _keyboardShortcuts,
        topButtonBar: normalTopBar,
        bottomButtonBar: desktopBottomBar,
      ),
      fullscreen: MaterialDesktopVideoControlsThemeData(
        playAndPauseOnTap: true,
        keyboardShortcuts: _keyboardShortcuts,
        topButtonBar: fullscreenTopBar,
        bottomButtonBar: desktopBottomBar,
      ),
      child: MaterialVideoControlsTheme(
        normal: MaterialVideoControlsThemeData(
          seekOnDoubleTap: true,
          topButtonBar: normalTopBar,
          bottomButtonBar: mobileBottomBar,
        ),
        fullscreen: MaterialVideoControlsThemeData(
          seekOnDoubleTap: true,
          topButtonBar: fullscreenTopBar,
          bottomButtonBar: mobileBottomBar,
        ),
        child: Video(
          key: _videoKey,
          controller: widget.controller,
          onEnterFullscreen: _onEnterFullscreen,
          onExitFullscreen: _onExitFullscreen,
          controls: (state) => StreamBuilder<PiPStatus>(
            stream: pipPluginSupported
                ? Floating().pipStatusStream
                : const Stream.empty(),
            initialData: PiPStatus.disabled,
            builder: (context, pipSnapshot) {
              if (pipSnapshot.data == PiPStatus.enabled) {
                return const SizedBox.shrink();
              }
              return Stack(
                children: [
              // Na mobitelu u portraitu titl crta `SubtitleStrip` ISPOD slike
              // (VideoPanel / jednostavni prikaz) — osim u fullscreenu, gdje
              // ispod slike nema ničega. `isFullscreen` mora čitati kontekst
              // ispod media_kitove rute, zato `Builder`.
              if (timeline != null)
                Positioned.fill(
                  child: Builder(
                    builder: (context) {
                      final below = subtitlesBelowPlayer(context) &&
                          !inRotated &&
                          !isFullscreen(context);
                      if (below) return const SizedBox.shrink();
                      return IgnorePointer(
                        child: _SubtitleOverlay(
                          player: widget.player,
                          timeline: timeline,
                          enabled: SubtitlesEnabled.instance,
                        ),
                      );
                    },
                  ),
                ),
              AdaptiveVideoControls(state),
              // „Uključi zvuk" preko slike dok traje muted autoplay. Iznad
              // kontrola jer mora primiti tap prije `playAndPauseOnTap`; kroz
              // `controls:` builder pa postoji i u fullscreen ruti.
              Positioned.fill(
                child: UnmuteOverlay(
                  onUnmuted: () {
                    if (!widget.player.state.playing) widget.player.play();
                  },
                ),
              ),
              // Oznaka plaćenog trenutka — iznad kontrola I iznad
              // `UnmuteOverlay` (koji preko cijele slike hvata tap), inače bi
              // tap na brand utišani autoplay pretvorio u „uključi zvuk". U
              // fullscreenu je gornji lijevi kut `_SpeakerBadge`, pa ide niže.
              if (widget.sponsoredMoments != null)
                Builder(
                  builder: (context) => Positioned(
                    top: inRotated || isFullscreen(context) ? 56 : 8,
                    left: 8,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: SponsoredMomentVideoBadge(
                        controller: widget.sponsoredMoments!,
                      ),
                    ),
                  ),
                ),
              // Iznad kontrola u Z-osi jer mora primiti tap — media_kitov
              // control layer inače proguta klik (playAndPauseOnTap).
              // Kroz `controls:` builder pa pilula postoji i u fullscreen ruti.
              if (undo != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 72,
                  child: Center(
                    child: SeekUndoPill(
                      undo: undo,
                      onUndo: widget.player.seek,
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fullscreen gumb — naš jer bira putanju A/B/C (T4). Vizualno je namjerno
// kopija media_kitovog `Material*FullscreenButton`: ista ikona, ista veličina
// (28 desktop / 24 mobile, kao defaulti njihove teme) i ista bijela boja.
// ---------------------------------------------------------------------------

class _FullscreenPathButton extends StatelessWidget {
  const _FullscreenPathButton({
    required this.onPressed,
    required this.forceExitIcon,
    required this.iconSize,
  });

  final VoidCallback onPressed;

  /// U našoj rotacijskoj ruti media_kit ne zna da je fullscreen (nije njegova
  /// ruta) pa `isFullscreen` javlja false — ikonu tada forsiramo.
  final bool forceExitIcon;

  final double iconSize;

  @override
  Widget build(BuildContext context) {
    // `isFullscreen` je media_kitov context-based helper — u njihovoj
    // fullscreen ruti javlja true, pa se ikona sama prebaci na „izlaz".
    final exiting = forceExitIcon || isFullscreen(context);
    return IconButton(
      onPressed: onPressed,
      icon: Icon(exiting ? Icons.fullscreen_exit : Icons.fullscreen),
      iconSize: iconSize,
      color: const Color(0xFFFFFFFF),
    );
  }
}

// ---------------------------------------------------------------------------
// CC gumb — dijeli ValueNotifier sa overlayem pa radi i u fullscreen ruti.
// ---------------------------------------------------------------------------

class _SubtitleToggleButton extends StatelessWidget {
  final ValueListenable<bool> enabled;
  final VoidCallback onToggle;

  const _SubtitleToggleButton({required this.enabled, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: enabled,
      builder: (context, on, _) => IconButton(
        icon: Icon(
          on ? Icons.closed_caption : Icons.closed_caption_off_outlined,
          color: Colors.white,
        ),
        tooltip: on ? l.mediaSubtitlesOff : l.mediaSubtitlesOn,
        onPressed: onToggle,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Subtitle overlay — YouTube stil: bottom-center, crna podloga, bijeli tekst.
// Renderira se kroz `controls` builder pa postoji i u fullscreen ruti.
// ---------------------------------------------------------------------------

TextStyle _subtitleStyle(double fontSize) =>
    TextStyle(fontSize: fontSize, height: 1.3, fontWeight: FontWeight.w500);

/// Najveći font ≤ [base] uz koji cijeli [text] stane u [maxWidth]×[maxHeight].
/// Donja granica 9 px: ispod toga titl ionako nije čitljiv, pa radije pusti da
/// prijeđe gornji rub nego da postane točkica.
@visibleForTesting
double fittingSubtitleFontSize(
  String text,
  double base, {
  required double maxWidth,
  required double maxHeight,
  TextScaler textScaler = TextScaler.noScaling,
}) => _fittingFontSize(
  text,
  base,
  maxWidth: maxWidth,
  maxHeight: maxHeight,
  textScaler: textScaler,
);

/// Zadnji izračuni po (tekst, okvir, skala). Position stream fira ~5×/s, a
/// isti cue traje sekundama — bez ovoga bi svaki tick ponovio do 15 layouta.
final Map<String, double> _fitCache = {};

double _fittingFontSize(
  String text,
  double base, {
  required double maxWidth,
  required double maxHeight,
  TextScaler textScaler = TextScaler.noScaling,
  TextStyle baseStyle = const TextStyle(),
}) {
  if (maxWidth <= 0 || maxHeight <= 0) return base;
  final key =
      '$base|${maxWidth.round()}|${maxHeight.round()}|'
      '${textScaler.scale(10)}|${baseStyle.fontFamily}|$text';
  final cached = _fitCache[key];
  if (cached != null) return cached;
  if (_fitCache.length > 64) _fitCache.clear();
  return _fitCache[key] = _measureFit(
    text,
    base,
    maxWidth: maxWidth,
    maxHeight: maxHeight,
    textScaler: textScaler,
    baseStyle: baseStyle,
  );
}

double _measureFit(
  String text,
  double base, {
  required double maxWidth,
  required double maxHeight,
  required TextScaler textScaler,
  required TextStyle baseStyle,
}) {
  var size = base;
  while (size > 9) {
    final tp = TextPainter(
      // Isti stil kao `Text` u overlayu: on spaja DefaultTextStyle (Inter iz
      // teme) s našim — mjerenje bez fonta teme daje krivi broj redaka.
      text: TextSpan(text: text, style: baseStyle.merge(_subtitleStyle(size))),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: maxWidth);
    final fits = tp.height <= maxHeight;
    tp.dispose();
    if (fits) return size;
    size -= 1;
  }
  return 9;
}

class _SubtitleOverlay extends StatelessWidget {
  final Player player;
  final SpeakerTimeline timeline;
  final ValueListenable<bool> enabled;

  const _SubtitleOverlay({
    required this.player,
    required this.timeline,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: enabled,
      builder: (context, on, _) {
        if (!on) return const SizedBox.shrink();
        // Zatvoren bočni panel (TickerMode off): titl se ionako ne vidi,
        // pa ne trošimo layout teksta.
        if (!TickerMode.valuesOf(context).enabled) {
          return const SizedBox.shrink();
        }
        return CaptionClock(
          player: player,
          keyOf: (ms) {
            final cue = timeline.cueAt(Duration(milliseconds: ms));
            return cue == null
                ? null
                : (identityHashCode(cue), cue.activeWordAt(ms));
          },
          builder: (context, ms) {
            final cue = timeline.cueAt(Duration(milliseconds: ms));
            if (cue == null || cue.text.isEmpty) {
              return const SizedBox.shrink();
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                // Font skalira s veličinom playera: mali panel ~13px,
                // fullscreen 1080p ~24px — kao YouTube auto-size.
                final baseFont = (constraints.maxWidth * 0.022).clamp(
                  12.0,
                  24.0,
                );
                final bottomPad =
                    (constraints.maxHeight * 0.06).clamp(8.0, 54.0) + 30;
                final boxWidth = constraints.maxWidth * 0.88;
                // Titl se NIKAD ne reže: korisnici čitaju dok slušaju, pa je
                // puni tekst važniji od slike koju prekrije. Raste prema gore
                // od istog sidra iznad trake; tek ako ni tako ne stane u
                // player (mali panel, dugačak cue), smanjuje se font.
                final fontSize = _fittingFontSize(
                  cue.text,
                  baseFont,
                  maxWidth: boxWidth - 20,
                  maxHeight: constraints.maxHeight - bottomPad - 8 - 10,
                  textScaler: MediaQuery.textScalerOf(context),
                  baseStyle: DefaultTextStyle.of(context).style,
                );
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    // Tik iznad bottom control bara — YouTube pozicija (~10%
                    // od dna), skalira s visinom playera umjesto fiksnog 12%+36
                    // koji je na malom side-panelu gurao titl u sredinu slike.
                    padding: EdgeInsets.only(
                      bottom: bottomPad,
                      left: 12,
                      right: 12,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: boxWidth),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(190),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        // Isticanje mijenja samo boju, pa izračun fonta nad
                        // golim tekstom vrijedi i za obojeni.
                        child: Text.rich(
                          captionSpan(
                            cue.tokens,
                            from: 0,
                            to: cue.tokens.length,
                            active: cue.activeWordAt(ms),
                            style: _subtitleStyle(fontSize),
                            colors: CaptionColors(
                              spoken: Colors.white,
                              upcoming: Colors.white.withAlpha(170),
                              activeText: Colors.white,
                              activeFill: Theme.of(
                                context,
                              ).colorScheme.tertiary,
                            ),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Speaker badge u fullscreen top baru (bivši _FullscreenSpeakerLabel iz
// video_panel.dart — premješten ovamo da ga dobije i simple screen).
// ---------------------------------------------------------------------------

class _SpeakerBadge extends StatelessWidget {
  final Player player;
  final SpeakerTimeline speakerTimeline;
  final List<SummarySpeaker> speakers;
  final Map<String, Color> speakerColors;

  const _SpeakerBadge({
    required this.player,
    required this.speakerTimeline,
    required this.speakers,
    required this.speakerColors,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      builder: (context, snapshot) {
        final pos = snapshot.data ?? Duration.zero;
        final speakerId = speakerTimeline.speakerAt(pos);
        if (speakerId == null) return const SizedBox.shrink();

        SummarySpeaker? speaker;
        for (final s in speakers) {
          if (s.id == speakerId) {
            speaker = s;
            break;
          }
        }
        if (speaker == null) return const SizedBox.shrink();

        final color = speakerColors[speakerId] ?? Colors.white;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              // Anonymous host (suggested_name == role) → samo roleLabel
              // umjesto duplog "Voditelj voditelj".
              if (speaker.displayName != null) ...[
                Text(
                  speaker.displayName!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (speaker.roleLabel.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text(
                    '· ${speaker.roleLabel}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ] else
                Text(
                  speaker.roleLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
