import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../../router/nav.dart';
import '../../services/catalog_client.dart';
import '../../services/cdn_config.dart';
import '../../src/log.dart' show log;
import '../../theme/typography.dart';
import '../../widgets/cached_thumbnail.dart';
import 'catalog_day_format.dart';

/// `/dani/:datum` — sve epizode jednog dana iz kataloga (`GET /days/:date`,
/// oba tiera), stranica po stranica po `next` kursoru.
///
/// Stanja: učitavanje, popis, prazan dan (s ponudom prethodnog), neispravan
/// datum (oblik ili HTTP 400), „nije dostupno” (brend bez
/// `Endpoints.catalog`, mreža, 5xx). Aplikacija radi i bez kataloga, pa ruta
/// postoji uvijek i sama kaže da popisa nema.
///
/// Prethodni/sljedeći dan ide kroz [goPeer] (dan → dan je peer, stog ne
/// raste); sljedeći ne ide iza današnjeg lokalnog datuma.
class CatalogDayScreen extends StatefulWidget {
  /// Doslovno iz URL-a; valjanost provjerava ekran.
  final String date;

  /// Sat za testove; `null` = `DateTime.now()`.
  final DateTime Function()? clock;

  const CatalogDayScreen({super.key, required this.date, this.clock});

  /// Veličina stranice.
  static const int pageSize = 30;

  @override
  State<CatalogDayScreen> createState() => _CatalogDayScreenState();
}

enum _Phase { loading, list, empty, badDate, unavailable }

class _CatalogDayScreenState extends State<CatalogDayScreen> {
  final _scroll = ScrollController();
  late final DateTime? _date = parseCatalogDate(widget.date);

  _Phase _phase = _Phase.loading;
  final List<CatalogCard> _items = [];
  String? _next;
  bool _loadingMore = false;
  bool _moreFailed = false;

  DateTime get _today => catalogToday(widget.clock?.call());

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    if (_date == null) {
      log('CatalogDayScreen(${widget.date}): neispravan datum');
      _phase = _Phase.badDate;
    } else if (!CatalogClient.instance.enabled) {
      log('CatalogDayScreen(${widget.date}): brend nema katalog');
      _phase = _Phase.unavailable;
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

  Future<void> _loadFirst() async {
    if (_phase != _Phase.loading) setState(() => _phase = _Phase.loading);
    final result = await CatalogClient.instance.day(
      widget.date,
      limit: CatalogDayScreen.pageSize,
      // Prva stranica dolazi iz diskovnog cachea (stale-while-revalidate),
      // a dan se puni tijekom dana: bez ovoga ekran ostane zamrznut na
      // stranici s prvog otvaranja (6. 11.: 26 umjesto 34, bez „Učitaj još”).
      onUpdate: _applyFreshFirstPage,
    );
    if (!mounted) return;
    setState(() {
      switch (result) {
        case CatalogDayFound(:final found):
          _items
            ..clear()
            ..addAll(found.items);
          _next = found.next;
          _phase = found.isEmpty ? _Phase.empty : _Phase.list;
        case CatalogDayBadDate():
          _phase = _Phase.badDate;
        case CatalogDayUnavailable():
          _phase = _Phase.unavailable;
      }
    });
  }

  /// Revalidirana prva stranica. Dok je učitana samo prva stranica, svježa
  /// je zamjenjuje (s njenim `next`, pa „Učitaj još” proradi ako ga stara
  /// nije imala). Kad je korisnik već listao dalje, popis i kursor ostaju, a
  /// nove epizode s prve stranice dodaju se na kraj — umetanje iznad
  /// vidljivog dijela pomaknulo bi sadržaj pod korisnikom.
  void _applyFreshFirstPage(CatalogDayPage fresh) {
    if (!mounted) return;
    if (_phase != _Phase.list && _phase != _Phase.empty) return;
    log(
      'CatalogDayScreen(${widget.date}): revalidirana prva stranica, '
      '${fresh.items.length} epizoda${fresh.hasMore ? ', ima dalje' : ''}',
    );
    setState(() {
      if (_items.length <= CatalogDayScreen.pageSize) {
        _items
          ..clear()
          ..addAll(fresh.items);
        _next = fresh.next;
        _moreFailed = false;
      } else {
        final seen = {for (final c in _items) c.id};
        _items.addAll(fresh.items.where((c) => seen.add(c.id)));
      }
      _phase = _items.isEmpty ? _Phase.empty : _Phase.list;
    });
  }

  Future<void> _loadMore() async {
    final after = _next;
    if (after == null || _loadingMore) return;
    setState(() {
      _loadingMore = true;
      _moreFailed = false;
    });
    final result = await CatalogClient.instance.day(
      widget.date,
      limit: CatalogDayScreen.pageSize,
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
      // Keyset kursor ne daje duplikate, ali spremljena stranica može biti
      // starija od prethodne — isti ID se ne crta dvaput.
      final seen = {for (final c in _items) c.id};
      _items.addAll(page.items.where((c) => seen.add(c.id)));
      _next = page.next;
    });
  }

  /// Beskonačno listanje: sljedeća stranica kreće kad je do dna manje od
  /// ~1,5 ekrana. Gumb „Učitaj još” ostaje za slučaj da popis ne puni ekran
  /// ili je prethodni pokušaj pao.
  void _onScroll() {
    if (!_scroll.hasClients || _next == null || _loadingMore || _moreFailed) {
      return;
    }
    final pos = _scroll.position;
    if (pos.maxScrollExtent - pos.pixels < pos.viewportDimension * 1.5) {
      unawaited(_loadMore());
    }
  }

  void _goToDay(DateTime date) =>
      goPeer(context, '/dani/${formatCatalogDate(date)}');

  void _open(String id) => drillDown(context, '/v/$id');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final date = _date;
    final today = _today;
    final canGoNext =
        date != null && shiftCatalogDate(date, 1).compareTo(today) <= 0;
    final dayNavEnabled = date != null && _phase != _Phase.unavailable;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: l.commonBack,
          onPressed: () => back(context),
        ),
        title: date == null
            ? Text(l.catalogDayEyebrow)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l.catalogDayEyebrow.toUpperCase(),
                    style: AppTypography.eyebrowStyle(theme.colorScheme),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    catalogDayLongLabel(context, date),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
        actions: [
          if (dayNavEnabled) ...[
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: l.catalogDayPrevious,
              onPressed: () => _goToDay(shiftCatalogDate(date, -1)),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: l.catalogDayNext,
              onPressed: canGoNext
                  ? () => _goToDay(shiftCatalogDate(date, 1))
                  : null,
            ),
          ],
        ],
      ),
      body: SafeArea(top: false, child: _body(theme, l, date)),
    );
  }

  Widget _body(ThemeData theme, AppLocalizations l, DateTime? date) {
    switch (_phase) {
      case _Phase.loading:
        return const Center(child: CircularProgressIndicator());
      case _Phase.badDate:
        return _message(
          theme,
          icon: Icons.event_busy,
          title: l.catalogDayInvalidTitle,
          body: l.catalogDayInvalidBody,
          action: FilledButton.icon(
            icon: const Icon(Icons.home_outlined),
            label: Text(l.commonGoHome),
            onPressed: () => context.go('/'),
          ),
        );
      case _Phase.unavailable:
        return _message(
          theme,
          icon: Icons.cloud_off_outlined,
          title: l.catalogDayUnavailableTitle,
          body: l.catalogDayUnavailableBody,
          action: CatalogClient.instance.enabled
              ? FilledButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: Text(l.commonRetry),
                  onPressed: () => unawaited(_loadFirst()),
                )
              : FilledButton.icon(
                  icon: const Icon(Icons.home_outlined),
                  label: Text(l.commonGoHome),
                  onPressed: () => context.go('/'),
                ),
        );
      case _Phase.empty:
        return _message(
          theme,
          icon: Icons.event_available_outlined,
          title: l.catalogDayEmptyTitle,
          body: l.catalogDayEmptyBody,
          action: FilledButton.icon(
            icon: const Icon(Icons.chevron_left),
            label: Text(l.catalogDayPrevious),
            onPressed: () => _goToDay(shiftCatalogDate(date!, -1)),
          ),
        );
      case _Phase.list:
        return _list(theme, l);
    }
  }

  Widget _message(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String body,
    required Widget action,
  }) {
    final cs = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: cs.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              action,
            ],
          ),
        ),
      ),
    );
  }

  /// Najveća širina kartice u mreži; ista kao na `/c/<slug>`
  /// (`_ResponsiveVideoList` u `channel_screen.dart`).
  static const double _maxGridCardWidth = 300;

  /// Ispod ove širine stupac s retcima, iznad mreža kartica (kao kanal).
  static const double _gridMinWidth = 600;

  Widget _list(ThemeData theme, AppLocalizations l) {
    final hasFooter = _next != null || _loadingMore || _moreFailed;
    // Popis koji ne puni ekran (desktop mreža: 30 stavki je par redova) ne
    // može okinuti scroll, pa se nakon layouta provjeri isto što i pri
    // listanju. `_onScroll` sam pazi na `_next`/`_loadingMore`/`_moreFailed`.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onScroll();
    });
    // Rubni padding ide UNUTAR scrollabla (vidi CLAUDE.md — Scrollabilne liste).
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width < _gridMinWidth) {
          return ListView.separated(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: _items.length + (hasFooter ? 1 : 0),
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              if (i < _items.length) return _row(theme, _items[i]);
              return _footer(theme, l);
            },
          );
        }
        // Desktop/tablet: mreža kao na `/c/<slug>`, da ekran ne bude uski
        // stupac usred praznine.
        final available = width - 32;
        final columns = (available / _maxGridCardWidth).floor().clamp(2, 99);
        final cardWidth = (available - (columns - 1) * 12) / columns;
        return SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final card in _items)
                    SizedBox(
                      width: cardWidth,
                      child: _gridCard(theme, card, cardWidth),
                    ),
                ],
              ),
              if (hasFooter) ...[
                const SizedBox(height: 16),
                Center(child: _footer(theme, l)),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Kartica mreže: slika 16:9 preko pune širine, ispod kanal i naslov.
  Widget _gridCard(ThemeData theme, CatalogCard card, double width) {
    final cs = theme.colorScheme;
    final channel = card.channel?.name;
    final channelRoute = card.channel?.hasChannelRoute == true
        ? '/c/${card.channel!.routeSlug}'
        : null;
    return Material(
      color: cs.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(card.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: CachedThumbnail(
                url: CdnConfig.thumbnailUrl(card.id),
                width: width,
                fit: BoxFit.cover,
                errorIcon: Icons.ondemand_video,
                errorIconSize: 28,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (channel != null) ...[
                    _channelLabel(theme, channel, channelRoute),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    card.displayTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer(ThemeData theme, AppLocalizations l) {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          if (_moreFailed) ...[
            Text(
              l.catalogDayLoadMoreFailed,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton(
            onPressed: () => unawaited(_loadMore()),
            child: Text(_moreFailed ? l.commonRetry : l.catalogDayLoadMore),
          ),
        ],
      ),
    );
  }

  /// Ime kanala; s rutom (Tier 1 i, od S10, Tier 2) vodi na `/c/<slug>`.
  /// Unutarnji InkWell pobjeđuje onaj retka, pa ostatak retka i dalje
  /// otvara epizodu.
  Widget _channelLabel(ThemeData theme, String channel, String? route) {
    final text = Text(
      channel.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (route == null) return text;
    return InkWell(
      onTap: () => drillDown(context, route),
      borderRadius: BorderRadius.circular(4),
      child: text,
    );
  }

  Widget _row(ThemeData theme, CatalogCard card) {
    final cs = theme.colorScheme;
    final channel = card.channel?.name;
    final channelRoute = card.channel?.hasChannelRoute == true
        ? '/c/${card.channel!.routeSlug}'
        : null;
    return Material(
      color: cs.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(card.id),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              SizedBox(
                width: 128,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedThumbnail(
                      url: CdnConfig.thumbnailUrl(card.id),
                      width: 128,
                      fit: BoxFit.cover,
                      errorIcon: Icons.ondemand_video,
                      errorIconSize: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (channel != null) ...[
                      _channelLabel(theme, channel, channelRoute),
                      const SizedBox(height: 3),
                    ],
                    Text(
                      card.displayTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
