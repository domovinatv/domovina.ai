import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../src/log.dart' show appVersion;
import '../../brand/app_brand.dart';
import '../../models/channel_index.dart';
import '../../services/update_notifier.dart';
import '../../l10n/app_localizations.dart';

import '../../theme/typography.dart';
import '../../router/nav.dart';

/// 3-kolonski footer na dnu home screen-a.
///
/// Kolone:
/// - O PROJEKTU — kratak opis aplikacije
/// - LINKOVI — kontakt (mailto), ostalo "Uskoro" disabled
/// - STATISTIKE — agregirane vrijednosti iz `ChannelIndex` (broj kanala,
///   epizoda, sati, prosjecni Magisterium score)
///
/// Verzija + copyright + atribut na samom dnu. Mobile (<700px): kolone su
/// vertikalno slozene.
class HomeFooter extends StatelessWidget {
  final List<ChannelSummary> channels;

  const HomeFooter({super.key, required this.channels});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final isMobile = MediaQuery.of(context).size.width < 700;

    final totalEpisodes =
        channels.fold<int>(0, (sum, c) => sum + c.videoCount);
    final totalHours =
        channels.fold<int>(0, (sum, c) => sum + c.totalDurationSeconds) ~/
            3600;
    final scoredChannels =
        channels.where((c) => c.avgMagisteriumScore != null).toList();
    final avgScore = scoredChannels.isEmpty
        ? null
        : (scoredChannels.fold<int>(
                    0, (sum, c) => sum + c.avgMagisteriumScore!) /
                scoredChannels.length)
            .round();

    return Container(
      margin: const EdgeInsets.only(top: 32),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: 24,
        vertical: isMobile ? 32 : 48,
      ),
      child: Column(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _aboutColumn(theme, l),
                      const SizedBox(height: 28),
                      _linksColumn(theme),
                      const SizedBox(height: 28),
                      _statsColumn(theme, l,
                          totalEpisodes: totalEpisodes,
                          totalHours: totalHours,
                          avgScore: avgScore),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _aboutColumn(theme, l)),
                      const SizedBox(width: 32),
                      Expanded(child: _linksColumn(theme)),
                      const SizedBox(width: 32),
                      Expanded(
                          child: _statsColumn(theme, l,
                              totalEpisodes: totalEpisodes,
                              totalHours: totalHours,
                              avgScore: avgScore)),
                    ],
                  ),
          ),
          const SizedBox(height: 32),
          Divider(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            height: 1,
          ),
          const SizedBox(height: 16),
          _bottomRow(context, theme, isMobile),
        ],
      ),
    );
  }

  Widget _columnHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 2,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: AppTypography.eyebrowStyle(theme.colorScheme).copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _aboutColumn(ThemeData theme, AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _columnHeader(theme, l.homeFooterAbout),
        Text(
          AppBrand.config.flags.domainScore
              ? l.homeFooterAboutText(AppBrand.config.appName)
              : l.homeFooterAboutTextGeneric(AppBrand.config.appName),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.6,
          ),
        ),
      ],
    );
  }

  Widget _linksColumn(ThemeData theme) {
    return Builder(builder: (context) {
      final l = AppLocalizations.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _columnHeader(theme, l.homeFooterLinks),
          _link(
            theme,
            l,
            label: l.homeFooterSuggestEpisode,
            onTap: () => _launchMail(
              'stepanic.matija@gmail.com',
              subject: l.homeFooterEpisodeSuggestionSubject(
                AppBrand.config.appName,
              ),
            ),
          ),
          _link(
            theme,
            l,
            label: l.homeFooterContact,
            onTap: () => _launchMail('stepanic.matija@gmail.com'),
          ),
          _link(
            theme,
            l,
            label: 'GitHub',
            onTap: () => _launchUrl(AppBrand.config.sourceCodeUrl),
          ),
          _link(
            theme,
            l,
            label: l.homeFooterPrivacy,
            onTap: () => drillDown(context, '/privacy'),
          ),
          _link(
            theme,
            l,
            label: l.homeFooterTerms,
            onTap: () => drillDown(context, '/terms'),
          ),
        ],
      );
    });
  }

  Widget _statsColumn(
    ThemeData theme,
    AppLocalizations l, {
    required int totalEpisodes,
    required int totalHours,
    required int? avgScore,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _columnHeader(theme, l.homeFooterStats),
        _stat(theme, '${channels.length}',
            l.homeFooterStatChannels(channels.length)),
        const SizedBox(height: 6),
        _stat(theme, _formatNumber(totalEpisodes),
            l.homeFooterStatEpisodes(totalEpisodes)),
        const SizedBox(height: 6),
        _stat(theme, _formatNumber(totalHours),
            l.homeFooterStatHours(totalHours)),
        if (avgScore != null && AppBrand.config.flags.domainScore) ...[
          const SizedBox(height: 6),
          _stat(theme, '$avgScore', l.homeFooterStatAvgScore),
        ],
      ],
    );
  }

  Widget _stat(ThemeData theme, String value, String label) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$value  ',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          TextSpan(
            text: label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _link(
    ThemeData theme,
    AppLocalizations l, {
    required String label,
    VoidCallback? onTap,
    bool comingSoon = false,
  }) {
    final disabled = comingSoon || onTap == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: disabled ? null : onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: disabled
                    ? theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.5)
                    : theme.colorScheme.onSurface,
                decoration:
                    disabled ? null : TextDecoration.underline,
                decorationColor: theme.colorScheme.onSurface
                    .withValues(alpha: 0.3),
              ),
            ),
            if (comingSoon) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
                child: Text(
                  l.homeFooterSoon,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 9,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bottomRow(BuildContext context, ThemeData theme, bool isMobile) {
    final l = AppLocalizations.of(context);
    final children = [
      _versionPill(theme),
      _smallText(
          theme,
          l.homeFooterCopyright(
              DateTime.now().year, AppBrand.config.appName)),
      _smallText(theme, l.homeFooterMadeIn),
    ];
    if (isMobile) {
      return Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: children,
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        children[0],
        const SizedBox(width: 16),
        _dot(theme),
        const SizedBox(width: 16),
        children[1],
        const SizedBox(width: 16),
        _dot(theme),
        const SizedBox(width: 16),
        children[2],
      ],
    );
  }

  Widget _versionPill(ThemeData theme) {
    return GestureDetector(
      onTap: kIsWeb ? () => hardReload() : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'v$appVersion',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant
                  .withValues(alpha: 0.7),
              fontFamily: 'monospace',
            ),
          ),
          if (kIsWeb) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.refresh,
              size: 12,
              color: theme.colorScheme.onSurfaceVariant
                  .withValues(alpha: 0.6),
            ),
          ],
        ],
      ),
    );
  }

  Widget _smallText(ThemeData theme, String text) {
    return Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
    );
  }

  Widget _dot(ThemeData theme) {
    return Container(
      width: 3,
      height: 3,
      decoration: BoxDecoration(
        color:
            theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        shape: BoxShape.circle,
      ),
    );
  }

  String _formatNumber(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  Future<void> _launchMail(String email, {String? subject}) async {
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: subject != null ? {'subject': subject} : null,
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
