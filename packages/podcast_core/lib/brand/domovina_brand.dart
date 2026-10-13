import 'package:flutter/painting.dart' show Color;

import 'brand_config.dart';

/// DOMOVINA.ai — prvi (referentni) brend jezgre. Vrijednosti su one koje su
/// do 18. 9. 2026. bile raspršene po `lib/` (vidi docs/02 u podcasterium-app).
const BrandConfig domovinaBrand = BrandConfig(
  appName: 'DOMOVINA.ai',
  wordmark: 'DOMOVINA',
  wordmarkAccent: '.ai',
  plusDisplayName: 'DOMOVINA Plus',
  logPrefix: 'DOMOVINA',
  urlScheme: 'ai.domovina',
  androidPackage: 'ai.domovina',
  iosBundleId: 'ai.domovina',
  iosAppStoreId: '6781716801',
  entitlement: 'domovina_plus',
  seed: Color(0xFF002F6C),
  accent: Color(0xFFFF0000),
  logoAsset: 'assets/icons/domovina_ai_logo_1024.png',
  splashAsset: 'assets/splash/splash_full_1.png',
  defaultLocale: 'hr',
  defaultEpisodeLanguage: 'hr',
  endpoints: Endpoints(
    site: 'https://domovina.ai',
    cdn: 'https://cdn.domovina.ai',
    rag: 'https://mcp.domovina.ai',
    meili: 'https://search.domovina.ai',
    cutter: 'https://cutter.domovina.ai',
    certilia: 'https://certilia.domovina.ai',
    wallet: 'https://wallet.domovina.ai',
    paymentIntents: 'https://mpt.domovina.ai',
    events: 'https://domovina.ai/api/state',
  ),
  flags: FeatureFlags(
    voting: true,
    pinka: true,
    channelOwnership: true,
    domainScore: true,
    calBooking: true,
    passkeys: true,
    homeSnapshot: true,
    youtubeWatch: true,
  ),
);
