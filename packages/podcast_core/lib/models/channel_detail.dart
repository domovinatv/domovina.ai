import '../services/cdn_config.dart';
import '../brand/domain_score.dart';

/// Matcha kanonski YouTube channel ID `UC` + 22 znaka (base64url alfabet).
final RegExp kYoutubeChannelIdPattern = RegExp(r'^UC[0-9A-Za-z_-]{22}$');

/// Vrati validan `UC…` ID iz eksplicitnog polja, ili ga izvuci iz
/// `youtube_channel_url` (npr. `https://www.youtube.com/channel/UC…`).
/// Handle/`/c/` URL-ovi nemaju UC ID pa vraćaju null. Vidi
/// docs/channel-ownership-and-safe-payout-plan.md (Faza 0).
String? canonicalUcId(String? explicit, String? url) {
  if (explicit != null && kYoutubeChannelIdPattern.hasMatch(explicit)) {
    return explicit;
  }
  if (url != null) {
    final m = RegExp(r'/channel/(UC[0-9A-Za-z_-]{22})').firstMatch(url);
    if (m != null) return m.group(1);
  }
  return null;
}

/// Model za /channels/data/{channel_id}.json
class ChannelDetail {
  final String version;
  final String id;
  final String name;
  final String? avatarSquare;
  final String? avatarCover;
  final String youtubeChannelUrl;

  /// Kanonski YouTube channel ID (`UC…`). Izvor: pipeline upisuje yt-dlp
  /// `channel_id` u channel.json. Potreban za ownership verifikaciju
  /// (`channels.list?mine=true` match). Null dok pipeline ne upiše polje
  /// (osim ako se da izvući iz `/channel/UC…` URL-a).
  final String? youtubeChannelId;
  final String? youtubePlaylistUrl;
  final String? description;
  final List<String> tags;
  final int? followerCount;
  final int videoCount;
  final int totalDurationSeconds;
  final int? avgMagisteriumScore;
  final String? latestVideoDate;
  final List<ChannelVideo> videos;

  const ChannelDetail({
    required this.version,
    required this.id,
    required this.name,
    this.avatarSquare,
    this.avatarCover,
    required this.youtubeChannelUrl,
    this.youtubeChannelId,
    this.youtubePlaylistUrl,
    this.description,
    this.tags = const [],
    this.followerCount,
    required this.videoCount,
    required this.totalDurationSeconds,
    this.avgMagisteriumScore,
    this.latestVideoDate,
    required this.videos,
  });

  /// True kad je kanal audio-only izvor (podcast feed, npr. launchedfm.com /
  /// subclub.com) — `youtube_channel_url` host nije youtube.com/youtu.be.
  /// Pouzdano na razini KANALA (vlastiti URL kanala), za razliku od per-epizoda
  /// heuristike koja false-pozitivira (i video epizode na tim kanalima imaju
  /// ne-YouTube URL). Koristi se da channel listing prikaže "Audio Only"
  /// placeholder umjesto generičkog video placeholdera kad epizoda nema thumbnail.
  bool get isAudioSource {
    final host = Uri.tryParse(youtubeChannelUrl)?.host ?? '';
    return host.isNotEmpty &&
        !host.contains('youtube.com') &&
        !host.contains('youtu.be');
  }

  ChannelDetail withVideos(List<ChannelVideo> videos) => ChannelDetail(
        version: version,
        id: id,
        name: name,
        avatarSquare: avatarSquare,
        avatarCover: avatarCover,
        youtubeChannelUrl: youtubeChannelUrl,
        youtubeChannelId: youtubeChannelId,
        youtubePlaylistUrl: youtubePlaylistUrl,
        description: description,
        tags: tags,
        followerCount: followerCount,
        videoCount: videoCount,
        totalDurationSeconds: totalDurationSeconds,
        avgMagisteriumScore: avgMagisteriumScore,
        latestVideoDate: latestVideoDate,
        videos: videos,
      );

  /// Isti kanal bez domenske ocjene ni na kanalu ni na epizodama (vlasnik
  /// je isključio `magisterium`, odluka 504).
  ChannelDetail withoutDomainScore() => ChannelDetail(
        version: version,
        id: id,
        name: name,
        avatarSquare: avatarSquare,
        avatarCover: avatarCover,
        youtubeChannelUrl: youtubeChannelUrl,
        youtubeChannelId: youtubeChannelId,
        youtubePlaylistUrl: youtubePlaylistUrl,
        description: description,
        tags: tags,
        followerCount: followerCount,
        videoCount: videoCount,
        totalDurationSeconds: totalDurationSeconds,
        latestVideoDate: latestVideoDate,
        videos: [for (final v in videos) v.withoutDomainScore()],
      );

  factory ChannelDetail.fromJson(Map<String, dynamic> json) {
    return ChannelDetail(
      version: json['version']?.toString() ?? '1.0',
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      avatarSquare: CdnConfig.rebaseOrNull(json['avatar_square'] as String?),
      avatarCover: CdnConfig.rebaseOrNull(json['avatar_cover'] as String?),
      youtubeChannelUrl: json['youtube_channel_url'] as String? ?? '',
      youtubeChannelId: canonicalUcId(
        json['youtube_channel_id'] as String?,
        json['youtube_channel_url'] as String?,
      ),
      youtubePlaylistUrl: json['youtube_playlist_url'] as String?,
      description: json['description'] as String?,
      tags: (json['tags'] as List<dynamic>? ?? []).cast<String>(),
      followerCount: json['follower_count'] as int?,
      videoCount: json['video_count'] as int? ?? 0,
      totalDurationSeconds: json['total_duration_seconds'] as int? ?? 0,
      avgMagisteriumScore: domainScoreFromJson(json['avg_magisterium_score']),
      latestVideoDate: json['latest_video_date'] as String?,
      videos: (json['videos'] as List<dynamic>? ?? [])
          .map((e) => ChannelVideo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ChannelVideo {
  final String id;
  final String title;
  final String? titleHr;
  final String? date;
  final int? durationSeconds;
  final String? _durationDisplay;
  final int? views;
  final int? likes;
  final String? thumbnail;
  final String? youtubeUrl;
  final String? abstract_;
  final List<String> topics;
  final List<String> speakers;
  final int? magisteriumScore;
  final VideoPipeline? pipeline;

  /// Izvor epizode (npr. `youtube`/`beamly`) i direktni audio link — prisutni
  /// samo ako ih pipeline upiše u channel listing (trenutno još nije slučaj;
  /// detekcija pada na [isAudioOnly] heuristiku po [youtubeUrl] hostu).
  final String? source;
  final String? soundLink;

  const ChannelVideo({
    required this.id,
    required this.title,
    this.titleHr,
    this.date,
    this.durationSeconds,
    String? durationDisplay,
    this.views,
    this.likes,
    this.thumbnail,
    this.youtubeUrl,
    this.abstract_,
    this.topics = const [],
    this.speakers = const [],
    this.magisteriumScore,
    this.pipeline,
    this.source,
    this.soundLink,
  }) : _durationDisplay = durationDisplay;

  /// Trajanje za prikaz („20:14", „1:40:06"). Listing ga nosi kao
  /// `duration_display`, ali `home.json` i skraćeni listing (v2) ne — tada se
  /// računa iz [durationSeconds] u istom obliku koji piše pipeline.
  String? get durationDisplay {
    final given = _durationDisplay;
    if (given != null) return given;
    final secs = durationSeconds;
    if (secs == null || secs <= 0) return null;
    String two(int n) => n.toString().padLeft(2, '0');
    final h = secs ~/ 3600, m = (secs % 3600) ~/ 60, s = secs % 60;
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }

  /// Kopija s tekstom za pretragu (sažetak, teme, govornici) iz
  /// `search.json` — skraćeni listing (v2) ga ne nosi. Prazno polje u kopiji
  /// ostaje kakvo je bilo.
  ChannelVideo withSearchText({
    String? abstract,
    List<String> topics = const [],
    List<String> speakers = const [],
  }) {
    return ChannelVideo(
      id: id,
      title: title,
      titleHr: titleHr,
      date: date,
      durationSeconds: durationSeconds,
      durationDisplay: _durationDisplay,
      views: views,
      likes: likes,
      thumbnail: thumbnail,
      youtubeUrl: youtubeUrl,
      abstract_: abstract_ ?? abstract,
      topics: this.topics.isNotEmpty ? this.topics : topics,
      speakers: this.speakers.isNotEmpty ? this.speakers : speakers,
      magisteriumScore: magisteriumScore,
      pipeline: pipeline,
      source: source,
      soundLink: soundLink,
    );
  }

  /// Display title — prefer Croatian title.
  /// Ista epizoda bez domenske ocjene: vlasnik kanala je isključio
  /// `magisterium` (postavke kanala, odluka 504) — kartica tada nema ni
  /// ocjene ni značke, a sortiranje je vidi kao neocijenjenu.
  ChannelVideo withoutDomainScore() {
    if (magisteriumScore == null && !(pipeline?.hasMagisterium ?? false)) {
      return this;
    }
    return ChannelVideo(
      id: id,
      title: title,
      titleHr: titleHr,
      date: date,
      durationSeconds: durationSeconds,
      durationDisplay: _durationDisplay,
      views: views,
      likes: likes,
      thumbnail: thumbnail,
      youtubeUrl: youtubeUrl,
      abstract_: abstract_,
      topics: topics,
      speakers: speakers,
      magisteriumScore: null,
      pipeline: pipeline?.withoutMagisterium(),
      source: source,
      soundLink: soundLink,
    );
  }

  String get displayTitle => titleHr ?? title;

  /// True SAMO kad channel listing eksplicitno nosi [soundLink] (trenutno ne).
  /// NE smije se izvoditi heuristikom iz [youtubeUrl] hosta — i video epizode
  /// na ne-YouTube kanalima (npr. subclub.com) imaju takav URL, pa bi se sve
  /// lažno označilo kao audio. Autoritativna audio-vs-video odluka je probe na
  /// episode ekranu (`EpisodeData.isAudioOnly` — postoji li `audio.mp3`); u
  /// channel listingu nema pouzdanog signala dok ga pipeline ne doda.
  bool get isAudioOnly => soundLink != null && soundLink!.isNotEmpty;

  factory ChannelVideo.fromJson(Map<String, dynamic> json) {
    // speakers can be List<String> or List<{id, suggested_name, role}>
    final rawSpeakers = json['speakers'] as List<dynamic>? ?? [];
    final speakers = rawSpeakers.map((s) {
      if (s is String) return s;
      if (s is Map<String, dynamic>) {
        return s['suggested_name'] as String? ?? s['name'] as String? ?? '';
      }
      return s.toString();
    }).toList();

    return ChannelVideo(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      titleHr: json['title_hr'] as String?,
      date: json['date'] as String?,
      // num.toInt() (ne `as int?`) — X/Twitter izvor daje decimalne vrijednosti.
      durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
      durationDisplay: json['duration_display'] as String?,
      views: (json['views'] as num?)?.toInt(),
      likes: (json['likes'] as num?)?.toInt(),
      thumbnail: CdnConfig.rebaseOrNull(json['thumbnail'] as String?),
      youtubeUrl: json['youtube_url'] as String?,
      abstract_: json['abstract'] as String?,
      topics: (json['topics'] as List<dynamic>? ?? []).cast<String>(),
      speakers: speakers,
      magisteriumScore: domainScoreFromJson(json['magisterium_score']),
      // v1 listing nosi `pipeline` objekt, v2 (skraćeni) bitmask `p`.
      pipeline: json['pipeline'] != null
          ? VideoPipeline.fromJson(json['pipeline'] as Map<String, dynamic>)
          : json['p'] is num
              ? VideoPipeline.fromBits((json['p'] as num).toInt())
              : null,
      source: json['source'] as String? ?? json['_source'] as String?,
      soundLink:
          json['sound_link'] as String? ?? json['_sound_link'] as String?,
    );
  }
}

class VideoPipeline {
  final bool hasTranscript;
  final bool hasDiarized;
  final bool hasSummary;
  final bool hasArticle;
  final bool hasMagisterium;

  /// Postoji li engleski prijevod članka.
  ///
  /// Jedina zastavica iz ovog bloka kojoj se smije vjerovati kad je PODIGNUTA:
  /// izmjereno 15.9.2026. nad svim kanalima — 42 epizode s podignutom zastavicom,
  /// od toga 0 bez `article.en.json` na CDN-u, ali 5 epizoda ima prijevod a
  /// zastavica šuti. Dakle: `true` ⇒ prijevod postoji, `false` ⇒ ne znamo.
  /// Zato je koristi samo za NUĐENJE engleske varijante (`share_language.dart`),
  /// nikad za tvrdnju da prijevoda nema.
  final bool hasArticleEn;

  const VideoPipeline({
    required this.hasTranscript,
    required this.hasDiarized,
    required this.hasSummary,
    required this.hasArticle,
    required this.hasMagisterium,
    this.hasArticleEn = false,
  });

  /// Zastavice kao bitmask (`p` u `home.json` i skraćenom listingu). Redoslijed
  /// bitova je ugovor s pipelineom i ne smije se mijenjati, samo nadopunjavati
  /// na kraju:
  ///
  /// | bit | zastavica |
  /// |---|---|
  /// | 0 | `has_transcript` |
  /// | 1 | `has_diarized` |
  /// | 2 | `has_summary` |
  /// | 3 | `has_article` |
  /// | 4 | `has_magisterium` |
  /// | 5 | `has_translation_en` |
  /// | 6 | `has_summary_en` |
  /// | 7 | `has_article_en` |
  /// | 8 | `has_magisterium_en` |
  /// Iste zastavice uz spuštenu `has_magisterium` (vidi
  /// [ChannelVideo.withoutDomainScore]).
  VideoPipeline withoutMagisterium() => VideoPipeline(
        hasTranscript: hasTranscript,
        hasDiarized: hasDiarized,
        hasSummary: hasSummary,
        hasArticle: hasArticle,
        hasMagisterium: false,
        hasArticleEn: hasArticleEn,
      );

  factory VideoPipeline.fromBits(int bits) {
    bool bit(int i) => bits & (1 << i) != 0;
    return VideoPipeline(
      hasTranscript: bit(0),
      hasDiarized: bit(1),
      hasSummary: bit(2),
      hasArticle: bit(3),
      hasMagisterium: bit(4),
      // Isto pravilo kao [VideoPipeline.fromJson]: dovoljno je jedno od dva.
      hasArticleEn: bit(7) || bit(5),
    );
  }

  factory VideoPipeline.fromJson(Map<String, dynamic> json) {
    return VideoPipeline(
      hasTranscript: json['has_transcript'] as bool? ?? false,
      hasDiarized: json['has_diarized'] as bool? ?? false,
      hasSummary: json['has_summary'] as bool? ?? false,
      hasArticle: json['has_article'] as bool? ?? false,
      hasMagisterium: json['has_magisterium'] as bool? ?? false,
      // Pipeline piše oba polja; `has_article_en` je ono koje stvarno prati
      // postojanje `article.en.json`, `has_translation_en` je njegov stariji
      // sinonim. Dovoljno je da JEDNO bude podignuto.
      hasArticleEn: (json['has_article_en'] as bool? ?? false) ||
          (json['has_translation_en'] as bool? ?? false),
    );
  }
}
