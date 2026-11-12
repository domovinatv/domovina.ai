/// Navigacijski ugovor aplikacije — jedno pravilo po VRSTI prijelaza.
///
/// Povod (analiza 4.9.2026., `docs/2026-09-04-navigacija-i-scroll-restoration.md`):
/// 82 od 98 navigacijskih poziva bila su `context.go()`, koji u go_routeru
/// **zamijeni cijelu listu ruta** umjesto da novu stavi na postojeću. Posljedica
/// je bila da aplikacija nema stog — svaki ekran s kojeg odeš biva *uništen*, a
/// ne odložen, pa se ni scroll ni `canPop()` nemaju odakle vratiti.
///
/// **Rule (odaberi po vrsti prijelaza, ne po osjećaju):**
///
/// | Prijelaz | Helper |
/// |---|---|
/// | lista → detalj, detalj → dublji detalj | [drillDown] |
/// | isti sadržaj, druga prezentacija (`/v` ↔ `/m`, HR ↔ EN) | [swapPresentation] |
/// | peer → peer (epizoda → srodna epizoda) | [goPeer] |
/// | povratak na korijen (logo, breadcrumb „Početna") | `context.go('/')` |
/// | gumb „nazad" | [back] |
///
/// **Rule (`context.go('/')` je dopušten SAMO** u ovoj datoteci, u breadcrumbu
/// „Početna" i u error/prazna stanja ekranima). Svugdje drugdje je to bio
/// prikriveni „nazad" koji je gurao NOVI history entry, pa je browserov Back
/// nakon njega vodio *naprijed* u detalj.
library;

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../brand/app_brand.dart';

/// Najveća dubina imperativnog stoga prije nego [drillDown] prijeđe na
/// `pushReplacement`.
///
/// Bez ograde je `push` curenje memorije: `NoTransitionPage` ima
/// `maintainState: true`, pa svaki ekran u stogu ostaje živ sa svojim
/// slikama i (na epizodama) playerom. Korisnik koji prolista 20 epizoda inače
/// drži 20 živih ekrana. Osam je odabrano kao dubina koju stvarna sesija
/// realno dosegne (home → katalog → kanal → epizoda → osoba → epizoda), uz
/// zalihu; preko toga se najstariji korak tiho gubi umjesto da raste memorija.
const int kMaxStackDepth = 8;

/// Trenutna dubina imperativnog (pushanog) stoga.
///
/// `GoRouterState` ne izlaže broj imperativnih matcheva javno, pa dubinu
/// računamo iz `RouteMatchList`.
int navStackDepthOf(GoRouter router) =>
    router.routerDelegate.currentConfiguration.matches.length - 1;

/// [navStackDepthOf] preko konteksta.
int navStackDepth(BuildContext context) =>
    navStackDepthOf(GoRouter.of(context));

/// Drill-down: lista → detalj, ili detalj → dublji detalj.
///
/// Ovo je zahvat koji vraća scroll bez ijedne linije koda za pamćenje
/// pozicije: ruta ispod ostaje živa (`maintainState: true`), pa njezin
/// `ScrollPosition` nikad ne ode. Na `pop()` se vraća ISTA instanca ekrana —
/// bez `initState`, bez skeletona, bez asinkronog čekanja.
///
/// Preko [kMaxStackDepth] prelazi na `pushReplacement` da stog ne raste
/// neograničeno.
void drillDown(BuildContext context, String location) =>
    drillDownOn(GoRouter.of(context), location);

/// [drillDown] za pozivatelje kojima je `BuildContext` već nestao — tipično
/// modal koji se sam popa PRIJE navigacije (search paleta): nakon `pop()` je
/// njegov context unmountan, pa se `GoRouter` mora uhvatiti unaprijed.
void drillDownOn(GoRouter router, String location) {
  if (navStackDepthOf(router) >= kMaxStackDepth) {
    router.pushReplacement(location);
    return;
  }
  router.push(location);
}

/// Isti sadržaj u drugoj prezentaciji — `/v/<id>` ↔ `/m/<id>`, HR ↔ EN.
///
/// **Ne smije stvoriti history entry**: prebacivanje prikaza nije korak u
/// povijesti pregledavanja. Prije 6.9.2026. je bilo `go()`, pa su dva
/// prebacivanja značila dva lažna Back koraka kroz koja se korisnik morao
/// probiti da se vrati odakle je došao.
void swapPresentation(BuildContext context, String location) {
  context.replace(location);
}

/// Ista lokacija bez jezičnog sufiksa `/en` (`/v/<id>/t/<sec>/en?p=x` →
/// `/v/<id>/t/<sec>?p=x`). Za [swapPresentation] kad vlasnik kanala isključi
/// engleski prijevod (postavke kanala, odluka 503): HR sadržaj se ne smije
/// prikazivati na EN URL-u. Lokacija bez sufiksa se vraća nepromijenjena.
String withoutEnSuffix(String location) {
  final uri = Uri.parse(location);
  final segs = uri.pathSegments;
  if (segs.isEmpty || segs.last != 'en') return location;
  return uri
      .replace(path: '/${segs.sublist(0, segs.length - 1).join('/')}')
      .toString();
}

/// Zamijeni trenutnu rutu istom bez `/en` (vidi [withoutEnSuffix]). Bez
/// routera (testovi) ne radi ništa.
void dropEnSuffix(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router == null) return;
  final here = router.routeInformationProvider.value.uri.toString();
  final hr = withoutEnSuffix(here);
  if (hr != here) router.replace(hr);
}

/// Peer → peer: epizoda → srodna epizoda, kandidat → kandidat.
///
/// Zamjenjuje vrh stoga umjesto da ga produbi — inače bi „još jedna epizoda"
/// iz raila unutar epizode gradila proizvoljno dubok stog istorodnih ekrana.
void goPeer(BuildContext context, String location) {
  context.pushReplacement(location);
}

/// Gumb „nazad" — popa kad ima što, inače ide na SEMANTIČKOG roditelja.
///
/// **Rule (`upTarget` nije uvijek `/`)**: dolazak izvana (share link, hard
/// refresh) nema stog, pa ← mora znati kamo „gore". Do 6.9.2026. je svih 10
/// ekrana padalo na `/`, pa je ← s epizode otvorene iz kataloga vodio na
/// naslovnicu umjesto natrag na kanal.
void back(BuildContext context, {String fallback = '/'}) {
  if (context.canPop()) {
    context.pop();
    return;
  }
  context.go(fallback);
}

/// Semantički roditelj rute — odredište za ← kad stog ne postoji.
///
/// Čista funkcija nad lokacijom, bez `BuildContext`-a, da je pokrivena
/// unit testovima (`test/nav_up_target_test.dart`).
///
/// [channelSlug] je opcionalan jer se na epizodi razrješava asinkrono iz
/// channel indexa (`_resolveChannelSlug`); dok ga nema, epizoda pada na `/`.
String upTarget(String location, {String? channelSlug}) {
  final uri = Uri.parse(location);
  final segs = uri.pathSegments;
  if (segs.isEmpty) return '/';

  switch (segs.first) {
    // Epizoda → njezin kanal, ako ga znamo. Inače naslovnica.
    case 'v':
    case 'm':
      return channelSlug != null && channelSlug.isNotEmpty
          ? '/c/$channelSlug'
          : '/';
    // Kanal → katalog kanala.
    case 'c':
      // Podstranice kanala (/c/<slug>/doniraj, /claim) idu na sam kanal.
      if (segs.length > 2) return '/c/${segs[1]}';
      return '/channels';
    // Osoba → katalog s već odabranim filtrom „Osobe" (ista ruta, query param).
    case 'p':
      return '/channels?prikaz=osobe';
    // Detalj kandidata → ljestvica.
    // Bez `voting` flaga `/glasanje` ne postoji, pa je roditelj naslovnica.
    case 'glasanje':
      return AppBrand.config.flags.voting && segs.length > 1
          ? '/glasanje'
          : '/';
    case 'account':
      // Bez `channelOwnership` flaga `/account/channels*` ne postoji.
      if (!AppBrand.config.flags.channelOwnership) {
        return segs.length > 1 ? '/account' : '/';
      }
      // /account/channels/<uc>/campaigns/... → jedan korak gore.
      if (segs.length > 3) return '/account/channels/${segs[2]}';
      if (segs.length > 2) return '/account/channels';
      if (segs.length > 1) return '/account';
      return '/';
    default:
      return '/';
  }
}

/// [back] koji sam razriješi `upTarget` iz trenutne lokacije.
void backUp(BuildContext context, {String? channelSlug}) {
  if (context.canPop()) {
    context.pop();
    return;
  }
  final here = GoRouterState.of(context).uri.toString();
  context.go(upTarget(here, channelSlug: channelSlug));
}

/// Zatvori imperativni modal (dialog, bottom sheet) kad se promijeni ruta.
///
/// **Zašto je ovo potrebno na webu:** `showDialog`/`showModalBottomSheet` guraju
/// rutu kroz IMPERATIVNI `Navigator`, o kojem go_router ne zna ništa i koja ne
/// proizvodi history entry. Na nativeu je to bezopasno — sistemski Back ide kroz
/// `popRoute()` → `Navigator.maybePop()`, pa modal uredno padne prvi. Na webu
/// browserov Back NE ide tim putem nego kroz `popstate` → `setNewRoutePath`, pa
/// se stranica ISPOD modala promijeni dok modal ostane visjeti preko nje.
///
/// Vraća funkciju za odjavu; pozovi je kad modal ionako nestane.
VoidCallback closeOnRouteChange(BuildContext context, VoidCallback close) {
  final router = GoRouter.of(context);
  final startedAt = router.routerDelegate.currentConfiguration.uri.toString();
  void listener() {
    final now = router.routerDelegate.currentConfiguration.uri.toString();
    if (now != startedAt) close();
  }

  router.routerDelegate.addListener(listener);
  return () => router.routerDelegate.removeListener(listener);
}
