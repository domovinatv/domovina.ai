import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_core/widgets/article_page_keys.dart';

void main() {
  late ScrollController controller;
  late bool active;

  Future<void> pump(WidgetTester tester, {bool withField = false}) async {
    controller = ScrollController();
    active = true;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArticlePageKeys(
            controller: controller,
            active: () => active,
            child: Row(
              children: [
                if (withField) const SizedBox(width: 200, child: TextField()),
                Expanded(
                  child: ListView.builder(
                    controller: controller,
                    itemCount: 200,
                    itemBuilder: (_, i) =>
                        SizedBox(height: 100, child: Text('$i')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  testWidgets('PageDown/PageUp pomiču članak bez fokusa u listi', (
    tester,
  ) async {
    await pump(tester);
    final viewport = controller.position.viewportDimension;
    await press(tester, LogicalKeyboardKey.pageDown);
    expect(controller.offset, closeTo(viewport * 0.8, 0.5));
    await press(tester, LogicalKeyboardKey.pageUp);
    expect(controller.offset, 0);
  });

  testWidgets('End ide na pravo dno lijene liste, Home na vrh', (
    tester,
  ) async {
    await pump(tester);
    await press(tester, LogicalKeyboardKey.end);
    expect(controller.offset, controller.position.maxScrollExtent);
    expect(controller.offset, 200 * 100 - controller.position.viewportDimension);
    await press(tester, LogicalKeyboardKey.home);
    expect(controller.offset, 0);
  });

  testWidgets('neaktivan (panel prekriva članak) — tipke ne diraju članak', (
    tester,
  ) async {
    await pump(tester);
    active = false;
    await press(tester, LogicalKeyboardKey.end);
    expect(controller.offset, 0);
  });

  testWidgets('u tekstnom polju Home/End pripadaju kursoru', (tester) async {
    await pump(tester, withField: true);
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.end);
    expect(controller.offset, 0);

    // Polje preda fokus ruti — tipke opet idu u članak.
    FocusManager.instance.primaryFocus!.unfocus();
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.end);
    expect(controller.offset, controller.position.maxScrollExtent);
  });
}
