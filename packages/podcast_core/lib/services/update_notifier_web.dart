import 'dart:js_interop';
import 'package:web/web.dart' as web;

void listenForAppUpdateImpl(void Function() onUpdateAvailable) {
  // Legacy `flutter-app-updated` event dolazio je iz SW updatefound handlera u
  // index.html-u. Od v2.0.5 NEMA SW — event se ne fira. Listener ostaje radi
  // dual-mode kompatibilnosti: ako se ikad vrati SW (ili neki drugi izvor),
  // automatski radi. Inače je no-op.
  web.window.addEventListener(
    'flutter-app-updated',
    (web.Event e) { onUpdateAvailable(); }.toJS,
  );
}

void reloadPageImpl() {
  web.window.location.reload();
}

Future<void> hardReloadImpl({bool stayHere = false}) async {
  try {
    // Clear all caches (Cache API)
    final cacheNames = await web.window.caches.keys().toDart;
    if (stayHere) await _reloadHttpCache(cacheNames.toDart);
    for (final name in cacheNames.toDart) {
      await web.window.caches.delete(name.toDart).toDart;
    }
    // Unregister all Service Workers
    final regs = await web.window.navigator.serviceWorker
        .getRegistrations()
        .toDart;
    for (final reg in regs.toDart) {
      await reg.unregister().toDart;
    }
  } catch (_) {}
  if (stayHere) {
    web.window.location.reload();
    return;
  }
  // Navigate with cache-buster to bypass bfcache
  final base = web.window.location.origin;
  final bust = DateTime.now().millisecondsSinceEpoch;
  web.window.location.replace('$base/?_cb=$bust');
}

/// JS ne može obrisati HTTP cache preglednika, ali ga može PREPISATI:
/// `fetch(url, {cache: 'reload'})` ide na mrežu i spremi svjež odgovor.
/// Prepisuje sve adrese koje aplikacija drži u Cache Storageu (listinzi,
/// `episode.json`) — upravo one koje se na CDN-u mijenjaju. 29.10.2026. je
/// `episode.json` bez Magisteriuma sat vremena stizao iz HTTP cachea
/// (`max-age=3600` iz CF cache pravila), a gumb ga nije mogao dirnuti.
Future<void> _reloadHttpCache(List<JSString> cacheNames) async {
  final urls = <String>{};
  for (final name in cacheNames) {
    if (!name.toDart.startsWith('domovina-')) continue;
    final cache = await web.window.caches.open(name.toDart).toDart;
    for (final req in (await cache.keys().toDart).toDart) {
      urls.add(req.url);
    }
  }
  await Future.wait([
    for (final url in urls)
      web.window
          .fetch(url.toJS, web.RequestInit(cache: 'reload'))
          .toDart
          // Tijelo se mora pročitati: HTTP cache upiše tek potpun odgovor,
          // a reload bi inače prekinuo prijenos.
          .then((res) => res.arrayBuffer().toDart)
          .then((_) {}, onError: (_) {}),
  ]).timeout(const Duration(seconds: 8), onTimeout: () => []);
}
