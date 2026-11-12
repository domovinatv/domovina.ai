import 'dart:convert';

import 'catalog_card.dart';

/// Kanal kako ga opisuje katalog (`katalog/contract/v1/channel.schema.json`):
/// zaglavlje `GET /channels/:slug` i stavka popisa `GET /directory` /
/// `GET /channels?tier=`. Oba tiera, samo kanali s barem jednom obrađenom
/// epizodom.
///
/// Slug Tier 1 kanala je ID listinga s podvlakom (`radio_mreznica`), Tier 2
/// kanala crtice (`sbs-croatian`) ili `yt-…`/`x-…` za kanal bez registry
/// unosa ([unregistered]). Ruta je [channel].`routeSlug`.
class CatalogChannelInfo {
  final String slug;
  final String name;
  final int tier;
  final String? lang;

  /// Apsolutni URL slike ili `null` (Tier 2 je danas gotovo uvijek `null`).
  final String? avatar;
  final String? youtubeChannelId;

  /// Broj epizoda koje lista `/channels/:slug/episodes` (bez varijanti).
  final int processedCount;

  /// `YYYY-MM-DD` zadnje obrađene epizode, ili `null`.
  final String? latestPublishedDate;

  /// Tier 2 kanal bez registry unosa (`yt-…`, `x-…`, katalog odluka 205).
  final bool unregistered;

  /// Stanje kanala iz omotnice `/channels/:slug` (`state`, odluka 309):
  /// `withdrawn`, `deleted` ili `null` (aktivan).
  final String? state;

  /// Trenutak brisanja (`deleted_at` omotnice) uz `state: deleted`.
  final DateTime? deletedAt;

  /// Isključeni ključevi postavki (`item.settings`, samo `false` vrijednosti).
  final Set<String> off;

  bool get isWithdrawn =>
      state == 'withdrawn' || (state == null && off.contains('channel_enabled'));
  bool get isDeleted => state == 'deleted';

  /// Povučen ili obrisan: sadržaj se ne prikazuje (nikad 404).
  bool get isGone => isWithdrawn || isDeleted;

  const CatalogChannelInfo({
    required this.slug,
    required this.name,
    required this.tier,
    required this.processedCount,
    this.lang,
    this.avatar,
    this.youtubeChannelId,
    this.latestPublishedDate,
    this.unregistered = false,
    this.state,
    this.deletedAt,
    this.off = const {},
  });

  /// Isti kanal u obliku koji nosi kartica epizode (`{slug, name, tier}`),
  /// s pravilom rute ([CatalogChannel.routeSlug]) na jednom mjestu.
  CatalogChannel get channel =>
      CatalogChannel(slug: slug, name: name, tier: tier);

  /// Kanal koji DOMOVINA prati stalno (statični listing postoji).
  bool get followed => tier == 1;

  /// Jedan kanal iz popisa ili `item` odgovora. `null` kad obavezna polja
  /// (`slug`, `name`, `tier`) nedostaju ili imaju krivi tip; neobavezna
  /// polja krivog tipa postaju `null` (broj epizoda 0). Nikad ne baca.
  static CatalogChannelInfo? fromItem(Object? item) {
    final ref = CatalogChannel.tryParse(item);
    if (ref == null || item is! Map) return null;
    String? str(String key) {
      final v = item[key];
      return v is String && v.isNotEmpty ? v : null;
    }

    final count = item['processed_count'];
    final settings = item['settings'];
    return CatalogChannelInfo(
      slug: ref.slug,
      name: ref.name,
      tier: ref.tier,
      lang: str('lang'),
      avatar: str('avatar'),
      youtubeChannelId: str('youtube_channel_id'),
      processedCount: count is num && count >= 0 ? count.toInt() : 0,
      latestPublishedDate: str('latest_published_date'),
      unregistered: item['unregistered'] == true,
      off: {
        if (settings is Map)
          for (final e in settings.entries)
            if (e.key is String && e.value == false) e.key as String,
      },
    );
  }

  /// Isti kanal sa stanjem iz omotnice odgovora.
  CatalogChannelInfo withState(String? state, DateTime? deletedAt) =>
      CatalogChannelInfo(
        slug: slug,
        name: name,
        tier: tier,
        lang: lang,
        avatar: avatar,
        youtubeChannelId: youtubeChannelId,
        processedCount: processedCount,
        latestPublishedDate: latestPublishedDate,
        unregistered: unregistered,
        state: state,
        deletedAt: deletedAt,
        off: off,
      );

  /// Tijelo `GET /channels/:slug` → kanal, ili `null` kad tijelo nije JSON,
  /// verzija nije [CatalogCard.supportedVersion] ili `item` nije čitljiv.
  static CatalogChannelInfo? tryParseResponse(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map) return null;
      if (json['version'] != CatalogCard.supportedVersion) return null;
      final info = fromItem(json['item']);
      final state = json['state'];
      if (info == null || state is! String || state == 'active') return info;
      final deletedAt = json['deleted_at'];
      return info.withState(
        state,
        deletedAt is String ? DateTime.tryParse(deletedAt) : null,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => 'CatalogChannelInfo($slug, tier $tier, $processedCount)';
}

/// Jedna stranica `GET /directory` ili `GET /channels?tier=` (ugovori
/// `directory.schema.json`, `channels.schema.json`): kanali poredani po
/// `latest_published_date` silazno.
class CatalogDirectoryPage {
  final List<CatalogChannelInfo> items;

  /// Neproziran keyset kursor; `null` na zadnjoj stranici.
  final String? next;

  /// ID zadnjeg uvoza — samo za log.
  final String? catalog;

  const CatalogDirectoryPage({required this.items, this.next, this.catalog});

  bool get isEmpty => items.isEmpty;
  bool get hasMore => next != null;

  /// `null` kad tijelo nije JSON, verzija nije podržana ili `items` nije
  /// lista. Nečitljiva stavka se preskače. Nikad ne baca.
  static CatalogDirectoryPage? tryParse(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map) return null;
      if (json['version'] != CatalogCard.supportedVersion) return null;
      final raw = json['items'];
      if (raw is! List) return null;
      return CatalogDirectoryPage(
        // Povučen kanal (`settings.channel_enabled: false`) se ne nabraja.
        items: [
          for (final item in raw)
            if (CatalogChannelInfo.fromItem(item) case final c? when !c.isGone)
              c,
        ],
        next: _cursor(json['next']),
        catalog: json['catalog'] is String ? json['catalog'] as String : null,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Jedna stranica `GET /channels/:slug/episodes` (ugovor
/// `channel-episodes.schema.json`): kartice epizoda kanala, najnovije prve.
class CatalogChannelEpisodesPage {
  /// Slug kanala kako je zatražen.
  final String slug;
  final List<CatalogCard> items;
  final String? next;
  final String? catalog;

  const CatalogChannelEpisodesPage({
    required this.slug,
    required this.items,
    this.next,
    this.catalog,
  });

  bool get isEmpty => items.isEmpty;
  bool get hasMore => next != null;

  /// Ista pravila kao [CatalogDirectoryPage.tryParse]; stavka je kartica
  /// ([CatalogCard.fromItem]).
  static CatalogChannelEpisodesPage? tryParse(
    String body, {
    required String slug,
  }) {
    try {
      final json = jsonDecode(body);
      if (json is! Map) return null;
      if (json['version'] != CatalogCard.supportedVersion) return null;
      final raw = json['items'];
      if (raw is! List) return null;
      final catalog = json['catalog'] is String
          ? json['catalog'] as String
          : null;
      return CatalogChannelEpisodesPage(
        slug: slug,
        items: [
          for (final item in raw) ?CatalogCard.fromItem(item, catalog: catalog),
        ],
        next: _cursor(json['next']),
        catalog: catalog,
      );
    } catch (_) {
      return null;
    }
  }
}

String? _cursor(Object? raw) => raw is String && raw.isNotEmpty ? raw : null;
