import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../models/podcast_info.dart';
import '../models/podcast_summary.dart';
import '../services/cdn_config.dart';
import '../services/episode_language.dart';
import 'cached_thumbnail.dart';

class HeroSection extends StatefulWidget {
  final PodcastInfo info;
  final String youtubeId;

  /// Ako prosljeden, preferira lokalizirani title (HR ili EN) iz pipeline-a
  /// nad YouTube `info.title`. Bez summary-a (npr. basic layout dok AI nije
  /// gotov) fallback je `info.title`.
  final SummaryContent? summary;

  const HeroSection({
    super.key,
    required this.info,
    required this.youtubeId,
    this.summary,
  });

  @override
  State<HeroSection> createState() => _HeroSectionState();
}

class _HeroSectionState extends State<HeroSection> {
  /// True kad hero thumbnail ne postoji (404) — npr. audio-only epizode nemaju
  /// `thumbnail.png`. Tada sakrivamo cijeli image blok (umjesto broken-image
  /// placeholdera); cover-art audio epizode ionako pokazuje player panel.
  bool _thumbFailed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = widget.info;
    final uploadDt = info.uploadDateTime;
    final dateStr = '${uploadDt.day}.${uploadDt.month}.${uploadDt.year}.';
    final lang = EpisodeLanguageScope.of(context);

    // Prefer lokalizirani naslov iz summary-a (HR ili EN), fallback YouTube original.
    String displayTitle = info.title;
    final s = widget.summary;
    if (s != null) {
      if (lang == EpisodeLanguage.en) {
        if (s.titleEn != null && s.titleEn!.isNotEmpty) {
          displayTitle = s.titleEn!;
        } else if (s.titleHr.isNotEmpty) {
          displayTitle = s.titleHr;
        }
      } else if (s.titleHr.isNotEmpty) {
        displayTitle = s.titleHr;
      }
    }

    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_thumbFailed)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: CachedThumbnail(
                url: CdnConfig.thumbnailUrl(widget.youtubeId),
                fit: BoxFit.cover,
                // Nema thumbnaila (ni varijante ni PNG-a) → kolabiraj blok.
                // Post-frame jer ovo mijenja layout roditelja.
                onFailed: () {
                  if (!_thumbFailed) setState(() => _thumbFailed = true);
                },
                errorFallbackBuilder: (_) => const SizedBox.shrink(),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Channel chip
                Chip(
                  label: Text(
                    info.channel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  backgroundColor: AppTheme.brandPrimary,
                  side: AppTheme.brandRim(theme.brightness),
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: 12),

                // Title
                Text(
                  displayTitle,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 16),

                // Stats row
                Wrap(
                  spacing: 20,
                  runSpacing: 8,
                  children: [
                    _Stat(icon: Icons.calendar_today_outlined, label: dateStr),
                    _Stat(
                      icon: Icons.timer_outlined,
                      label: info.durationString.isNotEmpty
                          ? info.durationString
                          : _formatDuration(info.duration),
                    ),
                    // Varijanta epizode (`_variant_of` u info.json): ista snimka,
                    // drugi prolaz pipelinea. Diskretna oznaka da se ne miješa
                    // s izvornom epizodom.
                    if (info.isVariant) _VariantBadge(info: info),
                    // YouTube view/like/comment counts hidden — snapshot data, not live-synced.
                    // Re-enable once we have our own internal statistics.
                    // _Stat(
                    //   icon: Icons.visibility_outlined,
                    //   label: _formatCount(info.viewCount),
                    // ),
                    // _Stat(
                    //   icon: Icons.thumb_up_outlined,
                    //   label: _formatCount(info.likeCount),
                    // ),
                    // if (info.commentCount != null)
                    //   _Stat(
                    //     icon: Icons.comment_outlined,
                    //     label: _formatCount(info.commentCount!),
                    //   ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h}h ${m}min';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  // ignore: unused_element
  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }
}

/// Diskretna oznaka varijante: „Varijanta 2: Canary + pyannote → Opus".
/// Broj ide kroz ARB (chrome), opis je CDN tekst i ne lokalizira se.
class _VariantBadge extends StatelessWidget {
  final PodcastInfo info;

  const _VariantBadge({required this.info});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final n = info.variantNumber;
    final prefix = n != null ? l.episodeVariantNumbered(n) : l.episodeVariant;
    final label = info.variantLabel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        label != null ? '$prefix: $label' : prefix,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Stat({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
