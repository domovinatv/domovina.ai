/// Disk cache za JSON s `cdn.domovina.ai`: naslovnica se pri ponovnom
/// otvaranju crta iz spremljenog, a posjećene epizode se čitaju i offline.
///
/// Dvije strategije, po prirodi datoteke:
///
/// - **Promjenjive** (`index.json`, listinzi kanala, `home.json`,
///   `search.json`) — *stale-while-revalidate*: vrati spremljeno odmah, u
///   pozadini pitaj CDN je li se promijenilo i, ako jest, javi novu verziju
///   kroz `onUpdate`. Prikaz je najviše jedan korak iza; ručni purge ne treba.
/// - **Nepromjenjive** (per-epizoda `data/<id>/*`, `immutable` na CDN-u) —
///   *cache-first* bez revalidacije, samo na nativeu. Na webu ih preglednikov
///   HTTP cache ionako servira bez mreže.
///
/// Cache je bio namjerno ugašen da u razvoju ne smeta. Zato je ugašen u debug
/// buildu i uz `?nocache=1` na webu — tada sve ide ravno na mrežu kao prije.
/// 404 i greške se nikad ne spremaju (vidi `DataService._get`).
///
/// Mjerenja i odluke: `docs/2026-10-08-brzina-ucitavanja-naslovnice.md` (O1).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../src/log.dart' show log;
import 'cdn_store.dart';

class CdnJsonCache {
  CdnJsonCache({
    required CdnStore store,
    required this.enabled,
    this.sendConditionalHeaders = !kIsWeb,
    http.Client? client,
  })  : _store = store,
        _client = client;

  static CdnJsonCache instance = CdnJsonCache(
    store: createPlatformStore(),
    enabled: !kDebugMode && !_nocacheRequested(),
  );

  final CdnStore _store;
  final http.Client? _client;

  /// Kad je `false`, svaki poziv ide ravno na mrežu (debug build, `?nocache=1`).
  final bool enabled;

  /// Šalje li klijent sam `If-None-Match`. Na webu NE: to zaglavlje nije
  /// CORS-safelisted pa bi svaki zahtjev dobio preflight, a preglednik ionako
  /// sam radi uvjetni zahtjev iz svog HTTP cachea. CDN usto ne izlaže `etag`
  /// kroz `access-control-expose-headers`, pa ga web ni ne vidi — ondje se
  /// promjena prepoznaje usporedbom tijela.
  final bool sendConditionalHeaders;

  /// URL-ovi koji su u ovoj sesiji već revalidirani — ne pitamo CDN dvaput.
  final Set<String> _revalidated = {};

  /// Revalidacije pokrenute u ovoj sesiji: tijelo kad je CDN vratio DRUGAČIJE
  /// od spremljenog, inače `null`. Vidi [revalidation].
  final Map<String, Future<String?>> _revalidations = {};

  static bool _nocacheRequested() {
    if (!kIsWeb) return false;
    try {
      return Uri.base.queryParameters.containsKey('nocache');
    } catch (_) {
      return false;
    }
  }

  Future<http.Response> _httpGet(String url, {Map<String, String>? headers}) {
    final client = _client;
    return client != null
        ? client.get(Uri.parse(url), headers: headers)
        : http.get(Uri.parse(url), headers: headers);
  }

  /// Promjenjiva datoteka. Vraća spremljeno tijelo ako postoji (i u pozadini
  /// revalidira), inače ide na mrežu. Baca `Exception('HTTP <kod>: <url>')`
  /// kad mreža vrati ne-200 a spremljenog nema — isto kao prije cachea.
  ///
  /// [onUpdate] se zove samo kad je revalidacija donijela DRUGAČIJE tijelo od
  /// vraćenog.
  ///
  /// [bucket] je [StoreBucket.mutable] za channel-level datoteke, a
  /// [StoreBucket.episode] za `episode.json` (ista strategija, ograničen broj).
  Future<String> getMutable(
    String url, {
    void Function(String body)? onUpdate,
    StoreBucket bucket = StoreBucket.mutable,
  }) async {
    if (!enabled || !_store.supports(bucket)) return _fetchOrThrow(url);

    final stored = await _store.get(bucket, url);
    if (stored == null) {
      final res = await _httpGet(url);
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: $url');
      }
      _revalidated.add(url);
      unawaited(_store.put(bucket, url,
          StoredEntry(res.body, etag: res.headers['etag'])));
      return res.body;
    }

    if (_revalidated.add(url)) {
      _revalidations[url] = _revalidate(url, stored, onUpdate, bucket);
    }
    return stored.body;
  }

  /// Pozadinska revalidacija za [url] koju je pokrenuo [getMutable]: završi
  /// novim tijelom ako se datoteka na CDN-u promijenila, inače `null`. `null`
  /// i kad revalidacije nema (tijelo je stiglo s mreže, cache je ugašen).
  ///
  /// Za odluku koja ne smije počivati na staroj kopiji: `episode.json` sa
  /// diska kaže da `article.magisterium.json` ne postoji, a pipeline ga je u
  /// međuvremenu uploadao — bez ovoga se Magisterium ne vidi do sljedećeg
  /// učitavanja (i Ctrl+Shift+R ne pomaže, jer ne briše Cache Storage).
  Future<String?> revalidation(String url) =>
      _revalidations[url] ?? Future<String?>.value();

  Future<String?> _revalidate(
    String url,
    StoredEntry stored,
    void Function(String body)? onUpdate,
    StoreBucket bucket,
  ) async {
    try {
      final etag = stored.etag;
      final res = await _httpGet(url,
          headers: sendConditionalHeaders && etag != null
              ? {'If-None-Match': etag}
              : null);
      if (res.statusCode != 200) return null; // 304, 404, 5xx: ostaje spremljeno
      if (res.body == stored.body) return null;
      await _store.put(bucket, url,
          StoredEntry(res.body, etag: res.headers['etag']));
      onUpdate?.call(res.body);
      return res.body;
    } catch (e) {
      // Offline ili mreža pukla — spremljeno ostaje važeće.
      log('CdnJsonCache: revalidacija nije uspjela ($url): $e');
      return null;
    }
  }

  Future<String> _fetchOrThrow(String url) async {
    final res = await _httpGet(url);
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}: $url');
    return res.body;
  }

  /// Nepromjenjiva per-epizoda datoteka: spremljena ako postoji, inače
  /// [fetch]; samo 200 se sprema. [fetch] zadržava svoju logiku (npr. drugi
  /// pokušaj nakon 404 u `DataService._get`).
  Future<http.Response> getImmutable(
    String url,
    Future<http.Response> Function() fetch,
  ) async {
    if (!enabled || !_store.supports(StoreBucket.immutable)) return fetch();
    final stored = await _store.get(StoreBucket.immutable, url);
    if (stored != null) {
      return http.Response.bytes(utf8.encode(stored.body), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }
    final res = await fetch();
    if (res.statusCode == 200) {
      unawaited(
          _store.put(StoreBucket.immutable, url, StoredEntry(res.body)));
    }
    return res;
  }

  /// Obriši sve spremljeno (za „očisti spremljene podatke").
  Future<void> clear() {
    _revalidated.clear();
    _revalidations.clear();
    return _store.clear();
  }
}
