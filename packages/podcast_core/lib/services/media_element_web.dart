/// Dohvat `<video>` elementa iza media_kitovog web playera.
///
/// Dijele ga mute (`media_element_mute_web.dart`) i cast na televizor
/// (`remote_playback_web.dart`) — oba moraju dirati pravi element jer
/// media_kit ni `muted` ni Remote Playback ne izlaže.
library;

import 'dart:js_interop';

import 'package:media_kit/media_kit.dart';
import 'package:web/web.dart' as web;

/// media_kitov `WebPlayer` drži javno polje `element` (HTMLVideoElement), ali
/// tip nije izvezen iz `package:media_kit/media_kit.dart` — do njega se dolazi
/// samo dinamički. Fallback je jedini `<video>` u dokumentu: naši ekrani drže
/// točno jedan media_kit player, a YouTube embed je cross-origin iframe pa se
/// njegov `<video>` ovdje uopće ne vidi.
web.HTMLVideoElement? videoElementOf(Player player) {
  try {
    final el = (player.platform as dynamic).element as JSAny?;
    if (el != null && el.isA<web.HTMLVideoElement>()) {
      return el as web.HTMLVideoElement;
    }
  } catch (_) {
    // Drukčija implementacija / promijenjen API — padamo na DOM pretragu.
  }
  final nodes = web.document.querySelectorAll('video');
  if (nodes.length == 1) {
    final node = nodes.item(0);
    if (node != null && node.isA<web.HTMLVideoElement>()) {
      return node as web.HTMLVideoElement;
    }
  }
  return null;
}
