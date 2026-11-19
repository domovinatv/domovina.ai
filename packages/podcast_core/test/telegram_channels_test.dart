import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:podcast_core/l10n/app_localizations.dart';
import 'package:podcast_core/services/telegram_channels.dart';
import 'package:podcast_core/widgets/telegram_join_button.dart';

const _uc = 'UCXXhnehl2pss0uYdfLRDtyw';
const _hr = 'https://t.me/+A91C5KOxeFBhNjA0';
const _en = 'https://t.me/+3ePgcPaULbhjOTJk';

String _body({String? hr = _hr, String? en = _en}) => jsonEncode({
  'title': hr == null ? null : 'DOMOVINA 🇭🇷',
  'link': hr,
  'en': en == null ? null : {'title': 'DOMOVINA 🇬🇧', 'link': en},
});

TelegramChannelService _service(
  MockClientHandler handler, {
  List<http.Request>? requests,
}) => TelegramChannelService(
  baseUrl: 'https://tg.test/public/podcasts',
  client: MockClient((req) {
    requests?.add(req);
    return handler(req);
  }),
);

void main() {
  group('TelegramChannelService', () {
    test('200 s oba jezika; URL je /public/podcasts/<UC>', () async {
      final requests = <http.Request>[];
      final s = _service(
        (_) async => http.Response.bytes(utf8.encode(_body()), 200),
        requests: requests,
      );
      final r = await s.lookup(_uc);
      expect(r!.hr, _hr);
      expect(r.en, _en);
      expect(
        requests.single.url.toString(),
        'https://tg.test/public/podcasts/$_uc',
      );
    });

    test('samo engleski par', () async {
      final s = _service(
        (_) async => http.Response.bytes(utf8.encode(_body(hr: null)), 200),
      );
      final r = await s.lookup(_uc);
      expect(r!.hr, isNull);
      expect(r.en, _en);
    });

    test('404 → nema kanala', () async {
      final s = _service((_) async => http.Response('not found', 404));
      expect(await s.lookup(_uc), isNull);
    });

    test('greška mreže → nema kanala, ne baca', () async {
      final s = _service((_) async => throw http.ClientException('offline'));
      expect(await s.lookup(_uc), isNull);
    });

    test('nečitljiv JSON i link koji nije t.me → nema kanala', () async {
      final s1 = _service((_) async => http.Response('<html>', 200));
      expect(await s1.lookup(_uc), isNull);
      final s2 = _service(
        (_) async => http.Response(
          jsonEncode({'link': 'https://evil.example/x', 'en': null}),
          200,
        ),
      );
      expect(await s2.lookup(_uc), isNull);
    });

    test('neispravan UC i null → bez zahtjeva', () async {
      final requests = <http.Request>[];
      final s = _service(
        (_) async => http.Response.bytes(utf8.encode(_body()), 200),
        requests: requests,
      );
      expect(await s.lookup(null), isNull);
      expect(await s.lookup('domovina_tv'), isNull);
      expect(requests, isEmpty);
    });

    test('cache po UC-u i dedup istodobnih poziva', () async {
      final requests = <http.Request>[];
      final s = _service(
        (_) async => http.Response.bytes(utf8.encode(_body()), 200),
        requests: requests,
      );
      final both = await Future.wait([s.lookup(_uc), s.lookup(_uc)]);
      expect(both.every((r) => r?.hr == _hr), isTrue);
      await s.lookup(_uc);
      expect(requests, hasLength(1));
      expect(s.cached(_uc)?.en, _en);
    });
  });

  group('TelegramChannels.linkFor', () {
    const both = TelegramChannels(hr: _hr, en: _en);
    test('željeni jezik', () {
      expect(both.linkFor(english: false)!.link, _hr);
      final en = both.linkFor(english: true)!;
      expect(en.link, _en);
      expect(en.isEnglish, isTrue);
    });
    test('pad na drugi jezik s oznakom', () {
      const onlyEn = TelegramChannels(en: _en);
      final p = onlyEn.linkFor(english: false)!;
      expect(p.link, _en);
      expect(p.isEnglish, isTrue);
      const onlyHr = TelegramChannels(hr: _hr);
      expect(onlyHr.linkFor(english: true)!.isEnglish, isFalse);
    });
  });

  group('TelegramJoinButton', () {
    late TelegramChannelService original;
    setUp(() => original = TelegramChannelService.instance);
    tearDown(() => TelegramChannelService.instance = original);

    Widget app(Widget child, {Locale locale = const Locale('hr')}) =>
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        );

    testWidgets('bez kanala (404) gumba nema', (tester) async {
      TelegramChannelService.instance = _service(
        (_) async => http.Response('', 404),
      );
      await tester.pumpWidget(
        app(const TelegramJoinButton(uc: _uc, style: TelegramJoinStyle.button)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('telegram-join')), findsNothing);
    });

    testWidgets('s kanalom gumb postoji, tekst na hrvatskom', (tester) async {
      TelegramChannelService.instance = _service(
        (_) async => http.Response.bytes(utf8.encode(_body()), 200),
      );
      await tester.pumpWidget(
        app(const TelegramJoinButton(uc: _uc, style: TelegramJoinStyle.button)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('telegram-join')), findsOneWidget);
      expect(find.text('Pridruži se na Telegramu'), findsOneWidget);
    });

    testWidgets('samo EN kanal uz HR sučelje → oznaka jezika', (tester) async {
      TelegramChannelService.instance = _service(
        (_) async => http.Response.bytes(utf8.encode(_body(hr: null)), 200),
      );
      await tester.pumpWidget(
        app(
          const TelegramJoinButton(
            uc: _uc,
            style: TelegramJoinStyle.episodeLink,
            english: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Poglavlja i rasprava na Telegramu (na engleskom)'),
        findsOneWidget,
      );
    });

    testWidgets('zaglavlje na uskom ekranu = ikona s tooltipom', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      TelegramChannelService.instance = _service(
        (_) async => http.Response.bytes(utf8.encode(_body()), 200),
      );
      await tester.pumpWidget(
        app(
          const TelegramJoinButton(uc: _uc, style: TelegramJoinStyle.header),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(IconButton), findsOneWidget);
      expect(find.byTooltip('Join on Telegram'), findsOneWidget);
    });
  });
}
