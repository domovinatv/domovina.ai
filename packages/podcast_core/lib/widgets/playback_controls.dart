/// Dijeljene kontrole reprodukcije — brzina, pozadinska reprodukcija i pilula
/// „poništi skok".
///
/// Zašto zajednička datoteka a ne inline u playeru: iste tri kontrole moraju
/// postojati na tri mjesta (media_kit control bar u `episode_video.dart`, red
/// kontrola u `video_panel.dart`, `_PlayerTab` u `episode_simple_screen.dart`)
/// — uključujući **audio-only** epizode, gdje `EpisodeVideo` uopće ne postoji
/// (`AudioPoster` putanja). Plan: `docs/plans/2026-07-27-playback-overhaul.md`.
///
/// Widgeti NE dohvaćaju ekranski state: brzina i pozadinska reprodukcija su
/// globalni singletoni (uređaj), a `SeekUndo` i seek callback dolaze kao
/// parametri od ekrana koji drži `Player`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:floating/floating.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../l10n/app_localizations.dart';
import '../services/background_playback.dart';
import '../services/playback_speed.dart';
import '../services/player_mute.dart';
import '../services/seek_undo.dart';
import '../theme/app_theme.dart';

/// Kontrole žive i preko videa (media_kit control bar, tamni scrim neovisan o
/// temi) i u običnom panelu na površini teme. Boja se bira ovim flagom umjesto
/// da pozivatelj hardkodira konstantu.
///
/// `onVideo: true` → bijela, kao ostali media_kit gumbi u istoj traci
/// (`_SubtitleToggleButton` u `episode_video.dart`).
Color _controlColor(BuildContext context, bool onVideo) =>
    onVideo ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant;

/// `1:12:03` / `4:07` — isti oblik kao `ResumeHintBanner`, da dvije pilule u
/// istom ekranu pišu vrijeme jednako.
String formatPlaybackTime(Duration d) {
  final total = d.isNegative ? Duration.zero : d;
  final h = total.inHours;
  final m = total.inMinutes % 60;
  final s = total.inSeconds % 60;
  String p(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${p(m)}:${p(s)}' : '$m:${p(s)}';
}

/// `1` / `1,25` — sama brojka, bez `×`. Decimalni separator ide kroz
/// `NumberFormat` jer hrvatski traži zarez, a engleski točku. Cijeli broj se
/// piše bez `,0` (YouTube stil).
///
/// Odvojeno od [formatPlaybackRate] jer ARB ključ `mediaPlaybackSpeedSet` već
/// nosi svoj `×` („Brzina: {rate}×") — ubacivanje već ozvjezdane brzine dalo bi
/// „Brzina: 1,25××".
String formatPlaybackRateNumber(double rate, String localeName) {
  final f = NumberFormat.decimalPattern(localeName)
    ..minimumFractionDigits = 0
    ..maximumFractionDigits = 2;
  return f.format(rate);
}

/// `1×` / `1,25×` — vizualni label gumba.
String formatPlaybackRate(double rate, String localeName) =>
    '${formatPlaybackRateNumber(rate, localeName)}×';

// ---------------------------------------------------------------------------
// Brzina reprodukcije
// ---------------------------------------------------------------------------

/// Kružni prekidač brzine (1,0× → 1,25× → 1,5× → 1,75× → 2,0× → 1,0×) —
/// tekstualni gumb koji piše trenutnu brzinu, kao na YouTubeu.
///
/// Sam sprema izbor u [PlaybackSpeed] (globalno za uređaj, odluka D1);
/// [onChanged] je za pozivatelja koji brzinu mora odmah primijeniti na svoj
/// `Player` (`player.setRate`) — ekran se svejedno pretplaćuje na singleton pa
/// je callback samo prečac, ne jedini put.
class SpeedCycleButton extends StatelessWidget {
  const SpeedCycleButton({
    super.key,
    this.onVideo = false,
    this.onChanged,
  });

  /// Renderira se preko videa (bijela boja) umjesto na površini teme.
  final bool onVideo;

  /// Zove se s novom brzinom nakon tapa.
  final ValueChanged<double>? onChanged;

  void _cycle() {
    final next = PlaybackSpeed.instance.nextRate;
    PlaybackSpeed.instance.setRate(next);
    onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final color = _controlColor(context, onVideo);

    return ListenableBuilder(
      listenable: PlaybackSpeed.instance,
      builder: (context, _) {
        final number = formatPlaybackRateNumber(
          PlaybackSpeed.instance.rate,
          l.localeName,
        );
        final label = '$number×';
        return Semantics(
          button: true,
          // Bez `×` — ključ ga već ima u sebi.
          label: l.mediaPlaybackSpeedSet(number),
          child: Tooltip(
            message: l.mediaPlaybackSpeed,
            child: TextButton(
              onPressed: _cycle,
              style: TextButton.styleFrom(
                foregroundColor: color,
                // Uska traka kontrola: gumb mora biti gust kao IconButton
                // susjedi, ali i dalje ≥48 dp dodirna meta (Material).
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Zvuk (mute / unmute)
// ---------------------------------------------------------------------------

/// Prekidač zvuka — jedini izlaz iz muted autoplaya na dodirnim uređajima.
///
/// media_kitova **mobilna** traka namjerno nema volume gumb (na telefonu
/// glasnoću drže fizičke tipke), a `MaterialDesktopVolumeButton` postoji samo
/// u desktop varijanti. Kad browser padne na muted autoplay, na mobitelu je
/// zato prije ovoga postojao mrtav player: slika se vrti, zvuka nema, a ništa
/// u UI-ju ne nudi unmute. Vidi [PlayerMute].
///
/// Kad je mute nametnuo browser ([PlayerMute.autoplayBlocked]), gumb dobiva
/// popunjeni brand tretman — nije to običan toggle nego jedina radnja koja
/// epizodi vraća zvuk.
class MuteToggleButton extends StatelessWidget {
  const MuteToggleButton({super.key, this.onVideo = false});

  /// Renderira se preko videa (bijela boja) umjesto na površini teme.
  final bool onVideo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return ListenableBuilder(
      listenable: PlayerMute.instance,
      builder: (context, _) {
        final mute = PlayerMute.instance;
        final muted = mute.muted;
        final highlight = mute.autoplayBlocked;
        return IconButton(
          icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
          tooltip: muted ? l.mediaBoostVolume : l.mediaMute,
          style: highlight
              ? IconButton.styleFrom(
                  backgroundColor: AppTheme.brandPrimary,
                  foregroundColor: Colors.white,
                  side: AppTheme.brandRim(theme.brightness),
                )
              : IconButton.styleFrom(
                  foregroundColor: _controlColor(context, onVideo),
                ),
          onPressed: () => mute.setMuted(!muted),
        );
      },
    );
  }
}

/// Puni „Uključi zvuk" CTA preko slike, vidljiv samo dok traje muted autoplay.
///
/// Ide u `Positioned.fill` iznad video površine u `Stack`-u; sam se ukloni čim
/// korisnik uključi zvuk (ili ga sam ugasi gumbom — tada je
/// [PlayerMute.autoplayBlocked] već obrisan pa se CTA ne vraća). Dok je
/// nevidljiv ne hvata dodire (prazan `SizedBox` ne sudjeluje u hit testu), pa
/// tap na video i dalje pauzira kao inače.
class UnmuteOverlay extends StatelessWidget {
  const UnmuteOverlay({super.key, this.onUnmuted});

  /// Zove se nakon uključivanja zvuka — ekran tu obično osigura da svira
  /// (tap je ujedno i user gesture koji browser traži).
  final VoidCallback? onUnmuted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return ListenableBuilder(
      listenable: PlayerMute.instance,
      builder: (context, _) {
        if (!PlayerMute.instance.autoplayBlocked) {
          return const SizedBox.shrink();
        }
        return GestureDetector(
          onTap: () async {
            await PlayerMute.instance.setMuted(false);
            onUnmuted?.call();
          },
          child: Container(
            color: Colors.black54,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppTheme.brandPrimary,
                      shape: BoxShape.circle,
                      border: Border.fromBorderSide(
                        AppTheme.brandRim(theme.brightness),
                      ),
                    ),
                    child: const Icon(
                      Icons.volume_up,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l.mediaBoostVolume,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Reprodukcija u pozadini
// ---------------------------------------------------------------------------

/// Prekidač „nastavi svirati kad izađem iz aplikacije" u samom playeru.
///
/// Isti singleton kao prekidač na `/account` (odluka D5: dva ulaza, jedna
/// postavka) — kontekstualna odluka („sad idem u džep") ne traži se u
/// postavkama. SnackBar je ovdje dopušten jer je potvrda korisnikove radnje,
/// ne nudge (vidi Rule o nudgeovima u CLAUDE.md).
class BackgroundPlaybackButton extends StatelessWidget {
  const BackgroundPlaybackButton({super.key, this.onVideo = false});

  /// Renderira se preko videa (bijela boja) umjesto na površini teme.
  final bool onVideo;

  void _toggle(BuildContext context, bool enabled) {
    final l = AppLocalizations.of(context);
    final next = !enabled;
    BackgroundPlayback.instance.setEnabled(next);
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            next
                ? l.mediaBackgroundPlaybackToastOn
                : l.mediaBackgroundPlaybackToastOff,
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final color = _controlColor(context, onVideo);

    return ListenableBuilder(
      listenable: BackgroundPlayback.instance,
      builder: (context, _) {
        final enabled = BackgroundPlayback.instance.enabled;
        return IconButton(
          icon: Icon(
            enabled ? Icons.headset : Icons.headset_off,
            color: color,
          ),
          tooltip: enabled
              ? l.mediaBackgroundPlaybackTooltipOn
              : l.mediaBackgroundPlaybackTooltipOff,
          onPressed: () => _toggle(context, enabled),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Picture-in-Picture
// ---------------------------------------------------------------------------

/// `floating` ima samo Android implementaciju. Na iOS-u i macOS-u svaki
/// poziv baca `MissingPluginException` — do v2.0.182 je to bila nehvaćena
/// iznimka pri svakom otvaranju epizode na iPhoneu (uhvatio smoke test
/// 13.10.2026., `integration_test/smoke_test.dart`).
bool get pipPluginSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

class PictureInPictureButton extends StatelessWidget {
  const PictureInPictureButton({super.key, this.onVideo = false});

  final bool onVideo;

  void _toggle(BuildContext context) async {
    if (!pipPluginSupported) return;
    final floating = Floating();
    if (await floating.isPipAvailable) {
      floating.enable(const ImmediatePiP(aspectRatio: Rational.landscape()));
    } else {
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Picture-in-Picture nije podržan na ovom uređaju.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!pipPluginSupported) return const SizedBox.shrink();

    final color = _controlColor(context, onVideo);

    return FutureBuilder<bool>(
      future: Floating().isPipAvailable,
      builder: (context, snapshot) {
        // Sakrij gumb ako PiP nije podržan (npr. iOS trenutno ili stari Android)
        if (snapshot.data != true) {
          return const SizedBox.shrink();
        }
        return IconButton(
          icon: Icon(Icons.picture_in_picture_alt, color: color),
          tooltip: 'Picture in Picture',
          onPressed: () => _toggle(context),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Undo skoka
// ---------------------------------------------------------------------------

/// `↺ Natrag na 1:12:03` — ponuda povratka nakon ručnog skoka po timelineu
/// (scrub/swipe ili dvoklik ±10 s). Tap na poglavlje je namjerna navigacija i
/// pilulu NE pali — to rješava `SeekUndo.suppress()` na strani ekrana (D2).
///
/// Ponuda dolazi i nestaje sama (TTL u [SeekUndo]); ovdje je samo fade.
/// Stil je posuđen od `ResumeHintBanner` da dvije pilule u istom ekranu
/// izgledaju kao ista obitelj — razlika je što je ova interaktivna.
class SeekUndoPill extends StatelessWidget {
  const SeekUndoPill({
    super.key,
    required this.undo,
    required this.onUndo,
  });

  /// Izvor ponude; pilula sluša [SeekUndo.undoTarget].
  final SeekUndo undo;

  /// Sam seek radi pozivatelj (on drži `Player`). Prozor tolerancije oko tog
  /// seeka ne treba otvarati ručno — `SeekUndo.consume()` ga otvori sam.
  final ValueChanged<Duration> onUndo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return ValueListenableBuilder<Duration?>(
      valueListenable: undo.undoTarget,
      builder: (context, target, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: target == null
            ? const SizedBox.shrink()
            : Material(
                key: ValueKey<Duration>(target),
                elevation: 4,
                borderRadius: BorderRadius.circular(24),
                color: theme.colorScheme.inverseSurface,
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () {
                    // Ponuda se gasi odmah, prije seeka — inače bi drugi tap
                    // stigao na već potrošenu ponudu.
                    undo.consume();
                    onUndo(target);
                  },
                  child: Tooltip(
                    message: l.mediaSeekUndoTooltip,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.undo,
                            size: 18,
                            color: theme.colorScheme.onInverseSurface,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l.mediaSeekUndo(formatPlaybackTime(target)),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onInverseSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
