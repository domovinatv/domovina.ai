import 'package:podcast_core/brand/brand_config.dart';
import 'package:podcast_core/brand/domovina_brand.dart';

/// Brendovi za testove jezgre.
///
/// [brandWithoutDomainScore] je DOMOVINA s ugašenom domenskom ocjenom
/// (`flags.domainScore == false`) — sve ostalo isto, pa test mjeri samo
/// učinak te zastavice. Testovi ga postavljaju kroz `AppBrand.init(...)` i
/// u `tearDown` vraćaju [domovinaBrand].
BrandConfig brandWithoutDomainScore() =>
    _domovinaWith(domainScore: false);

/// DOMOVINA bez passkeyja (`flags.passkeys == false`) — kao brend koji još
/// nema Corbado projekt.
BrandConfig brandWithoutPasskeys() => _domovinaWith(passkeys: false);

/// DOMOVINA s uključenim glasanjem. Glasanje je u [domovinaBrand]
/// privremeno ugašeno (26.10.2026.), a testovi njegove logike i dalje
/// trebaju brend u kojem `/glasanje*` postoji.
BrandConfig brandWithVoting() => _domovinaWith(voting: true);

BrandConfig _domovinaWith({bool? domainScore, bool? passkeys, bool? voting}) {
  final d = domovinaBrand;
  final f = d.flags;
  return BrandConfig(
    appName: d.appName,
    wordmark: d.wordmark,
    wordmarkAccent: d.wordmarkAccent,
    plusDisplayName: d.plusDisplayName,
    logPrefix: d.logPrefix,
    urlScheme: d.urlScheme,
    androidPackage: d.androidPackage,
    iosBundleId: d.iosBundleId,
    iosAppStoreId: d.iosAppStoreId,
    entitlement: d.entitlement,
    seed: d.seed,
    accent: d.accent,
    logoAsset: d.logoAsset,
    splashAsset: d.splashAsset,
    defaultLocale: d.defaultLocale,
    defaultEpisodeLanguage: d.defaultEpisodeLanguage,
    endpoints: d.endpoints,
    flags: FeatureFlags(
      voting: voting ?? f.voting,
      pinka: f.pinka,
      channelOwnership: f.channelOwnership,
      domainScore: domainScore ?? f.domainScore,
      calBooking: f.calBooking,
      handoff: f.handoff,
      tv: f.tv,
      passkeys: passkeys ?? f.passkeys,
    ),
  );
}
