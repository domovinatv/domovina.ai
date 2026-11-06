import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../brand/app_brand.dart';
import '../../src/log.dart' show log;
import '../../models/channel_index.dart';
import '../../models/person_hub.dart';
import '../../services/catalog_client.dart';
import '../../services/channel_cache.dart';
import '../../services/person_channel_flag.dart';
import '../../services/scroll_memory.dart';
import '../../services/person_index_cache.dart';
import '../../theme/app_theme.dart';
import '../../utils/text_search.dart';
import '../home/channel_card.dart';
import '../home/person_card.dart';
import '../home/sort_mode.dart';
import 'catalog_directory_view.dart';
import '../../router/nav.dart';

/// Standalone "Svi kanali" ekran — odvojen od home-a (scroll-perf).
///
/// Zasto odvojeno: home je prije renderirao SVE kanale (44+) eager u jednom
/// `SliverToBoxAdapter` → `Wrap`. Na web (skwasm) buildu to znaci da svaka
/// kartica zivi u stablu i sudjeluje u rasterizaciji svakog scroll frame-a →
/// vidljiv jank. Ovdje listu renderiramo **lazy** (`SliverList` po redovima,
/// recycle off-screen) + dodajemo filter, pa home ostaje lagan.
///
/// Surface je self-contained: sam ucita index iz [channelCache], drzi vlastiti
/// sort + filter state i persista sort (dijeli `channel_sort_v1` /
/// `channel_order` kljuceve s home-om). Otvara se kao full-page `/channels`
/// ruta ([AllChannelsScreen]) i na desktopu i na mobitelu — deep-linkable,
/// native back button.

/// Full-page varijanta — meta `/channels` rute.
class AllChannelsScreen extends StatelessWidget {
  /// Otvori katalog s već odabranim filtrom (`/channels?prikaz=osobe`).
  ///
  /// Namjerno query param na POSTOJEĆOJ ruti, a ne nova `/osobe` ruta: nova
  /// javna content ruta mora u OBA deep-link popisa (AASA `components` u
  /// `web/_worker.js` + Android intent filter), pa bi „Prikaži sve" na railu
  /// osoba koštalo dva zaboravljiva upisa i propagaciju AASA cachea. Query
  /// param ne mijenja rutu ni za jedan popis.
  final bool showPersons;

  /// Otvori popis „Svi” (`/channels?prikaz=svi`, katalog S10). Brend bez
  /// kataloga ga ignorira i otvara „Pratimo”.
  final bool showDirectory;

  const AllChannelsScreen({
    super.key,
    this.showPersons = false,
    this.showDirectory = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        title: Text(showPersons ? l.homePersonsRailTitle : l.channelAllChannels),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: l.commonBack,
          onPressed: () => back(context),
        ),
      ),
      body: SafeArea(
        top: false,
        child: AllChannelsView(
          initialFilter:
              showPersons ? CatalogFilter.persons : CatalogFilter.all,
          initialDirectory: showDirectory,
        ),
      ),
    );
  }
}

/// Filter kataloga — kanali i osobe (virtualni kanali) žive u ISTOJ lazy listi
/// (odluka O9 u `docs/plans/virtualni-kanali.md`); chip samo suzava prikaz.
/// Vidljiv je tek kad je `PersonChannelFlag` upaljen I indeks osoba ima barem
/// jednu osobu — bez toga katalog izgleda točno kao prije.
enum CatalogFilter { all, channels, persons }

/// Jedan redak kataloga: ILI kanal ILI osoba (nikad oboje). Namjerno nije
/// zajednički model — `ChannelSummary` nosi `UC…` id, cover dimenzije i
/// ownership/pinka reference koje osoba nema, pa bi zajednički tip značio
/// null-guardove kroz cijeli lanac (odbačena opcija (a) u O1).
typedef _CatalogEntry = ({ChannelSummary? channel, PersonSummary? person});

/// Sadrzaj surface-a: search bar + filter chipovi + sort red + lazy lista
/// kanala i osoba.
///
/// Self-contained — ucita index kanala, indeks osoba i sort sam.
class AllChannelsView extends StatefulWidget {
  /// Filtar s kojim se katalog otvara. `/channels?prikaz=osobe` i „Prikaži
  /// sve" na home railu osoba ulaze ovuda; sve ostalo otvara `all`.
  final CatalogFilter initialFilter;

  /// Otvori s odabranim „Svi” (popis iz kataloga) umjesto „Pratimo”.
  final bool initialDirectory;

  const AllChannelsView({
    super.key,
    this.initialFilter = CatalogFilter.all,
    this.initialDirectory = false,
  });

  @override
  State<AllChannelsView> createState() => _AllChannelsViewState();
}

class _AllChannelsViewState extends State<AllChannelsView> {
  static const double _maxCardWidth = 360;

  final _searchCtrl = TextEditingController();

  /// Pozicija u lazy listi kataloga — vidi `ScrollMemory`. Ključ nosi query
  /// jer `/channels` i `/channels?prikaz=osobe` imaju dvije nezavisne pozicije.
  final _scrollCtrl = ScrollController();
  String _query = '';

  ChannelSortMode _sortMode = ChannelSortMode.newest;
  List<ChannelSummary> _channels = const [];
  List<String>? _customOrder;
  bool _ready = false;

  // Osobe kao virtualni kanali — prazno dok flag ne stigne ili dok backend
  // nema `/api/persons` (F2). Oba slučaja daju današnji katalog.
  late CatalogFilter _filter = widget.initialFilter;
  bool _flagOn = false;

  /// „Pratimo” (false, današnji popis iz statičnog indeksa) ili „Svi” (true,
  /// [CatalogDirectoryView]). Bez kataloga u brendu uvijek „Pratimo” i bez
  /// chipova, pa Podcasterium ne vidi ništa novo ni ne šalje zahtjev.
  late bool _directory = widget.initialDirectory;

  bool get _catalogEnabled => CatalogClient.instance.enabled;

  bool get _showsDirectory => _catalogEnabled && _directory;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      if (_searchCtrl.text != _query) {
        setState(() => _query = _searchCtrl.text);
      }
    });
    // Flag/indeks se čitaju IZVAN build faze: prvo čitanje `isOn` pokreće
    // `_load()`, koji u `?vk=1` grani zove `notifyListeners()` sinkrono — iz
    // build()-a bi to srušilo frame. Zato microtask + lokalno stanje.
    PersonChannelFlag.instance.addListener(_onFlagChanged);
    personIndexCache.addListener(_onIndexChanged);
    unawaited(Future.microtask(_initPersonChannels));
    _init();
  }

  Future<void> _initPersonChannels() async {
    unawaited(personIndexCache.loadIndex());
    await PersonChannelFlag.instance.init();
    _onFlagChanged();
  }

  void _onFlagChanged() {
    final on = PersonChannelFlag.instance.isOn;
    if (!mounted || on == _flagOn) return;
    setState(() => _flagOn = on);
  }

  void _onIndexChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _init() async {
    try {
      final index = channelCache.index ?? await channelCache.loadIndex();
      final mode = await loadSortMode() ?? ChannelSortMode.newest;
      final order = await loadCustomOrder();
      if (!mounted) return;
      setState(() {
        _channels = index.channels;
        _sortMode = mode;
        _customOrder = order;
        _ready = true;
      });
    } catch (e) {
      log('AllChannelsView._init ERROR: $e');
      if (mounted) setState(() => _ready = true);
    }
  }

  @override
  void dispose() {
    PersonChannelFlag.instance.removeListener(_onFlagChanged);
    personIndexCache.removeListener(_onIndexChanged);
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  List<ChannelSummary> get _ordered =>
      applySortMode(_channels, _sortMode, customOrder: _customOrder);

  /// Osobe koje smiju stajati uz kanale — backend je već primijenio prag i
  /// opt-out (`is_virtual_channel`), frontend ne preračunava. Najviše nastupa
  /// prvo; sort modovi kanala se na osobe ne primjenjuju (rade nad
  /// `ChannelSummary` poljima koja osoba nema).
  List<PersonSummary> get _persons {
    final list =
        List<PersonSummary>.from(personIndexCache.virtualChannels);
    list.sort((a, b) => b.episodeCount.compareTo(a.episodeCount));
    return list;
  }

  /// Ima li se uopće što filtrirati — chipovi i osobe se pojave samo tada.
  bool get _personsEnabled =>
      _flagOn && personIndexCache.virtualChannels.isNotEmpty;

  /// Filtar koji se STVARNO primjenjuje.
  ///
  /// „Osobe" bez osoba za prikaz nije prazan katalog nego **pun** katalog:
  /// chipovi se u tom slučaju uopće ne crtaju, pa bi korisnik gledao praznu
  /// listu bez ijedne kontrole kojom bi je vratio. Dva puta vode ovamo —
  /// `/channels?prikaz=osobe` kod korisnika s ugašenim flagom, i gašenje flaga
  /// dok je „Osobe" aktivan (rubni slučaj iz reviewa r3 u
  /// `docs/plans/virtualni-kanali.md`).
  CatalogFilter get _effectiveFilter =>
      (!_personsEnabled && _filter == CatalogFilter.persons)
          ? CatalogFilter.all
          : _filter;

  bool get _showsPersons =>
      _personsEnabled && _effectiveFilter != CatalogFilter.channels;

  /// Vidljiva lista nakon filtera. Prazan upit → puni (sortirani) popis
  /// kanala pa osobe; inace dijakritik-neosjetljiv match na imenu preko OBA
  /// tipa, najbolji rezultat prvi (pa "sarolic" i "šarolić" nađu osobu i kad
  /// je katalog pun kanala).
  List<_CatalogEntry> get _visible {
    final channels = _effectiveFilter == CatalogFilter.persons
        ? const <ChannelSummary>[]
        : _ordered;
    final persons = _showsPersons ? _persons : const <PersonSummary>[];
    final q = _query.trim();

    if (q.isEmpty) {
      return [
        for (final c in channels) (channel: c, person: null),
        for (final p in persons) (channel: null, person: p),
      ];
    }

    final scored = <(double, _CatalogEntry)>[];
    for (final c in channels) {
      final s = localMatchScore(q, c.name);
      if (s > 0) scored.add((s, (channel: c, person: null)));
    }
    for (final p in persons) {
      final s = localMatchScore(q, p.name);
      if (s > 0) scored.add((s, (channel: null, person: p)));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return scored.map((e) => e.$2).toList();
  }

  Future<void> _onSortChanged(ChannelSortMode mode) async {
    await saveSortMode(mode);
    // Naslovnica drži izračunati redoslijed u cacheu — mora ga preračunati.
    channelCache.invalidateOrder();
    if (mounted) setState(() => _sortMode = mode);
  }

  Future<void> _onShuffle() async {
    final shuffled = List<ChannelSummary>.from(_channels)..shuffle(Random());
    final ids = shuffled.map((c) => c.id).toList();
    await saveCustomOrder(ids);
    await saveSortMode(ChannelSortMode.custom);
    channelCache.invalidateOrder();
    if (mounted) {
      setState(() {
        _customOrder = ids;
        _sortMode = ChannelSortMode.custom;
      });
    }
  }

  void _openChannel(ChannelSummary channel) {
    final slug = channel.id.replaceAll('_', '-');
    drillDown(context, '/c/$slug');
  }

  /// Person slug ide DOSLOVNO (bez `-`↔`_` pretvorbe koju rade kanali).
  void _openPerson(PersonSummary person) =>
      drillDown(context, person.routePath);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_catalogEnabled) _scopeChips(theme),
        if (_showsDirectory)
          const Expanded(child: CatalogDirectoryView())
        else ...[
          _searchBar(theme),
          if (_personsEnabled) _filterChips(theme),
          _toolbar(theme),
          Expanded(
            child: !_ready
                ? const Center(child: CircularProgressIndicator())
                : _list(),
          ),
        ],
        if (AppBrand.config.flags.voting) _votingBar(theme),
      ],
    );
  }

  /// Trajna traka na dnu kataloga — „Nema tvog podcasta? Glasaj koji ide
  /// sljedeći." (plan §8.6).
  ///
  /// Traka, a ne dijalog ni snackbar: CLAUDE.md pravilo o nudge-evima traži
  /// trajnu površinu koja ništa ne prekida. Vidljiva je **svima** — ljestvica
  /// glasanja je javna, a poziv na potvrdu identiteta stoji tek na samom ekranu
  /// glasanja, gdje uz sebe ima kontekst.
  ///
  /// Donji `SafeArea` NE ide ovdje: [AllChannelsScreen] već omata cijeli
  /// `AllChannelsView` u jedan `SafeArea(top: false)`, pa bi drugi inset bio
  /// dupli razmak (CLAUDE.md, slaganje donjih traka).
  Widget _votingBar(ThemeData theme) {
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      child: InkWell(
        onTap: () => drillDown(context, '/glasanje'),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(
            children: [
              Icon(Icons.how_to_vote_outlined, size: 20, color: cs.tertiary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l.votingChannelsBarTitle,
                      style: theme.textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      l.votingChannelsBarBody,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                l.votingChannelsBarCta,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.tertiary,
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: cs.tertiary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchBar(ThemeData theme) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchCtrl,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: l.channelSearchChannelsHint,
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: l.channelClear,
                  onPressed: () => _searchCtrl.clear(),
                )
              : null,
          isDense: true,
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }

  /// Pratimo / Svi (katalog S10). Zaseban red IZNAD pretrage: „Svi” nema ni
  /// pretragu ni sort (katalog ih ne nudi, a filtriranje samo učitanih
  /// stranica lagalo bi), pa red s kojim se bira prikaz ostaje na mjestu, a
  /// ispod njega se mijenja sve ostalo.
  Widget _scopeChips(ThemeData theme) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          _choiceChip(
            theme,
            label: l.channelsScopeFollowed,
            selected: !_directory,
            onSelected: () => setState(() => _directory = false),
            identifier: 'channels-scope-followed',
          ),
          const SizedBox(width: 8),
          _choiceChip(
            theme,
            label: l.channelsScopeAll,
            selected: _directory,
            onSelected: () => setState(() => _directory = true),
            identifier: 'channels-scope-all',
          ),
        ],
      ),
    );
  }

  /// Sve / Kanali / Osobe. Chipovi stanu u red i na uskom mobitelu (tri kratke
  /// riječi), pa nema scrollabla — a time ni pravila o paddingu unutar liste.
  Widget _filterChips(ThemeData theme) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(
        children: [
          _filterChip(theme,
              label: l.channelsFilterAll, value: CatalogFilter.all),
          const SizedBox(width: 8),
          _filterChip(theme,
              label: l.channelsFilterChannels, value: CatalogFilter.channels),
          const SizedBox(width: 8),
          _filterChip(theme,
              label: l.channelsFilterPersons,
              value: CatalogFilter.persons,
              identifier: 'channels-filter-persons'),
        ],
      ),
    );
  }

  Widget _filterChip(ThemeData theme,
      {required String label,
      required CatalogFilter value,
      String? identifier}) =>
      _choiceChip(
        theme,
        label: label,
        selected: _effectiveFilter == value,
        onSelected: () => setState(() => _filter = value),
        identifier: identifier,
      );

  Widget _choiceChip(ThemeData theme,
      {required String label,
      required bool selected,
      required VoidCallback onSelected,
      String? identifier}) {
    // Brand-fill je navy (AppTheme.brandPrimary) + brandRim — NE cs.primary, koji
    // M3 dark shema izblijedi.
    final chip = ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      labelStyle: theme.textTheme.labelMedium?.copyWith(
        color: selected ? Colors.white : theme.colorScheme.onSurfaceVariant,
      ),
      selectedColor: AppTheme.brandPrimary,
      side: selected ? AppTheme.brandRim(theme.brightness) : BorderSide.none,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
    );
    if (identifier == null) return chip;
    return Semantics(identifier: identifier, container: true, child: chip);
  }

  Widget _toolbar(ThemeData theme) {
    final l = AppLocalizations.of(context);
    final count = _visible.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(
        children: [
          Text(
            // "X kanala" bi lagalo čim su u listi i osobe — tada brojimo
            // rezultate.
            _query.trim().isNotEmpty || _showsPersons
                ? l.channelResultsCount(count)
                : l.channelChannelsCount(count),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          // Sort je besmislen dok je aktivan filter (rezultati su po relevanciji).
          if (_query.trim().isEmpty)
            ChannelSortDropdown(
              mode: _sortMode,
              onChanged: _onSortChanged,
              onShuffle: _onShuffle,
            ),
        ],
      ),
    );
  }

  Widget _list() {
    final l = AppLocalizations.of(context);
    final items = _visible;
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _query.trim().isEmpty
                ? l.channelNoChannels
                : l.channelNoChannelsForQuery(_query.trim()),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final available = width - 32; // horizontalni padding 16+16
        // Mobile (< 600): 1 stupac. Sire: clamp na ~360px max sirinu kartice.
        final columns = width < 600
            ? 1
            : (available / _maxCardWidth).floor().clamp(2, 99);
        final cardWidth = columns == 1
            ? available
            : (available - (columns - 1) * 16) / columns;
        final rowCount = (items.length / columns).ceil();

        // SliverList po REDOVIMA (ne SliverGrid): kanal kartice imaju
        // varijabilnu visinu (banner vs square layout, 1-2 linije naziva), a
        // SliverGrid forsira uniformnu visinu celije → clipanje. Red drzi
        // prirodne visine (top-aligned), a SliverList recycle-a off-screen
        // redove → lazy paint kakav nam je i bio cilj.
        return ScrollRestorer(
          storageKey: widget.initialFilter == CatalogFilter.persons
              ? '/channels?prikaz=osobe'
              : '/channels',
          controller: _scrollCtrl,
          child: CustomScrollView(
          controller: _scrollCtrl,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              sliver: SliverList.builder(
                itemCount: rowCount,
                itemBuilder: (context, row) {
                  final start = row * columns;
                  final end = min(start + columns, items.length);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (int i = start; i < end; i++) ...[
                          if (i > start) const SizedBox(width: 16),
                          SizedBox(
                            width: cardWidth,
                            child: _card(items[i]),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
          ),
        );
      },
    );
  }

  /// Kartica kanala ili osobe — obje SQUARE forme, pa red drži prirodne visine
  /// i bez posebnog slučaja.
  Widget _card(_CatalogEntry entry) {
    final person = entry.person;
    if (person != null) {
      return PersonCard(person: person, onTap: () => _openPerson(person));
    }
    final channel = entry.channel!;
    return ChannelCard(
      channel: channel,
      onTap: () => _openChannel(channel),
    );
  }
}

/// Sort selektor za kanale — PopupMenuButton sa svim sort opcijama + shuffle.
///
/// Premjesteno iz home-a (bivsi `_SortDropdown`) da ga dijeli `AllChannelsView`.
class ChannelSortDropdown extends StatelessWidget {
  final ChannelSortMode mode;
  final Future<void> Function(ChannelSortMode) onChanged;
  final VoidCallback onShuffle;

  const ChannelSortDropdown({
    super.key,
    required this.mode,
    required this.onChanged,
    required this.onShuffle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return PopupMenuButton<String>(
      tooltip: l.channelSortChannels,
      offset: const Offset(0, 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (value) {
        if (value == '__shuffle__') {
          onShuffle();
        } else {
          final m = ChannelSortMode.values.firstWhere((e) => e.name == value);
          onChanged(m);
        }
      },
      itemBuilder: (context) => [
        for (final m in ChannelSortMode.offered)
          PopupMenuItem<String>(
            value: m.name,
            child: Row(
              children: [
                Icon(
                  m == mode ? Icons.check : Icons.circle_outlined,
                  size: 14,
                  color: m == mode
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.3),
                ),
                const SizedBox(width: 10),
                Text(m.label(l), style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: '__shuffle__',
          child: Row(
            children: [
              Icon(Icons.shuffle,
                  size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Text(l.channelShuffle, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              mode.label(l),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down,
                size: 18, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
