/// Tekstualne normalizacije za lokalnu (offline) pretragu.
///
/// Hrvatski search MORA biti dijakritik-neosjetljiv: "Zizek" treba naći
/// "Žižek", "cuspajz" treba naći "Čušpajž". Flutter/`fuzzy` ne radi to sam,
/// pa normaliziramo i upit i ključeve prije usporedbe.
library;

/// Mapa hrvatskih (i čestih stranih) dijakritika na ASCII ekvivalente.
const Map<String, String> _foldMap = {
  'č': 'c', 'ć': 'c', 'ç': 'c',
  'š': 's', 'ś': 's',
  'ž': 'z', 'ź': 'z',
  'đ': 'd', // dž se prirodno fold-a kroz d + z
  'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ñ': 'n',
};

/// Lowercase + fold dijakritika → usporedivi ASCII oblik.
///
/// Foldano PO ZNAKU tako da je izlaz iste duljine kao ulaz (1 code unit →
/// 1 znak). To je nužno za [highlightRanges] gdje indekse iz foldane verzije
/// mapiramo natrag na originalni tekst. Za naš (hrvatski/latinični) sadržaj
/// lowercase je 1:1; ako neki znak lowercasea u više znakova, čuvamo original.
String foldText(String input) {
  final buf = StringBuffer();
  for (var i = 0; i < input.length; i++) {
    final cu = input.codeUnitAt(i);
    // ASCII brzi put: pretraga folda cijeli korpus (~2,7 MB), a `split('')`
    // alocira string po znaku.
    if (cu < 0x80) {
      buf.writeCharCode(cu >= 0x41 && cu <= 0x5A ? cu + 0x20 : cu);
      continue;
    }
    final ch = input[i];
    final lc = ch.toLowerCase();
    final c = lc.length == 1 ? lc : ch;
    buf.write(_foldMap[c] ?? c);
  }
  return buf.toString();
}

/// Upit kakav ga vidi korisnik: bez rubnih razmaka, uzastopni razmaci
/// stopljeni. „fra" i „fra " su isti upit — ne smiju okinuti novi mrežni
/// zahtjev ni prerangirati rezultate.
String normalizeQuery(String query) =>
    query.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Foldani tokeni upita — računaj JEDNOM po upitu, ne po epizodi.
List<String> queryTokens(String query) {
  final q = foldText(query).trim();
  if (q.isEmpty) return const [];
  return q.split(RegExp(r'\s+'));
}

/// Funkcijske riječi koje u upitu ne nose sadržaj (foldane). Upit „što je
/// rekao papa o ratu u ukrajini" je Meili s njima pogađao na „je", „o" i
/// „što" u naslovima koji nemaju veze s papom (izmjereno 14.10.2026.).
/// Prilozi poput „nakon"/„prije" NISU ovdje — u „život nakon smrti" nose
/// značenje.
const Set<String> _stopWords = {
  'a', 'ali', 'bi', 'bio', 'bila', 'biti', 'da', 'do', 'gdje', 'i', 'ili',
  'iz', 'je', 'jesu', 'k', 'ka', 'kad', 'kada', 'kako', 'koja', 'koje',
  'kojeg', 'koji', 'li', 'mi', 'na', 'ne', 'ni', 'o', 'od', 'po', 'pri', 's',
  'sa', 'sam', 'se', 'si', 'smo', 'ste', 'sta', 'sto', 'su', 'ta', 'te', 'ti',
  'tko', 'to', 'u', 'uz', 'vi', 'za', 'zasto',
};

/// [query] bez funkcijskih riječi, s izvornim pisanjem (dijakritike ostaju,
/// jer upit ide i Meiliju). Kad bi ostao prazan („što je to"), vraća izvorni
/// upit — bolje nešto naći nego ništa.
String contentQuery(String query) {
  final words = normalizeQuery(query).split(' ');
  final kept = [
    for (final w in words)
      if (!_stopWords.contains(foldText(w))) w,
  ];
  return kept.isEmpty ? normalizeQuery(query) : kept.join(' ');
}

/// Broj sadržajnih riječi upita. Tri i više znače pitanje ili opis, a ne
/// naslov ili ime — tu semantika zna više od podudaranja riječi.
int contentWordCount(String query) =>
    contentQuery(query).split(' ').where((w) => w.isNotEmpty).length;

/// Rasponi `[start, end)` u [text] koji odgovaraju bilo kojem tokenu iz
/// [query] (dijakritik-neosjetljivo). Rezultat je sortiran i spojen (bez
/// preklapanja) — spreman za izgradnju highlight TextSpan-ova.
///
/// Match je na razini RIJEČI s prefiks-poklapanjem (stem), pa hvata i hrvatske
/// sklonjene oblike: upit "demografska obnova" istakne i "demografsku obnovu",
/// "demografski", "obnove" itd. Highlighta se cijela riječ iz teksta.
List<List<int>> highlightRanges(String text, String query) {
  if (text.isEmpty) return const [];
  final q = foldText(query).trim();
  if (q.isEmpty) return const [];
  final tokens =
      q.split(RegExp(r'\s+')).where((t) => t.length >= 2).toList();
  if (tokens.isEmpty) return const [];

  final folded = foldText(text); // ista duljina kao text → indeksi se poklapaju
  final ranges = <List<int>>[];
  for (final m in RegExp(r'[a-z0-9]+').allMatches(folded)) {
    final word = m.group(0)!;
    for (final token in tokens) {
      if (_wordMatchesToken(word, token)) {
        ranges.add([m.start, m.end]);
        break;
      }
    }
  }
  if (ranges.isEmpty) return const [];

  ranges.sort((a, b) => a[0].compareTo(b[0]));
  final merged = <List<int>>[];
  var cur = ranges.first;
  for (var i = 1; i < ranges.length; i++) {
    final r = ranges[i];
    if (r[0] <= cur[1]) {
      if (r[1] > cur[1]) cur = [cur[0], r[1]];
    } else {
      merged.add(cur);
      cur = r;
    }
  }
  merged.add(cur);
  return merged;
}

/// Riječ se poklapa s tokenom ako dijele dovoljno dug zajednički prefiks da
/// pokriju varijaciju nastavka (hrvatska deklinacija/konjugacija).
bool _wordMatchesToken(String word, String token) {
  final n = word.length < token.length ? word.length : token.length;
  var cp = 0;
  while (cp < n && word.codeUnitAt(cp) == token.codeUnitAt(cp)) {
    cp++;
  }
  final need = token.length < 4 ? token.length : 4;
  // Zajednički prefiks mora biti barem `need` znakova I pokriti sve osim
  // zadnja 2 znaka kraće riječi (toleriraj nastavak).
  return cp >= need && cp >= n - 2;
}

/// Vrati isječak [text]-a centriran oko PRVOG pogotka [query]-ja (s „…"
/// rubovima) tako da je highlightani dio vidljiv i kad je tekst dug. Ako nema
/// pogotka, vraća početak. Snap-a na granice riječi.
String snippetAround(String text, String query,
    {int before = 70, int window = 280}) {
  final t = text.trim();
  if (t.length <= window) return t;

  final ranges = highlightRanges(t, query);
  if (ranges.isEmpty) {
    return '${t.substring(0, window).trimRight()}…';
  }

  final matchStart = ranges.first[0];
  var start = (matchStart - before).clamp(0, t.length);
  var end = (start + window).clamp(0, t.length);
  // Snap na granice riječi da ne režemo usred riječi.
  if (start > 0) {
    final sp = t.indexOf(' ', start);
    if (sp != -1 && sp - start < 25) start = sp + 1;
  }
  if (end < t.length) {
    final sp = t.lastIndexOf(' ', end);
    if (sp > start) end = sp;
  }
  final core = t.substring(start, end).trim();
  return '${start > 0 ? '…' : ''}$core${end < t.length ? '…' : ''}';
}

/// Deterministički lokalni match scorer. Vraća score > 0 ako se SVI tokeni
/// upita pojavljuju u (foldanom) tekstu; viši = bolji (prefiks/cijela riječ
/// vrijede više). 0 = nema matcha.
///
/// Token-AND semantika je predvidljivija od fuzzy-ja za kratke upite i ne
/// vraća slučajne false-positive rezultate.
double localMatchScore(String query, String haystack) =>
    localMatchScoreFolded(queryTokens(query), foldText(haystack));

/// [localMatchScore] nad već foldanim tokenima ([queryTokens]) i već foldanim
/// tekstom ([foldText]). Za pretragu nad cijelim katalogom: haystack se folda
/// jednom po korpusu, a ne pri svakom tipku.
double localMatchScoreFolded(List<String> tokens, String hay) {
  if (tokens.isEmpty || hay.isEmpty) return 0;
  double total = 0;
  for (final token in tokens) {
    var idx = hay.indexOf(token);
    // „medjugorje" je „Međugorje" pisan bez kvačica; fold daje „medugorje".
    if (idx < 0 && token.contains('dj')) {
      idx = hay.indexOf(token.replaceAll('dj', 'd'));
    }
    if (idx < 0) return 0; // svaki token mora biti prisutan (AND)
    // Bonus: match na granici riječi (početak ili nakon razmaka) vrijedi više.
    final atWordStart = idx == 0 || hay.codeUnitAt(idx - 1) == 0x20;
    total += atWordStart ? 2.0 : 1.0;
    // Bonus za duže tokene (specifičniji upit).
    total += token.length / 20.0;
  }
  return total;
}
