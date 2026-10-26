import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'cdn_config.dart';

/// Jedno izdanje e-knjige epizode na CDN-u (`book.epub` ili `book.en.epub`).
class EbookEdition {
  /// True za englesko izdanje (`book.en.epub`).
  final bool isEn;

  /// Čisti (immutable) URL za preuzimanje — NE probe URL s cache-busterom.
  final String url;

  /// Veličina u bajtovima iz `content-length` HEAD odgovora; null ako je CDN
  /// nije poslao (tada UI jednostavno ne piše veličinu, ne izmišlja je).
  final int? bytes;

  const EbookEdition({required this.isEn, required this.url, this.bytes});
}

/// Što od e-knjige postoji za jednu epizodu. Prazno dok pipeline nije došao do
/// KORAK 9.8, ili trajno prazno za epizode bez članka.
class EbookAvailability {
  final EbookEdition? hr;
  final EbookEdition? en;

  const EbookAvailability({this.hr, this.en});

  static const EbookAvailability none = EbookAvailability();

  bool get any => hr != null || en != null;

  /// HR pa EN — redoslijed kojim ih UI nudi.
  List<EbookEdition> get editions => [?hr, ?en];

  /// Izdanje koje odgovara jeziku koji korisnik trenutno čita; ako tog izdanja
  /// nema, ono drugo (knjiga na krivom jeziku je bolja od ničega, a UI svejedno
  /// piše koji je jezik).
  EbookEdition? preferred({required bool wantEn}) =>
      wantEn ? (en ?? hr) : (hr ?? en);
}

/// Otkriva i dohvaća EPUB e-knjigu epizode s CDN-a.
///
/// **Postojanje se MJERI** (HEAD probe), ne čita iz `pipeline` zastavica u
/// channel listingu — tamo za knjigu ionako nema zastavice, a i da je ima,
/// vrijedilo bi pravilo iz CLAUDE.md („pipeline zastavice ≠ stvarnost").
/// Probe ide na URL s cache-busterom jer CDN 404 cachira 4 sata, a knjiga se
/// generira nakon članka.
class EbookService {
  EbookService._();

  static const String mimeType = 'application/epub+zip';

  static final Map<String, EbookAvailability> _availability = {};
  static final Map<String, Future<EbookAvailability>> _inFlight = {};

  /// Bajtovi već preuzetih knjiga, ključ = čisti URL. Drži se najviše
  /// [_maxCachedFiles] jer je knjiga ~2,5 MB po komadu.
  static final Map<String, Uint8List> _bytes = {};
  static final Map<String, Future<Uint8List>> _bytesInFlight = {};
  static const int _maxCachedFiles = 2;

  /// Ima li epizoda e-knjigu, i u kojim jezicima. Rezultat se pamti za život
  /// sesije — knjiga koja postoji ne nestaje, a za onu koje nema korisnik ionako
  /// ne vidi nikakav gumb pa ponovni probe nema što promijeniti.
  static Future<EbookAvailability> probe(String videoId) {
    final cached = _availability[videoId];
    if (cached != null) return Future.value(cached);
    final running = _inFlight[videoId];
    if (running != null) return running;

    final future = _probe(videoId).then((result) {
      _availability[videoId] = result;
      _inFlight.remove(videoId);
      return result;
    }).catchError((Object _) {
      _inFlight.remove(videoId);
      return EbookAvailability.none;
    });
    _inFlight[videoId] = future;
    return future;
  }

  /// Sinkroni pogled u keš — za `build()` koji ne smije čekati.
  static EbookAvailability? cached(String videoId) => _availability[videoId];

  static Future<EbookAvailability> _probe(String videoId) async {
    final results = await Future.wait([
      _head(
        probeUrl: CdnConfig.ebookProbeUrl(videoId),
        url: CdnConfig.ebookUrl(videoId),
        isEn: false,
      ),
      _head(
        probeUrl: CdnConfig.ebookEnProbeUrl(videoId),
        url: CdnConfig.ebookEnUrl(videoId),
        isEn: true,
      ),
    ]);
    return EbookAvailability(hr: results[0], en: results[1]);
  }

  static Future<EbookEdition?> _head({
    required String probeUrl,
    required String url,
    required bool isEn,
  }) async {
    try {
      final r = await http.head(Uri.parse(probeUrl));
      if (r.statusCode != 200) return null;
      final len = int.tryParse(r.headers['content-length'] ?? '');
      return EbookEdition(
        isEn: isEn,
        url: url,
        bytes: (len != null && len > 0) ? len : null,
      );
    } catch (_) {
      // Mreža/CORS → ponašaj se kao da knjige nema; nikad ne ruši ekran epizode.
      return null;
    }
  }

  /// Preuzima (i pamti) bajtove knjige.
  ///
  /// Zašto uopće držimo bajtove u memoriji umjesto da pustimo browser da skine
  /// URL: dijeljenje DATOTEKE kroz `navigator.share` traži `File` objekt, a
  /// poziv mora pasti unutar korisnikove geste. Preuzimanje 2,5 MB usred te
  /// geste na iOS-u zna isteći („NotAllowedError"), pa sheet počne preuzimati
  /// čim se otvori i do tapa su bajtovi obično već tu.
  static Future<Uint8List> download(String url) {
    final cached = _bytes[url];
    if (cached != null) return Future.value(cached);
    final running = _bytesInFlight[url];
    if (running != null) return running;

    final future = http.get(Uri.parse(url)).then((r) {
      if (r.statusCode != 200) {
        throw http.ClientException('HTTP ${r.statusCode}', Uri.parse(url));
      }
      if (_bytes.length >= _maxCachedFiles) {
        _bytes.remove(_bytes.keys.first);
      }
      _bytes[url] = r.bodyBytes;
      _bytesInFlight.remove(url);
      return r.bodyBytes;
    }).catchError((Object e) {
      _bytesInFlight.remove(url);
      throw e;
    });
    _bytesInFlight[url] = future;
    return future;
  }

  /// Je li knjiga već u memoriji (tap tada dijeli bez čekanja).
  static bool isDownloaded(String url) => _bytes.containsKey(url);

  /// Ime datoteke koje korisnik vidi u WhatsAppu/Filesu.
  ///
  /// Dijakritici se transliteriraju, a sve ostalo van `[A-Za-z0-9-_]` pada na
  /// crticu: datoteka putuje kroz tuđe aplikacije i datotečne sustave, gdje
  /// „č" i „?" znaju završiti kao smeće ili odbijeni upload.
  static String fileName({required String title, required bool isEn}) {
    final slug = _slug(title);
    final base = slug.isEmpty ? 'domovina-ai-epizoda' : slug;
    return '$base${isEn ? '-en' : ''}.epub';
  }

  /// Isti slug za druge datoteke koje putuju kroz share (npr. reel MP4).
  static String fileSlug(String title) => _slug(title);

  static const Map<String, String> _translit = {
    'č': 'c', 'ć': 'c', 'ž': 'z', 'š': 's', 'đ': 'd',
    'Č': 'C', 'Ć': 'C', 'Ž': 'Z', 'Š': 'S', 'Đ': 'D',
  };

  static String _slug(String input) {
    var out = input;
    _translit.forEach((from, to) => out = out.replaceAll(from, to));
    out = out
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (out.length > 60) {
      out = out.substring(0, 60).replaceAll(RegExp(r'-+$'), '');
    }
    return out;
  }

  /// „2,5 MB" / „940 kB" — hrvatski decimalni zarez, SI prefiksi (CDN mjeri u
  /// dekadskim bajtovima, isto kao `content-length`).
  static String formatSize(int bytes) {
    if (bytes >= 1000000) {
      final mb = bytes / 1000000;
      return '${mb.toStringAsFixed(1).replaceAll('.', ',')} MB';
    }
    return '${(bytes / 1000).round()} kB';
  }
}
