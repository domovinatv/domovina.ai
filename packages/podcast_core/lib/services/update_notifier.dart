import 'package:flutter/foundation.dart' show kIsWeb;
import 'update_notifier_web.dart' if (dart.library.io) 'update_notifier_stub.dart'
    as platform;

/// Registers a callback to be invoked when a new app version is detected
/// via Service Worker update. Web-only; no-op on native.
void listenForAppUpdate(void Function() onUpdateAvailable) {
  if (kIsWeb) {
    platform.listenForAppUpdateImpl(onUpdateAvailable);
  }
}

/// Force-reloads the page. Web-only.
void reloadPage() {
  if (kIsWeb) {
    platform.reloadPageImpl();
  }
}

/// Unregisters all Service Workers then reloads — guarantees fresh version.
/// [stayHere] ponovno učita trenutnu adresu umjesto naslovnice.
Future<void> hardReload({bool stayHere = false}) async {
  if (kIsWeb) {
    await platform.hardReloadImpl(stayHere: stayHere);
  }
}
