import 'package:flutter/material.dart';

import '../catalog_day_rail.dart';
import '../episodes_rail.dart';
import '../favorites_rail.dart';
import '../followed_rail.dart';
import '../footer.dart';
import '../home_app_bar.dart';
import '../persons_rail.dart';
import 'home_variant_data.dart';
import 'variant_strings.dart';
import 'variant_widgets.dart';

/// Varijanta B — „Novine”. Široko: glavni stupac (hero + „Najnovije” kao
/// gusta lista) i bočna traka osobnog (380 px). Usko: kartice
/// Za tebe / Novo / Otkrij umjesto jednog dugog scrolla.
class HomeVariantB extends StatefulWidget {
  final HomeVariantData data;

  const HomeVariantB({super.key, required this.data});

  /// Ispod ove širine bočna traka nema mjesta → kartice.
  static const double twoColumnMinWidth = 1000;
  static const double sidebarWidth = 380;

  @override
  State<HomeVariantB> createState() => _HomeVariantBState();
}

enum _Tab { forYou, fresh, discover }

class _HomeVariantBState extends State<HomeVariantB> {
  _Tab _tab = _Tab.fresh;

  HomeVariantData get data => widget.data;

  @override
  Widget build(BuildContext context) {
    final wide = data.width >= HomeVariantB.twoColumnMinWidth;
    return CustomScrollView(
      controller: data.scrollController,
      slivers: [
        HomeAppBar(onSearchTap: data.onSearchTap),
        if (wide) ..._wide(context) else ..._tabs(context),
        SliverToBoxAdapter(child: HomeFooter(channels: data.channels)),
      ],
    );
  }

  // ---------------------------------------------------------------- široko

  List<Widget> _wide(BuildContext context) {
    final latest = NewZone(
      data: data,
      title: VariantStrings.latest,
      subtitle: null,
      preferList: true,
      filters: const [NewFilter.all, NewFilter.processed, NewFilter.processing],
    );
    return [
      SliverToBoxAdapter(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  VariantHero(data: data),
                  latest,
                ],
              ),
            ),
            SizedBox(
              width: HomeVariantB.sidebarWidth,
              child: Padding(
                padding: const EdgeInsets.only(top: 16, right: 8),
                child: _Sidebar(data: data),
              ),
            ),
          ],
        ),
      ),
      ..._discover(context, header: true),
    ];
  }

  // ---------------------------------------------------------------- usko

  List<Widget> _tabs(BuildContext context) {
    return [
      SliverToBoxAdapter(
        child: _TabStrip(
          selected: _tab,
          onSelected: (t) {
            if (t == _tab) return;
            setState(() => _tab = t);
            if (data.scrollController.hasClients) {
              data.scrollController.jumpTo(0);
            }
          },
        ),
      ),
      ...switch (_tab) {
        _Tab.fresh => [
          SliverToBoxAdapter(child: VariantHero(data: data)),
          SliverToBoxAdapter(
            child: NewZone(
              data: data,
              title: VariantStrings.latest,
              subtitle: null,
              filters: const [
                NewFilter.all,
                NewFilter.processed,
                NewFilter.processing,
                NewFilter.corpus,
              ],
            ),
          ),
        ],
        _Tab.forYou => [
          SliverToBoxAdapter(
            child: PersonalScope(
              continueWatching: data.continueWatching,
              builder: (context, personal) {
                if (!personal.hasAnything) {
                  final theme = Theme.of(context);
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      VariantStrings.forYouEmpty,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (personal.hasContinue) ...[
                      const SectionLabel(
                        VariantStrings.continueListening,
                        padding: EdgeInsets.fromLTRB(
                          kVariantGutter,
                          20,
                          kVariantGutter,
                          4,
                        ),
                      ),
                      ContinueCompactList(
                        items: data.continueWatching.take(5).toList(),
                        onVideoTap: data.onVideoTap,
                      ),
                      const SizedBox(height: 12),
                    ],
                    FollowedRail(
                      isMobile: data.isMobile,
                      onVideoTap: data.onVideoTap,
                    ),
                    FavoritesRail(
                      isMobile: data.isMobile,
                      onVideoTap: data.onVideoTap,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
        _Tab.discover => _discover(context, header: false),
      },
    ];
  }

  List<Widget> _discover(BuildContext context, {required bool header}) {
    final isMobile = data.isMobile;
    final shows = data.featuredShows();
    return [
      if (header)
        const SliverToBoxAdapter(
          child: ZoneHeader(
            title: VariantStrings.zoneDiscover,
            subtitle: VariantStrings.zoneDiscoverSub,
          ),
        )
      else
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
      if (shows.isNotEmpty)
        SliverToBoxAdapter(
          child: EpisodesRail(
            eyebrow: VariantStrings.featuredShows,
            isMobile: isMobile,
            cards: [
              for (final fv in shows)
                feedCard(context, fv, data, width: isMobile ? 220 : 260),
            ],
          ),
        ),
      SliverToBoxAdapter(child: PersonsRail(isMobile: isMobile)),
      if (data.channels.isNotEmpty) ...[
        const SliverToBoxAdapter(child: SectionLabel(VariantStrings.channels)),
        SliverToBoxAdapter(
          child: ChannelTiles(
            channels: data.channels,
            limit: isMobile ? 6 : 9,
            columns: isMobile ? 2 : 3,
          ),
        ),
      ],
    ];
  }
}

/// Bočna traka osobnog (široki B): Nastavi, Od praćenih, Danas u korpusu,
/// Spremljeno. Svaki dio se sam skriva kad nema podataka.
class _Sidebar extends StatelessWidget {
  final HomeVariantData data;

  const _Sidebar({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PersonalScope(
      continueWatching: data.continueWatching,
      builder: (context, personal) => Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (personal.hasContinue) ...[
              const SectionLabel(VariantStrings.continueListening),
              ContinueCompactList(
                items: data.continueWatching.take(4).toList(),
                onVideoTap: data.onVideoTap,
                thumbWidth: 104,
              ),
              const SizedBox(height: 8),
            ],
            FollowedRail(isMobile: true, onVideoTap: data.onVideoTap),
            CatalogDayRail(isMobile: true, onVideoTap: data.onVideoTap),
            if (personal.favorites.isNotEmpty)
              FavoritesShelfCard(favorites: personal.favorites, compact: true),
          ],
        ),
      ),
    );
  }
}

class _TabStrip extends StatelessWidget {
  final _Tab selected;
  final ValueChanged<_Tab> onSelected;

  const _TabStrip({required this.selected, required this.onSelected});

  static const _labels = {
    _Tab.forYou: VariantStrings.zoneForYou,
    _Tab.fresh: VariantStrings.zoneNew,
    _Tab.discover: VariantStrings.zoneDiscover,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          for (final t in _Tab.values)
            Expanded(
              child: Semantics(
                selected: t == selected,
                button: true,
                child: InkWell(
                  onTap: () => onSelected(t),
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          width: 2,
                          color: t == selected
                              ? cs.tertiary
                              : Colors.transparent,
                        ),
                      ),
                    ),
                    child: Text(
                      _labels[t]!,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: t == selected
                            ? cs.onSurface
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
