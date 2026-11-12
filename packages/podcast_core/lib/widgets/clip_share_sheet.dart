import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../services/channel_feature_gate.dart';
import '../services/clip_service.dart';
import '../services/open_url.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// Trailing action on a chapter row: opens a sheet to download or copy a link
/// to this chapter as a standalone MP4 clip cut on-demand by cutter.domovina.ai
/// over the arbitrary [startSec, endSec] window. Only shown for episodes with a
/// video source (the cutter needs `video_h264.mp4`).
class ClipShareButton extends StatelessWidget {
  final String videoId;
  final int startSec;
  final int endSec;
  final String title;

  const ClipShareButton({
    super.key,
    required this.videoId,
    required this.startSec,
    required this.endSec,
    required this.title,
  });

  /// Smije li se isječak epizode [videoId] nuditi: vlasnik kanala ga gasi
  /// ključem `share_clips` (postavke kanala, matrica §8). Jedno mjesto za
  /// poglavlja u oba prikaza i članak.
  static bool allowedFor(String videoId) =>
      ChannelFeatureGate.isEnabledNow(videoId, EpisodeKey.shareClips);

  @override
  Widget build(BuildContext context) {
    if (!allowedFor(videoId)) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return IconButton(
      icon: const Icon(Icons.ios_share, size: 18),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      tooltip: AppLocalizations.of(context).clipTooltip,
      color: theme.colorScheme.onSurfaceVariant,
      onPressed: () => showClipShareSheet(
        context,
        videoId: videoId,
        startSec: startSec,
        endSec: endSec,
        title: title,
      ),
    );
  }
}

/// Bottom sheet with two actions: download the chapter clip (a real MP4 file)
/// and copy a shareable link to it.
Future<void> showClipShareSheet(
  BuildContext context, {
  required String videoId,
  required int startSec,
  required int endSec,
  required String title,
}) {
  if (!ClipShareButton.allowedFor(videoId)) return Future.value();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _ClipShareSheet(
      videoId: videoId,
      startSec: startSec,
      endSec: endSec,
      title: title,
    ),
  );
}

class _ClipShareSheet extends StatelessWidget {
  final String videoId;
  final int startSec;
  final int endSec;
  final String title;

  const _ClipShareSheet({
    required this.videoId,
    required this.startSec,
    required this.endSec,
    required this.title,
  });

  static String _clock(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    final durationSec = (endSec - startSec).clamp(0, 1 << 30);
    final minutes = (durationSec / 60).round().clamp(1, 1 << 30);
    final sizeMb = (ClipService.estimatedBytes(durationSec) / 1000000)
        .round()
        .clamp(1, 1 << 30);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header — scissors badge + chapter topic.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: AppTheme.brandPrimary,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.fromBorderSide(
                      AppTheme.brandRim(theme.brightness),
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.content_cut,
                      color: Colors.white,
                      size: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${l.clipShareTitle.toUpperCase()} · ${_clock(startSec)}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: Text(l.clipDownload),
            subtitle: Text(l.clipDownloadSubtitle(sizeMb, minutes)),
            onTap: () {
              openUrl(
                ClipService.rangeDownloadUrl(
                  videoId,
                  startSec,
                  endSec,
                  name: title,
                ),
              );
              Navigator.of(context).pop();
            },
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: Text(l.clipCopyLink),
            subtitle: Text(l.clipCopyLinkSubtitle),
            onTap: () {
              // Capture the messenger before popping the sheet's context away.
              final messenger = ScaffoldMessenger.of(context);
              Clipboard.setData(
                ClipboardData(
                  text: ClipService.rangeInlineUrl(videoId, startSec, endSec),
                ),
              );
              Navigator.of(context).pop();
              messenger.showSnackBar(
                SnackBar(
                  content: Text(l.clipLinkCopied),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Text(
              l.clipHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
