import '../services/cdn_config.dart';
import 'channel_detail.dart' show canonicalUcId;
import '../brand/domain_score.dart';

/// Model za /channels/data/index.json
class ChannelIndex {
  final String version;
  final int channelCount;
  final List<ChannelSummary> channels;

  const ChannelIndex({
    required this.version,
    required this.channelCount,
    required this.channels,
  });

  factory ChannelIndex.fromJson(Map<String, dynamic> json) {
    return ChannelIndex(
      version: json['version']?.toString() ?? '1.0',
      channelCount: json['channel_count'] as int? ?? 0,
      channels: (json['channels'] as List<dynamic>? ?? [])
          .map((e) => ChannelSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ChannelSummary {
  final String id;
  final String name;
  final String? avatarSquare;
  final String? avatarCover;
  final ImageDimensions? avatarCoverDimensions;
  final String youtubeChannelUrl;

  /// Kanonski `UC…` ID — vidi [ChannelDetail.youtubeChannelId].
  final String? youtubeChannelId;
  final String? youtubePlaylistUrl;
  final int? followerCount;
  final int videoCount;
  final int totalDurationSeconds;
  final int? avgMagisteriumScore;
  final LatestVideo? latestVideo;

  const ChannelSummary({
    required this.id,
    required this.name,
    this.avatarSquare,
    this.avatarCover,
    this.avatarCoverDimensions,
    required this.youtubeChannelUrl,
    this.youtubeChannelId,
    this.youtubePlaylistUrl,
    this.followerCount,
    required this.videoCount,
    required this.totalDurationSeconds,
    this.avgMagisteriumScore,
    this.latestVideo,
  });

  String get durationDisplay {
    final h = totalDurationSeconds ~/ 3600;
    final m = (totalDurationSeconds % 3600) ~/ 60;
    return '${h}h ${m}m';
  }

  /// True if cover is a real banner (width != height).
  bool get hasBannerCover {
    final d = avatarCoverDimensions;
    if (d == null || avatarCover == null) return false;
    return d.width != d.height;
  }

  /// Isti kanal bez prosječne domenske ocjene (vlasnik je isključio
  /// `magisterium`, odluka 504).
  ChannelSummary withoutDomainScore() => avgMagisteriumScore == null
      ? this
      : ChannelSummary(
          id: id,
          name: name,
          avatarSquare: avatarSquare,
          avatarCover: avatarCover,
          avatarCoverDimensions: avatarCoverDimensions,
          youtubeChannelUrl: youtubeChannelUrl,
          youtubeChannelId: youtubeChannelId,
          youtubePlaylistUrl: youtubePlaylistUrl,
          followerCount: followerCount,
          videoCount: videoCount,
          totalDurationSeconds: totalDurationSeconds,
          latestVideo: latestVideo,
        );

  factory ChannelSummary.fromJson(Map<String, dynamic> json) {
    final lv = json['latest_video'];
    final coverDim = json['avatar_cover_dimensions'];
    return ChannelSummary(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      avatarSquare: CdnConfig.rebaseOrNull(json['avatar_square'] as String?),
      avatarCover: CdnConfig.rebaseOrNull(json['avatar_cover'] as String?),
      avatarCoverDimensions:
          coverDim != null && coverDim is Map<String, dynamic>
              ? ImageDimensions.fromJson(coverDim)
              : null,
      youtubeChannelUrl: json['youtube_channel_url'] as String? ?? '',
      youtubeChannelId: canonicalUcId(
        json['youtube_channel_id'] as String?,
        json['youtube_channel_url'] as String?,
      ),
      youtubePlaylistUrl: json['youtube_playlist_url'] as String?,
      followerCount: json['follower_count'] as int?,
      videoCount: json['video_count'] as int? ?? 0,
      totalDurationSeconds: json['total_duration_seconds'] as int? ?? 0,
      avgMagisteriumScore: domainScoreFromJson(json['avg_magisterium_score']),
      latestVideo: lv != null && lv is Map<String, dynamic>
          ? LatestVideo.fromJson(lv)
          : null,
    );
  }
}

class ImageDimensions {
  final int width;
  final int height;

  const ImageDimensions({required this.width, required this.height});

  double get aspectRatio => height > 0 ? width / height : 1;

  factory ImageDimensions.fromJson(Map<String, dynamic> json) {
    return ImageDimensions(
      width: json['width'] as int? ?? 0,
      height: json['height'] as int? ?? 0,
    );
  }
}

class LatestVideo {
  final String id;
  final String date;
  final String title;

  const LatestVideo({
    required this.id,
    required this.date,
    required this.title,
  });

  factory LatestVideo.fromJson(Map<String, dynamic> json) {
    return LatestVideo(
      id: json['id'] as String? ?? '',
      date: json['date'] as String? ?? '',
      title: json['title'] as String? ?? '',
    );
  }
}
