/// Defenderi za `SeekUndo` (2026-07-27, plan
/// `docs/plans/2026-07-27-playback-overhaul.md`).
///
/// Štite ugovor zbog kojeg servis postoji: **nakon skakanja po timelineu ili
/// poglavljima korisnik se mora moći vratiti na mjesto gledanja**, i nakon više
/// skokova i minute razgledavanja („pametni povratak", 16.11.2026.). Resume,
/// deep link i sam povratak (`suppress`) te prirodni tijek ponudu ne pale.
library;

import 'dart:async';

import 'package:podcast_core/services/seek_undo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Kratki prozori da testovi ne čekaju stvarnih 1,2 s / 8 s; margina do
  /// [afterWindow] je namjerno velika (flake guard na sporom CI-u).
  const window = Duration(milliseconds: 40);
  const fresh = Duration(milliseconds: 60);
  const afterWindow = Duration(milliseconds: 200);

  late StreamController<Duration> positionController;
  SeekUndo? undo;

  setUp(() {
    positionController = StreamController<Duration>();
  });

  tearDown(() async {
    undo?.dispose();
    undo = null;
    await positionController.close();
  });

  SeekUndo build() {
    return undo = SeekUndo(
      positionStream: positionController.stream,
      jumpThreshold: const Duration(seconds: 2),
      fresh: fresh,
      settleMin: const Duration(seconds: 3),
      exploreSettle: const Duration(seconds: 10),
      nearAnchor: const Duration(seconds: 10),
    );
  }

  /// Emitira poziciju playera i pusti event loop da je dostavi listeneru.
  Future<void> emit(Duration position) async {
    positionController.add(position);
    await Future<void>.delayed(Duration.zero);
  }

  /// Prirodni tijek: ~5 eventa u sekundi, korak 0,2 s. Vraća zadnju poziciju.
  Future<Duration> emitNatural(Duration from, {int steps = 10}) async {
    var p = from;
    for (var i = 1; i <= steps; i++) {
      p = from + Duration(milliseconds: 200 * i);
      await emit(p);
    }
    return p;
  }

  const m5 = Duration(minutes: 5);

  test('1 — prirodni tijek ne pali ponudu', () async {
    final u = build();
    await emit(m5);
    await emitNatural(m5);
    expect(u.undoTarget.value, isNull);
  });

  test('2 — prirodni tijek pri 2,0× (korak 0,4 s) ne pali ponudu', () async {
    final u = build();
    await emit(m5);
    for (var i = 1; i <= 10; i++) {
      await emit(m5 + Duration(milliseconds: 400 * i));
    }
    expect(u.undoTarget.value, isNull);
  });

  test('3 — skok naprijed pali ponudu na mjesto gledanja', () async {
    final u = build();
    await emit(m5); // otvaranje = mjesto gledanja
    final last = await emitNatural(m5, steps: 20); // 4 s gledanja
    await emit(const Duration(minutes: 42)); // scrub
    expect(u.undoTarget.value, last);
    expect(u.offer.value?.fresh, isTrue);
  });

  test('4 — skok natrag pali ponudu', () async {
    final u = build();
    await emit(const Duration(minutes: 42));
    await emit(m5); // scrub unatrag
    expect(u.undoTarget.value, const Duration(minutes: 42));
  });

  test('5 — skok unutar suppress prozora ne pali (resume, deep link)',
      () async {
    final u = build();
    await emit(m5);
    u.suppress(window: window);
    await emit(const Duration(minutes: 42));
    expect(u.undoTarget.value, isNull);
  });

  test('6 — tap na poglavlje (bez suppress) NUDI povratak', () async {
    final u = build();
    await emit(m5);
    await Future<void>.delayed(afterWindow);
    await emit(const Duration(minutes: 42));
    expect(u.undoTarget.value, m5);
  });

  test('7 — prvi event nakon otvaranja epizode ne pali ponudu', () async {
    final u = build();
    await emit(const Duration(minutes: 33));
    expect(u.undoTarget.value, isNull);
  });

  test('8 — ponuda NE istječe dok se razgledava, samo prestane biti svježa',
      () async {
    final u = build();
    await emit(m5);
    await emit(const Duration(minutes: 42));
    expect(u.offer.value?.fresh, isTrue);

    await Future<void>.delayed(afterWindow);
    expect(u.undoTarget.value, m5);
    expect(u.offer.value?.fresh, isFalse);
  });

  test('9 — consume() gasi ponudu odmah i ne nudi povratak na povratak',
      () async {
    final u = build();
    await emit(m5);
    await emit(const Duration(minutes: 42));
    expect(u.undoTarget.value, m5);

    u.consume();
    expect(u.undoTarget.value, isNull);
    await emit(m5); // pozivatelj odmah izvodi povratni seek
    expect(u.undoTarget.value, isNull, reason: 'povratak ne nudi povratak');
  });

  test('10 — rupa u streamu (buffering stall) ne pali ponudu', () async {
    final u = build();
    await emit(m5);
    await emit(m5 + const Duration(milliseconds: 200));
    await Future<void>.delayed(afterWindow);
    await emit(m5 + const Duration(milliseconds: 200));
    await emitNatural(m5 + const Duration(milliseconds: 200));
    expect(u.undoTarget.value, isNull);
  });

  test('11 — skakanje po poglavljima drži PRVO sidro', () async {
    final u = build();
    final watched = await emitNatural(m5, steps: 30);
    await emit(const Duration(minutes: 42));
    await emitNatural(const Duration(minutes: 42), steps: 25); // 5 s gleda
    await emit(const Duration(minutes: 12));
    await emitNatural(const Duration(minutes: 12), steps: 25);
    await emit(const Duration(hours: 1));
    expect(u.undoTarget.value, watched,
        reason: 'sidro je mjesto gledanja, ne mjesta razgledavanja');
    expect(u.offer.value?.fresh, isTrue, reason: 'svaki skok osvježi ponudu');
  });

  test('12 — suppress (resume / deep link) gasi zatečenu ponudu', () async {
    final u = build();
    await emit(m5);
    await emit(const Duration(minutes: 42));
    expect(u.undoTarget.value, isNotNull);

    u.suppress(window: window);
    await emit(const Duration(minutes: 20));
    expect(u.undoTarget.value, isNull);
  });

  test('13 — smiri se na novom mjestu → ponuda nestaje', () async {
    final u = build();
    await emit(m5);
    await emit(const Duration(minutes: 42));
    await emitNatural(const Duration(minutes: 42), steps: 45); // 9 s
    expect(u.undoTarget.value, m5);
    await emitNatural(const Duration(minutes: 42, seconds: 9), steps: 10);
    expect(u.undoTarget.value, isNull);
  });

  test('14 — ručni skok blizu sidra = vratio se sam', () async {
    final u = build();
    await emit(m5);
    await emit(const Duration(minutes: 42));
    await emit(m5 + const Duration(seconds: 4));
    expect(u.undoTarget.value, isNull);
  });

  test('15 — prirodnim tijekom stigao do sidra', () async {
    final u = build();
    await emit(m5);
    await emit(m5 - const Duration(seconds: 30)); // skok unatrag 30 s
    expect(u.undoTarget.value, m5);
    await emitNatural(m5 - const Duration(seconds: 1), steps: 10);
    expect(u.undoTarget.value, isNull);
  });

  test('16 — dismiss() gasi ponudu; kratko razgledavanje poslije ne nudi '
      'povratak na odbačeno mjesto', () async {
    final u = build();
    await emit(m5);
    await emit(const Duration(minutes: 42));
    u.dismiss();
    expect(u.undoTarget.value, isNull);
    await emitNatural(const Duration(minutes: 42), steps: 5); // 1 s
    await emit(const Duration(minutes: 20));
    expect(u.undoTarget.value, isNull);
  });

  test('17 — bez mjesta gledanja (odbačeno, kratko razgledavanje) skok ništa '
      'ne nudi', () async {
    final u = build();
    await emit(m5);
    await emit(const Duration(minutes: 42));
    u.dismiss();
    await emitNatural(const Duration(minutes: 42), steps: 5);
    await emit(const Duration(minutes: 50));
    expect(u.undoTarget.value, isNull);
  });

  test('18 — dispose prestaje slušati stream', () async {
    final u = build();
    await emit(m5);
    u.dispose();
    undo = null;
    await emit(const Duration(minutes: 42));
  });
}
