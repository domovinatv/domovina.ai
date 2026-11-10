/// Filtar „Pratimo / Svi” na `/channels` (katalog S10): „Svi” je popis iz
/// `GET /directory` s beskonačnim listanjem i gumbom kao rezervom, kraj
/// popisa, pad stranice, nedostupan katalog, tap na kanal (Tier 1 s
/// crticom, Tier 2 doslovno) i brend bez kataloga, koji ne vidi ništa novo
/// i ne šalje zahtjev. Bez mreže (odluka 806).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:podcast_core/l10n/app_localizations.dart';
import 'package:podcast_core/screens/channels/all_channels_screen.dart';
import 'package:podcast_core/screens/channels/catalog_directory_view.dart';
import 'package:podcast_core/services/catalog_client.dart';
import 'package:podcast_core/services/cdn_json_cache.dart';
import 'package:podcast_core/services/cdn_store.dart';
import 'package:podcast_core/services/channel_cache.dart';
import 'package:podcast_core/services/person_channel_flag.dart';
import 'package:podcast_core/services/person_index_cache.dart';
import 'package:podcast_core/services/scroll_memory.dart';

import 'support/fake_catalog_channels.dart';

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

late GoRouter _router;
final List<String> _opened = [];

Widget _harness(String initial) {
  _router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/channels',
        pageBuilder: (_, state) {
          final svi = state.uri.queryParameters['prikaz'] == 'svi';
          return NoTransitionPage(
            key: ValueKey(svi ? 'all-channels-directory' : 'all-channels'),
            child: AllChannelsScreen(showDirectory: svi),
          );
        },
      ),
      GoRoute(
        path: '/c/:slug',
        builder: (_, state) {
          _opened.add(state.uri.path);
          return const Scaffold(body: Text('kanal'));
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

List<CatalogChannelInfo> _channels(String prefix, int n) => [
  for (var i = 0; i < n; i++)
    fakeCatalogChannel(
      '$prefix-${i.toString().padLeft(2, '0')}',
      name: 'Kanal $prefix ${i.toString().padLeft(2, '0')}',
    ),
];

void main() {
  late CatalogClient originalCatalog;
  late CdnJsonCache originalCdn;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PersonChannelFlag.instance.debugReset();
    personIndexCache.debugReset();
    channelCache.resetForTest();
    CatalogDirectoryView.resetMemo();
    ScrollMemory.instance.clearAll();
    originalCatalog = CatalogClient.instance;
    originalCdn = CdnJsonCache.instance;
    // Statični indeks kanala nije predmet testa: 404, popis „Pratimo” prazan.
    CdnJsonCache.instance = CdnJsonCache(
      store: _NoStore(),
      enabled: false,
      client: MockClient((_) async => http.Response('', 404)),
    );
    _opened.clear();
  });

  tearDown(() {
    CatalogClient.instance = originalCatalog;
    CdnJsonCache.instance = originalCdn;
    channelCache.resetForTest();
    PersonChannelFlag.instance.debugReset();
    personIndexCache.debugReset();
  });

  testWidgets('„Svi”: prva stranica, beskonačno listanje do kraja popisa', (
    tester,
  ) async {
    final fake = FakeCatalogChannels(
      directoryPages: {
        '': fakeDirectoryPage(_channels('a', 30), next: 'K1'),
        // Spremljena stranica može ponoviti kanal: ne crta se dvaput.
        'K1': fakeDirectoryPage([..._channels('a', 1), ..._channels('b', 5)]),
      },
    );
    CatalogClient.instance = fake;
    await tester.pumpWidget(_harness('/channels?prikaz=svi'));
    await tester.pumpAndSettle();

    expect(find.text('Pratimo'), findsOneWidget);
    expect(find.text('Svi'), findsOneWidget);
    // „Svi” nema pretragu ni sort, ima objašnjenje.
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('barem jednom obrađenom'), findsOneWidget);
    expect(find.text('Kanal a 00'), findsOneWidget);
    expect(fake.asked, ['directory|']);

    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await tester.pumpAndSettle();
    expect(fake.asked, ['directory|', 'directory|K1']);
    expect(find.text('Kanal b 04'), findsOneWidget);
    expect(find.text('Učitaj još'), findsNothing);
    expect(find.text('Kanal a 00'), findsNothing); // odskrolan, ne dupli
  });

  testWidgets('„Svi” na desktopu: kartice u stupcima do 360 px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    CatalogClient.instance = FakeCatalogChannels(
      directoryPages: {'': fakeDirectoryPage(_channels('a', 8))},
    );
    await tester.pumpWidget(_harness('/channels?prikaz=svi'));
    await tester.pumpAndSettle();

    // (1400 - 32) / 360 → 3 stupca.
    double top(String t) => tester.getTopLeft(find.text(t)).dy;
    double left(String t) => tester.getTopLeft(find.text(t)).dx;
    expect(top('Kanal a 01'), top('Kanal a 00'));
    expect(top('Kanal a 02'), top('Kanal a 00'));
    expect(top('Kanal a 03'), greaterThan(top('Kanal a 00')));
    expect(left('Kanal a 03'), left('Kanal a 00'));
    expect(left('Kanal a 01') - left('Kanal a 00'), greaterThan(400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tap: Tier 2 slug doslovno, Tier 1 s crticom', (tester) async {
    CatalogClient.instance = FakeCatalogChannels(
      directoryPages: {
        '': fakeDirectoryPage([
          fakeCatalogChannel('sbs-croatian', name: 'SBS Croatian'),
          fakeCatalogChannel(
            'radio_mreznica',
            name: 'Radio Mrežnica',
            tier: 1,
            processedCount: 225,
          ),
        ]),
      },
    );
    await tester.pumpWidget(_harness('/channels?prikaz=svi'));
    await tester.pumpAndSettle();
    // Oznaka samo uz Tier 2.
    expect(find.text('Ne pratimo stalno'), findsOneWidget);
    expect(find.textContaining('225 obrađenih epizoda'), findsOneWidget);

    await tester.tap(find.text('SBS Croatian'));
    await tester.pumpAndSettle();
    _router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Radio Mrežnica'));
    await tester.pumpAndSettle();
    expect(_opened, ['/c/sbs-croatian', '/c/radio-mreznica']);
  });

  testWidgets('„Pratimo” je zadan i ne pita katalog; tap na „Svi” pita', (
    tester,
  ) async {
    final fake = FakeCatalogChannels(
      directoryPages: {'': fakeDirectoryPage(_channels('a', 2))},
    );
    CatalogClient.instance = fake;
    await tester.pumpWidget(_harness('/channels'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(fake.asked, isEmpty);

    await tester.tap(find.text('Svi'));
    await tester.pumpAndSettle();
    expect(fake.asked, ['directory|']);
    expect(find.text('Kanal a 01'), findsOneWidget);
    // Kratak popis bez kursora: nema gumba.
    expect(find.text('Učitaj još'), findsNothing);
  });

  testWidgets('pad sljedeće stranice: popis ostaje, gumb nudi ponovno', (
    tester,
  ) async {
    final fake = FakeCatalogChannels(
      directoryPages: {
        '': fakeDirectoryPage(_channels('a', 2), next: 'K1'),
        'K1': const CatalogDirectoryUnavailable(),
      },
    );
    CatalogClient.instance = fake;
    await tester.pumpWidget(_harness('/channels?prikaz=svi'));
    await tester.pumpAndSettle();
    // Dva retka ne pune ekran: gumb je rezerva.
    await tester.tap(find.text('Učitaj još'));
    await tester.pumpAndSettle();
    expect(find.text('Nismo uspjeli učitati nastavak popisa.'), findsOneWidget);
    expect(find.text('Kanal a 00'), findsOneWidget);

    fake.directoryPages['K1'] = fakeDirectoryPage(_channels('c', 1));
    await tester.tap(find.text('Pokušaj ponovno'));
    await tester.pumpAndSettle();
    expect(find.text('Kanal c 00'), findsOneWidget);
    expect(find.text('Pokušaj ponovno'), findsNothing);
  });

  testWidgets('katalog nedostupan → poruka i Pokušaj ponovno', (tester) async {
    final fake = FakeCatalogChannels(
      unavailable: true,
      directoryPages: {'': fakeDirectoryPage(_channels('a', 1))},
    );
    CatalogClient.instance = fake;
    await tester.pumpWidget(_harness('/channels?prikaz=svi'));
    await tester.pumpAndSettle();
    expect(
      find.text('Popis svih kanala trenutačno nije dostupan'),
      findsOneWidget,
    );
    fake.unavailable = false;
    await tester.tap(find.text('Pokušaj ponovno'));
    await tester.pumpAndSettle();
    expect(find.text('Kanal a 00'), findsOneWidget);
  });

  testWidgets(
    'brend bez kataloga: bez chipova i bez zahtjeva, i uz ?prikaz=svi',
    (tester) async {
      final fake = FakeCatalogChannels(
        baseUrl: '',
        directoryPages: {'': fakeDirectoryPage(_channels('a', 1))},
      );
      CatalogClient.instance = fake;
      await tester.pumpWidget(_harness('/channels?prikaz=svi'));
      await tester.pumpAndSettle();
      expect(find.text('Pratimo'), findsNothing);
      expect(find.text('Svi'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(fake.asked, isEmpty);
    },
  );

  testWidgets('remount: popis iz memoa, bez novog zahtjeva', (tester) async {
    final fake = FakeCatalogChannels(
      directoryPages: {'': fakeDirectoryPage(_channels('a', 3))},
    );
    CatalogClient.instance = fake;
    await tester.pumpWidget(_harness('/channels?prikaz=svi'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_harness('/channels?prikaz=svi'));
    await tester.pumpAndSettle();
    expect(find.text('Kanal a 02'), findsOneWidget);
    expect(fake.asked, ['directory|']);
  });
}
