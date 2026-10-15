import 'package:http/http.dart' as http;

import 'analytics_transport.dart' show SendResult, resultForStatus;

Future<SendResult> sendBatch(String url, String body) async {
  try {
    final res = await http
        .post(
          Uri.parse(url),
          headers: const {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(const Duration(seconds: 10));
    return resultForStatus(res.statusCode);
  } catch (_) {
    return SendResult.retry;
  }
}

String? documentReferrer() => null;

bool? documentVisible() => null;

void listenDocumentVisibility(void Function(bool visible) onChange) {}
