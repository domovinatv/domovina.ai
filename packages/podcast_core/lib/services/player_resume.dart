/// Pouzdan open + resume-seek za media_kit player.
///
/// Pozadina: na native (iOS/Android libmpv) putanji seek pozvan ODMAH nakon
/// `open()` se često odbaci — demuxer još nema duration / prvi frame, pa libmpv
/// ignorira seek i playback ostane na 0. (Web je bio manje pogođen jer je već
/// otvarao pauzirano, ali isti race vrijedi.) Rezultat: "resume kreće od
/// početka". Fix: otvori pauzirano → pričekaj da duration postane poznat →
/// seek → play. Vidi watch_progress_service.dart.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:media_kit/media_kit.dart';

import 'player_mute.dart';
import 'remote_playback.dart';

/// Otvara [uri] i, ako je [startAtSeconds] zadan, pouzdano seeka na tu poziciju
/// prije play-a. Vraća `true` ako je unmuted autoplay uspio; `false` ako je
/// browser odbio pa smo pali na muted autoplay (samo web — na native uvijek
/// `true`).
///
/// Stanje muteanja se NE vraća pozivatelju kroz parametre nego živi u
/// [PlayerMute] singletonu — vidi tamošnji doc zašto.
Future<bool> openAndResume(
  Player player, {
  required String uri,
  int? startAtSeconds,
}) async {
  PlayerMute.instance.attach(player);
  RemotePlayback.instance.attach(player);
  await player.open(Media(uri), play: false);

  if (startAtSeconds != null && startAtSeconds > 0) {
    // Seek mora pričekati da demuxer javi duration, inače ga libmpv odbaci.
    // Ako je duration već poznat (npr. brza interna nav s keširanim resursom),
    // ne čekamo stream. Timeout je safety net — seekamo svejedno nakon 5s.
    if (player.state.duration.inMilliseconds <= 0) {
      await player.stream.duration
          .firstWhere((d) => d.inMilliseconds > 0)
          .timeout(const Duration(seconds: 5), onTimeout: () => Duration.zero);
    }
    await player.seek(Duration(seconds: startAtSeconds));
  }

  // Pokušaj unmuted autoplay. Browser ga smije odbiti — Chromium traži da je
  // korisnik već kliknuo/tapnuo po domeni u toj sesiji (ili MEI prag na
  // desktopu), WebKit traži `muted` element. Hladno otvoren share link nema ni
  // jedno ni drugo → fallback na muted autoplay.
  try {
    await player.play();
  } catch (_) {
    await PlayerMute.instance.muteForAutoplay();
    await player.play();
    return false;
  }

  if (kIsWeb) {
    // Tihi fail bez exceptiona — provjeri playing state nakon kratke pauze.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!player.state.playing) {
      await PlayerMute.instance.muteForAutoplay();
      await player.play();
      return false;
    }
  }

  return true;
}
