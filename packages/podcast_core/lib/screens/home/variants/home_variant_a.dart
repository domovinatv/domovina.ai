import 'package:flutter/material.dart';

import '../episodes_rail.dart';
import '../followed_rail.dart';
import '../footer.dart';
import '../home_app_bar.dart';
import '../persons_rail.dart';
import 'home_variant_data.dart';
import 'variant_strings.dart';
import 'variant_widgets.dart';

/// Varijanta A — „Tri police”: isti railovi kao danas, grupirani u tri
/// imenovane zone (Za tebe / Novo / Otkrij). „Novo” je JEDAN filtrirani
/// blok umjesto tri raila; spremljeno je kartica u „Za tebe”, ne rail na dnu.
class HomeVariantA extends StatelessWidget {
  final HomeVariantData data;

  const HomeVariantA({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final isMobile = data.isMobile;
    final shows = data.featuredShows();

    return CustomScrollView(
      controller: data.scrollController,
      slivers: [
        HomeAppBar(onSearchTap: data.onSearchTap),
        SliverToBoxAdapter(child: VariantHero(data: data)),

        // ---- Za tebe ---------------------------------------------------
        SliverToBoxAdapter(
          child: PersonalScope(
            continueWatching: data.continueWatching,
            builder: (context, personal) {
              if (!personal.hasAnything) return const SizedBox.shrink();
              final favorites = personal.favorites;
              final followed = FollowedRail(
                isMobile: isMobile,
                onVideoTap: data.onVideoTap,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ZoneHeader(
                    title: VariantStrings.of(context).zoneForYou,
                    subtitle: VariantStrings.of(context).zoneForYouSub,
                  ),
                  if (personal.hasContinue)
                    EpisodesRail(
                      eyebrow: VariantStrings.of(context).continueListening,
                      isMobile: isMobile,
                      cards: continueCards(data),
                    ),
                  if (isMobile || favorites.isEmpty) ...[
                    followed,
                    if (favorites.isNotEmpty)
                      FavoritesShelfCard(favorites: favorites, compact: true),
                  ] else
                    // Desktop: od praćenih (3/5) uz karticu police (2/5).
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: followed),
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              0,
                              8,
                              kVariantGutter,
                              16,
                            ),
                            child: FavoritesShelfCard(favorites: favorites),
                          ),
                        ),
                      ],
                    ),
                ],
              );
            },
          ),
        ),

        // ---- Novo ------------------------------------------------------
        SliverToBoxAdapter(
          child: NewZone(
            data: data,
            filters: const [
              NewFilter.processed,
              NewFilter.processing,
              NewFilter.corpus,
            ],
          ),
        ),

        // ---- Otkrij ----------------------------------------------------
        SliverToBoxAdapter(
          child: ZoneHeader(
            title: VariantStrings.of(context).zoneDiscover,
            subtitle: VariantStrings.of(context).zoneDiscoverSub,
          ),
        ),
        if (shows.isNotEmpty)
          SliverToBoxAdapter(
            child: EpisodesRail(
              eyebrow: VariantStrings.of(context).featuredShows,
              isMobile: isMobile,
              cards: [
                for (final fv in shows)
                  feedCard(context, fv, data, width: isMobile ? 220 : 260),
              ],
            ),
          ),
        SliverToBoxAdapter(child: PersonsRail(isMobile: isMobile)),
        if (data.channels.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionLabel(VariantStrings.of(context).channels),
          ),
          SliverToBoxAdapter(
            child: ChannelTiles(
              channels: data.channels,
              limit: isMobile ? 4 : 6,
              columns: isMobile ? 2 : 3,
            ),
          ),
        ],

        SliverToBoxAdapter(child: HomeFooter(channels: data.channels)),
      ],
    );
  }
}
