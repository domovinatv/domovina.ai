/// Postavke kanala za vlasnika (lanac `postavke-kanala/`, S4).
///
/// 20 ključeva su ugovor svih potrošača (odluka 1) i ne preimenuju se. Izvor
/// je `domovina_ai.public_channel_settings` u domovina-api: `settings` je
/// RIJEDAK (samo ključevi koje je vlasnik postavio, nedostaje = `true`,
/// odluka 203), a `effective` je efektivno stanje svih 20 koje računa jedna
/// SQL funkcija (odluka 200). Klijent efektivno stanje NE preračunava; mapa
/// roditelja ovdje služi samo za tekst objašnjenja zašto je prekidač siv.
library;

/// Skupina prekidača na ekranu (odluka 1).
enum ChannelSettingGroup { main, presence, media, ai, money }

/// Jedan ključ i njegova skupina.
class ChannelSettingDef {
  const ChannelSettingDef(this.key, this.group);
  final String key;
  final ChannelSettingGroup group;
}

/// Glavni prekidač: isključen gasi sve ostale.
const String kChannelEnabledKey = 'channel_enabled';

/// Svih 20 ključeva redom iz odluke 1.
const List<ChannelSettingDef> kChannelSettingDefs = [
  ChannelSettingDef('channel_enabled', ChannelSettingGroup.main),
  ChannelSettingDef('processing', ChannelSettingGroup.presence),
  ChannelSettingDef('home_featured', ChannelSettingGroup.presence),
  ChannelSettingDef('in_app_search', ChannelSettingGroup.presence),
  ChannelSettingDef('search_engines', ChannelSettingGroup.presence),
  ChannelSettingDef('push_notifications', ChannelSettingGroup.presence),
  ChannelSettingDef('cdn_playback', ChannelSettingGroup.media),
  ChannelSettingDef('share_clips', ChannelSettingGroup.media),
  ChannelSettingDef('ebook', ChannelSettingGroup.media),
  ChannelSettingDef('article_summary', ChannelSettingGroup.ai),
  ChannelSettingDef('transcript_subtitles', ChannelSettingGroup.ai),
  ChannelSettingDef('english_translation', ChannelSettingGroup.ai),
  ChannelSettingDef('magisterium', ChannelSettingGroup.ai),
  ChannelSettingDef('highlights_reels', ChannelSettingGroup.ai),
  ChannelSettingDef('persons_mentions', ChannelSettingGroup.ai),
  ChannelSettingDef('news_portal', ChannelSettingGroup.ai),
  ChannelSettingDef('ai_assistants', ChannelSettingGroup.ai),
  ChannelSettingDef('donations', ChannelSettingGroup.money),
  ChannelSettingDef('paid_sponsor_moments', ChannelSettingGroup.money),
  ChannelSettingDef('sponsors_in_video', ChannelSettingGroup.money),
];

/// Samo imena ključeva, istim redom.
final List<String> kChannelSettingKeys = [
  for (final d in kChannelSettingDefs) d.key,
];

/// Ključevi jedne skupine, redom iz odluke 1.
List<String> channelSettingKeysOf(ChannelSettingGroup group) => [
  for (final d in kChannelSettingDefs)
    if (d.group == group) d.key,
];

/// Izravni ovisni ključevi (odluka 108, potvrđena u 200): `transcript_subtitles`
/// gasi AI skupinu, `article_summary` gasi ono što se gradi iz članka.
const Map<String, List<String>> kChannelSettingDependents = {
  'transcript_subtitles': [
    'article_summary',
    'english_translation',
    'magisterium',
    'highlights_reels',
    'persons_mentions',
    'news_portal',
    'ai_assistants',
  ],
  'article_summary': [
    'ebook',
    'magisterium',
    'english_translation',
    'share_clips',
    'news_portal',
  ],
};

/// Ovisi li [key] (izravno ili preko lanca) o [parent].
bool channelSettingDependsOn(String key, String parent) {
  if (parent == kChannelEnabledKey) return key != kChannelEnabledKey;
  final direct = kChannelSettingDependents[parent] ?? const <String>[];
  if (direct.contains(key)) return true;
  return direct.any((d) => channelSettingDependsOn(key, d));
}

/// Stanje postavki jednog kanala: sirovo (što je vlasnik postavio) i
/// efektivno (što stvarno vrijedi, iz viewa ili odgovora RPC-a).
class ChannelSettings {
  const ChannelSettings({
    this.raw = const {},
    this.effective = const {},
    this.updatedAt,
    this.tombstoned = false,
  });

  /// Kanal bez retka u viewu: sve uključeno.
  static const ChannelSettings defaults = ChannelSettings();

  /// Rijetko: samo postavljeni ključevi.
  final Map<String, bool> raw;

  /// Efektivno stanje; ključ koji nedostaje = `true`.
  final Map<String, bool> effective;
  final DateTime? updatedAt;
  final bool tombstoned;

  /// Sirova vrijednost: nepostavljen ili nepoznat ključ = `true`.
  bool rawValue(String key) => raw[key] ?? true;

  /// Efektivna vrijednost: ključ koji nedostaje = `true`.
  bool effectiveValue(String key) => effective[key] ?? true;

  /// Vlasnik ga je ostavio uključenim, ali ga gasi roditelj (ili brisanje).
  bool isOverridden(String key) => rawValue(key) && !effectiveValue(key);

  /// Prvi roditelj čija SIROVA vrijednost gasi [key]: `channel_enabled`,
  /// pa `transcript_subtitles`, pa `article_summary`. `null` kad nijedan
  /// (npr. obrisan kanal) — tada ekran daje općenito objašnjenje.
  String? blockingParent(String key) {
    for (final parent in const [
      kChannelEnabledKey,
      'transcript_subtitles',
      'article_summary',
    ]) {
      if (parent == key) continue;
      if (!rawValue(parent) && channelSettingDependsOn(key, parent)) {
        return parent;
      }
    }
    return null;
  }

  /// Red iz `public_channel_settings`; `null` (kanal bez retka) = sve
  /// uključeno.
  factory ChannelSettings.fromView(Map<String, dynamic>? row) {
    if (row == null) return defaults;
    return ChannelSettings(
      raw: _boolMap(row['settings']),
      effective: _boolMap(row['effective']),
      updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? ''),
      tombstoned: row['tombstoned'] == true,
    );
  }

  /// Optimistično: promijeni samo sirovu vrijednost.
  ChannelSettings withRaw(String key, bool value) => ChannelSettings(
    raw: {...raw, key: value},
    effective: effective,
    updatedAt: updatedAt,
    tombstoned: tombstoned,
  );

  /// Efektivno stanje iz odgovora `set_channel_setting`.
  ChannelSettings withEffective(Map<String, dynamic> next) => ChannelSettings(
    raw: raw,
    effective: _boolMap(next),
    updatedAt: updatedAt,
    tombstoned: tombstoned,
  );

  static Map<String, bool> _boolMap(Object? json) {
    if (json is! Map) return const {};
    return {
      for (final e in json.entries)
        if (e.value is bool) e.key.toString(): e.value as bool,
    };
  }
}

/// Vrsta događaja u logu (`channel_settings_events.kind`, odluka 204).
enum ChannelSettingsEventKind {
  setting,
  deletionRequested,
  deletionCancelled,
  deletionPhoneConfirmed,
  deletionExecuted,
  unknown;

  static ChannelSettingsEventKind fromJson(String? raw) => switch (raw) {
    'setting' => setting,
    'deletion_requested' => deletionRequested,
    'deletion_cancelled' => deletionCancelled,
    'deletion_phone_confirmed' => deletionPhoneConfirmed,
    'deletion_executed' => deletionExecuted,
    _ => unknown,
  };
}

/// Jedan red loga. Imena računa nema (backend ih ne vraća); ekran pokazuje
/// ulogu i „ti” za vlastiti račun.
class ChannelSettingsEvent {
  const ChannelSettingsEvent({
    required this.id,
    required this.kind,
    this.key,
    this.oldValue,
    this.newValue,
    this.accountId,
    this.role,
    this.source = 'app',
    this.createdAt,
    this.pending = false,
  });

  /// `null` za lokalni (optimistični) red koji još nije u bazi.
  final int? id;
  final ChannelSettingsEventKind kind;
  final String? key;
  final bool? oldValue;
  final bool? newValue;
  final String? accountId;

  /// `primary` | `collaborator` (za `app`), inače `null`.
  final String? role;

  /// `app` | `phone` | `system`.
  final String source;
  final DateTime? createdAt;

  /// Lokalni red „sprema se”.
  final bool pending;

  factory ChannelSettingsEvent.fromJson(Map<String, dynamic> json) =>
      ChannelSettingsEvent(
        id: (json['id'] as num?)?.toInt(),
        kind: ChannelSettingsEventKind.fromJson(json['kind'] as String?),
        key: json['key'] as String?,
        oldValue: json['old_value'] as bool?,
        newValue: json['new_value'] as bool?,
        accountId: json['account_id'] as String?,
        role: json['role'] as String?,
        source: json['source'] as String? ?? 'app',
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      );

  /// Optimistični red za promjenu prekidača.
  factory ChannelSettingsEvent.pendingSetting({
    required String key,
    required bool oldValue,
    required bool newValue,
    String? accountId,
    String? role,
    DateTime? at,
  }) => ChannelSettingsEvent(
    id: null,
    kind: ChannelSettingsEventKind.setting,
    key: key,
    oldValue: oldValue,
    newValue: newValue,
    accountId: accountId,
    role: role,
    createdAt: at,
    pending: true,
  );
}

/// Stanje zahtjeva za trajno brisanje.
enum ChannelDeletionState {
  requested,
  cancelled,
  phoneConfirmed,
  executed,
  unknown;

  static ChannelDeletionState fromJson(String? raw) => switch (raw) {
    'requested' => requested,
    'cancelled' => cancelled,
    'phone_confirmed' => phoneConfirmed,
    'executed' => executed,
    _ => unknown,
  };
}

/// Red iz `channel_deletion_requests`.
class ChannelDeletionRequest {
  const ChannelDeletionRequest({
    required this.id,
    required this.youtubeChannelId,
    required this.state,
    this.channelTitle,
    this.requestedBy,
    this.requestedRole,
    this.requestedAt,
    this.cancelledAt,
    this.phoneConfirmedAt,
    this.executedAt,
  });

  final String id;
  final String youtubeChannelId;
  final String? channelTitle;
  final String? requestedBy;
  final String? requestedRole;
  final ChannelDeletionState state;
  final DateTime? requestedAt;
  final DateTime? cancelledAt;
  final DateTime? phoneConfirmedAt;
  final DateTime? executedAt;

  /// Otvoren = čeka poziv ili je poziv potvrđen, a brisanje još nije izvršeno.
  bool get isOpen =>
      state == ChannelDeletionState.requested ||
      state == ChannelDeletionState.phoneConfirmed;

  /// Otkazati se može samo prije potvrde poziva.
  bool get canCancel => state == ChannelDeletionState.requested;

  factory ChannelDeletionRequest.fromJson(Map<String, dynamic> json) {
    DateTime? t(String k) => DateTime.tryParse(json[k] as String? ?? '');
    return ChannelDeletionRequest(
      id: json['id'] as String? ?? '',
      youtubeChannelId: json['youtube_channel_id'] as String? ?? '',
      channelTitle: json['channel_title'] as String?,
      requestedBy: json['requested_by'] as String?,
      requestedRole: json['requested_role'] as String?,
      state: ChannelDeletionState.fromJson(json['state'] as String?),
      requestedAt: t('requested_at'),
      cancelledAt: t('cancelled_at'),
      phoneConfirmedAt: t('phone_confirmed_at'),
      executedAt: t('executed_at'),
    );
  }
}

/// Jedan kanal iz kataloga `GET /v1/settings` (odluka 312): samo kanali s
/// barem jednim isključenim ključem ili tombstoneom. Za javni prikaz (S5).
class CatalogChannelSettings {
  const CatalogChannelSettings({
    required this.status,
    required this.off,
    this.deletedAt,
  });

  /// `active` | `withdrawn` | `deleted`.
  final String status;

  /// Efektivno isključeni ključevi (sortirani).
  final Set<String> off;
  final DateTime? deletedAt;

  bool get isDeleted => status == 'deleted';
  bool get isWithdrawn => status == 'withdrawn';

  /// Vrijedi li [key]: ključ izvan `off` je uključen.
  bool isEnabled(String key) => !off.contains(key);

  /// `null` za zapis koji nije objekt.
  static CatalogChannelSettings? fromJson(Object? json) {
    if (json is! Map) return null;
    final off = json['off'];
    return CatalogChannelSettings(
      status: json['status'] as String? ?? 'active',
      off: {
        if (off is List)
          for (final k in off)
            if (k is String) k,
      },
      deletedAt: DateTime.tryParse(json['deleted_at'] as String? ?? ''),
    );
  }

  /// Cijeli odgovor `{"settings": {UC: {...}}, ...}` → mapa po UC-u.
  /// `null` kad odgovor nema `settings` objekt (nečitljiv).
  static Map<String, CatalogChannelSettings>? parseResponse(Object? json) {
    if (json is! Map) return null;
    final settings = json['settings'];
    if (settings is! Map) return null;
    final out = <String, CatalogChannelSettings>{};
    for (final e in settings.entries) {
      final v = fromJson(e.value);
      if (v != null) out[e.key.toString()] = v;
    }
    return out;
  }
}
