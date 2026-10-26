/// Feature flagovi brenda (`FeatureFlags` u `lib/brand/brand_config.dart`).
///
/// Ugovor: s `domovinaBrand` (sve uključeno) aplikacija je ista kao prije
/// flagova; s ugašenim flagom značajka nema NI RUTU — deep-link na nju pada
/// u `errorPageBuilder` kao i svaki nepoznat URL. Provjere su jeftine (tablica
/// ruta + čisti `upTarget`), bez renderiranja ekrana koji traže mrežu.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:podcast_core/brand/app_brand.dart';
import 'package:podcast_core/brand/brand_config.dart';
import 'package:podcast_core/brand/domovina_brand.dart';
import 'package:podcast_core/router/app_router.dart';
import 'package:podcast_core/router/nav.dart';

/// `domovinaBrand` s drugim flagovima — `BrandConfig` nema `copyWith`, pa se
/// prepisuju sva polja (namjerno: novo obavezno polje mora se ovdje vidjeti).
BrandConfig brandWith(FeatureFlags flags) => BrandConfig(
      appName: domovinaBrand.appName,
      wordmark: domovinaBrand.wordmark,
      wordmarkAccent: domovinaBrand.wordmarkAccent,
      plusDisplayName: domovinaBrand.plusDisplayName,
      logPrefix: domovinaBrand.logPrefix,
      urlScheme: domovinaBrand.urlScheme,
      androidPackage: domovinaBrand.androidPackage,
      iosBundleId: domovinaBrand.iosBundleId,
      iosAppStoreId: domovinaBrand.iosAppStoreId,
      entitlement: domovinaBrand.entitlement,
      seed: domovinaBrand.seed,
      accent: domovinaBrand.accent,
      logoAsset: domovinaBrand.logoAsset,
      splashAsset: domovinaBrand.splashAsset,
      defaultLocale: domovinaBrand.defaultLocale,
      defaultEpisodeLanguage: domovinaBrand.defaultEpisodeLanguage,
      endpoints: domovinaBrand.endpoints,
      flags: flags,
    );

/// Svi DOMOVINA flagovi osim onih koji se eksplicitno gase.
FeatureFlags domovinaFlagsExcept({
  bool voting = true,
  bool pinka = true,
  bool channelOwnership = true,
  bool calBooking = true,
}) =>
    FeatureFlags(
      voting: voting,
      pinka: pinka,
      channelOwnership: channelOwnership,
      domainScore: true,
      calBooking: calBooking,
    );

/// Putanje svih top-level ruta produkcijskog rutera (nema `ShellRoute`).
Set<String> routePaths() => createRouter()
    .configuration
    .routes
    .whereType<GoRoute>()
    .map((r) => r.path)
    .toSet();

/// Pada li deep-link u error handler (isto ponašanje kao nepoznat URL).
bool isUnroutable(String location) =>
    createRouter().configuration.findMatch(Uri.parse(location)).isError;

const votingRoutes = {'/glasanje', '/glasanje/:slug'};
const pinkaRoutes = {
  '/c/:slug/support',
  '/c/:slug/doniraj',
  '/v/:videoId/support',
  '/v/:videoId/doniraj',
};
const campaignRoutes = {
  '/account/channels/:ucId/campaigns',
  '/account/channels/:ucId/campaigns/:campaignId',
};
const ownershipRoutes = {
  '/c/:slug/claim',
  '/youtube-claim/callback',
  '/account/channels',
  '/account/channels/:ucId',
};

/// Brand-neutralne rute koje nijedan flag ne smije dirati.
const coreRoutes = {'/', '/channels', '/c/:slug', '/p/:slug', '/v/:videoId', '/account'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => AppBrand.init(domovinaBrand));

  test('domovinaBrand: sve rute domenskih značajki postoje (invarijanta)', () {
    AppBrand.init(domovinaBrand);
    final paths = routePaths();
    expect(paths, containsAll(coreRoutes));
    // Glasanje je PRIVREMENO skriveno (26.10.2026., `voting: false` u
    // domovina_brand.dart). Kad se vrati, ovdje opet containsAll + isFalse.
    expect(paths.intersection(votingRoutes), isEmpty);
    expect(paths, containsAll(pinkaRoutes));
    expect(paths, containsAll(campaignRoutes));
    expect(paths, containsAll(ownershipRoutes));
    expect(isUnroutable('/glasanje'), isTrue);
    expect(isUnroutable('/c/laudato/doniraj'), isFalse);
    expect(isUnroutable('/account/channels'), isFalse);
  });

  group('voting: false', () {
    setUp(() => AppBrand.init(brandWith(domovinaFlagsExcept(voting: false))));

    test('ruter nema nijednu /glasanje rutu, ostale su netaknute', () {
      final paths = routePaths();
      expect(paths.where((p) => p.startsWith('/glasanje')), isEmpty);
      expect(paths, containsAll(coreRoutes));
      expect(paths, containsAll(pinkaRoutes));
      expect(paths, containsAll(ownershipRoutes));
    });

    test('deep-link na /glasanje pada u error handler', () {
      expect(isUnroutable('/glasanje'), isTrue);
      expect(isUnroutable('/glasanje/laudato'), isTrue);
    });

    test('upTarget s detalja kandidata ne vodi na nepostojeći /glasanje', () {
      expect(upTarget('/glasanje/laudato'), '/');
      expect(upTarget('/glasanje'), '/');
    });
  });

  group('pinka: false', () {
    setUp(() => AppBrand.init(brandWith(domovinaFlagsExcept(pinka: false))));

    test('nema ruta podrške ni kampanja; vlasništvo kanala ostaje', () {
      final paths = routePaths();
      expect(paths.intersection(pinkaRoutes), isEmpty);
      expect(paths.intersection(campaignRoutes), isEmpty);
      expect(paths, containsAll(ownershipRoutes));
      expect(paths, containsAll(coreRoutes));
    });

    test('deep-link na /c/:slug/doniraj i /v/:id/support pada u error handler', () {
      expect(isUnroutable('/c/laudato/doniraj'), isTrue);
      expect(isUnroutable('/c/laudato/support'), isTrue);
      expect(isUnroutable('/v/abc123/support'), isTrue);
      expect(isUnroutable('/account/channels/UCx/campaigns'), isTrue);
    });
  });

  group('channelOwnership: false', () {
    setUp(() =>
        AppBrand.init(brandWith(domovinaFlagsExcept(channelOwnership: false))));

    test('nema claim ni /account/channels ruta; kampanje (ovise o njima) nema',
        () {
      final paths = routePaths();
      expect(paths.intersection(ownershipRoutes), isEmpty);
      expect(paths.intersection(campaignRoutes), isEmpty);
      expect(paths, containsAll(pinkaRoutes));
      expect(paths, containsAll(coreRoutes));
    });

    test('deep-link na claim flow pada u error handler', () {
      expect(isUnroutable('/c/laudato/claim'), isTrue);
      expect(isUnroutable('/youtube-claim/callback'), isTrue);
      expect(isUnroutable('/account/channels'), isTrue);
    });

    test('upTarget ispod /account ne vodi na nepostojeći /account/channels',
        () {
      expect(upTarget('/account/channels'), '/account');
      expect(upTarget('/account/channels/UCx/campaigns/1'), '/account');
      expect(upTarget('/account'), '/');
    });
  });

  test('sve četiri ugašene: ruter je brand-neutralan, jezgra netaknuta', () {
    AppBrand.init(brandWith(domovinaFlagsExcept(
      voting: false,
      pinka: false,
      channelOwnership: false,
      calBooking: false,
    )));
    final paths = routePaths();
    expect(paths.intersection(votingRoutes), isEmpty);
    expect(paths.intersection(pinkaRoutes), isEmpty);
    expect(paths.intersection(campaignRoutes), isEmpty);
    expect(paths.intersection(ownershipRoutes), isEmpty);
    expect(paths, containsAll(coreRoutes));
    expect(paths, contains('/handoff'));
  });
}
