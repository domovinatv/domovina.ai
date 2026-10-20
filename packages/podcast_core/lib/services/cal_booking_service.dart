import 'dart:convert';

import 'package:http/http.dart' as http;

import '../brand/app_brand.dart';
import '../src/log.dart' show log;
import 'locale_service.dart' show appStrings;

/// Klijent za Cal.com booking ("15 min DOMOVINA.ai" / stepanic/15min).
///
/// NE zove api.cal.com direktno — ide kroz Cloudflare worker proxy
/// (`web/_worker.js`, ruta `/api/cal/*`) koji drži `CAL_API_KEY` server-side.
/// Tako ključ NIKAD ne završi u web bundleu (full-account secret).
///
/// Slotovi reflektiraju kolizije s povezanim Google kalendarom (Cal.com to
/// računa server-side); mi samo renderamo native Flutter UI nad rezultatom.
class CalConfig {
  CalConfig._();

  /// Apsolutni base radi na svim platformama: web (same-origin u prod),
  /// native (iOS/Android/macOS) i lokalni dev (worker ima permisivni CORS).
  /// Override za staging/self-host: --dart-define=CAL_PROXY_BASE=...
  static const String _proxyBaseOverride =
      String.fromEnvironment('CAL_PROXY_BASE');

  /// Bez override-a: `<endpoints.site>/api/cal` aktivnog brenda.
  static String get proxyBase => _proxyBaseOverride.isNotEmpty
      ? _proxyBaseOverride
      : '${AppBrand.config.endpoints.site}/api/cal';

  /// Vremenska zona event-typea (host = Europe/Zagreb). Slotovi i booking
  /// se računaju u njoj; UI prikazuje wall-clock iz ISO stringa direktno.
  static const String timeZone = 'Europe/Zagreb';
}

/// Jedan slobodan termin. `iso` je sirov string iz API-ja koji se šalje
/// natrag VERBATIM pri bookingu (offset uključen). `label` je wall-clock
/// ("09:00") izvučen iz stringa — neovisan o vremenskoj zoni uređaja.
class CalSlot {
  final String iso;
  final String dayKey; // "2026-06-22"
  final String label; // "09:00"

  const CalSlot({required this.iso, required this.dayKey, required this.label});
}

/// Rezultat uspješne rezervacije.
class CalBooking {
  final String uid;
  final String? meetingUrl;
  final String startIso;

  const CalBooking({
    required this.uid,
    required this.meetingUrl,
    required this.startIso,
  });
}

/// Korisniku-prikaziva greška (već lokalizirana poruka iz API-ja/proxyja).
class CalException implements Exception {
  final String message;
  const CalException(this.message);
  @override
  String toString() => message;
}

class CalBookingService {
  CalBookingService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Dohvati slobodne slotove u rasponu [from, to] (inkluzivno po danu).
  /// Vraća ravnu listu sortiranu kronološki; UI je grupira po `dayKey`.
  Future<List<CalSlot>> fetchSlots({
    required DateTime from,
    required DateTime to,
  }) async {
    final uri = Uri.parse(
      '${CalConfig.proxyBase}/slots'
      '?start=${_ymd(from)}&end=${_ymd(to)}'
      '&timeZone=${Uri.encodeComponent(CalConfig.timeZone)}',
    );
    log('CalBookingService.fetchSlots ${_ymd(from)}..${_ymd(to)}');
    final res = await _client.get(uri);
    if (res.statusCode != 200) {
      log('CalBookingService.fetchSlots HTTP ${res.statusCode}: ${res.body}');
      throw CalException(appStrings.channelCannotFetchSlots);
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final data = (body['data'] as Map<String, dynamic>?) ?? const {};
    final slots = <CalSlot>[];
    data.forEach((day, list) {
      for (final raw in (list as List)) {
        final iso = (raw as Map)['start'] as String;
        slots.add(CalSlot(iso: iso, dayKey: day, label: _timeLabel(iso)));
      }
    });
    slots.sort((a, b) => a.iso.compareTo(b.iso));
    log('CalBookingService.fetchSlots → ${slots.length} slotova');
    return slots;
  }

  /// Kreira rezervaciju. `startIso` mora biti točan string iz [CalSlot.iso].
  Future<CalBooking> createBooking({
    required String startIso,
    required String name,
    required String email,
    String? notes,
  }) async {
    final uri = Uri.parse('${CalConfig.proxyBase}/book');
    log('CalBookingService.createBooking $startIso <$email>');
    final res = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'start': startIso,
        'name': name,
        'email': email,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        'timeZone': CalConfig.timeZone,
        'language': 'hr',
      }),
    );
    Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw CalException(appStrings.channelBookingUnexpectedResponse);
    }
    final ok = res.statusCode >= 200 &&
        res.statusCode < 300 &&
        body['status'] == 'success';
    if (ok) {
      final d = body['data'] as Map<String, dynamic>;
      return CalBooking(
        uid: (d['uid'] as String?) ?? '',
        meetingUrl: (d['meetingUrl'] as String?) ?? (d['location'] as String?),
        startIso: (d['start'] as String?) ?? startIso,
      );
    }
    final msg = (body['error'] is Map
            ? body['error']['message'] as String?
            : null) ??
        body['message'] as String? ??
        appStrings.channelBookingFailed;
    log('CalBookingService.createBooking FAIL ${res.statusCode}: $msg');
    throw CalException(msg);
  }

  // "2026-06-22T09:00:00.000+02:00" → "09:00"
  static String _timeLabel(String iso) {
    final t = iso.indexOf('T');
    if (t == -1 || iso.length < t + 6) return iso;
    return iso.substring(t + 1, t + 6);
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
