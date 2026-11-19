import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../services/open_url.dart';
import '../services/telegram_channels.dart';

/// Gdje gumb stoji, pa koliko je glasan.
enum TelegramJoinStyle {
  /// Zaglavlje stranice kanala: ikona + tekst na širokom ekranu, sama ikona
  /// s tooltipom na uskom (mobitel, gdje je mjesto uz „Prati” tijesno).
  header,

  /// Gumb s tekstom u tijelu stranice (Tier 2 kanal iz kataloga).
  button,

  /// Diskretna poveznica uz poglavlja na stranici epizode.
  episodeLink,
}

/// „Pridruži se na Telegramu”. Ne crta ništa dok se ne zna da kanal postoji,
/// i ništa ako ga nema ili dohvat padne — nikad ne blokira stranicu.
class TelegramJoinButton extends StatefulWidget {
  const TelegramJoinButton({
    super.key,
    required this.uc,
    required this.style,
    this.english,
    this.padding = EdgeInsets.zero,
  });

  /// YouTube UC podcasta; `null` = gumba nema.
  final String? uc;

  final TelegramJoinStyle style;

  /// Željeni jezik kanala. `null` = jezik sučelja.
  final bool? english;

  /// Razmak oko gumba, samo kad je vidljiv (skriven gumb ne ostavlja rupu).
  final EdgeInsetsGeometry padding;

  /// Ispod ove širine zaglavlje pokazuje samo ikonu.
  static const double headerLabelMinWidth = 600;

  @override
  State<TelegramJoinButton> createState() => _TelegramJoinButtonState();
}

class _TelegramJoinButtonState extends State<TelegramJoinButton> {
  TelegramChannels? _channels;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TelegramJoinButton old) {
    super.didUpdateWidget(old);
    if (old.uc != widget.uc) _load();
  }

  void _load() {
    final uc = widget.uc;
    final service = TelegramChannelService.instance;
    _channels = uc == null ? null : service.cached(uc);
    if (uc == null || _channels != null) return;
    unawaited(
      service.lookup(uc).then((r) {
        if (!mounted || widget.uc != uc) return;
        setState(() => _channels = r);
      }),
    );
  }

  void _open(String link) {
    if (kIsWeb) {
      openUrl(link);
    } else {
      // Vanjska aplikacija: t.me je universal/app link pa otvori Telegram,
      // a ne preglednik unutar aplikacije.
      unawaited(
        launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final button = _button(context);
    if (button == null) return const SizedBox.shrink();
    return widget.padding == EdgeInsets.zero
        ? button
        : Padding(padding: widget.padding, child: button);
  }

  Widget? _button(BuildContext context) {
    final channels = _channels;
    if (channels == null) return null;
    final english =
        widget.english ?? Localizations.localeOf(context).languageCode == 'en';
    final pick = channels.linkFor(english: english);
    if (pick == null) return null;

    final l = AppLocalizations.of(context);
    final base = widget.style == TelegramJoinStyle.episodeLink
        ? l.telegramEpisodeLink
        : l.telegramJoin;
    final label = pick.isEnglish == english
        ? base
        : '$base (${pick.isEnglish ? l.telegramInEnglish : l.telegramInCroatian})';
    void onPressed() => _open(pick.link);

    switch (widget.style) {
      case TelegramJoinStyle.header:
        final wide =
            MediaQuery.sizeOf(context).width >=
            TelegramJoinButton.headerLabelMinWidth;
        if (!wide) {
          return IconButton(
            key: const ValueKey('telegram-join'),
            icon: const Icon(Icons.send_outlined),
            tooltip: label,
            onPressed: onPressed,
          );
        }
        return TextButton.icon(
          key: const ValueKey('telegram-join'),
          icon: const Icon(Icons.send_outlined, size: 18),
          label: Text(label),
          onPressed: onPressed,
        );
      case TelegramJoinStyle.button:
        return Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('telegram-join'),
            icon: const Icon(Icons.send_outlined, size: 18),
            label: Text(label),
            onPressed: onPressed,
          ),
        );
      case TelegramJoinStyle.episodeLink:
        final theme = Theme.of(context);
        return Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('telegram-join'),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurfaceVariant,
              textStyle: theme.textTheme.bodySmall,
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.send_outlined, size: 16),
            label: Text(label),
            onPressed: onPressed,
          ),
        );
    }
  }
}
