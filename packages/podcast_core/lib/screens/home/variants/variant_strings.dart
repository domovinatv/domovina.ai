/// Tekstovi varijanti naslovnice — **svjesna, privremena iznimka** od ARB
/// pravila (plan §5): varijante su eksperiment iza `?home=`, pa prijevod ide
/// tek kad se izabere pobjednik (tada u `app_hr.arb`/`app_en.arb`). Ne
/// koristiti izvan `variants/`. Registar „ti”, bez emojija.
library;

class VariantStrings {
  VariantStrings._();

  static const zoneForYou = 'Za tebe';
  static const zoneForYouSub =
      'Gdje si stao i što je novo kod onih koje pratiš.';
  static const zoneNew = 'Novo';
  static const zoneNewSub = 'Sve što je stiglo, na jednom mjestu.';
  static const zoneDiscover = 'Otkrij';
  static const zoneDiscoverSub = 'Emisije, ljudi i kanali koje još ne pratiš.';

  static const filterAll = 'Sve';
  static const filterProcessed = 'Obrađeno';
  static const filterProcessing = 'U obradi';
  static const filterCorpus = 'Danas u korpusu';
  static const filterFollowed = 'Od praćenih';

  static const followedHint =
      'Kad netko koga pratiš objavi novu epizodu, pojavit će se ovdje.';
  static const emptyFilter = 'Ovdje trenutno nema epizoda.';
  static const forYouEmpty =
      'Ovdje će biti epizode koje si započeo, novo od onih koje pratiš i '
      'tvoje spremljeno. Počni slušati bilo što s kartice Novo.';

  static const continueListening = 'Nastavi slušati';
  static const continueWhereStopped = 'Nastavi gdje si stao';
  static const alsoStarted = 'Također započeto';
  static const resume = 'Nastavi';
  static String remaining(int minutes) =>
      minutes <= 1 ? 'još minutu' : 'još $minutes min';

  static const featuredToday = 'Istaknuto danas';
  static const featuredShows = 'Istaknute emisije';
  static const latest = 'Najnovije';

  static const shelf = 'Tvoja polica';
  static String savedCount(int n) => 'Spremljeno · $n';
  static const openShelf = 'Otvori policu';

  static const shows = 'Emisije';
  static const persons = 'Osobe';
  static const channels = 'Kanali';
  static const allPersons = 'Sve osobe';
  static String allChannels(int n) => 'Svi kanali ($n)';
  static const allNewByDay = 'Sve nove epizode po danima';

  static const navHome = 'Početna';
  static const navSearch = 'Traži';
  static const navSaved = 'Spremljeno';
  static const navAccount = 'Račun';
}
