/// Ruta značajke kanala koju vlasnik može isključiti (lanac
/// `postavke-kanala/`, S5): `/c/:slug/doniraj` (`donations`),
/// `/c/:slug/oglasi` i `/v/:id/sponzoriraj` (`paid_sponsor_moments`).
///
/// Isključena značajka → „Vlasnik kanala je isključio ovu mogućnost.” umjesto
/// zida ili izloga; povučen/obrisan kanal → [ChannelGoneView]. Kanal bez UC-a
/// ili bez retka postavki → [child] kao prije (fail-open, tvrdi uvjet 4).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../models/channel_detail.dart' show kYoutubeChannelIdPattern;
import '../router/nav.dart';
import '../services/channel_cache.dart';
import '../services/channel_visibility.dart';
import 'channel_gone_view.dart';

class ChannelFeatureOffGuard extends StatefulWidget {
  const ChannelFeatureOffGuard({
    super.key,
    required this.featureKey,
    required this.child,
    this.channelId,
    this.ucId,
  });

  /// Ključ postavki (`donations`, `paid_sponsor_moments`).
  final String featureKey;

  /// Naš interni id kanala (`domovina_tv`); UC se traži u indexu.
  final String? channelId;

  /// `UC…` kad ga ruta već zna (`?uc=`); ima prednost pred [channelId].
  final String? ucId;

  final Widget child;

  @override
  State<ChannelFeatureOffGuard> createState() => _ChannelFeatureOffGuardState();
}

class _ChannelFeatureOffGuardState extends State<ChannelFeatureOffGuard> {
  late final ChannelVisibility _vis;
  bool _settled = false;
  String? _uc;

  @override
  void initState() {
    super.initState();
    _vis = ChannelVisibility.instance;
    _vis.addListener(_onChange);
    unawaited(_resolve());
  }

  @override
  void dispose() {
    _vis.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _resolve() async {
    final given = widget.ucId;
    String? uc = given != null && kYoutubeChannelIdPattern.hasMatch(given)
        ? given
        : null;
    final id = widget.channelId;
    if (uc == null && id != null) {
      uc = channelCache.ucFor(id);
      if (uc == null) {
        try {
          await channelCache.loadIndex();
        } catch (_) {
          // Index nedostupan → UC nepoznat → fail-open.
        }
        uc = channelCache.ucFor(id);
      }
    }
    await _vis.ready();
    if (!mounted) return;
    setState(() {
      _uc = uc;
      _settled = true;
    });
  }

  void _back(BuildContext context) {
    if (GoRouter.maybeOf(context) != null) {
      backUp(context);
    } else {
      unawaited(Navigator.maybePop(context));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_settled) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final uc = _uc;
    if (_vis.isEnabled(uc, widget.featureKey)) return widget.child;
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: l.commonBack,
          onPressed: () => _back(context),
        ),
      ),
      body: _vis.isGone(uc)
          ? ChannelGoneView(
              ucId: uc,
              isDeleted: _vis.isDeleted(uc),
              deletedAt: _vis.deletedAt(uc),
            )
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.block_outlined,
                      size: 48,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l.channelFeatureOffByOwner,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
