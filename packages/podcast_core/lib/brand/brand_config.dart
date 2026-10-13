import 'package:flutter/painting.dart' show Color;

/// Sve što jedan brend (DOMOVINA.ai, Podcasterium…) razlikuje od drugoga,
/// a živi u Dart kodu. Jedina dopuštena mjesta s imenom brenda, hostovima,
/// identifikatorima trgovina i bojama u `lib/` su ova datoteka i
/// `domovina_brand.dart`; ostatak jezgre čita `AppBrand.config`.
///
/// Sve što NIJE Dart (ikone, splash, manifest.json, colors.xml, index.html)
/// dolazi iz brand manifesta ljuske, ne odavde.
class BrandConfig {
  const BrandConfig({
    required this.appName,
    required this.wordmark,
    this.wordmarkAccent = '',
    required this.plusDisplayName,
    required this.logPrefix,
    required this.urlScheme,
    required this.androidPackage,
    required this.iosBundleId,
    required this.iosAppStoreId,
    required this.entitlement,
    required this.seed,
    required this.accent,
    required this.logoAsset,
    required this.splashAsset,
    this.defaultLocale = 'en',
    this.defaultEpisodeLanguage = 'en',
    required this.endpoints,
    this.flags = const FeatureFlags(),
    this.sourceCodeUrl = 'https://github.com/domovinatv',
    this.contactEmail = 'ms@domovina.ai',
    this.plusLifetime = true,
    this.featuredChannels = const [],
  });

  /// ID-evi kanala koje brend ističe (npr. `subclub`): prvi slideovi hero
  /// karusela, zaseban rail na naslovnici, vrh popisa kanala i chipova
  /// pretrage. Prazna lista = bez isticanja, ponašanje kao prije.
  final List<String> featuredChannels;

  /// Nudi li Plus i doživotni (lifetime) paket. Utječe na orijentacijske
  /// pločice paywalla kad RevenueCat offering nije dostupan.
  final bool plusLifetime;

  /// Poveznica „GitHub” u podnožju naslovnice.
  final String sourceCodeUrl;

  /// Contact address on the privacy and terms pages.
  final String contactEmail;

  /// Puno ime proizvoda, npr. `DOMOVINA.ai` — naslovi, page meta, obavijesti.
  final String appName;

  /// Wordmark u app baru i auth sheetu; [wordmarkAccent] je sufiks u
  /// naglašenoj boji (`.ai`), prazan string = bez naglaska.
  final String wordmark;
  final String wordmarkAccent;

  /// Ime pretplate, npr. `DOMOVINA Plus`.
  final String plusDisplayName;

  /// Prefiks u `log()` — `[DOMOVINA v2.0.153] …`.
  final String logPrefix;

  /// Custom URL shema za auth callback i deep linkove (`ai.domovina`).
  final String urlScheme;

  /// Android applicationId; koristi se i za kanal audio obavijesti.
  final String androidPackage;
  final String iosBundleId;

  /// Numerički App Store ID (bez `id` prefiksa).
  final String iosAppStoreId;

  /// RevenueCat entitlement koji otključava Plus.
  final String entitlement;

  /// Seed boja Material 3 sheme i naglasna (tertiary) boja.
  final Color seed;
  final Color accent;

  /// Putanje asseta u bundleu LJUSKE (korijenski pubspec), ne paketa.
  final String logoAsset;
  final String splashAsset;

  /// Zadani jezik sučelja i zadani jezik sadržaja za nove korisnike.
  final String defaultLocale;
  final String defaultEpisodeLanguage;

  final Endpoints endpoints;
  final FeatureFlags flags;

  /// App Store poveznica na native aplikaciju.
  String get iosAppStoreUrl =>
      'https://apps.apple.com/app/id$iosAppStoreId';

  /// Google Play poveznica na native aplikaciju.
  String get androidPlayStoreUrl =>
      'https://play.google.com/store/apps/details?id=$androidPackage';

  /// Apsolutni URL javne stranice (share, OG, pravni dokumenti).
  /// [path] počinje kosom crtom, npr. `/v/abc123`.
  String shareUrl(String path) => '${endpoints.site}$path';
}

/// Hostovi backend servisa jednog brenda. Bez završne kose crte.
class Endpoints {
  const Endpoints({
    required this.site,
    required this.cdn,
    required this.rag,
    required this.meili,
    required this.cutter,
    this.certilia = '',
    this.wallet = '',
    this.paymentIntents = '',
    this.events = '',
  });

  /// Javna web stranica — baza za share linkove i OG.
  final String site;

  /// Statični CDN s JSON-om, slikama i medijima (`CdnConfig`).
  final String cdn;

  /// Person hub / semantičko pretraživanje (MCP).
  final String rag;

  /// Meilisearch (keyword pretraga).
  final String meili;

  /// Servis za rezanje klipova.
  final String cutter;

  /// Certilia (e-Osobna) OAuth posrednik; prazno kad je flag ugašen.
  final String certilia;

  /// Pinka wallet SDK host i intent-status API; prazno kad je pinka ugašena.
  final String wallet;
  final String paymentIntents;

  /// Ingest vlastite analitike (`domovina-analytics`), puni URL. Prazno =
  /// brend nema analitiku. Mora biti na ISTOM originu kao [site]: zahtjev na
  /// tuđu domenu (ili s riječima poput `analytics`/`track` u putanji)
  /// adblockeri blokiraju.
  final String events;
}

/// Značajke koje brend uključuje. Zadano je sve UGAŠENO osim onoga što je
/// brand-neutralno; DOMOVINA pali svoje domenske značajke eksplicitno.
///
/// Prijava e-Osobnom (Certilia) NIJE zastavica: ljuska registrira
/// `AuthProviderPlugin` kroz `runPodcastApp(authPlugins:)`, a bez plugina
/// jezgra nema ni SDK ni gumb.
class FeatureFlags {
  const FeatureFlags({
    this.voting = false,
    this.pinka = false,
    this.channelOwnership = false,
    this.domainScore = false,
    this.calBooking = false,
    this.handoff = true,
    this.tv = true,
    this.passkeys = false,
    this.plusInHeader = false,
    this.homeSnapshot = false,
    this.youtubeWatch = false,
  });

  /// Glasanje za podcaste (`/glasanje*`, rail na naslovnici).
  final bool voting;

  /// Pinka podrška (SEPA doniranje, zid podrške, kampanje).
  final bool pinka;

  /// Vlasništvo kanala (claim, KYC, isplate) — ovisi o pinki.
  final bool channelOwnership;

  /// Domenska ocjena epizoda (Magisterium) — ranker, sort, značke.
  final bool domainScore;

  /// „15 min s osnivačem” (Cal.com).
  final bool calBooking;

  /// Handoff web ↔ native.
  final bool handoff;

  /// Android TV / Leanback sučelje.
  final bool tv;

  /// Prijava i upravljanje passkeyjima (Corbado). Traži Corbado projekt s
  /// domenom brenda kao relying party; bez njega „Dodaj passkey” pada, pa
  /// brend bez projekta ne prikazuje ni tile u auth sheetu ni sekciju u
  /// Mom računu.
  final bool passkeys;

  /// A Plus button in the home header for everyone who is not Plus yet,
  /// signed in or not. Without it the paywall is only reachable from the
  /// account screen, which App Review could not find (Guideline 2.1(b)).
  final bool plusInHeader;

  /// Naslovnica iz `channels/data/home.json` (`HomeSnapshot`) prije
  /// listinga. Datoteku slaže noćni pipeline za DOMOVINA-in izbor kanala i
  /// ocjena, a korpus je dijeljen — brend s vlastitim istaknutim kanalima je
  /// ne smije prikazati, nego gradi naslovnicu iz listinga kao prije.
  final bool homeSnapshot;

  /// Samostalni `/yt/:videoId` player za bilo koji YouTube video (službeni
  /// nocookie embed). Eksperimentalno; brend ga pali tek kad to odluči
  /// (App Review 5.2.3 — mediji treće strane).
  final bool youtubeWatch;
}
