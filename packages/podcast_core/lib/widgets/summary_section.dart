import 'package:flutter/material.dart';
import '../models/person_hub.dart';
import '../models/podcast_summary.dart';
import '../services/episode_language.dart';
import '../l10n/app_localizations.dart';
import '../router/nav.dart';

class SummarySection extends StatelessWidget {
  final PodcastSummary summary;

  const SummarySection({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = summary.summary;
    final lang = EpisodeLanguageScope.of(context);
    final isEn = lang == EpisodeLanguage.en;

    final l = AppLocalizations.of(context);
    final abstractText = pickLang(lang, s.abstractHr, s.abstractEn);
    final keyTopics = pickLangList(lang, s.keyTopics, s.keyTopicsEn);
    final keyPoints = pickLangList(lang, s.keyPoints, s.keyPointsEn);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Abstract
          _SectionTitle(title: l.sectionSummary),
          const SizedBox(height: 8),
          Text(abstractText, style: theme.textTheme.bodyMedium?.copyWith(height: 1.6)),
          const SizedBox(height: 24),

          // Key Topics
          _SectionTitle(title: l.sectionKeyTopics),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: keyTopics
                .map((t) => Chip(
                      label: Text(t, style: theme.textTheme.labelSmall),
                      side: BorderSide(color: theme.colorScheme.outline),
                      backgroundColor: Colors.transparent,
                      padding: EdgeInsets.zero,
                    ))
                .toList(),
          ),
          const SizedBox(height: 24),

          // Speakers
          _SectionTitle(title: l.sectionSpeakers),
          const SizedBox(height: 10),
          ...s.speakers.map((sp) {
            // Anonymous govornik (npr. host se ne predstavi) → suggested_name
            // == role. Tada prikazi samo capitalized roleLabel umjesto duplog.
            final name = sp.displayNameFor(isEn);
            final roleLabel = isEn ? sp.roleLabelEn() : sp.roleLabel;
            final primary = name ?? roleLabel;
            final row = Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    primary.isNotEmpty ? primary[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(primary,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    if (name != null && roleLabel.isNotEmpty)
                      Text(
                        roleLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ],
            );
            // Govornik s pravim imenom → tap na profil (/p/:slug). Anonimni
            // role-labeli nisu u bazi pa se ne linkaju.
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: name == null
                  ? row
                  : InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () =>
                          drillDown(context,
                              // Profil osobe je ključan po izvornom (HR) imenu.
                              '/p/${personSlug(sp.suggestedName.trim())}'),
                      child: row,
                    ),
            );
          }),
          const SizedBox(height: 24),

          // Key Points
          _SectionTitle(title: l.sectionKeyTakeaways),
          const SizedBox(height: 10),
          ...keyPoints.asMap().entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${e.key + 1}',
                          style: TextStyle(
                            color: theme.colorScheme.onPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(e.value,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(height: 1.5)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
    );
  }
}
