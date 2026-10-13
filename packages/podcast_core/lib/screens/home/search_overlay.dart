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
import '../../services/meili_client.dart';
import '../../services/search_service.dart';
import '../../services/unified_search.dart';
import '../../src/log.dart' show log;
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
typedef _IndexedVideo = ({
  _VideoHit hit,
  String title,
  String speakers,
  String all,
});

class _SearchOverlayState extends State<_SearchOverlay> {
  final _searchController = TextEditingController();
  final _idController = TextEditingController();
  late final FocusNode _searchFocus;
  Timer? _debounce;
  Timer? _meiliDebounce;
  Timer? _semanticDebounce;
  // Završava se kad upit zastari — prekida semantički zahtjev u letu.
  Completer<void>? _semanticAbort;
  Timer? _dataDebounce;
  String _query = '';
  // Upiti za koje su poslani (ili se šalju) mrežni zahtjevi — normalizirani,
  // pa „fra" → „fra " ne okida novi zahtjev; odgovor za stari upit se baca.
  String _meiliQuery = '';
  String _semanticQuery = '';

  // Foldani tekst epizoda, računa se JEDNOM po stanju `channelCache`-a, ne pri
  // svakom buildu. Korpus je ~3300 epizoda / 2,7 MB teksta; prije je cijeli
  // prolazio kroz `foldText` u svakom `build()` (spinner, stigli rezultati,
  // svaka notifikacija cachea), ~75 ms na M-čipu i višestruko više na
  // mobitelu — tipkanje je štucalo.
  List<_IndexedVideo>? _videoIndex;
  bool _showIdInput = false;

  // Tri izvora (vidi `services/unified_search.dart`).
  List<LocalEpisodeMatch> _localResults = const [];
  List<MeiliHit> _meiliResults = const [];
  List<SemanticResult> _semanticResults = const [];
  bool _meiliLoading = false;
  bool _semanticLoading = false;
  bool get _loading => _meiliLoading || _semanticLoading;

  // Vidljivi redovi, jednim redom: osobe → kanali → epizode. Isti redoslijed
  // dijele build i tipkovnica.
  List<PersonSummary> _visiblePersons = const [];
  List<ChannelSummary> _visibleChannels = const [];
  List<EpisodeHit> _visibleEpisodes = const [];

  // Odabrani red za ↑/↓/Enter. Pamti se i ID epizode, da odabir ostane na
  // istoj epizodi kad Meili ili semantika stignu i presalože listu.
  int _sel = 0;
  String? _selEpisodeId;
  final _scroll = ScrollController();
  final _selectedKey = GlobalKey();

  /// Osobe (virtualni kanali) iza `PersonChannelFlag`-a. Lokalni match nad
  /// `PersonIndexCache`-om — `/api/search` se NE dira (odluka O6 u
  /// `docs/plans/virtualni-kanali.md`): osobe su egzaktan lookup po imenu, a
  /// lokalni match je brži, jeftiniji i radi offline.
  bool _flagOn = false;

  int get _count =>
      _visiblePersons.length + _visibleChannels.length + _visibleEpisodes.length;

  @override
  void initState() {
    super.initState();
    // onKeyEvent na samom FocusNode-u fokusiranog polja → dobiva event PRIJE
    // text-editing shortcutova (↑/↓ inače pomiču kursor).
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
    _meiliDebounce?.cancel();
    _semanticDebounce?.cancel();
    _abortSemantic();
    _scroll.dispose();
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
          _sel = 0;
          _selEpisodeId = null;
          // Rezultati mreže za stari upit više ne vrijede.
          if (_meiliQuery != q) _meiliResults = const [];
          if (_semanticQuery != q) _semanticResults = const [];
          _recomputeLocal();
        });
      });
    }

    // Meili — full-text, brz (desetak ms na serveru), pa kraći debounce.
    if (q != _meiliQuery) {
      _meiliDebounce?.cancel();
      if (q.length < 2) {
        _meiliQuery = '';
        _meiliLoading = false;
      } else {
        _meiliDebounce = Timer(const Duration(milliseconds: 200), () {
          _runMeili(q);
        });
      }
    }

    // Semantika — duži debounce + min duljina (štedi mrežu/embeddinge).
    if (q != _semanticQuery) {
      _semanticDebounce?.cancel();
      _abortSemantic();
      if (q.length < 3) {
        _semanticQuery = '';
        _semanticLoading = false;
      } else {
        _semanticDebounce = Timer(const Duration(milliseconds: 420), () {
          _runSemantic(q);
        });
      }
    }
  }

  void _clearQuery() {
    _searchController.clear();
    _onSearchChanged('');
    _searchFocus.requestFocus();
  }

  Future<void> _runMeili(String q) async {
    _meiliQuery = q;
    setState(() => _meiliLoading = true);
    List<MeiliHit> hits;
    try {
      // Bez funkcijskih riječi i sa SVIM preostalima: inače „što je rekao
      // papa…" vrati svaki naslov s „je" ili „o" (vidi `contentQuery`).
      hits = (await MeiliClient.search(contentQuery(q),
              matchingStrategy: 'all', limit: 12))
          .hits;
    } catch (e) {
      // Meili nedostupan → ostaju lokalni i semantički rezultati.
      log('SearchOverlay: Meili greška za "$q": $e');
      hits = const [];
    }
    if (!mounted || _meiliQuery != q) return;
    setState(() {
      _meiliResults = hits;
      _meiliLoading = false;
      _remerge();
    });
  }

  Future<void> _runSemantic(String q) async {
    _semanticQuery = q;
    setState(() => _semanticLoading = true);
    // DOMOVINA Plus dobiva veći set rezultata (free ostaje pun i koristan).
    final limit = EntitlementService.instance.isPlus.value ? 30 : 12;
    final abort = _semanticAbort = Completer<void>();
    final results = await SearchService.search(q,
        limit: limit, abortTrigger: abort.future);
    if (identical(_semanticAbort, abort)) _semanticAbort = null;
    if (!mounted || _semanticQuery != q) return;
    setState(() {
      _semanticResults = results;
      _semanticLoading = false;
      _remerge();
    });
  }

  void _abortSemantic() {
    final a = _semanticAbort;
    _semanticAbort = null;
    if (a != null && !a.isCompleted) a.complete();
  }

  void _openVideoId() {
    final id = _idController.text.trim();
    if (id.isEmpty) return;
    Navigator.of(context).pop();
    widget.onSelectVideo(id);
  }

  /// Puni prikaz (Meili, filtar po kanalu) za isti upit.
  void _openFullResults() {
    final router = GoRouter.of(context);
    final q = normalizeQuery(_searchController.text);
    Navigator.of(context).pop();
    drillDownOn(router,
        q.isEmpty ? '/search' : '/search?q=${Uri.encodeQueryComponent(q)}');
  }

  // ── Keyboard navigacija ─────────────────────────────────────────
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      // Na mobitelu Enter (Gboard ga na webu šalje i kao keydown) ide kroz
      // `onSubmitted`, koji samo spušta tipkovnicu.
      if (_isCompact(MediaQuery.sizeOf(context))) return KeyEventResult.ignored;
      if (_count > 0) {
        _activateSelected();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _move(int delta) {
    if (_count == 0) return;
    setState(() => _select((_sel + delta).clamp(0, _count - 1)));
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

  void _select(int i) {
    _sel = i;
    final e = i - _visiblePersons.length - _visibleChannels.length;
    _selEpisodeId =
        e >= 0 && e < _visibleEpisodes.length ? _visibleEpisodes[e].youtubeId : null;
  }

  bool _activated = false; // guard protiv dvostruke aktivacije (onSubmitted + key)

  void _activateSelected() {
    if (_activated || _count == 0) return;
    _activated = true;
    final p = _visiblePersons.length;
    final c = _visibleChannels.length;
    final i = _sel.clamp(0, _count - 1);
    if (i < p) {
      _openPerson(_visiblePersons[i]);
    } else if (i < p + c) {
      _openChannel(_visibleChannels[i - p]);
    } else {
      _openEpisode(_visibleEpisodes[i - p - c]);
    }
  }

  void _openPerson(PersonSummary person) {
    // Router se uzima PRIJE pop-a — nakon njega ovaj context više nije u stablu.
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    drillDownOn(router, person.routePath);
  }

  void _openChannel(ChannelSummary ch) {
    Navigator.of(context).pop();
    widget.onSelectChannel(ch);
  }

  void _openEpisode(EpisodeHit hit, {int? at}) {
    Navigator.of(context).pop();
    final seconds = at ?? hit.openAt;
    if (seconds != null) {
      widget.onSelectVideoAt(hit.youtubeId, seconds);
    } else {
      widget.onSelectVideo(hit.youtubeId);
    }
  }

  // ── Lokalni sloj + spajanje ─────────────────────────────────────
  /// Izračunaj lokalne rezultate za [_query] i spoji ih s mrežnima. Zove se
  /// kad se promijeni upit ili podaci — NIKAD iz `build()`.
  void _recomputeLocal() {
    if (_query.isEmpty) {
      _visiblePersons = const [];
      _visibleChannels = const [];
      _localResults = const [];
      _meiliResults = const [];
      _semanticResults = const [];
      _visibleEpisodes = const [];
      return;
    }
    // Funkcijske riječi bi uz AND semantiku tražile „je" i „o" u svakoj
    // epizodi; za ime osobe ili kanala ionako ne nose ništa.
    final tokens = queryTokens(contentQuery(_query));
    _visiblePersons = _localPersons(tokens);
    _visibleChannels = _localChannels(tokens);
    _localResults = _localVideos(tokens);
    _remerge();
  }

  void _remerge() {
    _visibleEpisodes = mergeSearchResults(
      query: _query,
      local: _localResults,
      meili: _meiliResults,
      semantic: _semanticResults,
      channelName: _channelNameForSlug,
    ).take(20).toList();
    // Odabir prati epizodu, ne poziciju.
    final id = _selEpisodeId;
    if (id != null) {
      final e = _visibleEpisodes.indexWhere((h) => h.youtubeId == id);
      if (e >= 0) {
        _sel = _visiblePersons.length + _visibleChannels.length + e;
        return;
      }
    }
    if (_sel >= _count) _sel = _count == 0 ? 0 : _count - 1;
  }

  String? _channelNameForSlug(String slug) {
    for (final c in widget.channels) {
      if (c.id == slug) return c.name;
    }
    final name = channelCache.get(slug)?.name;
    return name;
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
            // Naslov i govornici: pogodak ovdje je „po naslovu / osobi" i
            // rangira se iznad spominjanja u tekstu; naslov iznad govornika.
            title: foldText(hit.video.displayTitle),
            speakers: foldText(hit.video.speakers.join('  ')),
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

  List<LocalEpisodeMatch> _localVideos(List<String> tokens) {
    final scored = <(double, _VideoHit, bool)>[];
    for (final e in _index) {
      final base = localMatchScoreFolded(tokens, e.all);
      if (base <= 0) continue;
      final inTitle = localMatchScoreFolded(tokens, e.title) > 0;
      final inSpeakers = localMatchScoreFolded(tokens, e.speakers) > 0;
      scored.add((
        base + (inTitle ? 6.0 : 0.0) + (inSpeakers ? 3.0 : 0.0),
        e.hit,
        inTitle || inSpeakers,
      ));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return [
      for (final (_, hit, head) in scored.take(12))
        (
          channelId: hit.channelId,
          channelName: hit.channelName,
          video: hit.video,
          titleMatch: head,
          snippet: _localMatchContext(hit.video, _query),
        ),
    ];
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
                Expanded(child: _resultsBody(theme)),
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

    // Desktop → paleta s jednom spojenom listom (vidi `unified_search.dart`).
    final maxWidth = (size.width - 48).clamp(560.0, 720.0);
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
                  Flexible(child: _resultsBody(theme)),
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

  Widget _resultsBody(ThemeData theme) {
    if (_query.isEmpty) return _emptyState(theme);
    final l = AppLocalizations.of(context);

    if (_count == 0) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: _loading
              ? _loadingRow(theme)
              : Text(
                  l.homeSearchNoResults(_query),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
        ),
      );
    }

    final p = _visiblePersons.length;
    final c = _visibleChannels.length;
    final e = _visibleEpisodes.length;
    // Povlačenje rezultata spušta tipkovnicu (da se vidi što je ispod nje).
    return ListView(
      controller: _scroll,
      shrinkWrap: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // Osobe idu PRVE (odluka O6): tko traži ime, traži osobu.
        if (p > 0) ...[
          _sectionLabel(theme, l.searchSectionPeople),
          for (var i = 0; i < p; i++)
            _selectableRow(i, _personRow(theme, _visiblePersons[i])),
        ],
        if (c > 0) ...[
          _sectionLabel(theme, l.homeSearchSectionChannels),
          for (var i = 0; i < c; i++)
            _selectableRow(p + i, _channelRow(theme, _visibleChannels[i])),
        ],
        if (e > 0) ...[
          _sectionLabel(theme, l.homeSearchSectionEpisodes),
          for (var i = 0; i < e; i++)
            _selectableRow(
                p + c + i, _episodeRow(theme, _visibleEpisodes[i])),
        ],
        // Mreža još dopunjuje listu — tiha oznaka na dnu, lista ne skače.
        if (_loading) _loadingRow(theme),
      ],
    );
  }

  Widget _selectableRow(int index, Widget child) {
    final isSel = index == _sel;
    return Container(
      key: isSel ? _selectedKey : null,
      color: isSel
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
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

  Widget _loadingRow(ThemeData theme) {
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
            AppLocalizations.of(context).homeSearchSearching,
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

  /// Redak epizode iz bilo kojeg izvora. Ispod naslova: kanal (ako ga smijemo
  /// pokazati) + datum, isječak s isticanjem, i semantički trenuci kao chipovi
  /// za skok na točnu sekundu.
  Widget _episodeRow(ThemeData theme, EpisodeHit hit) {
    final l = AppLocalizations.of(context);
    return InkWell(
      onTap: () => _openEpisode(hit),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedThumbnail(
                url: CdnConfig.thumbnailUrl(hit.youtubeId),
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
                  QueryHighlightText(
                    hit.title.text,
                    query: _query,
                    ranges: hit.title.ranges,
                    style: theme.textTheme.titleSmall,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (hit.channelName != null) ...[
                        Flexible(
                          child: Text(
                            hit.channelName!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      EpisodeAgeChip(hit.date),
                    ],
                  ),
                  if (hit.snippet != null) ...[
                    const SizedBox(height: 3),
                    QueryHighlightText(
                      hit.snippet!.ranges.isEmpty
                          ? snippetAround(hit.snippet!.text, _query,
                              before: 60, window: 220)
                          : hit.snippet!.text,
                      query: _query,
                      ranges: hit.snippet!.ranges,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (hit.moments.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final m in hit.moments)
                          ActionChip(
                              avatar: Icon(Icons.play_arrow,
                                  size: 14, color: theme.colorScheme.primary),
                              label: Text(_fmtTs(m.seconds)),
                              labelStyle: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                              tooltip: l.homeSearchJumpTo(_fmtTs(m.seconds)),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              onPressed: () => _openEpisode(hit, at: m.seconds),
                            ),
                      ],
                    ),
                  ],
                ],
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

  Widget _idInputSection(ThemeData theme) {
    final l = AppLocalizations.of(context);
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: Column(
        children: [
          // Overlay je brzi skok; puni prikaz (filtar po kanalu, svi pogoci)
          // je `/search` s istim upitom.
          if (_query.isNotEmpty)
            InkWell(
              onTap: _openFullResults,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.manage_search,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l.homeSearchShowAll,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(Icons.arrow_forward,
                        size: 16, color: theme.colorScheme.primary),
                  ],
                ),
              ),
            ),
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
