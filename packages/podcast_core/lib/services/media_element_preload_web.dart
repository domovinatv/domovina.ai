import 'dart:js_interop';

import 'package:media_kit/media_kit.dart';
import 'package:web/web.dart' as web;

/// `preload="auto"` na `<video>` elementu playera, PRIJE `open`.
///
/// media_kit ne postavlja `preload`, pa Chrome za pauziran element izvan DOM-a
/// skine samo zaglavlje i stane; ostatak traži tek nakon `play()`. Za
/// [PlayerPreload] (element se otvara sekundama prije nego ga ekran montira)
/// to znači drugi range zahtjev na kritičnom putu.
///
/// Samo kroz media_kitovo polje `element` — bez DOM fallbacka iz
/// `videoElementOf`, jer bi on mogao dohvatiti `<video>` druge epizode koja
/// je još montirana ispod.
void preloadWholeMedia(Player player) {
  try {
    final el = (player.platform as dynamic).element as JSAny?;
    if (el != null && el.isA<web.HTMLVideoElement>()) {
      (el as web.HTMLVideoElement).preload = 'auto';
    }
  } catch (_) {}
}
