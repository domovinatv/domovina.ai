import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:podcast_core/models/episode_bundle.dart';
import 'package:podcast_core/services/data_service.dart';

/// Ugovor za `data/<id>/episode.json` ([EpisodeBundle]): s njim ekran epizode
/// ne traži datoteke kojih nema i ne probe-a mediju. Vidi
/// `docs/2026-10-08-brzina-ucitavanja-naslovnice.md` §8.
void main() {
  setUp(DataService.resetMemoryForTest);

  const id = 'abc123';

  String bundle({List<String> extraFiles = const []}) => jsonEncode({
        'version': 1,
        'generated_at': '2026-10-10T02:00:00Z',
        'files': [
          'info.json',
          'summary.json',
          'article.json',
          'diarized.srt',
          'audio.mp3',
          ...extraFiles,
        ],
        'inline': {
          'info.json': {'id': id, 'title': 'Naslov', 'duration': 60},
          'summary.json': {
            'summary': {'title_hr': 'Naslov HR'},
          },
          'article.json': {'iterations': []},
        },
      });

  test('s bundleom se traže samo datoteke s popisa, bez probe-a', () async {
    final log = <String>[];
    final data = await http.runWithClient(
      () => EpisodeData.load(youtubeId: id),
      () => MockClient((req) async {
        log.add('${req.method} ${req.url.path}');
        if (req.url.path.endsWith('/episode.json')) {
          return http.Response(bundle(), 200);
        }
        if (req.url.path.endsWith('/diarized.srt')) {
          return http.Response(
              '1\n00:00:01,000 --> 00:00:02,000\n[SPEAKER_00] Dobar dan\n',
              200);
        }
        return http.Response('Not Found', 404);
      }),
    );

    expect(data.info.title, 'Naslov');
    expect(data.article, isNotNull);
    expect(data.outline, isNull);
    expect(data.isAudioOnly, isTrue);
    expect(data.speakerTimeline, isNotNull);
    expect(log, [
      'GET /data/$id/episode.json',
      'GET /data/$id/diarized.srt',
    ]);
  });

  // docs/plans/2026-10-29-titlovi-na-dva-jezika.md: titl prati jezik sadržaja,
  // `diarized.<lang>.srt` uz pad na zadani `diarized.srt`.
  group('titl na jeziku sadržaja', () {
    Future<EpisodeData> load(List<String> extra) => http.runWithClient(
          () => EpisodeData.load(youtubeId: id),
          () => MockClient((req) async {
            final p = req.url.path;
            if (p.endsWith('/episode.json')) {
              return http.Response(bundle(extraFiles: extra), 200);
            }
            if (p.endsWith('/diarized.srt')) {
              return http.Response(
                  '1\n00:00:01,000 --> 00:00:02,000\n[SPEAKER_00] Dobar dan\n',
                  200);
            }
            if (p.endsWith('/diarized.en.srt')) {
              return http.Response(
                  '1\n00:00:01,000 --> 00:00:02,000\n[SPEAKER_00] Good day\n',
                  200);
            }
            if (p.endsWith('/words.en.json')) {
              return http.Response(
                  jsonEncode({
                    'v': 1,
                    'cues': [
                      {'s': 1000, 'e': 2000, 'w': [1000, 1400, 1500, 2000]},
                    ],
                  }),
                  200);
            }
            return http.Response('Not Found', 404);
          }),
        );

    test('EN korisnik dobiva diarized.en.srt s words.en.json', () async {
      final data = await load(['diarized.en.srt', 'words.en.json']);
      final en = data.speakerTimelineFor(true)!;
      expect(en.segments.single.text, 'Good day');
      expect(en.hasWordTimings, isTrue);
      expect(data.speakerTimelineFor(false)!.segments.single.text, 'Dobar dan');
    });

    test('bez diarized.en.srt EN korisnik dobiva zadani titl', () async {
      final data = await load(const []);
      expect(data.speakerTimelineEn, isNull);
      expect(data.speakerTimelineFor(true)!.segments.single.text, 'Dobar dan');
    });
  });

  test('bez bundlea stari put (svaka datoteka + probe)', () async {
    var requests = 0;
    await http.runWithClient(
      () => EpisodeData.load(youtubeId: id),
      () => MockClient((req) async {
        requests++;
        if (req.url.path.endsWith('/info.json')) {
          return http.Response('{"id":"$id","title":"t"}', 200);
        }
        return http.Response('Not Found', 404);
      }),
    );
    expect(requests, greaterThan(20));
  });

  group('video iz bundlea', () {
    Future<EpisodeData> loadWith(List<String> files) => http.runWithClient(
          () => EpisodeData.load(youtubeId: id),
          () => MockClient((req) async {
            if (req.url.path.endsWith('/episode.json')) {
              final b = jsonDecode(bundle()) as Map<String, dynamic>;
              b['files'] = ['info.json', 'summary.json', 'article.json', ...files];
              return http.Response(jsonEncode(b), 200);
            }
            return http.Response('Not Found', 404);
          }),
        );

    test('fmp4 ima prednost pred video_h264.mp4', () async {
      final data = await loadWith(['video_h264.mp4', 'video_h264_fmp4.mp4']);
      expect(data.videoUri, contains('/data/$id/video_h264_fmp4.mp4?g='));
      expect(data.isAudioOnly, isFalse);
    });

    group('fragmentedVideoUrl po platformi', () {
      const both = EpisodeBundle(files: {
        'video_h264.mp4',
        'video_h264_fmp4.mp4',
        'video_h264_fmp4_web.mp4',
      }, inline: {});
      const onlyInterleaved = EpisodeBundle(
          files: {'video_h264.mp4', 'video_h264_fmp4.mp4'}, inline: {});

      test('native uzima interleavani fmp4', () {
        expect(fragmentedVideoUrl(both, id, web: false, webKit: false),
            contains('/video_h264_fmp4.mp4?g='));
      });

      test('Chromium uzima samo web fmp4', () {
        expect(fragmentedVideoUrl(both, id, web: true, webKit: false),
            contains('/video_h264_fmp4_web.mp4?g='));
      });

      // Interleavani fmp4 ruši Chromium nakon niza skokova
      // (docs/2026-10-28-fmp4-interleave-chromium-seek.md).
      test('Chromium NIKAD ne uzima interleavani fmp4', () {
        expect(
            fragmentedVideoUrl(onlyInterleaved, id, web: true, webKit: false),
            isNull);
      });

      test('WebKit ne uzima nijedan fmp4', () {
        expect(fragmentedVideoUrl(both, id, web: true, webKit: true), isNull);
      });
    });

    test('bez fmp4 ostaje video_h264.mp4', () async {
      final data = await loadWith(['video_h264.mp4', 'audio.mp3']);
      expect(data.videoUri, endsWith('/data/$id/video_h264.mp4'));
    });
  });

  test('nepoznata verzija se ignorira', () {
    expect(EpisodeBundle.tryParse('{"version":2,"files":[]}'), isNull);
    expect(EpisodeBundle.tryParse('nije json'), isNull);
  });

  test('predučitavanje s bundleom je jedan zahtjev', () async {
    final log = <String>[];
    await http.runWithClient(
      () => const DataService(youtubeId: id).prefetchFirstPaint(),
      () => MockClient((req) async {
        log.add(req.url.path);
        return http.Response(bundle(), 200);
      }),
    );
    expect(log, ['/data/$id/episode.json']);
  });

  test('članak se vraća prije titlova, titlovi stižu kroz onTimeline',
      () async {
    EpisodeData? full;
    final first = await http.runWithClient(
      () => EpisodeData.loadWithProgress(
        youtubeId: id,
        onProgress: (_, _, _) {},
        onTimeline: (d) => full = d,
      ),
      () => MockClient((req) async {
        if (req.url.path.endsWith('/episode.json')) {
          return http.Response(bundle(), 200);
        }
        if (req.url.path.endsWith('/diarized.srt')) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return http.Response(
              '1\n00:00:01,000 --> 00:00:02,000\n[SPEAKER_00] Dobar dan\n',
              200);
        }
        return http.Response('Not Found', 404);
      }),
    );
    expect(first.article, isNotNull);
    expect(first.speakerTimeline, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(full?.speakerTimeline, isNotNull);
  });
}
