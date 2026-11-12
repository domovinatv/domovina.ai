/// Sponzorski trenuci — dohvat iz `domovina-api` (schema `pinka_finance`).
///
/// Ugovor: `domovina-api/docs/sponzorski-trenuci-ugovor.md`. Dva odvojena
/// čitanja za dvije publike:
///
/// - [loadLive] → gledatelj epizode: plaćeni trenuci koji su SADA uživo
///   (`public_live_moments`), za traku „Sponzorirano · {brand}" i oznake.
/// - [loadOffers] → kupac u izlogu: svi trenuci s cijenom i stanjem
///   (`public_sponsor_moments`). Ime branda tamo NE postoji.
///
/// **Rule (dohvat)**: bez memorije preko sesije i bez pollinga; greška, prazno
/// ili nečitljiv red znači da sloja nema — isto kao `loadSponsorsInVideo`.
/// Plaćeni trenutak nije razlog da se ekran epizode sruši ni uspori.
library;

import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../brand/app_brand.dart';
import '../src/log.dart' show log;
import '../models/sponsor_offer.dart';
import '../models/sponsored_moment.dart';
import 'channel_feature_gate.dart';

/// Kampanja sponzorskih trenutaka po kanalu. MVP ima jednu (ugovor §1, O1:
/// jedna kampanja i jedna `timeline` karta za SVE epizode kanala).
class SponsorCampaign {
  const SponsorCampaign._({
    required this.campaignId,
    required this.channelId,
    required this.channelSlug,
  });

  final String campaignId;

  /// CDN channel id (podvlake), kao u `channels/data/<id>.json`.
  final String channelId;

  /// Slug u URL-u (crtice): `/c/<slug>/oglasi`.
  final String channelSlug;

  static const domovinaTv = SponsorCampaign._(
    campaignId: '7e5a0f3e-2f1d-4c9b-9a51-0d0b1a5e7101',
    channelId: 'domovina_tv',
    channelSlug: 'domovina-tv',
  );

  static const all = [domovinaTv];

  static SponsorCampaign? forChannel(String channelId) {
    for (final c in all) {
      if (c.channelId == channelId) return c;
    }
    return null;
  }

  /// Bucket za logo (javan za čitanje), ugovor §4.
  static const logoBucket = 'sponsor-logos';

  /// ≤ 200 kB — bucket ga nameće, forma javlja prije uploada.
  static const logoMaxBytes = 204800;

  static const logoExtensions = {'png', 'jpg', 'jpeg', 'webp'};
}

class SponsoredMomentsService {
  SponsoredMomentsService({sb.SupabaseClient? client}) : _injected = client;

  static final SponsoredMomentsService instance = SponsoredMomentsService();

  final sb.SupabaseClient? _injected;
  sb.SupabaseClient get _client => _injected ?? sb.Supabase.instance.client;

  static const _schema = 'pinka_finance';

  /// Živi plaćeni trenuci epizode; null kad ih nema ili dohvat ne uspije.
  Future<SponsoredMoments?> loadLive(String youtubeId) async {
    // Trenutke prodaje izlog uz pinku; brend bez nje ih ne prikazuje.
    if (!AppBrand.config.flags.pinka) return null;
    // Vlasnik kanala je isključio plaćene trenutke: traka i značka u sva tri
    // playera nestaju jer je ovo jedini izvor (postavke kanala, matrica §19).
    if (!await ChannelFeatureGate.isEnabled(
      youtubeId,
      EpisodeKey.paidSponsorMoments,
    )) {
      return null;
    }
    try {
      final rows = await _client
          .schema(_schema)
          .from('public_live_moments')
          .select()
          .eq('youtube_id', youtubeId)
          .order('start_sec');
      final moments = SponsoredMoments.fromRows(
        rows,
      ).liveAt(DateTime.now().toUtc());
      if (moments.isEmpty) return null;
      log('SponsoredMoments: ${moments.moments.length} live for $youtubeId');
      return moments;
    } catch (e) {
      log('SponsoredMoments: load failed for $youtubeId — $e');
      return null;
    }
  }

  /// Ponuda u izlogu. [youtubeId] = karta jedne epizode; bez njega svi
  /// trenuci kampanje (popis epizoda). Baca na grešku — izlog bez ponude mora
  /// reći „pokušaj ponovno", a ne pretvarati se da je sve prodano.
  Future<List<SponsorOffer>> loadOffers(
    SponsorCampaign campaign, {
    String? youtubeId,
  }) async {
    var q = _client
        .schema(_schema)
        .from('public_sponsor_moments')
        .select()
        .eq('campaign_id', campaign.campaignId);
    if (youtubeId != null) q = q.eq('youtube_id', youtubeId);
    final rows = await q.order('youtube_id').order('start_sec');
    return SponsorOffer.listFromRows(rows);
  }

  /// Status narudžbe (`contribution_id` je capability, odgovor bez PII).
  Future<SponsorOrderStatus?> orderStatus(String contributionId) async {
    try {
      final data = await _client
          .schema(_schema)
          .rpc(
            'sponsor_order_status',
            params: {'p_contribution_id': contributionId},
          );
      return SponsorOrderStatus.tryParse(data);
    } catch (e) {
      log('SponsorOrder: status failed — $e');
      return null;
    }
  }

  /// Upload loga prije plaćanja (ugovor §4). Vraća put za `logo_path`.
  /// Traži pravi račun — `SponsorEpisodeScreen` prijavu traži prije forme.
  Future<String> uploadLogo(Uint8List bytes, String extension) async {
    final ext = extension.toLowerCase();
    if (!SponsorCampaign.logoExtensions.contains(ext)) {
      throw ArgumentError.value(extension, 'extension');
    }
    if (bytes.length > SponsorCampaign.logoMaxBytes) {
      throw ArgumentError.value(bytes.length, 'bytes', 'logo > 200 kB');
    }
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw StateError('no session');
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final path = '$uid/$id.$ext';
    await _client.storage
        .from(SponsorCampaign.logoBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: sb.FileOptions(
            contentType: logoContentType(ext),
            upsert: false,
          ),
        );
    log('SponsorOrder: logo uploaded ($path, ${bytes.length} B)');
    return path;
  }

  /// Javni URL loga za pregled u formi.
  String logoPublicUrl(String path) =>
      _client.storage.from(SponsorCampaign.logoBucket).getPublicUrl(path);
}

String logoContentType(String ext) => switch (ext) {
  'png' => 'image/png',
  'webp' => 'image/webp',
  _ => 'image/jpeg',
};
