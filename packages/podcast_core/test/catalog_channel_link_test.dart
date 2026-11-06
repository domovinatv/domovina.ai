/// Link na kanal iz kataloga (S10): Tier 2 kanal od S10 ima `/c/` rutu, pa
/// ime kanala na kartici raila „Danas u korpusu” i u retku `/dani/` vodi na
/// `/c/<slug>`, a ostatak kartice i dalje na epizodu. Kartica bez kanala
/// ostaje bez linka.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:podcast_core/l10n/app_localizations.dart';
import 'package:podcast_core/screens/catalog_day/catalog_day_screen.dart';
import 'package:podcast_core/screens/home/catalog_day_rail.dart';
import 'package:podcast_core/services/catalog_client.dart';

import 'support/fake_catalog_days.dart';

DateTime _clock() => DateTime(2026, 11, 6, 12, 38);

final List<String> _visited = [];

Widget _harness(String initial) {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: SingleChildScrollView(
            child: CatalogDayRail(
              isMobile: true,
              onVideoTap: (id) => _visited.add('/v/$id'),
              clock: _clock,
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/dani/:datum',
        builder: (_, state) => CatalogDayScreen(
          date: state.pathParameters['datum']!,
          clock: _clock,
        ),
      ),
      for (final p in ['/c/:slug', '/v/:id'])
        GoRoute(
          path: p,
          builder: (_, state) {
            _visited.add(state.uri.path);
            return const Scaffold(body: Text('odredište'));
          },
        ),
    ],
  );
  return MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('hr'),
  );
}

FakeCatalogDays _fake(String date) => FakeCatalogDays(
  pages: {
    date: fakeDayPage(date, [
      fakeDayCard(
        'aaaaaaaaaaa',
        title: 'Prva',
        channel: 'Tribina',
        tier: 2,
        date: date,
      ),
      fakeDayCard('bbbbbbbbbbb', title: 'Druga', date: date),
    ]),
  },
);

void main() {
  late CatalogClient original;

  setUp(() {
    original = CatalogClient.instance;
    CatalogDayRail.resetMemo();
    _visited.clear();
  });

  tearDown(() {
    CatalogClient.instance = original;
    CatalogDayRail.resetMemo();
  });

  testWidgets('rail: ime Tier 2 kanala vodi na /c/<slug>, kartica na epizodu', (
    tester,
  ) async {
    CatalogClient.instance = _fake('2026-11-06');
    await tester.pumpWidget(_harness('/'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('TRIBINA'));
    await tester.pumpAndSettle();
    expect(_visited, ['/c/tribina']);
  });

  testWidgets('rail: tap na naslov i dalje otvara epizodu', (tester) async {
    CatalogClient.instance = _fake('2026-11-06');
    await tester.pumpWidget(_harness('/'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prva'));
    await tester.pumpAndSettle();
    expect(_visited, ['/v/aaaaaaaaaaa']);
  });

  testWidgets('/dani/: ime kanala vodi na /c/<slug> (dva InkWella)', (
    tester,
  ) async {
    CatalogClient.instance = _fake('2026-11-04');
    await tester.pumpWidget(_harness('/dani/2026-11-04'));
    await tester.pumpAndSettle();
    expect(
      find.ancestor(of: find.text('TRIBINA'), matching: find.byType(InkWell)),
      findsNWidgets(2), // vlastiti + onaj retka
    );
    await tester.tap(find.text('TRIBINA'));
    await tester.pumpAndSettle();
    expect(_visited, ['/c/tribina']);
  });

  testWidgets('/dani/: redak bez kanala nema link kanala', (tester) async {
    CatalogClient.instance = _fake('2026-11-04');
    await tester.pumpWidget(_harness('/dani/2026-11-04'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Druga'));
    await tester.pumpAndSettle();
    expect(_visited, ['/v/bbbbbbbbbbb']);
  });
}
