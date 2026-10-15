import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;

import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_core/services/analytics/analytics.dart';
import 'package:podcast_core/services/analytics/analytics_route.dart';
import 'package:podcast_core/services/analytics/analytics_transport.dart';

/// Ugovor klijenta prema `domovina-analytics` (docs/ugovor.md u tom repou).
void main() {
  group('screenInfoFor', () {
    test('epizoda: video ID, bez /t/<sec> i query stringa', () {
      final i = screenInfoFor(Uri.parse('/v/aue1GuuMsbA/t/8/en?p=ivo'));
      expect(i.route, '/v/aue1GuuMsbA/en');
      expect(i.videoId, 'aue1GuuMsbA');
    });

    test('jednostavni prikaz i /yt nose video, /c kanal, /p osobu', () {
      expect(screenInfoFor(Uri.parse('/m/abc_-1')).videoId, 'abc_-1');
      expect(screenInfoFor(Uri.parse('/yt/xyz')).videoId, 'xyz');
      expect(screenInfoFor(Uri.parse('/c/sub%20club/oglasi')).channel, 'sub club');
      expect(screenInfoFor(Uri.parse('/p/ivan-merz')).person, 'ivan-merz');
      expect(screenInfoFor(Uri.parse('')).route, '/');
      expect(screenInfoFor(Uri.parse('/channels/')).route, '/channels');
    });
  });

  group('Analytics', () {
    late DateTime now;
    late List<Map<String, dynamic>> sent;
    late SendResult next;
    late Analytics a;

    setUp(() {
      now = DateTime.utc(2026, 10, 14, 12);
      sent = [];
      next = SendResult.ok;
      a = Analytics.forTest(
        sender: (url, body) async {
          sent.add(jsonDecode(body) as Map<String, dynamic>);
          return next;
        },
        clock: () => now,
      );
    });

    List<String> names(Map<String, dynamic> env) =>
        [for (final e in env['events'] as List) e['n'] as String];

    test('prvi batch nosi session_start i omotnicu ugovora', () async {
      a.screen(Uri.parse('/v/abc/t/10'));
      await a.flush();
      expect(sent, hasLength(1));
      final env = sent.single;
      expect(env['app'], 'test.app');
      expect(env['device_id'], 'dev_test');
      expect(env['session_id'], a.sessionId);
      expect(names(env), ['session_start', 'screen_view']);
      final view = (env['events'] as List)[1] as Map;
      expect(view['route'], '/v/abc');
      expect(view['video_id'], 'abc');
      expect(view['id'], matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });

    test('pomak timestampa u istoj epizodi nije novi screen_view', () async {
      a.screen(Uri.parse('/v/abc'));
      a.screen(Uri.parse('/v/abc/t/30'));
      a.screen(Uri.parse('/v/abc/t/90'));
      await a.flush();
      expect(names(sent.single).where((n) => n == 'screen_view'), hasLength(1));
    });

    test('prazan red na otkucaju šalje heartbeat (online sada)', () async {
      await a.flush();
      now = now.add(const Duration(seconds: 30));
      await a.tick();
      expect(names(sent.last), ['heartbeat']);
    });

    test('retry vraća batch u red, rejected ga baca', () async {
      next = SendResult.retry;
      a.track('x_y');
      await a.flush();
      expect(a.queued.map((e) => e['n']), ['session_start', 'x_y']);

      next = SendResult.rejected;
      now = now.add(const Duration(seconds: 10));
      await a.flush();
      expect(a.queued, isEmpty);
    });

    test('flush ne ide češće od minFlushGap osim uz force', () async {
      a.track('a_b');
      await a.flush();
      a.track('c_d');
      await a.flush();
      expect(sent, hasLength(1));
      await a.flush(force: true);
      expect(sent, hasLength(2));
    });

    test('30 min neaktivnosti otvara novu sesiju', () async {
      final first = a.sessionId;
      a.track('a_b');
      now = now.add(const Duration(minutes: 31));
      a.track('c_d');
      expect(a.sessionId, isNot(first));
      expect(a.queued.map((e) => e['n']), ['session_start', 'a_b', 'session_start', 'c_d']);
    });

    test('prijava: stari događaji idu pod starim identitetom, pa identify', () async {
      a.track('as_guest');
      a.setUser('3f2b8c1e-9a4d-4e2f-8b1a-0c9d8e7f6a5b');
      await Future<void>.delayed(Duration.zero);
      expect(sent.first.containsKey('user_id'), isFalse);
      expect(names(sent.first), ['session_start', 'as_guest']);

      now = now.add(const Duration(seconds: 10));
      await a.flush();
      expect(sent.last['user_id'], '3f2b8c1e-9a4d-4e2f-8b1a-0c9d8e7f6a5b');
      expect(names(sent.last), ['identify']);
    });

    test('hidden gasi heartbeat, a prvi događaj korisnika ga vraća', () async {
      await a.flush();
      a.handleLifecycle(AppLifecycleState.hidden);
      await Future<void>.delayed(Duration.zero);
      expect(names(sent.last), ['app_background']);

      now = now.add(const Duration(seconds: 30));
      await a.tick();
      expect(sent, hasLength(2), reason: 'u pozadini nema heartbeata');

      a.screen(Uri.parse('/v/abc'));
      now = now.add(const Duration(seconds: 30));
      await a.tick();
      expect(names(sent.last), ['screen_view']);
    });

    test('web: hidden uz vidljiv tab ne gasi heartbeat', () async {
      var visible = true;
      final w = Analytics.forTest(
        sender: (url, body) async {
          sent.add(jsonDecode(body) as Map<String, dynamic>);
          return SendResult.ok;
        },
        clock: () => now,
        visible: () => visible,
      );
      await w.flush();
      w.handleLifecycle(AppLifecycleState.hidden);
      now = now.add(const Duration(seconds: 30));
      await w.tick();
      expect(names(sent.last), ['heartbeat']);

      // Pravi odlazak javi preglednik (visibilitychange), jednom.
      visible = false;
      w.handleVisibility(false);
      w.handleLifecycle(AppLifecycleState.hidden);
      await Future<void>.delayed(Duration.zero);
      expect(names(sent.last), ['app_background']);
      expect(sent.where((e) => names(e).contains('app_background')), hasLength(1));

      visible = true;
      w.handleVisibility(true);
      now = now.add(const Duration(seconds: 30));
      await w.tick();
      expect(names(sent.last), ['heartbeat']);
    });

    test('send koji visi ne zaključa red zauvijek', () {
      fakeAsync((async) {
        final hung = Analytics.forTest(
          sender: (url, body) => Completer<SendResult>().future,
          clock: () => now,
        );
        hung.flush();
        async.elapse(Analytics.sendTimeout + const Duration(seconds: 1));
        expect(hung.queued.map((e) => e['n']), ['session_start']);
      });
    });

    test('batch je ograničen na maxBatch događaja', () async {
      for (var i = 0; i < 120; i++) {
        a.track('e_$i');
      }
      await a.flush();
      expect((sent.single['events'] as List), hasLength(Analytics.maxBatch));
      expect(a.queued, hasLength(121 - Analytics.maxBatch));
    });
  });

  test('status → SendResult', () {
    expect(resultForStatus(204), SendResult.ok);
    expect(resultForStatus(429), SendResult.retry);
    expect(resultForStatus(503), SendResult.retry);
    expect(resultForStatus(400), SendResult.rejected);
    expect(resultForStatus(403), SendResult.rejected);
  });
}
