import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'analytics_transport.dart' show SendResult, resultForStatus;

/// `text/plain` je „jednostavan” zahtjev: s localhosta na produkcijski
/// ingest ide bez CORS preflighta. `keepalive` pušta zahtjev da završi i kad
/// se tab zatvara (limit 64 KB po zahtjevu; batch je manji, vidi Analytics).
Future<SendResult> sendBatch(String url, String body) async {
  try {
    final headers = web.Headers()..set('Content-Type', 'text/plain');
    final res = await web.window
        .fetch(
          url.toJS,
          web.RequestInit(
            method: 'POST',
            body: body.toJS,
            headers: headers,
            keepalive: true,
            credentials: 'omit',
          ),
        )
        .toDart;
    return resultForStatus(res.status);
  } catch (_) {
    return SendResult.retry;
  }
}

String? documentReferrer() {
  try {
    final r = web.document.referrer;
    return r.isEmpty ? null : r;
  } catch (_) {
    return null;
  }
}
