import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_core/widgets/scrub_preview.dart';

void main() {
  group('scrubTimeAt', () {
    const total = Duration(hours: 2);

    test('rubovi tracka su 0 i kraj, uvlaka se poštuje', () {
      expect(
        scrubTimeAt(14, width: 328, inset: 14, total: total),
        Duration.zero,
      );
      expect(scrubTimeAt(314, width: 328, inset: 14, total: total), total);
      // Lijevo od tracka (u uvlaci) se ne ide ispod nule.
      expect(
        scrubTimeAt(0, width: 328, inset: 14, total: total),
        Duration.zero,
      );
    });

    test('sredina tracka je pola trajanja, na sekundu', () {
      expect(
        scrubTimeAt(164, width: 328, inset: 14, total: total),
        const Duration(hours: 1),
      );
      final t = scrubTimeAt(100, width: 328, inset: 14, total: total);
      expect(t.inMilliseconds % 1000, 0);
    });

    test('bez trajanja nema vremena', () {
      expect(
        scrubTimeAt(100, width: 328, inset: 14, total: Duration.zero),
        Duration.zero,
      );
    });
  });

  test('formatScrubTime', () {
    expect(formatScrubTime(const Duration(seconds: 5)), '0:05');
    expect(formatScrubTime(const Duration(minutes: 12, seconds: 3)), '12:03');
    expect(
      formatScrubTime(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
  });

  Widget host({required ValueChanged<double> onSlider}) => MaterialApp(
    home: Scaffold(
      body: Center(
        // Visina je fiksna: ograničen Slider se rastegne na cijelu visinu.
        child: SizedBox(
          width: 328,
          height: 48,
          child: ScrubPreview(
            total: const Duration(hours: 2),
            inset: 24,
            labelAt: (t) => t >= const Duration(hours: 1) ? 'Drugi dio' : null,
            child: Slider(value: 0, onChanged: onSlider),
          ),
        ),
      ),
    ),
  );

  testWidgets('hover mišem pokaže vrijeme i poglavlje', (tester) async {
    await tester.pumpWidget(host(onSlider: (_) {}));
    final rect = tester.getRect(find.byType(Slider));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: rect.center);
    await mouse.moveTo(rect.center);
    await tester.pump();
    expect(find.text('1:00:00'), findsOneWidget);
    expect(find.text('Drugi dio'), findsOneWidget);
    await mouse.moveTo(rect.center + const Offset(0, 200));
    await tester.pump();
    await tester.pump();
    expect(find.text('1:00:00'), findsNothing);
    await mouse.removePointer();
  });

  testWidgets('vučenje prstom pokaže vrijeme, a Slider i dalje dobiva drag', (
    tester,
  ) async {
    final values = <double>[];
    await tester.pumpWidget(host(onSlider: values.add));
    final rect = tester.getRect(find.byType(Slider));
    final finger = await tester.startGesture(
      rect.centerLeft + const Offset(24, 0),
    );
    await tester.pump();
    expect(find.text('0:00'), findsOneWidget);
    await finger.moveTo(rect.center);
    await tester.pump();
    expect(find.text('1:00:00'), findsOneWidget);
    expect(values, isNotEmpty);
    await finger.up();
    await tester.pump();
    expect(find.text('1:00:00'), findsNothing);
  });
}
