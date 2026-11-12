/// Javno stanje postavki kanala za sve ekrane (lanac `postavke-kanala/`, S5).
///
/// JEDAN izvor u aplikaciji: katalog `GET /v1/settings` (odluka 312) jednom po
/// sesiji, osvježen najviše svakih [maxAge]. Ekrani i servisi pitaju
/// [ChannelVisibility.instance] po UC-u; nitko ne radi dodatni zahtjev po
/// prekidaču. Isto pravilo kao „stanje kontrole ide kroz singleton” u
/// korijenskom `CLAUDE.md`: tri stabla playera i TV čitaju isto stanje bez
/// prop drillinga.
///
/// Fail-open (tvrdi uvjet 4 plana): kanal bez UC-a, kanal kojeg nema u mapi,
/// nepoznat ključ i nedostupan katalog = sve uključeno, tj. kao danas.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../src/log.dart' show log;
import 'channel_settings_service.dart';

class ChannelVisibility extends ChangeNotifier {
  ChannelVisibility({ChannelSettingsCatalog? catalog, DateTime Function()? now})
    : _catalog = catalog ?? ChannelSettingsCatalog(),
      _now = now ?? DateTime.now;

  /// Zamjenjivo u testovima (`ChannelVisibility.instance = …`).
  static ChannelVisibility instance = ChannelVisibility();

  /// Koliko dugo vrijedi učitana mapa prije sljedećeg [refresh].
  static const Duration maxAge = Duration(minutes: 5);

  final ChannelSettingsCatalog _catalog;
  final DateTime Function() _now;

  Map<String, CatalogChannelSettings> _byUc = const {};
  DateTime? _loadedAt;
  Future<void>? _inFlight;

  /// Je li mapa ikad uspješno učitana (ili postavljena u testu).
  bool get isLoaded => _loadedAt != null;

  /// UC-ovi s barem jednim isključenim ključem (samo za dijagnostiku/testove).
  Map<String, CatalogChannelSettings> get snapshot => _byUc;

  /// Učitaj (ili osvježi starije od [maxAge]). Ne baca; neuspjeh zadrži
  /// zadnju poznatu mapu.
  Future<void> refresh({bool force = false}) {
    final at = _loadedAt;
    if (!force && at != null && _now().difference(at) < maxAge) {
      return Future.value();
    }
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  Future<void> _load() async {
    final map = await _catalog.fetch();
    if (map == null) return; // katalog nedostupan → ostaje što je bilo
    final changed = !mapEquals(_signature(map), _signature(_byUc));
    _byUc = Map.unmodifiable(map);
    _loadedAt = _now();
    log('ChannelVisibility: ${map.length} kanala s ograničenjima');
    if (changed) notifyListeners();
  }

  /// Za ekrane koji odlučuju prije prvog crtanja (epizoda, kanal): pričekaj
  /// učitavanje najviše [timeout], pa nastavi s onim što ima (fail-open).
  Future<void> ready({Duration timeout = const Duration(milliseconds: 1500)}) =>
      refresh().timeout(timeout, onTimeout: () {});

  /// Stanje kanala ili `null` (= sve uključeno).
  CatalogChannelSettings? of(String? ucId) =>
      (ucId == null || ucId.isEmpty) ? null : _byUc[ucId];

  /// Vrijedi li [key] za kanal. Povučen ili obrisan kanal gasi sve.
  bool isEnabled(String? ucId, String key) {
    final s = of(ucId);
    if (s == null) return true;
    if (s.isWithdrawn || s.isDeleted) return false;
    return s.isEnabled(key);
  }

  bool isWithdrawn(String? ucId) => of(ucId)?.isWithdrawn ?? false;
  bool isDeleted(String? ucId) => of(ucId)?.isDeleted ?? false;

  /// Povučen ILI obrisan: sadržaj se ne prikazuje.
  bool isGone(String? ucId) => isWithdrawn(ucId) || isDeleted(ucId);
  DateTime? deletedAt(String? ucId) => of(ucId)?.deletedAt;

  /// Testovi: postavi mapu bez mreže.
  @visibleForTesting
  void setForTest(Map<String, CatalogChannelSettings> byUc) {
    _byUc = Map.unmodifiable(byUc);
    _loadedAt = _now();
    notifyListeners();
  }

  static Map<String, String> _signature(Map<String, CatalogChannelSettings> m) =>
      {
        for (final e in m.entries)
          e.key:
              '${e.value.status}|${(e.value.off.toList()..sort()).join(',')}|'
              '${e.value.deletedAt?.toIso8601String() ?? ''}',
      };
}

/// Pomoćnik za testove: stanje jednog kanala.
@visibleForTesting
CatalogChannelSettings channelOff(
  Iterable<String> off, {
  String status = 'active',
  DateTime? deletedAt,
}) => CatalogChannelSettings(
  status: status,
  off: off.toSet(),
  deletedAt: deletedAt,
);
