import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/markdown_brand.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/magisterium_data.dart';
import '../services/episode_language.dart';
import '../services/open_url.dart';
import 'magisterium_section.dart';
import 'citation_helpers.dart';

/// Standalone chronological read-through of the full Magisterium AI analysis.
/// Presents all theological assessments, enrichments, and citations as a
/// continuous "article" — branded as Magisterium AI content.
class MagisteriumArticleSection extends StatelessWidget {
  final MagisteriumData magisterium;

  /// Optional keys per screenshot_timestamp — used by parent for scroll-sync.
  final Map<String, GlobalKey>? sectionKeys;

  const MagisteriumArticleSection({
    super.key,
    required this.magisterium,
    this.sectionKeys,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final mag = magisterium;
    final overallColor = MagisteriumSection.scoreColor(mag.overallScore);
    final headerTitle = l.magisteriumArticleHeaderTitle;
    final headerSubtitle = l.magisteriumArticleHeaderSubtitle;
    final footerText = l.magisteriumAnalysisGeneratedBy(
        mag.model, mag.generatedAt.toIso8601String().substring(0, 10));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header / branding ──────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  overallColor.withAlpha(18),
                  overallColor.withAlpha(6),
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              border: Border.all(color: overallColor.withAlpha(50)),
            ),
            child: Row(
              children: [
                Icon(Icons.church, size: 22, color: overallColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headerTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        headerSubtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Overall score badge
                if (mag.overallScore != null)
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: overallColor.withAlpha(25),
                      border: Border.all(color: overallColor, width: 2.5),
                    ),
                    child: Center(
                      child: Text(
                        '${mag.overallScore}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: overallColor,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Iteration blocks ──────────────────────────────────
          ...mag.iterations.map((iter) => _IterationArticle(
                iteration: iter,
                sectionKeys: sectionKeys,
                isLast: iter == mag.iterations.last,
              )),

          // ── Footer attribution ────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(12),
              ),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withAlpha(80),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome,
                    size: 14, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    footerText,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
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

// ─────────────────────────────────────────────────────────────────────────────
// One iteration block — theme header + all section analyses
// ─────────────────────────────────────────────────────────────────────────────

class _IterationArticle extends StatelessWidget {
  final MagisteriumIteration iteration;
  final Map<String, GlobalKey>? sectionKeys;
  final bool isLast;

  const _IterationArticle({
    required this.iteration,
    this.sectionKeys,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = MagisteriumSection.scoreColor(iteration.iterationScore);
    final lang = EpisodeLanguageScope.of(context);
    final themeText = pickLang(lang, iteration.theme, iteration.themeEn);

    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80),
          ),
          right: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Iteration theme header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(100),
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withAlpha(60),
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppTheme.brandPrimary,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.fromBorderSide(
                      AppTheme.brandRim(theme.brightness),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '${iteration.iterationNumber}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    themeText,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                if (iteration.iterationScore != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color.withAlpha(80)),
                    ),
                    child: Text(
                      '${iteration.iterationScore}/100',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Section analyses
          ...iteration.sections.asMap().entries.map((entry) {
            final idx = entry.key;
            final sec = entry.value;
            if (sec.magisterium == null || sec.magisterium!.assessment.isEmpty) {
              return const SizedBox.shrink();
            }
            return MagisteriumSectionAnalysis(
              key: sectionKeys?[sec.screenshotTimestamp],
              timestamp: sec.screenshotTimestamp,
              subtitle: sec.subtitle,
              subtitleEn: sec.subtitleEn,
              mag: sec.magisterium!,
              showDivider:
                  idx < iteration.sections.length - 1 || !isLast,
            );
          }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// One section's theological analysis
// ─────────────────────────────────────────────────────────────────────────────

/// Jedna sekcija teoloske analize (timestamp + score + subtitle + procjena +
/// obogacivanje + zabrinutosti + citati). Samostalno upravlja expand stanjem
/// citata. Koristi se i u [MagisteriumArticleSection] (stupac) i u paralelnom
/// desktop layoutu (ParallelArticleView) gdje [padding] = zero da se timestamp
/// poravna s clankom u istom redu.
class MagisteriumSectionAnalysis extends StatefulWidget {
  final String timestamp;
  final String subtitle;
  final String? subtitleEn;
  final SectionMagisterium mag;
  final bool showDivider;
  final EdgeInsetsGeometry padding;

  const MagisteriumSectionAnalysis({
    super.key,
    required this.timestamp,
    required this.subtitle,
    this.subtitleEn,
    required this.mag,
    this.showDivider = true,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 0),
  });

  @override
  State<MagisteriumSectionAnalysis> createState() =>
      _MagisteriumSectionAnalysisState();
}

class _MagisteriumSectionAnalysisState
    extends State<MagisteriumSectionAnalysis> {
  bool _citationsExpanded = true; // izvori zadano rašireni

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final mag = widget.mag;
    final color = MagisteriumSection.scoreColor(mag.score);
    final lang = EpisodeLanguageScope.of(context);
    final subtitleText = pickLang(lang, widget.subtitle, widget.subtitleEn);
    final assessmentText = pickLang(lang, mag.assessment, mag.assessmentEn);
    final enrichmentText = pickLang(lang, mag.enrichment, mag.enrichmentEn);
    final concernsList = pickLangList(lang, mag.concerns, mag.concernsEn);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: widget.padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section header: timestamp + score + subtitle
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Timestamp
                  if (widget.timestamp.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withAlpha(20),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: theme.colorScheme.primary.withAlpha(60),
                        ),
                      ),
                      child: Text(
                        widget.timestamp,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ),
                  // Score badge
                  if (mag.score != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withAlpha(25),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: color.withAlpha(80)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.church, size: 11, color: color),
                          const SizedBox(width: 3),
                          Text(
                            '${mag.score}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      subtitleText,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Assessment — markdown
              MarkdownBody(
                data: assessmentText,
                styleSheet: MarkdownStyleSheet.fromTheme(theme)
                    .copyWith(
                      p: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                    )
                    .withBrandBlockquote(theme),
                onTapLink: (text, href, title) {
                  if (href != null) openUrl(href);
                },
              ),

              // Enrichment — markdown
              if (enrichmentText.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withAlpha(10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border(
                      left: BorderSide(color: color.withAlpha(100), width: 3),
                    ),
                  ),
                  child: MarkdownBody(
                    data: enrichmentText,
                    styleSheet: MarkdownStyleSheet.fromTheme(theme)
                        .copyWith(
                          p: theme.textTheme.bodySmall?.copyWith(
                            height: 1.6,
                            fontStyle: FontStyle.italic,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                        .withBrandBlockquote(theme),
                    onTapLink: (text, href, title) {
                      if (href != null) openUrl(href);
                    },
                  ),
                ),
              ],

              // Concerns
              if (concernsList.isNotEmpty) ...[
                const SizedBox(height: 10),
                ...concernsList.map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(Icons.warning_amber,
                                size: 15, color: Color(0xFFEF6C00)),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              c,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFFEF6C00),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],

              // Citations
              if (mag.citations.isNotEmpty) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => setState(
                      () => _citationsExpanded = !_citationsExpanded),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          _citationsExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          l.magisteriumSourcesFromChurchDocs(
                              mag.citations.length),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_citationsExpanded)
                  ...mag.citations.map((cit) => _FullCitation(citation: cit)),
              ],
            ],
          ),
        ),
        if (widget.showDivider)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Divider(
              height: 1,
              color: theme.colorScheme.outlineVariant.withAlpha(60),
            ),
          ),
        if (!widget.showDivider) const SizedBox(height: 16),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full citation card — slightly more generous than the inline version
// ─────────────────────────────────────────────────────────────────────────────

class _FullCitation extends StatelessWidget {
  final MagisteriumCitation citation;

  const _FullCitation({required this.citation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cleaned = cleanCitedText(citation.citedText);
    final displayText = cleaned.length > 500
        ? '${cleaned.substring(0, 500)}...'
        : cleaned;

    final l = AppLocalizations.of(context);
    final parts = <String>[
      citation.documentTitle,
      if (citation.documentReference.isNotEmpty)
        citationRefLabel(citation.documentReference, l),
      if (citation.documentYear.isNotEmpty) citation.documentYear,
    ];

    return GestureDetector(
      onTap: () => openCitation(context, citation),
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(100),
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(
              color: theme.colorScheme.primary.withAlpha(80),
              width: 3,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.menu_book,
                    size: 14, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    parts.join(' — '),
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                Icon(Icons.open_in_new,
                    size: 12, color: theme.colorScheme.primary),
              ],
            ),
            if (citation.documentAuthor.isNotEmpty &&
                citation.documentAuthor != citation.documentTitle)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 20),
                child: Text(
                  citation.documentAuthor,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (displayText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                displayText,
                style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.6,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ] else if (citation.sourceUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 20),
                child: Text(
                  l.magisteriumSourceNotCroatian,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
