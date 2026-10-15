/// Pretplate na push obavijesti o novim epizodama — FCM teme, bez baze.
///
/// Uređaj se sam pretplati na teme ([kTopicAllEpisodes], [channelTopic]), a
/// Worker `domovina-push` šalje jednu poruku po epizodi s uvjetom
/// `'ep_all' in topics || 'ep_c_<kanal>' in topics` — pa uređaj u obje teme
/// dobije jednu obavijest. Mi ne spremamo tokene; radi i za goste.
///
/// **Izvor istine je lokalan** (`push_topics_v1`): FCM nema API za čitanje
/// pretplata, a reinstalacija ili novi token ih tiho izgube. Zato se na svakom
/// startu i na [PushTransport.tokenRefreshed] sve teme ponovno pretplate
/// ([reconcile]); `subscribeToTopic` je idempotentan.
///
/// **„Uključeno" je NAŠA odluka, ne samo sistemska dozvola** (`push_enabled_v1`):
/// Android ispod 13 dozvolu daje bez pitanja, a korisnik nije ništa izabrao.
/// Teme se pretplaćuju tek kad korisnik svojim tapom uključi obavijesti.
///
/// Plan i odluke: `docs/plans/2026-10-15-push-nove-epizode.md`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../push/push_transport.dart';
import '../src/log.dart' show log;
import 'analytics/analytics.dart';
import 'follow_service.dart';
import 'local_prefs.dart';

/// Tema „Sve nove epizode".
const String kTopicAllEpisodes = 'ep_all';

const String _channelTopicPrefix = 'ep_c_';

const String kPushEnabledStorageKey = 'push_enabled_v1';
const String kPushTopicsStorageKey = 'push_topics_v1';

/// Teme s kojih se odjava nije uspjela (offline) — ponavlja se u [reconcile].
const String kPushTopicsOffStorageKey = 'push_topics_off_v1';

/// Tema kanala. FCM dopušta `[a-zA-Z0-9-_.~%]+`; interni id kanala je
/// `[a-z0-9_]`, ali sve ostalo se ipak zamijeni s `_` da neispravan id ne
/// sruši pretplatu cijelog skupa.
String channelTopic(String channelId) =>
    '$_channelTopicPrefix${channelId.replaceAll(RegExp(r'[^a-zA-Z0-9\-_.~%]'), '_')}';

/// Id kanala iz teme; `null` ako tema nije kanal.
String? channelIdFromTopic(String topic) => topic.startsWith(_channelTopicPrefix)
    ? topic.substring(_channelTopicPrefix.length)
    : null;

class PushTopics extends ChangeNotifier {
  static final PushTopics instance = PushTopics._();
  PushTopics._();

  PushTransport? _transport;
  PushPermission _permission = PushPermission.notDetermined;
  bool _enabled = false;
  final Set<String> _topics = {};
  final Set<String> _pendingOff = {};
  StreamSubscription<void>? _tokenSub;
  Future<void>? _reconciling;

  /// Ljuska je predala transport (DOMOVINA na iOS-u i Androidu). Bez njega se
  /// ekran Obavijesti i zvonca nigdje ne prikazuju.
  bool get available => _transport != null;

  /// Transport ljuske (za rukovanje tapom na obavijest u `app.dart`).
  PushTransport? get transport => _transport;

  PushPermission get permission => _permission;

  /// Korisnik je uključio obavijesti I sustav ih smije prikazati.
  bool get enabled => _enabled && _permission == PushPermission.granted;

  /// Korisnik je uključio obavijesti, ali ih je poslije ugasio u postavkama
  /// uređaja — teme su i dalje pretplaćene, samo se ništa ne prikazuje.
  bool get blockedBySystem =>
      _enabled && _permission == PushPermission.denied;

  bool get allEpisodes => enabled && _topics.contains(kTopicAllEpisodes);

  bool isChannelOn(String channelId) =>
      enabled && _topics.contains(channelTopic(channelId));

  /// Kanali s uključenom obaviješću (za vrh popisa na ekranu).
  Set<String> get channelIds =>
      _topics.map(channelIdFromTopic).whereType<String>().toSet();

  Future<void> init(PushTransport? transport) async {
    _transport = transport;
    if (transport == null) return;
    _enabled = await _read(kPushEnabledStorageKey) == '1';
    _topics.addAll(_decode(await _read(kPushTopicsStorageKey)));
    _pendingOff.addAll(_decode(await _read(kPushTopicsOffStorageKey)));
    await refreshPermission();
    _tokenSub = transport.tokenRefreshed.listen((_) => unawaited(reconcile()));
    unawaited(reconcile());
    log('push: enabled=$_enabled permission=${_permission.name} '
        'topics=${_topics.length}');
  }

  /// Ponovno pročitaj sistemsku dozvolu (korisnik je mogao otići u postavke).
  Future<void> refreshPermission() async {
    final t = _transport;
    if (t == null) return;
    try {
      final p = await t.permission();
      if (p == _permission) return;
      _permission = p;
      notifyListeners();
    } catch (e) {
      log('push: permission read failed ($e)');
    }
  }

  /// Uključi obavijesti. Poziva se SAMO iz korisnikova tapa — otvara sistemski
  /// dijalog. [initial] su teme koje se pretplate ako je ovo prvo uključenje;
  /// default je „Sve nove epizode" + praćeni kanali (odluka D1).
  ///
  /// Vraća `true` ako su obavijesti nakon toga uključene.
  Future<bool> enable({Set<String>? initial}) async {
    final t = _transport;
    if (t == null) return false;
    var p = _permission;
    if (p != PushPermission.granted) {
      Analytics.instance.track('push_permission_prompt');
      try {
        p = await t.requestPermission();
      } catch (e) {
        log('push: requestPermission failed ($e)');
        return false;
      }
      Analytics.instance
          .track('push_permission_result', props: {'result': p.name});
      _permission = p;
    }
    if (p != PushPermission.granted) {
      notifyListeners();
      return false;
    }
    if (!_enabled) {
      _enabled = true;
      await _write(kPushEnabledStorageKey, '1');
      final topics = initial ?? await _defaultTopics();
      for (final topic in topics) {
        _topics.add(topic);
        _pendingOff.remove(topic);
        Analytics.instance
            .track('push_topic_change', props: {'topic': topic, 'on': true});
      }
      await _persist();
    }
    notifyListeners();
    unawaited(reconcile());
    return true;
  }

  Future<Set<String>> _defaultTopics() async {
    await FollowService.instance.ensureLoaded();
    return {
      kTopicAllEpisodes,
      for (final id in FollowService.instance.channelIds) channelTopic(id),
    };
  }

  Future<void> setAllEpisodes(bool on) => _setTopic(kTopicAllEpisodes, on);

  Future<void> setChannel(String channelId, bool on) =>
      _setTopic(channelTopic(channelId), on);

  Future<void> _setTopic(String topic, bool on) async {
    if (!available) return;
    if (on && !enabled) {
      // Prvo uključenje preko pojedinog prekidača pretplati SAMO taj prekidač:
      // tko je tapnuo zvonce jednog kanala, nije tražio sve epizode.
      final ok = await enable(initial: _enabled ? null : {topic});
      if (!ok) return;
      if (_topics.contains(topic)) return;
    }
    final changed = on ? _topics.add(topic) : _topics.remove(topic);
    if (!changed) return;
    if (on) {
      _pendingOff.remove(topic);
    } else {
      _pendingOff.add(topic);
    }
    Analytics.instance
        .track('push_topic_change', props: {'topic': topic, 'on': on});
    await _persist();
    notifyListeners();
    unawaited(reconcile());
  }

  /// Sprega s praćenjem: praćenje kanala uključi njegovu obavijest, otpraćivanje
  /// je isključi. Obrnuto ne vrijedi — gašenje obavijesti NE otpraćuje kanal
  /// (rail „Novo od praćenih" ostaje). Bez uključenih obavijesti ne radi ništa:
  /// praćenje nikad ne otvara sistemski dijalog.
  Future<void> onFollowChanged(String followKey, bool following) async {
    if (!enabled) return;
    final channelId = channelIdFromFollowKey(followKey);
    if (channelId == null) return;
    await setChannel(channelId, following);
  }

  /// Pošalji FCM-u lokalno stanje: odjave koje nisu prošle, pa sve pretplate.
  /// Paralelni pozivi dijele isti prolaz.
  Future<void> reconcile() => _reconciling ??= _reconcile().whenComplete(() {
        _reconciling = null;
      });

  Future<void> _reconcile() async {
    final t = _transport;
    if (t == null || !_enabled) return;
    var dirty = false;
    for (final topic in _pendingOff.toList()) {
      try {
        await t.unsubscribe(topic);
        _pendingOff.remove(topic);
        dirty = true;
      } catch (e) {
        log('push: unsubscribe $topic failed ($e)');
      }
    }
    for (final topic in _topics.toList()) {
      try {
        await t.subscribe(topic);
      } catch (e) {
        log('push: subscribe $topic failed ($e)');
      }
    }
    if (dirty) await _persist();
  }

  Future<void> openSystemSettings() async {
    try {
      await _transport?.openSystemSettings();
    } catch (e) {
      log('push: openSystemSettings failed ($e)');
    }
  }

  // -------------------------------------------------------------------------
  // Perzistencija (isti obrazac kao FollowService)
  // -------------------------------------------------------------------------

  Future<void> _persist() async {
    await _write(kPushTopicsStorageKey, jsonEncode(_topics.toList()));
    await _write(kPushTopicsOffStorageKey, jsonEncode(_pendingOff.toList()));
  }

  /// Nikad ne baca — pokvaren zapis znači „nema pretplata", ne pad.
  static Set<String> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final list = jsonDecode(raw);
      if (list is! List) return {};
      return list.whereType<String>().where((t) => t.isNotEmpty).toSet();
    } catch (e) {
      log('push: neispravan zapis tema ($e)');
      return {};
    }
  }

  Future<String?> _read(String key) async {
    if (kIsWeb) return getLocalStorageString(key);
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  Future<void> _write(String key, String value) async {
    if (kIsWeb) {
      setLocalStorageString(key, value);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  /// Test hook: vrati servis u početno stanje.
  @visibleForTesting
  void debugReset() {
    unawaited(_tokenSub?.cancel());
    _tokenSub = null;
    _transport = null;
    _permission = PushPermission.notDetermined;
    _enabled = false;
    _topics.clear();
    _pendingOff.clear();
    _reconciling = null;
  }
}
