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

/// Preuzimanje 9:16 isječka u memoriju, s napretkom.
///
/// Živi IZVAN lista: zatvoren pa ponovno otvoren list nastavlja isto
/// preuzimanje (ili odmah ima bajtove), umjesto da krene ispočetka. Pamti se
/// samo zadnji reel, jer je svaki ~35 MB. `http` 1.6 na webu ide kroz `fetch`
/// i čita tijelo kao stream, pa napredak radi i u browseru (`Content-Length`
/// je u CDN-ovom `access-control-expose-headers`).
class _ReelDownload extends ChangeNotifier {
  final String url;
  int received = 0;
  int? total;
  Uint8List? bytes;
  Object? error;

  _ReelDownload(this.url) {
    _run();
  }

  bool get done => bytes != null;
  bool get failed => error != null;

  /// 0–100, ili null dok veličina nije poznata.
  int? get percent {
    final t = total;
    if (t == null || t <= 0) return null;
    return (received * 100 ~/ t).clamp(0, 100);
  }

  Future<void> _run() async {
    final client = http.Client();
    final sw = Stopwatch()..start();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(url)));
      if (res.statusCode != 200) {
        throw http.ClientException('HTTP ${res.statusCode}', Uri.parse(url));
      }
      total = res.contentLength;
      final builder = BytesBuilder(copy: false);
      var lastPercent = -1;
      await for (final chunk in res.stream) {
        builder.add(chunk);
        received += chunk.length;
        // Obavijest po postotku, ne po chunku (na 35 MB su to tisuće chunkova).
        final p = percent ?? -1;
        if (p != lastPercent) {
          lastPercent = p;
          notifyListeners();
        }
      }
      bytes = builder.takeBytes();
      log(
        'Reels: share download ${bytes!.length} B '
        'in ${sw.elapsedMilliseconds} ms',
      );
    } catch (e) {
      error = e;
      log('Reels: share download failed: $e');
    } finally {
      client.close();
      notifyListeners();
    }
  }
}

_ReelDownload? _current;

_ReelDownload _downloadFor(String url) {
  final c = _current;
  if (c != null && c.url == url && !c.failed) return c;
  return _current = _ReelDownload(url);
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
  late _ReelDownload _download = _downloadFor(_url);
  bool _sharing = false;

  String get _url => widget.reel.render!.url;

  int get _start => widget.reel.startSeconds;
  int get _end => widget.reel.endSec.ceil();

  void _retry() => setState(() => _download = _downloadFor(_url));

  Future<void> _send(BuildContext rowContext) async {
    final bytes = _download.bytes;
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

  Widget _sendRow(AppLocalizations l, bool canShare) {
    final dl = _download;
    final bytes = dl.bytes;
    final percent = dl.percent;
    final total = dl.total;
    return Builder(
      builder: (rowContext) => ListTile(
        enabled: (bytes != null && !_sharing) || dl.failed,
        leading: dl.failed
            ? const Icon(Icons.refresh)
            : bytes == null || _sharing
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: _sharing || percent == null ? null : percent / 100,
                ),
              )
            : Icon(canShare ? Icons.ios_share : Icons.download_outlined),
        title: Text(canShare ? l.reelsSendVideo : l.reelsDownloadVideo),
        subtitle: Text(
          dl.failed
              ? l.reelsShareFailed
              : bytes == null
              ? (percent == null || total == null
                    ? l.reelsPreparing
                    : l.reelsPreparingProgress(
                        percent,
                        EbookService.formatSize(total),
                      ))
              : [
                  'MP4',
                  EbookService.formatSize(bytes.length),
                  if (canShare) l.reelsSendHint,
                ].join(' · '),
        ),
        onTap: dl.failed ? _retry : () => _send(rowContext),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final canShare = canShareFiles();

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
            // Redak sluša preuzimanje izravno — ne ovisi o tome je li future
            // završio dok je list bio otvoren.
            ListenableBuilder(
              listenable: _download,
              builder: (context, _) => _sendRow(l, canShare),
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
