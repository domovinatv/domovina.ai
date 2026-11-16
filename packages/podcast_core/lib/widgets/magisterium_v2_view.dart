import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../models/magisterium_full_v2_data.dart';
import '../services/episode_language.dart';
import '../theme/markdown_brand.dart';
import 'citation_helpers.dart' show magisteriumLang, withMagisteriumLang;

/// Renders MagisteriumFullV2Data: score badge + evaluation markdown + lista
/// citata s expansion tiles.
///
/// Vraca Column — caller odlucuje o scrollingu (SingleChildScrollView ili
/// SliverToBoxAdapter u CustomScrollView).
class MagisteriumV2View extends StatelessWidget {
  final MagisteriumFullV2Data data;
  final EdgeInsetsGeometry padding;

  const MagisteriumV2View({
    super.key,
    required this.data,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final lang = EpisodeLanguageScope.of(context);
    final interpretation =
        pickLang(lang, data.scoreInterpretation, data.scoreInterpretationEn);
    final evaluation = pickLang(lang, data.evaluation, data.evaluationEn);
    final sourcesLabel = l.magisteriumSourcesTitle;
    final sourcesSubtitle =
        l.magisteriumCitationsFromChurchDocs(data.citations.length);

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        _ScoreBadge(
          score: data.overallScore,
          interpretation: interpretation,
          theme: theme,
        ),
        const SizedBox(height: 20),
        MarkdownBody(
          data: evaluation,
          selectable: true,
          styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
            p: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
            h1: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            h2: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            h3: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            listBullet: theme.textTheme.bodyMedium,
          ).withBrandBlockquote(theme),
        ),
        if (data.citations.isNotEmpty) ...[
          const SizedBox(height: 24),
          _SectionTitle(icon: Icons.library_books, label: sourcesLabel),
          const SizedBox(height: 8),
          Text(
            sourcesSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          ...data.citations.asMap().entries.map(
                (e) => _CitationCard(index: e.key + 1, citation: e.value),
              ),
        ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  final int score;
  final String interpretation;
  final ThemeData theme;

  const _ScoreBadge({
    required this.score,
    required this.interpretation,
    required this.theme,
  });

  Color _colorForScore(int s) {
    if (s >= 80) return const Color(0xFF2E7D32);
    if (s >= 60) return const Color(0xFF558B2F);
    if (s >= 40) return const Color(0xFFF9A825);
    if (s >= 20) return const Color(0xFFE65100);
    return const Color(0xFFC62828);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final color = _colorForScore(score);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$score',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.magisteriumScoreCaption,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  interpretation,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CitationCard extends StatelessWidget {
  final int index;
  final MagisteriumFullV2Citation citation;

  const _CitationCard({required this.index, required this.citation});

  Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.tryParse(withMagisteriumLang(url, magisteriumLang(context)));
    if (uri == null) return;
    // Prvo probaj deep-link app (npr. Magisterium AI ima intent filter na
    // magisterium.com URL-ove — otvori se tamo umjesto browsera).
    // Ako nema registrirane non-browser app, idi na external browser (Chrome).
    // Zadnji fallback je inAppBrowserView (Chrome Custom Tab) s vidljivim X
    // close buttonom — ako sve ostalo faila ostaje unutar app-a.
    for (final mode in const [
      LaunchMode.externalNonBrowserApplication,
      LaunchMode.externalApplication,
      LaunchMode.inAppBrowserView,
    ]) {
      try {
        final ok = await launchUrl(uri, mode: mode);
        if (ok) return;
      } catch (_) {
        // probaj sljedeci mode
      }
    }
    debugPrint('launchUrl: nijedan mode ne moze otvoriti $uri');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final subtitle = [
      if (citation.documentAuthor != null && citation.documentAuthor!.isNotEmpty)
        citation.documentAuthor!,
      if (citation.documentYear != null && citation.documentYear!.isNotEmpty)
        citation.documentYear!,
      if (citation.documentReference != null &&
          citation.documentReference!.isNotEmpty)
        citation.documentReference!,
    ].join(' • ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$index',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          title: Text(
            citation.documentTitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: subtitle.isNotEmpty
              ? Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    citation.citedText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      height: 1.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (citation.sourceUrl != null &&
                      citation.sourceUrl!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _openUrl(context, citation.sourceUrl!),
                      icon: const Icon(Icons.open_in_new, size: 14),
                      label: Text(l.commonOpenSource),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionTitle({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}
