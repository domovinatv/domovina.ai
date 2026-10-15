import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import '../brand/app_brand.dart';
import '../onboarding/moments/m4_handoff_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/channels/all_channels_screen.dart';
import '../screens/channel/channel_screen.dart';
import '../screens/person/person_screen.dart';
import '../screens/episode_screen.dart';
import '../screens/favorites/favorites_screen.dart';
import '../screens/episode_simple_screen.dart';
import '../screens/legal/privacy_screen.dart';
import '../screens/legal/terms_screen.dart';
import '../screens/search/meili_search_screen.dart';
import '../screens/subscribe/paywall_screen.dart';
import '../screens/subscribe/upgrade_trigger.dart';
import '../screens/account/account_screen.dart';
import '../screens/auth/auth_callback_screen.dart';
import '../screens/auth/invite_screen.dart';
import '../screens/ownership/channel_ownership_screen.dart';
import '../screens/ownership/campaigns/channel_campaigns_screen.dart';
import '../screens/ownership/campaigns/campaign_manage_screen.dart';
import '../pinka_sdk/pinka_sdk.dart';
import '../screens/tv/tv_channel_screen.dart';
import '../screens/tv/tv_episode_reader_screen.dart';
import '../screens/tv/tv_episode_screen.dart';
import '../screens/tv/tv_home_screen.dart';
import '../screens/tv/tv_person_screen.dart';
import '../screens/voting/voting_screen.dart';
import '../screens/youtube_watch/youtube_watch_screen.dart';
import '../screens/sponsor/sponsor_episode_screen.dart';
import '../screens/sponsor/sponsor_store_screen.dart';
import '../services/tv_mode.dart';

/// App router — go_router s NoTransitionPage za instant navigaciju.
/// Svaka ruta ima ValueKey da go_router zna rebuildat kad se mijenja path.
GoRouter createRouter() {
  // Značajke koje brend nije uključio NEMAJU rutu: deep-link na ugašenu
  // značajku pada u `errorPageBuilder` (naslovnica), isto kao nepoznat URL.
  final flags = AppBrand.config.flags;
  return GoRouter(
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => NoTransitionPage(
          key: const ValueKey('home'),
          // Android TV (Leanback) dobiva vlastiti 10-foot UI home. Ostale
          // rute u Fazi 1 jos uvijek koriste desktop/mobile ekran — TV
          // varijante stizu u Fazi 2-4. Vidi lib/services/tv_mode.dart.
          child: TvMode.isTv ? const TvHomeScreen() : const HomeScreen(),
        ),
      ),
      // Svi kanali — odvojen ekran s lazy listom + filterom (vidi
      // all_channels_screen.dart; maknuto s home-a radi scroll-perf-a).
      // Na mobitelu se s home-a otvara kao bottom sheet; ova ruta je za
      // desktop / direktni deep-link.
      // `?prikaz=osobe` otvara katalog s odabranim filtrom „Osobe" — odredište
      // gumba „Prikaži sve" na home railu osoba. Query param, a NE zasebna
      // `/osobe` ruta: nova javna content ruta mora u OBA deep-link popisa
      // (AASA components + Android intent filter), a ovo je isti katalog.
      GoRoute(
        path: '/channels',
        pageBuilder: (context, state) {
          final showPersons = state.uri.queryParameters['prikaz'] == 'osobe';
          return NoTransitionPage(
            // Različit key po prikazu: bez toga go_router zadrži isti State pri
            // prelasku /channels ↔ /channels?prikaz=osobe, pa se `initialFilter`
            // (čita se samo u initState) nikad ne primijeni.
            key: ValueKey(showPersons ? 'all-channels-persons' : 'all-channels'),
            child: AllChannelsScreen(showPersons: showPersons),
          );
        },
      ),
      GoRoute(
        path: '/c/:slug',
        pageBuilder: (context, state) {
          final slug = state.pathParameters['slug']!;
          final channelId = slug.replaceAll('-', '_');
          return NoTransitionPage(
            key: ValueKey('channel-$slug'),
            child: TvMode.isTv
                ? TvChannelScreen(channelId: channelId)
                : ChannelScreen(channelId: channelId),
          );
        },
      ),
      // Javni profil govornika ("person hub") — /p/:slug. Agregira SVE epizode
      // u kojima osoba GOVORI, kroz sve kanale. VAŽNO: person slug je primarni
      // ključ u bazi i prosljeđuje se DOSLOVNO (s crticama) — za razliku od
      // channel slug-a (/c/:slug) koji radi `-`→`_`. Vidi PersonScreen +
      // lib/services/person_service.dart.
      GoRoute(
        path: '/p/:slug',
        pageBuilder: (context, state) {
          final slug = state.pathParameters['slug']!;
          return NoTransitionPage(
            key: ValueKey('person-$slug'),
            // Android TV (Leanback) dobiva 10-foot pandan — grid epizoda s
            // D-pad navigacijom; vidi TvPersonScreen.
            child: TvMode.isTv
                ? TvPersonScreen(slug: slug)
                : PersonScreen(slug: slug),
          );
        },
      ),
      // "Zid podrške" — pinka.finance crowdfunding/donacije za kanal.
      // Standalone SDK u lib/pinka_sdk/. Subjekt = podcast_channel; ref se
      // matcha na UC… id ILI interni channel id. Episode varijanta
      // (/v/:id/support) je vizija — vidi PinkaCampaignScreen.episode.
      // Dvije rute za isti ekran: /support (EN share link) i /doniraj (HR).
      if (flags.pinka)
        for (final path in const ['/c/:slug/support', '/c/:slug/doniraj'])
          GoRoute(
          path: path,
          pageBuilder: (context, state) {
            final slug = state.pathParameters['slug']!;
            final channelId = slug.replaceAll('-', '_');
            return NoTransitionPage(
              key: ValueKey('support-$slug'),
              child: PinkaCampaignScreen.channel(
                channelId: channelId,
                youtubeChannelId: state.uri.queryParameters['uc'],
                channelName: state.uri.queryParameters['name'],
              ),
            );
          },
        ),
      // Izlog sponzorskih trenutaka kanala (plan
      // docs/plans/2026-10-06-mvp-sponzorski-trenuci-domovina-tv.md). Ruta je
      // generička, ali ponudu ima samo kanal sa `SponsorCampaign` — ostali
      // dobiju prazno stanje. Worker je zna (OG), vidi `web/_worker.js`.
      // Plaćanje ide SEPA blokom zida podrške, pa ruta postoji samo uz pinku.
      if (flags.pinka)
      GoRoute(
        path: '/c/:slug/oglasi',
        pageBuilder: (context, state) {
          final slug = state.pathParameters['slug']!;
          return NoTransitionPage(
            key: ValueKey('sponsor-store-$slug'),
            child: SponsorStoreScreen(channelId: slug.replaceAll('-', '_')),
          );
        },
      ),
      // Channel ownership claim flow (vidi docs/channel-ownership-and-safe-payout-plan.md)
      if (flags.channelOwnership)
        GoRoute(
          path: '/c/:slug/claim',
          pageBuilder: (context, state) {
            final slug = state.pathParameters['slug']!;
            final channelId = slug.replaceAll('-', '_');
            return NoTransitionPage(
              key: ValueKey('claim-$slug'),
              child: ChannelOwnershipScreen(channelId: channelId),
            );
          },
        ),
      if (flags.channelOwnership)
        GoRoute(
          path: '/youtube-claim/callback',
          pageBuilder: (context, state) => NoTransitionPage(
            key: const ValueKey('youtube-claim-callback'),
            child: YoutubeClaimCallbackScreen(
              code: state.uri.queryParameters['code'],
              state: state.uri.queryParameters['state'],
            ),
          ),
        ),
      if (flags.channelOwnership)
        GoRoute(
          path: '/account/channels',
          pageBuilder: (context, state) => const NoTransitionPage(
            key: ValueKey('my-channels'),
            child: MyChannelsScreen(),
          ),
        ),
      // Pinka kampanje za verificirani kanal (vlasnik administrira) — vidi
      // lib/screens/ownership/campaigns/. Faza A: upravljanje postojećima.
      if (flags.pinka && flags.channelOwnership)
        GoRoute(
          path: '/account/channels/:ucId/campaigns',
          pageBuilder: (context, state) {
            final ucId = state.pathParameters['ucId']!;
            return NoTransitionPage(
              key: ValueKey('channel-campaigns-$ucId'),
              child: ChannelCampaignsScreen(youtubeChannelId: ucId),
            );
          },
        ),
      if (flags.pinka && flags.channelOwnership)
        GoRoute(
          path: '/account/channels/:ucId/campaigns/:campaignId',
          pageBuilder: (context, state) {
            final ucId = state.pathParameters['ucId']!;
            final campaignId = state.pathParameters['campaignId']!;
            return NoTransitionPage(
              key: ValueKey('campaign-manage-$campaignId'),
              child: CampaignManageScreen(
                youtubeChannelId: ucId,
                campaignId: campaignId,
              ),
            );
          },
        ),
      // Per-kanal verifikacija/upravljanje otvoreno po UC… ID-u (iz "Moji kanali").
      if (flags.channelOwnership)
        GoRoute(
          path: '/account/channels/:ucId',
          pageBuilder: (context, state) {
            final ucId = state.pathParameters['ucId']!;
            return NoTransitionPage(
              key: ValueKey('manage-$ucId'),
              child: ChannelOwnershipScreen(youtubeChannelId: ucId),
            );
          },
        ),
      // **Rule (ključ NE smije nositi `startAt` ni `person`)**: do 6.9.2026. je
      // ključ bio `video-$id-$startAt-hr-$person`, pa je svaki prijelaz
      // `/v/<id>` → `/v/<id>/t/<sec>` bio NOVI ključ → novi `State` → uništen
      // player i ponovno učitavanje svih artefakata. Ključ sada nosi samo
      // identitet ekrana (video + jezik); `startAt`/`person` su obični propovi
      // koje `_EpisodeContentState.didUpdateWidget` primijeni na živom ekranu
      // (seek + ponovni person-highlight). Bez toga bi svaki push na epizodu s
      // timestampom (share link iz raila, tap na poglavlje, `?p=` marker)
      // platio puni remount.
      GoRoute(
        path: '/v/:videoId',
        pageBuilder: (context, state) {
          final videoId = state.pathParameters['videoId']!;
          final t = state.uri.queryParameters['t'];
          final startAt = t != null ? int.tryParse(t) : null;
          // `?p=<person-slug>` — person-highlight marker (dolazak s /p/
          // profila govornika); vidi EpisodeScreen.highlightPersonSlug.
          final person = state.uri.queryParameters['p'];
          return NoTransitionPage(
            // `?video=0|1` je zaseban ekran (vidi EpisodeScreen.openVideo);
            // s istim ključem bi se samo reciklirao postojeći.
            key: ValueKey('video-$videoId-hr'
                '${_videoKeySuffix(state)}'),
            // Android TV (Leanback): standalone 10-foot UI. EN toggle nije jos
            // u TV varijanti (Faza 4.5), pa /v/<id>/en za sada renderira isti
            // TvEpisodeScreen (vidi tv ruta /en ispod).
            child: TvMode.isTv
                ? TvEpisodeScreen(
                    youtubeId: videoId,
                    startAtSeconds: startAt,
                  )
                : EpisodeScreen(
                    youtubeId: videoId,
                    startAtSeconds: startAt,
                    highlightPersonSlug: person,
                    openVideo: _openVideo(state),
                  ),
          );
        },
      ),
      // "Zid podrške" za epizodu — pinka.finance donacije/crowdfunding po
      // epizodi. Subjekt = podcast_episode; ref = YouTube video id. SEPA (EPC
      // QR) + on-chain EURe (Gnosis Safe) + in-app DOMOVINA novčanik. Sam se
      // sakrije/prazni ako epizoda nema aktivnu kampanju. Pandan /c/:slug/support.
      if (flags.pinka)
        for (final path in const ['/v/:videoId/support', '/v/:videoId/doniraj'])
          GoRoute(
          path: path,
          pageBuilder: (context, state) {
            final videoId = state.pathParameters['videoId']!;
            return NoTransitionPage(
              key: ValueKey('support-v-$videoId'),
              child: PinkaCampaignScreen.episode(
                youtubeId: videoId,
                episodeTitle: state.uri.queryParameters['name'],
              ),
            );
          },
        ),
      // Karta sponzorskih trenutaka epizode → checkout → SEPA → stanje.
      // `?narudzba=<contribution_id>` otvara izravno stanje narudžbe (kupac se
      // vraća preko poveznice iz checkouta). Ključ nosi samo epizodu — ista
      // stranica s drugim query parametrom ne smije baciti formu/hold.
      if (flags.pinka)
      GoRoute(
        path: '/v/:videoId/sponzoriraj',
        pageBuilder: (context, state) {
          final videoId = state.pathParameters['videoId']!;
          return NoTransitionPage(
            key: ValueKey('sponsor-v-$videoId'),
            child: SponsorEpisodeScreen(
              youtubeId: videoId,
              orderId: state.uri.queryParameters['narudzba'],
            ),
          );
        },
      ),
      // Android TV reader mode — "Čitaj kao blog" prikaz s PiP videom u
      // kutu. Samo TV: na desktopu/mobitelu se redirecta na klasični
      // episode screen (na webu nema D-pad-a, nema smisla).
      GoRoute(
        path: '/v/:videoId/read',
        pageBuilder: (context, state) {
          final videoId = state.pathParameters['videoId']!;
          final t = state.uri.queryParameters['t'];
          final startAt = t != null ? int.tryParse(t) : null;
          return NoTransitionPage(
            key: ValueKey('reader-$videoId'),
            child: TvMode.isTv
                ? TvEpisodeReaderScreen(
                    youtubeId: videoId,
                    startAtSeconds: startAt,
                  )
                : EpisodeScreen(
                    youtubeId: videoId,
                    startAtSeconds: startAt,
                  ),
          );
        },
      ),
      // Per-episode jezik — /v/<id>/en. Sufix umjesto ?lang=en jer social
      // crawleri (Facebook, LinkedIn, WhatsApp) cesto droppaju query parametre
      // pri normalizaciji URL-a, sto bi ulinkano resharanjima izgubilo
      // engleski OG title/description.
      GoRoute(
        path: '/v/:videoId/en',
        pageBuilder: (context, state) {
          final videoId = state.pathParameters['videoId']!;
          final t = state.uri.queryParameters['t'];
          final startAt = t != null ? int.tryParse(t) : null;
          final person = state.uri.queryParameters['p'];
          return NoTransitionPage(
            // `?video=0|1` je zaseban ekran (vidi EpisodeScreen.openVideo);
            // s istim ključem bi se samo reciklirao postojeći.
            key: ValueKey('video-$videoId-en'
                '${_videoKeySuffix(state)}'),
            child: TvMode.isTv
                ? TvEpisodeScreen(
                    youtubeId: videoId,
                    startAtSeconds: startAt,
                  )
                : EpisodeScreen(
                    youtubeId: videoId,
                    startAtSeconds: startAt,
                    initialLanguageEn: true,
                    highlightPersonSlug: person,
                    openVideo: _openVideo(state),
                  ),
          );
        },
      ),
      // Path-based timestamp share — /v/<id>/t/<sec>
      // Path varijanta postoji da svaki clip ima vlastiti crawler cache entry
      // (Facebook/LinkedIn/WhatsApp normaliziraju query param verzije).
      GoRoute(
        path: '/v/:videoId/t/:seconds',
        pageBuilder: (context, state) {
          final videoId = state.pathParameters['videoId']!;
          final startAt = int.tryParse(state.pathParameters['seconds'] ?? '');
          final person = state.uri.queryParameters['p'];
          return NoTransitionPage(
            // `?video=0|1` je zaseban ekran (vidi EpisodeScreen.openVideo);
            // s istim ključem bi se samo reciklirao postojeći.
            key: ValueKey('video-$videoId-hr'
                '${_videoKeySuffix(state)}'),
            child: TvMode.isTv
                ? TvEpisodeScreen(
                    youtubeId: videoId,
                    startAtSeconds: startAt,
                  )
                : EpisodeScreen(
                    youtubeId: videoId,
                    startAtSeconds: startAt,
                    highlightPersonSlug: person,
                    openVideo: _openVideo(state),
                  ),
          );
        },
      ),
      // Engleski + timestamp — /v/<id>/t/<sec>/en
      GoRoute(
        path: '/v/:videoId/t/:seconds/en',
        pageBuilder: (context, state) {
          final videoId = state.pathParameters['videoId']!;
          final startAt = int.tryParse(state.pathParameters['seconds'] ?? '');
          final person = state.uri.queryParameters['p'];
          return NoTransitionPage(
            // `?video=0|1` je zaseban ekran (vidi EpisodeScreen.openVideo);
            // s istim ključem bi se samo reciklirao postojeći.
            key: ValueKey('video-$videoId-en'
                '${_videoKeySuffix(state)}'),
            child: TvMode.isTv
                ? TvEpisodeScreen(
                    youtubeId: videoId,
                    startAtSeconds: startAt,
                  )
                : EpisodeScreen(
                    youtubeId: videoId,
                    startAtSeconds: startAt,
                    initialLanguageEn: true,
                    highlightPersonSlug: person,
                    openVideo: _openVideo(state),
                  ),
          );
        },
      ),
      // Mobile simplified view
      GoRoute(
        path: '/m/:videoId',
        pageBuilder: (context, state) {
          final videoId = state.pathParameters['videoId']!;
          return NoTransitionPage(
            key: ValueKey('mobile-$videoId-hr'),
            child: EpisodeSimpleScreen(youtubeId: videoId),
          );
        },
      ),
      GoRoute(
        path: '/m/:videoId/en',
        pageBuilder: (context, state) {
          final videoId = state.pathParameters['videoId']!;
          return NoTransitionPage(
            key: ValueKey('mobile-$videoId-en'),
            child: EpisodeSimpleScreen(
              youtubeId: videoId,
              initialLanguageEn: true,
            ),
          );
        },
      ),
      // Path-based timestamp share — /m/<id>/t/<sec> (mobile simplified view).
      // Mirror /v/<id>/t/<sec> da share linkovi iz simple playera otvore
      // simple ekran umjesto da padnu na errorPageBuilder (homepage).
      GoRoute(
        path: '/m/:videoId/t/:seconds',
        pageBuilder: (context, state) {
          final videoId = state.pathParameters['videoId']!;
          final startAt = int.tryParse(state.pathParameters['seconds'] ?? '');
          return NoTransitionPage(
            key: ValueKey('mobile-$videoId-hr'),
            child: EpisodeSimpleScreen(
              youtubeId: videoId,
              startAtSeconds: startAt,
            ),
          );
        },
      ),
      GoRoute(
        path: '/m/:videoId/t/:seconds/en',
        pageBuilder: (context, state) {
          final videoId = state.pathParameters['videoId']!;
          final startAt = int.tryParse(state.pathParameters['seconds'] ?? '');
          return NoTransitionPage(
            key: ValueKey('mobile-$videoId-en'),
            child: EpisodeSimpleScreen(
              youtubeId: videoId,
              startAtSeconds: startAt,
              initialLanguageEn: true,
            ),
          );
        },
      ),
      // Samostalni YouTube player za BILO KOJI video (službeni nocookie
      // embed, bez blokiranja reklama). Gumb na obrađenu epizodu ako postoji.
      // Nije u AASA/Android App Links popisima — eksperimentalna ruta.
      if (flags.youtubeWatch)
      GoRoute(
        path: '/yt/:videoId',
        pageBuilder: (context, state) {
          final videoId = state.pathParameters['videoId']!;
          return NoTransitionPage(
            key: ValueKey('yt-$videoId'),
            child: YouTubeWatchScreen(videoId: videoId),
          );
        },
      ),
      // Keyword pretraga (Meilisearch PoC) — aktivno za lokalni test.
      // Kod živi u lib/screens/search/meili_search_screen.dart.
      GoRoute(
        path: '/search',
        // `?q=<upit>` otvara pretragu s već upisanim upitom (dijeljivi link,
        // store screenshotovi).
        pageBuilder: (context, state) => NoTransitionPage(
          key: const ValueKey('meili-search'),
          child: MeiliSearchScreen(
            initialQuery: state.uri.queryParameters['q'],
          ),
        ),
      ),
      // DOMOVINA Plus paywall — kontekstualni ?from=<trigger> (offline, export,
      // sync, search, enFirst, magisterium, badge). Mobile kupuje preko SDK-a,
      // web preusmjerava na RevenueCat Web Billing hosted checkout.
      GoRoute(
        path: '/subscribe',
        pageBuilder: (context, state) {
          final from = state.uri.queryParameters['from'];
          return NoTransitionPage(
            key: ValueKey('subscribe-${from ?? 'generic'}'),
            child: PaywallScreen(
              trigger: UpgradeTriggerCopy.fromSlug(from),
            ),
          );
        },
      ),
      // Spremljene (lajkane) epizode — puni popis, najnovija prvo. Isječak je
      // rail na naslovnici (vidi screens/home/favorites_rail.dart).
      GoRoute(
        path: '/favorites',
        pageBuilder: (context, state) => const NoTransitionPage(
          key: ValueKey('favorites'),
          child: FavoritesScreen(),
        ),
      ),
      // „Izborni dan" — glasanje o sljedećem kanalu koji ulazi u pipeline.
      // Ruta je JAVNA i dijeljiva: ljestvicu vidi svatko, glasa samo građanin
      // potvrđen e-Osobnom. `/glasanje/:slug` je deep-link na detalj kandidata
      // (isti ekran + sheet), pa share link ne otvara prazan ekran.
      // Plan: docs/plans/2026-08-08-glasanje-o-kanalima.md §8.1.
      if (flags.voting)
        GoRoute(
          path: '/glasanje',
          pageBuilder: (context, state) => const NoTransitionPage(
            key: ValueKey('voting'),
            child: VotingScreen(),
          ),
        ),
      if (flags.voting)
        GoRoute(
          path: '/glasanje/:slug',
          pageBuilder: (context, state) {
            // Registry slug ide DOSLOVNO (primarni ključ u bazi) — nikad
            // `-`↔`_` transformacija kao kod /c/:slug.
            final slug = state.pathParameters['slug']!;
            return NoTransitionPage(
              key: ValueKey('voting-$slug'),
              child: VotingScreen(focusSlug: slug),
            );
          },
        ),
      // Obavijesti o novim epizodama — postoji uvijek (deep link, URL), a
      // ekran sam kaže „samo u aplikaciji" kad ljuska nije predala push
      // transport (web, TV, Podcasterium). Plan:
      // docs/plans/2026-10-15-push-nove-epizode.md §4.3.
      GoRoute(
        path: '/obavijesti',
        pageBuilder: (context, state) => const NoTransitionPage(
          key: ValueKey('notifications'),
          child: NotificationsScreen(),
        ),
      ),
      // Moj račun — account management (identiteti, passkeyji, brisanje)
      GoRoute(
        path: '/account',
        pageBuilder: (context, state) => const NoTransitionPage(
          key: ValueKey('account'),
          child: AccountScreen(),
        ),
      ),
      // M4 handoff — cross-device sign-in transfer
      GoRoute(
        path: '/handoff',
        pageBuilder: (context, state) => const NoTransitionPage(
          key: ValueKey('handoff'),
          child: HandoffScreen(),
        ),
      ),
      GoRoute(
        path: '/handoff/:code',
        pageBuilder: (context, state) {
          final code = state.pathParameters['code'];
          return NoTransitionPage(
            key: ValueKey('handoff-$code'),
            child: HandoffScreen(prefilledCode: code),
          );
        },
      ),
      GoRoute(
        path: '/auth/callback',
        pageBuilder: (context, state) => const NoTransitionPage(
          key: ValueKey('auth_callback'),
          child: AuthCallbackScreen(),
        ),
      ),
      GoRoute(
        path: '/login-callback',
        pageBuilder: (context, state) => const NoTransitionPage(
          key: ValueKey('login_callback'),
          child: AuthCallbackScreen(),
        ),
      ),
      GoRoute(
        path: '/invite',
        pageBuilder: (context, state) {
          final token = state.uri.queryParameters['token'];
          return NoTransitionPage(
            key: ValueKey('invite'),
            child: InviteScreen(token: token),
          );
        },
      ),
      // Legalne stranice — placeholderi za Google OAuth consent screen.
      GoRoute(
        path: '/privacy',
        pageBuilder: (context, state) => const NoTransitionPage(
          key: ValueKey('privacy'),
          child: PrivacyScreen(),
        ),
      ),
      GoRoute(
        path: '/terms',
        pageBuilder: (context, state) => const NoTransitionPage(
          key: ValueKey('terms'),
          child: TermsScreen(),
        ),
      ),
      // Legacy format
      GoRoute(
        path: '/episode/:videoId',
        redirect: (context, state) =>
            '/v/${state.pathParameters['videoId']}',
      ),
    ],
    // ?v=ytId query param support (redirect to /v/ytId)
    redirect: (context, state) {
      final v = state.uri.queryParameters['v'];
      if (v != null && v.isNotEmpty && state.matchedLocation == '/') {
        return '/v/$v';
      }
      return null;
    },
    errorPageBuilder: (context, state) => NoTransitionPage(
      key: const ValueKey('error'),
      child: TvMode.isTv ? const TvHomeScreen() : const HomeScreen(),
    ),
  );
}

/// `?video=0` → false, `?video=1` → true, inače null (vidi
/// EpisodeScreen.openVideo).
bool? _openVideo(GoRouterState state) =>
    switch (state.uri.queryParameters['video']) {
      '0' => false,
      '1' => true,
      _ => null,
    };

String _videoKeySuffix(GoRouterState state) => switch (_openVideo(state)) {
      false => '-novideo',
      true => '-video',
      null => '',
    };
