import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../models/person_hub.dart';
import '../models/podcast_summary.dart';
import '../services/episode_language.dart';
import '../l10n/app_localizations.dart';
import '../router/nav.dart';

class EntitiesSection extends StatelessWidget {
  final SummaryContent summary;

  /// Person-highlight (dolazak s /p/ profila preko `?p=<slug>`): chip osobe
  /// čiji slug matcha renderira se bijelo-na-crveno (needle dekoracija).
  final String? highlightPersonSlug;

  const EntitiesSection({
    super.key,
    required this.summary,
    this.highlightPersonSlug,
  });

  @override
  Widget build(BuildContext context) {
    final lang = EpisodeLanguageScope.of(context);
    final l = AppLocalizations.of(context);
    final people =
        pickLangList(lang, summary.mentionedPeople, summary.mentionedPeopleEn);
    final places =
        pickLangList(lang, summary.mentionedPlaces, summary.mentionedPlacesEn);
    final orgs = pickLangList(
        lang, summary.mentionedOrganizations, summary.mentionedOrganizationsEn);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _EntityGroup(
            icon: Icons.person_outline,
            title: l.sectionPeople,
            items: people,
            color: _peopleColor,
            // Osobe vode na javni profil govornika (/p/:slug). Oni koji su i
            // govornici dobiju bogat profil; ostali (samo spomenuti) padnu na
            // uredno prazno stanje. Mjesta/organizacije nisu klikabilni.
            onItemTap: (name) => drillDown(context, '/p/${personSlug(name)}'),
            isHighlighted: highlightPersonSlug != null
                ? (name) => personSlug(name) == highlightPersonSlug
                : null,
          ),
          const SizedBox(height: 16),
          _EntityGroup(
            icon: Icons.place_outlined,
            title: l.sectionPlaces,
            items: places,
            color: _placesColor,
          ),
          const SizedBox(height: 16),
          _EntityGroup(
            icon: Icons.business_outlined,
            title: l.sectionOrganizations,
            items: orgs,
            color: _orgsColor,
          ),
        ],
      ),
    );
  }
}

/// Kompaktna traka spomenutih osoba ODMAH ispod naslova epizode — isti popis i
/// isti chipovi kao „Osobe" u [EntitiesSection], samo u jednom retku.
///
/// Zašto duplikat: puna sekcija entiteta živi na dnu članka, pa je dolazak s
/// `/p/<slug>` profila (crveni chip osobe) bio vidljiv tek nakon cijelog
/// članka. Ovdje se vidi odmah, i služi kao ulaz u druge profile.
///
/// Kad je [highlightPersonSlug] zadan, traka se sama doscrolla na taj chip —
/// inače bi osoba zbog koje si došao mogla biti deseta izvan viewporta.
class PeopleRail extends StatefulWidget {
  final SummaryContent summary;

  /// Person-highlight (dolazak s `?p=<slug>`): taj chip je bijelo-na-crveno.
  final String? highlightPersonSlug;

  /// `false` kad je vlasnik kanala isključio `persons_mentions`: imena ostaju
  /// kao tekst, bez poveznice na `/p/` (postavke kanala, odluka 505).
  final bool linkProfiles;

  const PeopleRail({
    super.key,
    required this.summary,
    this.highlightPersonSlug,
    this.linkProfiles = true,
  });

  @override
  State<PeopleRail> createState() => _PeopleRailState();
}

class _PeopleRailState extends State<PeopleRail> {
  final _highlightKey = GlobalKey();
  final _railKey = GlobalKey();
  final _controller = ScrollController();
  bool _scrolled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Doscrollaj SAMO ovu traku na istaknuti chip.
  ///
  /// Namjerno ručno, a NE `Scrollable.ensureVisible`: ona scrolla sve
  /// nadređene scrollable-ove, pa bi povukla i vertikalni scroll epizode natrag
  /// na vrh — točno suprotno od `_scrollToPersonAnchor` koji članak vodi na
  /// sekciju sa spomenom. Dvije bi se animacije tukle.
  void _revealHighlight() {
    if (_scrolled || !_controller.hasClients) return;
    if (_controller.position.maxScrollExtent <= 0) return; // sve stane u kadar
    final chip = _highlightKey.currentContext?.findRenderObject() as RenderBox?;
    final rail = _railKey.currentContext?.findRenderObject() as RenderBox?;
    if (chip == null || rail == null) return;
    _scrolled = true;
    final chipX = chip.localToGlobal(Offset.zero, ancestor: rail).dx;
    // 0.35 širine s lijeva — chip je u kadru, ali se vidi da ima još osoba.
    final target = (_controller.offset + chipX - rail.size.width * 0.35)
        .clamp(0.0, _controller.position.maxScrollExtent);
    if ((target - _controller.offset).abs() < 8) return;
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = EpisodeLanguageScope.of(context);
    final people =
        pickLangList(lang, widget.summary.mentionedPeople, widget.summary.mentionedPeopleEn);
    if (people.isEmpty) return const SizedBox.shrink();

    final slug = widget.highlightPersonSlug;
    if (slug != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _revealHighlight();
      });
    }

    // Isti dragDevices izbor kao episodes_rail: BEZ mouse-a (drag preko
    // InkWell chipova izgubi gesture arenu na kratkim potezima).
    final dragBehavior = ScrollConfiguration.of(context).copyWith(
      dragDevices: {
        PointerDeviceKind.touch,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      },
      scrollbars: false,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 2),
      child: ScrollConfiguration(
        behavior: dragBehavior,
        // Rubni razmak ide UNUTAR scrolla — traka kliže do fizičkog ruba.
        child: SingleChildScrollView(
          key: _railKey,
          controller: _controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Icon(Icons.person_outline,
                  size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              for (final name in people) ...[
                EntityChip(
                  key: personSlug(name) == slug ? _highlightKey : null,
                  label: name,
                  color: _peopleColor,
                  highlighted: personSlug(name) == slug,
                  onTap: widget.linkProfiles
                      ? () => drillDown(context, '/p/${personSlug(name)}')
                      : null,
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Boje kategorija entiteta — dijele ih traka na vrhu i sekcija na dnu, da im
/// chipovi ne odlutaju jedni od drugih.
const Color _peopleColor = Colors.blue;
const Color _placesColor = Colors.green;
const Color _orgsColor = Colors.orange;

/// Chip entiteta — jedini izvor izgleda za [PeopleRail] i [EntitiesSection].
///
/// `highlighted` (person-needle: dolazak s `/p/<slug>`) prebacuje na brand
/// crvenu (`cs.tertiary`) + bijeli tekst — ista boja kao marker u članku.
class EntityChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool highlighted;
  final VoidCallback? onTap;

  const EntityChip({
    super.key,
    required this.label,
    required this.color,
    this.highlighted = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: highlighted ? theme.colorScheme.tertiary : color.withAlpha(20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              highlighted ? theme.colorScheme.tertiary : color.withAlpha(60),
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: highlighted ? Colors.white : color.withAlpha(220),
          fontWeight: highlighted ? FontWeight.bold : null,
        ),
      ),
    );
    if (onTap == null) return chip;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: chip,
    );
  }
}

class _EntityGroup extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> items;
  final Color color;

  /// Ako je zadan, svaki chip postaje klikabilan (npr. osobe → profil).
  final void Function(String item)? onItemTap;

  /// Ako je zadan i vrati true, chip se renderira bijelo-na-crveno
  /// (person-needle highlight).
  final bool Function(String item)? isHighlighted;

  const _EntityGroup({
    required this.icon,
    required this.title,
    required this.items,
    required this.color,
    this.onItemTap,
    this.isHighlighted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(
              title,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 6),
            Text(
              '(${items.length})',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: items
              .map((item) => EntityChip(
                    label: item,
                    color: color,
                    highlighted: isHighlighted?.call(item) ?? false,
                    onTap:
                        onItemTap == null ? null : () => onItemTap!(item),
                  ))
              .toList(),
        ),
      ],
    );
  }
}
