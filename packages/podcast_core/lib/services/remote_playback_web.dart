/// Web implementacija [RemotePlayback]: WebKit AirPlay ili W3C Remote Playback.
///
/// Safari ima i standardni `remote`, ali dostupnost uređaja pouzdano javlja
/// samo vlastiti `webkitplaybacktargetavailabilitychanged` — zato WebKit ide
/// svojim putem čim element ima `webkitShowPlaybackTargetPicker`.
///
/// Chrome: `watchAvailability` na desktopu zna odbiti (`NotSupportedError`)
/// iako Cast postoji. Tada gumba nema — ne nudimo izbornik za koji ne znamo
/// ima li u njemu ičega.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:web/web.dart' as web;

import '../src/log.dart' show log;
import 'media_element_web.dart';
import 'remote_playback.dart';

bool _isWebKit(web.HTMLVideoElement el) =>
    (el as JSObject).has('webkitShowPlaybackTargetPicker');

RemoteState _parseState(String s) => switch (s) {
  'connected' => RemoteState.connected,
  'connecting' => RemoteState.connecting,
  _ => RemoteState.disconnected,
};

VoidCallback bindRemotePlayback(
  Player player, {
  required void Function(RemoteTarget? target) onTarget,
  required void Function(RemoteState state) onState,
}) {
  final el = videoElementOf(player);
  if (el == null) {
    log('RemotePlayback: nema <video> elementa');
    return () {};
  }
  return _isWebKit(el)
      ? _bindWebKit(el, onTarget, onState)
      : _bindStandard(el, onTarget, onState);
}

VoidCallback _bindWebKit(
  web.HTMLVideoElement el,
  void Function(RemoteTarget?) onTarget,
  void Function(RemoteState) onState,
) {
  el.setAttribute('x-webkit-airplay', 'allow');
  final onAvailability = ((web.Event e) {
    final availability = (e as JSObject)
        .getProperty<JSString?>('availability'.toJS)
        ?.toDart;
    onTarget(availability == 'available' ? RemoteTarget.airPlay : null);
  }).toJS;
  final onWireless = ((web.Event _) {
    final wireless =
        (el as JSObject)
            .getProperty<JSBoolean?>(
              'webkitCurrentPlaybackTargetIsWireless'.toJS,
            )
            ?.toDart ??
        false;
    onState(wireless ? RemoteState.connected : RemoteState.disconnected);
  }).toJS;
  el.addEventListener(
    'webkitplaybacktargetavailabilitychanged',
    onAvailability,
  );
  el.addEventListener(
    'webkitcurrentplaybacktargetiswirelesschanged',
    onWireless,
  );
  return () {
    el.removeEventListener(
      'webkitplaybacktargetavailabilitychanged',
      onAvailability,
    );
    el.removeEventListener(
      'webkitcurrentplaybacktargetiswirelesschanged',
      onWireless,
    );
  };
}

VoidCallback _bindStandard(
  web.HTMLVideoElement el,
  void Function(RemoteTarget?) onTarget,
  void Function(RemoteState) onState,
) {
  if (!(el as JSObject).has('remote')) {
    log('RemotePlayback: preglednik nema Remote Playback API');
    return () {};
  }
  final remote = el.remote;
  int? watchId;
  var disposed = false;

  remote
      .watchAvailability(
        ((JSBoolean available) {
          onTarget(available.toDart ? RemoteTarget.cast : null);
        }).toJS,
      )
      .toDart
      .then((id) {
        watchId = id.toDartInt;
        if (disposed) remote.cancelWatchAvailability(watchId!);
      })
      .catchError((Object e) {
        log('RemotePlayback.watchAvailability: $e');
        return null;
      });

  final onChange = ((web.Event _) => onState(_parseState(remote.state))).toJS;
  for (final type in const ['connecting', 'connect', 'disconnect']) {
    remote.addEventListener(type, onChange);
  }
  onState(_parseState(remote.state));

  return () {
    disposed = true;
    for (final type in const ['connecting', 'connect', 'disconnect']) {
      remote.removeEventListener(type, onChange);
    }
    final id = watchId;
    if (id != null) remote.cancelWatchAvailability(id);
  };
}

Future<void> promptRemotePlayback(Player player) async {
  final el = videoElementOf(player);
  if (el == null) return;
  if (_isWebKit(el)) {
    (el as JSObject).callMethod<JSAny?>('webkitShowPlaybackTargetPicker'.toJS);
    return;
  }
  await el.remote.prompt().toDart;
}
