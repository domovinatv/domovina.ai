/// Undo nakon ručnog skoka po timelineu — „vrati me gdje sam bio".
///
/// Uvedeno 2026-07-27 (plan `docs/plans/2026-07-27-playback-overhaul.md`) jer
/// slučajan swipe po seek baru nepovratno briše podatak dokle je korisnik
/// stigao: nema povijesti, a `watch_progress` je već prepisan.
///
/// Zašto stream, a ne omatanje naših slidera: seek ide kroz najmanje pet
/// putanja bez zajedničkog callbacka (`_SeekBar.onChangeEnd` u
/// `video_panel.dart`, slider u `episode_simple_screen.dart`,
/// `seekOnDoubleTap` unutar media_kita, tipkovničke kratice J/L/←/→ u
/// `episode_video.dart`, `seekto` s lock screena). Jedini izvor istine koji
/// hvata SVE putanje je `player.stream.position` — isti zaključak i isto
/// rješenje kao za pauzu u `services/playback_intent.dart`.
///
/// **Pametni povratak (od 16. 11. 2026.)**: ponuda više nije „poništi zadnji
/// skok u 8 s", nego „nastavi gdje si GLEDAO". Korisnik koji u trosatnom
/// podcastu stigne do 1:23:45 pa skače po poglavljima da vidi što je
/// zanimljivo mora se moći vratiti na 1:23:45 i nakon pet skokova i minute
/// razgledavanja. Zato:
///
///  - **mjesto gledanja** je pozicija gdje je korisnik neprekidno gledao barem
///    [settleMin] (ili kamo ga je doveo resume / deep link / sam povratak);
///    sekunde razgledavanja to nisu;
///  - prvi skok s mjesta gledanja otvara ponudu; svi sljedeći skokovi (scrub,
///    ±10 s, tap na poglavlje, sponzorski gumb) drže TO sidro;
///  - ponuda je prvih [fresh] velika pilula, zatim mali chip (vidi
///    [SeekOffer.fresh]) — ne nestaje sama dok korisnik razgledava;
///  - gasi se kad se korisnik smiri na novom mjestu ([exploreSettle]
///    neprekidne reprodukcije), kad se sam vrati blizu sidra, kad dođe do
///    sidra prirodnim tijekom, kad je prihvati ili odbaci.
///
/// Odluka D2 („tap na poglavlje ne nudi Undo") je time napuštena: upravo
/// skakanje po poglavljima je slučaj u kojem povratak najviše treba.
///
/// [suppress] ostaje za skokove koji NISU razgledavanje: resume pri
/// otvaranju, nova sekunda iz URL-a, sam povratak. Takav skok gasi zatečenu
/// ponudu i odredište mu je odmah mjesto gledanja.
///
/// Čista logika bez ovisnosti na `media_kit` (prima stream, ne Player) da bude
/// unit-testabilna — vidi `test/seek_undo_test.dart`.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

/// Trenutna ponuda povratka.
@immutable
class SeekOffer {
  /// Kamo se vraća.
  final Duration target;

  /// `true` prvih [SeekUndo.fresh] nakon zadnjeg skoka → velika pilula;
  /// poslije mali chip, da ne prekriva video dok korisnik razgledava.
  final bool fresh;

  const SeekOffer(this.target, {required this.fresh});

  @override
  bool operator ==(Object other) =>
      other is SeekOffer && other.target == target && other.fresh == fresh;

  @override
  int get hashCode => Object.hash(target, fresh);
}

class SeekUndo {
  /// [positionStream] umjesto samog Playera → testabilno bez media_kita
  /// (u testu običan StreamController).
  ///
  /// [jumpThreshold] mora ostati znatno iznad prirodnog pomaka između dva
  /// eventa: `player.stream.position` fira ~5×/s, pa je pri brzini 2,0×
  /// prirodni korak ~0,4 s. Dvije sekunde su sigurne; ne spuštati ispod 1 s.
  SeekUndo({
    required Stream<Duration> positionStream,
    this.jumpThreshold = const Duration(seconds: 2),
    this.fresh = const Duration(seconds: 8),
    this.settleMin = const Duration(seconds: 15),
    this.exploreSettle = const Duration(minutes: 2),
    this.nearAnchor = const Duration(seconds: 10),
  }) {
    _sub = positionStream.listen(_onPosition);
  }

  final Duration jumpThreshold;

  /// Koliko je ponuda „svježa" (velika pilula) nakon zadnjeg skoka.
  final Duration fresh;

  /// Neprekidna reprodukcija nakon koje je pozicija mjesto gledanja.
  final Duration settleMin;

  /// Neprekidna reprodukcija na novom mjestu nakon koje razgledavanje
  /// završava — korisnik je našao što ga zanima, ponuda se gasi.
  final Duration exploreSettle;

  /// Ručni skok na manje od ovoga od sidra = korisnik se sam vratio.
  final Duration nearAnchor;

  StreamSubscription<Duration>? _sub;

  /// Aktivan dok je prozor tolerancije otvoren.
  Timer? _suppressTimer;

  /// Prebacuje svježu ponudu u chip.
  Timer? _freshTimer;

  Duration? _lastPosition;

  /// Zadnje potvrđeno mjesto gledanja (prati reprodukciju dok se gleda).
  Duration? _watchPoint;

  /// Neprekidna reprodukcija od zadnjeg skoka.
  Duration _run = Duration.zero;

  /// Trenutni odsječak počinje programskim skokom kojem vjerujemo (resume,
  /// deep link, povratak) — mjesto gledanja je odmah, bez [settleMin].
  bool _trustedRun = false;

  final ValueNotifier<SeekOffer?> _offer = ValueNotifier<SeekOffer?>(null);
  final ValueNotifier<Duration?> _undoTarget = ValueNotifier<Duration?>(null);

  /// Ponuda (cilj + je li svježa), ili `null`.
  ValueListenable<SeekOffer?> get offer => _offer;

  /// Pozicija na koju povratak vodi, ili `null` kad ponude nema.
  ValueListenable<Duration?> get undoTarget => _undoTarget;

  /// Otvori prozor tolerancije NEPOSREDNO prije programskog seeka koji NIJE
  /// razgledavanje (resume, nova sekunda iz URL-a, sam povratak). Skok unutar
  /// prozora gasi zatečenu ponudu i odredište postaje mjesto gledanja.
  ///
  /// Ponovni poziv restarta prozor.
  void suppress({Duration window = const Duration(milliseconds: 1200)}) {
    _suppressTimer?.cancel();
    _suppressTimer = Timer(window, () {});
  }

  /// Korisnik je prihvatio ponudu. Gasi je i otvara prozor tolerancije, jer
  /// seek koji pozivatelj odmah izvodi inače proizvede novu ponudu.
  void consume() {
    _clearOffer();
    suppress();
  }

  /// Korisnik je odbacio ponudu (✕): ostaje gdje jest. Mjesto gledanja se
  /// gradi iznova od trenutne pozicije.
  void dismiss() {
    _clearOffer();
    _watchPoint = null;
  }

  void _onPosition(Duration position) {
    final last = _lastPosition;
    _lastPosition = position;
    if (last == null) {
      // Prvo što stigne nakon otvaranja je već resume pozicija.
      _run = Duration.zero;
      _trustedRun = true;
      _watchPoint = position;
      return;
    }

    final delta = position - last;
    if (delta.abs() <= jumpThreshold) {
      _onNatural(last, position, delta);
      return;
    }

    // Skok. Buffering stall ne pomiče poziciju pa ovamo ni ne dolazi.
    _run = Duration.zero;

    if (_suppressTimer?.isActive ?? false) {
      _clearOffer();
      _trustedRun = true;
      _watchPoint = position;
      return;
    }
    _trustedRun = false;

    final current = _offer.value;
    if (current != null) {
      // Korisnik se sam vratio na sidro — ponuda je ispunjena.
      if ((position - current.target).abs() <= nearAnchor) {
        _clearOffer();
        _watchPoint = position;
        _trustedRun = true;
        return;
      }
      // Razgledavanje se nastavlja: isto sidro, opet svježe.
      _setOffer(current.target);
      return;
    }

    // Prvi skok s mjesta gledanja. Ako je korisnik upravo gledao (odsječak je
    // „smiren"), sidro je točna pozicija prije skoka; inače zadnje potvrđeno
    // mjesto gledanja (npr. resume pa odmah skok).
    final anchor = _watchPoint;
    if (anchor == null) return;
    _setOffer(anchor);
  }

  void _onNatural(Duration last, Duration position, Duration delta) {
    if (delta > Duration.zero) _run += delta;

    final current = _offer.value;
    if (current != null) {
      // Prirodnim tijekom stigao do sidra (skočio unatrag pa gledao dalje).
      if (last < current.target && position >= current.target) {
        _clearOffer();
        _watchPoint = position;
        return;
      }
      // Smirio se na novom mjestu — razgledavanje je gotovo.
      if (_run >= exploreSettle) {
        _clearOffer();
        _watchPoint = position;
      }
      return;
    }

    if (_trustedRun || _run >= settleMin) _watchPoint = position;
  }

  void _setOffer(Duration target) {
    _offer.value = SeekOffer(target, fresh: true);
    _undoTarget.value = target;
    _freshTimer?.cancel();
    _freshTimer = Timer(fresh, () {
      final o = _offer.value;
      if (o != null) _offer.value = SeekOffer(o.target, fresh: false);
    });
  }

  void _clearOffer() {
    _freshTimer?.cancel();
    _freshTimer = null;
    _offer.value = null;
    _undoTarget.value = null;
  }

  void dispose() {
    _suppressTimer?.cancel();
    _suppressTimer = null;
    _freshTimer?.cancel();
    _freshTimer = null;
    _sub?.cancel();
    _sub = null;
    _offer.dispose();
    _undoTarget.dispose();
  }
}
