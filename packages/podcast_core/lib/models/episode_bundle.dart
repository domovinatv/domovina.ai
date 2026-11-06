import 'dart:convert';

import 'catalog_card.dart';

/// `data/<id>/episode.json` — jedna datoteka po epizodi koju pipeline slaže
/// nakon svakog uploada u `data/<id>/`.
///
/// Zašto postoji: ekran epizode traži ~18 datoteka, a tipično ih postoji 7.
/// Svaki 404 se ponavlja s cache-busterom (vidi `DataService._get`), pa
/// otvaranje epizode na sporoj mreži koči ~33 povratna putovanja, većinom
/// uzaludna. Ovaj fajl u jednom zahtjevu nosi sve što treba za prvi prikaz i
/// popis datoteka koje postoje — ostalo se traži samo ako je na popisu.
/// Mjerenja: `docs/2026-10-08-brzina-ucitavanja-naslovnice.md` §8.
///
/// **Ugovor (v1)**:
/// ```json
/// {
///   "version": 1,
///   "generated_at": "2026-10-10T02:14:00Z",
///   "files": ["info.json", "summary.json", "article.json", "diarized.srt",
///             "words.json", "video_h264.mp4", "book.epub", …],
///   "inline": {"info.json": {…}, "summary.json": {…}, "outline.json": {…},
///              "article.json": {…}, "article.magisterium.json": {…}}
/// }
/// ```
/// - `files` je IZMJERENI popis (listing R2 prefiksa `data/<id>/`), ne
///   namjera pipelinea — imena kako ih servira CDN.
/// - `inline` ključ je ime datoteke, vrijednost njezin sadržaj (JSON objekt;
///   tekstualna datoteka kao string). Titlovi, vrijeme po riječi i EN
///   prijevodi ostaju vani: to su 2/3 bajtova, a ne trebaju za prvi prikaz.
///
/// - `channel` (aditivno od 6. 11. 2026., katalog odluke 705–707):
///   `{slug, name, tier}` ([CatalogChannel]) ili `null` = katalog je epizodu
///   vidio bez kanala. Nose ga samo epizode prvi put viđene nakon tog datuma;
///   kod starih ključ izostaje = nepoznato ([channelKnown] je `false`).
///
/// Nepoznata verzija ili nečitljiv oblik → `null`, pa klijent ide starim
/// putem (datoteku po datoteku). Stari put ostaje zauvijek.
class EpisodeBundle {
  static const int supportedVersion = 1;
  static const String fileName = 'episode.json';

  final Set<String> files;
  final Map<String, Object> inline;

  /// Je li bundle rekao išta o kanalu: ključ `channel` postoji i vrijednost
  /// je `null` ili ispravan objekt. `false` za stare bundleove (ključ
  /// izostaje) i za nečitljivu vrijednost — tada kanal treba pitati drugdje.
  final bool channelKnown;

  /// Kanal iz kataloga; `null` uz [channelKnown] znači „katalog epizodu ima
  /// bez kanala”.
  final CatalogChannel? channel;

  const EpisodeBundle({
    required this.files,
    required this.inline,
    this.channelKnown = false,
    this.channel,
  });

  static EpisodeBundle? tryParse(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) return null;
      if ((json['version'] as num?)?.toInt() != supportedVersion) return null;
      final files = json['files'];
      if (files is! List) return null;
      final inline = json['inline'];
      final rawChannel = json['channel'];
      final channel = CatalogChannel.tryParse(rawChannel);
      return EpisodeBundle(
        channelKnown: json.containsKey('channel') &&
            (rawChannel == null || channel != null),
        channel: channel,
        files: {for (final f in files) if (f is String) f},
        inline: {
          if (inline is Map<String, dynamic>)
            for (final e in inline.entries)
              if (e.value != null) e.key: e.value as Object,
        },
      );
    } catch (_) {
      return null;
    }
  }

  bool has(String name) => files.contains(name) || inline.containsKey(name);

  /// Sadržaj datoteke kako bi ga vratio CDN, ili `null` ako nije uložen.
  String? inlineBody(String name) {
    final v = inline[name];
    if (v == null) return null;
    return v is String ? v : jsonEncode(v);
  }
}
