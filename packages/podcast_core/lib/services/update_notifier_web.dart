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
