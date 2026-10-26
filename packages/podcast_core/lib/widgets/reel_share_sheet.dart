import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:http/http.dart' as http;

import '../l10n/app_localizations.dart';
import '../models/episode_reels.dart';
import '../services/clip_service.dart';
import '../services/ebook_service.dart';
import '../services/file_share.dart';
import '../services/open_url.dart';
import '../src/log.dart' show log;

/// Dijeljenje istaknutog trenutka: renderirani 9:16 isječak kao DATOTEKA
/// (WhatsApp, poruke…) i, kao kod poglavlja, 16:9 isječak istog raspona s
/// cuttera (`ClipService`, ~27 kB/s — nekoliko MB, pa prolazi i kao poveznica).
///
/// Isti obrazac kao e-knjiga (`ebook_sheet.dart`): `navigator.share` mora pasti
/// unutar korisnikove geste, a isječak je ~35 MB, pa list počne preuzimati čim
/// se otvori i „Pošalji video" se omogući tek kad su bajtovi tu — tap je tada
/// svježa gesta i share ide odmah. CDN za `reels/*.mp4` šalje
/// `access-control-allow-origin: *` (provjereno 26.10.2026.).
Future<void> showReelShareSheet(
  BuildContext context, {
  required EpisodeReel reel,
  required String youtubeId,
  required String episodeUrl,
  required ScaffoldMessengerState messenger,
}) {
  assert(reel.isRendered);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    // Šest redaka ne stane u zadanih 9/16 visine na niskom mobitelu.
    isScrollControlled: true,
    builder: (_) => _ReelShareSheet(
      reel: reel,
      youtubeId: youtubeId,
      episodeUrl: episodeUrl,
      messenger: messenger,
    ),
  );
}

/// Zadnji preuzeti isječak — ponovno otvaranje lista za isti reel je odmah
/// spremno. Samo jedan, jer je svaki ~35 MB.
String? _cachedUrl;
Uint8List? _cachedBytes;
final Map<String, Future<Uint8List>> _inFlight = {};

Future<Uint8List> _download(String url) {
  if (url == _cachedUrl && _cachedBytes != null) {
    return Future.value(_cachedBytes);
  }
  return _inFlight[url] ??= http
      .get(Uri.parse(url))
      .then((r) {
        if (r.statusCode != 200) {
          throw http.ClientException('HTTP ${r.statusCode}', Uri.parse(url));
        }
        _cachedUrl = url;
        _cachedBytes = r.bodyBytes;
        return r.bodyBytes;
      })
      .whenComplete(() => _inFlight.remove(url));
}

class _ReelShareSheet extends StatefulWidget {
  final EpisodeReel reel;
  final String youtubeId;
  final String episodeUrl;
  final ScaffoldMessengerState messenger;

  const _ReelShareSheet({
    required this.reel,
    required this.youtubeId,
    required this.episodeUrl,
    required this.messenger,
  });

  @override
  State<_ReelShareSheet> createState() => _ReelShareSheetState();
}

class _ReelShareSheetState extends State<_ReelShareSheet> {
  Uint8List? _bytes;
  bool _failed = false;
  bool _sharing = false;

  String get _url => widget.reel.render!.url;

  int get _start => widget.reel.startSeconds;
  int get _end => widget.reel.endSec.ceil();

  @override
  void initState() {
    super.initState();
    _prefetch();
  }

  void _prefetch() {
    setState(() => _failed = false);
    _download(_url)
        .then((bytes) {
          if (mounted) setState(() => _bytes = bytes);
        })
        .catchError((Object e) {
          log('Reels: share download failed: $e');
          if (mounted) setState(() => _failed = true);
        });
  }

  Future<void> _send(BuildContext rowContext) async {
    final bytes = _bytes;
    if (bytes == null || _sharing) return;
    final l = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final messenger = widget.messenger;
    final slug = EbookService.fileSlug(widget.reel.title);
    final filename = '${slug.isEmpty ? 'domovina-ai-isjecak' : slug}.mp4';

    setState(() => _sharing = true);
    final outcome = await shareFile(
      bytes: bytes,
      filename: filename,
      mimeType: 'video/mp4',
      text: widget.episodeUrl,
      subject: widget.reel.title,
      sharePositionOrigin: _rectOf(rowContext),
    );
    log('Reels: share #${widget.reel.rank} → $outcome');
    if (!mounted) return;
    setState(() => _sharing = false);
    switch (outcome) {
      case FileShareOutcome.shared:
        navigator.pop();
      case FileShareOutcome.downloaded:
        navigator.pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(l.reelsVideoDownloaded),
            duration: const Duration(seconds: 3),
          ),
        );
      case FileShareOutcome.dismissed:
        break;
      case FileShareOutcome.failed:
        messenger.showSnackBar(SnackBar(content: Text(l.reelsShareFailed)));
    }
  }

  /// iPad share popover bez sidra ne zna gdje se iscrtati.
  static Rect? _rectOf(BuildContext context) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final canShare = canShareFiles();
    final bytes = _bytes;
    final busy = !_failed && (bytes == null || _sharing);

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.reelsShareTitle.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    widget.reel.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Builder(
              builder: (rowContext) => ListTile(
                enabled: (bytes != null && !_sharing) || _failed,
                leading: busy
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _failed
                            ? Icons.refresh
                            : canShare
                            ? Icons.ios_share
                            : Icons.download_outlined,
                      ),
                title: Text(canShare ? l.reelsSendVideo : l.reelsDownloadVideo),
                subtitle: Text(
                  _failed
                      ? l.reelsShareFailed
                      : bytes == null
                      ? l.reelsPreparing
                      : [
                          'MP4',
                          EbookService.formatSize(bytes.length),
                          if (canShare) l.reelsSendHint,
                        ].join(' · '),
                ),
                onTap: _failed ? _prefetch : () => _send(rowContext),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: Text(l.reelsCopyVideoLink),
              onTap: () {
                Clipboard.setData(ClipboardData(text: _url));
                Navigator.of(context).pop();
                widget.messenger.showSnackBar(
                  SnackBar(
                    content: Text(l.reelsVideoLinkCopied),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
            const Divider(height: 16),
            ListTile(
              leading: const Icon(Icons.content_cut),
              title: Text(l.reelsDownloadWide),
              subtitle: Text(
                l.clipDownloadSubtitle(
                  (ClipService.estimatedBytes(_end - _start) / 1000000)
                      .round()
                      .clamp(1, 1 << 30),
                  ((_end - _start) / 60).round().clamp(1, 1 << 30),
                ),
              ),
              onTap: () {
                openUrl(
                  ClipService.rangeDownloadUrl(
                    widget.youtubeId,
                    _start,
                    _end,
                    name: widget.reel.title,
                  ),
                );
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: Text(l.reelsCopyWideLink),
              subtitle: Text(l.clipCopyLinkSubtitle),
              onTap: () {
                Clipboard.setData(
                  ClipboardData(
                    text: ClipService.rangeInlineUrl(
                      widget.youtubeId,
                      _start,
                      _end,
                    ),
                  ),
                );
                Navigator.of(context).pop();
                widget.messenger.showSnackBar(
                  SnackBar(
                    content: Text(l.clipLinkCopied),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                l.clipHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
