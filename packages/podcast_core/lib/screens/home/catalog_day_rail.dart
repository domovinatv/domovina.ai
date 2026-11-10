import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../router/nav.dart';
import '../../services/catalog_client.dart';
import '../../services/cdn_config.dart';
import '../../services/share_language.dart';
import '../../services/share_links.dart';
import '../../src/log.dart' show log;
import '../catalog_day/catalog_day_format.dart';
import 'episode_rail_card.dart';
import 'episodes_rail.dart';

/// Home rail „Danas u korpusu” — obrađene epizode OBJAVLJENE tog dana
/// (`GET /days/:date`, oba tiera; dan objave u Europe/Zagreb, isti kao na
/// podcast.domovina.ai/dani/), s „Prikaži sve” na `/dani/<datum>`.
///
/// Pipeline noću obradi ono što je objavljeno jučer, pa danas do sutra ima
/// tek pokoju epizodu objavljenu iza ponoći (10. 11. 2026.: danas 2, jučer
/// 34). Rail zato ide od današnjeg lokalnog datuma unatrag najviše
/// [maxDaysBack] dana i pokazuje prvi dan s barem [minEpisodes] epizoda;
/// nema li takvog, najnoviji neprazan. Naslov kaže koji je dan pokazao.
///
/// Samodostatan kao `FollowedRail`: sam se sakrije kad brend nema katalog,
/// kad katalog nije dostupan ili kad su svi dani prazni. Skeletona nema — rail
/// se pojavi tek kad ima što pokazati, ispod „Upravo stiglo”, pa ništa iznad
/// njega ne skače.
class CatalogDayRail extends StatefulWidget {
  final bool isMobile;

  /// Otvaranje epizode ide kroz home (poštuje „Jednostavno” mod → `/m/:id`).
  final void Function(String videoId) onVideoTap;

  /// Sat za testove; `null` = `DateTime.now()`.
  final DateTime Function()? clock;

  const CatalogDayRail({
    super.key,
    required this.isMobile,
    required this.onVideoTap,
    this.clock,
  });

  /// Koliko dana prije današnjeg rail smije pogledati.
  static const int maxDaysBack = 3;

  /// Dan s manje epizoda je „tanak”: rail ide dan unatrag, a na njega se
  /// vraća samo kad ni jedan od pregledanih dana nema ovoliko.
  static const int minEpisodes = 6;

  /// Koliko epizoda rail traži (pun popis je na `/dani/<datum>`).
  static const int railLimit = 12;

  /// Zadnji pokazani dan, da ponovno montiranje naslovnice (deep-link pa ←,
  /// `go('/')` s breadcrumba) ne crta jedan frame bez raila pa ga onda doda.
  /// Vrijedi samo za isti današnji datum. Testovi ga brišu kroz [resetMemo].
  static _Resolved? _memo;

  @visibleForTesting
  static void resetMemo() => _memo = null;

  @override
  State<CatalogDayRail> createState() => _CatalogDayRailState();
}

class _Resolved {
  final DateTime today;
  final DateTime date;
  final CatalogDayPage page;
  const _Resolved(this.today, this.date, this.page);
}

class _CatalogDayRailState extends State<CatalogDayRail> {
  _Resolved? _shown;

  /// Svako novo razrješavanje poništava stariji odgovor koji kasni.
  int _generation = 0;

  DateTime get _today => catalogToday(widget.clock?.call());

  @override
  void initState() {
    super.initState();
    final memo = CatalogDayRail._memo;
    if (memo != null && memo.today == _today) _shown = memo;
    unawaited(_resolve());
  }

  Future<void> _resolve() async {
    final client = CatalogClient.instance;
    if (!client.enabled) return;
    final generation = ++_generation;
    final today = _today;
    _Resolved? newestNonEmpty;
    for (var back = 0; back <= CatalogDayRail.maxDaysBack; back++) {
      final date = shiftCatalogDate(today, -back);
      final result = await client.day(
        formatCatalogDate(date),
        limit: CatalogDayRail.railLimit,
        // Spremljena stranica je možda od jutros (prazan dan); kad
        // revalidacija donese drukčiju, razriješi ispočetka.
        onUpdate: (_) {
          if (mounted) unawaited(_resolve());
        },
      );
      if (!mounted || generation != _generation) return;
      final page = result.page;
      if (page == null) {
        // Katalog nije dostupan (ili kaže da datum ne valja): nema raila.
        log('CatalogDayRail: katalog nije dostupan, rail skriven');
        _show(null);
        return;
      }
      if (page.isEmpty) continue;
      final resolved = _Resolved(today, date, page);
      if (page.items.length >= CatalogDayRail.minEpisodes) {
        _show(resolved);
        return;
      }
      newestNonEmpty ??= resolved;
    }
    if (newestNonEmpty != null) {
      _show(newestNonEmpty);
      return;
    }
    log(
      'CatalogDayRail: danas i ${CatalogDayRail.maxDaysBack} dana unatrag '
      'bez epizoda, rail skriven',
    );
    _show(null);
  }

  void _show(_Resolved? resolved) {
    CatalogDayRail._memo = resolved;
    if (_shown == resolved) return;
    setState(() => _shown = resolved);
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    if (shown == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final dateParam = formatCatalogDate(shown.date);

    return Semantics(
      identifier: 'home-catalog-day-rail',
      container: true,
      child: EpisodesRail(
        eyebrow: catalogDayRailEyebrow(context, l, shown.date, shown.today),
        isMobile: widget.isMobile,
        seeAllLabel: l.commonSeeAll,
        onSeeAll: () => drillDown(context, '/dani/$dateParam'),
        cards: [
          for (final card in shown.page.items)
            EpisodeRailCard(
              title: card.displayTitle,
              subtitle: card.channel?.name,
              // Kanal (i Tier 2, od S10) ima `/c/` rutu: ime vodi na nj.
              onSubtitleTap: card.channel?.hasChannelRoute == true
                  ? () => drillDown(context, '/c/${card.channel!.routeSlug}')
                  : null,
              // Thumbnail uvijek s našeg CDN-a (ytimg URL-ovi ruše CORS na webu).
              thumbnailUrl: CdnConfig.thumbnailUrl(card.id),
              dateLabel: card.date,
              width: widget.isMobile ? 180 : 220,
              shareUrl: () => episodeShareUrl(
                card.id,
                lang: shareLanguageForVideo(card.id),
              ),
              prefetchEpisodeId: card.id,
              onTap: () => widget.onVideoTap(card.id),
            ),
        ],
      ),
    );
  }
}
