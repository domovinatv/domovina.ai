/// DOMOVINA push preko Firebase Cloud Messaging tema (iOS + Android).
///
/// Uvozi se samo na nativeu (conditional import u `main.dart`), pa web build
/// ne vuče Firebase u Dart kod. Jezgra zna samo za [PushTransport]; teme,
/// pretplate i ekran Obavijesti su u `podcast_core` (`PushTopics`).
///
/// Plan: `docs/plans/2026-10-15-push-nove-epizode.md`.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:podcast_core/podcast_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../firebase_options.dart';

/// Android: kanal „Nove epizode" i sistemske postavke obavijesti
/// (`MainActivity.kt`). Ime kanala mora odgovarati tamošnjem.
const _androidChannel = MethodChannel('app/push');

Future<PushTransport?> createPushTransport() async {
  // Zove se iz `main()` PRIJE `runPodcastApp`, a Firebase treba binding.
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    log('push: Firebase init failed ($e) — push off');
    return null;
  }
  final messaging = FirebaseMessaging.instance;
  // macOS i ostalo bez Firebase konfiguracije već je ispalo gore
  // (`DefaultFirebaseOptions` baca UnsupportedError).
  // iOS u prednjem planu inače NE prikazuje obavijest. Android je u prednjem
  // planu ionako ne prikazuje — korisnik je već u aplikaciji.
  await messaging.setForegroundNotificationPresentationOptions(
    alert: true,
    sound: true,
  );
  // Registracija pali `onRegistered`, na koji `PushTopics` ponovi pretplate.
  unawaited(messaging.register().catchError((Object e) {
    log('push: FCM register failed ($e)');
  }));
  return FirebasePushTransport(messaging);
}

class FirebasePushTransport implements PushTransport {
  FirebasePushTransport(this._messaging);

  final FirebaseMessaging _messaging;

  @override
  Future<PushPermission> permission() async =>
      _map((await _messaging.getNotificationSettings()).authorizationStatus);

  @override
  Future<PushPermission> requestPermission() async =>
      _map((await _messaging.requestPermission()).authorizationStatus);

  /// Android 13+ smije pitati dvaput: obično `denied` znači da sistemski
  /// dijalog još može izaći, pa ekran nudi gumb, ne put u postavke. Tek
  /// `deniedPermanently` (ili `denied` na iOS-u) šalje korisnika u postavke.
  static PushPermission _map(AuthorizationStatus s) => switch (s) {
        AuthorizationStatus.authorized ||
        AuthorizationStatus.provisional =>
          PushPermission.granted,
        AuthorizationStatus.denied => Platform.isAndroid
            ? PushPermission.notDetermined
            : PushPermission.denied,
        AuthorizationStatus.deniedPermanently => PushPermission.denied,
        AuthorizationStatus.notDetermined => PushPermission.notDetermined,
      };

  @override
  Future<void> subscribe(String topic) async {
    await _awaitApnsToken();
    await _messaging.subscribeToTopic(topic);
  }

  @override
  Future<void> unsubscribe(String topic) async {
    await _awaitApnsToken();
    await _messaging.unsubscribeFromTopic(topic);
  }

  /// Na iOS-u FCM odbija pretplatu dok APNs token nije stigao
  /// (`apns-token-not-set`), a on stiže asinkrono nakon dozvole. Čeka se
  /// kratko; ako ne stigne, pretplata pada i ponavlja se na sljedećem
  /// `reconcile` (start aplikacije ili `onTokenRefresh`).
  Future<void> _awaitApnsToken() async {
    if (!Platform.isIOS) return;
    for (var i = 0; i < 10; i++) {
      if (await _messaging.getAPNSToken() != null) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  @override
  Stream<String> get openedRoutes => FirebaseMessaging.onMessageOpenedApp
      .map(_routeOf)
      .where((r) => r != null)
      .cast<String>();

  @override
  Future<String?> initialRoute() async {
    final message = await _messaging.getInitialMessage();
    return message == null ? null : _routeOf(message);
  }

  static String? _routeOf(RemoteMessage m) {
    final route = m.data['route'];
    return route is String && route.isNotEmpty ? route : null;
  }

  /// Nova registracija (novi FID/token) ne nasljeđuje pretplate na teme.
  @override
  Stream<void> get tokenRefreshed => _messaging.onRegistered;

  @override
  Future<void> openSystemSettings() async {
    if (Platform.isAndroid) {
      await _androidChannel.invokeMethod<void>('openNotificationSettings');
      return;
    }
    await launchUrl(Uri.parse('app-settings:'));
  }
}
