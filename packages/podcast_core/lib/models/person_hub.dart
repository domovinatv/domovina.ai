/// Model javnog profila osobe ("person hub") — agregira SVE epizode u kojima se
/// jedna osoba pojavljuje, kroz sve kanale, iza stabilnog slug-a.
///
/// Dva odvojena izvora: [PersonHub.episodes] (osoba GOVORI — diarizirani
/// govornik) i [PersonHub.mentions] (osoba se SPOMINJE u epizodi). Osoba koja
/// nikad nije bila gost (povijesna/pokojna, npr. bl. Ivan Merz) ima samo
/// spomene — profil svejedno postoji i nije 404.
///
/// Mapira se 1:1 na `GET https://mcp.domovina.ai/api/person/{slug}` iz
/// domovina-rag. Ruta u aplikaciji: `/p/:slug` (npr. `/p/don-tomislav-lukac`).
///
/// VAŽNO: person slug je primarni ključ u bazi i koristi se DOSLOVNO (s
/// crticama) — NE transformira se kao channel slug (`-`↔`_`). Kad gradiš link
/// na profil iz imena govornika, reproduciraj [personSlug] točno.
library;

import '../services/cdn_config.dart';
import '../brand/domain_score.dart';

/// ASCII-fold imena → stabilni slug. Mora se poklapati s backend logikom koja
/// generira primarni ključ (npr. "don Tomislav Lukač" → "don-tomislav-lukac",
/// "Željka Markić" → "zeljka-markic"). Ako slug ne postoji na serveru → 404 i
/// profil pokaže prazno stanje.
String personSlug(String name) {
  const fold = {
    'č': 'c', 'ć': 'c', 'š': 's', 'ž': 'z', 'đ': 'd',
    'Č': 'c', 'Ć': 'c', 'Š': 's', 'Ž': 'z', 'Đ': 'd',
  };
  var s = name.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');
  s = s.split('').map((ch) => fold[ch] ?? ch).join();
  s = s
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return s;
}

/// Koliko udjela trajanja epizode osoba mora govoriti da nastup bude "glavni".
/// Odluka O3 u `docs/plans/virtualni-kanali.md`. Granica je INKLUZIVNA.
const double kPersonPrimaryShareThreshold = 0.15;

/// Apsolutni prag govora (sekunde) koji sam po sebi čini nastup glavnim, bez
/// obzira na udio — brani kratke samostalne nastupe u dugim panelima.
/// Granica je INKLUZIVNA.
const int kPersonPrimarySpeakingSeconds = 300;

/// Razina nastupa osobe u epizodi (odluka O3).
///
/// [primary] ulazi u `episode_count` na kartici i u glavni popis epizoda;
/// [cameo] živi u zasebnoj sekciji "Kratki nastupi" — ne skriva se, ali ne
/// napuhuje brojku.
enum PersonEpisodeTier {
  primary,
  cameo;

  static PersonEpisodeTier? tryParse(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'primary':
        return PersonEpisodeTier.primary;
      case 'cameo':
        return PersonEpisodeTier.cameo;
      default:
        return null;
    }
  }
}

/// Klijentska klasifikacija nastupa kad backend NE pošalje `tier` (stari
/// odgovor ili epizoda kojoj `speaking_seconds` nije izmjeren).
///
/// Pravilo O3: `primary` ako je udio ≥ [kPersonPrimaryShareThreshold] ILI je
/// govor ≥ [kPersonPrimarySpeakingSeconds]. Bez ijednog mjerenja govora vraća
/// [PersonEpisodeTier.primary] — graceful degradacija na današnje ponašanje
/// (sve epizode u jednom popisu), jer bi `cameo` tiho sakrio sadržaj.
PersonEpisodeTier classifyPersonEpisodeTier({
  int? speakingSeconds,
  int? durationSeconds,
  double? speakingShare,
}) {
  if (speakingSeconds == null && speakingShare == null) {
    return PersonEpisodeTier.primary;
  }
  if (speakingSeconds != null && speakingSeconds >= kPersonPrimarySpeakingSeconds) {
    return PersonEpisodeTier.primary;
  }
  final share = speakingShare ??
      ((durationSeconds != null && durationSeconds > 0 && speakingSeconds != null)
          ? speakingSeconds / durationSeconds
          : null);
  if (share != null && share >= kPersonPrimaryShareThreshold) {
    return PersonEpisodeTier.primary;
  }
  return PersonEpisodeTier.cameo;
}

/// "13h 39m" iz sekundi — isti oblik kao `ChannelSummary.durationDisplay`, da
/// kartica osobe i kartica kanala čitaju jednako.
String personDurationDisplay(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  return '${s ~/ 3600}h ${(s % 3600) ~/ 60}m';
}

/// Jedna epizoda u kojoj osoba govori.
class PersonEpisode {
  final String youtubeId;
  final String? title;

  /// Naš interni slug izvornog kanala (`n1`, `slijedi_svoj_poziv_2`).
  final String channel;
  final String uploadDate;

  /// Ime izvornog kanala za prikaz ("N1", "Lider"). Null na starom backendu →
  /// UI pada na [channel].
  final String? channelName;

  /// YouTube `UC…` id izvornog kanala. Informativno; ne koristi se za rutanje.
  final String? channelYoutubeId;

  /// True samo kad izvorni kanal ima svoju `/c/` stranicu u aplikaciji.
  /// Ad-hoc izvori (N1, Lider, TEDxZagreb…) nisu praćeni kanali → chip NE
  /// smije biti klikabilan (odluka O4).
  final bool channelTracked;

  /// Trajanje cijele epizode; null dok ga backend ne pošalje.
  final int? durationSeconds;

  /// Koliko sekundi osoba govori u toj epizodi (mjeri F2); null ako nije
  /// izmjereno.
  final int? speakingSeconds;

  /// [speakingSeconds] / [durationSeconds] kako ga je izračunao backend.
  final double? speakingShare;

  /// Razina nastupa — s backenda ako je poslana, inače [classifyPersonEpisodeTier].
  final PersonEpisodeTier tier;

  /// Magisterium ocjena epizode (0–100); null ako epizoda nema obradu.
  final int? magisteriumScore;

  /// Najranija sekunda u kojoj osoba govori u toj epizodi.
  final int firstTs;

  /// Gotov deep-link na player rutu (`/v/:id/t/:sec`). Koristi se direktno.
  final String deepLink;

  const PersonEpisode({
    required this.youtubeId,
    required this.title,
    required this.channel,
    required this.uploadDate,
    required this.firstTs,
    required this.deepLink,
    this.channelName,
    this.channelYoutubeId,
    this.channelTracked = false,
    this.durationSeconds,
    this.speakingSeconds,
    this.speakingShare,
    this.tier = PersonEpisodeTier.primary,
    this.magisteriumScore,
  });

  bool get isCameo => tier == PersonEpisodeTier.cameo;

  /// Ime kanala za prikaz — pada na interni slug kad backend ne pošalje ime.
  String get channelDisplayName =>
      (channelName != null && channelName!.trim().isNotEmpty)
          ? channelName!
          : channel;

  /// Ruta `/c/:slug` izvornog kanala — **samo** kad je [channelTracked].
  /// Null znači "kanal nema stranicu", pa chip ostaje neklikabilan.
  String? get channelRoutePath {
    if (!channelTracked || channel.isEmpty) return null;
    return '/c/${channel.replaceAll('_', '-')}';
  }

  /// In-app ruta iz [deepLink] (path bez sheme/hosta), npr.
  /// `https://domovina.ai/v/ID/t/6` → `/v/ID/t/6`. Fallback na `/v/:id` ako
  /// deep_link nije upotrebljiv.
  String get routePath {
    final dl = deepLink.trim();
    if (dl.isNotEmpty) {
      final uri = Uri.tryParse(dl);
      if (uri != null && uri.path.startsWith('/v/')) return uri.path;
    }
    return '/v/$youtubeId';
  }

  factory PersonEpisode.fromJson(Map<String, dynamic> json) {
    final durationSeconds = (json['duration_seconds'] as num?)?.toInt();
    final speakingSeconds = (json['speaking_seconds'] as num?)?.toInt();
    final speakingShare = (json['speaking_share'] as num?)?.toDouble();
    return PersonEpisode(
      youtubeId: json['youtube_id'] as String? ?? '',
      title: json['title'] as String?,
      channel: json['channel'] as String? ?? '',
      uploadDate: json['upload_date'] as String? ?? '',
      channelName: json['channel_name'] as String?,
      channelYoutubeId: json['channel_youtube_id'] as String?,
      channelTracked: json['channel_tracked'] as bool? ?? false,
      durationSeconds: durationSeconds,
      speakingSeconds: speakingSeconds,
      speakingShare: speakingShare,
      tier: PersonEpisodeTier.tryParse(json['tier'] as String?) ??
          classifyPersonEpisodeTier(
            speakingSeconds: speakingSeconds,
            durationSeconds: durationSeconds,
            speakingShare: speakingShare,
          ),
      magisteriumScore: domainScoreFromJson(json['magisterium_score']),
      firstTs: (json['first_ts'] as num?)?.toInt() ?? 0,
      deepLink: json['deep_link'] as String? ?? '',
    );
  }
}

/// Broj epizoda na jednom kanalu (raspodjela "gostuje na").
class PersonChannelCount {
  final String channel;
  final int count;

  const PersonChannelCount({required this.channel, required this.count});

  /// Channel slug → route slug za `/c/:slug` (kanali koriste `-` umjesto `_`).
  String get channelRouteSlug => channel.replaceAll('_', '-');

  factory PersonChannelCount.fromJson(Map<String, dynamic> json) {
    return PersonChannelCount(
      channel: json['channel'] as String? ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Broj epizoda u jednom mjesecu ("2019-01") — za timeline graf.
class PersonMonthCount {
  final String month;
  final int count;

  const PersonMonthCount({required this.month, required this.count});

  factory PersonMonthCount.fromJson(Map<String, dynamic> json) {
    return PersonMonthCount(
      month: json['month'] as String? ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Cijeli profil govornika.
class PersonHub {
  final String name;
  final String slug;
  final String? avatarUrl;
  final int channelCount;
  final int episodeCount;
  final List<PersonChannelCount> channels;
  final List<PersonEpisode> episodes;
  final List<PersonMonthCount> timeline;

  /// Epizode u kojima se osoba SPOMINJE (mentioned_people), a NE govori —
  /// zaseban izvor od [episodes]. Prazno dok backend ne pošalje `mentions`
  /// (sekcija se tada jednostavno ne prikaže). Mention nema speaking-timestamp
  /// pa je `first_ts` 0 i `deep_link` je `/v/<id>` bez `/t/`.
  final List<PersonEpisode> mentions;

  /// Broj epizoda u kojima se osoba spominje (`mention_episode_count` s backenda,
  /// fallback na duljinu [mentions]).
  final int mentionCount;

  /// Raspodjela SPOMENA po kanalima / mjesecima — pandan [channels]/[timeline]
  /// za osobu koja se samo spominje. Bez njih bi takav profil bio gol (govor-
  /// agregacije su prazne). Koriste se samo kad [episodes] nema.
  final List<PersonChannelCount> mentionChannels;
  final List<PersonMonthCount> mentionTimeline;

  /// Epizode s `tier == cameo` koje backend šalje u zasebnom `cameo_episodes[]`.
  /// Sekcija "Kratki nastupi" na profilu; ne broje se u [episodeCount].
  final List<PersonEpisode> cameoEpisodes;

  /// `cameo_episode_count` s backenda; fallback na duljinu [cameoAppearances].
  final int cameoEpisodeCount;

  /// Ukupno trajanje `primary` epizoda. Fallback: zbroj poznatih trajanja.
  final int totalDurationSeconds;

  /// Prosjek Magisterium ocjena epizoda koje je imaju; null ako nijedna nema.
  final int? avgMagisteriumScore;

  /// Godina prvog i zadnjeg nastupa (za deterministički podnaslov).
  final int? firstYear;
  final int? lastYear;

  /// Osoba je zatražila uklanjanje (O8) — profil ostaje kao MINIMALNI (ime +
  /// poruka), nikad 404, da već podijeljeni linkovi ne puknu.
  final bool optout;

  /// Jedan slug pokriva više različitih osoba (kolizija ASCII-folda). Tada se
  /// kanal-forma NE aktivira — vidi rizik "Kolizija slugova" u planu.
  final bool ambiguous;

  final bool _isVirtualChannel;

  /// Osoba se prikazuje kao virtualni kanal. Backend računa prag (≥ 3 `primary`
  /// epizode i bez opt-outa); frontend dodatno gasi formu na [ambiguous], jer
  /// bi spojena dva identiteta bila kanal koji ne pripada nikome.
  ///
  /// Stari backend ne šalje `is_virtual_channel` → false → današnji izgled.
  bool get isVirtualChannel => _isVirtualChannel && !ambiguous && !optout;

  /// Osoba postoji u korpusu samo kroz spomene — nikad nije bila gost.
  bool get isMentionOnly => episodes.isEmpty && mentions.isNotEmpty;

  /// Glavni nastupi iz [episodes]. Backend već šalje samo `primary` u
  /// `episodes[]`, ali filtriramo i ovdje da klijentska klasifikacija (stari
  /// odgovor s `speaking_seconds`, bez `tier`) ne propusti cameo u glavni popis.
  List<PersonEpisode> get primaryEpisodes =>
      episodes.where((e) => !e.isCameo).toList(growable: false);

  /// Svi kratki nastupi — `cameo_episodes[]` plus ono što je u `episodes[]`
  /// klasificirano kao cameo.
  List<PersonEpisode> get cameoAppearances => [
        ...episodes.where((e) => e.isCameo),
        ...cameoEpisodes,
      ];

  /// SVI nastupi u jednom popisu, najnoviji prvo.
  ///
  /// Ovo je popis za prikaz **bez** kanal-forme, i mora ostati potpun. Backend
  /// od 3.9.2026. dijeli nastupe na `episodes[]` (primary) i `cameo_episodes[]`;
  /// izmjereno tog dana, `cameo` je **31,7 %** svih parova govornik-epizoda.
  /// Kad bi profil bez flaga crtao samo `episodes`, gotovo trećina nečijih
  /// nastupa bi tiho nestala s javne stranice — a taj prikaz po definiciji
  /// mora izgledati točno kao prije uvođenja virtualnih kanala.
  ///
  /// Podjela na dvije sekcije postoji SAMO u kanal-formi, gdje je i objašnjena
  /// („Kratki nastupi").
  List<PersonEpisode> get allAppearances {
    if (cameoEpisodes.isEmpty) return episodes;
    final all = [...episodes, ...cameoEpisodes];
    // Backend sortira svaki popis zasebno; spojeni popis se mora presortirati
    // ili bi cameo nastupi svi pali na dno bez obzira na datum.
    all.sort((a, b) => b.uploadDate.compareTo(a.uploadDate));
    return all;
  }

  /// Isti profil samo s epizodama za koje [keep] vrijedi — u nastupima
  /// (`episodes`, `cameo_episodes`) i u spomenima. Brojači se umanje za
  /// izbačene epizode, a kanali bez ijedne preostale epizode ispadaju iz
  /// popisa kanala. Vremenska crta po mjesecima ostaje kako ju je backend
  /// izračunao (nema podjele po kanalu).
  ///
  /// Postavke kanala (S5, `persons_mentions`) — privremeni klijentski filtar
  /// dok RAG ne preračuna profile bez kanala (matrica, redak 15). Vraća
  /// ISTI objekt kad ništa nije izbačeno.
  PersonHub whereEpisodes(bool Function(PersonEpisode e) keep) {
    final ep = episodes.where(keep).toList();
    final cameo = cameoEpisodes.where(keep).toList();
    final ment = mentions.where(keep).toList();
    final removedEp = episodes.length - ep.length;
    final removedCameo = cameoEpisodes.length - cameo.length;
    final removedMent = mentions.length - ment.length;
    if (removedEp == 0 && removedCameo == 0 && removedMent == 0) return this;
    final speaking = {for (final e in [...ep, ...cameo]) e.channel};
    final mentioned = {for (final e in ment) e.channel};
    final removedSpeaking = {
      for (final e in [...episodes, ...cameoEpisodes])
        if (!keep(e)) e.channel,
    }..removeAll(speaking);
    final removedMentioned = {
      for (final e in mentions)
        if (!keep(e)) e.channel,
    }..removeAll(mentioned);
    int clamp(int v) => v < 0 ? 0 : v;
    final keptChannels = [
      for (final c in channels)
        if (!removedSpeaking.contains(c.channel)) c,
    ];
    return PersonHub(
      name: name,
      slug: slug,
      avatarUrl: avatarUrl,
      channelCount: clamp(channelCount - (channels.length - keptChannels.length)),
      episodeCount: clamp(episodeCount - removedEp - removedCameo),
      channels: keptChannels,
      episodes: ep,
      timeline: timeline,
      mentions: ment,
      mentionCount: clamp(mentionCount - removedMent),
      mentionChannels: [
        for (final c in mentionChannels)
          if (!removedMentioned.contains(c.channel)) c,
      ],
      mentionTimeline: mentionTimeline,
      cameoEpisodes: cameo,
      cameoEpisodeCount: clamp(
        cameoEpisodeCount -
            removedCameo -
            episodes.where((e) => e.isCameo && !keep(e)).length,
      ),
      totalDurationSeconds: clamp(
        totalDurationSeconds -
            [...episodes, ...cameoEpisodes]
                .where((e) => !keep(e))
                .fold<int>(0, (sum, e) => sum + (e.durationSeconds ?? 0)),
      ),
      avgMagisteriumScore: avgMagisteriumScore,
      firstYear: firstYear,
      lastYear: lastYear,
      optout: optout,
      ambiguous: ambiguous,
      isVirtualChannel: _isVirtualChannel,
    );
  }

  /// "13h 39m" — hero/kartica virtualnog kanala.
  String get durationDisplay => personDurationDisplay(totalDurationSeconds);

  const PersonHub({
    required this.name,
    required this.slug,
    required this.avatarUrl,
    required this.channelCount,
    required this.episodeCount,
    required this.channels,
    required this.episodes,
    required this.timeline,
    this.mentions = const [],
    this.mentionCount = 0,
    this.mentionChannels = const [],
    this.mentionTimeline = const [],
    this.cameoEpisodes = const [],
    this.cameoEpisodeCount = 0,
    this.totalDurationSeconds = 0,
    this.avgMagisteriumScore,
    this.firstYear,
    this.lastYear,
    this.optout = false,
    this.ambiguous = false,
    bool isVirtualChannel = false,
  }) : _isVirtualChannel = isVirtualChannel;

  factory PersonHub.fromJson(Map<String, dynamic> json) {
    final rawChannels = json['channels'] as List<dynamic>? ?? const [];
    final rawEpisodes = json['episodes'] as List<dynamic>? ?? const [];
    final rawTimeline = json['timeline'] as List<dynamic>? ?? const [];
    final rawMentions = json['mentions'] as List<dynamic>? ?? const [];
    final rawMentionChannels =
        json['mention_channels'] as List<dynamic>? ?? const [];
    final rawMentionTimeline =
        json['mention_timeline'] as List<dynamic>? ?? const [];
    final rawCameo = json['cameo_episodes'] as List<dynamic>? ?? const [];

    final episodes = rawEpisodes
        .map((e) => PersonEpisode.fromJson(e as Map<String, dynamic>))
        .toList();
    final cameoEpisodes = rawCameo
        .map((e) => PersonEpisode.fromJson(e as Map<String, dynamic>))
        .toList();
    final primary = episodes.where((e) => !e.isCameo);

    // Sva agregatna polja imaju izračunat fallback: stari backend ih ne šalje,
    // a hero/kartica ih traže. Izračun nikad ne izmišlja podatak — zbroji se
    // samo ono što je stvarno stiglo.
    final totalDuration = (json['total_duration_seconds'] as num?)?.toInt() ??
        primary.fold<int>(0, (sum, e) => sum + (e.durationSeconds ?? 0));

    final rawAvg = domainScoreFromJson(json['avg_magisterium_score']);
    final scores = episodes
        .map((e) => e.magisteriumScore)
        .whereType<int>()
        .toList(growable: false);
    final avgScore = rawAvg ??
        (scores.isEmpty
            ? null
            : (scores.reduce((a, b) => a + b) / scores.length).round());

    final years = episodes
        .map((e) => int.tryParse(e.uploadDate.split('-').first))
        .whereType<int>()
        .where((y) => y > 1900)
        .toList(growable: false)
      ..sort();
    final firstYear = (json['first_year'] as num?)?.toInt() ??
        (years.isEmpty ? null : years.first);
    final lastYear =
        (json['last_year'] as num?)?.toInt() ?? (years.isEmpty ? null : years.last);

    return PersonHub(
      name: json['name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      avatarUrl: CdnConfig.rebaseOrNull(json['avatar_url'] as String?),
      channelCount: (json['channel_count'] as num?)?.toInt() ?? 0,
      episodeCount: (json['episode_count'] as num?)?.toInt() ?? 0,
      channels: rawChannels
          .map((e) => PersonChannelCount.fromJson(e as Map<String, dynamic>))
          .toList(),
      episodes: episodes,
      timeline: rawTimeline
          .map((e) => PersonMonthCount.fromJson(e as Map<String, dynamic>))
          .toList(),
      mentions: rawMentions
          .map((e) => PersonEpisode.fromJson(e as Map<String, dynamic>))
          .toList(),
      mentionCount: (json['mention_episode_count'] as num?)?.toInt() ??
          rawMentions.length,
      mentionChannels: rawMentionChannels
          .map((e) => PersonChannelCount.fromJson(e as Map<String, dynamic>))
          .toList(),
      mentionTimeline: rawMentionTimeline
          .map((e) => PersonMonthCount.fromJson(e as Map<String, dynamic>))
          .toList(),
      cameoEpisodes: cameoEpisodes,
      cameoEpisodeCount: (json['cameo_episode_count'] as num?)?.toInt() ??
          (cameoEpisodes.length + episodes.where((e) => e.isCameo).length),
      totalDurationSeconds: totalDuration,
      avgMagisteriumScore: avgScore,
      firstYear: firstYear,
      lastYear: lastYear,
      optout: json['optout'] as bool? ?? false,
      ambiguous: json['ambiguous'] as bool? ?? false,
      isVirtualChannel: json['is_virtual_channel'] as bool? ?? false,
    );
  }
}

/// Jedna osoba u indeksu virtualnih kanala (`GET /api/persons`, §4.1 plana).
///
/// Namjerno je ODVOJEN model od [PersonHub]: index je popis za katalog/rail/
/// pretragu (bez epizoda), hub je puni profil. Polje `latest_episode` je
/// pandan `ChannelSummary.latestVideo`.
class PersonSummary {
  final String slug;
  final String name;
  final String? avatarUrl;

  /// Broj `primary` epizoda — ista brojka koju hero i kartica prikazuju.
  final int episodeCount;
  final int channelCount;
  final int totalDurationSeconds;
  final int? avgMagisteriumScore;
  final int? firstYear;
  final int? lastYear;

  /// Backend već primjenjuje prag i opt-out; frontend ovo NE preračunava.
  final bool isVirtualChannel;
  final PersonLatestEpisode? latestEpisode;

  const PersonSummary({
    required this.slug,
    required this.name,
    this.avatarUrl,
    this.episodeCount = 0,
    this.channelCount = 0,
    this.totalDurationSeconds = 0,
    this.avgMagisteriumScore,
    this.firstYear,
    this.lastYear,
    this.isVirtualChannel = false,
    this.latestEpisode,
  });

  /// "13h 39m" — isti oblik kao na kartici kanala.
  String get durationDisplay => personDurationDisplay(totalDurationSeconds);

  /// In-app ruta profila. Person slug se koristi DOSLOVNO (bez `-`↔`_`).
  String get routePath => '/p/$slug';

  /// Inicijali za monogram avatar (T3) — najviše dva slova.
  String get initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && RegExp(r'^\p{L}', unicode: true).hasMatch(w))
        .toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  factory PersonSummary.fromJson(Map<String, dynamic> json) {
    final latest = json['latest_episode'];
    return PersonSummary(
      slug: json['slug'] as String? ?? '',
      name: json['name'] as String? ?? '',
      avatarUrl: CdnConfig.rebaseOrNull(json['avatar_url'] as String?),
      episodeCount: (json['episode_count'] as num?)?.toInt() ?? 0,
      channelCount: (json['channel_count'] as num?)?.toInt() ?? 0,
      totalDurationSeconds:
          (json['total_duration_seconds'] as num?)?.toInt() ?? 0,
      avgMagisteriumScore: domainScoreFromJson(json['avg_magisterium_score']),
      firstYear: (json['first_year'] as num?)?.toInt(),
      lastYear: (json['last_year'] as num?)?.toInt(),
      isVirtualChannel: json['is_virtual_channel'] as bool? ?? false,
      latestEpisode: latest is Map<String, dynamic>
          ? PersonLatestEpisode.fromJson(latest)
          : null,
    );
  }
}

/// Zadnja epizoda osobe — izvor za rail "Novo od praćenih" (T5).
class PersonLatestEpisode {
  final String youtubeId;
  final String date;
  final String title;

  const PersonLatestEpisode({
    required this.youtubeId,
    required this.date,
    required this.title,
  });

  String get routePath => '/v/$youtubeId';

  factory PersonLatestEpisode.fromJson(Map<String, dynamic> json) {
    return PersonLatestEpisode(
      youtubeId: json['youtube_id'] as String? ?? '',
      date: json['date'] as String? ?? '',
      title: json['title'] as String? ?? '',
    );
  }
}

/// Indeks osoba — pandan [ChannelIndex] za virtualne kanale.
class PersonIndex {
  final String version;
  final int personCount;
  final List<PersonSummary> persons;

  const PersonIndex({
    this.version = '1.0',
    this.personCount = 0,
    this.persons = const [],
  });

  /// Prazan indeks — backend bez `/api/persons` (404) ili greška u mreži.
  static const PersonIndex empty = PersonIndex();

  /// Samo osobe koje smiju izgledati kao kanal (katalog, rail, TV lane).
  List<PersonSummary> get virtualChannels =>
      persons.where((p) => p.isVirtualChannel).toList(growable: false);

  PersonSummary? bySlug(String slug) {
    for (final p in persons) {
      if (p.slug == slug) return p;
    }
    return null;
  }

  factory PersonIndex.fromJson(Map<String, dynamic> json) {
    final raw = json['persons'] as List<dynamic>? ?? const [];
    final persons = raw
        .whereType<Map<String, dynamic>>()
        .map(PersonSummary.fromJson)
        .where((p) => p.slug.isNotEmpty)
        .toList();
    return PersonIndex(
      version: json['version'] as String? ?? '1.0',
      personCount: (json['person_count'] as num?)?.toInt() ?? persons.length,
      persons: persons,
    );
  }
}
