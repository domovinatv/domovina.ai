/// Reprodukcija na televizoru iz preglednika — AirPlay (Safari) i Remote
/// Playback API (Chrome na Androidu → Google Cast).
///
/// Oba puta predaju televizoru URL koji `<video>` već svira; televizor medij
/// vuče sam s CDN-a, a lokalni element ostaje „daljinski": play/pause/seek na
/// njemu idu na televizor, i `timeupdate` dolazi s televizora. Zato ovdje nema
/// vlastitog stanja pozicije — media_kitovi streamovi ostaju izvor istine.
/// Plan i mjerenja: `docs/plans/2026-10-17-cast-na-tv.md` (iteracija B).
///
/// Singleton iz istog razloga kao [PlayerMute]: isti gumb crtaju tri stabla
/// (video traka, `VideoPanel`, `_PlayerTab`). Native (iOS/Android/macOS) ovdje
/// uvijek javlja „nema uređaja" — native Cast i AirPlay su zasebne iteracije.
library;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../src/log.dart' show log;
import 'remote_playback_web.dart'
    if (dart.library.io) 'remote_playback_stub.dart'
    as platform;

/// Kamo preglednik zna poslati video.
enum RemoteTarget { airPlay, cast }

/// Stanje veze s televizorom (preslikava `RemotePlayback.state`).
enum RemoteState { disconnected, connecting, connected }

class RemotePlayback extends ChangeNotifier {
  RemotePlayback._();

  static final RemotePlayback instance = RemotePlayback._();

  Player? _player;
  VoidCallback? _unbind;
  RemoteTarget? _target;
  RemoteState _state = RemoteState.disconnected;

  /// Dostupan cilj, ili `null` kad u mreži nema uređaja (gumb se tada ne crta).
  RemoteTarget? get target => _target;

  RemoteState get state => _state;

  /// Veže se na novootvoreni player. Zove [openAndResume], kao [PlayerMute].
  void attach(Player player) {
    _unbind?.call();
    _player = player;
    _target = null;
    _state = RemoteState.disconnected;
    _unbind = platform.bindRemotePlayback(
      player,
      onTarget: (target) {
        if (target == _target) return;
        _target = target;
        log('RemotePlayback: target=${target?.name}');
        notifyListeners();
      },
      onState: (state) {
        if (state == _state) return;
        _state = state;
        log('RemotePlayback: state=${state.name}');
        notifyListeners();
      },
    );
    notifyListeners();
  }

  /// Odvezuje se samo ako je [player] doista vezani (vidi [PlayerMute.detach]).
  void detach(Player player) {
    if (!identical(_player, player)) return;
    _unbind?.call();
    _unbind = null;
    _player = null;
    _target = null;
    _state = RemoteState.disconnected;
    notifyListeners();
  }

  /// Otvara sistemski izbornik uređaja. Mora pasti unutar korisnikovog tapa —
  /// i Safari i Chrome bez geste odbiju prompt.
  Future<void> prompt() async {
    final p = _player;
    if (p == null) return;
    try {
      await platform.promptRemotePlayback(p);
    } catch (e) {
      // Korisnik je zatvorio izbornik (`NotAllowedError`) ili uređaj je u
      // međuvremenu nestao — nije greška koju treba pokazati.
      log('RemotePlayback.prompt: $e');
    }
  }
}
