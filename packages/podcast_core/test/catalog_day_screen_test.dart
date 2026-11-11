/// Ekran `/dani/:datum` (S9): popis, paginacija po `next` kursoru, prazan
/// dan s ponudom prethodnog, neispravan datum, katalog nedostupan / brend bez
/// kataloga, prethodni/sljedeći dan kroz `goPeer` (ne iza današnjeg) i tap na
/// epizodu na `/v/<id>`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:podcast_core/l10n/app_localizations.dart';
import 'package:podcast_core/screens/catalog_day/catalog_day_screen.dart';
import 'package:podcast_core/services/catalog_client.dart';

import 'support/fake_catalog_days.dart';

DateTime _clock() => DateTime(2026, 11, 6, 12, 38);

late GoRouter _router;
final List<String> _opened = [];

/// Zadano je širina mobitela (popis u jednom stupcu); [width] ≥ 600 daje
/// desktop mrežu kao na `/c/<slug>`.
Widget _harness(String initial, {double width = 390}) {
  _router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('home')),
      ),
      GoRoute(
        path: '/dani/:datum',
        pageBuilder: (_, state) {
          final datum = state.pathParameters['datum']!;
          return NoTransitionPage(
            key: ValueKey('catalog-day-$datum'),
            child: CatalogDayScreen(date: datum, clock: _clock),
          );
        },
      ),
      GoRoute(
        path: '/v/:id',
        builder: (_, state) {
          _opened.add(state.pathParameters['id']!);
          return const Scaffold(body: Text('epizoda'));
        },
      ),
    ],
  );
  return Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: width,
      child: MaterialApp.router(
        routerConfig: _router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('hr'),
      ),
    ),
  );
}

String _location() =>
    _router.routerDelegate.currentConfiguration.uri.toString();

List<CatalogCard> _cards(String prefix, int n, {String date = '2026-11-04'}) =>
    [
      for (var i = 0; i < n; i++)
        fakeDayCard('$prefix${i.toString().padLeft(2, '0')}', date: date),
    ];

void main() {
  late CatalogClient original;

  setUp(() {
    original = CatalogClient.instance;
    _opened.clear();
  });

  tearDown(() => CatalogClient.instance = original);

  testWidgets('popis: datum na hrvatskom, kanal, tap otvara /v/<id>', (
    tester,
  ) async {
    CatalogClient.instance = FakeCatalogDays(
      pages: {
        '2026-11-04': fakeDayPage('2026-11-04', [
          fakeDayCard('aaaaaaaaaaa', title: 'Prva', channel: 'Tribina'),
          fakeDayCard('bbbbbbbbbbb', title: 'Druga'),
        ]),
      },
    );
    await tester.pumpWidget(_harness('/dani/2026-11-04'));
    await tester.pumpAndSettle();

    expect(find.text('4. studenoga 2026.'), findsOneWidget);
    expect(find.text('EPIZODE DANA'), findsOneWidget);
    expect(find.text('Prva'), findsOneWidget);
    expect(find.text('TRIBINA'), findsOneWidget);
    expect(find.text('Učitaj još'), findsNothing, reason: 'next je null');

    await tester.tap(find.text('Prva'));
    await tester.pumpAndSettle();
    expect(_opened, ['aaaaaaaaaaa']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('meta: sat objave, trajanje i ocjena; bez podataka ništa', (
    tester,
  ) async {
    final published = DateTime.utc(2026, 11, 4, 17, 5);
    CatalogClient.instance = FakeCatalogDays(
      pages: {
        '2026-11-04': fakeDayPage('2026-11-04', [
          fakeDayCard(
            'aaaaaaaaaaa',
            title: 'Prva',
            durationSeconds: 3961,
            magisteriumScore: 79,
            publishedAt: published,
          ),
          fakeDayCard('bbbbbbbbbbb', title: 'Druga', tier: 2),
        ]),
      },
    );
    await tester.pumpWidget(_harness('/dani/2026-11-04'));
    await tester.pumpAndSettle();

    final local = published.toLocal();
    final hm =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    expect(find.text(hm), findsOneWidget);
    expect(find.text('1:06:01'), findsOneWidget);
    expect(find.text('79'), findsOneWidget);
    expect(find.byIcon(Icons.church), findsOneWidget);
    expect(find.byIcon(Icons.timelapse), findsOneWidget, reason: 'Druga nema');
    expect(tester.takeException(), isNull);

    // Isto u desktop mreži.
    await tester.pumpWidget(_harness('/dani/2026-11-04', width: 1200));
    await tester.pumpAndSettle();
    expect(find.text('1:06:01'), findsOneWidget);
    expect(find.text('79'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop: mreža kartica u više stupaca, kao na /c/<slug>', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    CatalogClient.instance = FakeCatalogDays(
      pages: {'2026-11-04': fakeDayPage('2026-11-04', _cards('g_', 8))},
    );
    await tester.pumpWidget(_harness('/dani/2026-11-04', width: 1400));
    await tester.pumpAndSettle();

    expect(find.byType(ListView), findsNothing);
    // (1400 - 32) / 300 → 4 stupca: prve četiri kartice u istom retku.
    final tops = [
      for (var i = 0; i < 5; i++)
        tester.getTopLeft(find.text('Epizoda g_0$i')).dy,
    ];
    expect(tops.sublist(0, 4).toSet(), hasLength(1));
    expect(tops[4], greaterThan(tops[0]));
    final left0 = tester.getTopLeft(find.text('Epizoda g_00')).dx;
    final left1 = tester.getTopLeft(find.text('Epizoda g_01')).dx;
    expect(left1 - left0, greaterThan(300));

    await tester.tap(find.text('Epizoda g_05'));
    await tester.pumpAndSettle();
    expect(_opened, ['g_05']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('paginacija: popis koji ne puni ekran sam traži nastavak', (
    tester,
  ) async {
    final fake = FakeCatalogDays(
      pages: {
        '2026-11-04': fakeDayPage('2026-11-04', _cards('p1_', 3), next: 'K1'),
        '2026-11-04|K1': fakeDayPage('2026-11-04', _cards('p2_', 2)),
      },
    );
    CatalogClient.instance = fake;
    await tester.pumpWidget(_harness('/dani/2026-11-04'));
    await tester.pumpAndSettle();

    expect(fake.asked, ['2026-11-04', '2026-11-04|K1']);
    expect(find.text('Epizoda p1_02'), findsOneWidget);
    expect(find.text('Epizoda p2_01'), findsOneWidget);
    expect(find.text('Učitaj još'), findsNothing);
  });

  testWidgets(
    'revalidacija: spremljenih 26 bez next → svježih 30 + next, nastavak radi',
    (tester) async {
      final fake = FakeCatalogDays(
        pages: {
          '2026-11-04': fakeDayPage('2026-11-04', _cards('p1_', 26)),
          '2026-11-04|K1': fakeDayPage('2026-11-04', _cards('p2_', 4)),
        },
      );
      fake.revalidated['2026-11-04'] = CatalogDayPage(
        date: '2026-11-04',
        items: _cards('p1_', 30),
        next: 'K1',
      );
      CatalogClient.instance = fake;
      await tester.pumpWidget(_harness('/dani/2026-11-04'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Epizoda p1_29'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Epizoda p1_29'), findsOneWidget);
      await tester.pumpAndSettle();
      // Beskonačno listanje (ili „Učitaj još”) sada ima kursor.
      if (!fake.asked.contains('2026-11-04|K1')) {
        await tester.scrollUntilVisible(
          find.text('Učitaj još'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('Učitaj još'));
        await tester.pumpAndSettle();
      }
      expect(fake.asked, ['2026-11-04', '2026-11-04|K1']);
    },
  );

  testWidgets('revalidacija nakon listanja dalje: popis ostaje, novi na kraj', (
    tester,
  ) async {
    final fake = FakeCatalogDays(
      pages: {
        '2026-11-04': fakeDayPage('2026-11-04', _cards('p1_', 30), next: 'K1'),
        '2026-11-04|K1': fakeDayPage('2026-11-04', _cards('p2_', 3)),
      },
    );
    CatalogClient.instance = fake;
    await tester.pumpWidget(_harness('/dani/2026-11-04'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await tester.pumpAndSettle();
    expect(fake.asked, ['2026-11-04', '2026-11-04|K1']);

    // Revalidacija prve stranice stiže nakon što je korisnik listao dalje:
    // nova epizoda (p1_30) ide na kraj, ništa se ne duplicira, kursor ostaje.
    fake.onUpdates['2026-11-04']!(
      CatalogDayPage(date: '2026-11-04', items: _cards('p1_', 31), next: 'K9'),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await tester.pumpAndSettle();
    expect(find.text('Epizoda p1_30'), findsOneWidget);
    expect(find.text('Epizoda p2_02'), findsOneWidget);
    expect(fake.asked, [
      '2026-11-04',
      '2026-11-04|K1',
    ], reason: 'K9 se ne traži');
  });

  testWidgets('beskonačno listanje: scroll do dna povuče sljedeću stranicu', (
    tester,
  ) async {
    final fake = FakeCatalogDays(
      pages: {
        '2026-11-04': fakeDayPage('2026-11-04', _cards('p1_', 30), next: 'K1'),
        '2026-11-04|K1': fakeDayPage('2026-11-04', _cards('p2_', 5)),
      },
    );
    CatalogClient.instance = fake;
    await tester.pumpWidget(_harness('/dani/2026-11-04'));
    await tester.pumpAndSettle();
    expect(fake.asked, ['2026-11-04']);

    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await tester.pumpAndSettle();
    expect(fake.asked, ['2026-11-04', '2026-11-04|K1']);
  });

  testWidgets('pad sljedeće stranice: poruka i „Pokušaj ponovno”', (
    tester,
  ) async {
    final fake = FakeCatalogDays(
      pages: {
        '2026-11-04': fakeDayPage('2026-11-04', _cards('p1_', 2), next: 'K1'),
        '2026-11-04|K1': const CatalogDayUnavailable(),
      },
    );
    CatalogClient.instance = fake;
    await tester.pumpWidget(_harness('/dani/2026-11-04'));
    await tester.pumpAndSettle();
    // Dva retka ne pune ekran: nastavak se traži sam, bez tapa.
    expect(fake.asked, ['2026-11-04', '2026-11-04|K1']);

    expect(find.text('Nismo uspjeli učitati još epizoda.'), findsOneWidget);
    expect(find.text('Pokušaj ponovno'), findsOneWidget);
    expect(find.text('Epizoda p1_01'), findsOneWidget, reason: 'popis ostaje');
  });

  testWidgets('prazan dan: prazno stanje, gumb vodi na prethodni dan', (
    tester,
  ) async {
    CatalogClient.instance = FakeCatalogDays();
    await tester.pumpWidget(_harness('/dani/2026-11-06'));
    await tester.pumpAndSettle();

    expect(find.text('Za ovaj dan još nema epizoda'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Prethodni dan'));
    await tester.pumpAndSettle();
    expect(_location(), '/dani/2026-11-05');
    expect(find.text('5. studenoga 2026.'), findsOneWidget);
  });

  testWidgets('sljedeći dan ne ide iza današnjeg', (tester) async {
    CatalogClient.instance = FakeCatalogDays();
    await tester.pumpWidget(_harness('/dani/2026-11-06'));
    await tester.pumpAndSettle();

    final next = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right),
    );
    expect(next.onPressed, isNull);

    await tester.tap(find.byTooltip('Prethodni dan'));
    await tester.pumpAndSettle();
    expect(_location(), '/dani/2026-11-05');

    await tester.tap(find.byTooltip('Sljedeći dan'));
    await tester.pumpAndSettle();
    expect(_location(), '/dani/2026-11-06');
  });

  testWidgets('prethodni dan preko granice mjeseca', (tester) async {
    CatalogClient.instance = FakeCatalogDays();
    await tester.pumpWidget(_harness('/dani/2026-11-01'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Prethodni dan'));
    await tester.pumpAndSettle();
    expect(_location(), '/dani/2026-10-31');
  });

  testWidgets('nevaljan datum: stanje pogreške bez upita', (tester) async {
    final fake = FakeCatalogDays();
    CatalogClient.instance = fake;
    await tester.pumpWidget(_harness('/dani/2026-02-30'));
    await tester.pumpAndSettle();

    expect(find.text('Neispravan datum'), findsOneWidget);
    expect(find.byTooltip('Prethodni dan'), findsNothing);
    expect(fake.asked, isEmpty);

    await tester.tap(find.text('Natrag na početnu'));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('katalog nedostupan: „nije dostupno” i „Pokušaj ponovno”', (
    tester,
  ) async {
    final fake = FakeCatalogDays(unavailable: true);
    CatalogClient.instance = fake;
    await tester.pumpWidget(_harness('/dani/2026-11-04'));
    await tester.pumpAndSettle();

    expect(
      find.text('Popis epizoda po danima trenutačno nije dostupan'),
      findsOneWidget,
    );
    fake
      ..unavailable = false
      ..pages['2026-11-04'] = fakeDayPage('2026-11-04', [
        fakeDayCard('ccccccccccc'),
      ]);
    await tester.tap(find.text('Pokušaj ponovno'));
    await tester.pumpAndSettle();
    expect(find.text('Epizoda ccccccccccc'), findsOneWidget);
  });

  testWidgets('brend bez kataloga: „nije dostupno” bez upita, bez retryja', (
    tester,
  ) async {
    final fake = FakeCatalogDays(baseUrl: '');
    CatalogClient.instance = fake;
    await tester.pumpWidget(_harness('/dani/2026-11-04'));
    await tester.pumpAndSettle();

    expect(
      find.text('Popis epizoda po danima trenutačno nije dostupan'),
      findsOneWidget,
    );
    expect(find.text('Pokušaj ponovno'), findsNothing);
    expect(find.text('Natrag na početnu'), findsOneWidget);
    expect(fake.asked, isEmpty);
  });
}
