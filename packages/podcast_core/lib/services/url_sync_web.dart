import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// URL koji čeka jer stranica nema fokus (vidi [replaceTimestampImpl]).
String? _pending;
bool _focusListening = false;

void _flushOnFocus() {
  if (_focusListening) return;
  _focusListening = true;
  web.window.addEventListener(
    'focus',
    ((web.Event _) {
      final url = _pending;
      _pending = null;
      if (url != null) _replace(url);
    }).toJS,
  );
}

void _replace(String url) {
  // PRVI arg mora biti POSTOJEĆI state, ne `null`.
  //
  // Flutter web engine svaki history entry omota u `{serialCount, state}`
  // (`_engine/engine/navigation/history.dart` → `_tagWithSerialCount`), a
  // go_router u to `state` polje serijalizira `location` + `imperativeMatches`
  // — dakle cijeli pushani stog (`RouteMatchListCodec`). `replaceState(null,…)`
  // je taj omot brisao: izmjereno 4.9.2026. na produkciji, `history.state` je
  // nakon jednog sync-a bio `null`.
  //
  // Posljedice su bile dvije: engine na povratku u takav entry vidi
  // `!_hasSerialCount(state)` i pretpostavi da je to sljedeći entry UNAPRIJED
  // (pa mu prepiše brojač u krivom smjeru), a go_router dobije
  // `pushRouteInformation` bez statea i mora rekonstruirati rutu samo iz
  // stringa lokacije — **bez stoga ispod**. Dok je sve išlo kroz `go()` to se
  // nije vidjelo jer je stog ionako bio prazan; otkad drill-down puša
  // (`lib/router/nav.dart`), svaki povratak u epizodu koja je svirala izgubio
  // bi cijeli trag ispod sebe.
  //
  // Treći arg je URL — relativni je OK, browser ga resolva u trenutni origin.
  web.window.history.replaceState(web.window.history.state, '', url);
}

/// Update address bar bez triggera router refresha.
///
/// replaceState NE fira popstate event, pa go_router ostaje nesvjestan
/// promjene — Flutter widget tree se ne rebuilda, player nastavlja raditi.
/// (Push bi bio loš — back button bi bio puno timestampa.)
///
/// [langSuffix]: '/en' kad je korisnik na engleskom; null ili '' za HR.
/// Stavi se NAKON timestamp segmenta da social crawleri vide stabilan
/// path-based URL (query parameters get droppani u WhatsApp/Facebook preview).
///
/// [query]: query string bez '?' (npr. `p=<person-slug>`) — appenda se na
/// kraj da highlight parametar preživi playback URL sync.
void replaceTimestampImpl(
  String basePath,
  int? seconds, {
  String? langSuffix,
  String? query,
}) {
  final ts = (seconds != null && seconds > 0) ? '/t/$seconds' : '';
  final lang = (langSuffix != null && langSuffix.isNotEmpty) ? langSuffix : '';
  final q = (query != null && query.isNotEmpty) ? '?$query' : '';
  final url = '$basePath$ts$lang$q';
  // Adresna traka u fokusu = stranica bez fokusa. Browser ne javlja „korisnik
  // je kliknuo adresnu traku”, ali stranica tada izgubi fokus
  // (`document.hasFocus()` je false, `window` dobije `blur`). replaceState bi
  // svake sekunde prepisao tekst koji korisnik upravo označava ili uređuje
  // (dopisuje /en), pa ga ne bi mogao kopirati. Zato dok stranica nema fokus
  // URL miruje, a zadnji traženi se upiše čim se fokus vrati.
  if (!web.document.hasFocus()) {
    _pending = url;
    _flushOnFocus();
    return;
  }
  _pending = null;
  _replace(url);
}
