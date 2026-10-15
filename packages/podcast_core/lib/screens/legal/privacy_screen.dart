import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../brand/app_brand.dart';
import 'legal_page_scaffold.dart';

/// Placeholder za /privacy — potreban za Google OAuth consent screen.
/// Konacni tekst dolazi kasnije; trenutno samo opisuje sto se sprema.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final body = theme.textTheme.bodyLarge?.copyWith(height: 1.6);

    return LegalPageScaffold(
      title: l.legalPrivacyTitle,
      children: [
        Text(
          l.legalLastUpdated('15. listopada 2026.'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          AppBrand.config.flags.domainScore
              ? l.legalPrivacyIntro(AppBrand.config.appName)
              : l.legalPrivacyIntroGeneric(AppBrand.config.appName),
          style: body,
        ),
        const SizedBox(height: 24),
        Text(l.legalPrivacyDataTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(l.legalPrivacyDataBody(AppBrand.config.contactEmail), style: body),
        const SizedBox(height: 24),
        Text(l.legalPrivacyAnalyticsTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          l.legalPrivacyAnalyticsBody(AppBrand.config.contactEmail),
          style: body,
        ),
        const SizedBox(height: 24),
        Text(l.legalContactTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          l.legalPrivacyContactBody(AppBrand.config.contactEmail),
          style: body,
        ),
        const SizedBox(height: 48),
      ],
    );
  }
}
