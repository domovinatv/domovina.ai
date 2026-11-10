/// Tekstovi varijanti naslovnice — **svjesna, privremena iznimka** od ARB
/// pravila (plan §5): varijante su eksperiment iza `?home=`, pa u ARB ide tek
/// pobjednik. Do tada HR i EN žive ovdje. Ne koristiti izvan `variants/`.
/// Registar „ti”, bez emojija.
///
/// [of] čita `Localizations.localeOf(context)`, dakle registrira ovisnost:
/// promjena jezika sučelja odmah prevede i varijante (isto pravilo kao
/// `AppLocalizations.of`, ne `appStrings`).
library;

import 'package:flutter/widgets.dart';

class VariantStrings {
  final bool en;

  const VariantStrings._(this.en);

  static VariantStrings of(BuildContext context) =>
      VariantStrings._(Localizations.localeOf(context).languageCode == 'en');

  String _t(String hr, String enText) => en ? enText : hr;

  String get zoneForYou => _t('Za tebe', 'For you');
  String get zoneForYouSub => _t(
    'Gdje si stao i što je novo kod onih koje pratiš.',
    'Where you left off and what is new from those you follow.',
  );
  String get zoneNew => _t('Novo', 'New');
  String get zoneNewSub => _t(
    'Sve što je stiglo, na jednom mjestu.',
    'Everything that just arrived, in one place.',
  );
  String get zoneDiscover => _t('Otkrij', 'Discover');
  String get zoneDiscoverSub => _t(
    'Emisije, ljudi i kanali koje još ne pratiš.',
    'Shows, people and channels you do not follow yet.',
  );

  String get filterAll => _t('Sve', 'All');
  String get filterProcessed => _t('Obrađeno', 'Processed');
  String get filterProcessing => _t('U obradi', 'Processing');
  String get filterCorpus => _t('Danas u korpusu', 'Added today');
  String get filterFollowed => _t('Od praćenih', 'Following');

  String get followedHint => _t(
    'Kad netko koga pratiš objavi novu epizodu, pojavit će se ovdje.',
    'When someone you follow publishes a new episode, it will show up here.',
  );
  String get emptyFilter =>
      _t('Ovdje trenutno nema epizoda.', 'No episodes here right now.');
  String get forYouEmpty => _t(
    'Ovdje će biti epizode koje si započeo, novo od onih koje pratiš i '
        'tvoje spremljeno. Počni slušati bilo što s kartice Novo.',
    'Episodes you have started, new ones from those you follow and your '
        'saved episodes will appear here. Start with anything on the New tab.',
  );

  String get continueListening => _t('Nastavi slušati', 'Continue listening');
  String get continueWhereStopped =>
      _t('Nastavi gdje si stao', 'Pick up where you left off');
  String get alsoStarted => _t('Također započeto', 'Also started');
  String get resume => _t('Nastavi', 'Resume');
  String remaining(int minutes) => en
      ? (minutes <= 1 ? '1 min left' : '$minutes min left')
      : (minutes <= 1 ? 'još minutu' : 'još $minutes min');

  String get featuredToday => _t('Istaknuto danas', 'Featured today');
  String get featuredShows => _t('Istaknute emisije', 'Featured shows');
  String get latest => _t('Najnovije', 'Latest');

  String get shelf => _t('Tvoja polica', 'Your shelf');
  String savedCount(int n) => _t('Spremljeno · $n', 'Saved · $n');
  String get openShelf => _t('Otvori policu', 'Open shelf');

  String get shows => _t('Emisije', 'Shows');
  String get persons => _t('Osobe', 'People');
  String get channels => _t('Kanali', 'Channels');
  String get allPersons => _t('Sve osobe', 'All people');
  String allChannels(int n) => _t('Svi kanali ($n)', 'All channels ($n)');
  String get allNewByDay =>
      _t('Sve nove epizode po danima', 'All new episodes by day');

  String get navHome => _t('Početna', 'Home');
  String get navSearch => _t('Traži', 'Search');
  String get navSaved => _t('Spremljeno', 'Saved');
  String get navAccount => _t('Račun', 'Account');
}
