/// Prikaz kanala ili epizode koju je vlasnik povukao ili trajno obrisao
/// (lanac `postavke-kanala/`, S5, ključ `channel_enabled`).
///
/// Tvrdi uvjet 3 plana: povučen ili obrisan sadržaj NIKAD nije 404 ni prazan
/// kanal s „0 epizoda”, nego ovaj prikaz. Dijele ga `/c/<slug>` (web i TV) i
/// `/v/<id>` (ekran epizode), pa je API stabilan:
/// `ChannelGoneView(ucId:, deletedAt:, isDeleted:, youtubeUrl:)`.
///
/// - povučen: naslov + „Snimka je i dalje dostupna na YouTubeu” + „Otvori na
///   YouTubeu” + „Na naslovnicu”;
/// - obrisan: „Kanal je trajno uklonjen s domovina.ai {datum}.” + „Na
///   naslovnicu”, bez avatara, epizoda i poveznice (vlasnik je tražio trajno
///   uklanjanje, pa ga ne usmjeravamo dalje).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';

class ChannelGoneView extends StatelessWidget {
  const ChannelGoneView({
    super.key,
    this.ucId,
    this.deletedAt,
    this.isDeleted = false,
    this.youtubeUrl,
    this.onBackHome,
    this.autofocus = false,
  });

  /// `UC…` kanala; iz njega se gradi poveznica kad [youtubeUrl] nije zadan.
  final String? ucId;

  /// Trenutak brisanja (tombstone). Samo uz [isDeleted].
  final DateTime? deletedAt;

  /// `true` = trajno obrisan, `false` = povučen.
  final bool isDeleted;

  /// Izravna poveznica (npr. video na `/v/<id>`); zadano kanal po [ucId].
  final String? youtubeUrl;

  /// Zamjena za `context.go('/')` (testovi, TV).
  final VoidCallback? onBackHome;

  /// TV (D-pad): prvi gumb dobiva fokus.
  final bool autofocus;

  /// Poveznica koju gumb otvara, ili `null` kad je nema (obrisan kanal, kanal
  /// bez UC-a i bez [youtubeUrl]).
  String? get resolvedYoutubeUrl {
    if (isDeleted) return null;
    final direct = youtubeUrl;
    if (direct != null && direct.isNotEmpty) return direct;
    final uc = ucId;
    if (uc == null || uc.isEmpty) return null;
    return 'https://www.youtube.com/channel/$uc';
  }

  /// `dd. mm. gggg.` u lokalnom vremenu (isti zapis za HR i EN).
  static String formatDate(DateTime at) {
    final d = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}. ${two(d.month)}. ${d.year}.';
  }

  /// Naslov prikaza (za ekrane koji ga trebaju i u app baru ili OG-u).
  static String titleFor(
    AppLocalizations l, {
    required bool isDeleted,
    DateTime? deletedAt,
  }) {
    if (!isDeleted) return l.channelGoneWithdrawn;
    if (deletedAt == null) return l.channelGoneDeletedNoDate;
    // Datum nosi završnu točku („05. 11. 2026.”), pa ARB rečenica nema svoju.
    return l.channelGoneDeleted(formatDate(deletedAt));
  }

  void _goHome(BuildContext context) {
    final cb = onBackHome;
    if (cb != null) return cb();
    // Prazno/stanje greške smije `go('/')` (CLAUDE.md, routing).
    GoRouter.maybeOf(context)?.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final url = resolvedYoutubeUrl;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isDeleted
                    ? Icons.delete_outline
                    : Icons.visibility_off_outlined,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                titleFor(l, isDeleted: isDeleted, deletedAt: deletedAt),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (!isDeleted) ...[
                const SizedBox(height: 8),
                Text(
                  l.channelGoneWithdrawnBody,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (url != null)
                    FilledButton.icon(
                      autofocus: autofocus,
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: Text(l.channelGoneOpenYouTube),
                      onPressed: () => unawaited(
                        launchUrl(
                          Uri.parse(url),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                    ),
                  OutlinedButton.icon(
                    autofocus: autofocus && url == null,
                    icon: const Icon(Icons.home_outlined, size: 18),
                    label: Text(l.channelGoneBackHome),
                    onPressed: () => _goHome(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
