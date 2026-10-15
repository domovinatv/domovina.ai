/// Praćenje kanala i osoba — **jedan** lokalni popis s namespace prefiksom
/// (`channel:<id>`, `person:<slug>`), po uzoru na `favorites_service.dart`.
///
/// Zašto zaseban servis, a ne proširenje `FavoritesService`: favoriti su
/// epizode s vlastitom Supabase tablicom i migracijskim flagom; miješanje
/// entiteta razbilo bi `domovina_ai.favorites` ugovor i `migrateToSupabase`
/// tok (odluka O10 u `docs/plans/virtualni-kanali.md`).
///
/// **Remote sync je namjerno no-op.** Tablica `domovina_ai.follows` NE postoji
/// u shemi (provjereno 28.07.2026.); migracija je zaseban issue
/// `domovinatv/domovina-api#3`. Do tada praćenje živi isključivo lokalno — i
/// za prijavljene i za anonimne korisnike. Kad tablica stigne, jedina izmjena
/// je popuniti [_syncRemote] (i backfill po uzoru na
/// `FavoritesService.migrateToSupabase`); ugovor prema UI-ju se ne mijenja.
///
/// Perzistencija: `window.localStorage` na webu preko `local_prefs.dart`
/// (`SharedPreferences` puca u dart2js release buildu — vidi CLAUDE.md),
/// `SharedPreferences` na nativeu.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../src/log.dart' show log;
import 'local_prefs.dart';
import 'push_topics.dart';

/// Popis praćenih entiteta (JSON lista ključeva).
const String kFollowsStorageKey = 'follows_v1';

/// Zadnje viđeni datum epizode po praćenom entitetu (JSON mapa ključ → `YYYY-MM-DD`).
/// Odvojen zapis od popisa: brisanje praćenja ne smije zaboraviti da je
/// korisnik nešto već vidio, jer bi ponovno praćenje istog kanala vratilo
/// staru epizodu u rail „Novo od praćenih".
const String kFollowsSeenStorageKey = 'follows_seen_v1';

const String _personPrefix = 'person:';
const String _channelPrefix = 'channel:';

/// Ključ osobe u popisu praćenja. Person slug se koristi DOSLOVNO (s crticama),
/// nikad kroz `-`↔`_` transformaciju koju rade kanali.
String personFollowKey(String slug) => '$_personPrefix$slug';

/// Ključ kanala — interni channel id (`slijedi_svoj_poziv_2`), ne `/c/` slug.
String channelFollowKey(String channelId) => '$_channelPrefix$channelId';

/// Slug osobe iz ključa; null ako ključ nije osoba.
String? personSlugFromFollowKey(String key) =>
    key.startsWith(_personPrefix) ? key.substring(_personPrefix.length) : null;

/// Interni id kanala iz ključa; null ako ključ nije kanal.
String? channelIdFromFollowKey(String key) =>
    key.startsWith(_channelPrefix) ? key.substring(_channelPrefix.length) : null;

/// Je li [latestDate] noviji od zadnje viđenog [seenDate].
///
/// Datumi su ISO `YYYY-MM-DD` pa je leksikografska usporedba dovoljna i, za
/// razliku od parsiranja u `DateTime`, ne ovisi o današnjem datumu (test ostaje
/// stabilan). Prazan/nepoznat [latestDate] nikad nije „novo" — bez signala ne
/// izmišljamo obavijest.
bool isNewerThanSeen(String? latestDate, String? seenDate) {
  final latest = latestDate?.trim() ?? '';
  if (latest.isEmpty) return false;
  final seen = seenDate?.trim() ?? '';
  if (seen.isEmpty) return true;
  return latest.compareTo(seen) > 0;
}

class FollowService extends ChangeNotifier {
  static final FollowService instance = FollowService._();
  FollowService._();

  final Set<String> _keys = {};
  final Map<String, String> _seen = {};
  bool _loaded = false;
  Future<void>? _loading;

  /// True čim je lokalni popis pročitan — do tada UI prikazuje „ne pratim"
  /// (isti default kao `PersonChannelFlag`, nikad lažni pozitiv).
  bool get isLoaded => _loaded;

  /// Učitaj popis (idempotentno; višestruki pozivi dijele isti Future).
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    _keys.addAll(_decodeKeys(await _read(kFollowsStorageKey)));
    _seen.addAll(_decodeSeen(await _read(kFollowsSeenStorageKey)));
    _loaded = true;
    notifyListeners();
  }

  /// Svi praćeni ključevi (uključujući prefiks).
  List<String> get all => _keys.toList(growable: false);

  /// Slugovi praćenih osoba.
  List<String> get personSlugs =>
      _keys.map(personSlugFromFollowKey).whereType<String>().toList();

  /// Interni id-evi praćenih kanala.
  List<String> get channelIds =>
      _keys.map(channelIdFromFollowKey).whereType<String>().toList();

  /// Sinkrona provjera — ispravna tek nakon [ensureLoaded].
  bool isFollowingSync(String key) => _keys.contains(key);

  /// Asinkrona provjera koja sama čeka učitavanje (za widget `initState`).
  Future<bool> isFollowing(String key) async {
    await ensureLoaded();
    return _keys.contains(key);
  }

  /// Prati/prestani pratiti. Vraća **novo** stanje (true = sad prati).
  Future<bool> toggle(String key) async {
    await ensureLoaded();
    final nowFollowing = !_keys.contains(key);
    if (nowFollowing) {
      _keys.add(key);
    } else {
      _keys.remove(key);
    }
    await _persistKeys();
    notifyListeners();
    await _syncRemote(key, nowFollowing);
    await PushTopics.instance.onFollowChanged(key, nowFollowing);
    return nowFollowing;
  }

  /// Zadnji datum koji je korisnik vidio za taj entitet (`YYYY-MM-DD`).
  String? lastSeenDate(String key) => _seen[key];

  /// Ima li praćeni entitet epizodu noviju od zadnje viđene.
  bool hasUnseen(String key, String? latestDate) =>
      isNewerThanSeen(latestDate, _seen[key]);

  /// Zapamti da je korisnik vidio epizodu tog datuma. Stariji datum ne pomiče
  /// oznaku unatrag (rail se ne smije „vratiti" nakon otvaranja arhivske
  /// epizode).
  Future<void> markSeen(String key, String? date) async {
    final value = date?.trim() ?? '';
    if (value.isEmpty) return;
    await ensureLoaded();
    final current = _seen[key];
    if (current != null && current.compareTo(value) >= 0) return;
    _seen[key] = value;
    await _persistSeen();
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Perzistencija
  // -------------------------------------------------------------------------

  Future<void> _persistKeys() =>
      _write(kFollowsStorageKey, jsonEncode(_keys.toList()));

  Future<void> _persistSeen() =>
      _write(kFollowsSeenStorageKey, jsonEncode(_seen));

  /// Nikad ne baca — pokvaren zapis znači „nema praćenja", ne pad ekrana.
  static Set<String> _decodeKeys(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final list = jsonDecode(raw);
      if (list is! List) return {};
      return list.whereType<String>().where((k) => k.isNotEmpty).toSet();
    } catch (e) {
      log('follows: neispravan zapis popisa ($e)');
      return {};
    }
  }

  static Map<String, String> _decodeSeen(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return {};
      return {
        for (final e in map.entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
      };
    } catch (e) {
      log('follows: neispravan zapis viđenih datuma ($e)');
      return {};
    }
  }

  Future<String?> _read(String key) async {
    if (kIsWeb) return getLocalStorageString(key);
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  Future<void> _write(String key, String value) async {
    if (kIsWeb) {
      setLocalStorageString(key, value);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  /// Sinkronizacija s bazom — **namjerno prazna** dok `domovina_ai.follows` ne
  /// postoji (`domovinatv/domovina-api#3`). Zove se iz [toggle] da mjesto
  /// budućeg dual-write-a bude očito i da lokalna putanja ostane netaknuta kad
  /// tablica stigne.
  Future<void> _syncRemote(String key, bool following) async {}

  /// Test hook: vrati servis u početno stanje.
  @visibleForTesting
  void debugReset() {
    _keys.clear();
    _seen.clear();
    _loaded = false;
    _loading = null;
  }
}
