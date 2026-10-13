import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../brand/app_brand.dart';
import '../../theme/app_theme.dart';

import '../../l10n/app_localizations.dart';
import '../../services/cdn_config.dart';
import '../../services/channel_cache.dart';
import '../../services/meili_client.dart';
import '../../widgets/em_highlight_text.dart';
import '../../widgets/episode_age.dart';
import '../../widgets/cached_thumbnail.dart';
import '../../router/nav.dart';

/// LOKALNI PoC ekran — instant keyword tražilica nad 2562 epizode preko
/// Meilisearcha (`localhost:7700`). Komplementarno semantičkoj MCP pretrazi.
/// Ruta: `/search` (vidi app_router.dart).
class MeiliSearchScreen extends StatefulWidget {
  /// Upit iz `?q=` — upisan u polje i pokrenut odmah, bez fokusa (tipkovnica
  /// ne prekriva rezultate).
  final String? initialQuery;

  const MeiliSearchScreen({super.key, this.initialQuery});

  @override
  State<MeiliSearchScreen> createState() => _MeiliSearchScreenState();
}

class _MeiliSearchScreenState extends State<MeiliSearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;

  String _query = '';
  String? _channel; // odabrani slug ili null (svi)
  MeiliResponse? _response;
  Map<String, int> _allChannels = const {}; // slug → broj (puna distribucija)
  bool _loading = false;
  String? _error;
  bool _meiliUp = true;

  @override
  void initState() {
    super.initState();
    final q = widget.initialQuery?.trim() ?? '';
    if (q.isNotEmpty) {
      _controller.text = q;
      _query = q;
    }
    _bootstrap();
    if (q.isEmpty) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _focus.requestFocus());
    }
  }

  Future<void> _bootstrap() async {
    final up = await MeiliClient.ping();
    if (!mounted) return;
    setState(() => _meiliUp = up);
    if (!up) return;
    if (_query.isNotEmpty) _runSearch();
    try {
      final facets = await MeiliClient.channelFacets();
      if (mounted) setState(() => _allChannels = facets);
    } catch (_) {/* facet fetch nije kritičan */}
    // Facet nosi slug, ime kanala je u indeksu. Na hladnom `/search` indeks
    // još nije učitan, pa je chip padao na slug („nanovoroeni" →
    // „Nanovoroeni" umjesto „Nanovo rođeni" — slug nema dijakritike).
    if (channelCache.index == null) {
      try {
        await channelCache.loadIndex();
        if (mounted) setState(() {});
      } catch (_) {/* ostaje fallback na slug */}
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    // Instant-search: Meili je <5ms, kratki debounce samo da ne spamamo po tipki.
    _debounce = Timer(const Duration(milliseconds: 220), () {
      setState(() => _query = value);
      _runSearch();
    });
  }

  Future<void> _runSearch() async {
    final q = _controller.text.trim();
    if (q.isEmpty) {
      setState(() {
        _response = null;
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await MeiliClient.search(q, channel: _channel, limit: 30);
      if (!mounted || _controller.text.trim() != q) return; // stale guard
      setState(() {
        _response = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _selectChannel(String? slug) {
    setState(() => _channel = slug);
    _runSearch();
  }

  String _channelName(String slug) {
    final idx = channelCache.index;
    if (idx != null) {
      for (final c in idx.channels) {
        if (c.id == slug) return c.name;
      }
    }
    // Fallback: prettify slug.
    return slug
        .split('_')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.channelKeywordSearch),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              back(context),
        ),
      ),
      body: Column(
        children: [
          _searchField(theme),
          if (!_meiliUp) _meiliDownBanner(theme),
          _statsBar(theme),
          if (_allChannels.isNotEmpty) _channelChips(theme),
          const Divider(height: 1),
          Expanded(child: _results(theme)),
        ],
      ),
    );
  }

  Widget _searchField(ThemeData theme) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        // S `?q=` bez fokusa: tipkovnica bi prekrila rezultate.
        autofocus: (widget.initialQuery ?? '').trim().isEmpty,
        textInputAction: TextInputAction.search,
        onChanged: _onChanged,
        style: theme.textTheme.titleMedium,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () {
                    _controller.clear();
                    _onChanged('');
                  },
                ),
          hintText: l.channelKeywordSearchHint,
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
        ),
      ),
    );
  }

  Widget _meiliDownBanner(ThemeData theme) {
    final l = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        l.channelSearchUnavailable(MeiliClient.baseUrl),
        style: theme.textTheme.labelMedium
            ?.copyWith(color: theme.colorScheme.onErrorContainer),
      ),
    );
  }

  Widget _statsBar(ThemeData theme) {
    final l = AppLocalizations.of(context);
    final res = _response;
    final muted = theme.colorScheme.onSurfaceVariant;
    String text;
    if (_loading) {
      text = l.channelSearching;
    } else if (res != null) {
      text = l.channelResultsInMs(res.estimatedTotalHits, res.processingTimeMs);
    } else {
      text = l.channelSearchPrompt;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 16, 8),
      child: Row(
        children: [
          Icon(Icons.bolt, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 4),
          Expanded(
            child: Text(text,
                style: theme.textTheme.labelMedium?.copyWith(color: muted)),
          ),
        ],
      ),
    );
  }

  Widget _channelChips(ThemeData theme) {
    final l = AppLocalizations.of(context);
    // Istaknuti kanali brenda prvi, zatim po veličini (najveći prvi).
    final featured = AppBrand.config.featuredChannels;
    final entries = _allChannels.entries.toList()
      ..sort((a, b) {
        final fa = featured.contains(a.key) ? 0 : 1;
        final fb = featured.contains(b.key) ? 0 : 1;
        return fa != fb ? fa.compareTo(fb) : b.value.compareTo(a.value);
      });
    return SizedBox(
      height: 46,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
        ),
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            _chip(theme, label: l.channelAll, selected: _channel == null,
                onTap: () => _selectChannel(null)),
            for (final e in entries)
              _chip(theme,
                  label: '${_channelName(e.key)} (${e.value})',
                  selected: _channel == e.key,
                  onTap: () => _selectChannel(e.key)),
          ],
        ),
      ),
    );
  }

  Widget _chip(ThemeData theme,
      {required String label,
      required bool selected,
      required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Center(
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
          labelStyle: theme.textTheme.labelMedium?.copyWith(
            color: selected
                ? Colors.white
                : theme.colorScheme.onSurfaceVariant,
          ),
          selectedColor: AppTheme.brandPrimary,
          side: selected
              ? AppTheme.brandRim(theme.brightness)
              : BorderSide.none,
          showCheckmark: false,
        ),
      ),
    );
  }

  Widget _results(ThemeData theme) {
    final l = AppLocalizations.of(context);
    if (_error != null) {
      return _centered(theme, l.commonErrorWithDetails(_error!));
    }
    final res = _response;
    if (res == null) {
      return _centered(
        theme,
        _query.isEmpty ? l.channelSearchStart : l.channelSearching,
        icon: Icons.search,
      );
    }
    if (res.hits.isEmpty) {
      return _centered(
        theme,
        l.channelNoResultsForQuery(_controller.text.trim()),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: res.hits.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, indent: 16, endIndent: 16),
      itemBuilder: (context, i) => _resultCard(theme, res.hits[i]),
    );
  }

  Widget _resultCard(ThemeData theme, MeiliHit hit) {
    final snippet = hit.formattedArticleSnippet.trim();
    return InkWell(
      onTap: () => drillDown(context, '/v/${hit.youtubeId}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedThumbnail(
                url: CdnConfig.thumbnailUrl(hit.youtubeId),
                width: 104,
                height: 58,
                fit: BoxFit.cover,
                errorIcon: Icons.ondemand_video,
                errorIconSize: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  EmHighlightText(
                    hit.formattedTitle,
                    style: theme.textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          _channelName(hit.channel),
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.colorScheme.primary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      EpisodeAgeChip(hit.uploadDate),
                    ],
                  ),
                  if (snippet.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    EmHighlightText(
                      snippet,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (hit.sectionTitles.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      hit.sectionTitles.take(3).join('  ·  '),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.65),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

  Widget _centered(ThemeData theme, String text, {IconData? icon}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(text,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}
