import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:podcast_core/brand/app_brand.dart';
import 'package:podcast_core/brand/domovina_brand.dart';
import 'package:podcast_core/l10n/app_localizations.dart';
import 'package:podcast_core/models/episode_reels.dart';
import 'package:podcast_core/services/data_service.dart';
import 'package:podcast_core/theme/app_theme.dart';
import 'package:podcast_core/widgets/episode_reels.dart';

/// Ugovor `reels.json` (version 1) — producent je `fetch.domovina.tv`, ugovor
/// u `fetch.domovina.tv/docs/2026-10-25-reels-kandidati.md`.
///
/// Fixture je skraćena kopija stvarnog odgovora za `Yoln5fe9RdY`
/// (26.10.2026.): #1 i #2 renderirani, #3 samo kandidat; dodana su dva
/// pokvarena zapisa koja parser mora preskočiti.
const _yoln = '''
{
  "version": 1, "video_id": "Yoln5fe9RdY", "channel": "muzevni_budite",
  "reels": [
    {"rank": 1, "start_sec": 3149.91, "end_sec": 3215.67, "duration_sec": 65.76,
     "title": "Ozdravila na molitvi, a operacija bi koštala 5.000 eura",
     "hook": "Ozdravila je na molitvi. Bi li dala kao kirurgu?",
     "kind": "controversy", "score": 9, "speaker": "Marko Matijašević",
     "speakers": ["Marko Matijašević"],
     "render": {"version": 1, "clip_start_sec": 3149.79, "duration_sec": 66.33,
       "url": "https://cdn.domovina.ai/data/Yoln5fe9RdY/reels/1-882a249e.mp4",
       "storyboard_url": "https://cdn.domovina.ai/data/Yoln5fe9RdY/reels/1-882a249e.storyboard.jpg",
       "poster_url": "https://cdn.domovina.ai/data/Yoln5fe9RdY/reels/1-882a249e.poster.webp"}},
    {"rank": 2, "start_sec": 907.83, "end_sec": 985.41, "title": "Drugi",
     "render": {"url": "https://cdn.domovina.ai/data/Yoln5fe9RdY/reels/2-d979126b.mp4"}},
    {"rank": 3, "start_sec": 1564.77, "end_sec": 1630.71, "title": "Treći",
     "speaker": "  "},
    {"rank": 4, "start_sec": 2000, "end_sec": 1990, "title": "Obrnut raspon"},
    {"rank": 5, "start_sec": 2100, "end_sec": 2160, "title": "Loš render",
     "render": {"url": "/data/x/reels/5.mp4"}},
    {"rank": 6, "start_sec": 2200, "end_sec": 2260}
  ]
}
''';

EpisodeReels _parse(String raw) =>
    EpisodeReels.fromJson(jsonDecode(raw) as Map<String, dynamic>);

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light(),
  locale: const Locale('hr'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  setUp(() => AppBrand.init(domovinaBrand));

  group('parsiranje', () {
    test('poredano po vremenu, pokvareni zapisi preskočeni', () {
      final r = _parse(_yoln);
      // #4 (end <= start) i #6 (bez naslova) ispadaju; #5 ostaje kao trenutak.
      expect(r.reels.map((e) => e.rank), [2, 3, 5, 1]);
    });

    test('samo https render je video', () {
      final r = _parse(_yoln);
      final byRank = {for (final e in r.reels) e.rank: e};
      expect(byRank[1]!.isRendered, isTrue);
      expect(byRank[2]!.isRendered, isTrue);
      expect(byRank[3]!.isRendered, isFalse);
      expect(byRank[5]!.isRendered, isFalse, reason: 'relativna putanja');
    });

    test('poster je poster_url, nikad storyboard', () {
      final byRank = {for (final e in _parse(_yoln).reels) e.rank: e};
      expect(byRank[1]!.render!.posterUrl, endsWith('.poster.webp'));
      expect(byRank[2]!.render!.posterUrl, isNull);
    });

    test('prazan govornik = bez govornika', () {
      final byRank = {for (final e in _parse(_yoln).reels) e.rank: e};
      expect(byRank[3]!.speaker, isNull);
      expect(byRank[1]!.speaker, 'Marko Matijašević');
    });

    test('activeAt: unutar raspona, kraj isključen', () {
      final r = _parse(_yoln);
      expect(r.activeAt(const Duration(seconds: 3150))?.rank, 1);
      expect(r.activeAt(const Duration(milliseconds: 3215670)), isNull);
      expect(r.activeAt(const Duration(seconds: 100)), isNull);
    });
  });

  group('dohvat', () {
    setUp(DataService.resetMemoryForTest);

    Future<EpisodeReels?> load(MockClient client) => http.runWithClient(
      () => DataService(youtubeId: 'Yoln5fe9RdY').loadReels(),
      () => client,
    );

    test('bundle ne navodi reels.json → nema zahtjeva za njim', () async {
      var asked = false;
      final reels = await load(
        MockClient((req) async {
          if (req.url.path.endsWith('/episode.json')) {
            return http.Response(
              jsonEncode({'version': 1, 'files': ['info.json'], 'inline': {}}),
              200,
            );
          }
          if (req.url.path.endsWith('/reels.json')) asked = true;
          return http.Response('', 404);
        }),
      );
      expect(reels, isNull);
      expect(asked, isFalse);
    });

    test('bez bundlea (stara epizoda) → nema zahtjeva za njim', () async {
      var asked = false;
      final reels = await load(
        MockClient((req) async {
          if (req.url.path.endsWith('/reels.json')) asked = true;
          return http.Response('', 404);
        }),
      );
      expect(reels, isNull);
      expect(asked, isFalse);
    });

    test('bundle ga navodi → dohvat i parsiranje', () async {
      final reels = await load(
        MockClient((req) async {
          if (req.url.path.endsWith('/episode.json')) {
            return http.Response(
              jsonEncode({
                'version': 1,
                'files': ['info.json', 'reels.json'],
                'inline': {},
              }),
              200,
            );
          }
          if (req.url.path.endsWith('/reels.json')) {
            return http.Response.bytes(utf8.encode(_yoln), 200);
          }
          return http.Response('', 404);
        }),
      );
      expect(reels?.reels.length, 4);
    });

    test('nečitljiv JSON → null, ne baca', () async {
      final reels = await load(
        MockClient((req) async {
          if (req.url.path.endsWith('/episode.json')) {
            return http.Response(
              jsonEncode({'version': 1, 'files': ['reels.json'], 'inline': {}}),
              200,
            );
          }
          return http.Response('{nije json', 200);
        }),
      );
      expect(reels, isNull);
    });
  });

  group('traka u playeru', () {
    testWidgets('„Pogledaj" samo uz renderirani trenutak', (tester) async {
      final jumped = <int>[];
      final watched = <int>[];
      await tester.pumpWidget(
        _host(
          EpisodeReelsPlayerStrip(
            reels: _parse(_yoln),
            position: Duration.zero,
            onJump: (r) => jumped.add(r.rank),
            onWatch: (r) => watched.add(r.rank),
          ),
        ),
      );
      expect(find.text('Istaknuti trenuci'), findsOneWidget);
      expect(find.text('Pogledaj'), findsNWidgets(2));

      await tester.tap(find.text('Treći'));
      expect(jumped, [3]);

      await tester.tap(find.text('Pogledaj').first);
      expect(watched, [2], reason: 'prvi po vremenu je #2 (15:07)');
    });

    testWidgets('bez podataka nema sekcije', (tester) async {
      await tester.pumpWidget(
        _host(
          const EpisodeReelsPlayerStrip(reels: null, position: Duration.zero),
        ),
      );
      expect(find.text('Istaknuti trenuci'), findsNothing);
    });
  });
}
