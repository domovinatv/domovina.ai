import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/catalog_card.dart';
import '../../widgets/magisterium_section.dart';

/// Meta redak epizode iz kataloga: sat objave na YouTubeu, trajanje i
/// Magisterium ocjena. Dio koji katalog ne zna (sat kod starijeg uvoza,
/// ocjena kod Tier 2) se izostavlja; bez ičega se ne crta ništa.
///
/// Sat je u lokalnoj zoni uređaja; dan na `/dani/` je Europe/Zagreb, pa se
/// za korisnike u Hrvatskoj poklapaju.
class CatalogCardMeta extends StatelessWidget {
  final CatalogCard card;

  const CatalogCardMeta({super.key, required this.card});

  static bool hasAny(CatalogCard c) =>
      c.publishedAt != null ||
      c.durationDisplay != null ||
      c.magisteriumScore != null;

  @override
  Widget build(BuildContext context) {
    if (!hasAny(card)) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final published = card.publishedAt;
    final duration = card.durationDisplay;
    final score = card.magisteriumScore;
    final time = published == null
        ? null
        : DateFormat.Hm(
            Localizations.maybeLocaleOf(context)?.languageCode ?? 'hr',
          ).format(published.toLocal());
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (time != null)
          _chip(theme, Icons.schedule, time, l.catalogMetaPublished(time)),
        if (duration != null)
          _chip(
            theme,
            Icons.timelapse,
            duration,
            l.catalogMetaDuration(duration),
          ),
        if (score != null) _score(score, l.catalogMetaScore(score)),
      ],
    );
  }

  Widget _chip(ThemeData theme, IconData icon, String text, String tooltip) {
    final color = theme.colorScheme.onSurfaceVariant;
    return Tooltip(
      message: tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text(text, style: theme.textTheme.labelSmall?.copyWith(color: color)),
        ],
      ),
    );
  }

  /// Ista pilula kao u `videoMeta` na `/c/<slug>`.
  Widget _score(int score, String tooltip) {
    final color = MagisteriumSection.scoreColor(score);
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.church, size: 11, color: color),
            const SizedBox(width: 3),
            Text(
              '$score',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
