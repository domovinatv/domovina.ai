/// Vlastita analitika događaja. Klijent servisa `domovina-analytics`
/// (zaseban repo: Cloudflare Worker na istom originu → ClickHouse).
///
/// Ugovor omotnice i popis događaja: `domovina-analytics/docs/ugovor.md`.
///
/// Kako radi:
/// - događaji se skupljaju u memoriji i šalju batchem najviše jednom u 30 s
///   dok je aplikacija u prednjem planu — taj flush je ujedno heartbeat po
///   kojem dashboard zna tko je sada u aplikaciji;
/// - pri odlasku u pozadinu / zatvaranju taba ide završni flush (web:
///   `fetch keepalive`);
/// - neposlano se vraća u red (do [maxQueued]), a 4xx odgovor se ne šalje
///   ponovno jer bi bio odbijen opet;
/// - sesija se prekida nakon [sessionGap] neaktivnosti.
///
/// Brend bez `Endpoints.events` nema analitiku: [init] tada ne radi ništa i
/// svaki poziv je no-op. U debug buildu je također ugašena, osim uz
/// `--dart-define=ANALYTICS_IN_DEBUG=true`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../src/log.dart' show log;
import '../local_prefs.dart';
import 'analytics_route.dart';
import 'analytics_transport.dart';

const bool _inDebug = bool.fromEnvironment('ANALYTICS_IN_DEBUG');

/// Lokalni razvoj: `--dart-define=ANALYTICS_ENDPOINT=http://127.0.0.1:8787/api/state`
/// šalje na `wrangler dev` umjesto na produkciju.
const String _endpointOverride = String.fromEnvironment('ANALYTICS_ENDPOINT');
const String _deviceIdKey = 'analytics_device_id';

class Analytics {
  Analytics._({
    AnalyticsSender? sender,
    DateTime Function()? clock,
    Random? random,
  })  : _send = sender ?? sendBatch,
        _clock = clock ?? DateTime.now,
        _random = random ?? Random.secure();

  static final Analytics instance = Analytics._();

  /// Instanca za testove: lažni transport i sat, bez lifecycle listenera i
  /// bez timera (flush se zove ručno).
  @visibleForTesting
  factory Analytics.forTest({
    required AnalyticsSender sender,
    required DateTime Function() clock,
    String endpoint = 'https://example.test/api/state',
    String deviceId = 'dev_test',
  }) {
    final a = Analytics._(sender: sender, clock: clock, random: Random(1));
    a._configure(
      endpoint: endpoint,
      app: 'test.app',
      platform: 'web',
      appVersion: '0.0.0',
      deviceId: deviceId,
    );
    return a;
  }

  static const flushInterval = Duration(seconds: 30);
  static const firstFlushDelay = Duration(seconds: 5);
  static const sendTimeout = Duration(seconds: 15);
  static const minFlushGap = Duration(seconds: 5);
  static const sessionGap = Duration(minutes: 30);
  static const maxBatch = 50;
  static const maxQueued = 500;

  final AnalyticsSender _send;
  final DateTime Function() _clock;
  final Random _random;

  bool _enabled = false;
  String _endpoint = '';
  String _app = '';
  String _platform = '';
  String _appVersion = '';
  String _deviceId = '';
  String _sessionId = '';
  String? _userId;
  String _locale = '';
  List<int> _screen = const [0, 0];

  final List<Map<String, Object?>> _queue = [];
  DateTime? _lastActivity;
  DateTime? _lastFlush;
  bool _inFlight = false;
  String? _lastScreenKey;
  bool _foreground = true;
  Timer? _timer;
  AppLifecycleListener? _lifecycle;

  bool get enabled => _enabled;
  String get sessionId => _sessionId;
  @visibleForTesting
  List<Map<String, Object?>> get queued => List.unmodifiable(_queue);

  Future<void> init({
    required String endpoint,
    required String app,
    required String platform,
    required String appVersion,
  }) async {
    if (_endpointOverride.isNotEmpty) endpoint = _endpointOverride;
    if (endpoint.isEmpty || (kDebugMode && !_inDebug)) {
      log('Analytics: off (${endpoint.isEmpty ? 'brand bez endpointa' : 'debug'})');
      return;
    }
    _configure(
      endpoint: endpoint,
      app: app,
      platform: platform,
      appVersion: appVersion,
      deviceId: await _loadDeviceId(),
    );
    _readScreen();
    _lifecycle = AppLifecycleListener(onStateChange: handleLifecycle);
    _startTimer();
    // Prvi batch ne čeka puni interval: posjet kraći od 30 s bi inače ostao
    // neizbrojen kad tab nestane bez `hidden` događaja.
    Timer(firstFlushDelay, () => unawaited(flush()));
    log('Analytics: on → $endpoint');
  }

  void _configure({
    required String endpoint,
    required String app,
    required String platform,
    required String appVersion,
    required String deviceId,
  }) {
    _endpoint = endpoint;
    _app = app;
    _platform = platform;
    _appVersion = appVersion;
    _deviceId = deviceId;
    _enabled = true;
    _startSession();
  }

  Future<String> _loadDeviceId() async {
    // Web: localStorage (SharedPreferences na webu ruši release build —
    // CLAUDE.md, Known Issues). Native: SharedPreferences.
    if (kIsWeb) {
      final existing = getLocalStorageString(_deviceIdKey);
      if (existing != null) return existing;
      final id = _newId();
      setLocalStorageString(_deviceIdKey, id);
      return id;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(_deviceIdKey);
      if (existing != null && existing.isNotEmpty) return existing;
      final id = _newId();
      await prefs.setString(_deviceIdKey, id);
      return id;
    } catch (_) {
      return _newId();
    }
  }

  void _readScreen() {
    try {
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final size = view.physicalSize / view.devicePixelRatio;
      _screen = [size.width.round(), size.height.round()];
    } catch (_) {}
  }

  /// UUID v4 — ugovor ga traži za `event_id`; za device/session je samo
  /// dovoljno slučajan i u dopuštenom skupu znakova.
  String _newId() {
    final b = List<int>.generate(16, (_) => _random.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  void _startSession() {
    _sessionId = _newId();
    _lastScreenKey = null;
    final props = <String, Object?>{};
    final ref = documentReferrer();
    if (ref != null) props['referrer'] = ref;
    if (kIsWeb) {
      Uri.base.queryParameters.forEach((k, v) {
        if (k.startsWith('utm_')) props[k] = v;
      });
    }
    _enqueue('session_start', props: props);
  }

  void _touch() {
    // Događaj od korisnika znači da je aplikacija pred njim, što god
    // lifecycle zadnje javio — na webu `hidden` zna stići i bez stvarnog
    // odlaska (izmjereno pri otvaranju epizode), a bez ovoga bi heartbeat
    // stao do sljedećeg `resumed`.
    if (!_foreground) {
      _foreground = true;
      if (_lifecycle != null) _startTimer();
    }
    final now = _clock();
    final last = _lastActivity;
    _lastActivity = now;
    if (last != null && now.difference(last) > sessionGap) {
      _startSession();
    }
  }

  void _enqueue(
    String name, {
    Map<String, Object?>? props,
    String? route,
    String? videoId,
    String? channel,
  }) {
    _queue.add({
      'id': _newId(),
      't': _clock().millisecondsSinceEpoch,
      'n': name,
      'route': ?route,
      'video_id': ?videoId,
      'channel': ?channel,
      if (props != null && props.isNotEmpty) 'props': props,
    });
    if (_queue.length > maxQueued) {
      _queue.removeRange(0, _queue.length - maxQueued);
    }
  }

  /// Proizvoljan događaj. [name] je `snake_case` (`^[a-z][a-z0-9_]{1,63}$`,
  /// inače ga server odbaci); [props] serijaliziran stane u 4 KB.
  void track(
    String name, {
    Map<String, Object?>? props,
    String? videoId,
    String? channel,
  }) {
    if (!_enabled) return;
    _touch();
    _enqueue(
      name,
      props: props,
      route: _lastScreenKey,
      videoId: videoId,
      channel: channel,
    );
  }

  /// Prikaz ekrana; zove ga listener rutera. Isti ekran zaredom (npr. samo
  /// promijenjen `/t/<sec>`) se ne broji ponovno.
  void screen(Uri location) {
    if (!_enabled) return;
    _touch();
    final info = screenInfoFor(location);
    if (info.key == _lastScreenKey) return;
    _lastScreenKey = info.key;
    _enqueue(
      'screen_view',
      route: info.route,
      videoId: info.videoId,
      channel: info.channel,
      props: info.person == null ? null : {'person': info.person},
    );
  }

  /// Supabase `auth.users.id` prijavljenog korisnika, null za gosta.
  void setUser(String? userId) {
    final next = (userId == null || userId.isEmpty) ? null : userId;
    if (next == _userId) return;
    // Događaji iz reda pripadaju onome tko ih je napravio — pošalji ih pod
    // starim identitetom. `flush` omotnicu slaže sinkrono, prije prvog
    // `await`, pa uhvati još nepromijenjen `_userId`.
    if (_enabled && _queue.isNotEmpty) unawaited(flush(force: true));
    _userId = next;
    if (!_enabled) return;
    _enqueue(next == null ? 'sign_out' : 'identify');
  }

  void setLocale(String locale) => _locale = locale;

  @visibleForTesting
  void handleLifecycle(AppLifecycleState state) {
    log('Analytics: lifecycle ${state.name}');
    switch (state) {
      case AppLifecycleState.resumed:
        _foreground = true;
        _touch();
        _startTimer();
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        if (_foreground) {
          _foreground = false;
          _timer?.cancel();
          _enqueue('app_background');
          unawaited(flush(force: true));
        }
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(flushInterval, (_) => tick());
  }

  /// Jedan otkucaj: prazan red dobiva `heartbeat`, pa flush. Javno radi
  /// testova; u aplikaciji ga zove timer.
  @visibleForTesting
  Future<void> tick() async {
    if (!_enabled || !_foreground) return;
    if (_queue.isEmpty) _enqueue('heartbeat', route: _lastScreenKey);
    await flush();
  }

  Future<void> flush({bool force = false}) async {
    if (!_enabled || _inFlight || _queue.isEmpty) return;
    final now = _clock();
    final last = _lastFlush;
    if (!force && last != null && now.difference(last) < minFlushGap) return;
    _inFlight = true;
    _lastFlush = now;
    final batch = _queue.take(maxBatch).toList();
    _queue.removeRange(0, batch.length);
    try {
      final body = jsonEncode({
        'v': 1,
        'app': _app,
        'device_id': _deviceId,
        'session_id': _sessionId,
        if (_userId != null) 'user_id': _userId,
        'platform': _platform,
        'app_version': _appVersion,
        if (_locale.isNotEmpty) 'locale': _locale,
        'screen': _screen,
        'events': batch,
      });
      // Zahtjev koji nikad ne završi ne smije zauvijek držati `_inFlight`.
      final result = await _send(_endpoint, body)
          .timeout(sendTimeout, onTimeout: () => SendResult.retry);
      if (result == SendResult.retry) {
        _queue.insertAll(0, batch);
        if (_queue.length > maxQueued) {
          _queue.removeRange(maxQueued, _queue.length);
        }
      } else if (result == SendResult.rejected) {
        log('Analytics: server odbio batch (${batch.length} događaja)');
      }
    } finally {
      _inFlight = false;
    }
  }

  @visibleForTesting
  void dispose() {
    _timer?.cancel();
    _lifecycle?.dispose();
    _enabled = false;
  }
}
