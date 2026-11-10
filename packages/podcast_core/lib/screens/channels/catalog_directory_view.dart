import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../router/nav.dart';
import '../../services/catalog_client.dart';
import '../../services/scroll_memory.dart';
import '../../src/log.dart' show log;
import '../../widgets/person_monogram.dart';
import '../catalog_day/catalog_day_format.dart';
import '../channel/catalog_channel_body.dart'
    show CatalogLoadMoreFooter, CatalogMessage, CatalogOccasionalBadge;

/// Filtar „Svi” na `/channels` (`?prikaz=svi`, katalog S10): svi kanali s
/// barem jednom obrađenom epizodom iz `GET /directory`, oba tiera,
/// najsvježiji prvi, stranica po stranica.
///
/// Učitani popis živi u statičkom memou procesa (kao `ScrollMemory`): kad se
/// ekran sruši i vrati (deep-link pa ←, `go('/')` s breadcrumba), popis i
/// pozicija su odmah tu, pa `ScrollRestorer` ima do čega skočiti.
class CatalogDirectoryView extends StatefulWidget {
  const CatalogDirectoryView({super.key});

  /// Veličina stranice.
  static const int pageSize = 30;

  /// Ključ pozicije za `ScrollRestorer` — nosi query, kao `/channels?prikaz=osobe`.
  static const String scrollKey = '/channels?prikaz=svi';

  static _DirectoryMemo? _memo;

  /// Za testove: zaboravi učitani popis.
  @visibleForTesting
  static void resetMemo() => _memo = null;

  @override
  State<CatalogDirectoryView> createState() => _CatalogDirectoryViewState();
}

class _DirectoryMemo {
  final List<CatalogChannelInfo> items;
  final String? next;
  final DateTime at;
  const _DirectoryMemo(this.items, this.next, this.at);

  /// Popis se mijenja tek noćnim ingestom; četvrt sata je dovoljno za
  /// povratak na isti popis, a ne drži ga cijeli dan.
  static const Duration maxAge = Duration(minutes: 15);

  bool get fresh => DateTime.now().difference(at) < maxAge;
}

enum _Phase { loading, list, empty, unavailable }

class _CatalogDirectoryViewState extends State<CatalogDirectoryView> {
  final _scroll = ScrollController();
  _Phase _phase = _Phase.loading;
  final List<CatalogChannelInfo> _items = [];
  String? _next;
  bool _loadingMore = false;
  bool _moreFailed = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    final memo = CatalogDirectoryView._memo;
    if (memo != null && memo.items.isNotEmpty && memo.fresh) {
      _items.addAll(memo.items);
      _next = memo.next;
      _phase = _Phase.list;
    } else {
      unawaited(_loadFirst());
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _remember() => CatalogDirectoryView._memo = _DirectoryMemo(
    List.of(_items),
    _next,
    DateTime.now(),
  );

  Future<void> _loadFirst() async {
    if (_phase != _Phase.loading) setState(() => _phase = _Phase.loading);
    final result = await CatalogClient.instance.directory(
      limit: CatalogDirectoryView.pageSize,
    );
    if (!mounted) return;
    setState(() {
      switch (result) {
        case CatalogDirectoryFound(:final found):
          _items
            ..clear()
            ..addAll(found.items);
          _next = found.next;
          _phase = found.isEmpty ? _Phase.empty : _Phase.list;
        case CatalogDirectoryUnavailable():
          _phase = _Phase.unavailable;
      }
    });
    log('CatalogDirectoryView: ${_phase.name}, ${_items.length} kanala');
    if (_phase == _Phase.list) _remember();
  }

  Future<void> _loadMore() async {
    final after = _next;
    if (after == null || _loadingMore) return;
    setState(() {
      _loadingMore = true;
      _moreFailed = false;
    });
    final result = await CatalogClient.instance.directory(
      limit: CatalogDirectoryView.pageSize,
      after: after,
    );
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      final page = result.page;
      if (page == null) {
        _moreFailed = true;
        return;
      }
      // Spremljena stranica može biti starija: isti kanal se ne crta dvaput.
      final seen = {for (final c in _items) c.slug};
      _items.addAll(page.items.where((c) => seen.add(c.slug)));
      _next = page.next;
    });
    if (result.page != null) _remember();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _next == null || _loadingMore || _moreFailed) {
      return;
    }
    final pos = _scroll.position;
    if (pos.maxScrollExtent - pos.pixels < pos.viewportDimension * 1.5) {
      unawaited(_loadMore());
    }
  }

  void _open(CatalogChannelInfo c) =>
      drillDown(context, '/c/${c.channel.routeSlug}');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    switch (_phase) {
      case _Phase.loading:
        return const Center(child: CircularProgressIndicator());
      case _Phase.empty:
        return CatalogMessage(
          icon: Icons.inbox_outlined,
          title: l.channelDirectoryEmpty,
          body: l.channelDirectoryHint,
          action: const SizedBox.shrink(),
        );
      case _Phase.unavailable:
        return CatalogMessage(
          icon: Icons.cloud_off_outlined,
          title: l.channelDirectoryUnavailableTitle,
          body: l.channelDirectoryUnavailableBody,
          action: FilledButton.icon(
            icon: const Icon(Icons.refresh),
            label: Text(l.commonRetry),
            onPressed: () => unawaited(_loadFirst()),
          ),
        );
      case _Phase.list:
        return _list(theme, l);
    }
  }

  /// Najveća širina kartice u stupcu; ista kao kartice „Pratimo”
  /// (`_maxCardWidth` u `all_channels_screen.dart`).
  static const double _maxTileWidth = 360;

  Widget _list(ThemeData theme, AppLocalizations l) {
    final hasFooter = _next != null || _loadingMore || _moreFailed;
    // Popis koji ne puni ekran (desktop mreža: 30 stavki je par redova) ne
    // može okinuti scroll, pa se nakon layouta provjeri isto što i pri
    // listanju. `_onScroll` sam pazi na `_next`/`_loadingMore`/`_moreFailed`.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onScroll();
    });
    return ScrollRestorer(
      storageKey: CatalogDirectoryView.scrollKey,
      controller: _scroll,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Mobitel (< 600): jedan stupac. Šire: onoliko stupaca koliko
          // stane kartica do [_maxTileWidth], kao „Pratimo”.
          final available = constraints.maxWidth - 32;
          final columns = constraints.maxWidth < 600
              ? 1
              : (available / _maxTileWidth).floor().clamp(2, 99);
          final rows = (_items.length / columns).ceil();
          return ListView.builder(
            controller: _scroll,
            // Rubni padding UNUTAR scrollabla (CLAUDE.md, scrollabilne liste).
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            // Red po red (ne GridView): kartice imaju različitu visinu
            // (oznaka „Ne pratimo stalno”), a lijeno crtanje ostaje.
            itemCount: 1 + rows + (hasFooter ? 1 : 0),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    l.channelDirectoryHint,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              final row = i - 1;
              if (row < rows) {
                final first = row * columns;
                final last = (first + columns).clamp(0, _items.length);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  // Kartice u redu iste visine; prazna mjesta zadnjeg reda
                  // drže širinu stupca.
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var k = first; k < first + columns; k++) ...[
                          if (k > first) const SizedBox(width: 12),
                          Expanded(
                            child: k < last
                                ? CatalogChannelTile(
                                    channel: _items[k],
                                    onTap: () => _open(_items[k]),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }
              return CatalogLoadMoreFooter(
                loading: _loadingMore,
                failed: _moreFailed,
                onLoadMore: () => unawaited(_loadMore()),
              );
            },
          );
        },
      ),
    );
  }
}

/// Redak kanala iz kataloga: slika ili monogram, ime, broj obrađenih epizoda
/// i datum zadnje, te oznaka „Ne pratimo stalno” za Tier 2.
class CatalogChannelTile extends StatelessWidget {
  final CatalogChannelInfo channel;
  final VoidCallback onTap;

  const CatalogChannelTile({
    super.key,
    required this.channel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);
    final c = channel;
    final date = c.latestPublishedDate == null
        ? null
        : parseCatalogDate(c.latestPublishedDate!);
    final meta = [
      l.channelCatalogEpisodeCount(c.processedCount),
      if (date != null)
        l.channelCatalogLatest(catalogDayLongLabel(context, date)),
    ].join(' · ');
    return Material(
      color: cs.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              PersonMonogram(
                name: c.name,
                avatarUrl: c.avatar,
                size: 52,
                radius: 12,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      c.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!c.followed) ...[
                      const SizedBox(height: 6),
                      CatalogOccasionalBadge(
                        label: l.channelCatalogOccasionalBadge,
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
