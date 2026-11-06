/// `/c/:slug` za kanal bez statičnog listinga (katalog S10): zaglavlje iz
/// kataloga, kanal s jednom epizodom, paginacija, 404, nedostupno, Tier 1
/// i dalje ide statičnim putem, brend bez kataloga zadržava staru grešku, i
/// ruter predaje izvorni slug. Bez mreže: listing ide kroz `MockClient`, a
/// katalog kroz lažni `CatalogClient.instance` (odluka 806).
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:podcast_core/l10n/app_localizations.dart';
import 'package:podcast_core/router/app_router.dart';
import 'package:podcast_core/screens/channel/channel_screen.dart';
import 'package:podcast_core/screens/channels/all_channels_screen.dart';
import 'package:podcast_core/services/catalog_client.dart';
import 'package:podcast_core/services/cdn_json_cache.dart';
import 'package:podcast_core/services/cdn_store.dart';
import 'package:podcast_core/services/channel_cache.dart';
import 'package:podcast_core/widgets/follow_button.dart';

import 'support/fake_catalog_channels.dart';
import 'support/fake_catalog_days.dart' show fakeDayCard;

class _NoStore implements CdnStore {
  @override
  Future<StoredEntry?> get(StoreBucket b, String url) async => null;
  @override
  Future<void> put(StoreBucket b, String url, StoredEntry e) async {}
  @override
  Future<void> clear() async {}
  @override
  bool supports(StoreBucket b) => false;
}

/// Statični listinzi: samo `radio_mreznica` postoji, sve ostalo je 404.
final List<String> _cdnAsked = [];
CdnJsonCache _cdn() => CdnJsonCache(
  store: _NoStore(),
  enabled: false,
  client: MockClient((req) async {
    _cdnAsked.add(req.url.path);
    if (req.url.path.endsWith('/channels/data/radio_mreznica.json')) {
      return http.Response.bytes(
        utf8.encode(
          '{"id":"radio_mreznica","name":"Radio Mrežnica","videos":[]}',
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    return http.Response('not found', 404);
  }),
);

late GoRouter _router;
final List<String> _opened = [];

/// Ruta `/c/:slug` kao u `app_router.dart` (bez TV grane).
Widget _harness(String initial) {
  _router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('home')),
      ),
      GoRoute(
        path: '/channels',
        builder: (_, _) => const Scaffold(body: Text('svi kanali')),
      ),
      GoRoute(
        path: '/c/:slug',
        pageBuilder: (_, state) {
          final slug = state.pathParameters['slug']!;
          return NoTransitionPage(
            key: ValueKey('channel-$slug'),
            child: ChannelScreen(
              channelId: slug.replaceAll('-', '_'),
              catalogSlug: slug,
            ),
          );
        },
      ),
      for (final p in ['/v/:id', '/m/:id'])
        GoRoute(
          path: p,
          builder: (_, state) {
            _opened.add(state.uri.path);
            return const Scaffold(body: Text('epizoda'));
          },
        ),
    ],
  );
  return MaterialApp.router(
    routerConfig: _router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('hr'),
  );
}

List<CatalogCard> _cards(String prefix, int n) => [
  for (var i = 0; i < n; i++)
    fakeDayCard(
      '$prefix${i.toString().padLeft(2, '0')}',
      channel: 'Tribina',
      tier: 2,
    ),
];

void main() {
  late CatalogClient originalCatalog;
  late CdnJsonCache originalCdn;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    originalCatalog = CatalogClient.instance;
    originalCdn = CdnJsonCache.instance;
    CdnJsonCache.instance = _cdn();
    channelCache.resetForTest();
    _cdnAsked.clear();
    _opened.clear();
  });

  tearDown(() {
    CatalogClient.instance = originalCatalog;
    CdnJsonCache.instance = originalCdn;
    channelCache.resetForTest();
  });

  testWidgets('Tier 2: zaglavlje, iskrena oznaka, epizode, tap → /v/<id>', (
    tester,
  ) async {
    final fake = FakeCatalogChannels(
      channels: {
        'sbs-croatian': fakeCatalogChannel(
          'sbs-croatian',
          name: 'SBS Croatian',
          processedCount: 3,
        ),
      },
      episodePages: {
        'sbs-croatian': fakeEpisodesPage('sbs-croatian', _cards('s', 3)),
      },
    );
    CatalogClient.instance = fake;
    await tester.pumpWidget(_harness('/c/sbs-croatian'));
    await tester.pumpAndSettle();

    // Statični listing je pitan prvi (ID s podvlakom), katalog s izvornim slugom.
    expect(_cdnAsked.single, endsWith('/channels/data/sbs_croatian.json'));
    expect(
      fake.asked,
      containsAll(['channel|sbs-croatian', 'episodes|sbs-croatian|']),
    );
    expect(find.text('SBS Croatian'), findsWidgets);
    expect(find.text('Ne pratimo stalno'), findsOneWidget);
    expect(find.textContaining('ne pratimo stalno, pa ovdje'), findsOneWidget);
    expect(find.textContaining('3 obrađene epizode'), findsOneWidget);
    expect(find.text('Obrađene epizode'), findsOneWidget);
    // Bez praćenja, izloga oglasa i preuzimanja vlasništva.
    expect(find.byType(FollowButton), findsNothing);
    expect(find.byIcon(Icons.campaign_outlined), findsNothing);
    expect(find.byIcon(Icons.verified_user_outlined), findsNothing);

    await tester.tap(find.text('Epizoda s01'));
    await tester.pumpAndSettle();
    expect(_opened, ['/v/s01']);
  });

  testWidgets('kanal s jednom epizodom izgleda namjerno', (tester) async {
    CatalogClient.instance = FakeCatalogChannels(
      channels: {
        'vez-sv-antuna': fakeCatalogChannel(
          'vez-sv-antuna',
          name: 'VEZ sv. Antuna',
          processedCount: 1,
          latest: '2026-11-04',
          youtubeChannelId: 'UCdd4vcXePSZGFGXz2Z7AZeQ',
        ),
      },
      episodePages: {
        'vez-sv-antuna': fakeEpisodesPage('vez-sv-antuna', _cards('v', 1)),
      },
    );
    await tester.pumpWidget(_harness('/c/vez-sv-antuna'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 obrađena epizoda'), findsOneWidget);
    expect(find.textContaining('zadnja'), findsOneWidget);
    expect(find.text('Epizoda v00'), findsOneWidget);
    expect(find.text('Kanal na YouTubeu'), findsOneWidget);
    expect(find.text('Učitaj još'), findsNothing);
  });

  testWidgets('paginacija: gumb na dnu učitava nastavak bez duplikata', (
    tester,
  ) async {
    final fake = FakeCatalogChannels(
      channels: {'tribina': fakeCatalogChannel('tribina', name: 'Tribina')},
      episodePages: {
        'tribina': fakeEpisodesPage('tribina', _cards('t', 2), next: 'K1'),
        'tribina|K1': fakeEpisodesPage('tribina', [
          ..._cards('t', 1),
          ..._cards('u', 1),
        ]),
      },
    );
    CatalogClient.instance = fake;
    await tester.pumpWidget(_harness('/c/tribina'));
    await tester.pumpAndSettle();
    // Kratak popis puni ekran tek do pola: gumb je rezerva.
    await tester.tap(find.text('Učitaj još'));
    await tester.pumpAndSettle();
    expect(fake.asked.where((a) => a.startsWith('episodes|')), [
      'episodes|tribina|',
      'episodes|tribina|K1',
    ]);
    expect(find.text('Epizoda t00'), findsOneWidget);
    expect(find.text('Epizoda u00'), findsOneWidget);
    expect(find.text('Učitaj još'), findsNothing);
  });

  testWidgets('katalog 404 → „Kanal nije pronađen”, ne sirova greška', (
    tester,
  ) async {
    final fake = FakeCatalogChannels();
    CatalogClient.instance = fake;
    await tester.pumpWidget(_harness('/c/nepostoji-xyz'));
    await tester.pumpAndSettle();
    expect(find.text('Kanal nije pronađen'), findsOneWidget);
    expect(find.textContaining('HTTP'), findsNothing);
    // Slug s crticom pita i oblik s podvlakom (Tier 1 u katalogu).
    expect(fake.asked, contains('channel|nepostoji_xyz'));
  });

  testWidgets('katalog nedostupan → poruka i Pokušaj ponovno', (tester) async {
    final fake = FakeCatalogChannels(
      unavailable: true,
      channels: {'tribina': fakeCatalogChannel('tribina', name: 'Tribina')},
    );
    CatalogClient.instance = fake;
    await tester.pumpWidget(_harness('/c/tribina'));
    await tester.pumpAndSettle();
    expect(find.text('Kanal se trenutačno ne može učitati'), findsOneWidget);

    fake.unavailable = false;
    await tester.tap(find.text('Pokušaj ponovno'));
    await tester.pumpAndSettle();
    expect(find.text('Ne pratimo stalno'), findsOneWidget);
  });

  testWidgets('Tier 1 ide statičnim putem, katalog se ne pita', (tester) async {
    final fake = FakeCatalogChannels();
    CatalogClient.instance = fake;
    await tester.pumpWidget(_harness('/c/radio-mreznica'));
    await tester.pumpAndSettle();
    expect(_cdnAsked.single, endsWith('/channels/data/radio_mreznica.json'));
    expect(fake.asked, isEmpty);
    expect(find.text('Radio Mrežnica'), findsOneWidget);
    expect(find.byType(FollowButton), findsOneWidget);
    expect(find.text('Ne pratimo stalno'), findsNothing);
  });

  testWidgets('brend bez kataloga: stara greška, nijedan upit', (tester) async {
    final fake = FakeCatalogChannels(baseUrl: '');
    CatalogClient.instance = fake;
    await tester.pumpWidget(_harness('/c/sbs-croatian'));
    await tester.pumpAndSettle();
    expect(fake.asked, isEmpty);
    expect(find.textContaining('HTTP 404'), findsOneWidget);
  });

  testWidgets('ruter: /c/:slug predaje izvorni slug, ključ je slug; '
      '/channels?prikaz=svi otvara „Svi”', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final context = tester.element(find.byType(SizedBox));
    final router = createRouter();
    GoRoute route(String path) => router.configuration.routes
        .whereType<GoRoute>()
        .firstWhere((r) => r.path == path);
    GoRouterState state(
      String location,
      String fullPath,
      Map<String, String> p,
    ) => GoRouterState(
      router.configuration,
      uri: Uri.parse(location),
      matchedLocation: Uri.parse(location).path,
      fullPath: fullPath,
      pathParameters: p,
      pageKey: const ValueKey('test'),
    );

    final page =
        route('/c/:slug').pageBuilder!(
              context,
              state('/c/yt-UCfT_PJPR2vuqqKcCgEf3scA', '/c/:slug', {
                'slug': 'yt-UCfT_PJPR2vuqqKcCgEf3scA',
              }),
            )
            as NoTransitionPage;
    final screen = page.child as ChannelScreen;
    expect(screen.catalogSlug, 'yt-UCfT_PJPR2vuqqKcCgEf3scA');
    expect(screen.channelId, 'yt_UCfT_PJPR2vuqqKcCgEf3scA');
    expect(page.key, const ValueKey('channel-yt-UCfT_PJPR2vuqqKcCgEf3scA'));

    final all =
        route('/channels').pageBuilder!(
              context,
              state('/channels?prikaz=svi', '/channels', const {}),
            )
            as NoTransitionPage;
    expect((all.child as AllChannelsScreen).showDirectory, isTrue);
    expect(all.key, const ValueKey('all-channels-directory'));
  });
}
