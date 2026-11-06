import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/cached_thumbnail.dart';
import '../../widgets/prefetch_on_intent.dart';
import '../../widgets/magisterium_section.dart';
import '../../widgets/share_context_menu.dart';

/// Compact episode card za horizontalne railove ("Najnovije", "Nastavi
/// slusati"). Vertikalan layout: 16:9 cover gore, tekst dolje.
class EpisodeRailCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? thumbnailUrl;
  final String? dateLabel;
  final int? magisteriumScore;

  /// Mala oznaka u gornjem-lijevom kutu cover-a (npr. "U obradi" za tek
  /// pristigle, još neobrađene epizode). Null = bez oznake.
  final String? statusBadge;

  /// Progress 0.0–1.0 — pokazuje se kao tanka bar na dnu cover-a.
  /// Null = nema progresa (npr. "Najnovije" rail).
  final double? progress;

  final VoidCallback onTap;
  final double width;

  /// Poveznica za "Kopiraj poveznicu" u context menu-u (desni-klik / long-press).
  /// Null = bez context menu-a.
  ///
  /// Lijeno: jezik linka ovisi o preferenciji koja se može promijeniti dok
  /// kartica stoji živa ispod u navigacijskom stogu.
  final String Function()? shareUrl;

  /// Epizoda koju kartica otvara. Kad je zadana, hover ili dodir je
  /// predučitavaju ([EpisodePrefetch.intent]) — klik onda ne čeka mrežu.
  final String? prefetchEpisodeId;

  /// Tap na [subtitle] (ime kanala) — npr. `/c/<slug>` za kartice iz
  /// kataloga. `null` = podnaslov je samo tekst, kao do sada.
  final VoidCallback? onSubtitleTap;

  const EpisodeRailCard({
    super.key,
    required this.title,
    required this.onTap,
    required this.width,
    this.subtitle,
    this.thumbnailUrl,
    this.dateLabel,
    this.magisteriumScore,
    this.statusBadge,
    this.progress,
    this.shareUrl,
    this.prefetchEpisodeId,
    this.onSubtitleTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final card = SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover s ProgressIndicator overlay
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _coverImage(theme),
                      if (statusBadge != null)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: _statusPill(theme),
                        ),
                      if (magisteriumScore != null)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: _scorePill(theme),
                        ),
                      if (progress != null && progress! > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: _progressBar(theme),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (subtitle != null) ...[
                _subtitle(theme),
                const SizedBox(height: 4),
              ],
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (dateLabel != null) ...[
                const SizedBox(height: 4),
                Text(
                  dateLabel!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    final id = prefetchEpisodeId;
    final withIntent = id == null
        ? card
        : PrefetchOnIntent(episodeId: id, child: card);
    if (shareUrl == null) return withIntent;
    return ShareContextMenu.lazy(urlBuilder: shareUrl!, child: withIntent);
  }

  Widget _coverImage(ThemeData theme) {
    if (thumbnailUrl == null) return _coverFallback(theme);
    // `width` je stvarna širina kartice → CachedThumbnail iz nje bira WebP
    // varijantu (180/220 dp × dpr → thumb-640 umjesto 830 KB PNG-a).
    return CachedThumbnail(
      url: thumbnailUrl!,
      width: width,
      fit: BoxFit.cover,
      errorIcon: Icons.ondemand_video,
      errorIconSize: 28,
    );
  }

  Widget _subtitle(ThemeData theme) {
    final text = Text(
      subtitle!.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final tap = onSubtitleTap;
    if (tap == null) return text;
    // Unutarnji InkWell pobjeđuje vanjski (cijela kartica = epizoda), pa tap
    // na ime kanala vodi na kanal, a ostatak kartice na epizodu.
    return InkWell(
      onTap: tap,
      borderRadius: BorderRadius.circular(4),
      child: text,
    );
  }

  Widget _coverFallback(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Center(
        child: Icon(
          Icons.ondemand_video,
          size: 28,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _progressBar(ThemeData theme) {
    return Container(
      height: 3,
      color: Colors.black.withValues(alpha: 0.5),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress!.clamp(0.0, 1.0),
        child: Container(color: AppTheme.brandAccent),
      ),
    );
  }

  Widget _statusPill(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.tertiary.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hourglass_top, size: 10, color: theme.colorScheme.tertiary),
          const SizedBox(width: 3),
          Text(
            statusBadge!,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _scorePill(ThemeData theme) {
    final color = MagisteriumSection.scoreColor(magisteriumScore);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.church, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            '$magisteriumScore',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
