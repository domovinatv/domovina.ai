import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../src/log.dart' show log;
import '../../models/person_hub.dart';
import '../../services/channel_visibility.dart';
import '../../services/channel_visibility_filters.dart';
import '../../services/person_channel_flag.dart';
import '../../services/person_service.dart';
import '../../widgets/person_monogram.dart';
import 'widgets/tv_episode_card.dart';
import 'widgets/tv_focus.dart';
import 'widgets/tv_row_traversal.dart';
import '../../router/nav.dart';

/// TV varijanta person huba (`/p/:slug`) — 10-foot pandan
/// `lib/screens/person/person_screen.dart`.
///
/// Layout je namjerno posuđen iz [TvChannelScreen] (`tv_channel_screen.dart`),
/// jer je poanta virtualnog kanala da osoba stoji ravnopravno uz kanal:
///
///   AppBar (NATRAG + monogram + ime + meta)
///   Grid: TvEpisodeCard (2-6 stupaca ovisno o širini ekrana)
///
/// Razlike naspram kanala:
/// - avatar je [PersonMonogram] (osoba nema cover — odluka O5 u planu),
/// - epizode dolaze s više različitih izvornih kanala, pa kartica nosi ime
///   kanala kao eyebrow (na kanalu bi bilo redundantno),
/// - grid ima do tri sekcije: „Epizode" (`primary`), „Kratki nastupi"
///   (`cameo`, samo u kanal-formi) i „Spominje se u" (spomeni).
///
/// **Kanal-forma** ([PersonChannelFlag], `?vk=1`) mijenja SAMO prezentaciju:
/// meta redak postaje „OSOBA · N EP · Xh Ym" i cameo nastupi se odvajaju u
/// vlastitu sekciju. Bez flaga (ili kad backend ne kaže `is_virtual_channel`)
/// ekran pokazuje jedan popis epizoda — isto pravilo kao na webu.
///
/// D-pad ponašanje:
/// - Autofocus na prvu karticu (NATRAG ostaje dostupan UP-om); kad epizoda
///   nema, autofocus ide na NATRAG da fokus nikad ne ostane nigdje.
/// - OK/Enter na karticu → `/v/<id>` (odnosno `/v/<id>/t/<sec>` iz deep-linka),
///   OK na NATRAG → `/`.
///
/// `Shortcuts` wrapper za arrow-key → DirectionalFocusIntent je obavezan —
/// Flutter Web ne mapira arrow keys na directional focus po defaultu (vidi
/// komentar u `tv_home_screen.dart`).
class TvPersonScreen extends StatefulWidget {
  /// Person slug se koristi DOSLOVNO (s crticama) — primarni ključ u bazi,
  /// za razliku od channel slug-a koji radi `-`→`_`.
  final String slug;

  const TvPersonScreen({super.key, required this.slug});

  @override
  State<TvPersonScreen> createState() => _TvPersonScreenState();
}

class _TvPersonScreenState extends State<TvPersonScreen> {
  late final Future<PersonHub?> _future;
  final _backFocus = FocusNode(debugLabel: 'tv-person-back');

  /// Lokalna kopija feature flaga. NE čita se prvi put u `build()`:
  /// `PersonChannelFlag.isOn` pri prvom čitanju pokrene `_load()` koji u
  /// `?vk=1` grani sinkrono zove `notifyListeners()` — poziv iz build faze
  /// srušio bi frame ("markNeedsBuild during build"). Isti obrazac kao
  /// `person_screen.dart`.
  bool _flagOn = false;

  @override
  void initState() {
    super.initState();
    log('TvPersonScreen.init slug=${widget.slug}');
    // Postavke kanala (`persons_mentions`), isto kao `PersonScreen`.
    _future = PersonService.fetch(widget.slug).then((hub) async {
      if (hub == null) return null;
      await ChannelVisibility.instance.ready();
      return visiblePersonHub(hub);
    });
    PersonChannelFlag.instance.addListener(_onFlagChanged);
    unawaited(Future.microtask(_initFlag));
  }

  @override
  void dispose() {
    PersonChannelFlag.instance.removeListener(_onFlagChanged);
    _backFocus.dispose();
    super.dispose();
  }

  Future<void> _initFlag() async {
    await PersonChannelFlag.instance.init();
    _onFlagChanged();
  }

  void _onFlagChanged() {
    if (!mounted) return;
    final on = PersonChannelFlag.instance.isOn;
    if (on == _flagOn) return;
    setState(() => _flagOn = on);
  }

  void _back() {
    log('TvPerson: back');
    backUp(context);
  }

  void _openEpisode(PersonEpisode episode) {
    final route = episode.routePath;
    log('TvPerson: open $route');
    drillDown(context, route);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.arrowUp):
                DirectionalFocusIntent(TraversalDirection.up),
            SingleActivator(LogicalKeyboardKey.arrowDown):
                DirectionalFocusIntent(TraversalDirection.down),
            SingleActivator(LogicalKeyboardKey.arrowLeft):
                DirectionalFocusIntent(TraversalDirection.left),
            SingleActivator(LogicalKeyboardKey.arrowRight):
                DirectionalFocusIntent(TraversalDirection.right),
            SingleActivator(LogicalKeyboardKey.escape): _BackIntent(),
            SingleActivator(LogicalKeyboardKey.goBack): _BackIntent(),
            SingleActivator(LogicalKeyboardKey.browserBack): _BackIntent(),
          },
          child: Actions(
            actions: {
              _BackIntent: CallbackAction<_BackIntent>(
                onInvoke: (_) {
                  _back();
                  return null;
                },
              ),
            },
            // Ista retkovna D-pad politika kao na TV home-u: zadnji redak
            // sekcije „Epizode" često nije pun, pa bi default traversal s
            // desnog stupca preskočio prvi redak „Kratkih nastupa" ili
            // „Spominje se u". Vidi widgets/tv_row_traversal.dart.
            child: FocusTraversalGroup(
              policy: TvRowTraversalPolicy(),
              child: FutureBuilder<PersonHub?>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return _buildLoading(theme, l);
                  }
                  final hub = snap.data;
                  if (hub == null) {
                    return _buildNotFound(theme, l);
                  }
                  // Opt-out (O8) NIJE iza feature flaga — to je zahtjev osobe
                  // za uklanjanjem, ne prezentacijska varijanta. Nikad 404, da
                  // već podijeljeni linkovi ne puknu.
                  if (hub.optout) {
                    return _buildOptedOut(theme, l, hub);
                  }
                  return _buildContent(theme, l, hub);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // States
  // ---------------------------------------------------------------------------

  Widget _buildLoading(ThemeData theme, AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAppBar(theme, l, hub: null, autofocusBack: false),
        const Expanded(child: Center(child: CircularProgressIndicator())),
      ],
    );
  }

  Widget _buildNotFound(ThemeData theme, AppLocalizations l) {
    log('TvPersonScreen: "${widget.slug}" nije pronađen');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAppBar(theme, l, hub: null, autofocusBack: true),
        Expanded(
          child: _CenteredMessage(
            icon: Icons.person_off_outlined,
            title: l.personNotFoundTitle,
            body: l.personNotFoundBody,
          ),
        ),
      ],
    );
  }

  Widget _buildOptedOut(ThemeData theme, AppLocalizations l, PersonHub hub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAppBar(theme, l, hub: hub, autofocusBack: true),
        Expanded(
          child: _CenteredMessage(
            icon: Icons.person_outline,
            title: hub.name,
            body: l.personOptedOut,
          ),
        ),
      ],
    );
  }

  Widget _buildContent(ThemeData theme, AppLocalizations l, PersonHub hub) {
    final channelForm = _flagOn && hub.isVirtualChannel;
    // Bez kanal-forme popis ostaje JEDAN — cameo se ne izdvaja, kao na webu.
    final primary = channelForm ? hub.primaryEpisodes : hub.episodes;
    final cameo = channelForm ? hub.cameoAppearances : const <PersonEpisode>[];

    final sections = <_PersonSection>[
      if (primary.isNotEmpty)
        _PersonSection(
          title: channelForm ? l.personSectionEpisodes : l.personEpisodesHeading,
          episodes: primary,
        ),
      if (cameo.isNotEmpty)
        _PersonSection(
          title: l.personSectionCameo,
          hint: l.personSectionCameoHint,
          episodes: cameo,
        ),
      // Spomeni ostaju izvan kanala (odluka O3), ali se prikazuju — inače bi
      // profil osobe koja se samo spominje bio prazan ekran.
      if (hub.mentions.isNotEmpty)
        _PersonSection(title: l.personMentionedIn, episodes: hub.mentions),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAppBar(
          theme,
          l,
          hub: hub,
          channelForm: channelForm,
          autofocusBack: sections.isEmpty,
        ),
        Expanded(
          child: sections.isEmpty
              ? _CenteredMessage(
                  icon: Icons.podcasts_outlined,
                  title: hub.name,
                  body: l.personMentionOnlyNote,
                )
              : _buildGrid(theme, sections),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // App bar (NATRAG + monogram + ime + meta)
  // ---------------------------------------------------------------------------

  Widget _buildAppBar(
    ThemeData theme,
    AppLocalizations l, {
    required PersonHub? hub,
    bool channelForm = false,
    bool autofocusBack = false,
  }) {
    // `episode_count` s backenda broji samo `primary`; stari odgovor ga nema,
    // pa padamo na klijentski klasificirane glavne nastupe.
    final episodes = hub == null
        ? 0
        : (hub.episodeCount > 0 ? hub.episodeCount : hub.primaryEpisodes.length);
    // Kanal-forma nosi „OSOBA · 17 EP · 13H 39M" (odluka O9) — ista brojka,
    // ali eksplicitno označena kao osoba, jer virtualni kanal nije kanal koji
    // netko uređuje.
    final meta = hub == null
        ? null
        : (channelForm
            ? l.personCardMeta(episodes, hub.durationDisplay).toUpperCase()
            : (episodes > 0 ? l.personEpisodesCount(episodes) : null));

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 20, 48, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          TvFocusable(
            style: TvFocusStyle.subtleButton,
            focusNode: _backFocus,
            autofocus: autofocusBack,
            borderRadius: BorderRadius.circular(12),
            onActivate: _back,
            builder: (context, focused) => AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: focused
                    ? theme.colorScheme.tertiaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_back,
                    size: 22,
                    color: theme.colorScheme.onSurface,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l.commonBack.toUpperCase(),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 24),
          PersonMonogram(
            name: hub?.name ?? _readableSlug(widget.slug),
            avatarUrl: hub?.avatarUrl,
            size: 48,
            radius: 8,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hub?.name ?? _readableSlug(widget.slug),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (meta != null)
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: channelForm ? 1.2 : null,
                      fontWeight: channelForm ? FontWeight.w700 : null,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Čitljivo ime iz slug-a dok profil ne stigne (dijakritika je izgubljena u
  /// fold-u, ali dovoljno informativno da se zna KOJA osoba se učitava).
  static String _readableSlug(String slug) => slug
      .split('-')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  // ---------------------------------------------------------------------------
  // Grid
  // ---------------------------------------------------------------------------

  Widget _buildGrid(ThemeData theme, List<_PersonSection> sections) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 48.0;
        const columnSpacing = 24.0;
        const rowSpacing = 32.0;

        // Isti izračun kao TvChannelScreen: target ~220dp, clamp 2-6 stupaca
        // (EON 960dp → 3-4, 1920dp → 6).
        final available = constraints.maxWidth - horizontalPadding * 2;
        const targetCardWidth = 220.0;
        final columns =
            ((available + columnSpacing) / (targetCardWidth + columnSpacing))
                .floor()
                .clamp(2, 6);
        final cardWidth =
            (available - (columns - 1) * columnSpacing) / columns;

        // Visina: thumbnail (16:9) + tekst region. 118 > 82 s kanala jer
        // kartica ovdje nosi i eyebrow s imenom izvornog kanala (do 2 retka)
        // iznad naslova (do 5 redaka), plus 10dp focus bordera.
        final cardHeight = cardWidth * 9 / 16 + 118;

        final slivers = <Widget>[];
        var first = true;
        var autofocusUsed = false;
        for (final section in sections) {
          slivers.add(
            SliverPadding(
              // Donjih 24: fokusirana kartica se skalira 1.18 i glow joj
              // prelazi vlastiti okvir — s manjim razmakom prekrije naslov
              // sekcije iznad sebe.
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                first ? 4 : 28,
                horizontalPadding,
                24,
              ),
              sliver: SliverToBoxAdapter(
                child: _SectionHeader(
                  title: section.title,
                  hint: section.hint,
                ),
              ),
            ),
          );
          final episodes = section.episodes;
          final autofocusIndex = autofocusUsed ? -1 : 0;
          autofocusUsed = true;
          slivers.add(
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: horizontalPadding,
              ),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: columnSpacing,
                  mainAxisSpacing: rowSpacing,
                  mainAxisExtent: cardHeight,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final e = episodes[i];
                    return TvEpisodeCard(
                      episodeId: e.youtubeId,
                      title: (e.title != null && e.title!.trim().isNotEmpty)
                          ? e.title!.trim()
                          : e.youtubeId,
                      subtitle: e.channelDisplayName.replaceAll('_', ' '),
                      magisteriumScore: personEpisodeScore(e),
                      width: cardWidth,
                      // Autofocus prva kartica prve sekcije — D-pad UP iz nje
                      // fokusira NATRAG.
                      autofocus: i == autofocusIndex,
                      onTap: () => _openEpisode(e),
                    );
                  },
                  childCount: episodes.length,
                ),
              ),
            ),
          );
          first = false;
        }
        // Donji rub: focused card scale 1.18 + glow trebaju prostora ispod
        // zadnjeg reda.
        slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 48)));

        return CustomScrollView(slivers: slivers);
      },
    );
  }
}

/// Jedna sekcija gridova na profilu — „Epizode", „Kratki nastupi" ili
/// „Spominje se u".
class _PersonSection {
  final String title;
  final String? hint;
  final List<PersonEpisode> episodes;

  const _PersonSection({
    required this.title,
    required this.episodes,
    this.hint,
  });
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? hint;

  const _SectionHeader({required this.title, this.hint});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(width: 28, height: 3, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Text(
              title.toUpperCase(),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
              ),
            ),
          ],
        ),
        if (hint != null) ...[
          const SizedBox(height: 6),
          Text(
            hint!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// Prazna/poruka stanja (404, opt-out, osoba bez gostovanja) — centrirano,
/// čitljivo s 3m.
class _CenteredMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Intent za hardware BACK / ESC keyeve — Android TV remote BACK obično šalje
/// `goBack` ili `browserBack` kod, a Mac/Chrome dev koristi ESC.
class _BackIntent extends Intent {
  const _BackIntent();
}
