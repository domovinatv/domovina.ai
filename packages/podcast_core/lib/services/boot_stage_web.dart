/// Web: faza ide HTML splashu kao `CustomEvent` na `window`.
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

void reportBootStage(String stage) {
  try {
    web.window.dispatchEvent(web.CustomEvent(
      'app-boot-stage',
      web.CustomEventInit(detail: stage.toJS),
    ));
  } catch (_) {
    // Splash je samo prikaz; boot ne smije pasti zbog njega.
  }
}
