import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../l10n/app_localizations.dart';
import '../router/nav.dart' show closeOnRouteChange;
import '../services/ebook_service.dart';
import '../services/file_share.dart';
import '../theme/app_theme.dart';

/// Površine za EPUB e-knjigu epizode: ikona u app baru, kartica u sadržaju i
/// zajednički bottom sheet iz kojeg se knjiga dijeli ili preuzima.
///
/// Knjigu radi pipeline (KORAK 9.8) i ona na CDN-u stoji kao `book.epub` /
/// `book.en.epub`. Postojanje MJERI [EbookService] — ekran epizode probe-a
/// jednom i rezultat prosljeđuje ovim widgetima; nijedan od njih se ne prikazuje
/// dok se ne zna da knjiga doista postoji.

/// Tekstovi e-knjige na jeziku SADRŽAJA epizode, ne sučelja. `/v/<id>/en`
/// otvoren uz hrvatsko sučelje nudio je „Englesko izdanje” s hrvatskim
/// naslovom kartice, opisom i „Kopiraj poveznicu na knjigu”. Knjiga je dio
/// sadržaja (izdanje bira `preferEn`), pa i riječi oko nje prate taj jezik.
AppLocalizations ebookStrings(bool preferEn) =>
    lookupAppLocalizations(Locale(preferEn ? 'en' : 'hr'));

/// Ikona u app baru epizode. Vraća prazan prostor dok se ne zna da knjiga
/// postoji — nikad ne nudi akciju koja bi završila na 404.
class EbookAction extends StatelessWidget {
  final EbookAvailability availability;
  final String title;
  final bool preferEn;
  final String? episodeUrl;

  const EbookAction({
    super.key,
    required this.availability,
    required this.title,
    required this.preferEn,
    this.episodeUrl,
  });

  @override
  Widget build(BuildContext context) {
    if (!availability.any) return const SizedBox.shrink();
    return IconButton(
      // `auto_stories` (otvorena knjiga), NE `menu_book` — tu ikonu u
      // jednostavnom prikazu već nosi tab Magisteriuma.
      icon: const Icon(Icons.auto_stories_outlined),
      tooltip: ebookStrings(preferEn).ebookTooltip,
      onPressed: () => showEbookSheet(
        context,
        availability: availability,
        title: title,
        preferEn: preferEn,
        episodeUrl: episodeUrl,
      ),
    );
  }
}

/// Kartica u tijelu epizode — jedina površina na kojoj se e-knjiga sama
/// objasni. Ikona u app baru je prečac za onoga tko već zna da knjiga postoji.
class EbookCard extends StatelessWidget {
  final EbookAvailability availability;
  final String title;
  final bool preferEn;
  final String? episodeUrl;

  const EbookCard({
    super.key,
    required this.availability,
    required this.title,
    required this.preferEn,
    this.episodeUrl,
  });

  @override
  Widget build(BuildContext context) {
    if (!availability.any) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l = ebookStrings(preferEn);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.4,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.fromBorderSide(AppTheme.brandRim(theme.brightness)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _BookBadge(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.ebookCardTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l.ebookCardBody,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      icon: Icon(
                        canShareFiles()
                            ? Icons.ios_share
                            : Icons.download_outlined,
                        size: 18,
                      ),
                      label: Text(l.ebookCardAction),
                      onPressed: () => showEbookSheet(
                        context,
                        availability: availability,
                        title: title,
                        preferEn: preferEn,
                        episodeUrl: episodeUrl,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookBadge extends StatelessWidget {
  const _BookBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        // Brand-fill je uvijek croBlue + rim, nikad cs.primary (vidi CLAUDE.md).
        color: AppTheme.brandPrimary,
        borderRadius: BorderRadius.circular(6),
        border: Border.fromBorderSide(AppTheme.brandRim(theme.brightness)),
      ),
      child: const Center(
        child: Icon(Icons.menu_book, color: Colors.white, size: 16),
      ),
    );
  }
}

Future<void> showEbookSheet(
  BuildContext context, {
  required EbookAvailability availability,
  required String title,
  required bool preferEn,
  String? episodeUrl,
}) {
  // Browserov Back mijenja rutu ISPOD sheeta (modal nema history entry) —
  // vidi `closeOnRouteChange` i pravilo u CLAUDE.md.
  final navigator = Navigator.of(context);
  late final VoidCallback unsubscribe;
  unsubscribe = closeOnRouteChange(context, () {
    if (navigator.canPop()) navigator.pop();
  });
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _EbookSheet(
      availability: availability,
      title: title,
      preferEn: preferEn,
      episodeUrl: episodeUrl,
    ),
  ).whenComplete(unsubscribe);
}

class _EbookSheet extends StatefulWidget {
  final EbookAvailability availability;
  final String title;
  final bool preferEn;
  final String? episodeUrl;

  const _EbookSheet({
    required this.availability,
    required this.title,
    required this.preferEn,
    this.episodeUrl,
  });

  @override
  State<_EbookSheet> createState() => _EbookSheetState();
}

class _EbookSheetState extends State<_EbookSheet> {
  /// URL izdanja koje se upravo preuzima (null = ništa u tijeku).
  String? _busyUrl;

  @override
  void initState() {
    super.initState();
    // Predpreuzimanje čim se sheet otvori: `navigator.share` mora pasti unutar
    // korisnikove geste, a 2,5 MB usred te geste na iOS-u zna isteći. Kad
    // korisnik tapne redak, bajtovi su obično već tu i share ide odmah.
    final preferred = widget.availability.preferred(wantEn: widget.preferEn);
    // Greška se ovdje namjerno guta: pravi pokušaj je korisnikov tap na redak,
    // koji poruku i prikaže.
    if (preferred != null) EbookService.download(preferred.url).ignore();
  }

  Future<void> _take(BuildContext rowContext, EbookEdition edition) async {
    if (_busyUrl != null) return;
    final l = ebookStrings(widget.preferEn);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final origin = _rectOf(rowContext);
    final filename = EbookService.fileName(
      title: widget.title,
      isEn: edition.isEn,
    );

    setState(() => _busyUrl = edition.url);
    try {
      final bytes = await EbookService.download(edition.url);
      final outcome = await shareFile(
        bytes: bytes,
        filename: filename,
        mimeType: EbookService.mimeType,
        text: widget.episodeUrl,
        subject: widget.title,
        sharePositionOrigin: origin,
      );
      if (!mounted) return;
      setState(() => _busyUrl = null);
      switch (outcome) {
        case FileShareOutcome.shared:
          navigator.pop();
        case FileShareOutcome.downloaded:
          navigator.pop();
          messenger.showSnackBar(
            SnackBar(
              content: Text(l.ebookDownloaded(filename)),
              duration: const Duration(seconds: 3),
            ),
          );
        case FileShareOutcome.dismissed:
          break;
        case FileShareOutcome.failed:
          messenger.showSnackBar(SnackBar(content: Text(l.ebookFailed)));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _busyUrl = null);
      messenger.showSnackBar(SnackBar(content: Text(l.ebookFailed)));
    }
  }

  /// Pravokutnik retka u globalnim koordinatama — iPad share popover bez sidra
  /// ne zna gdje se iscrtati.
  static Rect? _rectOf(BuildContext context) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = ebookStrings(widget.preferEn);
    final canShare = canShareFiles();

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                const _BookBadge(),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.ebookSheetTitle.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        widget.title,
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
          for (final edition in widget.availability.editions)
            Builder(
              builder: (rowContext) {
                final busy = _busyUrl == edition.url;
                final size = edition.bytes;
                return ListTile(
                  enabled: _busyUrl == null,
                  leading: busy
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          canShare ? Icons.ios_share : Icons.download_outlined,
                        ),
                  title: Text(
                    edition.isEn ? l.ebookEditionEn : l.ebookEditionHr,
                  ),
                  subtitle: Text(
                    busy
                        ? l.ebookPreparing
                        : [
                            'EPUB',
                            if (size != null) EbookService.formatSize(size),
                            canShare ? l.ebookShareHint : l.ebookDownloadHint,
                          ].join(' · '),
                  ),
                  onTap: () => _take(rowContext, edition),
                );
              },
            ),
          ListTile(
            leading: const Icon(Icons.link),
            title: Text(l.ebookCopyLink),
            onTap: () {
              final edition =
                  widget.availability.preferred(wantEn: widget.preferEn);
              if (edition == null) return;
              final messenger = ScaffoldMessenger.of(context);
              Clipboard.setData(ClipboardData(text: edition.url));
              Navigator.of(context).pop();
              messenger.showSnackBar(
                SnackBar(
                  content: Text(l.ebookLinkCopied),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Text(
              l.ebookRights,
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
