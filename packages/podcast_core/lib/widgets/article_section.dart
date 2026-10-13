import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/markdown_brand.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/podcast_article.dart';
import '../models/magisterium_data.dart';
import '../models/sponsored_moment.dart';
import '../models/sponsors_in_video.dart';
import '../services/sponsored_moments_controller.dart';
import '../services/cdn_config.dart';
import '../services/episode_language.dart';
import '../services/share_links.dart';
import 'magisterium_section.dart';
import 'person_needle_highlight.dart';
import 'citation_helpers.dart';
import 'clip_share_sheet.dart';
import '../services/clip_service.dart';
import '../services/open_url.dart';
import '../l10n/app_localizations.dart';
import '../services/deferred_screenshots.dart';
import 'cached_thumbnail.dart';
import 'sponsored_moment_widgets.dart';
import 'sponsors_in_video_section.dart';

class ArticleSection extends StatelessWidget {
  final PodcastArticle article;
  final String youtubeId;
  final Map<String, GlobalKey> sectionKeys;
  final void Function(String timestamp)? onPlayTap;
  final MagisteriumData? magisterium;

  /// Kad false (audio-only epizode), sekcije ne renderiraju screenshot blok.
  final bool showScreenshot;

  /// Person-highlight marker (dolazak s /p/ profila preko `?p=<slug>`):
  /// sekcija s ovim timestampom dobiva crvenu pill oznaku, a sva pojavljivanja
  /// imena u tekstu SVIH sekcija dobiju inline needle highlight.
  final String? highlightTimestamp;

  /// Ime osobe — needle za inline highlight (sve sekcije) + tekst pill oznake
  /// (samo [highlightTimestamp] sekcija).
  final String? highlightPersonName;

  /// True kad osoba stvarno GOVORI (diarizirani govornik) → pill "X govori
  /// ovdje"; false kad se samo spominje → pill "Ovdje se spominje: X".
  final bool highlightSpeaks;

  /// Poruke sponzora po timestampu sekcije (vidi
  /// [SponsorsInVideo.marksBySection]) i „Poslušaj" za njih.
  final Map<String, List<SponsorInVideoMark>> sponsorMarks;
  final void Function(SponsorInVideoSegment segment)? onSponsorListen;

  /// PLAĆENI trenuci po timestampu sekcije (vidi
  /// [SponsoredMoments.marksBySection]) — zaseban sloj od [sponsorMarks].
  final Map<String, List<SponsoredMoment>> sponsoredMarks;
  final SponsoredMomentsController? sponsoredMoments;
  final void Function(SponsoredMoment moment)? onSponsoredListen;

  const ArticleSection({
    super.key,
    required this.article,
    required this.youtubeId,
    required this.sectionKeys,
    this.onPlayTap,
    this.magisterium,
    this.showScreenshot = true,
    this.highlightTimestamp,
    this.highlightPersonName,
    this.highlightSpeaks = true,
    this.sponsorMarks = const {},
    this.onSponsorListen,
    this.sponsoredMarks = const {},
    this.sponsoredMoments,
    this.onSponsoredListen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final title = l.sectionArticle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...article.iterations.map(
          (iter) => _IterationBlock(
            iteration: iter,
            youtubeId: youtubeId,
            sectionKeys: sectionKeys,
            onPlayTap: onPlayTap,
            magisterium: magisterium,
            showScreenshot: showScreenshot,
            highlightTimestamp: highlightTimestamp,
            highlightPersonName: highlightPersonName,
            highlightSpeaks: highlightSpeaks,
            sponsorMarks: sponsorMarks,
            onSponsorListen: onSponsorListen,
            sponsoredMarks: sponsoredMarks,
            sponsoredMoments: sponsoredMoments,
            onSponsoredListen: onSponsoredListen,
          ),
        ),
      ],
    );
  }
}

class _IterationBlock extends StatelessWidget {
  final ArticleIteration iteration;
  final String youtubeId;
  final Map<String, GlobalKey> sectionKeys;
  final void Function(String timestamp)? onPlayTap;
  final MagisteriumData? magisterium;
  final bool showScreenshot;
  final String? highlightTimestamp;
  final String? highlightPersonName;
  final bool highlightSpeaks;
  final Map<String, List<SponsorInVideoMark>> sponsorMarks;
  final void Function(SponsorInVideoSegment segment)? onSponsorListen;

  /// PLAĆENI trenuci po timestampu sekcije (vidi
  /// [SponsoredMoments.marksBySection]) — zaseban sloj od [sponsorMarks].
  final Map<String, List<SponsoredMoment>> sponsoredMarks;
  final SponsoredMomentsController? sponsoredMoments;
  final void Function(SponsoredMoment moment)? onSponsoredListen;

  const _IterationBlock({
    required this.iteration,
    required this.youtubeId,
    required this.sectionKeys,
    required this.onPlayTap,
    this.magisterium,
    this.showScreenshot = true,
    this.highlightTimestamp,
    this.highlightPersonName,
    this.highlightSpeaks = true,
    this.sponsorMarks = const {},
    this.onSponsorListen,
    this.sponsoredMarks = const {},
    this.sponsoredMoments,
    this.onSponsoredListen,
  });

  @override
  Widget build(BuildContext context) {
    // Nizak ekran (mobitel u landscapeu, ~340 px visine): razmak od 80 + 56 px
    // između sekcija pojede trećinu ekrana pa se vidi više praznine nego
    // teksta. Tamo ga stišćemo.
    final compact = MediaQuery.sizeOf(context).height < 500;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ArticleIterationHeader(iteration: iteration),
          const SizedBox(height: 16),
          ...iteration.sections.asMap().entries.map((entry) {
            final i = entry.key;
            final sec = entry.value;
            // Clip window za sekciju: start = ova sekcija, end = iduća sekcija
            // (ili kraj iteracije za zadnju). Null kad nema videa (audio-only).
            final endSec = i + 1 < iteration.sections.length
                ? ClipService.hmsToSeconds(
                    iteration.sections[i + 1].screenshotTimestamp,
                  )
                : ClipService.hmsToSeconds(iteration.endTime);
            // Leading razmak (top:80) je IZVAN KeyedSubtree-a da scroll-to-section
            // (localToGlobal na keyed box) cilja sam sadrzaj sekcije, a ne prazni
            // padding iznad njega — inace naslov sjedne ~80px prenisko (mobile).
            // Isti razlog kao paralelni desktop layout koji padding drzi izvan keya.
            return Padding(
              padding: EdgeInsets.only(top: compact ? 32 : 80),
              child: KeyedSubtree(
                key: sectionKeys[sec.screenshotTimestamp],
                child: ArticleSectionCard(
                  section: sec,
                  youtubeId: youtubeId,
                  onPlayTap: onPlayTap,
                  sectionMagisterium: magisterium?.forTimestamp(
                    sec.screenshotTimestamp,
                  ),
                  padding: EdgeInsets.only(bottom: compact ? 24 : 56),
                  showScreenshot: showScreenshot,
                  clipEndSec: showScreenshot ? endSec : null,
                  personHighlight: sec.screenshotTimestamp == highlightTimestamp
                      ? highlightPersonName
                      : null,
                  personHighlightSpeaks: highlightSpeaks,
                  personNeedle: highlightPersonName,
                  sponsorMarks:
                      sponsorMarks[sec.screenshotTimestamp] ?? const [],
                  onSponsorListen: onSponsorListen,
                  sponsoredMarks:
                      sponsoredMarks[sec.screenshotTimestamp] ?? const [],
                  sponsoredMoments: sponsoredMoments,
                  onSponsoredListen: onSponsoredListen,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Iteracijski header — broj iteracije + tema. Public da ga dijele
/// [ArticleSection] (vertikalni clanak) i ParallelArticleView (desktop paralelni
/// prikaz) bez dupliciranja stila.
class ArticleIterationHeader extends StatelessWidget {
  final ArticleIteration iteration;

  const ArticleIterationHeader({super.key, required this.iteration});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = EpisodeLanguageScope.of(context);
    final themeText = pickLang(lang, iteration.theme, iteration.themeEn);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: AppTheme.brandPrimary,
              borderRadius: BorderRadius.circular(4),
              border: Border.fromBorderSide(
                AppTheme.brandRim(theme.brightness),
              ),
            ),
            child: Center(
              child: Text(
                '${iteration.iterationNumber}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              themeText,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ispod ove širine kartice naslov sekcije ide u vlastiti red.
const double _kTitleOwnLineBelow = 520;

class ArticleSectionCard extends StatefulWidget {
  final PodcastSection section;
  final String youtubeId;
  final void Function(String timestamp)? onPlayTap;
  final SectionMagisterium? sectionMagisterium;

  /// Kad false, ne renderira inline teolosku procjenu (koristi se u paralelnom
  /// desktop layoutu gdje Magisterium ima zaseban stupac u istom redu).
  final bool showInlineMagisterium;

  /// Vanjski padding kartice. Default ostavlja prostor izmedu sekcija; paralelni
  /// layout prosljeduje EdgeInsets.zero (razmak hendla parent red).
  final EdgeInsetsGeometry padding;

  /// Kad false, ne renderira screenshot blok (audio-only epizode nemaju
  /// screenshote — inače bi se vidio prazan sivi placeholder).
  final bool showScreenshot;

  /// Kraj clip-raspona za ovu sekciju (početak = screenshot_timestamp). Kad je
  /// non-null i > start, header dobiva gumb za preuzimanje/dijeljenje isječka.
  /// Null za audio-only ili kad raspon nije poznat (cutter treba `video_h264.mp4`).
  final int? clipEndSec;

  /// Ime osobe za person-highlight pill (bijeli tekst na crvenoj pozadini)
  /// iznad naslova sekcije. Non-null samo na sekciji na koju je korisnik
  /// doveden s profila osobe (`/v/<id>/t/<sec>?p=<slug>`).
  final String? personHighlight;

  /// Varijanta pill teksta: true → "X govori ovdje" (diarizirani govornik),
  /// false → "Ovdje se spominje: X" (osoba se samo spominje).
  final bool personHighlightSpeaks;

  /// Ime osobe za inline needle highlight — SVA pojavljivanja imena u tekstu
  /// ove sekcije označe se bijelo-na-crveno (vidi person_needle_highlight.dart).
  /// Za razliku od [personHighlight], postavlja se na SVIM sekcijama.
  final String? personNeedle;

  /// Poruke sponzora koje počinju u ovoj sekciji — prigušena oznaka iznad
  /// naslova s gumbom „Poslušaj" (vidi [SponsorsInVideoSectionMark]).
  final List<SponsorInVideoMark> sponsorMarks;
  final void Function(SponsorInVideoSegment segment)? onSponsorListen;

  /// Plaćeni trenuci koji počinju u ovoj sekciji (sidro je vrijeme).
  final List<SponsoredMoment> sponsoredMarks;
  final SponsoredMomentsController? sponsoredMoments;
  final void Function(SponsoredMoment moment)? onSponsoredListen;

  const ArticleSectionCard({
    super.key,
    required this.section,
    required this.youtubeId,
    this.onPlayTap,
    this.sectionMagisterium,
    this.showInlineMagisterium = true,
    this.padding = const EdgeInsets.only(bottom: 56, top: 80),
    this.showScreenshot = true,
    this.clipEndSec,
    this.personHighlight,
    this.personHighlightSpeaks = true,
    this.personNeedle,
    this.sponsorMarks = const [],
    this.onSponsorListen,
    this.sponsoredMarks = const [],
    this.sponsoredMoments,
    this.onSponsoredListen,
  });

  @override
  State<ArticleSectionCard> createState() => _ArticleSectionCardState();
}

class _ArticleSectionCardState extends State<ArticleSectionCard> {
  bool _citationsExpanded = false;

  /// True kad screenshot za ovu sekciju ne postoji (404) — tada kolabiramo
  /// cijeli blok da se ne vidi prazan sivi placeholder.
  bool _screenshotFailed = false;

  int _tsToSeconds(String ts) {
    final parts = ts.split(':').map(int.parse).toList();
    if (parts.length == 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
    return 0;
  }

  void _copyShareLink(BuildContext context) {
    final l = AppLocalizations.of(context);
    final seconds = _tsToSeconds(widget.section.screenshotTimestamp);
    // Path-based URL → distinct crawler cache entry po timestampu, i `/en` kad
    // korisnik čita engleski — vidi services/share_links.dart.
    final url = episodeShareUrl(
      widget.youtubeId,
      seconds: seconds,
      lang: EpisodeLanguageScope.of(context),
    );
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.sectionLinkCopied(widget.section.screenshotTimestamp)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final section = widget.section;
    final mag = widget.sectionMagisterium;
    final lang = EpisodeLanguageScope.of(context);
    final subtitle = pickLang(lang, section.subtitle, section.subtitleEn);
    var content = pickLang(lang, section.content, section.contentEn);
    // Person-needle highlight: omotaj spomene imena u ⟦…⟧ markere koje custom
    // inline syntax renderira bijelo-na-crveno (vidi person_needle_highlight).
    final needle = widget.personNeedle;
    if (needle != null && needle.isNotEmpty) {
      content = markPersonMentions(content, needle);
    }
    final screenshotDesc = pickLang(
      lang,
      section.screenshotDescription,
      section.screenshotDescriptionEn,
    );
    final keywords = pickLangList(lang, section.keywords, section.keywordsEn);

    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Person-highlight marker — "X govori ovdje" (dolazak s /p/ profila).
          // Brand crvena (cs.tertiary = croRed) + bijeli tekst, namjerno upadljiv
          // da se odmah vidi ZAŠTO je korisnik doveden baš na ovu sekciju.
          if (widget.personHighlight != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.record_voice_over,
                      size: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        widget.personHighlightSpeaks
                            ? l.sectionPersonSpeaksHere(
                                widget.personHighlight!)
                            : l.sectionPersonMentionedHere(
                                widget.personHighlight!),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (widget.sponsorMarks.isNotEmpty)
            SponsorsInVideoSectionMark(
              marks: widget.sponsorMarks,
              onListen: widget.onSponsorListen,
            ),
          if (widget.sponsoredMarks.isNotEmpty)
            SponsoredMomentSectionMark(
              moments: widget.sponsoredMarks,
              controller: widget.sponsoredMoments,
              onListen: widget.onSponsoredListen,
            ),
          // Timestamp badge + play button + score badge + subtitle.
          // Na uskom stupcu (mobitel, landscape uz player) naslov ide u svoj
          // red preko cijele širine: stisnut uz ikone prelamao se u 3–4 retka,
          // a ispod ikona je ostajala praznina.
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Text(
                subtitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              );
              final controls = <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withAlpha(25),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: theme.colorScheme.primary.withAlpha(80),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    section.screenshotTimestamp,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                if (widget.onPlayTap != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.play_circle_outline,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        tooltip: l.sectionPlayFrom(section.screenshotTimestamp),
                        onPressed: () =>
                            widget.onPlayTap!(section.screenshotTimestamp),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.link,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      tooltip: l.sectionCopyLink,
                      onPressed: () => _copyShareLink(context),
                    ),
                  ),
                ),
                if (widget.clipEndSec != null &&
                    widget.clipEndSec! >
                        _tsToSeconds(section.screenshotTimestamp))
                  ClipShareButton(
                    videoId: widget.youtubeId,
                    startSec: _tsToSeconds(section.screenshotTimestamp),
                    endSec: widget.clipEndSec!,
                    title: subtitle,
                  ),
                if (mag?.score != null) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: MagisteriumSection.scoreColor(
                        mag!.score,
                      ).withAlpha(25),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: MagisteriumSection.scoreColor(
                          mag.score,
                        ).withAlpha(80),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.church,
                          size: 12,
                          color: MagisteriumSection.scoreColor(mag.score),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${mag.score}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: MagisteriumSection.scoreColor(mag.score),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ];
              if (constraints.maxWidth < _kTitleOwnLineBelow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Wrap, ne Row: u landscapeu na mobitelu stupac članka
                    // uz Magisterium i panel playera zna biti uži od svih
                    // kontrola (Android, smoke test 13.10.2026.: 2–12 px).
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      runSpacing: 4,
                      children: controls,
                    ),
                    const SizedBox(height: 6),
                    title,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ...controls,
                  const SizedBox(width: 6),
                  Expanded(child: title),
                ],
              );
            },
          ),
          // Screenshot — AspectRatio rezervira mjesto PRIJE async load-a slike.
          // Bez ovoga: section anchor scroll na page load promaši target jer
          // slike iznad load-aju asinkrono pa layout naraste poslije scrolla,
          // što je posebno loše na shared timestamp URL-ovima (mobile worst).
          // 16:9 odgovara originalnim screenshotima (1920×1080 PNG iz pipeline-a).
          // maxHeight 270 cap: na širim stupcima 16:9 puni širinu izgleda
          // predominantno (npr. 860px → 483px visoko); kapiranjem na 270px
          // (≈480px široko) slika sjedne ljepše, left-aligned.
          // Audio-only epizode nemaju screenshote (showScreenshot=false) →
          // preskačemo blok. Isto i kad screenshot 404-a (_screenshotFailed) —
          // da se ne vidi prazan sivi placeholder.
          if (widget.showScreenshot && !_screenshotFailed) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 270),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      // Screenshotovi nemaju WebP varijante (drugi URL prostor
                      // od thumbnaila) — dobitak je disk cache: povratak na
                      // pročitanu epizodu više ne povlači slike ponovno.
                      // Dok video ne krene, ostaje sivi okvir (isti layout,
                      // bez zahtjeva) — vidi DeferredScreenshots.
                      child: ListenableBuilder(
                        listenable: DeferredScreenshots.instance,
                        builder: (context, _) => !DeferredScreenshots.instance
                                .allows(section.screenshotTimestamp)
                            ? const SizedBox.expand()
                            : CachedThumbnail(
                                url: CdnConfig.screenshotUrl(
                                  widget.youtubeId,
                                  section.screenshotTimestamp,
                                ),
                                variantUrl: CdnConfig.screenshotWebpUrl(
                                  widget.youtubeId,
                                  section.screenshotTimestamp,
                                ),
                                fit: BoxFit.cover,
                                // Nema screenshota → kolabiraj blok (post-frame
                                // da se setState ne dogodi tijekom build/paint
                                // faze).
                                onFailed: () {
                                  if (!_screenshotFailed) {
                                    setState(() => _screenshotFailed = true);
                                  }
                                },
                                errorFallbackBuilder: (_) =>
                                    const SizedBox.shrink(),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],

          if (screenshotDesc.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Text(
                screenshotDesc,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          const SizedBox(height: 12),

          // Article content — markdown (+ opcijski person-needle inline syntax)
          MarkdownBody(
            data: content,
            styleSheet: MarkdownStyleSheet.fromTheme(theme)
                .copyWith(p: theme.textTheme.bodyMedium?.copyWith(height: 1.65))
                .withBrandBlockquote(theme),
            inlineSyntaxes:
                needle != null && needle.isNotEmpty ? [PersonMarkSyntax()] : null,
            builders: needle != null && needle.isNotEmpty
                ? {
                    'personMark': PersonMarkBuilder(
                      background: theme.colorScheme.tertiary,
                      foreground: Colors.white,
                    ),
                  }
                : const {},
            onTapLink: (text, href, title) {
              if (href != null) openUrl(href);
            },
          ),
          const SizedBox(height: 10),

          if (keywords.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: keywords
                  .map(
                    (k) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        k,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),

          // Magisterium enrichment block
          if (widget.showInlineMagisterium &&
              mag != null &&
              mag.assessment.isNotEmpty)
            _MagisteriumEnrichment(
              mag: mag,
              citationsExpanded: _citationsExpanded,
              onToggleCitations: () =>
                  setState(() => _citationsExpanded = !_citationsExpanded),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Magisterium enrichment block shown under each article section
// ---------------------------------------------------------------------------

class _MagisteriumEnrichment extends StatelessWidget {
  final SectionMagisterium mag;
  final bool citationsExpanded;
  final VoidCallback onToggleCitations;

  const _MagisteriumEnrichment({
    required this.mag,
    required this.citationsExpanded,
    required this.onToggleCitations,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final color = MagisteriumSection.scoreColor(mag.score);
    final mdStyle = MarkdownStyleSheet.fromTheme(theme)
        .copyWith(p: theme.textTheme.bodySmall?.copyWith(height: 1.5))
        .withBrandBlockquote(theme);
    final lang = EpisodeLanguageScope.of(context);
    final assessment = pickLang(lang, mag.assessment, mag.assessmentEn);
    final enrichment = pickLang(lang, mag.enrichment, mag.enrichmentEn);
    final concerns = pickLangList(lang, mag.concerns, mag.concernsEn);
    final heading = l.sectionTheologicalAssessment;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.church, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                heading,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Assessment — markdown
          MarkdownBody(data: assessment, styleSheet: mdStyle),

          // Enrichment — markdown
          if (enrichment.isNotEmpty) ...[
            const SizedBox(height: 8),
            MarkdownBody(
              data: enrichment,
              styleSheet: mdStyle.copyWith(
                p: theme.textTheme.bodySmall?.copyWith(
                  height: 1.5,
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],

          // Concerns
          if (concerns.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...concerns.map(
              (c) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber,
                      size: 14,
                      color: Color(0xFFEF6C00),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        c,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFEF6C00),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Citations (expandable, tappable)
          if (mag.citations.isNotEmpty) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: onToggleCitations,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      citationsExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l.sectionSources(mag.citations.length),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (citationsExpanded)
              ...mag.citations.map((cit) => _CitationCard(citation: cit)),
          ],
        ],
      ),
    );
  }
}

class _CitationCard extends StatelessWidget {
  final MagisteriumCitation citation;

  const _CitationCard({required this.citation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cleanText = cleanCitedText(citation.citedText);
    final displayText = cleanText.length > 300
        ? '${cleanText.substring(0, 300)}...'
        : cleanText;

    final ref = [
      citation.documentTitle,
      if (citation.documentReference.isNotEmpty) citation.documentReference,
      if (citation.documentYear.isNotEmpty) citation.documentYear,
    ].join(' — ');

    return GestureDetector(
      onTap: () => showCitationSheet(context, citation),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
          borderRadius: BorderRadius.circular(6),
          border: Border(
            left: BorderSide(
              color: theme.colorScheme.primary.withAlpha(100),
              width: 3,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              displayText,
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.5,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    ref,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(
                  Icons.open_in_new,
                  size: 12,
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
