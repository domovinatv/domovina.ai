/// Čisti filtri popisa po postavkama kanala (lanac `postavke-kanala/`, S5).
///
/// Stanje je uvijek [ChannelVisibility.instance], a veza epizoda → kanal →
/// `UC…` ide kroz [channelCache] (index, listinzi, `home.json`). Kad se UC ne
/// može odrediti, epizoda ostaje (fail-open, tvrdi uvjet 4 plana).
///
/// Korisnikovi popisi (favoriti, „Nastavi slušati”, „Pratim”): pod
/// `channel_enabled` kartica nestaje, ali spremljeni zapis se NE briše
/// (odluka 502) — kad vlasnik vrati kanal, kartica se vrati.
library;

import '../models/channel_detail.dart' show kYoutubeChannelIdPattern;
import '../models/person_hub.dart';
import 'channel_cache.dart';
import 'channel_setting_keys.dart';
import 'channel_visibility.dart';
import 'watch_progress_service.dart';

/// `UC…` kanala epizode, ili `null` kad se ne zna.
///
/// [uc] je izravan podatak (npr. `info.channelId`, `WatchProgress.channelId`)
/// i ima prednost kad je valjan UC; inače epizoda u učitanim listinzima /
/// `home.json`, pa ime kanala ([channelName]) preko indexa.
String? ucForEpisode(String episodeId, {String? uc, String? channelName}) {
  if (uc != null && kYoutubeChannelIdPattern.hasMatch(uc)) return uc;
  final hit = channelCache.findVideo(episodeId);
  if (hit != null) return channelCache.ucFor(hit.channelId);
  if (channelName != null && channelName.isNotEmpty) {
    final id = channelCache.channelIdForName(channelName);
    if (id != null) return channelCache.ucFor(id);
  }
  return null;
}

/// Je li kanal epizode povučen ili obrisan.
bool isEpisodeChannelGone(String episodeId, {String? uc, String? channelName}) {
  if (ChannelVisibility.instance.snapshot.isEmpty) return false;
  return ChannelVisibility.instance.isGone(
    ucForEpisode(episodeId, uc: uc, channelName: channelName),
  );
}

/// Vrijedi li ključ [key] za kanal epizode.
bool episodeChannelAllows(
  String episodeId,
  String key, {
  String? uc,
  String? channelName,
}) {
  if (ChannelVisibility.instance.snapshot.isEmpty) return true;
  return ChannelVisibility.instance.isEnabled(
    ucForEpisode(episodeId, uc: uc, channelName: channelName),
    key,
  );
}

/// „Nastavi slušati” bez epizoda povučenih/obrisanih kanala.
List<WatchProgress> visibleContinueWatching(List<WatchProgress> list) {
  if (ChannelVisibility.instance.snapshot.isEmpty) return list;
  return [
    for (final wp in list)
      if (!isEpisodeChannelGone(wp.episodeId, uc: wp.channelId)) wp,
  ];
}

/// Smije li pogodak pretrage epizode [videoId] u paletu (`in_app_search`).
///
/// [channelSlug] je ono što izvor nosi: naš interni id kanala (lokalni sloj)
/// ili slug iz Meilija/semantike (crtica ili podvlaka); kad ga cache ne zna,
/// kanal se traži po epizodi.
bool isSearchable(String videoId, {String channelSlug = ''}) {
  final vis = ChannelVisibility.instance;
  if (vis.snapshot.isEmpty) return true;
  String? uc;
  if (channelSlug.isNotEmpty) {
    uc =
        channelCache.ucFor(channelSlug) ??
        channelCache.ucFor(channelSlug.replaceAll('-', '_'));
  }
  uc ??= ucForEpisode(videoId);
  return vis.isEnabled(uc, ChannelKey.inAppSearch);
}

/// Smije li epizoda ostati na profilu osobe (`persons_mentions`): u
/// nastupima i u spomenima. UC dolazi iz backenda (`channel_youtube_id`),
/// inače preko našeg sluga kanala ili same epizode.
bool isPersonEpisodeAllowed(PersonEpisode e) {
  final vis = ChannelVisibility.instance;
  if (vis.snapshot.isEmpty) return true;
  final uc = ucForEpisode(
    e.youtubeId,
    uc: e.channelYoutubeId ?? channelCache.ucFor(e.channel),
    channelName: e.channelName,
  );
  return vis.isEnabled(uc, ChannelKey.personsMentions);
}

/// Profil osobe bez epizoda kanala kojima je isključen `persons_mentions`.
PersonHub visiblePersonHub(PersonHub hub) =>
    ChannelVisibility.instance.snapshot.isEmpty
    ? hub
    : hub.whereEpisodes(isPersonEpisodeAllowed);

/// Ocjena epizode s profila osobe za karticu, ili `null` kad je vlasnik
/// kanala isključio `magisterium` (odluka 504).
int? personEpisodeScore(PersonEpisode e) {
  final score = e.magisteriumScore;
  if (score == null || ChannelVisibility.instance.snapshot.isEmpty) {
    return score;
  }
  final uc = ucForEpisode(
    e.youtubeId,
    uc: e.channelYoutubeId ?? channelCache.ucFor(e.channel),
    channelName: e.channelName,
  );
  return ChannelVisibility.instance.isEnabled(uc, ChannelKey.magisterium)
      ? score
      : null;
}
