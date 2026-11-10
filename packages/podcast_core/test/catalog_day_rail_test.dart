/// Home rail „Danas u korpusu” (S9): današnji dan, pad na jučer i do tri dana
/// unatrag, skriven kad je sve prazno, kad katalog nije dostupan ili ga brend
/// nema, a „Prikaži sve” vodi na `/dani/<datum>`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:podcast_core/brand/app_brand.dart';
import 'package:podcast_core/brand/domovina_brand.dart';
import 'package:podcast_core/l10n/app_localizations.dart';
import 'package:podcast_core/screens/home/catalog_day_rail.dart';
import 'package:podcast_core/services/catalog_client.dart';

import 'support/fake_catalog_days.dart';
import 'support/test_brands.dart';

/// 6. 11. 2026. u 12:38, kad je izmjereno da je današnji dan prazan.
DateTime _clock() => DateTime(2026, 11, 6, 12, 38);

String? _dayRoute;
final List<String> _tapped = [];

Widget _harness() {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: SingleChildScrollView(
            child: CatalogDayRail(
              isMobile: true,
              onVideoTap: _tapped.add,
              clock: _clock,
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/dani/:datum',
        builder: (_, state) {
          _dayRoute = state.pathParameters['datum'];
          return const Scaffold(body: Text('dan'));
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

void main() {
  late CatalogClient original;

  setUp(() {
    original = CatalogClient.instance;
    CatalogDayRail.resetMemo();
    _dayRoute = null;
    _tapped.clear();
  });

  tearDown(() {
    CatalogClient.instance = original;
    CatalogDayRail.resetMemo();
    AppBrand.init(domovinaBrand);
  });

  testWidgets('današnji dan s epizodama: „Danas u korpusu”, naslov i kanal', (
    tester,
  ) async {
    final fake = FakeCatalogDays(
      pages: {
        '2026-11-06': fakeDayPage('2026-11-06', [
          fakeDayCard('aaaaaaaaaaa', title: 'Prva', channel: 'Tribina'),
          fakeDayCard('bbbbbbbbbbb', title: 'Druga'),
        ]),
      },
    );
    CatalogClient.instance = fake;
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.text('DANAS U KORPUSU'), findsOneWidget);
    expect(find.text('Prva'), findsOneWidget);
    expect(find.text('TRIBINA'), findsOneWidget);
    expect(find.text('Druga'), findsOneWidget);
    // Dvije epizode su ispod praga, a stariji dani prazni → ipak danas.
    expect(fake.asked, [
      '2026-11-06',
      '2026-11-05',
      '2026-11-04',
      '2026-11-03',
    ]);

    await tester.tap(find.text('Prva'));
    expect(_tapped, ['aaaaaaaaaaa']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('prazan danas → jučer, eyebrow „Jučer u korpusu”', (
    tester,
  ) async {
    final fake = FakeCatalogDays(
      pages: {
        '2026-11-05': fakeDayPage('2026-11-05', [fakeDayCard('ccccccccccc')]),
      },
    );
    CatalogClient.instance = fake;
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.text('JUČER U KORPUSU'), findsOneWidget);
    expect(find.text('Epizoda ccccccccccc'), findsOneWidget);
    // Jedna epizoda je ispod praga, pa rail pogleda i starije (prazne) dane.
    expect(fake.asked, [
      '2026-11-06',
      '2026-11-05',
      '2026-11-04',
      '2026-11-03',
    ]);
  });

  testWidgets('pun danas se pokazuje odmah, bez upita za jučer', (
    tester,
  ) async {
    final fake = FakeCatalogDays(
      pages: {
        '2026-11-06': fakeDayPage('2026-11-06', [
          for (var i = 0; i < CatalogDayRail.minEpisodes; i++)
            fakeDayCard('t${i}tttttttttt'.substring(0, 11)),
        ]),
      },
    );
    CatalogClient.instance = fake;
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.text('DANAS U KORPUSU'), findsOneWidget);
    expect(fake.asked, ['2026-11-06']);
  });

  testWidgets('tanak danas (2 iza ponoći) → pun jučer (10. 11. 2026.)', (
    tester,
  ) async {
    final fake = FakeCatalogDays(
      pages: {
        '2026-11-06': fakeDayPage('2026-11-06', [
          fakeDayCard('wskqG_JDCMY'),
          fakeDayCard('ih32PNrjdXU'),
        ]),
        '2026-11-05': fakeDayPage('2026-11-05', [
          for (var i = 0; i < 12; i++)
            fakeDayCard('j${i}jjjjjjjjjj'.substring(0, 11)),
        ]),
      },
    );
    CatalogClient.instance = fake;
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.text('JUČER U KORPUSU'), findsOneWidget);
    expect(find.text('Epizoda wskqG_JDCMY'), findsNothing);
    expect(fake.asked, ['2026-11-06', '2026-11-05']);
  });

  testWidgets('tri dana unatrag: eyebrow s datumom na hrvatskom', (
    tester,
  ) async {
    final fake = FakeCatalogDays(
      pages: {
        '2026-11-03': fakeDayPage('2026-11-03', [fakeDayCard('ddddddddddd')]),
      },
    );
    CatalogClient.instance = fake;
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.text('U KORPUSU · 3. STUDENOGA'), findsOneWidget);
    expect(fake.asked, [
      '2026-11-06',
      '2026-11-05',
      '2026-11-04',
      '2026-11-03',
    ]);
  });

  testWidgets('sva četiri dana prazna → rail se ne crta, ne ide dalje', (
    tester,
  ) async {
    final fake = FakeCatalogDays(
      pages: {
        // Peti dan unatrag ima epizode, ali je izvan prozora.
        '2026-11-02': fakeDayPage('2026-11-02', [fakeDayCard('eeeeeeeeeee')]),
      },
    );
    CatalogClient.instance = fake;
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.textContaining('KORPUSU'), findsNothing);
    expect(find.text('Prikaži sve'), findsNothing);
    expect(fake.asked, hasLength(4));
    expect(
      tester.getSize(find.byType(CatalogDayRail)).height,
      0,
      reason: 'skriven rail ne zauzima mjesto',
    );
  });

  testWidgets('katalog nedostupan → rail skriven nakon prvog upita', (
    tester,
  ) async {
    final fake = FakeCatalogDays(unavailable: true);
    CatalogClient.instance = fake;
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.textContaining('KORPUSU'), findsNothing);
    expect(fake.asked, ['2026-11-06']);
  });

  testWidgets('brend bez kataloga → nijedan upit, rail skriven', (
    tester,
  ) async {
    AppBrand.init(brandWithoutCatalog());
    // Bez vlastitog baseUrl-a klijent čita brend, kao u aplikaciji.
    final fake = FakeCatalogDays(baseUrl: '');
    CatalogClient.instance = fake;
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.textContaining('KORPUSU'), findsNothing);
    expect(fake.asked, isEmpty);
  });

  testWidgets('„Prikaži sve” vodi na /dani/<pokazani datum>', (tester) async {
    CatalogClient.instance = FakeCatalogDays(
      pages: {
        '2026-11-05': fakeDayPage('2026-11-05', [fakeDayCard('fffffffffff')]),
      },
    );
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Prikaži sve'));
    await tester.pumpAndSettle();
    expect(_dayRoute, '2026-11-05');
    expect(find.text('dan'), findsOneWidget);
  });
}
