import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsBinding;
import 'package:flutter/services.dart' show BrowserContextMenu;
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/app_localizations.dart';
import '../router/app_router.dart';
import '../services/analytics/analytics.dart';
import '../services/auth_service.dart';
import '../services/background_audio.dart';
import '../services/background_playback.dart';
import '../services/boot_stage.dart';
import '../services/entitlement_service.dart';
import '../services/locale_service.dart';
import '../services/playback_speed.dart';
import '../services/push_topics.dart';
import '../services/revenue_cat_service.dart';
import '../services/theme_mode_service.dart';
import '../services/tv_mode.dart';
import '../services/update_notifier.dart';
import '../services/watch_progress_service.dart';
import '../services/episode_language.dart';
import '../theme/app_theme.dart';
import '../auth/auth_provider_plugin.dart';
import '../push/push_transport.dart';
import '../brand/app_brand.dart';
import '../brand/brand_config.dart';
import '../theme/typography.dart';
import 'log.dart';

/// Supabase backend (self-hosted na Coolify, Kong gateway).
/// Konfiguracija dolazi preko --dart-define u build/run komandi; vidi
/// .env za lokalni dev i scripts/deploy.sh za production propagation.
const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Pokreće aplikaciju za zadani [brand]: inicijalizacija servisa u obveznom
/// redoslijedu pa `runApp`. Ljuska (`lib/main.dart`) ne radi ništa osim
/// poziva ove funkcije; tako DOMOVINA i Podcasterium dijele isti core.
///
/// [authPlugins] su vanjski načini prijave koje ljuska donosi (DOMOVINA:
/// Certilia); jezgra ih samo registrira i nudi u auth sheetu.
Future<void> runPodcastApp(
  BrandConfig brand, {
  List<AuthProviderPlugin> authPlugins = const [],
  PushTransport? pushTransport,
}) async {
  // Prije prvog log() poziva — prefiks loga dolazi iz branda.
  AppBrand.init(brand);
  for (final plugin in authPlugins) {
    AuthPlugins.register(plugin);
  }
  log('main() start');
  WidgetsFlutterBinding.ensureInitialized();

  // Fontovi krecu ODMAH, u pozadini — dok teku ostali await-ovi (Supabase,
  // auth, prefs) stignu se skinuti i registrirati, pa cekanje pred runApp
  // obicno traje ~0 ms. Bez ovoga se prvi frame crta fallback fontom pa se
  // cijela stranica prelomi kad pravi font stigne.
  AppTypography.startPreload();

  try { usePathUrlStrategy(); } catch (_) {}

  // Adresna traka mora pratiti i `push()`ane rute, ne samo `go()`ane.
  //
  // `RouteMatchList.uri` po ugovoru odražava SAMO ne-imperativne matcheve
  // (`go_router/lib/src/match.dart:509-511`), a `RouteMatchList.push` radi
  // `copyWith(matches: …)` bez prosljeđivanja `uri` — pa bi bez ove zastavice
  // `push('/v/abc')` s naslovnice ostavio URL na `/`. Za nas je to rušenje, ne
  // kozmetika: „Kopiraj poveznicu" bi kopirao krivi URL, worker ne bi injectao
  // OG tagove epizode, a `url_sync` bi pisao `/t/<sec>` preko krive baze.
  //
  // go_router odgovara od ove zastavice uz obrazloženje da „URL najgornje rute
  // nije uvijek deeplink-abilan" (`router.dart:279-281`). Kod nas to ne vrijedi:
  // nemamo nijedan `ShellRoute`, sve su rute top-level `GoRoute`, i svaka MORA
  // biti dosežna izravnim URL-om jer to već traže AASA popis (`web/_worker.js`),
  // Android intent filteri i OG inject. Provjereno mjerenjem 6.9.2026.
  GoRouter.optionURLReflectsImperativeAPIs = true;

  // Gasi browserov native right-click menu na webu da bi se vidjeli NAŠI custom
  // context menu-i (npr. "Kopiraj poveznicu" na karticama kanala/epizoda —
  // ShareContextMenu). Bez ovoga Flutter web pušta browserov menu koji zasjeni
  // showMenu(). App-wide je (nema per-element API-ja u frameworku).
  if (kIsWeb) {
    try { await BrowserContextMenu.disableContextMenu(); } catch (_) {}
  }

  // Semantics (a11y DOM / ARIA čvorovi) — retestirano na Flutter 3.41.6:
  // ensureSemantics() NE crasha release web (ni skwasm ni dart2js); stara
  // zabrana je bila pogrešna atribucija istovremenih SharedPreferences/
  // flutter_svg crasheva (vidi CLAUDE.md "Known Issues"). Ipak ga ne palimo
  // svima uvijek zbog poznatih BIHEVIORALNIH semantics bugova na webu
  // (flutter/flutter#163576 — click-through kroz preklapajuće widgete):
  //  - e2e alati (Playwright/Cypress) otvaraju app s ?a11y=1 → semantics
  //    odmah, deterministički;
  //  - screen readeri i dalje aktiviraju Flutterov ugrađeni
  //    flt-semantics-placeholder (pali identično stablo, potvrđeno).
  // Handle se namjerno ne dispose-a — app-lifetime.
  if (kIsWeb && Uri.base.queryParameters['a11y'] == '1') {
    SemanticsBinding.instance.ensureSemantics();
    log('semantics: enabled via ?a11y=1');
  }

  // TV detekcija mora biti prije runApp jer router i theme citaju TvMode.isTv
  // sinkrono. Override: --dart-define=FORCE_TV=true za desktop iteraciju.
  await TvMode.init();

  MediaKit.ensureInitialized();
  await BackgroundAudio.init();

  // Supabase init MORA biti prije AuthService.init() — auth service sluša
  // Supabase auth state changes. Bez konfiguracije app radi u offline mode
  // (mock fallback ostaje, ali pravi backend pozivi su no-op).
  if (_supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(
      url: _supabaseUrl,
      anonKey: _supabaseAnonKey,
      debug: false,
    );
    // Bez sesije = gost: sve javno se čita anon ključem, a gostujuća
    // donacija ide bez prijave. Anonimne prijave su ugašene (8.10.2026.,
    // domovina-api ugovor v2 §9) — klijent NIKAD ne zove signInAnonymously.
    // Postojeće anonimne sesije se i dalje vraćaju dok ne isteknu.
    final user = Supabase.instance.client.auth.currentUser;
    log(user == null
        ? 'Supabase: no session — guest'
        : 'Supabase: restored session for ${user.id} '
            '(anon=${user.isAnonymous})');
  } else {
    log('Supabase: SUPABASE_URL / SUPABASE_ANON_KEY not set; running offline');
  }

  // RevenueCat mora biti konfiguriran PRIJE AuthService.init() jer init odmah
  // resolva trenutnog usera pa Purchases.logIn(uid) treba configured SDK.
  // No-op na webu/TV-u (SDK bypassan) — vidi revenue_cat_service.dart.
  await RevenueCatService.instance.configure();

  await AuthService.instance.init();
  // Entitlement state (domovina_plus) — čita Supabase red na svim platformama
  // + folda mobilni optimistic SDK unlock. Mora poslije AuthService.init().
  await EntitlementService.instance.init();
  await WatchProgressService.instance.init();
  // Ucitaj spremljenu temu (default tamna za nove korisnike).
  await ThemeController.instance.init();
  // Ucitaj spremljeni UI jezik (default hrvatski).
  await LocaleController.instance.init();
  // Ucitaj pref "Reprodukcija u pozadini" (default ukljuceno).
  await BackgroundPlayback.instance.init();
  // Ucitaj spremljenu brzinu reprodukcije (default 1.0x, pamti se globalno).
  await PlaybackSpeed.instance.init();

  // Preferirani jezik sadržaja mora biti poznat SINKRONO prije prvog frame-a:
  // share link na kartici epizode odlučuje jezik u trenutku klika, a na nativeu
  // je čitanje (SharedPreferences) asinkrono. Na webu je localStorage sinkron
  // pa ovo ondje samo ubrza prvi pristup.
  await PreferredEpisodeLanguage.instance.init();

  // Analitika (domovina-analytics). Korisnik i jezik se postave PRIJE
  // init-a, da `session_start` već nosi identitet umjesto da se odmah šalje
  // gostujući batch pa `identify`.
  final analytics = Analytics.instance;
  void syncAnalyticsUser() =>
      analytics.setUser(AuthService.instance.currentUser?.id);
  void syncAnalyticsLocale() =>
      analytics.setLocale(LocaleController.instance.locale.languageCode);
  syncAnalyticsUser();
  syncAnalyticsLocale();
  await analytics.init(
    endpoint: brand.endpoints.events,
    app: Uri.parse(brand.endpoints.site).host,
    platform: _analyticsPlatform(),
    appVersion: appVersion,
  );
  AuthService.instance.addListener(syncAnalyticsUser);
  LocaleController.instance.addListener(syncAnalyticsLocale);

  // Push obavijesti o novim epizodama — samo kad ljuska preda transport, i
  // nikad na webu/TV-u. Init NE pita za dozvolu; dijalog otvara tek korisnikov
  // tap (ekran Obavijesti ili zvonce kanala).
  if (!kIsWeb && !TvMode.isTv && pushTransport != null) {
    await PushTopics.instance.init(pushTransport);
  }

  // Uhvati Flutter greske i ispisi u console (vidljivo i u minified buildu)
  FlutterError.onError = (details) {
    log('FLUTTER ERROR: ${details.exception}');
    log('STACK: ${details.stack}');
    FlutterError.presentError(details);
  };

  // Zadnja stanica prije prvog framea — vidi AppTypography.startPreload().
  reportBootStage('fonts');
  await AppTypography.awaitPreload();

  log('runApp');
  runApp(const PodcastApp());
}

String _analyticsPlatform() {
  if (kIsWeb) return 'web';
  if (TvMode.isTv) return 'tv';
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS => 'ios',
    TargetPlatform.android => 'android',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.windows => 'windows',
    _ => 'linux',
  };
}

class PodcastApp extends StatefulWidget {
  const PodcastApp({super.key});

  @override
  State<PodcastApp> createState() => _PodcastAppState();
}

/// Globalni ScaffoldMessenger key — omogućuje prikaz SnackBar-a iz servisa
/// (npr. AuthService) neovisno o BuildContext-u koji je možda već unmountan
/// (npr. nakon zatvaranja bottom sheeta). Vezan na MaterialApp ispod.
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class _PodcastAppState extends State<PodcastApp> {
  final _messengerKey = rootScaffoldMessengerKey;
  late final _router = createRouter();

  @override
  void initState() {
    super.initState();
    listenForAppUpdate(_showUpdateSnackBar);
    // `screen_view` za svaku promjenu lokacije. Sluša se provider, ne
    // `routerDelegate`: delegate na `push` ne javlja listenerima (izmjereno —
    // otvorena epizoda ostala je zapisana kao `/`), a provider javlja svaki
    // go/push/pop i browserov Back.
    _router.routeInformationProvider.addListener(_reportScreen);
    _reportScreen();
    _listenForPushOpens();
  }

  StreamSubscription<String>? _pushOpenSub;

  /// Tap na obavijest otvara rutu iz `data.route` (npr. `/v/<id>`) — i dok
  /// aplikacija živi, i kad ju je obavijest pokrenula (hladni start).
  void _listenForPushOpens() {
    final transport = PushTopics.instance.transport;
    if (transport == null) return;
    _pushOpenSub = transport.openedRoutes.listen(_openPushRoute);
    unawaited(transport.initialRoute().then((route) {
      if (route == null) return;
      // Ruter mora imati prvi frame prije push-a, inače se ruta izgubi pod
      // inicijalnom lokacijom.
      WidgetsBinding.instance.addPostFrameCallback((_) => _openPushRoute(route));
    }));
  }

  void _openPushRoute(String route) {
    // Samo naše interne putanje — obavijest nikad ne vodi na tuđi host.
    if (!route.startsWith('/') || route.startsWith('//')) return;
    log('push: open $route');
    Analytics.instance.track('push_open', props: {'route': route});
    unawaited(_router.push(route));
  }

  @override
  void dispose() {
    unawaited(_pushOpenSub?.cancel());
    super.dispose();
  }

  void _reportScreen() =>
      Analytics.instance.screen(_router.routeInformationProvider.value.uri);

  void _showUpdateSnackBar() {
    final ctx = _messengerKey.currentContext;
    final l = ctx != null ? AppLocalizations.of(ctx) : null;
    _messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(l?.updateAvailable ?? 'Dostupna je nova verzija'),
        duration: const Duration(days: 1),
        action: SnackBarAction(
          label: l?.updateRefresh ?? 'Osvježi',
          onPressed: reloadPage,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Na Android TV-u forsiramo dark TV temu (10-foot UI uvijek tamno).
    // Mobile/desktop/web prate korisnikov odabir iz ThemeController-a
    // (default tamna za nove korisnike, prebacivo preko ikone u home baru).
    final isTv = TvMode.isTv;
    if (isTv) {
      return MaterialApp.router(
        scaffoldMessengerKey: _messengerKey,
        title: AppBrand.config.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.tv(),
        darkTheme: AppTheme.tv(),
        themeMode: ThemeMode.dark,
        // TV je hrvatsko tržište (10-foot UI) — fiksno hrvatski.
        locale: const Locale('hr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: _router,
      );
    }
    return AnimatedBuilder(
      // Rebuild na promjenu teme ILI UI jezika.
      animation: Listenable.merge(
        [ThemeController.instance, LocaleController.instance],
      ),
      builder: (context, _) => MaterialApp.router(
        scaffoldMessengerKey: _messengerKey,
        title: AppBrand.config.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeController.instance.mode,
        locale: LocaleController.instance.locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: _router,
      ),
    );
  }
}
