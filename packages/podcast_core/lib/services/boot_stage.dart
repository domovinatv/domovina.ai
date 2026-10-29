/// Javlja HTML boot splashu (`#boot-intro` u `web/index.html` ljuske) u kojoj
/// je fazi `main()`, da tekst ispod trake napretka kaže što se stvarno radi.
///
/// Na webu je to `CustomEvent('app-boot-stage', detail: <faza>)` na `window`;
/// splash bez slušatelja (druga ljuska, stari `index.html`) ga ignorira. Na
/// nativeu je no-op — ondje splash crta platforma.
///
/// Jedina faza je zasad `fonts` (čekanje `AppTypography.awaitPreload`, na Slow
/// 4G punih 3 s). Inicijalizacija servisa (~10 ms) i `runApp` → prvi frame
/// (~70 ms) su izmjereni i prekratki da bi ih itko pročitao.
/// Puna slika: `docs/2026-10-09-boot-splash.md` §6.
///
/// Gate je `dart.library.js_interop`, ne `dart.library.html` — potonji ne
/// postoji u `--wasm` buildu.
library;

import 'boot_stage_stub.dart'
    if (dart.library.js_interop) 'boot_stage_web.dart' as platform;

void reportBootStage(String stage) => platform.reportBootStage(stage);
