import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_core/widgets/episode_panel_canvas.dart';
import 'package:podcast_core/widgets/thumb_drag_slider.dart';

/// Ugovor seek bara u panelu playera (prijava 20.11.2026.): swipe preko trake
/// zatvara panel i NE pomiče reprodukciju; prstom se vuče samo kružić, a
/// kratak dodir na traku i dalje skače.
void main() {
  final canvas = GlobalKey<EpisodePanelCanvasState>();
  late double value;
  late List<double> ends;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    value = 0.5;
    ends = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EpisodePanelCanvas(
            key: canvas,
            center: const SizedBox.expand(),
            right: Center(
              child: StatefulBuilder(
                builder: (context, setState) => SizedBox(
                  key: const Key('bar'),
                  height: 48,
                  child: ThumbDragSlider(
                    value: value,
                    inset: 14,
                    onChanged: (v) => setState(() => value = v),
                    onChangeEnd: ends.add,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    canvas.currentState!.open(EpisodePanelSide.right);
    await tester.pumpAndSettle();
  }

  Rect bar(WidgetTester tester) => tester.getRect(find.byKey(const Key('bar')));

  Offset thumb(WidgetTester tester) {
    final r = bar(tester);
    return Offset(r.left + 14 + value * (r.width - 28), r.center.dy);
  }

  testWidgets('swipe udesno preko trake zatvara panel i ne seeka', (
    tester,
  ) async {
    await pump(tester);
    final r = bar(tester);
    // Kreće na četvrtini trake — daleko od kružića na sredini.
    await tester.flingFrom(
      Offset(r.left + r.width * 0.2, r.center.dy),
      const Offset(300, 0),
      1500,
    );
    await tester.pumpAndSettle();

    expect(canvas.currentState!.openSide, isNull);
    expect(value, 0.5);
    expect(ends, isEmpty);
  });

  testWidgets('vučenje s kružića seeka relativno i ne zatvara panel', (
    tester,
  ) async {
    await pump(tester);
    final r = bar(tester);
    final track = r.width - 28;
    // Hvat 10 px desno od središta kružića: hvat sam ne smije pomaknuti.
    final g = await tester.startGesture(thumb(tester) + const Offset(10, 0));
    await g.moveBy(const Offset(30, 0));
    await g.moveBy(const Offset(30, 0));
    await g.up();
    await tester.pumpAndSettle();

    expect(canvas.currentState!.openSide, EpisodePanelSide.right);
    expect(ends, hasLength(1));
    expect(ends.single, closeTo(0.5 + 60 / track, 0.01));
  });

  testWidgets('dodir na traku skače na to mjesto', (tester) async {
    await pump(tester);
    final r = bar(tester);
    await tester.tapAt(Offset(r.left + 14 + (r.width - 28) * 0.25, r.center.dy));
    await tester.pumpAndSettle();

    expect(ends.single, closeTo(0.25, 0.01));
    expect(canvas.currentState!.openSide, EpisodePanelSide.right);
  });

  testWidgets('dodir na kružić bez pomaka ne seeka na staru vrijednost', (
    tester,
  ) async {
    await pump(tester);
    await tester.tapAt(thumb(tester));
    await tester.pumpAndSettle();
    expect(ends.single, closeTo(0.5, 0.01));
  });

  testWidgets('miš vuče s bilo kojeg mjesta trake', (tester) async {
    await pump(tester);
    final r = bar(tester);
    final g = await tester.startGesture(
      Offset(r.left + r.width * 0.2, r.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(const Offset(40, 0));
    await g.up();
    await tester.pumpAndSettle();
    expect(ends, hasLength(1));
    expect(canvas.currentState!.openSide, EpisodePanelSide.right);
  });
}
