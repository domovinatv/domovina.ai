import '../../brand/app_brand.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../services/cdn_config.dart';
import '../../l10n/app_localizations.dart';

import '../../services/favorites_service.dart';
import '../../theme/typography.dart';
import '../../widgets/cached_thumbnail.dart';
import 'home_feed.dart';
import '../../router/nav.dart';
import '../../widgets/prefetch_on_intent.dart';

/// Split hero (slika lijevo, tekst desno) bira se za `isMobile == false`,
/// tj. od 600 px širine — a to uključuje i mobitel u landscapeu (iPhone SE
/// 667 pt, 12 mini 812 pt). S fiksnom slikom od 460 px tekstu je ondje
/// ostajalo 120–260 px i eyebrow/CTA retci su probijali rub (smoke test
/// 13.10.2026., `integration_test/smoke_test.dart`). Slika zato uzima
/// najviše 40 % širine; na desktopu (≥ 1150 px) ostaje 460 px kao prije.
/// [HeroSkeleton] koristi istu funkciju — visine moraju ostati jednake.
double heroSplitImageWidth(double maxWidth) =>
    (maxWidth * 0.4).clamp(0.0, 460.0);

/// Unutarnji razmak teksta u split heroju; uži split štedi 16 px.
EdgeInsets heroSplitTextPadding(double maxWidth) => maxWidth >= 1000
    ? const EdgeInsets.fromLTRB(28, 24, 28, 24)
    : const EdgeInsets.fromLTRB(20, 20, 20, 20);

/// Editorial hero sekcija — split layout (slika lijevo, tekst desno) na desktop,
/// stack na mobile. Compact dimenzije — slika je 16:9 ograničena na 480px wide
/// pa hero nikad nije visok preko ~290px.
///
/// Desktop layout:
/// ```
/// ┌─────────────────┬───────────────────────────┐
/// │                 │  ISTAKNUTO                │
/// │  [thumb 16:9]   │  Naslov u serifu          │
/// │                 │  Channel · 2 dana · 1h    │
/// │                 │  [▶ Slušaj]  [♡ Spremi]   │
/// └─────────────────┴───────────────────────────┘
/// ```
///
/// Mobile layout:
/// ```
/// ┌────────────────────────┐
/// │  [thumb 16:9 full]     │
/// ├────────────────────────┤
/// │  ISTAKNUTO             │
/// │  Naslov...             │
/// │  [Slušaj] [Spremi]     │
/// └────────────────────────┘
/// ```
class HeroSection extends StatelessWidget {
  final FeaturedPick featured;
  final VoidCallback onPlay;
  final bool isMobile;

  /// Vanjski razmak oko kartice. Default ostavlja zracni prostor ispod hero-a;
  /// [HeroCarousel] ga stisne jer kontrolnu traku (rotacija + dots) crta sam
  /// ispod kartice.
  final EdgeInsets outerPadding;

  const HeroSection({
    super.key,
    required this.featured,
    required this.onPlay,
    required this.isMobile,
    this.outerPadding = const EdgeInsets.fromLTRB(16, 8, 16, 24),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return Padding(
      padding: outerPadding,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: theme.colorScheme.surfaceContainerLowest,
          child: PrefetchOnIntent(
            episodeId: featured.video.video.id,
            child: InkWell(
              onTap: onPlay,
              child: isMobile
                  ? _mobileLayout(theme, l)
                  : _desktopLayout(theme, l),
            ),
          ),
        ),
      ),
    );
  }

  /// Desktop split — slika lijevo ([heroSplitImageWidth]), tekst desno.
  Widget _desktopLayout(ThemeData theme, AppLocalizations l) {
    // LayoutBuilder IZVAN IntrinsicHeight — LayoutBuilder ne daje
    // intrinzične dimenzije.
    return LayoutBuilder(
      builder: (context, constraints) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: heroSplitImageWidth(constraints.maxWidth),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _coverImage(),
                    if (featured.video.video.magisteriumScore != null)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: _magisteriumPill(theme, light: true),
                      ),
                  ],
                ),
              ),
            ),
            // Tekst desno
            Expanded(
              child: Padding(
                padding: heroSplitTextPadding(constraints.maxWidth),
                child: _content(theme, l, light: false),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Mobile stack — slika gore, tekst ispod.
  Widget _mobileLayout(ThemeData theme, AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _coverImage(),
              if (featured.video.video.magisteriumScore != null)
                Positioned(
                  top: 12,
                  right: 12,
                  child: _magisteriumPill(theme, light: true),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: _content(theme, l, light: false),
        ),
      ],
    );
  }

  Widget _coverImage() {
    // CDN URL (ne `video.thumbnail` koji moze biti i.ytimg.com - CORS blok).
    // Hero puni širinu → CachedThumbnail uzima širinu ekrana kao gornju ogradu
    // i bira najveću varijantu (thumb-1280, ~71 KB umjesto 830 KB PNG-a).
    return CachedThumbnail(
      url: CdnConfig.thumbnailUrl(featured.video.video.id),
      fit: BoxFit.cover,
      errorFallbackBuilder: (c) => _backdropFallback(Theme.of(c)),
    );
  }

  Widget _backdropFallback(ThemeData theme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.brandPrimary,
            AppTheme.brandPrimary.withValues(alpha: 0.7),
          ],
        ),
      ),
    );
  }

  Widget _content(ThemeData theme, AppLocalizations l, {required bool light}) {
    final video = featured.video.video;
    final channelName = featured.video.channelName;
    final textColor = light ? Colors.white : theme.colorScheme.onSurface;
    final subColor = light
        ? Colors.white.withValues(alpha: 0.85)
        : theme.colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Eyebrow + "Zašto?" info gumb
        Row(
          children: [
            Container(width: 24, height: 2, color: theme.colorScheme.tertiary),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                l.homeHeroEyebrow.toUpperCase(),
                style: AppTypography.eyebrowStyle(theme.colorScheme)
                    .copyWith(color: subColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _WhyButton(pick: featured, color: subColor),
          ],
        ),
        const SizedBox(height: 12),

        // Title
        Text(
          video.displayTitle,
          style: theme.textTheme.headlineMedium?.copyWith(
            color: textColor,
            height: 1.15,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 10),

        // Meta line
        Wrap(
          spacing: 10,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              channelName,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (video.date != null)
              Text(
                '·  ${_formatDate(video.date!, l)}',
                style: theme.textTheme.bodyMedium?.copyWith(color: subColor),
              ),
            if (video.durationDisplay != null)
              Text(
                '·  ${video.durationDisplay}',
                style: theme.textTheme.bodyMedium?.copyWith(color: subColor),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // CTA buttons — scaleDown je osigurač za uske širine: gumbi se
        // smanje umjesto da probiju rub (visina ostaje ista dok stanu).
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow, size: 20),
                label: Text(l.homeHeroListen),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.brandPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: AppTheme.brandRim(theme.brightness),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _SaveButton(
                video: featured.video,
                textColor: textColor,
                style: OutlinedButton.styleFrom(
                  foregroundColor: textColor,
                  side: BorderSide(color: textColor.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _magisteriumPill(ThemeData theme, {required bool light}) {
    final score = featured.video.video.magisteriumScore!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.church, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            '$score',
            style: theme.textTheme.labelMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String iso, AppLocalizations l) {
    try {
      final d = DateTime.parse(iso);
      final days = DateTime.now().difference(d).inDays;
      if (days == 0) return l.homeAgoToday;
      if (days == 1) return l.homeAgoYesterday;
      if (days < 7) return l.homeAgoDays(days);
      if (days < 30) return l.homeAgoWeeks((days / 7).floor());
      if (days < 365) return l.homeAgoMonths((days / 30).floor());
      return iso;
    } catch (_) {
      return iso;
    }
  }
}

/// Mali "Zasto?" gumb pored "ISTAKNUTO" eyebrow-a — otvara dialog s
/// objektivnim kriterijima zbog kojih je epizoda izabrana.
class _WhyButton extends StatelessWidget {
  final FeaturedPick pick;
  final Color color;

  const _WhyButton({required this.pick, required this.color});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _showWhyDialog(context, pick),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.help_outline, size: 11, color: color),
              const SizedBox(width: 4),
              Text(
                AppLocalizations.of(context).homeHeroWhyButton.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: color,
                  letterSpacing: 1.0,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showWhyDialog(BuildContext context, FeaturedPick pick) {
  showDialog<void>(
    context: context,
    builder: (ctx) => _WhyDialog(pick: pick),
  );
}

class _WhyDialog extends StatelessWidget {
  final FeaturedPick pick;

  const _WhyDialog({required this.pick});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      title: Row(
        children: [
          Container(width: 24, height: 2, color: theme.colorScheme.tertiary),
          const SizedBox(width: 10),
          Text(
            l.homeWhyDialogTitle.toUpperCase(),
            style: AppTypography.eyebrowStyle(theme.colorScheme),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _reasonHeadline(l, pick.reason),
              style: theme.textTheme.headlineSmall?.copyWith(height: 1.2),
            ),
            const SizedBox(height: 16),
            _factsTable(theme, l, pick),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.homeWhyAlgorithmHeading.toUpperCase(),
                    style: AppTypography.eyebrowStyle(theme.colorScheme),
                  ),
                  const SizedBox(height: 10),
                  _algorithmTiers(theme, l, pick.reason),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l.homeWhyDialogExplainer,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.homeWhyGotIt),
        ),
      ],
    );
  }

  String _reasonHeadline(AppLocalizations l, FeaturedReason reason) {
    switch (reason) {
      case FeaturedReason.hiQualityRecent:
        return l.homeReasonHeadlineHiQualityRecent;
      case FeaturedReason.hiQuality:
        return l.homeReasonHeadlineHiQuality;
      case FeaturedReason.anyMagisterium:
        return l.homeReasonHeadlineAnyMagisterium;
      case FeaturedReason.newest:
        return l.homeReasonHeadlineNewest;
    }
  }

  Widget _factsTable(ThemeData theme, AppLocalizations l, FeaturedPick pick) {
    final rows = <(String, String)>[
      (l.homeWhyFactChannel, pick.video.channelName),
      if (pick.magisteriumScore != null)
        (l.homeWhyFactScore, '${pick.magisteriumScore} / 100'),
      if (pick.daysAgo != null)
        (l.homeWhyFactPublished, _daysAgoLabel(l, pick.daysAgo!)),
      (
        l.homeWhyFactAiProcessing,
        (pick.video.video.pipeline?.hasMagisterium ?? false)
            ? (AppBrand.config.flags.domainScore
                  ? l.homeWhyFactAiYes
                  : l.homeWhyFactAiYesGeneric)
            : l.homeWhyFactAiNo,
      ),
      if (pick.combinedScore != null)
        (
          l.homeWhyFactWeight,
          l.homeWhyFactWeightValue(pick.combinedScore!.toStringAsFixed(1)),
        ),
      (l.homeWhyFactPool, l.homeWhyFactPoolValue(pick.candidatePool)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 140,
                  child: Text(
                    r.$1,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    r.$2,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _algorithmTiers(
    ThemeData theme,
    AppLocalizations l,
    FeaturedReason activeTier,
  ) {
    final tiers = [
      (FeaturedReason.hiQualityRecent, l.homeTier1Title, l.homeTier1Desc),
      (FeaturedReason.hiQuality, l.homeTier2Title, l.homeTier2Desc),
      (FeaturedReason.anyMagisterium, l.homeTier3Title, l.homeTier3Desc),
      (FeaturedReason.newest, l.homeTier4Title, l.homeTier4Desc),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final t in tiers)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 5),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: t.$1 == activeTier
                        ? theme.colorScheme.tertiary
                        : theme.colorScheme.outlineVariant,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.$2,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: t.$1 == activeTier
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: t.$1 == activeTier
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t.$3,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _daysAgoLabel(AppLocalizations l, int days) {
    if (days == 0) return l.homeAgoToday;
    if (days == 1) return l.homeAgoYesterday;
    if (days < 7) return l.homeAgoDays(days);
    if (days < 30) return l.homeAgoWeeks((days / 7).floor());
    if (days < 365) return l.homeAgoMonths((days / 30).floor());
    return l.homeAgoYears((days / 365).floor());
  }
}

/// „Spremi" na hero kartici — pravi favorit, ne placeholder.
///
/// Vlastiti state jer se ikona/labela mijenjaju odmah nakon tapa, a hero je
/// inače stateless. Sluša [FavoritesService] pa se osvježi i kad se favorit
/// makne drugdje (rail, `/favorites`, ekran epizode).
class _SaveButton extends StatefulWidget {
  final FeedVideo video;
  final Color textColor;
  final ButtonStyle style;

  const _SaveButton({
    required this.video,
    required this.textColor,
    required this.style,
  });

  @override
  State<_SaveButton> createState() => _SaveButtonState();
}

class _SaveButtonState extends State<_SaveButton> {
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    FavoritesService.instance.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(covariant _SaveButton old) {
    super.didUpdateWidget(old);
    if (old.video.video.id != widget.video.video.id) _load();
  }

  @override
  void dispose() {
    FavoritesService.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final v = await FavoritesService.instance.isFavorite(widget.video.video.id);
    if (mounted) setState(() => _saved = v);
  }

  Future<void> _toggle() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final added = await FavoritesService.instance.toggle(
      widget.video.video.id,
      title: widget.video.video.displayTitle,
      channelName: widget.video.channelName,
    );
    if (!mounted) return;
    // SnackBar samo kao potvrda korisnikove radnje (vidi CLAUDE.md — nudge).
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(added ? l.favoritesSaved : l.favoritesRemoved),
        duration: const Duration(seconds: 2),
        action: added
            ? SnackBarAction(
                label: l.commonSeeAll,
                onPressed: () => drillDown(context, '/favorites'),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return OutlinedButton.icon(
      onPressed: _toggle,
      icon: Icon(
        _saved ? Icons.favorite : Icons.favorite_border,
        size: 18,
        color: _saved ? AppTheme.brandAccent : widget.textColor,
      ),
      label: Text(_saved ? l.favoritesSaved : l.commonSave),
      style: widget.style,
    );
  }
}
