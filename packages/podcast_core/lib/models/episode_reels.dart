/// Model za `data/<id>/reels.json` — istaknuti trenuci epizode i vertikalni
/// (9:16) isječci izrezani iz njih.
///
/// Producent: `fetch.domovina.tv` (kandidati + render), ugovor u
/// `fetch.domovina.tv/docs/2026-10-25-reels-kandidati.md`. Svaki zapis je
/// trenutak u epizodi (`start_sec`…`end_sec`, apsolutno vrijeme = pozicija na
/// timelineu); samo zapisi s `render.url` imaju i video. Ostali su samo
/// trenutak — tap skoči u epizodu.
///
/// Parser je defenzivan kao i [SponsorsInVideo]: zapis bez valjanog raspona
/// ili naslova se preskače, nepoznata verzija se pokuša pročitati, a pokvaren
/// `render` znači samo da trenutak nema video.
library;

/// Renderirani 9:16 isječak jednog trenutka.
class EpisodeReelRender {
  /// `reels/<rank>-<sha8>.mp4` — H.264, ključ je verzioniran (immutable).
  final String url;

  /// Jedan 9:16 kadar za karticu. Do backfilla ga nema; tada kartica nosi
  /// ikonu. `storyboard_url` (kontaktni list od šest kadrova) namjerno se ne
  /// koristi kao poster.
  final String? posterUrl;

  /// Stvarni raspon izrezanog klipa — može se za djelić sekunde razlikovati
  /// od raspona trenutka.
  final double clipStartSec;
  final double durationSec;

  /// Režirani isječak (`render.premium`, objekt `{ beats, tail_sec }`):
  /// uz tekstualne kartice nosi i ilustracije usidrene na izgovorene riječi.
  /// Polje je opcionalno i aditivno — izostanak znači standardni isječak.
  final bool isPremium;

  const EpisodeReelRender({
    required this.url,
    this.posterUrl,
    required this.clipStartSec,
    required this.durationSec,
    this.isPremium = false,
  });

  static EpisodeReelRender? tryParse(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final url = _https(raw['url']);
    if (url == null) return null;
    return EpisodeReelRender(
      url: url,
      posterUrl: _https(raw['poster_url']),
      clipStartSec: _num(raw['clip_start_sec']) ?? 0,
      durationSec: _num(raw['duration_sec']) ?? 0,
      isPremium: raw['premium'] is Map,
    );
  }
}

/// Jedan istaknuti trenutak epizode.
class EpisodeReel {
  final int rank;
  final double startSec;
  final double endSec;
  final String title;
  final String? hook;
  final String? speaker;

  /// Null = trenutak bez videa (samo skok u epizodu).
  final EpisodeReelRender? render;

  const EpisodeReel({
    required this.rank,
    required this.startSec,
    required this.endSec,
    required this.title,
    this.hook,
    this.speaker,
    this.render,
  });

  bool get isRendered => render != null;

  /// Režirani isječak — vidi [EpisodeReelRender.isPremium].
  bool get isPremium => render?.isPremium ?? false;

  Duration get startPosition =>
      Duration(milliseconds: (startSec * 1000).round());
  Duration get endPosition => Duration(milliseconds: (endSec * 1000).round());

  /// Cijele sekunde za share link i prikaz vremena.
  int get startSeconds => startSec.floor();
  int get durationSeconds => (endSec - startSec).round();

  bool contains(Duration pos) => pos >= startPosition && pos < endPosition;

  static EpisodeReel? tryParse(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final start = _num(raw['start_sec']);
    final end = _num(raw['end_sec']);
    final title = _nonEmpty(raw['title']);
    if (start == null || end == null || title == null) return null;
    if (start < 0 || end <= start) return null;
    return EpisodeReel(
      rank: _num(raw['rank'])?.toInt() ?? 0,
      startSec: start,
      endSec: end,
      title: title,
      hook: _nonEmpty(raw['hook']),
      speaker: _nonEmpty(raw['speaker']),
      render: EpisodeReelRender.tryParse(raw['render']),
    );
  }
}

/// Sadržaj `reels.json` za jednu epizodu.
class EpisodeReels {
  /// Poredani po početku — tim redom stoje i na timelineu i u traci.
  final List<EpisodeReel> reels;

  const EpisodeReels(this.reels);

  factory EpisodeReels.fromJson(Map<String, dynamic> json) {
    final list = json['reels'];
    final reels = [
      if (list is List)
        for (final r in list) ?EpisodeReel.tryParse(r),
    ]..sort((a, b) => a.startSec.compareTo(b.startSec));
    return EpisodeReels(reels);
  }

  bool get isEmpty => reels.isEmpty;
  bool get isNotEmpty => reels.isNotEmpty;

  /// Trenutak koji upravo svira (prvi po početku ako se preklapaju).
  EpisodeReel? activeAt(Duration pos) {
    for (final r in reels) {
      if (r.contains(pos)) return r;
    }
    return null;
  }
}

double? _num(Object? v) => v is num && v.isFinite ? v.toDouble() : null;

String? _nonEmpty(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

/// Samo apsolutni https URL — relativna putanja ili drugi scheme ne ulaze u
/// player ni u `Image`.
String? _https(Object? v) {
  final s = _nonEmpty(v);
  if (s == null) return null;
  final uri = Uri.tryParse(s);
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty ? s : null;
}
