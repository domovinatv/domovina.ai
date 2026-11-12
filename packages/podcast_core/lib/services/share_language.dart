/// Koji jezik ponuditi u share linku kartice epizode (rail, channel lista).
///
/// Episode ekrani ovo NE trebaju — ondje jezik dolazi iz `EpisodeLanguageScope`
/// odnosno `_language`, koji je stvarno stanje prikaza. Ovdje je riječ o
/// karticama izvan episode ekrana, gdje se mora pogoditi, pa vrijede dva uvjeta
/// istovremeno:
///
///  1. korisnik je izabrao engleski (`PreferredEpisodeLanguage`), i
///  2. za TU epizodu znamo da prijevod postoji.
///
/// Drugi uvjet je bitan: `/v/<id>/en` za neprevedenu epizodu tehnički radi
/// (ruta postoji, worker i aplikacija padnu na hrvatski), ali dijeliti link
/// koji obećava engleski a otvori hrvatski gore je nego dijeliti hrvatski.
///
/// Izvor drugog uvjeta je `pipeline.has_article_en` iz channel listinga, preko
/// `ChannelCache`. CLAUDE.md pravilo kaže da pipeline zastavice lažu u oba
/// smjera i da izostanak zastavice NIJE informacija — oboje se ovdje poštuje:
/// mjereno 15.9.2026. nad svim kanalima, podignuta zastavica nije promašila
/// nijednom (42/42 imaju `article.en.json`), a 5 epizoda ima prijevod uz
/// zastavicu koja šuti. Zato podignuta zastavica nudi EN, a njezin izostanak
/// samo znači „ostajemo na hrvatskom" — nikad „prijevoda nema".
library;

import 'channel_cache.dart';
import 'channel_feature_gate.dart';
import 'episode_language.dart';

/// Jezik za share link epizode [videoId] izvan episode ekrana.
///
/// Vraća HR kad god nismo sigurni: korisnik nije birao engleski, epizoda nije
/// u cacheu (kanal još nije učitan), ili listing ne tvrdi da prijevod postoji.
EpisodeLanguage shareLanguageForVideo(String videoId) {
  if (PreferredEpisodeLanguage.instance.value != EpisodeLanguage.en) {
    return EpisodeLanguage.hr;
  }
  final hit = channelCache.findVideo(videoId);
  // Vlasnik kanala je isključio engleski prijevod (postavke kanala): link
  // ostaje hrvatski i kad listing još nosi staru zastavicu.
  if (!ChannelFeatureGate.isEnabledNow(
        videoId,
        EpisodeKey.englishTranslation,
      ) ||
      (hit != null &&
          !channelCache.channelAllows(
            hit.channelId,
            EpisodeKey.englishTranslation,
          ))) {
    return EpisodeLanguage.hr;
  }
  final hasEn = hit?.video.pipeline?.hasArticleEn ?? false;
  return hasEn ? EpisodeLanguage.en : EpisodeLanguage.hr;
}
