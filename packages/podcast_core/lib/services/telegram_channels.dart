// Telegram kanal podcasta: svaka epizoda je jedna objava, a ispod nje su u
// komentarima poglavlja kronološkim redom, svako s linkom na svoj trenutak.
//
// Izvor (javan, CORS *, cache 5 min):
//   GET https://telegram.domovina.ai/public/podcasts/<UC>
//   → 200 {"title", "link", "en": {"title", "link"} | null}
//   → 404 kad podcast nema nijedan kanal
// Gornja razina je hrvatski kanal, `en` engleski par; svaki je zaseban
// pristanak podcasta, pa može postojati samo jedan od dva.
//
// `title` se namjerno NE čita: nosi emoji zastave, a sučelje je bez emojija
// (test/no_emoji_in_strings_test.dart). Tekst gumba je l10n string.
//
// Plan i ugovor: docs/plans/2026-11-19-telegram-kanal-po-podcastu.md §4.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../brand/app_brand.dart';
import '../src/log.dart' show log;

/// Jedan Telegram kanal (invite link `https://t.me/+…`).
class TelegramChannelLink {
  const TelegramChannelLink({required this.link, required this.isEnglish});

  final String link;

  /// `true` = engleski par, `false` = hrvatski kanal.
  final bool isEnglish;
}

/// Kanali jednog podcasta. Barem jedan od dva postoji.
class TelegramChannels {
  const TelegramChannels({this.hr, this.en});

  final String? hr;
  final String? en;

  bool get isEmpty => hr == null && en == null;

  /// Kanal na željenom jeziku; kad njega nema, drugi jezik (pozivatelj tada
  /// vidi `isEnglish != english` i dopiše oznaku jezika).
  TelegramChannelLink? linkFor({required bool english}) {
    final preferred = english ? en : hr;
    if (preferred != null) {
      return TelegramChannelLink(link: preferred, isEnglish: english);
    }
    final other = english ? hr : en;
    if (other != null) {
      return TelegramChannelLink(link: other, isEnglish: !english);
    }
    return null;
  }

  /// `null` kad odgovor nije čitljiv ili nema nijedan valjan link.
  static TelegramChannels? tryParse(Object? json) {
    if (json is! Map) return null;
    String? valid(Object? v) =>
        v is String && v.startsWith('https://t.me/') ? v : null;
    final enObj = json['en'];
    final channels = TelegramChannels(
      hr: valid(json['link']),
      en: enObj is Map ? valid(enObj['link']) : null,
    );
    return channels.isEmpty ? null : channels;
  }
}

/// Dohvat po YouTube UC-u. Nikad ne baca: 404, greška, timeout, CORS i
/// nečitljiv odgovor znače „nema kanala” i gumba nema.
///
/// Šav za testove: [instance] se smije zamijeniti instancom s vlastitim
/// [http.Client] (isti obrazac kao `CatalogClient.instance`).
class TelegramChannelService {
  TelegramChannelService({
    http.Client? client,
    this.baseUrl = 'https://telegram.domovina.ai/public/podcasts',
    this.timeout = const Duration(seconds: 4),
  }) : _client = client;

  static TelegramChannelService instance = TelegramChannelService();

  final http.Client? _client;
  final String baseUrl;
  final Duration timeout;

  /// Ishod po UC-u za život sesije (i „nema" — 5 min cache na serveru je
  /// ionako duži od tipičnog zadržavanja na stranici).
  final Map<String, TelegramChannels?> _cache = {};
  final Map<String, Future<TelegramChannels?>> _inFlight = {};

  bool get enabled => AppBrand.config.flags.telegramChannels;

  static final RegExp _ucPattern = RegExp(r'^UC[A-Za-z0-9_-]{22}$');

  /// Sinkroni pogled u keš — za prvi `build()` bez treptaja.
  TelegramChannels? cached(String uc) => _cache[uc];

  Future<TelegramChannels?> lookup(String? uc) {
    if (!enabled || uc == null || !_ucPattern.hasMatch(uc)) {
      return Future.value(null);
    }
    if (_cache.containsKey(uc)) return Future.value(_cache[uc]);
    final running = _inFlight[uc];
    if (running != null) return running;
    final future = _fetch(uc).then((r) {
      _cache[uc] = r;
      _inFlight.remove(uc);
      return r;
    });
    _inFlight[uc] = future;
    return future;
  }

  Future<TelegramChannels?> _fetch(String uc) async {
    final uri = Uri.parse('$baseUrl/${Uri.encodeComponent(uc)}');
    try {
      final c = _client;
      final r = await (c != null ? c.get(uri) : http.get(uri)).timeout(timeout);
      if (r.statusCode != 200) {
        if (r.statusCode != 404) log('Telegram($uc): HTTP ${r.statusCode}');
        return null;
      }
      final parsed = TelegramChannels.tryParse(
        jsonDecode(utf8.decode(r.bodyBytes)),
      );
      log(
        'Telegram($uc): ${parsed == null ? 'nečitljivo' : 'hr=${parsed.hr != null} en=${parsed.en != null}'}',
      );
      return parsed;
    } catch (e) {
      log('Telegram($uc): $e');
      return null;
    }
  }
}
