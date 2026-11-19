import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../src/log.dart' show log;
import 'media_element_preload_stub.dart'
    if (dart.library.js_interop) 'media_element_preload_web.dart';

/// Player koji ekran epizode otvori čim zna URL medije (odmah nakon
/// `episode.json`), dok se ostatak `EpisodeData` još učitava i parsira.
/// Otvoren je s `play: false`: preglednik / libmpv skida zaglavlje i prvi
/// fragment, ali ništa ne svira dok ga sadržaj ekrana ne preuzme ([take]).
///
/// Izmjereno 19.11.2026. (Fast 4G, CPU 4×): bez ovoga `video.src` dolazi
/// ~2,6 s nakon `episode.json`, jer `_initVideo` čeka sve artefakte, parsing i
/// build članka. Vidi `docs/2026-11-19-prvi-frame-videa-kriticni-put.md`.
///
/// **Vlasništvo**: dok ga nitko nije preuzeo, player pripada onome tko je
/// stvorio [PlayerPreload] i taj ga zatvara kroz [dispose]. Nakon [take]
/// vlasnik je pozivatelj [take]-a, a [dispose] ga više ne dira.
///
/// **Ništa globalno prije preuzimanja**: `PlayerMute`, `RemotePlayback`,
/// pozadinski zvuk i Media Session se vežu tek u `openAndResume`, nakon
/// [take]. Preload ne smije preoteti singletone playeru koji možda još svira
/// na ekranu ispod (`push` drži prethodnu epizodu živom).
class PlayerPreload {
  PlayerPreload._(this.uri, this.player, this._controller, this.opened);

  /// Otvori [uri] u novom playeru bez reprodukcije.
  ///
  /// **Web: controller tek pri preuzimanju.** `VideoController` se
  /// inicijalizira u post-frame callbacku, a media_kitov `open` čeka tu
  /// inicijalizaciju prije nego postavi `src`. Sljedeći frame je baš onaj koji
  /// gradi sadržaj epizode (long task ~2 s na CPU 4×), pa je `src` s
  /// controllerom stizao tek iza njega (izmjereno 19.11.2026.: preload u
  /// 9552 ms, `src` u 12245 ms). Bez controllera `open` postavi `src` odmah;
  /// `WebVideoController` podržava i element koji je već otvoren.
  ///
  /// **Native: controller prije `open`**, kao dosad u `_initVideo` — libmpv
  /// izlaz videa se veže kroz controller, i redoslijed nije isproban na
  /// uređaju.
  factory PlayerPreload.open(String uri) {
    final player = Player();
    final controller = kIsWeb ? null : VideoController(player);
    preloadWholeMedia(player);
    final opened = player.open(Media(uri), play: false).catchError((Object e) {
      log('PlayerPreload: open nije uspio ($e)');
    });
    log('PlayerPreload: open $uri');
    return PlayerPreload._(uri, player, controller, opened);
  }

  final String uri;
  final Player player;
  VideoController? _controller;

  /// Controller playera; na webu se stvara pri prvom čitanju (vidi [open]).
  VideoController get controller => _controller ??= VideoController(player);

  /// Završi kad je `open` gotov (ili pao — greška je progutana; pozivatelj
  /// je vidi kroz `player.stream.error` kao i inače).
  final Future<void> opened;

  bool _taken = false;
  bool _disposed = false;

  bool get isTaken => _taken;
  bool get isDisposed => _disposed;

  /// Preuzmi player ako je otvoren baš za [expectedUri] i još je slobodan.
  /// Inače `null` (pozivatelj ide starim putem), a ovaj se preload zatvori.
  PlayerPreload? take(String expectedUri) {
    if (_taken || _disposed) return null;
    if (expectedUri != uri) {
      log('PlayerPreload: URL se razlikuje ($uri ≠ $expectedUri), zatvaram');
      dispose();
      return null;
    }
    _taken = true;
    return this;
  }

  /// Zatvori player ako ga nitko nije preuzeo. Idempotentno.
  void dispose() {
    if (_taken || _disposed) return;
    _disposed = true;
    unawaited(player.dispose());
  }
}
