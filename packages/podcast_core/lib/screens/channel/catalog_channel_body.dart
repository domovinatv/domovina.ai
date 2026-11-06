import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../router/nav.dart';
import '../../services/catalog_client.dart';
import '../../services/cdn_config.dart';
import '../../services/scroll_memory.dart';
import '../../src/log.dart' show log;
import '../../widgets/cached_thumbnail.dart';
import '../../widgets/person_monogram.dart';
import '../catalog_day/catalog_day_format.dart';

/// Tijelo `/c/:slug` za kanal bez statičnog listinga (Tier 2, od S10):
/// zaglavlje iz `GET /channels/:slug` i epizode iz
/// `GET /channels/:slug/episodes`, stranica po stranica.
///
/// [ChannelScreen] ga crta tek kad je statični listing pao, a katalog je
/// uključen, pa Tier 1 ostaje na starom putu. Stanja: učitavanje, kanal,
/// „nije pronađen” (katalog 404) i „ne može se učitati” (mreža, timeout,
/// 5xx) s ponovnim pokušajem.
class CatalogChannelBody extends StatefulWidget {
  /// Slug doslovno iz URL-a (`sbs-croatian`, `yt-UCfT_PJ…`).
  final String slug;

  /// Otvori epizodu; [ChannelScreen] poštuje jednostavni prikaz (`/m/`).
  final void Function(String videoId) onVideoTap;

  /// Javlja učitani kanal (ime u traci, `<title>`), jednom po učitavanju.
  final ValueChanged<CatalogChannelInfo>? onChannel;

  const CatalogChannelBody({
    super.key,
    required this.slug,
    required this.onVideoTap,
    this.onChannel,
  });

  /// Veličina stranice epizoda.
  static const int pageSize = 30;

  @override
  State<CatalogChannelBody> createState() => _CatalogChannelBodyState();
}

enum _Phase { loading, ready, notFound, unavailable }

class _CatalogChannelBodyState extends State<CatalogChannelBody> {
  final _scroll = ScrollController();
  _Phase _phase = _Phase.loading;
  CatalogChannelInfo? _info;
  final List<CatalogCard> _items = [];
  String? _next;
  bool _loadingMore = false;
  bool _moreFailed = false;

  CatalogClient get _client => CatalogClient.instance;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    unawaited(_load());
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_phase != _Phase.loading) setState(() => _phase = _Phase.loading);
    var slug = widget.slug;
    // Zaglavlje i prva stranica paralelno: za slug iz URL-a to je jedan
    // krug do kataloga umjesto dva.
    final first = await Future.wait([
      _client.channel(slug),
      _client.channelEpisodes(slug, limit: CatalogChannelBody.pageSize),
    ]);
    var channel = first[0] as CatalogChannelLookup;
    var episodes = first[1] as CatalogChannelEpisodesLookup;
    // Tier 1 slug u katalogu nosi podvlaku (`radio_mreznica`), a ruta
    // crticu. Ovamo dolazi samo kad statični listing nije stigao (mreža,
    // CDN), pa katalog pita i ID listinga prije nego kaže „nema ga”.
    final alt = slug.replaceAll('-', '_');
    if (channel is CatalogChannelNotFound && alt != slug) {
      log('CatalogChannelBody($slug): 404, pokušavam $alt');
      final retry = await _client.channel(alt);
      if (retry is! CatalogChannelNotFound) {
        slug = alt;
        channel = retry;
        if (retry is CatalogChannelFound) {
          episodes = await _client.channelEpisodes(
            alt,
            limit: CatalogChannelBody.pageSize,
          );
        }
      }
    }
    if (!mounted) return;
    final info = channel.channel;
    final page = episodes.page;
    setState(() {
      _items.clear();
      _next = null;
      _moreFailed = false;
      if (channel is CatalogChannelNotFound ||
          (info != null && episodes is CatalogChannelEpisodesNotFound)) {
        _phase = _Phase.notFound;
      } else if (info == null || page == null) {
        _phase = _Phase.unavailable;
      } else {
        _info = info;
        _items.addAll(page.items);
        _next = page.next;
        _phase = _Phase.ready;
      }
    });
    log('CatalogChannelBody(${widget.slug}): ${_phase.name}');
    if (_phase == _Phase.ready) widget.onChannel?.call(info!);
  }

  Future<void> _loadMore() async {
    final after = _next;
    final info = _info;
    if (after == null || info == null || _loadingMore) return;
    setState(() {
      _loadingMore = true;
      _moreFailed = false;
    });
    final result = await _client.channelEpisodes(
      info.slug,
      limit: CatalogChannelBody.pageSize,
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
      // Spremljena stranica može biti starija od prethodne: isti ID se ne
      // crta dvaput.
      final seen = {for (final c in _items) c.id};
      _items.addAll(page.items.where((c) => seen.add(c.id)));
      _next = page.next;
    });
  }

  /// Beskonačno listanje (kao `/dani/`): sljedeća stranica kad je do dna
  /// manje od ~1,5 ekrana; gumb na dnu je rezerva.
  void _onScroll() {
    if (!_scroll.hasClients || _next == null || _loadingMore || _moreFailed) {
      return;
    }
    final pos = _scroll.position;
    if (pos.maxScrollExtent - pos.pixels < pos.viewportDimension * 1.5) {
      unawaited(_loadMore());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    switch (_phase) {
      case _Phase.loading:
        return const Center(child: CircularProgressIndicator());
      case _Phase.notFound:
        return CatalogMessage(
          icon: Icons.search_off,
          title: l.channelCatalogNotFoundTitle,
          body: l.channelCatalogNotFoundBody,
          action: FilledButton.icon(
            icon: const Icon(Icons.grid_view_outlined),
            label: Text(l.channelAllChannels),
            onPressed: () => drillDown(context, '/channels'),
          ),
        );
      case _Phase.unavailable:
        return CatalogMessage(
          icon: Icons.cloud_off_outlined,
          title: l.channelCatalogUnavailableTitle,
          body: l.channelCatalogUnavailableBody,
          action: FilledButton.icon(
            icon: const Icon(Icons.refresh),
            label: Text(l.commonRetry),
            onPressed: () => unawaited(_load()),
          ),
        );
      case _Phase.ready:
        return _list(theme, l, _info!);
    }
  }

  Widget _list(ThemeData theme, AppLocalizations l, CatalogChannelInfo info) {
    final hasFooter = _next != null || _loadingMore || _moreFailed;
    final hasYouTube = info.youtubeChannelId != null;
    final children = <Widget>[
      _header(theme, l, info),
      const SizedBox(height: 20),
      Text(
        l.channelCatalogEpisodesHeading,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 10),
      for (final card in _items) ...[
        CatalogEpisodeRow(card: card, onTap: () => widget.onVideoTap(card.id)),
        const SizedBox(height: 12),
      ],
      if (hasFooter)
        CatalogLoadMoreFooter(
          loading: _loadingMore,
          failed: _moreFailed,
          onLoadMore: () => unawaited(_loadMore()),
        ),
      if (hasYouTube && !hasFooter) ...[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(l.channelCatalogOpenYouTube),
            onPressed: () => unawaited(
              launchUrl(
                Uri.parse(
                  'https://www.youtube.com/channel/${info.youtubeChannelId}',
                ),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ),
        ),
      ],
    ];
    // Rubni padding ide UNUTAR scrollabla (CLAUDE.md, scrollabilne liste).
    return ScrollRestorer(
      storageKey: '/c/${widget.slug}',
      controller: _scroll,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: children,
          ),
        ),
      ),
    );
  }

  Widget _header(ThemeData theme, AppLocalizations l, CatalogChannelInfo info) {
    final cs = theme.colorScheme;
    final date = info.latestPublishedDate == null
        ? null
        : parseCatalogDate(info.latestPublishedDate!);
    final meta = [
      l.channelCatalogEpisodeCount(info.processedCount),
      if (date != null)
        l.channelCatalogLatest(catalogDayLongLabel(context, date)),
    ].join(' · ');
    return Semantics(
      identifier: 'catalog-channel-header',
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PersonMonogram(
                name: info.name,
                avatarUrl: info.avatar,
                size: 72,
                radius: 16,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      meta,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    if (!info.followed) ...[
                      const SizedBox(height: 8),
                      CatalogOccasionalBadge(
                        label: l.channelCatalogOccasionalBadge,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (!info.followed) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l.channelCatalogOccasionalBody,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Oznaka „Ne pratimo stalno” (Tier 2) — u zaglavlju kanala i u popisu
/// „Svi” na `/channels`.
class CatalogOccasionalBadge extends StatelessWidget {
  final String label;

  const CatalogOccasionalBadge({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
      ),
    );
  }
}

/// Redak epizode iz kataloga (sličica, naslov, datum), isti oblik kao na
/// `/dani/`.
class CatalogEpisodeRow extends StatelessWidget {
  final CatalogCard card;
  final VoidCallback onTap;

  const CatalogEpisodeRow({super.key, required this.card, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final date = card.date == null ? null : parseCatalogDate(card.date!);
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
                    Text(
                      card.displayTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (date != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        catalogDayLongLabel(context, date),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
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

/// Dno popisa iz kataloga: vrtuljak dok stiže stranica, inače gumb
/// „Učitaj još” (rezerva za beskonačno listanje) ili poruka + ponovni pokušaj.
class CatalogLoadMoreFooter extends StatelessWidget {
  final bool loading;
  final bool failed;
  final VoidCallback onLoadMore;

  const CatalogLoadMoreFooter({
    super.key,
    required this.loading,
    required this.failed,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          if (failed) ...[
            Text(
              l.catalogLoadMoreFailed,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton(
            onPressed: onLoadMore,
            child: Text(failed ? l.commonRetry : l.catalogLoadMore),
          ),
        ],
      ),
    );
  }
}

/// Poruka preko cijelog tijela (ikona, naslov, objašnjenje, radnja).
class CatalogMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget action;

  const CatalogMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
}
