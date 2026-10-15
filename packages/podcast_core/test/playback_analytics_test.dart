import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_core/services/analytics/playback_analytics.dart';

/// Događaji reprodukcije (`domovina-analytics/docs/ugovor.md`).
void main() {
  late StreamController<bool> playing;
  late StreamController<Duration> position;
  late List<(String, Map<String, Object?>)> events;
  late DateTime now;

  PlaybackAnalytics make({int duration = 1000}) => PlaybackAnalytics(
        playingStream: playing.stream,
        positionStream: position.stream,
        videoId: 'abc',
        surface: 'v',
        durationSeconds: duration,
        sink: (n, p) => events.add((n, p)),
        clock: () => now,
      );

  List<String> names() => [for (final e in events) e.$1];
  Map<String, Object?> last(String name) =>
      events.lastWhere((e) => e.$1 == name).$2;

  setUp(() {
    playing = StreamController<bool>(sync: true);
    position = StreamController<Duration>(sync: true);
    events = [];
    now = DateTime.utc(2026, 10, 15, 12);
  });

  /// Svira od [from] do [to] u koracima od 0,2 s, kao media_kit (~5×/s).
  void play(int from, int to) {
    for (var ms = from * 1000; ms <= to * 1000; ms += 200) {
      position.add(Duration(milliseconds: ms));
    }
  }

  test('start, pauza i nastavak; pauza nosi odslušano', () {
    final a = make();
    position.add(Duration.zero);
    playing.add(true);
    play(0, 30);
    playing.add(false);
    playing.add(true);
    expect(names(), ['playback_start', 'playback_pause', 'playback_resume']);
    expect(last('playback_start')['duration_s'], 1000);
    expect(last('playback_pause')['listened_s'], 30);
    expect(last('playback_pause')['video_id'], 'abc');
    a.dispose();
  });

  test('resume-seek pri otvaranju nije skok i ne okida preskočene pragove', () {
    final a = make();
    position.add(Duration.zero);
    position.add(const Duration(seconds: 600)); // resume na 60 %
    playing.add(true);
    play(600, 760); // prijeđe 75 %
    expect(names().where((n) => n == 'playback_seek'), isEmpty);
    expect([
      for (final e in events)
        if (e.$1 == 'playback_progress') e.$2['pct'],
    ], [75]);
    a.dispose();
  });

  test('povlačenje slidera daje JEDAN seek, kad se smiri', () {
    fakeAsync((fa) {
      final a = make();
      position.add(Duration.zero);
      playing.add(true);
      now = now.add(const Duration(seconds: 20)); // izvan prozora otvaranja
      play(0, 10);
      position.add(const Duration(seconds: 100));
      position.add(const Duration(seconds: 200));
      position.add(const Duration(seconds: 300));
      expect(names().where((n) => n == 'playback_seek'), isEmpty);
      fa.elapse(const Duration(seconds: 2));
      final seeks = events.where((e) => e.$1 == 'playback_seek').toList();
      expect(seeks, hasLength(1));
      expect(seeks.single.$2['from_s'], 10);
      expect(seeks.single.$2['to_s'], 300);
      a.dispose();
    });
  });

  test('skok se ne broji u odslušano; end nosi listened_s i end_pct', () {
    final a = make(duration: 100);
    position.add(Duration.zero);
    playing.add(true);
    now = now.add(const Duration(seconds: 20));
    play(0, 10);
    position.add(const Duration(seconds: 80));
    play(80, 85);
    a.dispose();
    final end = last('playback_end');
    expect(end['listened_s'], 15);
    expect(end['end_pct'], 85);
    expect(names(), contains('playback_seek')); // dispose ispere čekajući seek
  });

  test('bez reprodukcije nema playback_end', () {
    final a = make();
    position.add(Duration.zero);
    a.dispose();
    expect(events, isEmpty);
  });

  test('nakon dispose nema događaja', () {
    final a = make();
    playing.add(true);
    a.dispose();
    events.clear();
    playing.add(false);
    expect(events, isEmpty);
  });
}
