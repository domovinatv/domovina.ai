/// Web implementacija muteanja — `<video>.muted`, ne `volume`.
///
/// Zašto ne `player.setVolume(0)`: na iOS-u `HTMLMediaElement.volume` NIJE
/// zapisiv (setter je no-op, getter uvijek vraća 1) jer Apple glasnoću drži
/// pod fizičkim tipkama uređaja. media_kit `setVolume` usput još i **skida**
/// `muted` flag prije nego postavi `volume`, pa je na iPhoneu efekt točno
/// suprotan od željenog — element ostane nemutiran i browser odbije autoplay.
///
/// `muted` property radi na svim browserima i jedini je koji WebKit gleda u
/// autoplay provjeri.
library;

import 'package:media_kit/media_kit.dart';

import 'media_element_web.dart';

/// Postavlja `muted` na video element. Vraća `false` ako element nije nađen —
/// pozivatelj tada pada na `player.setVolume` (radi svugdje osim na iOS-u).
bool setElementMuted(Player player, bool muted) {
  final el = videoElementOf(player);
  if (el == null) return false;
  el.muted = muted;
  return true;
}

/// Stvarno stanje elementa; `null` ako element nije nađen.
bool? elementMuted(Player player) => videoElementOf(player)?.muted;
