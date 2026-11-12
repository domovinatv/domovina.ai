/// Postavke kanala za vlasnika (lanac `postavke-kanala/`, S4): čitanje
/// `public_channel_settings`, pisanje kroz RPC `set_channel_setting`, log
/// (`get_channel_settings_log`), zahtjev za trajno brisanje i njegovo
/// otkazivanje, sve u shemi `domovina_ai` (domovina-api).
///
/// Ekran ide kroz [ChannelSettingsBackend], pa widget testovi idu s lažnjakom
/// bez mreže ([ChannelSettingsBackend.instance] je zamjenjiv, a ekran prima
/// i backend kroz konstruktor).
///
/// Greške backend vraća kao P0001 s porukom koja POČINJE kodom
/// (`not_owner`, `unknown_key: x`, …); ovdje postaju
/// [ChannelSettingsException] s kodom do prve dvotočke.
///
/// Katalog (`GET {catalog}/settings`) servis samo čita i parsira za javni
/// prikaz (S5). Ekran postavki ga NE koristi: kasni do ~1,5 min i nosi samo
/// efektivni `off`, ne sirove vrijednosti.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../brand/app_brand.dart';
import '../models/channel_claim.dart';
import '../models/channel_settings.dart';
import '../src/log.dart' show log;
import 'channel_ownership_service.dart';

export '../models/channel_settings.dart';

/// Tipizirana greška s kodom backenda.
class ChannelSettingsException implements Exception {
  const ChannelSettingsException(this.code, [this.message]);

  /// Kod do prve dvotočke (`not_owner`, `confirm_name_mismatch`, …), ili
  /// `network` kad backend nije odgovorio, ili `unknown`.
  final String code;
  final String? message;

  /// Kodovi koje backend šalje (migracija `20261111120000`).
  static const Set<String> knownCodes = {
    'login_required',
    'not_owner',
    'unknown_key',
    'invalid_value',
    'channel_deleted',
    'confirm_name_mismatch',
    'deletion_already_requested',
    'no_open_request',
    'invalid_state',
    'invalid_transition',
  };

  /// Kod iz poruke: prefiks do prve dvotočke. Poruka bez poznatog koda
  /// daje `unknown`.
  static String codeFrom(String? message) {
    final m = (message ?? '').trim();
    final i = m.indexOf(':');
    final head = (i < 0 ? m : m.substring(0, i)).trim();
    return knownCodes.contains(head) ? head : 'unknown';
  }

  @override
  String toString() =>
      'ChannelSettingsException($code${message == null ? '' : ': $message'})';
}

/// Sučelje prema domovina-api. Sve metode bacaju samo
/// [ChannelSettingsException].
abstract class ChannelSettingsBackend {
  /// Zamjenjiv u testovima.
  static ChannelSettingsBackend instance = SupabaseChannelSettingsBackend();

  /// Id prijavljenog (ne-anonimnog) računa, inače `null`.
  String? get currentUserId;

  /// Claim trenutnog korisnika za kanal (`null` ako ga nema).
  Future<ChannelClaim?> myClaim(String ucId);

  /// Red iz `public_channel_settings`; kanal bez retka = sve uključeno.
  Future<ChannelSettings> fetchSettings(String ucId);

  /// `set_channel_setting` → efektivno stanje svih 20 ključeva.
  Future<Map<String, dynamic>> setSetting(String ucId, String key, bool value);

  /// `get_channel_settings_log`, od najnovijeg. [before] = id zadnjeg
  /// prikazanog reda (stranica starijih).
  Future<List<ChannelSettingsEvent>> fetchLog(
    String ucId, {
    int limit = 50,
    int? before,
  });

  /// Otvoren zahtjev za brisanje (`requested` ili `phone_confirmed`), ili
  /// `null`.
  Future<ChannelDeletionRequest?> fetchOpenDeletionRequest(String ucId);

  /// `request_channel_deletion` → id zahtjeva.
  Future<String> requestDeletion(String ucId, String confirmName);

  /// `cancel_channel_deletion` → id otkazanog zahtjeva.
  Future<String> cancelDeletion(String ucId);
}

/// Produkcijska izvedba nad `Supabase.instance.client.schema('domovina_ai')`.
class SupabaseChannelSettingsBackend implements ChannelSettingsBackend {
  sb.SupabaseClient get _client => sb.Supabase.instance.client;
  sb.SupabaseQuerySchema get _db => _client.schema('domovina_ai');

  @override
  String? get currentUserId {
    final user = _client.auth.currentUser;
    if (user == null || user.isAnonymous) return null;
    return user.id;
  }

  @override
  Future<ChannelClaim?> myClaim(String ucId) =>
      ChannelOwnershipService.instance.myClaimFor(ucId);

  @override
  Future<ChannelSettings> fetchSettings(String ucId) =>
      _guard('fetchSettings', () async {
        final row = await _db
            .from('public_channel_settings')
            .select()
            .eq('youtube_channel_id', ucId)
            .maybeSingle();
        return ChannelSettings.fromView(row);
      });

  @override
  Future<Map<String, dynamic>> setSetting(
    String ucId,
    String key,
    bool value,
  ) => _guard('setSetting', () async {
    final res = await _db.rpc(
      'set_channel_setting',
      params: {'p_youtube_channel_id': ucId, 'p_key': key, 'p_value': value},
    );
    if (res is! Map) throw const ChannelSettingsException('unknown');
    return res.cast<String, dynamic>();
  });

  @override
  Future<List<ChannelSettingsEvent>> fetchLog(
    String ucId, {
    int limit = 50,
    int? before,
  }) => _guard('fetchLog', () async {
    final res = await _db.rpc(
      'get_channel_settings_log',
      params: {
        'p_youtube_channel_id': ucId,
        'p_limit': limit,
        'p_before': before,
      },
    );
    return [
      for (final r in (res as List? ?? const []))
        ChannelSettingsEvent.fromJson((r as Map).cast<String, dynamic>()),
    ];
  });

  @override
  Future<ChannelDeletionRequest?> fetchOpenDeletionRequest(String ucId) =>
      _guard('fetchOpenDeletionRequest', () async {
        final row = await _db
            .from('channel_deletion_requests')
            .select()
            .eq('youtube_channel_id', ucId)
            .inFilter('state', ['requested', 'phone_confirmed'])
            .order('requested_at', ascending: false)
            .limit(1)
            .maybeSingle();
        return row == null ? null : ChannelDeletionRequest.fromJson(row);
      });

  @override
  Future<String> requestDeletion(String ucId, String confirmName) =>
      _guard('requestDeletion', () async {
        final res = await _db.rpc(
          'request_channel_deletion',
          params: {'p_youtube_channel_id': ucId, 'p_confirm_name': confirmName},
        );
        return res.toString();
      });

  @override
  Future<String> cancelDeletion(String ucId) =>
      _guard('cancelDeletion', () async {
        final res = await _db.rpc(
          'cancel_channel_deletion',
          params: {'p_youtube_channel_id': ucId},
        );
        return res.toString();
      });

  Future<T> _guard<T>(String tag, Future<T> Function() body) async {
    try {
      return await body();
    } on ChannelSettingsException {
      rethrow;
    } on sb.PostgrestException catch (e) {
      log('channel settings $tag: ${e.code} ${e.message}');
      throw ChannelSettingsException(
        ChannelSettingsException.codeFrom(e.message),
        e.message,
      );
    } catch (e) {
      log('channel settings $tag: $e');
      throw ChannelSettingsException('network', e.toString());
    }
  }
}

/// Katalog `GET {AppBrand.config.endpoints.catalog}/settings` (odluka 312)
/// za javni prikaz (S5). Kasni za izvorom do ~1,5 min (odluka 316).
class ChannelSettingsCatalog {
  ChannelSettingsCatalog({
    http.Client? client,
    String? baseUrl,
    this.timeout = const Duration(seconds: 4),
  }) : _client = client,
       _baseUrl = baseUrl;

  final http.Client? _client;
  final String? _baseUrl;
  final Duration timeout;

  String get baseUrl => _baseUrl ?? AppBrand.config.endpoints.catalog;
  String get settingsUrl => '$baseUrl/settings';

  /// Mapa UC → stanje. Kanal kojeg nema u mapi ima sve uključeno. `null` =
  /// katalog nije dostupan (nema endpointa, mreža, timeout, ne-200,
  /// nečitljiv odgovor). Nikad ne baca.
  Future<Map<String, CatalogChannelSettings>?> fetch() async {
    if (baseUrl.isEmpty) return null;
    try {
      final uri = Uri.parse(settingsUrl);
      final c = _client;
      final res = await (c == null ? http.get(uri) : c.get(uri)).timeout(
        timeout,
      );
      if (res.statusCode != 200) {
        log('katalog settings: HTTP ${res.statusCode}');
        return null;
      }
      return parse(utf8.decode(res.bodyBytes));
    } catch (e) {
      log('katalog settings: $e');
      return null;
    }
  }

  /// Tijelo odgovora → mapa; `null` kad nije čitljivo.
  static Map<String, CatalogChannelSettings>? parse(String body) {
    try {
      return CatalogChannelSettings.parseResponse(jsonDecode(body));
    } catch (_) {
      return null;
    }
  }
}
