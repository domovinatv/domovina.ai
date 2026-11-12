/// Postavke kanala na razini EPIZODE (lanac `postavke-kanala/`, S5).
///
/// [ChannelVisibility] zna stanje po `UC…`, a ekrani i servisi epizode znaju
/// samo `youtubeId`. Ovaj registar ih spaja: `DataService.loadInfo` upiše UC
/// epizode čim `info.json` stigne, a svaki dohvat AI artefakta (članak,
/// titlovi, Magisterium, reelovi, e-knjiga, sponzori, plaćeni trenuci,
/// medija) pita [ChannelFeatureGate.isEnabled] PRIJE zahtjeva (matrica §B,
/// odluka 500). Tri stabla playera i TV tako dobiju isto bez prop drillinga.
///
/// Fail-open (tvrdi uvjet 4): epizoda čiji `info.json` još nije tražen, bez
/// UC-a (X, RSS, beamly) ili kanal izvan mape = sve uključeno, kao danas, i
/// bez ijednog dodatnog zahtjeva.
library;

import 'channel_visibility.dart';

/// Ključevi koje provodi ekran epizode. Ugovor imena je `kChannelSettingDefs`
/// u `models/channel_settings.dart` (provjerava
/// `test/channel_settings_episode_gate_test.dart`).
abstract final class EpisodeKey {
  static const channelEnabled = 'channel_enabled';
  static const cdnPlayback = 'cdn_playback';
  static const shareClips = 'share_clips';
  static const ebook = 'ebook';
  static const articleSummary = 'article_summary';
  static const transcriptSubtitles = 'transcript_subtitles';
  static const englishTranslation = 'english_translation';
  static const magisterium = 'magisterium';
  static const highlightsReels = 'highlights_reels';
  static const personsMentions = 'persons_mentions';
  static const donations = 'donations';
  static const paidSponsorMoments = 'paid_sponsor_moments';
  static const sponsorsInVideo = 'sponsors_in_video';

  static const all = [
    channelEnabled,
    cdnPlayback,
    shareClips,
    ebook,
    articleSummary,
    transcriptSubtitles,
    englishTranslation,
    magisterium,
    highlightsReels,
    personsMentions,
    donations,
    paidSponsorMoments,
    sponsorsInVideo,
  ];
}

abstract final class ChannelFeatureGate {
  /// `youtubeId` → UC u letu (ili gotov). Puni ga [remember].
  static final Map<String, Future<String?>> _pending = {};

  /// `youtubeId` → UC kad je poznat (sinkrono, za `build` i share URL-ove).
  static final Map<String, String?> _known = {};

  static const int _max = 256;

  /// Zapamti UC epizode iz dohvata `info.json`. Prvi upis vrijedi (epizoda ne
  /// mijenja kanal); greška dohvata znači „nepoznato” (fail-open).
  static void remember(String youtubeId, Future<String?> uc) {
    if (_pending.containsKey(youtubeId)) return;
    final f = uc.then<String?>((v) {
      _known[youtubeId] = v;
      return v;
    }, onError: (Object _) => null);
    _pending[youtubeId] = f;
    while (_pending.length > _max) {
      final first = _pending.keys.first;
      _pending.remove(first);
      _known.remove(first);
    }
  }

  /// Sinkrono zapamti UC (npr. iz listinga kanala).
  static void rememberKnown(String youtubeId, String? uc) {
    if (uc == null || uc.isEmpty) return;
    _known[youtubeId] = uc;
    _pending.putIfAbsent(youtubeId, () => Future.value(uc));
  }

  /// UC epizode ako je već poznat.
  static String? channelOf(String youtubeId) => _known[youtubeId];

  /// Sinkrona odluka iz onoga što je već poznato (za `build`, share URL).
  static bool isEnabledNow(String youtubeId, String key) =>
      ChannelVisibility.instance.isEnabled(_known[youtubeId], key);

  /// Smije li se za epizodu [youtubeId] dohvatiti/prikazati [key]. Čeka UC
  /// samo ako je `info.json` već tražen, a katalog najviše 1,5 s
  /// ([ChannelVisibility.ready]); bez UC-a ne pita katalog uopće.
  static Future<bool> isEnabled(String youtubeId, String key) async {
    final pending = _pending[youtubeId];
    if (pending == null) return true;
    final uc = await pending;
    if (uc == null || uc.isEmpty) return true;
    await ChannelVisibility.instance.ready();
    return ChannelVisibility.instance.isEnabled(uc, key);
  }

  /// Zaboravi sve UC-ove (testovi, kroz `DataService.resetMemoryForTest`).
  static void forgetAll() {
    _pending.clear();
    _known.clear();
  }
}
