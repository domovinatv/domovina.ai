/// Brzina reprodukcije — YouTube-ov kružni prekidač
/// 1,0× → 1,25× → 1,5× → 1,75× → 2,0× → 1,0×.
///
/// Pamti se **globalno za uređaj** (odluka D1 u
/// `docs/plans/2026-07-27-playback-overhaul.md`), ne po epizodi: tko sluša na
/// 1,5×, sluša tako i sljedeću epizodu, i nakon reloada.
///
/// Web: localStorage (SharedPreferences puca u dart2js release buildu —
/// vidi CLAUDE.md). Native: SharedPreferences. Isti oblik kao
/// `background_playback.dart` (lazy `init()`, `_loaded` guard protiv utrke
/// između čitanja i settera).
///
/// `init()` se smije (i preporučeno je) pozvati iz main() prije runApp, ali
/// NIJE obavezan: prvi pristup `rate` sam pokrene učitavanje i javi
/// listenerima kad vrijednost stigne.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'analytics/analytics.dart';
import 'local_prefs.dart';

/// Ponuđene brzine, redoslijedom kružnog prekidača.
const kPlaybackRates = <double>[1.0, 1.25, 1.5, 1.75, 2.0];

const String _playbackSpeedKey = 'playback_speed';
const double _defaultRate = 1.0;

class PlaybackSpeed extends ChangeNotifier {
  PlaybackSpeed._();
  static final PlaybackSpeed instance = PlaybackSpeed._();

  /// Normalna brzina dok se spremljena vrijednost ne učita.
  double _rate = _defaultRate;

  /// True čim je vrijednost poznata — bilo iz storagea, bilo iz setRate().
  bool _loaded = false;

  Future<void>? _loading;

  /// Trenutna brzina reprodukcije; uvijek jedna od [kPlaybackRates].
  ///
  /// Lazy: ako init() nije pozvan, prvi pristup pokrene čitanje u pozadini i
  /// notifyListeners() kad vrijednost stigne. Dotle vraća default (1.0).
  double get rate {
    unawaited(init());
    return _rate;
  }

  /// Sljedeća brzina u krugu (2,0× → 1,0×). Ne mijenja stanje.
  double get nextRate {
    final i = kPlaybackRates.indexOf(rate);
    // -1 ne bi smio nastati (rate je uvijek clampan), ali (-1 + 1) % n == 1
    // bi preskočio 1,0× pa je fallback izričit.
    if (i < 0) return kPlaybackRates.first;
    return kPlaybackRates[(i + 1) % kPlaybackRates.length];
  }

  /// Učitaj spremljenu vrijednost. Idempotentno — višestruki pozivi dijele
  /// isti Future.
  Future<void> init() => _loading ??= _load();

  /// Postavi brzinu; [r] se clampa na najbližu iz [kPlaybackRates].
  Future<void> setRate(double r) async {
    // Korisnikov odabir pobjeđuje eventualno čitanje u letu.
    _loaded = true;
    _loading ??= Future<void>.value();
    final value = _nearest(r);
    if (value == _rate) return;
    Analytics.instance.track('playback_rate', props: {'from': _rate, 'to': value});
    _rate = value;
    notifyListeners();
    await _write(_encode(value));
  }

  Future<void> _load() async {
    final raw = await _read();
    // Utrka: setRate() je stigao prije nego se čitanje vratilo.
    if (_loaded) return;
    _loaded = true;
    final value = _decode(raw);
    if (value == _rate) return;
    Analytics.instance.track('playback_rate', props: {'from': _rate, 'to': value});
    _rate = value;
    notifyListeners();
  }

  /// Najbliža ponuđena brzina — brani od pokvarene spremljene vrijednosti i
  /// od pozivatelja koji pošalje brzinu izvan popisa.
  static double _nearest(double r) {
    if (!r.isFinite) return _defaultRate;
    var best = kPlaybackRates.first;
    var bestDelta = (r - best).abs();
    for (final candidate in kPlaybackRates.skip(1)) {
      final delta = (r - candidate).abs();
      if (delta < bestDelta) {
        best = candidate;
        bestDelta = delta;
      }
    }
    return best;
  }

  /// Storage je stringovni (`local_prefs.dart`), pa i native grana piše string
  /// — ista vrijednost čitljiva na obje platforme.
  static String _encode(double value) => value.toString();

  static double _decode(String? raw) {
    if (raw == null) return _defaultRate;
    final parsed = double.tryParse(raw);
    if (parsed == null) return _defaultRate;
    return _nearest(parsed);
  }

  Future<String?> _read() async {
    if (kIsWeb) return getLocalStorageString(_playbackSpeedKey);
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_playbackSpeedKey);
  }

  Future<void> _write(String value) async {
    if (kIsWeb) {
      setLocalStorageString(_playbackSpeedKey, value);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_playbackSpeedKey, value);
  }
}
