/// Ugovor pretplata na push teme (`docs/plans/2026-10-15-push-nove-epizode.md`).
///
/// Transport je lažan: bilježi pretplate i odjave koje bi otišle FCM-u.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:podcast_core/l10n/app_localizations.dart';
import 'package:podcast_core/push/push_transport.dart';
import 'package:podcast_core/screens/notifications/notifications_screen.dart';
import 'package:podcast_core/services/follow_service.dart';
import 'package:podcast_core/services/push_topics.dart';

class _FakeTransport implements PushTransport {
  _FakeTransport({this.current = PushPermission.notDetermined, this.grant = true});

  PushPermission current;
  bool grant;
  int prompts = 0;
  bool failNetwork = false;
  final Set<String> subscribed = {};
  final List<String> unsubscribed = [];
  final _opened = StreamController<String>.broadcast();
  final _token = StreamController<void>.broadcast();

  @override
  Future<PushPermission> permission() async => current;

  @override
  Future<PushPermission> requestPermission() async {
    prompts++;
    current = grant ? PushPermission.granted : PushPermission.denied;
    return current;
  }

  @override
  Future<void> subscribe(String topic) async {
    if (failNetwork) throw Exception('offline');
    subscribed.add(topic);
  }

  @override
  Future<void> unsubscribe(String topic) async {
    if (failNetwork) throw Exception('offline');
    subscribed.remove(topic);
    unsubscribed.add(topic);
  }

  @override
  Stream<String> get openedRoutes => _opened.stream;

  @override
  Future<String?> initialRoute() async => null;

  @override
  Stream<void> get tokenRefreshed => _token.stream;

  void refreshToken() => _token.add(null);

  @override
  Future<void> openSystemSettings() async {}
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late PushTopics push;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FollowService.instance.debugReset();
    PushTopics.instance.debugReset();
    push = PushTopics.instance;
  });

  test('tema kanala zamijeni nedopuštene znakove', () {
    expect(channelTopic('radio_mreznica'), 'ep_c_radio_mreznica');
    expect(channelTopic('a b/č'), 'ep_c_a_b__');
    expect(channelIdFromTopic('ep_c_radio_mreznica'), 'radio_mreznica');
    expect(channelIdFromTopic(kTopicAllEpisodes), isNull);
  });

  test('bez transporta je sve ugašeno i ništa ne baca', () async {
    await push.init(null);
    expect(push.available, isFalse);
    expect(await push.enable(), isFalse);
    await push.setAllEpisodes(true);
    expect(push.allEpisodes, isFalse);
  });

  test('init NE pita za dozvolu i ne pretplaćuje ništa', () async {
    final t = _FakeTransport(current: PushPermission.granted);
    await push.init(t);
    await _settle();
    expect(t.prompts, 0);
    // Android ispod 13 daje dozvolu bez pitanja — korisnik ipak nije ništa
    // izabrao, pa obavijesti nisu „uključene".
    expect(push.enabled, isFalse);
    expect(t.subscribed, isEmpty);
  });

  test('prvo uključenje: Sve nove epizode + praćeni kanali (D1)', () async {
    await FollowService.instance.toggle(channelFollowKey('subclub'));
    await FollowService.instance.toggle(personFollowKey('ivan-merz'));
    final t = _FakeTransport();
    await push.init(t);

    expect(await push.enable(), isTrue);
    await _settle();

    expect(t.prompts, 1);
    expect(push.allEpisodes, isTrue);
    expect(t.subscribed, {kTopicAllEpisodes, 'ep_c_subclub'});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kPushEnabledStorageKey), '1');
    expect(
      (jsonDecode(prefs.getString(kPushTopicsStorageKey)!) as List).toSet(),
      {kTopicAllEpisodes, 'ep_c_subclub'},
    );
  });

  test('odbijena dozvola ne uključuje ništa', () async {
    final t = _FakeTransport(grant: false);
    await push.init(t);
    expect(await push.enable(), isFalse);
    expect(push.enabled, isFalse);
    expect(push.permission, PushPermission.denied);
    expect(t.subscribed, isEmpty);
  });

  test('prvo uključenje preko zvonca kanala pretplati SAMO taj kanal',
      () async {
    final t = _FakeTransport();
    await push.init(t);
    await push.setChannel('subclub', true);
    await _settle();
    expect(t.subscribed, {'ep_c_subclub'});
    expect(push.allEpisodes, isFalse);
  });

  test('praćenje dodaje temu kanala, otpraćivanje je miče', () async {
    final t = _FakeTransport();
    await push.init(t);
    await push.enable();
    await _settle();

    await FollowService.instance.toggle(channelFollowKey('glas_koncila'));
    await _settle();
    expect(push.isChannelOn('glas_koncila'), isTrue);
    expect(t.subscribed, contains('ep_c_glas_koncila'));

    await FollowService.instance.toggle(channelFollowKey('glas_koncila'));
    await _settle();
    expect(push.isChannelOn('glas_koncila'), isFalse);
    expect(t.unsubscribed, contains('ep_c_glas_koncila'));
  });

  test('gašenje obavijesti kanala NE otpraćuje kanal', () async {
    final t = _FakeTransport();
    await push.init(t);
    await FollowService.instance.toggle(channelFollowKey('subclub'));
    await push.enable();
    await push.setChannel('subclub', false);
    expect(FollowService.instance.isFollowingSync(channelFollowKey('subclub')),
        isTrue);
  });

  test('praćenje bez uključenih obavijesti ne otvara dijalog', () async {
    final t = _FakeTransport();
    await push.init(t);
    await FollowService.instance.toggle(channelFollowKey('subclub'));
    await _settle();
    expect(t.prompts, 0);
    expect(t.subscribed, isEmpty);
  });

  test('neuspjela odjava se ponavlja pri sljedećem reconcileu', () async {
    final t = _FakeTransport();
    await push.init(t);
    await push.enable();
    await _settle();

    t.failNetwork = true;
    await push.setAllEpisodes(false);
    await push.reconcile();
    expect(t.subscribed, contains(kTopicAllEpisodes));

    t.failNetwork = false;
    await push.reconcile();
    expect(t.subscribed, isNot(contains(kTopicAllEpisodes)));
  });

  test('novi token ponovno pretplati sve teme iz lokalnog stanja', () async {
    SharedPreferences.setMockInitialValues({
      kPushEnabledStorageKey: '1',
      kPushTopicsStorageKey: jsonEncode([kTopicAllEpisodes, 'ep_c_subclub']),
    });
    final t = _FakeTransport(current: PushPermission.granted);
    await push.init(t);
    await _settle();
    expect(t.subscribed, {kTopicAllEpisodes, 'ep_c_subclub'});

    t.subscribed.clear(); // reinstalacija: FCM je zaboravio pretplate
    t.refreshToken();
    await _settle();
    await push.reconcile();
    expect(t.subscribed, {kTopicAllEpisodes, 'ep_c_subclub'});
  });

  group('ekran Obavijesti', () {
    Widget wrap() => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('hr'),
          home: const NotificationsScreen(),
        );

    testWidgets('bez transporta kaže da je samo u aplikaciji', (tester) async {
      await push.init(null);
      await tester.pumpWidget(wrap());
      await tester.pump();
      expect(find.text('Obavijesti su dostupne u aplikaciji za iOS i Android.'),
          findsOneWidget);
    });

    testWidgets('neuključeno: gumb otvara dijalog, nakon toga stanje',
        (tester) async {
      final t = _FakeTransport();
      await tester.runAsync(() => push.init(t));
      await tester.pumpWidget(wrap());
      await tester.pump();
      expect(find.byKey(const ValueKey('notifications-enable')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('notifications-enable')));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      expect(t.prompts, 1);
      expect(find.text('Obavijesti su uključene'), findsOneWidget);
      final all = tester.widget<SwitchListTile>(
          find.byKey(const ValueKey('notifications-all')));
      expect(all.value, isTrue);
    });

    testWidgets('odbijeno: put u postavke, prekidači onemogućeni',
        (tester) async {
      final t = _FakeTransport(current: PushPermission.denied);
      await tester.runAsync(() => push.init(t));
      await tester.pumpWidget(wrap());
      await tester.pump();
      expect(find.text('Otvori postavke'), findsOneWidget);
      final all = tester.widget<SwitchListTile>(
          find.byKey(const ValueKey('notifications-all')));
      expect(all.onChanged, isNull);
    });
  });
}
