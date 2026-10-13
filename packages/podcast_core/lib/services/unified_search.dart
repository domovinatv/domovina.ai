/// Spajanje triju izvora pretrage naslovnice u JEDAN rezultat po epizodi.
///
/// - **lokalno** (Tier 0): `channelCache` + `search.json` — instant, offline,
///   ali samo epizode praćenih kanala;
/// - **Meili** `episodes`: full-text nad naslovom, naslovima sekcija i cijelim
///   člankom, typo-tolerantan — jedini full-text izvor koji ima i epizode bez
///   listinga (`_unlisted`, ad-hoc obrade iz pipelinea);
/// - **semantika** (`/api/search`): chunkovi s točnom sekundom.
///
/// Ključ je YouTube ID. Semantički chunkovi iste epizode NE dobivaju svaki
/// svoj red — skupljaju se u [EpisodeHit.moments] („skočni" pod-pogoci), da
/// pet chunkova jedne epizode ne pojede listu.
library;

import '../models/channel_detail.dart';
import '../utils/text_search.dart';
import 'meili_client.dart';
import 'search_service.dart';

enum SearchSource { local, meili, semantic }

/// Razred pogotka; niži indeks = više u listi.
enum MatchTier {
  /// Upit je u naslovu ili imenu govornika.
  title,

  /// Upit je u tekstu (članak, sažetak, teme).
  text,

  /// Samo semantička sličnost — riječi upita možda nisu nigdje.
  semantic,
}

/// Lokalni (Tier 0) pogodak, već rangiran.
typedef LocalEpisodeMatch = ({
  String channelId,
  String channelName,
  ChannelVideo video,
  bool titleMatch,
  String? snippet,
});

/// Trenutak u epizodi na koji se može skočiti.
class SearchMoment {
  final int seconds;
  final String text;
  final double score;
  const SearchMoment(
      {required this.seconds, required this.text, required this.score});
}

/// Tekst s rasponima isticanja `[start, end)` (iz Meilijevih `<em>` tagova).
typedef MarkedText = ({String text, List<List<int>> ranges});

class EpisodeHit {
  final String youtubeId;
  final MarkedText title;

  /// `null` za epizode bez kanala koji smijemo pokazati (`_unlisted`).
  final String? channelName;
  final String? date;
  final MarkedText? snippet;
  final List<SearchMoment> moments;
  final MatchTier tier;
  final Set<SearchSource> sources;

  const EpisodeHit({
    required this.youtubeId,
    required this.title,
    required this.channelName,
    required this.date,
    required this.snippet,
    required this.moments,
    required this.tier,
    required this.sources,
  });

  /// Kamo vodi tap na red: epizoda koju je našla SAMO semantika otvara se na
  /// najboljem trenutku (zato je i nađena), sve ostalo od početka.
  int? get openAt =>
      tier == MatchTier.semantic && moments.isNotEmpty ? _best.seconds : null;

  SearchMoment get _best =>
      moments.reduce((a, b) => b.score > a.score ? b : a);
}

/// Makni `<em>`/`</em>` i vrati raspone koje su omeđivali.
MarkedText parseEmTags(String tagged) {
  const open = '<em>', close = '</em>';
  final buf = StringBuffer();
  final ranges = <List<int>>[];
  var i = 0;
  int? start;
  while (i < tagged.length) {
    if (tagged.startsWith(open, i)) {
      start = buf.length;
      i += open.length;
    } else if (tagged.startsWith(close, i)) {
      if (start != null && buf.length > start) ranges.add([start, buf.length]);
      start = null;
      i += close.length;
    } else {
      buf.write(tagged[i]);
      i++;
    }
  }
  return (text: buf.toString(), ranges: ranges);
}

/// Pokrivaju li istaknuti dijelovi [m] SVE riječi upita? Meili po defaultu
/// odbacuje riječi s kraja upita dok ne nađe pogotke (`matchingStrategy:
/// last`), pa „damir sabol" vrati i svakog „Damira" s istaknutim samo prvim
/// imenom. Takav pogodak nije „po naslovu".
bool coversAllTokens(MarkedText m, List<String> tokens) {
  if (tokens.isEmpty || m.ranges.isEmpty) return false;
  final marked = [
    for (final r in m.ranges) foldText(m.text.substring(r[0], r[1]))
  ];
  return tokens.every((t) => marked.any((w) {
        // Meili ističe cijelu riječ i prašta tipfelere/nastavke: dovoljan je
        // zajednički prefiks (najviše 4 znaka, kao `highlightRanges`).
        final n = [t.length, w.length, 4].reduce((a, b) => a < b ? a : b);
        return n > 0 && w.substring(0, n) == t.substring(0, n);
      }));
}

/// Pogođeni naslovi sekcija („…<em>Sabol</em>…") spojeni u jedan redak.
MarkedText? _matchedSections(List<String> tagged) {
  final parts = [
    for (final t in tagged)
      if (t.contains('<em>')) parseEmTags(t),
  ];
  if (parts.isEmpty) return null;
  final buf = StringBuffer();
  final ranges = <List<int>>[];
  for (final p in parts.take(3)) {
    if (buf.isNotEmpty) buf.write(' · ');
    final off = buf.length;
    buf.write(p.text);
    for (final r in p.ranges) {
      ranges.add([r[0] + off, r[1] + off]);
    }
  }
  return (text: buf.toString(), ranges: ranges);
}

/// Slug kanala koji korisnik ne smije vidjeti (`_unlisted`, interni).
bool isHiddenChannel(String slug) => slug.isEmpty || slug.startsWith('_');

class _Acc {
  final String id;
  MarkedText? title;
  String? channelName;
  String? date;
  MarkedText? snippet;
  MatchTier tier = MatchTier.semantic;
  final sources = <SearchSource>{};
  final semantic = <SemanticResult>[];
  // Položaj u svakom izvoru (manje = bolje) — za redoslijed unutar razreda.
  int? localRank;
  int? meiliRank;
  double semanticScore = 0;

  _Acc(this.id);

  void lift(MatchTier t) {
    if (t.index < tier.index) tier = t;
  }

  /// Najbolji položaj u nekom full-text izvoru; lokalni i Meili poredak se
  /// isprepliću (1. lokalni, 1. Meili, 2. lokalni…), a lokalni ima prednost
  /// pri jednakosti jer je instant i već ga je korisnik vidio.
  double get textRank {
    final l = localRank == null ? double.infinity : localRank! * 2.0;
    final m = meiliRank == null ? double.infinity : meiliRank! * 2.0 + 1;
    return l < m ? l : m;
  }
}

/// Spoji tri izvora u rangiranu listu epizoda.
///
/// [channelName] pretvara slug kanala (Meili, semantika) u ime za prikaz;
/// vraća `null` kad ga ne zna. Skriveni kanali ([isHiddenChannel]) se nikad
/// ne prikazuju, ni kao slug.
List<EpisodeHit> mergeSearchResults({
  required String query,
  List<LocalEpisodeMatch> local = const [],
  List<MeiliHit> meili = const [],
  List<SemanticResult> semantic = const [],
  required String? Function(String slug) channelName,
  int maxMoments = 3,
}) {
  final tokens = queryTokens(query);
  final byId = <String, _Acc>{};
  _Acc acc(String id) => byId.putIfAbsent(id, () => _Acc(id));

  String? displayChannel(String slug) =>
      isHiddenChannel(slug) ? null : channelName(slug);

  for (var i = 0; i < local.length; i++) {
    final m = local[i];
    final a = acc(m.video.id)
      ..sources.add(SearchSource.local)
      ..localRank = i
      ..title = (text: m.video.displayTitle, ranges: const [])
      ..channelName =
          isHiddenChannel(m.channelId) ? null : m.channelName
      ..date = m.video.date;
    if (m.snippet != null) a.snippet = (text: m.snippet!, ranges: const []);
    a.lift(m.titleMatch ? MatchTier.title : MatchTier.text);
  }

  for (var i = 0; i < meili.length; i++) {
    final h = meili[i];
    if (h.youtubeId.isEmpty) continue;
    final a = acc(h.youtubeId)
      ..sources.add(SearchSource.meili)
      ..meiliRank ??= i;
    final title = parseEmTags(h.formattedTitle);
    // Meilijev naslov nosi isticanje — bolji je i kad lokalni postoji.
    a.title = title.ranges.isNotEmpty || a.title == null ? title : a.title;
    a.channelName ??= displayChannel(h.channel);
    a.date ??= h.uploadDate.isEmpty ? null : h.uploadDate;
    if (a.snippet == null) {
      final snip = parseEmTags(h.formattedArticleSnippet);
      a.snippet = snip.text.trim().isNotEmpty
          ? snip
          : _matchedSections(h.formattedSectionTitles);
    }
    a.lift(coversAllTokens(title, tokens) ? MatchTier.title : MatchTier.text);
  }

  for (final r in semantic) {
    if (r.youtubeId.isEmpty) continue;
    final a = acc(r.youtubeId)..sources.add(SearchSource.semantic);
    a.semantic.add(r);
    if (r.score > a.semanticScore) a.semanticScore = r.score;
    a.title ??= (text: r.episodeTitle ?? r.youtubeId, ranges: const []);
    a.channelName ??= displayChannel(r.channel);
    a.date ??= r.uploadDate.isEmpty ? null : r.uploadDate;
  }

  final hits = <(EpisodeHit, _Acc)>[];
  for (final a in byId.values) {
    // Trenuci: samo chunkovi s vremenom, najbolji po scoreu, bez dvaput istog
    // mjesta (susjedni chunkovi unutar 30 s), pa poredani po vremenu.
    final timed = a.semantic.where((r) => !r.isSummary).toList()
      ..sort((x, y) => y.score.compareTo(x.score));
    final moments = <SearchMoment>[];
    for (final r in timed) {
      if (moments.length >= maxMoments) break;
      if (moments.any((m) => (m.seconds - r.startSeconds).abs() < 30)) continue;
      moments.add(SearchMoment(
          seconds: r.startSeconds, text: r.snippet, score: r.score));
    }
    moments.sort((x, y) => x.seconds.compareTo(y.seconds));

    var snippet = a.snippet;
    if (snippet == null && a.semantic.isNotEmpty) {
      final best = a.semantic.reduce((x, y) => y.score > x.score ? y : x);
      snippet = (text: best.snippet, ranges: const []);
    }

    hits.add((
      EpisodeHit(
        youtubeId: a.id,
        title: a.title!,
        channelName: a.channelName,
        date: a.date,
        snippet: snippet,
        moments: moments,
        tier: a.tier,
        sources: Set.unmodifiable(a.sources),
      ),
      a,
    ));
  }

  hits.sort((x, y) {
    final t = x.$1.tier.index.compareTo(y.$1.tier.index);
    if (t != 0) return t;
    if (x.$1.tier == MatchTier.semantic) {
      return y.$2.semanticScore.compareTo(x.$2.semanticScore);
    }
    final r = x.$2.textRank.compareTo(y.$2.textRank);
    if (r != 0) return r;
    // Isti položaj u full-text izvorima → semantika presuđuje.
    return y.$2.semanticScore.compareTo(x.$2.semanticScore);
  });
  return [for (final h in hits) h.$1];
}
