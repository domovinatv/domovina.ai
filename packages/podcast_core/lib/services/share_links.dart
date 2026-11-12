/// Apsolutne poveznice za dijeljenje (`https://domovina.ai/...`).
///
/// **Rule**: share URL epizode se NE sastavlja ručno — ide kroz `episodeShareUrl`.
///
/// Jezik sadržaja je dio PUTANJE (`/en` sufiks, a ne `?lang=en`, jer crawleri
/// droppaju query parametre pri normalizaciji — vidi `web/_worker.js` i rutu u
/// `lib/router/app_router.dart`). Svaki ručno sastavljen string zato tiho gubi
/// jezik: dijeliš engleski trenutak, a primatelj dobije hrvatski.
///
/// Na webu se to nije vidjelo jer adresna traka ima `url_sync` (koji `/en`
/// uredno održava), pa je ručno kopiranje iz trake davalo ispravan link. Na
/// iOS/Android aplikaciji adresne trake nema i „Kopiraj poveznicu" je jedini
/// izvor linka — ondje je gubitak bio potpun. Prijavljeno 15.9.2026.
library;

import '../brand/app_brand.dart';
import 'channel_feature_gate.dart';
import 'episode_language.dart';

/// Kanonski origin aplikacije (`AppBrand.config.endpoints.site`). Share
/// linkovi su uvijek apsolutni — kopiraju se u tuđe aplikacije, gdje
/// relativna putanja ne znači ništa. Getter, ne const: brend se postavlja u
/// runtimeu.
String get kShareOrigin => AppBrand.config.endpoints.site;

/// Poveznica na epizodu, po potrebi na točan trenutak i/ili jezik.
///
/// Redoslijed segmenata je `/v/<id>/t/<sec>/en` — isti koji `_worker.js`
/// matcha i koji `url_sync` piše u adresnu traku. Ne mijenjati bez oba.
///
/// [seconds] ≤ [minSeconds] daje link na cijelu epizodu: prvih nekoliko
/// sekundi nije „trenutak", a `/t/0` bi crawleru bio zaseban cache unos za
/// isti sadržaj.
///
/// [personSlug] je oznaka govornika (`?p=<slug>`) — query je ovdje u redu jer
/// je čisto in-app sidro; izgubi li ga crawler, preview je i dalje točan.
String episodeShareUrl(
  String youtubeId, {
  int? seconds,
  EpisodeLanguage lang = EpisodeLanguage.hr,
  String? personSlug,
  int minSeconds = 5,
}) {
  // Vlasnik kanala je isključio engleski prijevod: `/en` bi otvorio HR
  // sadržaj na EN URL-u (odluka 503), pa link ostaje hrvatski.
  if (lang == EpisodeLanguage.en &&
      !ChannelFeatureGate.isEnabledNow(
        youtubeId,
        EpisodeKey.englishTranslation,
      )) {
    lang = EpisodeLanguage.hr;
  }
  final buf = StringBuffer('$kShareOrigin/v/$youtubeId');
  if (seconds != null && seconds > minSeconds) {
    buf.write('/t/$seconds');
  }
  if (lang == EpisodeLanguage.en) {
    buf.write('/en');
  }
  if (personSlug != null && personSlug.isNotEmpty) {
    buf.write('?p=${Uri.encodeComponent(personSlug)}');
  }
  return buf.toString();
}
