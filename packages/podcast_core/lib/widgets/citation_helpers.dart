import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../l10n/app_localizations.dart';
import '../models/magisterium_data.dart';
import '../models/magisterium_full_data.dart';
import '../services/open_url.dart';
import '../theme/markdown_brand.dart';

/// Cleans cited_text: strips markdown footnote refs, dividers, excess whitespace.
String cleanCitedText(String raw) {
  return raw
      .replaceAll(RegExp(r'\[\^\d+\]:?\s*[^\n]*'), '')
      .replaceAll(RegExp(r'---\s*'), '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// Čitljiva oznaka reference: pipeline piše goli broj paragrafa („74"),
/// stranicu Acta Apostolicae Sedis („page65") ili odlomak („para-3"); sve
/// ostalo (naslovi poglavlja, rimski brojevi) ide kako je stiglo.
String citationRefLabel(String ref, AppLocalizations l) {
  final r = ref.trim();
  if (RegExp(r'^\d+$').hasMatch(r)) return l.magisteriumRefNumber(r);
  final page = RegExp(r'^page[\s-]?(\d+)$', caseSensitive: false).firstMatch(r);
  if (page != null) return l.magisteriumRefPage(page.group(1)!);
  final para = RegExp(r'^para-(\d+)$', caseSensitive: false).firstMatch(r);
  if (para != null) return l.magisteriumRefNumber(para.group(1)!);
  return r;
}

/// Tap na citat: sheet samo kad ima što pokazati. MCP pipeline citate sprema
/// BEZ `cited_text` (izmjereno 19.10.2026.: 394 od 394 u 6 epizoda), pa bi
/// sheet bio prazan naslov s gumbom — tada odmah otvaramo izvor.
void openCitation(BuildContext context, MagisteriumCitation citation) {
  if (cleanCitedText(citation.citedText).isNotEmpty) {
    showCitationSheet(context, citation);
  } else if (citation.sourceUrl.isNotEmpty) {
    openUrl(citation.sourceUrl);
  }
}

/// Converts MagisteriumFullCitation to MagisteriumCitation for reuse.
MagisteriumCitation _toMagCitation(MagisteriumFullCitation c) =>
    MagisteriumCitation(
      citedText: c.citedText,
      documentTitle: c.documentTitle,
      documentAuthor: c.documentAuthor ?? '',
      documentYear: c.documentYear ?? '',
      documentReference: c.documentReference ?? '',
      sourceUrl: c.sourceUrl ?? '',
    );

/// Shows a bottom sheet for MagisteriumFullCitation.
void showFullCitationSheet(
  BuildContext context,
  MagisteriumFullCitation citation,
) => openCitation(context, _toMagCitation(citation));

/// Shows a bottom sheet with full citation details and link to source.
void showCitationSheet(BuildContext context, MagisteriumCitation citation) {
  final theme = Theme.of(context);
  final l = AppLocalizations.of(context);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final cleaned = cleanCitedText(citation.citedText);
      final ref = [
        if (citation.documentReference.isNotEmpty)
          citationRefLabel(citation.documentReference, l),
        if (citation.documentYear.isNotEmpty) citation.documentYear,
      ].join(' — ');

      return DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, scrollController) {
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withAlpha(60),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Document title
              Row(
                children: [
                  Icon(
                    Icons.menu_book,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      citation.documentTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              if (citation.documentAuthor.isNotEmpty &&
                  citation.documentAuthor != citation.documentTitle)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 28),
                  child: Text(
                    citation.documentAuthor,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (ref.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 28),
                  child: Text(
                    ref,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              // Cited text — markdown rendered
              if (cleaned.isEmpty)
                Text(
                  l.magisteriumNoQuotedText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withAlpha(
                      120,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border(
                      left: BorderSide(
                        color: theme.colorScheme.primary.withAlpha(100),
                        width: 3,
                      ),
                    ),
                  ),
                  child: MarkdownBody(
                    data: cleaned,
                    styleSheet: MarkdownStyleSheet.fromTheme(theme)
                        .copyWith(
                          p: theme.textTheme.bodyMedium?.copyWith(height: 1.7),
                          em: theme.textTheme.bodyMedium?.copyWith(
                            fontStyle: FontStyle.italic,
                            height: 1.7,
                          ),
                          strong: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            height: 1.7,
                          ),
                        )
                        .withBrandBlockquote(theme),
                    onTapLink: (text, href, title) {
                      if (href != null) openUrl(href);
                    },
                  ),
                ),
              // Open on Magisterium button
              if (citation.sourceUrl.isNotEmpty) ...[
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: () => openUrl(citation.sourceUrl),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(l.magisteriumOpenOnMagisterium),
                ),
              ],
            ],
          );
        },
      );
    },
  );
}
