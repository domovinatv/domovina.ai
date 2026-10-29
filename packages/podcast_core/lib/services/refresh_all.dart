/// Skriveni gumb „Osvježi sve" — briše sve što aplikacija drži spremljeno i
/// ponovno učita istu adresu. Ono što DevTools „Clear site data" radi ručno,
/// samo bez diranja prijave (localStorage ostaje).
///
/// Zašto postoji: Ctrl+Shift+R preskače HTTP cache, ali **ne briše Cache
/// Storage**, a ondje žive listinzi i `episode.json` (`CdnJsonCache`). 29.10.
/// je `MNk-eEpDb3E` na Windows Braveu i nakon hard reloada ostao bez
/// Magisteriuma koji je pipeline ujutro dodao.
///
/// Vidljivost je runtime zastavica, kao `?vk=`:
/// - `?osvjezi=1` → gumb se pojavi i to se **pamti**;
/// - `?osvjezi=0` → gumb nestane i to se pamti;
/// - bez parametra → spremljena vrijednost, default skriveno.
///
/// Samo web: na nativeu nema adresne trake ni reloada.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../src/log.dart' show log;
import 'data_service.dart';
import 'local_prefs.dart';
import 'update_notifier.dart';

const String kRefreshAllParam = 'osvjezi';
const String _refreshAllKey = 'refresh_all_button';

/// `?osvjezi=1` → true, `?osvjezi=0` → false, inače null. Čista funkcija.
bool? refreshAllOverrideFromUri(Uri? uri) {
  final raw = uri?.queryParameters[kRefreshAllParam];
  if (raw == '1') return true;
  if (raw == '0') return false;
  return null;
}

/// Je li gumb vidljiv. Parametar u URL-u pobjeđuje i sprema se.
bool refreshAllButtonVisible() {
  if (!kIsWeb) return false;
  final override = refreshAllOverrideFromUri(Uri.base);
  if (override != null) {
    setLocalStorageString(_refreshAllKey, override ? '1' : '0');
    return override;
  }
  return getLocalStorageString(_refreshAllKey) == '1';
}

/// Obriši memoriju, Cache Storage i service workere, pa učitaj istu adresu.
/// Prije brisanja `hardReload` ponovno dohvati (`cache: 'reload'`) svaku CDN
/// adresu iz Cache Storagea, da i HTTP cache preglednika dobije svježe kopije.
Future<void> refreshAll() async {
  log('refreshAll: brišem spremljeno i učitavam ponovno');
  DataService.clearMemory();
  PaintingBinding.instance.imageCache
    ..clear()
    ..clearLiveImages();
  // NE `CdnJsonCache.clear()` ovdje: hardReload prvo čita adrese iz Cache
  // Storagea (za prepisivanje HTTP cachea), pa tek onda briše SVE zapise,
  // odjavi SW i napravi reload.
  await hardReload(stayHere: true);
}
