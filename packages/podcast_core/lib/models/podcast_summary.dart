/// Model za .wav.canary.summary.json — Gemini AI sažetak
class PodcastSummary {
  final String version;
  final DateTime generatedAt;
  final String model;
  final SummarySource source;
  final SummaryContent summary;

  const PodcastSummary({
    required this.version,
    required this.generatedAt,
    required this.model,
    required this.source,
    required this.summary,
  });

  factory PodcastSummary.fromJson(Map<String, dynamic> json) {
    return PodcastSummary(
      version: json['version'] as String? ?? '1.0',
      generatedAt: DateTime.tryParse(json['generated_at'] as String? ?? '') ??
          DateTime.now(),
      model: json['model'] as String? ?? '',
      source:
          SummarySource.fromJson(json['source'] as Map<String, dynamic>? ?? {}),
      summary: SummaryContent.fromJson(
          json['summary'] as Map<String, dynamic>? ?? {}),
    );
  }
}

class SummarySource {
  final String filename;
  final String channel;
  final String youtubeId;
  final String title;
  final String uploadDate; // YYYY-MM-DD
  final int durationSeconds;

  const SummarySource({
    required this.filename,
    required this.channel,
    required this.youtubeId,
    required this.title,
    required this.uploadDate,
    required this.durationSeconds,
  });

  factory SummarySource.fromJson(Map<String, dynamic> json) {
    return SummarySource(
      filename: json['filename'] as String? ?? '',
      channel: json['channel'] as String? ?? '',
      youtubeId: json['youtube_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      uploadDate: json['upload_date'] as String? ?? '',
      // X/Twitter izvor daje decimalan `duration_seconds` (245.295) — čitaj kao
      // `num` pa `.toInt()`, inače `as int?` baca TypeError, `loadSummary` puca,
      // summary postane null i `summaryFor(...)!` u buildu bijeli ekran.
      durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
    );
  }
}

class SummaryContent {
  final String titleHr;
  final String? titleEn;
  final String abstractHr;
  final String? abstractEn;
  final List<String> keyTopics;
  final List<String>? keyTopicsEn;
  final List<SummarySpeaker> speakers;
  final List<String> keyPoints;
  final List<String>? keyPointsEn;
  final List<String> mentionedPeople;
  final List<String>? mentionedPeopleEn;
  final List<String> mentionedPlaces;
  final List<String>? mentionedPlacesEn;
  final List<String> mentionedOrganizations;
  final List<String>? mentionedOrganizationsEn;
  final String language;
  final String contentType;
  final String sentiment;

  const SummaryContent({
    required this.titleHr,
    this.titleEn,
    required this.abstractHr,
    this.abstractEn,
    required this.keyTopics,
    this.keyTopicsEn,
    required this.speakers,
    required this.keyPoints,
    this.keyPointsEn,
    required this.mentionedPeople,
    this.mentionedPeopleEn,
    required this.mentionedPlaces,
    this.mentionedPlacesEn,
    required this.mentionedOrganizations,
    this.mentionedOrganizationsEn,
    required this.language,
    required this.contentType,
    required this.sentiment,
  });

  static List<String>? _optList(dynamic raw) {
    if (raw is! List) return null;
    return raw.cast<String>();
  }

  factory SummaryContent.fromJson(Map<String, dynamic> json) {
    return SummaryContent(
      titleHr: json['title_hr'] as String? ?? '',
      titleEn: json['title_en'] as String?,
      abstractHr: json['abstract_hr'] as String? ?? '',
      abstractEn: json['abstract_en'] as String?,
      keyTopics: (json['key_topics'] as List<dynamic>? ?? []).cast<String>(),
      keyTopicsEn: _optList(json['key_topics_en']),
      speakers: (json['speakers'] as List<dynamic>? ?? [])
          .map((s) => SummarySpeaker.fromJson(s as Map<String, dynamic>))
          .toList(),
      keyPoints: (json['key_points'] as List<dynamic>? ?? []).cast<String>(),
      keyPointsEn: _optList(json['key_points_en']),
      mentionedPeople:
          (json['mentioned_people'] as List<dynamic>? ?? []).cast<String>(),
      mentionedPeopleEn: _optList(json['mentioned_people_en']),
      mentionedPlaces:
          (json['mentioned_places'] as List<dynamic>? ?? []).cast<String>(),
      mentionedPlacesEn: _optList(json['mentioned_places_en']),
      mentionedOrganizations:
          (json['mentioned_organizations'] as List<dynamic>? ?? [])
              .cast<String>(),
      mentionedOrganizationsEn: _optList(json['mentioned_organizations_en']),
      language: json['language'] as String? ?? '',
      contentType: json['content_type'] as String? ?? '',
      sentiment: json['sentiment'] as String? ?? '',
    );
  }
}

class SummarySpeaker {
  final String id;
  final String suggestedName;
  final String role;
  final String? roleEn;

  /// Prevedeno generičko ime („Sudionica iz publike" → „Audience member").
  /// Vlastita imena pipeline ne prevodi; stari `summary.en.json` polje nema.
  final String? suggestedNameEn;

  const SummarySpeaker({
    required this.id,
    required this.suggestedName,
    required this.role,
    this.roleEn,
    this.suggestedNameEn,
  });

  factory SummarySpeaker.fromJson(Map<String, dynamic> json) {
    return SummarySpeaker(
      id: json['id'] as String? ?? '',
      suggestedName: json['suggested_name'] as String? ?? '',
      role: json['role'] as String? ?? '',
      roleEn: json['role_en'] as String?,
      suggestedNameEn: json['suggested_name_en'] as String?,
    );
  }

  /// Capitalized HR role label: "voditelj" → "Voditelj", "gost" → "Gost".
  String get roleLabel {
    if (role.isEmpty) return '';
    return role[0].toUpperCase() + role.substring(1);
  }

  /// Capitalized EN role label ako postoji prijevod, inace fallback na HR.
  String roleLabelEn() {
    final en = roleEn;
    if (en == null || en.isEmpty) return roleLabel;
    return en[0].toUpperCase() + en.substring(1);
  }

  /// Pravo ime govornika ako je razlicito od role-a, inace null.
  /// Pipeline ponekad postavi suggested_name = role kad LLM ne moze izvuci ime
  /// (npr. host se nikad ne predstavi). U tom slucaju zelimo prikazati samo
  /// roleLabel umjesto duplog "Voditelj / Voditelj".
  String? get displayName {
    final raw = suggestedName.trim();
    if (raw.isEmpty) return null;
    if (raw.toLowerCase() == role.toLowerCase()) return null;
    return raw;
  }

  /// [displayName] na jeziku sadržaja: na EN `suggested_name_en` kad ga ima.
  String? displayNameFor(bool en) {
    final name = displayName;
    if (!en || name == null) return name;
    final t = suggestedNameEn?.trim();
    return (t == null || t.isEmpty) ? name : t;
  }

  /// [roleLabel] na jeziku sadržaja.
  String roleLabelFor(bool en) => en ? roleLabelEn() : roleLabel;
}
