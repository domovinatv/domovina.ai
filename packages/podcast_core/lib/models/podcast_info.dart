import '../services/cdn_config.dart';

/// Model za info.json — yt-dlp metadata
class PodcastInfo {
  final String id;
  final String title;
  final String channel;
  final String channelId;
  final String uploader;
  final String uploadDate; // YYYYMMDD
  final int duration; // seconds
  final String durationString;
  final int viewCount;
  final int likeCount;
  final int? commentCount;
  final String description;
  final String thumbnail;
  final String webpageUrl;
  final List<String> tags;
  final List<String> categories;
  final List<YtChapter> chapters;
  final List<YtThumbnail> thumbnails;

  /// Izvor epizode — npr. `youtube` (default), `x` (X/Twitter post) ili
  /// `beamly` (audio podcast feed preko transistor.fm-a). Iz info.json `_source`.
  final String source;

  /// yt-dlp `extractor` — npr. `youtube`, `twitter`. Sekundarni marker izvora
  /// (X info.json ima `extractor: "twitter"`). Vidi [isX].
  final String extractor;

  /// Direktni link na audio (mp3) za audio-only epizode. Iz info.json
  /// `_sound_link`. Null za standardne (video) epizode.
  final String? soundLink;

  /// `_yt_matched` — false kad epizoda NIJE povezana s YouTube videom (nema
  /// `video.mp4` na CDN-u). Default true (stare/YT epizode nemaju ovo polje).
  final bool ytMatched;

  /// yt-dlp `playable_in_embed` — false kad je vlasnik kanala isključio
  /// ugrađivanje videa na tuđe stranice. Tada naš in-app YouTube iframe
  /// ostane crn ("Video unavailable"), pa se mora ponuditi vanjska poveznica.
  /// Default true: polje ima samo YouTube info.json, a stariji ga nemaju.
  final bool playableInEmbed;

  /// `_variant_of` — pravi YouTube ID izvorne epizode kad je ova epizoda
  /// „varijanta" (ista snimka, drugi prolaz pipelinea) objavljena pod
  /// SINTETIČKIM ID-om (`OspwepfLO_2` = prvih 9 znakova + `_` + broj). Null
  /// za obične epizode. Podaci s CDN-a (`data/<id>/`, `images/<id>/`) i
  /// domovina.ai linkovi ostaju na [id]; sve što ide prema YouTubeu koristi
  /// [youtubeVideoId].
  final String? variantOf;

  /// `_variant.n` — redni broj varijante (npr. 2). Null kad nije varijanta.
  final int? variantNumber;

  /// `_variant.label` — kratki opis varijante (npr. „Canary + pyannote →
  /// Opus"). Null kad nije varijanta ili pipeline nije dao opis.
  final String? variantLabel;

  const PodcastInfo({
    required this.id,
    required this.title,
    required this.channel,
    required this.channelId,
    required this.uploader,
    required this.uploadDate,
    required this.duration,
    required this.durationString,
    required this.viewCount,
    required this.likeCount,
    this.commentCount,
    required this.description,
    required this.thumbnail,
    required this.webpageUrl,
    required this.tags,
    required this.categories,
    required this.chapters,
    required this.thumbnails,
    this.source = 'youtube',
    this.extractor = 'youtube',
    this.soundLink,
    this.ytMatched = true,
    this.playableInEmbed = true,
    this.variantOf,
    this.variantNumber,
    this.variantLabel,
  });

  factory PodcastInfo.fromJson(Map<String, dynamic> json) {
    // Non-YouTube izvori (X/Twitter) imaju drukčiji info.json oblik: nedostaju
    // `channel`/`channel_url`/`view_count`/`categories`, a `duration` može biti
    // decimalan (245.295) umjesto cijelog broja. Sve numeričke vrijednosti zato
    // čitamo preko `num` (int ILI double) i tek onda `.toInt()`, a `channel`
    // fallback-amo na `uploader` ("Hobba 🟢"). Vidi CLAUDE.md / X info.json.
    final channelRaw = json['channel'] as String?;
    final uploaderRaw = json['uploader'] as String? ?? '';
    // Varijanta epizode: `_variant_of` + `_variant: {n, label}`. Čitamo
    // defenzivno — krivi tip ili prazan string znači „nije varijanta".
    final variantOfRaw = json['_variant_of'];
    final variantRaw = json['_variant'];
    final variantMap = variantRaw is Map ? variantRaw : null;
    final variantNumberRaw = variantMap?['n'];
    final variantLabelRaw = variantMap?['label'];
    return PodcastInfo(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      channel: (channelRaw != null && channelRaw.isNotEmpty)
          ? channelRaw
          : uploaderRaw,
      channelId: json['channel_id'] as String? ?? '',
      uploader: uploaderRaw,
      uploadDate: json['upload_date'] as String? ?? '',
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      durationString: json['duration_string'] as String? ?? '',
      viewCount: (json['view_count'] as num?)?.toInt() ?? 0,
      likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
      commentCount: (json['comment_count'] as num?)?.toInt(),
      description: json['description'] as String? ?? '',
      thumbnail: CdnConfig.rebase(json['thumbnail'] as String? ?? ''),
      webpageUrl: json['webpage_url'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>? ?? []).cast<String>(),
      categories: (json['categories'] as List<dynamic>? ?? []).cast<String>(),
      chapters: (json['chapters'] as List<dynamic>? ?? [])
          .map((c) => YtChapter.fromJson(c as Map<String, dynamic>))
          .toList(),
      thumbnails: (json['thumbnails'] as List<dynamic>? ?? [])
          .map((t) => YtThumbnail.fromJson(t as Map<String, dynamic>))
          .toList(),
      source: json['_source'] as String? ?? 'youtube',
      extractor: json['extractor'] as String? ?? 'youtube',
      soundLink: json['_sound_link'] as String?,
      ytMatched: json['_yt_matched'] as bool? ?? true,
      playableInEmbed: json['playable_in_embed'] as bool? ?? true,
      variantOf: variantOfRaw is String && variantOfRaw.trim().isNotEmpty
          ? variantOfRaw.trim()
          : null,
      variantNumber: variantNumberRaw is num ? variantNumberRaw.toInt() : null,
      variantLabel:
          variantLabelRaw is String && variantLabelRaw.trim().isNotEmpty
          ? variantLabelRaw.trim()
          : null,
    );
  }

  /// Je li ova epizoda varijanta druge (sintetički [id], pravi YouTube ID u
  /// [variantOf]).
  bool get isVariant => variantOf != null;

  /// YouTube video ID za player, ytimg thumbnail i youtube.com link:
  /// `variantOf ?? id`. Za varijantu je [id] sintetički i YouTube ga ne zna.
  /// NE koristi za CDN putanje ni domovina.ai linkove — ondje ide [id].
  String get youtubeVideoId => variantOf ?? id;

  /// Je li izvor X/Twitter post (ne YouTube). X info.json ima `_source: "x"` i
  /// `extractor: "twitter"`; kao dodatni guard gledamo i host webpage_url-a.
  /// Za X epizode `id` je SINTETIČKI (sha256→11 znakova) — NIJE pravi YouTube
  /// ID, pa se iz njega ne smije graditi ytimg thumbnail ni youtube.com/watch
  /// link. Vidi [sourceUrl].
  bool get isX =>
      source == 'x' ||
      extractor == 'twitter' ||
      webpageUrl.contains('x.com/') ||
      webpageUrl.contains('twitter.com/');

  /// Link na izvornu epizodu za "Otvori izvor" akciju. Za ne-YouTube izvore
  /// (X post preko `_source: "x"`, ili beamly/transistor audio podcasti s
  /// `_yt_matched == false`) `id` je sintetički pa vodimo na `webpage_url`
  /// (npr. x.com/…/status/… ili launchedfm.com/episode/…). Za prave YouTube
  /// epizode gradimo watch URL iz `id`. Null ako nema upotrebljivog URL-a.
  ///
  /// NB: audio-vs-video odluku za PLAYBACK/UI radi probe (`EpisodeData.isAudioOnly`),
  /// ne ovaj getter — `_sound_link` postoji i na video epizodama.
  String? get sourceUrl {
    if (isX || !ytMatched) {
      return webpageUrl.isNotEmpty ? webpageUrl : null;
    }
    return 'https://www.youtube.com/watch?v=$youtubeVideoId';
  }

  /// Kanonski YouTube channel ID (`UC…`) ili null. yt-dlp `channel_id` JEST
  /// UC ID na izvoru, ali validiramo prije korištenja za ownership match.
  /// Vidi docs/channel-ownership-and-safe-payout-plan.md.
  String? get youtubeChannelId =>
      RegExp(r'^UC[0-9A-Za-z_-]{22}$').hasMatch(channelId) ? channelId : null;

  /// Parses uploadDate (YYYYMMDD) into DateTime
  DateTime get uploadDateTime {
    final s = uploadDate;
    if (s.length == 8) {
      return DateTime(
        int.parse(s.substring(0, 4)),
        int.parse(s.substring(4, 6)),
        int.parse(s.substring(6, 8)),
      );
    }
    return DateTime.now();
  }
}

class YtChapter {
  final double startTime;
  final String title;

  const YtChapter({required this.startTime, required this.title});

  factory YtChapter.fromJson(Map<String, dynamic> json) {
    return YtChapter(
      startTime: (json['start_time'] as num?)?.toDouble() ?? 0,
      title: json['title'] as String? ?? '',
    );
  }
}

class YtThumbnail {
  final String url;
  final int? width;
  final int? height;

  const YtThumbnail({required this.url, this.width, this.height});

  factory YtThumbnail.fromJson(Map<String, dynamic> json) {
    return YtThumbnail(
      url: json['url'] as String? ?? '',
      width: json['width'] as int?,
      height: json['height'] as int?,
    );
  }
}
