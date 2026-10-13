import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_theme.dart';
import 'package:flutter/services.dart';
import '../../models/channel_index.dart';
import '../../models/person_hub.dart';
import '../../models/channel_detail.dart';
import '../../services/cdn_config.dart';
import '../../services/channel_cache.dart';
import '../../services/entitlement_service.dart';
import '../../services/person_channel_flag.dart';
import '../../services/person_index_cache.dart';
import '../../services/search_service.dart';
import '../../utils/text_search.dart';
import '../../widgets/episode_age.dart';
import '../../widgets/highlight_text.dart';
import '../../widgets/person_monogram.dart';

import '../../theme/typography.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/cached_thumbnail.dart';
import '../../router/nav.dart';

/// Otvori search overlay (modal) povrh home screen-a.
///
/// Dva sloja pretrage:
/// - Tier 0 (instant, offline): dijakritik-neosjetljiv lokalni match nad
///   učitanim kanalima/epizodama (naslov, govornici, teme, sažetak).
/// - Tier 1 (semantic, online): deterministički RAG `/api/search` — pronalazi
///   GDJE se o nečemu priča, s deep linkom na točan timestamp.
Future<void> showSearchOverlay(
  BuildContext context, {
  required List<ChannelSummary> channels,
  required void Function(ChannelSummary) onSelectChannel,
  required void Function(String videoId) onSelectVideo,
  required void Function(String videoId, int seconds) onSelectVideoAt,
}) async {
  // Browserov Back mijenja rutu ISPOD modala, a modal ne zna za to (vidi
  // `closeOnRouteChange`). Bez ovoga bi paleta ostala visjeti preko nove
  // stranice.
  final navigator = Navigator.of(context);
  late final VoidCallback unsubscribe;
  unsubscribe = closeOnRouteChange(context, () {
    if (navigator.canPop()) navigator.pop();
  });

  await showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: AppLocalizations.of(context).homeSearchBarrierLabel,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, _, _) => _SearchOverlay(
      channels: channels,
      onSelectChannel: onSelectChannel,
      onSelectVideo: onSelectVideo,
      onSelectVideoAt: onSelectVideoAt,
    ),
    // SAMO fade, bez `ScaleTransition`. Scale tween (0.96 → 1.0) ostavljao je
    // paletu trajno pod transformom, a skwasm na Mali GPU-u (moto g86,
    // Mali-G615, Chrome) pod njom krivo crta glifove: razmak dobije negativnu
    // širinu („fra stje" se vidi kao „frastje"), „d" izađe kao „đ". Unos je
    // bio ispravan, korisnik je samo vidio da razmak „ne radi". Izmjereno
    // 13.10.2026.; ista ruta bez transforma (`/search`) crta ispravno.
    // FadeTransition pri opacity 1 ne ostavlja nikakav sloj.
    transitionBuilder: (context, anim, _, child) =>
        FadeTransition(opacity: anim, child: child),
  );
  unsubscribe();
}

/// Uređaj kojem je KRAĆA stranica ispod ovoga (mobitel, i u landscapeu)
/// dobiva pretragu kao ekran, a ne plutajuću paletu.
const double _kCompactWidth = 600;

class _SearchOverlay extends StatefulWidget {
  final List<ChannelSummary> channels;
  final void Function(ChannelSummary) onSelectChannel;
  final void Function(String videoId) onSelectVideo;
  final void Function(String videoId, int seconds) onSelectVideoAt;

  const _SearchOverlay({
    required this.channels,
    required this.onSelectChannel,
    required this.onSelectVideo,
    required this.onSelectVideoAt,
  });

  @override
  State<_SearchOverlay> createState() => _SearchOverlayState();
}

// Lokalni rezultat epizode s izračunatim scoreom.
typedef _VideoHit = ({String channelId, String channelName, ChannelVideo video});

// Epizoda s unaprijed foldanim tekstom za pretragu.
typedef _IndexedVideo = ({_VideoHit hit, String title, String all});

class _SearchOverlayState extends State<_SearchOverlay> {
  final _searchController = TextEditingController();
  final _idController = TextEditingController();
  late final FocusNode _searchFocus;
  Timer? _debounce;
  Timer? _semanticDebounce;
  Timer? _dataDebounce;
  String _query = '';
  // Upit za koji je poslan (ili se šalje) semantički zahtjev — normaliziran,
  // pa „fra" → „fra " ne okida novi zahtjev.
  String _semanticQuery = '';

  // Foldani tekst epizoda, računa se JEDNOM po stanju `channelCache`-a, ne pri
  // svakom buildu. Korpus je ~3300 epizoda / 2,7 MB teksta; prije je cijeli
  // prolazio kroz `foldText` u svakom `build()` (spinner, stigli rezultati,
  // svaka notifikacija cachea), ~75 ms na M-čipu i višestruko više na
  // mobitelu — tipkanje je štucalo.
  List<_IndexedVideo>? _videoIndex;
  bool _showIdInput = false;

  // Tier 1 semantic state.
  List<SemanticResult> _semanticResults = [];
  bool _semanticLoading = false;

  // Keyboard navigacija — dva stupca (panes):
  //   pane 0 (lijevo)  = PO NASLOVU: kanali + epizode (lokalno)
  //   pane 1 (desno)   = U SADRŽAJU: semantički rezultati
  // ↑/↓ kroz aktivni stupac, ←/→ mijenja aktivni stupac. Svaki stupac ima
  // vlastiti indeks i scroll. _selectedKey se veže na aktivni-selektirani red
  // za ensureVisible.
  int _activePane = 0;
  int _leftSel = 0;
  int _rightSel = 0;
  final _leftScroll = ScrollController();
  final _rightScroll = ScrollController();
  final _selectedKey = GlobalKey();
  List<PersonSummary> _visiblePersons = const [];
  List<ChannelSummary> _visibleChannels = const [];
  List<_VideoHit> _visibleVideos = const [];

  /// Osobe (virtualni kanali) iza `PersonChannelFlag`-a. Lokalni match nad
  /// `PersonIndexCache`-om — `/api/search` se NE dira (odluka O6 u
  /// `docs/plans/virtualni-kanali.md`): osobe su egzaktan lookup po imenu, a
  /// lokalni match je brži, jeftiniji i radi offline.
  bool _flagOn = false;

  int get _leftCount =>
      _visiblePersons.length + _visibleChannels.length + _visibleVideos.length;
  int get _rightCount => _semanticResults.length;
  int get _activeCount => _activePane == 0 ? _leftCount : _rightCount;

  @override
  void initState() {
    super.initState();
    // onKeyEvent na samom FocusNode-u fokusiranog polja → dobiva event PRIJE
    // text-editing shortcutova, pa možemo presresti i ←/→ (inače pomiču kursor).
    _searchFocus = FocusNode(onKeyEvent: _handleKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocus.requestFocus();
    });
    // Flag i indeks osoba se čitaju IZVAN build faze: prvo čitanje
    // `PersonChannelFlag.isOn` pokreće `_load()`, koji u `?vk=1` grani zove
    // `notifyListeners()` sinkrono — iz build()-a bi to srušilo frame.
    PersonChannelFlag.instance.addListener(_onFlagChanged);
    personIndexCache.addListener(_onPersonIndexChanged);
    // Kad stignu listinzi ili tekst za pretragu, indeks se gradi iznova.
    // Prefetch naslovnice javlja po kanalu, pa se notifikacije skupljaju.
    channelCache.addListener(_onChannelCacheChanged);
    unawaited(Future.microtask(_initPersons));
    // Sažetak/teme/govornici za lokalnu pretragu — skraćeni listing (v2) ih
    // ne nosi. Kad stignu, cache notificira i rezultati se osvježe.
    unawaited(channelCache.ensureSearchText());
  }

  Future<void> _initPersons() async {
    unawaited(personIndexCache.loadIndex());
    await PersonChannelFlag.instance.init();
    _onFlagChanged();
  }

  void _onFlagChanged() {
    final on = PersonChannelFlag.instance.isOn;
    if (!mounted || on == _flagOn) return;
    setState(() {
      _flagOn = on;
      _recomputeLocal();
    });
  }

  /// Rebuild kad se promijeni indeks osoba.
  void _onPersonIndexChanged() {
    if (!mounted) return;
    setState(_recomputeLocal);
  }

  void _onChannelCacheChanged() {
    _videoIndex = null;
    _dataDebounce?.cancel();
    _dataDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted && _query.isNotEmpty) setState(_recomputeLocal);
    });
  }

  @override
  void dispose() {
    PersonChannelFlag.instance.removeListener(_onFlagChanged);
    personIndexCache.removeListener(_onPersonIndexChanged);
    channelCache.removeListener(_onChannelCacheChanged);
    _debounce?.cancel();
    _dataDebounce?.cancel();
    _semanticDebounce?.cancel();
    _leftScroll.dispose();
    _rightScroll.dispose();
    _searchController.dispose();
    _idController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    final q = normalizeQuery(value);

    // Tier 0 — lokalni rezultati (kratki debounce). Razmak na kraju ne mijenja
    // upit, pa ni rezultate ni odabrani red.
    _debounce?.cancel();
    if (q != _query) {
      _debounce = Timer(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        setState(() {
          _query = q;
          // novi upit → highlight prvi rezultat lijevog stupca
          _leftSel = 0;
          _rightSel = 0;
          _activePane = 0;
          _recomputeLocal();
        });
      });
    }

    // Tier 1 — semantic, duži debounce + min duljina (štedi mrežu/embeddinge).
    if (q == _semanticQuery) return;
    _semanticDebounce?.cancel();
    if (q.length < 3) {
      _semanticQuery = '';
      if (_semanticResults.isNotEmpty || _semanticLoading) {
        setState(() {
          _semanticResults = [];
          _semanticLoading = false;
        });
      }
      return;
    }
    _semanticDebounce = Timer(const Duration(milliseconds: 420), () {
      _runSemantic(q);
    });
  }

  void _clearQuery() {
    _searchController.clear();
    _onSearchChanged('');
    _searchFocus.requestFocus();
  }

  Future<void> _runSemantic(String q) async {
    _semanticQuery = q;
    setState(() => _semanticLoading = true);
    // DOMOVINA Plus dobiva veći set rezultata (free ostaje pun i koristan).
    final limit = EntitlementService.instance.isPlus.value ? 30 : 12;
    final results = await SearchService.search(q, limit: limit);
    if (!mounted) return;
    // Odbaci stale odgovor (upit se promijenio u međuvremenu).
    if (_semanticQuery != q) return;
    setState(() {
      _semanticResults = results;
      _semanticLoading = false;
    });
  }

  void _openVideoId() {
    final id = _idController.text.trim();
    if (id.isEmpty) return;
    Navigator.of(context).pop();
    widget.onSelectVideo(id);
  }

  // ── Keyboard navigacija (dva stupca) ──────────────────────────
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveInPane(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveInPane(-1);
      return KeyEventResult.handled;
    }
    // ←/→ mijenja stupac samo kad ima smisla; inače pusti (kursor u polju).
    if (key == LogicalKeyboardKey.arrowRight) {
      if (_activePane == 0 && _rightCount > 0) {
        _setActivePane(1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_activePane == 1 && _leftCount > 0) {
        _setActivePane(0);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      // Na mobitelu Enter (Gboard ga na webu šalje i kao keydown) ide kroz
      // `onSubmitted`, koji samo spušta tipkovnicu.
      if (_isCompact(MediaQuery.sizeOf(context))) return KeyEventResult.ignored;
      if (_activeCount > 0) {
        _activateSelected();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _moveInPane(int delta) {
    final n = _activeCount;
    if (n == 0) return;
    setState(() {
      if (_activePane == 0) {
        _leftSel = (_leftSel + delta).clamp(0, n - 1);
      } else {
        _rightSel = (_rightSel + delta).clamp(0, n - 1);
      }
    });
    _scrollSelectedIntoView();
  }

  void _setActivePane(int pane) {
    setState(() {
      _activePane = pane;
      final n = pane == 0 ? _leftCount : _rightCount;
      if (pane == 0) {
        _leftSel = _leftSel.clamp(0, n == 0 ? 0 : n - 1);
      } else {
        _rightSel = _rightSel.clamp(0, n == 0 ? 0 : n - 1);
      }
    });
    _scrollSelectedIntoView();
  }

  void _scrollSelectedIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _selectedKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool _activated = false; // guard protiv dvostruke aktivacije (onSubmitted + key)

  void _activateSelected() {
    if (_activated) return;
    if (_activeCount == 0) return;
    _activated = true;
    // Router se uzima PRIJE pop-a — nakon njega ovaj context više nije u stablu.
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    if (_activePane == 0) {
      final p = _visiblePersons.length;
      final c = _visibleChannels.length;
      final i = _leftSel.clamp(0, _leftCount - 1);
      if (i < p) {
        drillDownOn(router, _visiblePersons[i].routePath);
      } else if (i < p + c) {
        widget.onSelectChannel(_visibleChannels[i - p]);
      } else {
        widget.onSelectVideo(_visibleVideos[i - p - c].video.id);
      }
    } else {
      final r = _semanticResults[_rightSel.clamp(0, _rightCount - 1)];
      if (r.isSummary) {
        widget.onSelectVideo(r.youtubeId);
      } else {
        widget.onSelectVideoAt(r.youtubeId, r.startSeconds);
      }
    }
  }

  // ── Tier 0 scoring ────────────────────────────────────────────
  /// Osobe koje smiju izgledati kao kanal, dijakritik-neosjetljivo po imenu
  /// („sarolic" i „šarolić" daju isti pogodak). Prazno kad je flag ugašen ili
  /// backend još nema `/api/persons`.
  /// Izračunaj vidljive lokalne rezultate za [_query]. Zove se kad se
  /// promijeni upit ili podaci — NIKAD iz `build()`.
  void _recomputeLocal() {
    if (_query.isEmpty) {
      _visiblePersons = const [];
      _visibleChannels = const [];
      _visibleVideos = const [];
      return;
    }
    final tokens = queryTokens(_query);
    _visiblePersons = _localPersons(tokens);
    _visibleChannels = _localChannels(tokens);
    _visibleVideos = _localVideos(tokens);
  }

  List<PersonSummary> _localPersons(List<String> tokens) {
    if (!_flagOn) return const [];
    final scored = <(double, PersonSummary)>[];
    for (final p in personIndexCache.virtualChannels) {
      final s = localMatchScoreFolded(tokens, foldText(p.name));
      if (s > 0) scored.add((s, p));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return scored.take(5).map((e) => e.$2).toList();
  }

  List<ChannelSummary> _localChannels(List<String> tokens) {
    final scored = <(double, ChannelSummary)>[];
    for (final ch in widget.channels) {
      final s = localMatchScoreFolded(tokens, foldText(ch.name));
      if (s > 0) scored.add((s, ch));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return scored.take(6).map((e) => e.$2).toList();
  }

  List<_IndexedVideo> get _index => _videoIndex ??= [
        for (final hit in channelCache.allVideos)
          (
            hit: hit,
            title: foldText(hit.video.displayTitle),
            // Kombinirani haystack → multi-token upit radi i preko više polja
            // (npr. "šterc demografija": ime u speakers, tema u topics).
            all: foldText([
              hit.video.displayTitle,
              hit.video.title,
              hit.video.speakers.join(' '),
              hit.video.topics.join(' '),
              hit.video.abstract_ ?? '',
              hit.channelName,
            ].join('  ')),
          ),
      ];

  List<_VideoHit> _localVideos(List<String> tokens) {
    final scored = <(double, _VideoHit)>[];
    for (final e in _index) {
      final base = localMatchScoreFolded(tokens, e.all);
      if (base <= 0) continue;
      final titleBoost =
          localMatchScoreFolded(tokens, e.title) > 0 ? 3.0 : 0.0;
      scored.add((base + titleBoost, e.hit));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return scored.take(12).map((e) => e.$2).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.of(context);
    final size = mq.size;

    // Mobitel → pretraga preko cijelog ekrana (kao YouTube/Google na
    // mobitelu). Centrirana paleta s maxHeight 80 % ekrana ne zna za
    // tipkovnicu: u landscapeu ju je tipkovnica prekrila cijelu, a rezultati
    // se nisu vidjeli ni u portraitu ispod polja.
    if (_isCompact(size)) {
      return Material(
        color: theme.colorScheme.surface,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
            child: Column(
              children: [
                _searchHeader(theme, compact: true),
                const Divider(height: 1),
                Expanded(child: _resultsBody(theme, false)),
                // Dok je tipkovnica gore, svaki redak ide rezultatima: u
                // landscapeu je „Otvori po YouTube ID-u" pojeo jedini
                // preostali redak. Vrati se čim se tipkovnica spusti.
                if (mq.viewInsets.bottom == 0) ...[
                  const Divider(height: 1),
                  _idInputSection(theme),
                ],
              ],
            ),
          ),
        ),
      );
    }

    // Desktop (širok ekran) → dvostupčani layout (PO NASLOVU | U SADRŽAJU).
    final twoCol = size.width >= 760;
    final maxWidth = twoCol ? (size.width - 48).clamp(640.0, 960.0) : 640.0;
    // Visina se mjeri NAD tipkovnicom (tablet s on-screen tipkovnicom).
    final maxHeight = (size.height - mq.viewInsets.bottom) * 0.8;

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 40,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _searchHeader(theme, compact: false),
                  const Divider(height: 1),
                  Flexible(child: _resultsBody(theme, twoCol)),
                  const Divider(height: 1),
                  _idInputSection(theme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchHeader(ThemeData theme, {required bool compact}) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: compact
          ? const EdgeInsets.fromLTRB(4, 6, 4, 6)
          : const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Row(
        children: [
          // Na mobitelu je strelica „natrag" jedini izlaz (nema barijere oko
          // palete); × u polju briše upit.
          if (compact)
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: l.commonClose,
              onPressed: () => Navigator.of(context).pop(),
            )
          else ...[
            Icon(Icons.search,
                size: 22, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: TextField(
              key: const ValueKey('search-overlay-field'),
              controller: _searchController,
              focusNode: _searchFocus,
              // autofocus tijekom prvog builda dijaloga (pokrenutog tapom) →
              // pouzdano otvara on-screen tipkovnicu na mobile webu / iOS PWA,
              // gdje programatski requestFocus u postFrame često ne digne keyboard.
              autofocus: true,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.search,
              // Imena i naslovi nisu rječnik: autocorrect „fra" pretvara u
              // nešto drugo, a prijedlozi tipkovnice ostaju (brže tipkanje).
              autocorrect: false,
              onChanged: _onSearchChanged,
              // Desktop: Enter otvara odabrani red (command paleta). Mobitel:
              // tipka „traži" spušta tipkovnicu i otkriva rezultate — prvi
              // rezultat naslijepo nije ono što je korisnik tražio.
              onSubmitted: (_) => compact
                  ? _searchFocus.unfocus()
                  : _activateSelected(),
              style: theme.textTheme.titleMedium,
              decoration: InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintText: l.homeSearchHint,
                hintStyle: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.5),
                  fontWeight: FontWeight.w400,
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (_semanticLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _searchController,
            builder: (context, value, _) {
              if (compact && value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: compact ? l.homeSearchClear : l.commonClose,
                onPressed: compact
                    ? _clearQuery
                    : () => Navigator.of(context).pop(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _resultsBody(ThemeData theme, bool twoCol) {
    if (_query.isEmpty) return _emptyState(theme);

    final hasLocal = _leftCount > 0;
    final hasSemantic = _rightCount > 0;

    if (!hasLocal && !hasSemantic && !_semanticLoading) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            AppLocalizations.of(context).homeSearchNoResults(_query),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    // Auto-fokus na neprazni stupac + clamp indeksa.
    if (_activePane == 0 && _leftCount == 0 && _rightCount > 0) _activePane = 1;
    if (_activePane == 1 && _rightCount == 0 && _leftCount > 0) _activePane = 0;
    if (_leftSel >= _leftCount) _leftSel = _leftCount == 0 ? 0 : _leftCount - 1;
    if (_rightSel >= _rightCount) {
      _rightSel = _rightCount == 0 ? 0 : _rightCount - 1;
    }

    if (twoCol) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _pane(theme,
                pane: 0, scroll: _leftScroll, children: _leftChildren(theme)),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _pane(theme,
                pane: 1, scroll: _rightScroll, children: _rightChildren(theme)),
          ),
        ],
      );
    }

    // Uski — oba stupca složena u jedan scroll. Povlačenje rezultata spušta
    // tipkovnicu (da se vidi što je ispod nje).
    return ListView(
      controller: _leftScroll,
      shrinkWrap: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [..._leftChildren(theme), ..._rightChildren(theme)],
    );
  }

  // Lijevi stupac — osobe + kanali + epizode (PO NASLOVU). [] ako nema
  // lokalnih. Osobe idu PRVE (odluka O6): tko traži ime, traži osobu.
  List<Widget> _leftChildren(ThemeData theme) {
    final l = AppLocalizations.of(context);
    final p = _visiblePersons.length;
    final c = _visibleChannels.length;
    final v = _visibleVideos.length;
    if (p == 0 && c == 0 && v == 0) return const [];
    return [
      if (p > 0) ...[
        _sectionLabel(theme, l.searchSectionPeople),
        for (var i = 0; i < p; i++)
          _selectableRow(
              pane: 0, index: i, child: _personRow(theme, _visiblePersons[i])),
      ],
      if (c > 0) ...[
        _sectionLabel(theme, l.homeSearchSectionChannels),
        for (var i = 0; i < c; i++)
          _selectableRow(
              pane: 0,
              index: p + i,
              child: _channelRow(theme, _visibleChannels[i])),
      ],
      if (v > 0) ...[
        _sectionLabel(theme, l.homeSearchSectionEpisodes),
        for (var i = 0; i < v; i++)
          _selectableRow(
              pane: 0,
              index: p + c + i,
              child: _videoRow(theme, _visibleVideos[i])),
      ],
    ];
  }

  // Desni stupac — semantička pretraga (U SADRŽAJU). [] ako prazno i ne loada.
  List<Widget> _rightChildren(ThemeData theme) {
    final hasSemantic = _rightCount > 0;
    if (!hasSemantic && !_semanticLoading) return const [];
    return [
      _semanticSectionLabel(theme),
      if (hasSemantic)
        for (var i = 0; i < _semanticResults.length; i++)
          _selectableRow(
              pane: 1, index: i, child: _semanticRow(theme, _semanticResults[i]))
      else
        _semanticLoadingRow(theme),
    ];
  }

  // Stupac s blagom pozadinom kad je aktivan (signal fokusa za keyboard nav).
  Widget _pane(ThemeData theme,
      {required int pane,
      required ScrollController scroll,
      required List<Widget> children}) {
    final active = pane == _activePane;
    final body = children.isEmpty
        ? _paneEmpty(theme, pane)
        : ListView(
            controller: scroll,
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: children,
          );
    return Container(
      color: active
          ? theme.colorScheme.primary.withValues(alpha: 0.025)
          : null,
      child: body,
    );
  }

  Widget _paneEmpty(ThemeData theme, int pane) {
    final l = AppLocalizations.of(context);
    final msg = pane == 0
        ? l.homeSearchNoTitleMatches
        : (_semanticLoading
            ? l.homeSearchSearching
            : l.homeSearchNoContentMatches);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          msg,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }

  // Pozadina + key za selektirani red. Aktivni stupac = jači highlight,
  // neaktivni = blaži (da se vidi gdje će se fokus vratiti).
  Widget _selectableRow(
      {required int pane, required int index, required Widget child}) {
    final sel = pane == 0 ? _leftSel : _rightSel;
    final isSel = index == sel;
    final isActive = pane == _activePane;
    final theme = Theme.of(context);
    return Container(
      key: (isSel && isActive) ? _selectedKey : null,
      color: isSel
          ? theme.colorScheme.primary
              .withValues(alpha: isActive ? 0.14 : 0.05)
          : null,
      child: child,
    );
  }

  static bool _isCompact(Size size) => size.shortestSide < _kCompactWidth;

  Widget _emptyState(ThemeData theme) {
    final l = AppLocalizations.of(context);
    // Legenda strelica/Entera ima smisla samo uz fizičku tipkovnicu.
    final showKeyHint = !_isCompact(MediaQuery.sizeOf(context));
    return Padding(
      padding: const EdgeInsets.all(36),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_outlined,
              size: 42,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              l.homeSearchEmptyTitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l.homeSearchEmptySubtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
            if (showKeyHint) ...[
              const SizedBox(height: 10),
              Text(
                l.homeSearchKeyboardHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color:
                      theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 6),
      child: Text(
        text.toUpperCase(),
        style: AppTypography.eyebrowStyle(theme.colorScheme),
      ),
    );
  }

  Widget _semanticSectionLabel(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 6),
      child: Row(
        children: [
          Icon(Icons.auto_awesome,
              size: 13, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            AppLocalizations.of(context).homeSearchSectionContent.toUpperCase(),
            style: AppTypography.eyebrowStyle(theme.colorScheme),
          ),
        ],
      ),
    );
  }

  Widget _semanticLoadingRow(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            AppLocalizations.of(context).homeSearchSemanticLoading,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Redak osobe — monogram, ime (highlightano), „Osoba · N ep · Xh Ym".
  /// Vodi na `/p/<slug>`; slug ide DOSLOVNO iz indeksa.
  Widget _personRow(ThemeData theme, PersonSummary p) {
    return Semantics(
      identifier: 'person-card-${p.slug}',
      container: true,
      child: InkWell(
        onTap: () {
          final router = GoRouter.of(context);
          Navigator.of(context).pop();
          drillDownOn(router, p.routePath);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              PersonMonogram(
                name: p.name,
                avatarUrl: p.avatarUrl,
                size: 40,
                radius: 8,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    QueryHighlightText(
                      p.name,
                      query: _query,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      AppLocalizations.of(context)
                          .personCardMeta(p.episodeCount, p.durationDisplay),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 18, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _channelRow(ThemeData theme, ChannelSummary ch) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        widget.onSelectChannel(ch);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ch.avatarSquare != null
                  ? CachedThumbnail(
                      url: ch.avatarSquare!,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorFallbackBuilder: (_) => _placeholder(theme, 40),
                    )
                  : _placeholder(theme, 40),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  QueryHighlightText(
                    ch.name,
                    query: _query,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    AppLocalizations.of(context)
                        .homeSearchChannelMeta(ch.videoCount, ch.durationDisplay),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: 18, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _videoRow(ThemeData theme, _VideoHit vr) {
    final matchCtx = _localMatchContext(vr.video, _query);
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        widget.onSelectVideo(vr.video.id);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedThumbnail(
                url: CdnConfig.thumbnailUrl(vr.video.id),
                width: 72,
                height: 40,
                fit: BoxFit.cover,
                errorFallbackBuilder: (_) => _thumbPlaceholder(theme, 72, 40),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Naslov se prelama u više redaka (nije skraćen elipsom).
                  QueryHighlightText(
                    vr.video.displayTitle,
                    query: _query,
                    style: theme.textTheme.titleSmall,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          vr.channelName,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      EpisodeAgeChip(vr.video.date),
                    ],
                  ),
                  // Isječak iz polja gdje je query nađen (abstract/teme/govornici).
                  if (matchCtx != null) ...[
                    const SizedBox(height: 3),
                    QueryHighlightText(
                      matchCtx,
                      query: _query,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (vr.video.durationDisplay != null)
              Text(
                vr.video.durationDisplay!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Nađi polje epizode (abstract → teme → govornici) u kojem se query
  /// pojavljuje i vrati kratak isječak oko pogotka. null ako je match bio samo
  /// u naslovu (koji je već prikazan i highlightan).
  String? _localMatchContext(ChannelVideo v, String q) {
    final candidates = <String>[
      if ((v.abstract_ ?? '').trim().isNotEmpty) v.abstract_!.trim(),
      if (v.topics.isNotEmpty) v.topics.join(' · '),
      if (v.speakers.isNotEmpty) v.speakers.join(', '),
    ];
    String? best;
    var bestCount = 0;
    for (final c in candidates) {
      final n = highlightRanges(c, q).length;
      if (n > bestCount) {
        bestCount = n;
        best = c;
      }
    }
    if (best == null) return null;
    return snippetAround(best, q, before: 60, window: 220);
  }

  Widget _semanticRow(ThemeData theme, SemanticResult r) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        if (r.isSummary) {
          widget.onSelectVideo(r.youtubeId);
        } else {
          widget.onSelectVideoAt(r.youtubeId, r.startSeconds);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedThumbnail(
                url: CdnConfig.thumbnailUrl(r.youtubeId),
                width: 72,
                height: 40,
                fit: BoxFit.cover,
                errorFallbackBuilder: (_) => _thumbPlaceholder(theme, 72, 40),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (r.episodeTitle != null)
                    QueryHighlightText(
                      r.episodeTitle!,
                      query: _query,
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 3),
                  QueryHighlightText(
                    snippetAround(r.snippet, _query),
                    query: _query,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (!r.isSummary) ...[
                        Icon(Icons.play_circle_outline,
                            size: 12, color: theme.colorScheme.primary),
                        const SizedBox(width: 3),
                        Text(
                          _fmtTs(r.startSeconds),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      // Govornici u rezultatu SU govornici (ne samo spomenuti)
                      // pa sigurno vode na profil (/p/:slug). Nested tap: ovaj
                      // GestureDetector hvata tap na imenu, ostatak retka i
                      // dalje otvara epizodu.
                      Flexible(
                        child: r.speakers.isNotEmpty
                            ? GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  final router = GoRouter.of(context);
                                  Navigator.of(context).pop();
                                  drillDownOn(router,
                                      '/p/${personSlug(r.speakers.first)}');
                                },
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.person,
                                        size: 11,
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: 0.8)),
                                    const SizedBox(width: 3),
                                    Flexible(
                                      child: Text(
                                        r.speakers.join(', '),
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: theme.colorScheme.primary
                                              .withValues(alpha: 0.9),
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : Text(
                                r.channel,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.7),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                      const SizedBox(width: 8),
                      EpisodeAgeChip(r.uploadDate),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _relevanceMeter(theme, r.score),
          ],
        ),
      ),
    );
  }

  /// Kvantitativna metrika relevantnosti uz semantički rezultat: tanki bar
  /// (fill ~ score, normaliziran na 0.30–0.70 raspon gdje su realni pogoci) +
  /// sirovi score. Tooltip objašnjava značenje.
  Widget _relevanceMeter(ThemeData theme, double score) {
    final norm = ((score - 0.30) / 0.40).clamp(0.0, 1.0);
    final color = norm >= 0.66
        ? const Color(0xFF2E7D32) // zelena — jak pogodak
        : norm >= 0.33
            ? const Color(0xFFF9A825) // jantar — srednji
            : theme.colorScheme.outline; // slab
    return Tooltip(
      message: AppLocalizations.of(context)
          .homeSearchRelevanceTooltip(score.toStringAsFixed(2)),
      child: SizedBox(
        width: 36,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: norm,
                minHeight: 5,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              score.toStringAsFixed(2),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _idInputSection(ThemeData theme) {
    final l = AppLocalizations.of(context);
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _showIdInput = !_showIdInput),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    _showIdInput
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l.homeSearchOpenById,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_showIdInput)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _idController,
                      style: theme.textTheme.bodyMedium,
                      decoration: InputDecoration(
                        hintText: l.homeSearchIdHint,
                        isDense: true,
                      ),
                      textInputAction: TextInputAction.go,
                      onSubmitted: (_) => _openVideoId(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _openVideoId,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.brandPrimary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Icon(Icons.play_arrow, size: 18),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholder(ThemeData theme, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.podcasts,
          size: size * 0.5,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
    );
  }

  Widget _thumbPlaceholder(ThemeData theme, double w, double h) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(Icons.ondemand_video,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
    );
  }

  String _fmtTs(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    final ss = sec.toString().padLeft(2, '0');
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
    return '$m:$ss';
  }
}
