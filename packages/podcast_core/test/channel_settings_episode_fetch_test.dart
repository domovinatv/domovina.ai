import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:podcast_core/brand/app_brand.dart';
import 'package:podcast_core/brand/domovina_brand.dart';
import 'package:podcast_core/services/channel_feature_gate.dart';
import 'package:podcast_core/services/channel_settings_service.dart';
import 'package:podcast_core/services/channel_visibility.dart';
import 'package:podcast_core/services/data_service.dart';
import 'package:podcast_core/services/ebook_service.dart';
import 'package:podcast_core/services/sponsored_moments_service.dart';
import 'package:podcast_core/widgets/episode_channel_owner.dart';

/// Postavke kanala na ekranu epizode (lanac `postavke-kanala/`, S5): AI
/// ključevi se provode NA MJESTU DOHVATA (matrica §B, odluka 500). Svaki test
/// je par: ključ isključen → datoteka se ne traži; bez retka postavki → kao
/// danas (tvrdi uvjet 4). Ekrani su preteški za widget test (media_kit,
/// Supabase), a sva tri stabla playera i TV čitaju iste `EpisodeData`.
const _uc = 'UCXXhnehl2pss0uYdfLRDtyw';

void main() {
  setUp(() {
    AppBrand.init(domovinaBrand);
    DataService.resetMemoryForTest();
    ChannelVisibility.instance = ChannelVisibility(
      catalog: ChannelSettingsCatalog(baseUrl: ''),
    );
  });
  tearDown(() {
    DataService.resetMemoryForTest();
    ChannelVisibility.instance = ChannelVisibility();
  });

  void off(Iterable<String> keys, {String status = 'active', DateTime? at}) =>
      ChannelVisibility.instance.setForTest({
        _uc: channelOff(keys, status: status, deletedAt: at),
      });

  /// Lažni CDN: `info.json` s UC-om, [bundleFiles] u `episode.json` (ili 404),
  /// sve ostalo 404. Vraća „METODA putanja” svakog zahtjeva.
  Future<List<String>> record(
    Future<void> Function() body, {
    List<String>? bundleFiles,
  }) async {
    final seen = <String>[];
    await http.runWithClient(body, () {
      return MockClient((req) async {
        final path = req.url.path;
        if (path.endsWith('/episode.json')) {
          if (bundleFiles == null) return http.Response('', 404);
          return http.Response(
            jsonEncode({'version': 1, 'files': bundleFiles, 'inline': {}}),
            200,
          );
        }
        seen.add('${req.method} $path');
        if (path.endsWith('/info.json')) {
          return http.Response(jsonEncode({'id': 'x', 'channel_id': _uc}), 200);
        }
        if (path.endsWith('/reels.json')) return http.Response('{}', 200);
        return http.Response('', 404);
      });
    });
    return seen;
  }

  Future<(EpisodeData, List<String>)> loadEpisode(String id) async {
    late EpisodeData data;
    final seen = await record(() async {
      data = await EpisodeData.load(youtubeId: id);
    });
    return (data, seen);
  }

  bool any(List<String> seen, String part) => seen.any((p) => p.contains(part));

  group('EpisodeData.load', () {
    test('bez retka postavki: dohvaća sve kao danas', () async {
      final (data, seen) = await loadEpisode('base0000001');
      expect(data.channelSettings, isNull);
      expect(data.featureOn(EpisodeKey.cdnPlayback), isTrue);
      expect(data.isChannelGone, isFalse);
      for (final f in [
        '/summary.json',
        '/outline.json',
        '/article.json',
        '/article.magisterium',
        '/diarized.srt',
        '/words.json',
        '.en.json',
      ]) {
        expect(any(seen, f), isTrue, reason: f);
      }
      expect(seen.where((p) => p.startsWith('HEAD ')), isNotEmpty);
    });

    test('article_summary: nema sažetka, poglavlja ni članka', () async {
      off([EpisodeKey.articleSummary]);
      final (data, seen) = await loadEpisode('art00000001');
      expect(any(seen, '/info.json'), isTrue);
      for (final f in ['/summary', '/outline.json', '/article.json']) {
        expect(any(seen, f), isFalse, reason: f);
      }
      expect(data.hasAiContent, isFalse);
    });

    test('transcript_subtitles: nema diarized.srt ni words.json', () async {
      off([EpisodeKey.transcriptSubtitles]);
      final (data, seen) = await loadEpisode('srt00000001');
      expect(any(seen, 'diarized'), isFalse);
      expect(any(seen, 'words'), isFalse);
      expect(data.speakerTimeline, isNull);
    });

    test(
      'english_translation: nijedan *.en.* dohvat, nema prekidača',
      () async {
        off([EpisodeKey.englishTranslation]);
        final (data, seen) = await loadEpisode('eng00000001');
        expect(any(seen, '.en.'), isFalse);
        expect(data.hasTranslationEn, isFalse);
      },
    );

    test(
      'magisterium: nijedan Magisterium dohvat + tekst umjesto ocjene',
      () async {
        off([EpisodeKey.magisterium]);
        final (data, seen) = await loadEpisode('mag00000001');
        expect(any(seen, 'magisterium'), isFalse);
        expect(episodeMagisteriumOffByOwner(data), isTrue);
      },
    );

    test('cdn_playback: resolveMedia bez probe-a, samo YouTube', () async {
      off([EpisodeKey.cdnPlayback]);
      final (data, seen) = await loadEpisode('cdn00000001');
      expect(seen.where((p) => p.startsWith('HEAD ')), isEmpty);
      expect(data.hasMedia, isFalse);
      expect(episodeYouTubeOnly(data), isTrue);
    });

    test('povučen kanal: samo info.json, prikaz povučenog sadržaja', () async {
      off(const [], status: 'withdrawn');
      final (data, seen) = await loadEpisode('wd000000001');
      expect(
        seen.every((p) => p.contains('/info.json')),
        isTrue,
        reason: '$seen',
      );
      expect(data.isChannelGone, isTrue);
      expect(data.channelSettings?.isWithdrawn, isTrue);
      expect(episodeSourceUrl(data), contains('youtube.com/watch?v='));
    });

    test('obrisan kanal: datum brisanja stiže do ekrana', () async {
      final at = DateTime.utc(2026, 11, 12);
      off(const [], status: 'deleted', at: at);
      final (data, _) = await loadEpisode('del00000001');
      expect(data.isChannelGone, isTrue);
      expect(data.channelSettings?.isDeleted, isTrue);
      expect(data.channelSettings?.deletedAt, at);
    });

    test('kanal izvan mape (drugi UC ograničen): kao danas', () async {
      ChannelVisibility.instance.setForTest({
        'UCaaaaaaaaaaaaaaaaaaaaaa': channelOff([EpisodeKey.articleSummary]),
      });
      final (data, seen) = await loadEpisode('oth00000001');
      expect(any(seen, '/article.json'), isTrue);
      expect(data.channelSettings, isNull);
    });
  });

  group('pojedinačni dohvati', () {
    Future<List<String>> afterInfo(
      String id,
      Future<void> Function(DataService svc) body, {
      List<String>? bundleFiles,
    }) {
      final svc = DataService(youtubeId: id);
      return record(() async {
        await svc.loadInfo();
        await body(svc);
      }, bundleFiles: bundleFiles);
    }

    for (final isOff in [false, true]) {
      final tag = isOff ? 'isključen' : 'bez postavki';

      test('highlights_reels $tag', () async {
        if (isOff) off([EpisodeKey.highlightsReels]);
        final seen = await afterInfo(
          'reel${isOff ? 1 : 0}0000001',
          (svc) => svc.loadReels(),
          bundleFiles: const ['info.json', 'reels.json'],
        );
        expect(any(seen, '/reels.json'), !isOff);
      });

      test('sponsors_in_video $tag', () async {
        if (isOff) off([EpisodeKey.sponsorsInVideo]);
        final seen = await afterInfo(
          'spon${isOff ? 1 : 0}0000001',
          (svc) => svc.loadSponsorsInVideo(),
        );
        expect(any(seen, 'sponsors_in_video'), !isOff);
      });

      test('ebook $tag: probe ${isOff ? 'nije' : 'je'} pozvan', () async {
        if (isOff) off([EpisodeKey.ebook]);
        final id = 'book${isOff ? 1 : 0}0000001';
        late EbookAvailability got;
        final seen = await afterInfo(id, (_) async {
          got = await EbookService.probe(id);
        });
        expect(any(seen, '.epub'), !isOff);
        if (isOff) expect(got.any, isFalse);
      });

      test('paid_sponsor_moments $tag', () async {
        if (isOff) off([EpisodeKey.paidSponsorMoments]);
        final id = 'paid${isOff ? 1 : 0}0000001';
        var asked = false;
        final svc = SponsoredMomentsService(
          client: sb.SupabaseClient(
            'http://localhost',
            'anon',
            httpClient: MockClient((req) async {
              if (req.url.path.contains('public_live_moments')) asked = true;
              return http.Response(
                '[]',
                200,
                headers: {'content-type': 'application/json'},
              );
            }),
            authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
          ),
        );
        await afterInfo(id, (_) async {
          expect(await svc.loadLive(id), isNull);
        });
        expect(asked, !isOff);
      });
    }

    test(
      'epizoda čiji info.json nije tražen: fail-open, bez zahtjeva katalogu',
      () async {
        off([EpisodeKey.ebook]);
        expect(
          await ChannelFeatureGate.isEnabled('neznan00001', EpisodeKey.ebook),
          isTrue,
        );
      },
    );
  });

  test('EpisodeKey imena postoje u kChannelSettingDefs', () {
    final known = {for (final d in kChannelSettingDefs) d.key};
    for (final k in EpisodeKey.all) {
      expect(known, contains(k), reason: k);
    }
  });
}
