import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../brand/app_brand.dart';
import '../../l10n/app_localizations.dart';
import '../../models/person_hub.dart';
import '../../services/cdn_config.dart';
import '../../services/channel_visibility.dart';
import '../../services/channel_visibility_filters.dart';
import '../../services/follow_service.dart';
import '../../services/page_meta.dart';
import '../../services/person_channel_flag.dart';
import '../../services/person_service.dart';
import '../../services/scroll_memory.dart';
import '../../theme/app_theme.dart';
import '../../theme/typography.dart';
import '../../widgets/follow_button.dart';
import '../../widgets/person_monogram.dart';
import '../../widgets/cached_thumbnail.dart';
import '../../router/nav.dart';

/// Javni profil osobe ("person hub") — /p/:slug.
///
/// Dohvaća agregat SVIH epizoda u kojima se osoba pojavljuje (kroz sve kanale) s
/// domovina-rag `/api/person/{slug}` i prikazuje: ime + avatar, statistiku
/// (epizode / kanali / spomeni), raspodjelu po kanalima, mjesečni timeline te
/// dva popisa epizoda — „Epizode" (govori) i „Spominje se u". Prazno/404 stanje
/// tek ako slug nije ni govornik ni spomen.
///
/// Osoba koja se SAMO spominje (nikad gost — povijesna/pokojna figura) ima
/// valjan profil: govor-agregacije su prazne, pa se raspodjela po kanalima i
/// timeline crtaju iz spomena ([PersonHub.mentionChannels]/`mentionTimeline`).
///
/// Slug se prosljeđuje DOSLOVNO iz rute (bez `-`↔`_` transformacije koju rade
/// kanali) — on je primarni ključ u bazi.
///
/// **Kanal-forma (T3, `docs/plans/virtualni-kanali.md`)**: kad je osoba
/// virtualni kanal ([PersonHub.isVirtualChannel]) i [PersonChannelFlag] je
/// upaljen (`?vk=1`), hero se prebacuje u kanal-oblik (monogram, eyebrow
/// „OSOBA · N EP · Xh Ym", deterministički podnaslov), a popis govor-epizoda
/// se dijeli na „Epizode" (`primary`) i „Kratki nastupi" (`cameo`). Sekcija
/// „Spominje se u" ostaje nepromijenjena u OBA prikaza — spomen je sadržaj
/// *o* osobi i namjerno ne ulazi u kanal (odluka O3).
class PersonScreen extends StatefulWidget {
  final String slug;

  const PersonScreen({super.key, required this.slug});

  @override
  State<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends State<PersonScreen> {
  late Future<PersonHub?> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetchWithMeta();
    // Flag se učitava IZVAN build faze: `_load()` u override grani (`?vk=1`)
    // zove notifyListeners() sinkrono, pa bi poziv iz build()/initState-a
    // srušio frame ("markNeedsBuild during build"). Mreža je ionako sporija od
    // ovog microtaska, pa profil nikad ne bljesne u krivom obliku.
    unawaited(Future.microtask(PersonChannelFlag.instance.init));
  }

  @override
  void didUpdateWidget(PersonScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slug != widget.slug) {
      _future = _fetchWithMeta();
    }
  }

  /// Fetch + runtime <title>/og meta — isti format kao worker inject za /p/.
  Future<PersonHub?> _fetchWithMeta() async {
    final fetched = await PersonService.fetch(widget.slug);
    // Postavke kanala (`persons_mentions`): epizode tih kanala izostaju iz
    // nastupa i spomena. Katalog se čeka najviše 1,5 s (fail-open).
    if (fetched != null) await ChannelVisibility.instance.ready();
    final hub = fetched == null ? null : visiblePersonHub(fetched);
    if (hub != null && mounted) {
      setPageMeta(title: '${hub.name} — podcast profil');
    }
    return hub;
  }

  /// ← popa stog; bez stoga (share link, hard refresh) ide na katalog s
  /// filtrom „Osobe", ne na naslovnicu — vidi `upTarget`.
  void _back() => backUp(context);

  /// Kopira javnu poveznicu na profil (`/p/<slug>`). Worker injecta osobno-
  /// specifične OG tagove na taj path (ime + broj epizoda/kanala) pa WhatsApp/
  /// Facebook preview pokaže osobu, ne generički domovina.ai — vidi web/_worker.js.
  void _shareProfile() {
    final url = AppBrand.config.shareUrl('/p/${widget.slug}');
    Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.personLinkCopied),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: l.commonBack,
                    onPressed: _back,
                  ),
                  const Spacer(),
                  FutureBuilder<PersonHub?>(
                    future: _future,
                    builder: (context, snap) {
                      final hub = snap.data;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Praćenje ima smisla samo za postojeći profil; nakon
                          // opt-outa (O8) osoba je zatražila uklanjanje, pa joj
                          // ne nudimo ni gumb. Sam gumb se dodatno sakrije dok
                          // je PersonChannelFlag ugašen.
                          if (hub != null && !hub.optout) ...[
                            FollowButton(
                              followKey: personFollowKey(widget.slug),
                              followLabel: l.personFollow,
                              followingLabel: l.personFollowing,
                              semanticsIdentifier: 'person-follow-button',
                            ),
                            const SizedBox(width: 4),
                          ],
                          IconButton(
                            icon: const Icon(Icons.ios_share),
                            tooltip: l.personShareTooltip,
                            // Aktivan tek kad profil postoji — nema smisla
                            // dijeliti 404.
                            onPressed: hub != null ? _shareProfile : null,
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: PersonChannelFlag.instance,
                builder: (context, _) => FutureBuilder<PersonHub?>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final hub = snap.data;
                    if (hub == null) {
                      return _NotFound(slug: widget.slug);
                    }
                    // Opt-out (O8) NIJE iza feature flaga: to je zahtjev osobe
                    // za uklanjanjem, ne prezentacijska varijanta. 404 bi
                    // razbio već podijeljene linkove, pa ostaje minimalni
                    // profil. Stari backend ne šalje `optout` → false → ništa
                    // se ne mijenja.
                    if (hub.optout) {
                      return _OptedOutProfile(hub: hub);
                    }
                    return _PersonContent(
                      hub: hub,
                      channelForm:
                          hub.isVirtualChannel && PersonChannelFlag.instance.isOn,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Prazno / 404 stanje
// ---------------------------------------------------------------------------

class _NotFound extends StatelessWidget {
  final String slug;

  const _NotFound({required this.slug});

  /// Čitljivo ime iz slug-a (dijakritika je izgubljena u fold-u, ali dovoljno
  /// informativno da korisnik zna KOJU osobu nismo našli).
  static String _readable(String slug) => slug
      .split('-')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_off_outlined,
                size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              l.personNotFoundTitle,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              '»${_readable(slug)}«',
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: theme.colorScheme.primary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l.personNotFoundBody,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Minimalni profil nakon opt-outa (O8): ime + objašnjenje, bez ijednog
/// nastupa. Namjerno NIJE 404 — linkovi podijeljeni prije zahtjeva moraju i
/// dalje voditi na smislenu stranicu.
class _OptedOutProfile extends StatelessWidget {
  final PersonHub hub;

  const _OptedOutProfile({required this.hub});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PersonMonogram(name: hub.name, size: 88, radius: 44),
              const SizedBox(height: 16),
              Text(
                hub.name,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                l.personOptedOut,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sadržaj profila
// ---------------------------------------------------------------------------

class _PersonContent extends StatelessWidget {
  final PersonHub hub;

  /// Osoba se prikazuje kao virtualni kanal (flag upaljen + backend potvrdio).
  final bool channelForm;

  const _PersonContent({required this.hub, this.channelForm = false});

  /// Iznad ove širine → dvostupčani layout (lijevo fiksni info, desno scroll
  /// epizode). Ispod → jedan stupac (mobitel).
  static const double _twoColBreakpoint = 900;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _twoColBreakpoint) {
          return _SingleColumn(hub: hub, channelForm: channelForm);
        }
        return _TwoColumn(hub: hub, channelForm: channelForm);
      },
    );
  }
}

/// Mobitel / usko — sve u jednom scroll stupcu.
///
/// Pamćenje scroll pozicije je OVDJE, a ne na `_TwoColumn`: široki layout ima
/// dva nezavisna stupca koji scrollaju odvojeno, pa jedan spremljeni offset
/// nema smisla. Uski layout je i mjesto gdje se problem osjeti — popis nastupa
/// je dug, a tap na epizodu je najčešća radnja s ovog ekrana.
class _SingleColumn extends StatefulWidget {
  final PersonHub hub;
  final bool channelForm;

  const _SingleColumn({required this.hub, this.channelForm = false});

  @override
  State<_SingleColumn> createState() => _SingleColumnState();
}

class _SingleColumnState extends State<_SingleColumn> {
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hub = widget.hub;
    final channelForm = widget.channelForm;
    final l = AppLocalizations.of(context);
    // Osoba bez gostovanja: kanali/timeline dolaze iz spomena (govor-agregacije
    // su prazne), a naslov sekcije kanala se mijenja u „Spominje se na".
    final mentionOnly = hub.isMentionOnly;
    final channels = mentionOnly ? hub.mentionChannels : hub.channels;
    final timeline = mentionOnly ? hub.mentionTimeline : hub.timeline;
    // Bez kanal-forme popis ostaje JEDAN (današnje ponašanje) — cameo se ne
    // izdvaja, da profil bez flaga izgleda točno kao prije.
    final primary = channelForm ? hub.primaryEpisodes : hub.allAppearances;
    final cameo =
        channelForm ? hub.cameoAppearances : const <PersonEpisode>[];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ScrollRestorer(
          storageKey: '/p/${hub.slug}',
          controller: _scrollCtrl,
          child: ListView(
          controller: _scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
          children: [
            if (channelForm)
              _ChannelHero(hub: hub)
            else
              _Header(hub: hub),
            if (mentionOnly) ...[
              const SizedBox(height: 14),
              _MentionOnlyNote(text: l.personMentionOnlyNote),
            ],
            if (channels.isNotEmpty) ...[
              const SizedBox(height: 28),
              _ChannelsSection(
                channels: channels,
                title: mentionOnly ? l.personMentionedOn : l.personAppearsOn,
                facts: channelForm ? _channelFactsFrom(hub) : const {},
              ),
            ],
            if (timeline.length > 1) ...[
              const SizedBox(height: 28),
              _TimelineSection(timeline: timeline),
            ],
            if (primary.isNotEmpty) ...[
              const SizedBox(height: 28),
              _EpisodesSection(
                title: channelForm
                    ? l.personSectionEpisodes
                    : l.personEpisodesHeading,
                episodes: primary,
                personSlug: hub.slug,
                channelForm: channelForm,
                semanticsIdentifier:
                    channelForm ? 'person-episodes-primary' : null,
              ),
            ],
            if (cameo.isNotEmpty) ...[
              const SizedBox(height: 28),
              _EpisodesSection(
                title: l.personSectionCameo,
                hint: l.personSectionCameoHint,
                episodes: cameo,
                personSlug: hub.slug,
                channelForm: true,
                semanticsIdentifier: 'person-episodes-cameo',
              ),
            ],
            if (hub.mentions.isNotEmpty) ...[
              const SizedBox(height: 28),
              _EpisodesSection(
                title: l.personMentionedIn,
                episodes: hub.mentions,
                personSlug: hub.slug,
                isMention: true,
              ),
            ],
          ],
        ),
        ),
      ),
    );
  }
}

/// Desktop — lijevo fiksni info (header, kanali, timeline) koji ostaje vidljiv,
/// desno neovisno scrollabilna lista epizoda.
class _TwoColumn extends StatelessWidget {
  final PersonHub hub;
  final bool channelForm;

  const _TwoColumn({required this.hub, this.channelForm = false});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hasMentions = hub.mentions.isNotEmpty;
    final mentionOnly = hub.isMentionOnly;
    final channels = mentionOnly ? hub.mentionChannels : hub.channels;
    final timeline = mentionOnly ? hub.mentionTimeline : hub.timeline;
    final primary = channelForm ? hub.primaryEpisodes : hub.allAppearances;
    final cameo =
        channelForm ? hub.cameoAppearances : const <PersonEpisode>[];
    // Treći stupac („Spominje se u") traži više širine da sve tri kolone dišu.
    // Bez gostovanja su stupca samo dva → uža, gušća kompozicija.
    final maxWidth = hasMentions && !mentionOnly ? 1440.0 : 1180.0;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Lijevi stupac — glavni podaci; vlastiti scroll ako je visok.
            SizedBox(
              width: 380,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 16, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (channelForm) _ChannelHero(hub: hub) else _Header(hub: hub),
                    if (mentionOnly) ...[
                      const SizedBox(height: 14),
                      _MentionOnlyNote(text: l.personMentionOnlyNote),
                    ],
                    if (channels.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      _ChannelsSection(
                        channels: channels,
                        title:
                            mentionOnly ? l.personMentionedOn : l.personAppearsOn,
                        facts: channelForm ? _channelFactsFrom(hub) : const {},
                      ),
                    ],
                    if (timeline.length > 1) ...[
                      const SizedBox(height: 28),
                      _TimelineSection(timeline: timeline),
                    ],
                  ],
                ),
              ),
            ),
            // Srednji stupac — „Govori u" (epizode), neovisan scroll. U
            // kanal-formi isti stupac nosi i „Kratke nastupe" ispod glavnog
            // popisa (jedan scroll, dvije sekcije).
            if (primary.isNotEmpty || cameo.isNotEmpty)
              Expanded(
                flex: 3,
                child: _EpisodeListColumn(
                  title: channelForm
                      ? l.personSectionEpisodes
                      : l.personEpisodesHeading,
                  episodes: primary,
                  personSlug: hub.slug,
                  channelForm: channelForm,
                  semanticsIdentifier:
                      channelForm ? 'person-episodes-primary' : null,
                  cameoTitle: l.personSectionCameo,
                  cameoHint: l.personSectionCameoHint,
                  cameoEpisodes: cameo,
                ),
              ),
            // Desni stupac — „Spominje se u" (spomeni), zaseban scroll. Tanka
            // vertikalna linija razdvaja ga od „Govori u" radi preglednosti —
            // samo kad taj stupac postoji (osoba bez gostovanja ga nema).
            if (hasMentions) ...[
              if (primary.isNotEmpty || cameo.isNotEmpty)
                const VerticalDivider(width: 1, thickness: 1),
              Expanded(
                flex: 2,
                child: _EpisodeListColumn(
                  title: l.personMentionedIn,
                  episodes: hub.mentions,
                  personSlug: hub.slug,
                  isMention: true,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final PersonHub hub;

  const _Header({required this.hub});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    // „0 epizoda / 0 kanala" je šum na profilu osobe koja nikad nije gostovala —
    // govor-pilule se pokazuju samo kad govor postoji, a kanali se tada broje iz
    // spomena.
    final speaks = hub.episodes.isNotEmpty;
    final mentionChannelCount = hub.mentionChannels.length;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _Avatar(name: hub.name, avatarUrl: hub.avatarUrl),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hub.name,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (speaks) ...[
                    _StatPill(
                      icon: Icons.podcasts,
                      label: l.personEpisodesCount(hub.episodeCount),
                    ),
                    _StatPill(
                      icon: Icons.tv,
                      label: l.channelChannelsCount(hub.channelCount),
                    ),
                  ],
                  if (hub.mentions.isNotEmpty)
                    _StatPill(
                      icon: Icons.format_quote,
                      label: l.personMentionsCount(hub.mentionCount),
                    ),
                  if (!speaks && mentionChannelCount > 0)
                    _StatPill(
                      icon: Icons.tv,
                      label: l.channelChannelsCount(mentionChannelCount),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Hero u **kanal-formi**: monogram + eyebrow („OSOBA · 17 EP · 13H 39M") +
/// ime + deterministički podnaslov. Namjerno je vizualno blizak kartici kanala
/// (isti eyebrow stil, isti gradijent avatara) — razlika je jedino riječ
/// „Osoba" u eyebrowu (odluka O9), jer virtualni kanal NIJE kanal koji netko
/// uređuje, ali mora stajati ravnopravno uz kanale.
class _ChannelHero extends StatelessWidget {
  final PersonHub hub;

  const _ChannelHero({required this.hub});

  /// „Gostuje u 17 epizoda na 17 kanala, 2020.–2026." Godine idu kao String
  /// placeholderi (int bi kroz `NumberFormat` postao „2.026").
  static String? _subtitle(AppLocalizations l, PersonHub hub, int episodes) {
    final channels =
        hub.channelCount > 0 ? hub.channelCount : hub.channels.length;
    if (episodes == 0 || channels == 0) return null;
    final from = hub.firstYear ?? hub.lastYear;
    final to = hub.lastYear ?? hub.firstYear;
    if (from == null || to == null) return null;
    if (from == to) {
      return l.personVirtualChannelSubtitleOneYear(episodes, channels, '$from');
    }
    return l.personVirtualChannelSubtitle(episodes, channels, '$from', '$to');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    // `episode_count` s backenda broji samo `primary`; kad ga stari odgovor ne
    // pošalje, brojimo klijentski klasificirane glavne nastupe.
    final episodes =
        hub.episodeCount > 0 ? hub.episodeCount : hub.primaryEpisodes.length;
    final subtitle = _subtitle(l, hub, episodes);

    return Semantics(
      identifier: 'person-hero',
      container: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PersonMonogram(name: hub.name, avatarUrl: hub.avatarUrl, size: 96),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  identifier: 'person-episode-count',
                  child: Text(
                    l
                        .personCardMeta(episodes, hub.durationDisplay)
                        .toUpperCase(),
                    style: AppTypography.eyebrowStyle(theme.colorScheme),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  hub.name,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontFamily: 'Playfair Display',
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
                if (hub.mentions.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _StatPill(
                    icon: Icons.format_quote,
                    label: l.personMentionsCount(hub.mentionCount),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Napomena na profilu osobe koja se samo spominje — objašnjava zašto nema
/// popisa gostovanja, da prazan „Epizode" stupac ne izgleda kao greška.
class _MentionOnlyNote extends StatelessWidget {
  final String text;

  const _MentionOnlyNote({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.brandPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.fromBorderSide(AppTheme.brandRim(theme.brightness)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline,
              size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final String? avatarUrl;

  const _Avatar({required this.name, required this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    const double size = 72;
    // Brand-fill navy (croBlue) + brandRim — NE cs.primary (M3 dark ga izblijedi).
    final initials = _initials(name);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.brandPrimary,
        shape: BoxShape.circle,
        border: Border.fromBorderSide(
          AppTheme.brandRim(Theme.of(context).brightness),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: (avatarUrl != null && avatarUrl!.isNotEmpty)
          ? Image.network(
              avatarUrl!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) => _initialsLabel(initials),
            )
          : _initialsLabel(initials),
    );
  }

  Widget _initialsLabel(String initials) => Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 26,
        ),
      );

  static String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.brandPrimary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.fromBorderSide(AppTheme.brandRim(theme.brightness)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Foreground/ikona = cs.primary (per brand pravilo), ne croBlue fill.
          Icon(icon, size: 15, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// "Gostuje na" — raspodjela po kanalima
// ---------------------------------------------------------------------------

/// Što o izvornom kanalu znamo IZ EPIZODA (raspodjela „Gostuje na" sama nosi
/// samo slug i broj): ime za prikaz i je li kanal praćen.
class _ChannelFacts {
  final String? name;
  final bool tracked;

  const _ChannelFacts({this.name, this.tracked = false});
}

/// Slug → [_ChannelFacts] iz svih govor-epizoda (glavnih i cameo). Koristi se
/// SAMO u kanal-formi: na starom odgovoru `channel_tracked` ne postoji (uvijek
/// false), pa bi ovo pogasilo linkove koji danas rade.
Map<String, _ChannelFacts> _channelFactsFrom(PersonHub hub) {
  final out = <String, _ChannelFacts>{};
  for (final e in [...hub.episodes, ...hub.cameoEpisodes]) {
    if (e.channel.isEmpty) continue;
    final prev = out[e.channel];
    out[e.channel] = _ChannelFacts(
      name: e.channelName?.trim().isNotEmpty == true
          ? e.channelName
          : prev?.name,
      // Dovoljna je JEDNA epizoda koja tvrdi da je kanal praćen.
      tracked: (prev?.tracked ?? false) || e.channelTracked,
    );
  }
  return out;
}

class _ChannelsSection extends StatelessWidget {
  final List<PersonChannelCount> channels;

  /// „Gostuje na" (govor) ili „Spominje se na" (osoba bez gostovanja).
  final String title;

  /// Prazno izvan kanal-forme → svi čipovi ostaju klikabilni kao danas.
  final Map<String, _ChannelFacts> facts;

  const _ChannelsSection({
    required this.channels,
    required this.title,
    this.facts = const {},
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: title),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: channels
              .map((c) => _ChannelChip(channel: c, facts: facts[c.channel]))
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _ChannelChip extends StatelessWidget {
  final PersonChannelCount channel;

  /// `null` → ne znamo ništa (izvan kanal-forme ili kanal dolazi samo iz
  /// spomena) → ponašanje kao danas: klikabilno, ime iz sluga.
  final _ChannelFacts? facts;

  const _ChannelChip({required this.channel, this.facts});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final name = facts?.name ?? channel.channel.replaceAll('_', ' ');
    // Nepraćen kanal nema `/c/` stranicu — link bi vodio na 404 (odluka O4),
    // pa čip ostaje statičan uz tooltip koji to objasni.
    final untracked = facts != null && !facts!.tracked;
    final body = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tv, size: 15, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  name,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${channel.count}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        );

    if (untracked) {
      return Tooltip(
        message: l.personSourceChannelUntracked,
        child: Material(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          child: body,
        ),
      );
    }
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => drillDown(context, '/c/${channel.channelRouteSlug}'),
        child: body,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Timeline — mjesečna aktivnost (jednostavan bar graf)
// ---------------------------------------------------------------------------

class _TimelineSection extends StatelessWidget {
  final List<PersonMonthCount> timeline;

  const _TimelineSection({required this.timeline});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    // Popuni praznine (mjesece bez epizoda) da x-os bude LINEARNA po vremenu —
    // inače se mjeseci s podacima "zbiju" i osi se ne mogu vjerovati.
    final months = _expandMonths(timeline);
    if (months.length < 2) return const SizedBox.shrink();
    final maxCount = months.fold<int>(1, (m, e) => e.count > m ? e.count : m);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: l.personActivityOverTime),
        const SizedBox(height: 14),
        // Stupci popunjavaju punu širinu (svaki Expanded) → rubne oznake
        // (prvi/zadnji mjesec) se prirodno poravnaju s prvim/zadnjim stupcem.
        SizedBox(
          height: 68,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final m in months)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 0.8),
                    child: Tooltip(
                      message: '${m.month} · ${m.count}',
                      waitDuration: const Duration(milliseconds: 300),
                      child: Container(
                        height: m.count == 0
                            ? 3
                            : (7 + 55 * (m.count / maxCount)),
                        decoration: BoxDecoration(
                          color: m.count == 0
                              ? theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.14)
                              : AppTheme.brandPrimary.withValues(alpha: 0.72),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Tanka os-linija ispod stupaca.
        Container(height: 1, color: theme.colorScheme.outlineVariant),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(months.first.month,
                style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
            Text(months.last.month,
                style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ],
    );
  }
}

/// Pretvori rijetku listu mjeseci (samo oni s epizodama, "YYYY-MM") u
/// KONTINUIRANU listu od prvog do zadnjeg mjeseca, umećući `count: 0` za
/// praznine. Time timeline postaje istinita vremenska os.
List<PersonMonthCount> _expandMonths(List<PersonMonthCount> input) {
  if (input.isEmpty) return input;

  int? keyOf(String m) {
    final parts = m.split('-');
    if (parts.length < 2) return null;
    final y = int.tryParse(parts[0]);
    final mo = int.tryParse(parts[1]);
    if (y == null || mo == null) return null;
    return y * 12 + (mo - 1);
  }

  final counts = <int, int>{};
  int? minK, maxK;
  for (final e in input) {
    final k = keyOf(e.month);
    if (k == null) continue;
    counts[k] = e.count;
    if (minK == null || k < minK) minK = k;
    if (maxK == null || k > maxK) maxK = k;
  }
  if (minK == null || maxK == null) return input;

  final out = <PersonMonthCount>[];
  for (int k = minK; k <= maxK; k++) {
    final y = k ~/ 12;
    final mo = (k % 12) + 1;
    final label = '$y-${mo.toString().padLeft(2, '0')}';
    out.add(PersonMonthCount(month: label, count: counts[k] ?? 0));
  }
  return out;
}

// ---------------------------------------------------------------------------
// Popis epizoda
// ---------------------------------------------------------------------------

class _EpisodesSection extends StatelessWidget {
  final String title;

  /// Jedna rečenica ispod naslova (npr. objašnjenje „Kratkih nastupa").
  final String? hint;
  final List<PersonEpisode> episodes;

  /// Slug osobe — prosljeđuje se kao `?p=` na episode deep-link da episode
  /// ekran označi sekciju gdje osoba govori ("X govori ovdje" marker).
  final String personSlug;

  /// Popis spomena (ne gostovanja) → kartice nose oznaku trenutka.
  final bool isMention;

  /// Kartice u kanal-formi (chip izvornog kanala + „Prijavi grešku").
  final bool channelForm;

  /// e2e/a11y sidro na naslovu sekcije (`flt-semantics-identifier`).
  final String? semanticsIdentifier;

  const _EpisodesSection({
    required this.title,
    required this.episodes,
    required this.personSlug,
    this.hint,
    this.isMention = false,
    this.channelForm = false,
    this.semanticsIdentifier,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: title,
          hint: hint,
          semanticsIdentifier: semanticsIdentifier,
        ),
        const SizedBox(height: 10),
        for (final e in episodes)
          _EpisodeCard(
            episode: e,
            personSlug: personSlug,
            isMention: isMention,
            channelForm: channelForm,
          ),
      ],
    );
  }
}

/// Desktop stupac: naslov + neovisno scrollabilna lista epizoda (lazy).
/// Koristi ga i „Govori u" (episodes) i „Spominje se u" (mentions) stupac.
class _EpisodeListColumn extends StatelessWidget {
  final String title;
  final List<PersonEpisode> episodes;

  /// Slug osobe — prosljeđuje se kao `?p=` na episode deep-link (marker).
  final String personSlug;

  /// Popis spomena (ne gostovanja) → kartice nose oznaku trenutka.
  final bool isMention;

  /// Kartice u kanal-formi (chip izvornog kanala + „Prijavi grešku").
  final bool channelForm;

  /// e2e/a11y sidro na naslovu glavne sekcije.
  final String? semanticsIdentifier;

  /// Druga sekcija u ISTOM scrollu — „Kratki nastupi" (`cameo`). Prazno kad
  /// kanal-forma nije aktivna.
  final String? cameoTitle;
  final String? cameoHint;
  final List<PersonEpisode> cameoEpisodes;

  const _EpisodeListColumn({
    required this.title,
    required this.episodes,
    required this.personSlug,
    this.isMention = false,
    this.channelForm = false,
    this.semanticsIdentifier,
    this.cameoTitle,
    this.cameoHint,
    this.cameoEpisodes = const [],
  });

  /// Splošti naslove i kartice u JEDAN popis redaka da lista ostane
  /// `ListView.builder` (lazy) — dvije sekcije u dva ugniježđena scrolla bi
  /// razbile jedinstveni scroll stupca.
  List<_ColumnRow> _rows() {
    final rows = <_ColumnRow>[];
    if (episodes.isNotEmpty) {
      rows.add(_ColumnRow.header(title, null, semanticsIdentifier));
      rows.addAll(episodes.map(_ColumnRow.episode));
    }
    if (cameoEpisodes.isNotEmpty && cameoTitle != null) {
      rows.add(_ColumnRow.header(
          cameoTitle!, cameoHint, 'person-episodes-cameo',
          topGap: episodes.isNotEmpty));
      rows.addAll(cameoEpisodes.map(_ColumnRow.episode));
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        final episode = row.episode;
        if (episode == null) {
          return Padding(
            padding: EdgeInsets.only(top: row.topGap ? 24 : 0, bottom: 10),
            child: _SectionTitle(
              title: row.title!,
              hint: row.hint,
              semanticsIdentifier: row.identifier,
            ),
          );
        }
        return _EpisodeCard(
          episode: episode,
          personSlug: personSlug,
          isMention: isMention,
          channelForm: channelForm,
        );
      },
    );
  }
}

/// Jedan redak u [_EpisodeListColumn] — ili naslov sekcije, ili kartica.
class _ColumnRow {
  final String? title;
  final String? hint;
  final String? identifier;
  final bool topGap;
  final PersonEpisode? episode;

  const _ColumnRow.header(this.title, this.hint, this.identifier,
      {this.topGap = false})
      : episode = null;

  const _ColumnRow.episode(this.episode)
      : title = null,
        hint = null,
        identifier = null,
        topGap = false;
}

class _EpisodeCard extends StatelessWidget {
  final PersonEpisode episode;

  /// Slug osobe — appenda se kao `?p=` na deep-link da episode ekran prikaže
  /// "X govori ovdje" marker na ciljanoj sekciji članka.
  final String personSlug;

  /// Kartica je u popisu „Spominje se u" → prikaži je li spomen vezan uz TOČAN
  /// trenutak (tap seeka onamo) ili je samo epizodni (tap otvara od početka).
  /// Kod govor-epizoda razlika ne postoji — `first_ts` je uvijek stvaran.
  final bool isMention;

  /// Kanal-forma: chip izvornog kanala (klikabilan SAMO za praćene kanale) i
  /// akcija „Prijavi grešku" za krivo pripisanog govornika.
  final bool channelForm;

  const _EpisodeCard({
    required this.episode,
    required this.personSlug,
    this.isMention = false,
    this.channelForm = false,
  });

  /// Dojava krivo pripisanog govornika → `POST /api/person-report`.
  ///
  /// Prijava ide u `person_channel_overrides` **nepotvrđena**; epizoda ne
  /// ispada iz kanala dok je čovjek ne potvrdi. Bez te podjele bi gumb bez
  /// ikakve autentikacije bio brisač tuđih epizoda iz kataloga.
  ///
  /// Potvrda se prikazuje **odmah**, ne nakon odgovora: mreža nije korisnikova
  /// briga, a čekanje bi na sporoj vezi izgledalo kao da gumb ne radi.
  /// SnackBar je ovdje dopušten jer potvrđuje korisnikovu radnju i ne prekida
  /// reprodukciju (pravilo iz CLAUDE.md o nudgeovima).
  void _reportError(BuildContext context) {
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.personReportErrorThanks),
        duration: const Duration(seconds: 3),
      ),
    );
    unawaited(PersonService.reportEpisode(
      slug: personSlug,
      youtubeId: episode.youtubeId,
    ));
  }

  /// Sekunde → "16:45" / "1:05:30" (sat samo kad postoji).
  static String _clock(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
    return '$m:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final title = (episode.title != null && episode.title!.trim().isNotEmpty)
        ? episode.title!.trim()
        : episode.youtubeId;
    final channelName = episode.channel.replaceAll('_', ' ');
    final hasMoment = episode.firstTs > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            drillDown(context, '${episode.routePath}?p=$personSlug'),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedThumbnail(
                  url: CdnConfig.thumbnailUrl(episode.youtubeId),
                  width: 120,
                  height: 68,
                  fit: BoxFit.cover,
                  errorIcon: Icons.ondemand_video,
                  errorIconSize: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (isMention)
                          _MentionMomentChip(
                            hasMoment: hasMoment,
                            label: hasMoment
                                ? l.personMentionAtTime(
                                    _clock(episode.firstTs))
                                : l.personMentionWholeEpisode,
                          ),
                        if (channelForm)
                          _SourceChannelChip(episode: episode)
                        else
                          _MetaChip(icon: Icons.tv, text: channelName),
                        if (episode.uploadDate.isNotEmpty)
                          _MetaChip(
                              icon: Icons.calendar_today,
                              text: episode.uploadDate),
                      ],
                    ),
                    if (channelForm) ...[
                      const SizedBox(height: 2),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: () => _reportError(context),
                          icon: const Icon(Icons.flag_outlined, size: 14),
                          label: Text(l.personReportError),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: const Size(0, 28),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            foregroundColor: theme.colorScheme.onSurfaceVariant,
                            textStyle: theme.textTheme.labelSmall,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Razlikuje dvije vrste spomena u popisu „Spominje se u".
///
/// Puna brand-crvena (`cs.tertiary`) = znamo TOČAN trenutak; tap seeka onamo i
/// ondje dočeka isti crveni marker u članku — namjerno ista boja da korisnik
/// poveže karticu i marker. Obrubljena/prigušena = trenutak nije razriješen iz
/// `article.json` (~40% spomena), pa tap otvara epizodu od početka.
class _MentionMomentChip extends StatelessWidget {
  final bool hasMoment;
  final String label;

  const _MentionMomentChip({required this.hasMoment, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = hasMoment ? Colors.white : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: hasMoment ? theme.colorScheme.tertiary : null,
        borderRadius: BorderRadius.circular(6),
        border: hasMoment
            ? null
            : Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(hasMoment ? Icons.play_arrow : Icons.subject, size: 12, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: fg,
                fontWeight: hasMoment ? FontWeight.bold : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Izvorni kanal epizode u kanal-formi.
///
/// Klikabilan je **samo** kad kanal ima svoju `/c/` stranicu
/// ([PersonEpisode.channelTracked]). Ad-hoc izvori (N1, Lider, TEDxZagreb…)
/// nisu praćeni kanali — link bi vodio na 404, a i lažno bi sugerirao da je
/// riječ o kanalu u našem katalogu (odluka O4). Umjesto toga: prigušen tekst s
/// tooltipom koji to objasni.
class _SourceChannelChip extends StatelessWidget {
  final PersonEpisode episode;

  const _SourceChannelChip({required this.episode});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final label = episode.channelDisplayName.replaceAll('_', ' ');
    final route = episode.channelRoutePath;

    if (route == null) {
      return Tooltip(
        message: l.personSourceChannelUntracked,
        child: _MetaChip(icon: Icons.tv, text: label),
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => drillDown(context, route),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: _MetaChip(
          icon: Icons.tv,
          text: label,
          color: theme.colorScheme.primary,
          bold: true,
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String text;

  /// Boja ikone i teksta; `null` → prigušeno (`onSurfaceVariant`).
  final Color? color;
  final bool bold;

  const _MetaChip({
    required this.icon,
    required this.text,
    this.color,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = color ?? theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: fg),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: bold ? FontWeight.w700 : null,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  /// Jedna rečenica objašnjenja ispod naslova (npr. što je „Kratki nastup").
  final String? hint;

  /// e2e/a11y sidro (`flt-semantics-identifier` uz `?a11y=1`). Stoji na
  /// naslovu, ne na listi, jer se u dvostupčanom layoutu obje sekcije crtaju
  /// kroz JEDAN lazy `ListView.builder` pa lista nema vlastiti čvor.
  final String? semanticsIdentifier;

  const _SectionTitle({
    required this.title,
    this.hint,
    this.semanticsIdentifier,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style:
              theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(
            hint!,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
    if (semanticsIdentifier == null) return content;
    return Semantics(
      identifier: semanticsIdentifier,
      container: true,
      child: content,
    );
  }
}
