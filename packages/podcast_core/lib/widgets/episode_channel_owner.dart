/// Površine ekrana epizode koje ovise o postavkama kanala (lanac
/// `postavke-kanala/`, S5): povučen/obrisan kanal, reprodukcija samo preko
/// YouTubea (`cdn_playback`) i tekst umjesto Magisterium ocjene.
///
/// Dijele ih `/v/` (oba rasporeda), `/m/` i TV, pa je pravilo na jednom mjestu.
library;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../router/nav.dart';
import '../services/cdn_config.dart';
import '../services/channel_feature_gate.dart';
import '../services/data_service.dart';
import 'channel_gone_view.dart';
import 'youtube_embed.dart';

/// Poveznica na izvornu snimku za povučen prikaz: YouTube video kad ga ima,
/// inače izvorna stranica (X, RSS); `null` kad nema ničega.
String? episodeSourceUrl(EpisodeData data) {
  if (!data.info.isX && data.info.ytMatched) {
    return 'https://www.youtube.com/watch?v=${data.youtubeVideoId}';
  }
  return data.info.sourceUrl;
}

/// Je li vlasnik kanala isključio reprodukciju s našeg CDN-a — tada ekran
/// nudi samo službeni YouTube embed (i Cast se ne nudi).
bool episodeYouTubeOnly(EpisodeData data) =>
    !data.featureOn(EpisodeKey.cdnPlayback);

/// Treba li umjesto Magisterium ocjene stajati „Vlasnik je isključio
/// procjenu” (samo brend s domenskom ocjenom; odluka 2/504).
bool episodeMagisteriumOffByOwner(EpisodeData data) =>
    DataService.domainScoreEnabled && !data.featureOn(EpisodeKey.magisterium);

/// Cijeli ekran epizode povučenog ili obrisanog kanala. Nikad 404, nikad
/// player (tvrdi uvjet 3 plana).
class EpisodeChannelGoneScreen extends StatelessWidget {
  const EpisodeChannelGoneScreen({
    super.key,
    required this.data,
    this.showBack = true,
  });

  final EpisodeData data;

  /// TV nema app bar sa strelicom (Back je tipka daljinskog).
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final s = data.channelSettings;
    final isDeleted = s?.isDeleted ?? false;
    final view = ChannelGoneView(
      ucId: data.info.youtubeChannelId,
      isDeleted: isDeleted,
      deletedAt: s?.deletedAt,
      youtubeUrl: episodeSourceUrl(data),
    );
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      appBar: showBack
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: AppLocalizations.of(context).commonBack,
                onPressed: () => back(context),
              ),
            )
          : null,
      body: SafeArea(child: view),
    );
  }
}

/// Reprodukcija kad je vlasnik isključio `cdn_playback`: službeni
/// `InAppYouTubePlayer` (facade; na nativeu i Safariju tap otvara
/// youtube.com, pravilo COEP) i rečenica zašto. Sintetički ID-evi (X, RSS,
/// varijante bez YouTubea) nemaju video iza sebe, pa ostaje samo rečenica.
class OwnerYouTubePlayback extends StatelessWidget {
  const OwnerYouTubePlayback({super.key, required this.data});

  final EpisodeData data;

  bool get _hasYouTube => !data.info.isX && data.info.ytMatched;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_hasYouTube)
          InAppYouTubePlayer(
            videoId: data.youtubeVideoId,
            posterUrl: CdnConfig.thumbnailUrl(data.youtubeId),
            playableInEmbed: data.info.playableInEmbed,
          ),
        const OwnerYouTubeCaption(),
      ],
    );
  }
}

/// Rečenica „Vlasnik kanala reprodukciju dopušta samo preko YouTubea.” —
/// ispod YouTube površine koju ekran već ima (`_PlayerTab`, TV).
class OwnerYouTubeCaption extends StatelessWidget {
  const OwnerYouTubeCaption({
    super.key,
    this.padding = const EdgeInsets.only(top: 8),
  });

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Icon(
            Icons.smart_display,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppLocalizations.of(context).episodeYouTubeOnlyByOwner,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// „Vlasnik je isključio procjenu” na mjestu Magisterium panela/taba.
class MagisteriumOffNotice extends StatelessWidget {
  const MagisteriumOffNotice({super.key, this.padding});

  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          Icon(
            Icons.visibility_off_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppLocalizations.of(context).magisteriumOffByOwner,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
