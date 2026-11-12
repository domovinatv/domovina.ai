/// `/yt/:videoId` — samostalan ekran koji pušta BILO KOJI YouTube video kroz
/// službeni youtube-nocookie embed. Ništa osim playera; ako domovina.ai već
/// ima AI-obrađenu epizodu za taj video, ispod je jedan gumb koji vodi na nju.
///
/// Namjerno NEMA blokiranja reklama ni izvlačenja streamova (YouTube ToS,
/// App Store 5.2.3, Google Play) — vidi CLAUDE.md i
/// `docs/plans/2026-10-06-youtube-bez-reklama-plan-b.md` za odbačenu varijantu.
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../src/log.dart' show log;
import '../../router/nav.dart';
import '../../services/channel_visibility.dart';
import '../../services/data_service.dart';
import '../../services/open_url.dart';
import 'youtube_watch_player_native.dart'
    if (dart.library.js_interop) 'youtube_watch_player_web.dart';

/// YouTube video ID: točno 11 znakova iz base64url abecede.
final _videoIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

bool isValidYouTubeId(String id) => _videoIdPattern.hasMatch(id);

class YouTubeWatchScreen extends StatefulWidget {
  final String videoId;

  const YouTubeWatchScreen({super.key, required this.videoId});

  @override
  State<YouTubeWatchScreen> createState() => _YouTubeWatchScreenState();
}

class _YouTubeWatchScreenState extends State<YouTubeWatchScreen> {
  /// True kad na CDN-u postoji `summary.json` — epizoda je prošla AI obradu.
  bool _processed = false;

  bool get _valid => isValidYouTubeId(widget.videoId);

  @override
  void initState() {
    super.initState();
    if (_valid) _checkProcessed();
  }

  Future<void> _checkProcessed() async {
    try {
      final svc = DataService(youtubeId: widget.videoId);
      // `info.json` prvi: iz njega se zna kanal. Povučen ili obrisan kanal
      // (postavke kanala) nema gumb na epizodu; ostala stanja epizoda zna
      // sama, a isključen članak ionako znači da sažetka nema.
      final info = await svc.loadInfo();
      final uc = info.youtubeChannelId;
      if (uc != null) {
        await ChannelVisibility.instance.ready();
        if (ChannelVisibility.instance.isGone(uc)) return;
      }
      final summary = await svc.loadSummary();
      if (mounted && summary != null) setState(() => _processed = true);
    } catch (e) {
      // Bez gumba je ispravan ishod: player radi i bez naše obrade.
      log('YouTubeWatchScreen: summary probe failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final id = widget.videoId;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => back(context),
        ),
        title: Text(l.ytWatchTitle),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_valid)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      l.ytWatchInvalidId,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(color: Colors.white),
                    ),
                  )
                else if (youTubeWatchSupported)
                  // Flexible: na niskom prozoru 16:9 po punoj širini ne stane
                  // uz gumb, pa se player smanji po visini umjesto da prelije.
                  Flexible(
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: YouTubeWatchPlayer(videoId: id),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(
                          l.ytWatchEmbedUnsupported,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: Colors.white70),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => openUrl(
                            'https://www.youtube.com/watch?v=$id',
                          ),
                          icon: const Icon(Icons.open_in_new),
                          label: Text(l.episodeWatchOnYouTube),
                        ),
                      ],
                    ),
                  ),
                if (_valid && _processed)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton.icon(
                      onPressed: () => drillDown(context, '/v/$id'),
                      icon: const Icon(Icons.article_outlined),
                      label: Text(l.ytWatchOpenEpisode),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
