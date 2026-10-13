import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:podcast_core/l10n/app_localizations.dart';
import 'package:podcast_core/models/channel_detail.dart';
import 'package:podcast_core/screens/home/search_overlay.dart';
import 'package:podcast_core/services/channel_cache.dart';

/// Pretraga (Cmd+K paleta / ekran pretrage na mobitelu).
///
/// Povod 13.10.2026.: korisnik na Androidu (moto g86, Mali-G615) upisao
/// „fra", razmak i drugu riječ, a vidio je „frastje". Unos je bio ispravan
/// (DOM input je nosio „fra stje"); skwasm na Mali GPU-u krivo je crtao
/// glifove pod `ScaleTransition`-om kojim se paleta otvarala. Test drži da
/// polje za upis nikad nije pod scale transformom.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    channelCache.resetForTest();
    channelCache.seedForTest(ChannelDetail(
      version: '1.0',
      id: 'budi_frajer',
      name: 'Budi Frajer',
      youtubeChannelUrl: 'https://youtube.com/@budifrajer',
      videoCount: 2,
      totalDurationSeconds: 0,
      videos: const [
        ChannelVideo(
            id: 'a1', title: 'Propovijed fra Stjepana Brčine', date: '2026-10-01'),
        ChannelVideo(id: 'a2', title: 'Afrika i misije', date: '2026-10-02'),
      ],
    ));
  });

  Future<void> open(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: TextButton(
            onPressed: () => showSearchOverlay(
              context,
              channels: const [],
              onSelectChannel: (_) {},
              onSelectVideo: (_) {},
              onSelectVideoAt: (_, _) {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('hr'),
      routerConfig: router,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder field() => find.byKey(const ValueKey('search-overlay-field'));

  for (final (name, size) in [
    ('mobitel', const Size(390, 844)),
    ('desktop', const Size(1280, 800)),
  ]) {
    testWidgets('$name: polje nije pod ScaleTransition/scale transformom',
        (tester) async {
      await open(tester, size);
      expect(field(), findsOneWidget);
      expect(
          find.ancestor(of: field(), matching: find.byType(ScaleTransition)),
          findsNothing);
      // Nijedan Transform iznad polja ne smije skalirati.
      for (final t in tester.widgetList<Transform>(
          find.ancestor(of: field(), matching: find.byType(Transform)))) {
        expect(t.transform.getMaxScaleOnAxis(), 1.0);
      }
    });
  }

  testWidgets('mobitel: pretraga preko cijelog ekrana, iznad tipkovnice',
      (tester) async {
    await open(tester, const Size(390, 844));
    // Tipkovnica od 300 px.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    final fieldBox = tester.getRect(field());
    expect(fieldBox.top, lessThan(80), reason: 'polje je na vrhu ekrana');
    expect(find.byTooltip('Zatvori'), findsOneWidget,
        reason: 'strelica natrag zatvara pretragu');
  });

  testWidgets('drugu riječ se može upisati i ona sužava rezultate',
      (tester) async {
    await open(tester, const Size(390, 844));
    await tester.enterText(field(), 'fra');
    await tester.pump(const Duration(milliseconds: 200));
    // „fra" hvata i „Afrika" (podniz), i fra Stjepana.
    expect(find.textContaining('Afrika', findRichText: true), findsOneWidget);

    await tester.enterText(field(), 'fra ');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(field(), 'fra stjepan');
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<TextField>(field()).controller!.text, 'fra stjepan');
    expect(find.textContaining('Afrika', findRichText: true), findsNothing);
    expect(find.textContaining('Brčine', findRichText: true), findsOneWidget);

    // Pusti semantički debounce i neuspjeli mrežni zahtjev da se završe.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });
}
