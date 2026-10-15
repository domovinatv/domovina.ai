/// Slanje batcha i čitanje web konteksta (referrer, UTM). Web ide kroz
/// `fetch` s `keepalive` da batch preživi zatvaranje taba; native kroz
/// `package:http`. Gate je `dart.library.js_interop`, ne `dart.library.html`
/// (inače `--wasm` build uzme krivu granu).
library;

import 'analytics_transport_io.dart'
    if (dart.library.js_interop) 'analytics_transport_web.dart' as platform;

/// Ishod slanja. `retry` = mreža ili server privremeno ne radi (5xx, 429);
/// `rejected` = server je batch odbio kao neispravan (4xx) i ponovno slanje
/// istog sadržaja ne bi pomoglo.
enum SendResult { ok, retry, rejected }

typedef AnalyticsSender = Future<SendResult> Function(String url, String body);

Future<SendResult> sendBatch(String url, String body) =>
    platform.sendBatch(url, body);

/// Referrer dokumenta na webu; null na nativeu ili kad ga nema.
String? documentReferrer() => platform.documentReferrer();

/// Je li tab stvarno vidljiv (`document.visibilityState`); null na nativeu.
bool? documentVisible() => platform.documentVisible();

/// Web: [onChange] pri svakoj promjeni vidljivosti taba (`visibilitychange`,
/// `pagehide` kao skriven). Native: ništa — tamo vrijedi Flutter lifecycle.
void listenDocumentVisibility(void Function(bool visible) onChange) =>
    platform.listenDocumentVisibility(onChange);

SendResult resultForStatus(int status) {
  if (status >= 200 && status < 300) return SendResult.ok;
  if (status == 429 || status >= 500) return SendResult.retry;
  return SendResult.rejected;
}
