import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../l10n/app_localizations.dart';
import '../models/magisterium_data.dart';
import '../models/magisterium_full_data.dart';
import '../services/locale_service.dart';
import '../services/open_url.dart';
import '../theme/markdown_brand.dart';
import 'citation_helpers.dart';
import 'magisterium_section.dart';
import 'magisterium_article_section.dart';

/// Generic tab entry for MagisteriumPanel — supports different content types.
class _TabEntry {
  final String label;
  final IconData icon;
  final Color? badgeColor;
  final String? badgeText;
  final Widget Function(bool fillParent, Map<String, GlobalKey>? sectionKeys,
      int selectedIndex, int myIndex) builder;

  const _TabEntry({
    required this.label,
    required this.icon,
    this.badgeColor,
    this.badgeText,
    required this.builder,
  });
}

/// Tabbed panel showing Magisterium AI analysis variants, full evaluation,
/// and prompt. Shows tabs only when multiple entries are available.
///
/// [fillParent]: true for column mode (fills Expanded, internal scroll),
///               false for inline mode (no internal scroll, lives in parent scroll).
class MagisteriumPanel extends StatefulWidget {
  final List<(String, MagisteriumData)> variants;
  final MagisteriumFullData? magisteriumFull;
  final String? magisteriumFullPrompt;
  final bool fillParent;
  final Map<String, GlobalKey>? sectionKeys;

  const MagisteriumPanel({
    super.key,
    required this.variants,
    this.magisteriumFull,
    this.magisteriumFullPrompt,
    this.fillParent = false,
    this.sectionKeys,
  });

  @override
  State<MagisteriumPanel> createState() => _MagisteriumPanelState();
}

class _MagisteriumPanelState extends State<MagisteriumPanel>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  int _selectedIndex = 0;

  List<_TabEntry> _buildTabs(AppLocalizations l) {
    final tabs = <_TabEntry>[];

    // When Evaluacija (full) exists, it replaces old per-section/per-block tabs.
    // Old variants only shown as fallback when no full evaluation available.
    if (widget.magisteriumFull != null) {
      final full = widget.magisteriumFull!;
      final color = MagisteriumSection.scoreColor(full.overallScore);
      tabs.add(_TabEntry(
        label: l.magisteriumTabEvaluation,
        icon: Icons.auto_awesome,
        badgeColor: color,
        badgeText: '${full.overallScore}',
        builder: (_, _, _, _) =>
            _MagisteriumFullContent(data: full),
      ));
    } else {
      for (final (label, data) in widget.variants) {
        final color = MagisteriumSection.scoreColor(data.overallScore);
        tabs.add(_TabEntry(
          label: label,
          icon: Icons.church,
          badgeColor: color,
          badgeText: data.overallScore != null ? '${data.overallScore}' : '?',
          builder: (fill, keys, sel, my) => _VariantContent(
            magisterium: data,
            sectionKeys: sel == my ? keys : null,
          ),
        ));
      }
    }

    // Magisterium Full prompt (raw markdown)
    if (widget.magisteriumFullPrompt != null) {
      tabs.add(_TabEntry(
        label: l.magisteriumTabPrompt,
        icon: Icons.code,
        builder: (_, _, _, _) =>
            _MarkdownContent(markdown: widget.magisteriumFullPrompt!),
      ));
    }

    return tabs;
  }

  @override
  void initState() {
    super.initState();
    _initTabController();
  }

  void _initTabController() {
    // initState nema Localizations scope — treba nam samo broj tabova,
    // pa je globalni appStrings ovdje siguran (labeli se ne renderiraju).
    final count = _buildTabs(appStrings).length;
    if (count > 1) {
      _tabController = TabController(length: count, vsync: this)
        ..addListener(() {
          if (!_tabController!.indexIsChanging) {
            setState(() => _selectedIndex = _tabController!.index);
          }
        });
    }
  }

  @override
  void didUpdateWidget(MagisteriumPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldCount = oldWidget.variants.length +
        (oldWidget.magisteriumFull != null ? 1 : 0) +
        (oldWidget.magisteriumFullPrompt != null ? 1 : 0);
    final newCount = widget.variants.length +
        (widget.magisteriumFull != null ? 1 : 0) +
        (widget.magisteriumFullPrompt != null ? 1 : 0);
    if (oldCount != newCount) {
      _tabController?.dispose();
      _selectedIndex = 0;
      _initTabController();
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _buildTabs(AppLocalizations.of(context));
    if (tabs.isEmpty) return const SizedBox.shrink();

    if (tabs.length == 1) {
      final content = tabs.first
          .builder(widget.fillParent, widget.sectionKeys, 0, 0);
      if (widget.fillParent) {
        return ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 32),
          children: [content],
        );
      }
      return content;
    }

    // Tabbed mode
    final tabBar = _buildTabBar(context, tabs);

    if (widget.fillParent) {
      return Column(
        children: [
          tabBar,
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                for (int i = 0; i < tabs.length; i++)
                  ListView(
                    padding: const EdgeInsets.only(top: 8, bottom: 32),
                    children: [
                      tabs[i].builder(
                          true, widget.sectionKeys, _selectedIndex, i),
                    ],
                  ),
              ],
            ),
          ),
        ],
      );
    }

    // Inline mode
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tabBar,
        tabs[_selectedIndex]
            .builder(false, widget.sectionKeys, _selectedIndex, _selectedIndex),
      ],
    );
  }

  Widget _buildTabBar(BuildContext context, List<_TabEntry> tabs) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80),
          ),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: tabs.length > 3,
        tabs: tabs.map((t) {
          return Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(t.icon, size: 14, color: t.badgeColor),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(t.label, overflow: TextOverflow.ellipsis),
                ),
                if (t.badgeText != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: (t.badgeColor ?? theme.colorScheme.primary)
                          .withAlpha(25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: (t.badgeColor ?? theme.colorScheme.primary)
                            .withAlpha(80),
                      ),
                    ),
                    child: Text(
                      t.badgeText!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: t.badgeColor ?? theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
        labelColor: theme.colorScheme.primary,
        unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
        indicatorColor: theme.colorScheme.primary,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerHeight: 0,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab content widgets
// ---------------------------------------------------------------------------

/// Score card + chronological article for per-section/per-block variant.
class _VariantContent extends StatelessWidget {
  final MagisteriumData magisterium;
  final Map<String, GlobalKey>? sectionKeys;

  const _VariantContent({
    required this.magisterium,
    this.sectionKeys,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        MagisteriumSection(magisterium: magisterium),
        const SizedBox(height: 4),
        MagisteriumArticleSection(
          magisterium: magisterium,
          sectionKeys: sectionKeys,
        ),
      ],
    );
  }
}

/// Full Magisterium AI evaluation — premium layout with gradient header,
/// markdown evaluation, and expandable clickable citations.
class _MagisteriumFullContent extends StatefulWidget {
  final MagisteriumFullData data;

  const _MagisteriumFullContent({required this.data});

  @override
  State<_MagisteriumFullContent> createState() =>
      _MagisteriumFullContentState();
}

class _MagisteriumFullContentState extends State<_MagisteriumFullContent> {
  bool _citationsExpanded = true; // izvori zadano rašireni

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final data = widget.data;
    final color = MagisteriumSection.scoreColor(data.overallScore);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Gradient header — matches MagisteriumArticleSection style
        Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withAlpha(18),
                color.withAlpha(6),
              ],
            ),
            border: Border.all(color: color.withAlpha(40)),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 22, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.magisteriumFullHeaderTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l.magisteriumModelCitations(
                          data.model ?? 'magisterium-1', data.citations.length),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              // Score circle
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withAlpha(30),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withAlpha(100), width: 3),
                ),
                child: Center(
                  child: Text(
                    '${data.overallScore}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Score interpretation badge
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withAlpha(15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withAlpha(50)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.church, size: 14, color: color),
                const SizedBox(width: 6),
                // Flexible: na uskom stupcu (mobitel u landscapeu) tumačenje
                // se prelama umjesto da probije rub bedža.
                Flexible(
                  child: Text(
                    data.scoreInterpretation,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Evaluation markdown
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: MarkdownBody(
            data: data.evaluation,
            selectable: true,
            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
              p: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
              h1: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
              h2: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold, height: 2.0),
              h3: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
              blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              blockquoteDecoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: color.withAlpha(120), width: 3),
                ),
                color: color.withAlpha(10),
              ),
              listBullet: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
              listBulletPadding: const EdgeInsets.only(right: 8),
            ),
            onTapLink: (text, href, title) {
              if (href != null) openUrl(href);
            },
          ),
        ),
        const SizedBox(height: 16),
        // Citations — expandable section
        if (data.citations.isNotEmpty)
          _buildCitationsSection(theme, data, color),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildCitationsSection(
      ThemeData theme, MagisteriumFullData data, Color color) {
    final l = AppLocalizations.of(context);
    final count = data.citations.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          // Toggle header
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () =>
                setState(() => _citationsExpanded = !_citationsExpanded),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.menu_book, size: 16, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.magisteriumSourcesFromChurchDocs(count),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                  Icon(
                    _citationsExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          // Citation cards
          if (_citationsExpanded)
            ...data.citations.asMap().entries.map((entry) {
              final i = entry.key;
              final c = entry.value;
              return _FullCitationCard(
                index: i + 1,
                citation: c,
                accentColor: color,
              );
            }),
        ],
      ),
    );
  }
}

/// Single citation card — clickable, opens bottom sheet with full text.
class _FullCitationCard extends StatelessWidget {
  final int index;
  final MagisteriumFullCitation citation;
  final Color accentColor;

  const _FullCitationCard({
    required this.index,
    required this.citation,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final authorYear = [
      citation.documentAuthor ?? '',
      if ((citation.documentReference ?? '').isNotEmpty)
        citationRefLabel(citation.documentReference!, l),
      citation.documentYear ?? '',
    ].where((s) => s.isNotEmpty).join(', ');

    return GestureDetector(
      onTap: () => showFullCitationSheet(context, citation),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
          border: Border(
            left: BorderSide(
              color: accentColor.withAlpha(80),
              width: 3,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Footnote number
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: accentColor.withAlpha(20),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  '$index',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    citation.documentTitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (authorYear.isNotEmpty)
                    Text(
                      authorYear,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            if (citation.sourceUrl != null &&
                citation.sourceUrl!.isNotEmpty)
              Icon(Icons.open_in_new,
                  size: 14, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Raw markdown content — used for prompt display.
class _MarkdownContent extends StatelessWidget {
  final String markdown;

  const _MarkdownContent({required this.markdown});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: MarkdownBody(
        data: markdown,
        selectable: true,
        styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
          p: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
          h1: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.bold),
          h2: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
          h3: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
          code: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ).withBrandBlockquote(theme),
      ),
    );
  }
}
