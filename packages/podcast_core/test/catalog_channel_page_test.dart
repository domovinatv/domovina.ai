/// Ugovor S10 (Flutter): parseri popisa kanala, zaglavlja kanala i epizoda
/// kanala, te `CatalogClient.directory` / `channel` / `channelEpisodes`.
/// Fixtureovi su skraćeni stvarni odgovori produkcije od 6. 11. 2026.
/// (`curl -s "https://domovina.ai/api/katalog/v1/directory?limit=3"` itd.).
/// Bez mreže: `CdnJsonCache` s `MockClient`om.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:podcast_core/services/catalog_client.dart';
import 'package:podcast_core/services/cdn_json_cache.dart';
import 'package:podcast_core/services/cdn_store.dart';

const _base = 'https://domovina.ai/api/katalog/v1';

const _directory =
    '{"version":"1","catalog":"8","items":['
    '{"slug":"tribina","name":"Tribina","tier":2,"lang":null,"avatar":null,'
    '"youtube_channel_id":"UCjTiZ9ebMJumhPMsciuevxg","processed_count":6,'
    '"latest_published_date":"2026-11-05","unregistered":false},'
    '{"slug":"sbs-croatian","name":"SBS Croatian","tier":2,"lang":null,'
    '"avatar":null,"youtube_channel_id":"UCmOZTyhea2luossld9Qpu9Q",'
    '"processed_count":3,"latest_published_date":"2026-11-05",'
    '"unregistered":false},'
    '{"slug":"radio_mreznica","name":"Radio Mrežnica","tier":1,"lang":null,'
    '"avatar":"https://cdn.domovina.ai/channels/images/radio_mreznica/avatar_square.jpg",'
    '"youtube_channel_id":"UCI6pKljX81g3vuK2SYj62rQ","processed_count":225,'
    '"latest_published_date":"2026-11-05","unregistered":false}],'
    '"next":"WyIyMDI2LTExLTA1IiwicmFkaW9fbXJlem5pY2EiXQ",'
    '"meta":{"rows_read":7}}';

const _unregistered =
    '{"version":"1","catalog":"8","items":['
    '{"slug":"yt-UCfT_PJPR2vuqqKcCgEf3scA","name":"Capturing Catholicism",'
    '"tier":2,"lang":null,"avatar":null,'
    '"youtube_channel_id":"UCfT_PJPR2vuqqKcCgEf3scA","processed_count":1,'
    '"latest_published_date":"2026-09-17","unregistered":true}],'
    '"next":null,"meta":{"rows_read":2}}';

const _channel =
    '{"version":"1","catalog":"8","item":{"slug":"tribina","name":"Tribina",'
    '"tier":2,"lang":null,"avatar":null,'
    '"youtube_channel_id":"UCjTiZ9ebMJumhPMsciuevxg","processed_count":6,'
    '"latest_published_date":"2026-11-05","unregistered":false},'
    '"meta":{"rows_read":4}}';

const _episodes =
    '{"version":"1","catalog":"8","items":['
    '{"id":"_YOkTkbrh_k","title":"Novi početci | Tribina NBA",'
    '"title_hr":"Novi početci | Tribina NBA","date":"2026-11-05",'
    '"duration_seconds":5715,"magisterium_score":null,"p":511,"tier":2,'
    '"lang":"hr","variant_of":null,'
    '"channel":{"slug":"tribina","name":"Tribina","tier":2}},'
    '{"id":"BqJ67OO-FVA","title":"Clutch gen, ozljede i tradeovi | Tribina NFL",'
    '"title_hr":"Clutch gen, ozljede i tradeovi | Tribina NFL",'
    '"date":"2026-11-04","duration_seconds":6357,"magisterium_score":null,'
    '"p":511,"tier":2,"lang":"hr","variant_of":null,'
    '"channel":{"slug":"tribina","name":"Tribina","tier":2}}],'
    '"next":"WyIyMDI2LTExLTA0IiwiQnFKNjdPTy1GVkEiXQ","meta":{"rows_read":10}}';

const _notFound = '{"ok":false,"error":"channel_not_found"}';

class _MemStore implements CdnStore {
  final Map<String, StoredEntry> data = {};
  @override
  Future<StoredEntry?> get(StoreBucket b, String url) async =>
      data['${b.name}|$url'];
  @override
  Future<void> put(StoreBucket b, String url, StoredEntry e) async =>
      data['${b.name}|$url'] = e;
  @override
  Future<void> clear() async => data.clear();
  @override
  bool supports(StoreBucket b) => true;
}

void main() {
  group('CatalogDirectoryPage.tryParse', () {
    test('stvarni odgovor: oba tiera, kursor, avatar i null polja', () {
      final page = CatalogDirectoryPage.tryParse(_directory)!;
      expect(page.items.map((c) => c.slug), [
        'tribina',
        'sbs-croatian',
        'radio_mreznica',
      ]);
      expect(page.hasMore, isTrue);
      expect(page.catalog, '8');
      final tribina = page.items.first;
      expect(tribina.tier, 2);
      expect(tribina.followed, isFalse);
      expect(tribina.avatar, isNull);
      expect(tribina.lang, isNull);
      expect(tribina.processedCount, 6);
      expect(tribina.latestPublishedDate, '2026-11-05');
      final mreznica = page.items.last;
      expect(mreznica.followed, isTrue);
      expect(mreznica.avatar, startsWith('https://cdn.domovina.ai/'));
      expect(mreznica.processedCount, 225);
    });

    test('ruta: Tier 1 s crticom, Tier 2 doslovno (i yt- s podvlakom)', () {
      final page = CatalogDirectoryPage.tryParse(_directory)!;
      expect(page.items[1].channel.routeSlug, 'sbs-croatian');
      expect(page.items[2].channel.routeSlug, 'radio-mreznica');
      final yt = CatalogDirectoryPage.tryParse(_unregistered)!;
      expect(yt.hasMore, isFalse);
      expect(yt.items.single.unregistered, isTrue);
      expect(yt.items.single.channel.hasChannelRoute, isTrue);
      expect(yt.items.single.channel.routeSlug, 'yt-UCfT_PJPR2vuqqKcCgEf3scA');
    });

    test('nečitljiva stavka se preskače, ostatak vrijedi', () {
      final j = jsonDecode(_directory) as Map<String, dynamic>;
      final items = j['items'] as List;
      items.insert(0, {'slug': '', 'name': 'x', 'tier': 2});
      items.insert(1, 'nije objekt');
      (items[3] as Map)['processed_count'] = 'mnogo';
      final page = CatalogDirectoryPage.tryParse(jsonEncode(j))!;
      expect(page.items, hasLength(3));
      expect(page.items[1].processedCount, 0);
    });

    test('kriva verzija, items nije lista, ne-JSON → null', () {
      final j = jsonDecode(_directory) as Map<String, dynamic>;
      expect(
        CatalogDirectoryPage.tryParse(jsonEncode({...j, 'version': '2'})),
        isNull,
      );
      expect(
        CatalogDirectoryPage.tryParse(jsonEncode({...j, 'items': {}})),
        isNull,
      );
      expect(CatalogDirectoryPage.tryParse('<html>'), isNull);
    });
  });

  group('CatalogChannelInfo / CatalogChannelEpisodesPage', () {
    test('zaglavlje kanala', () {
      final c = CatalogChannelInfo.tryParseResponse(_channel)!;
      expect(c.name, 'Tribina');
      expect(c.youtubeChannelId, 'UCjTiZ9ebMJumhPMsciuevxg');
      expect(CatalogChannelInfo.tryParseResponse(_notFound), isNull);
    });

    test('epizode kanala: kartice i kursor', () {
      final p = CatalogChannelEpisodesPage.tryParse(
        _episodes,
        slug: 'tribina',
      )!;
      expect(p.items.map((c) => c.id), ['_YOkTkbrh_k', 'BqJ67OO-FVA']);
      expect(p.items.first.channel!.slug, 'tribina');
      expect(p.items.first.date, '2026-11-05');
      expect(p.hasMore, isTrue);
    });
  });

  group('CatalogClient (S10)', () {
    late _MemStore store;
    late List<http.Request> requests;

    CatalogClient client(
      MockClientHandler handler, {
      String base = _base,
      Duration timeout = const Duration(seconds: 4),
    }) => CatalogClient(
      baseUrl: base,
      timeout: timeout,
      cache: CdnJsonCache(
        store: store,
        enabled: true,
        client: MockClient((req) {
          requests.add(req);
          return handler(req);
        }),
      ),
    );

    http.Response ok(String body) =>
        http.Response.bytes(utf8.encode(body), 200);

    setUp(() {
      store = _MemStore();
      requests = [];
    });

    test(
      'URL-ovi: /directory, /channels?tier=, kursor enkodiran, limit 1–100',
      () {
        final c = CatalogClient(baseUrl: _base);
        expect(c.directoryUrl(), '$_base/directory?limit=30');
        expect(
          c.directoryUrl(limit: 500, after: 'a+b'),
          '$_base/directory?limit=100&cursor=a%2Bb',
        );
        expect(
          c.directoryUrl(tier: 2, limit: 0),
          '$_base/channels?tier=2&limit=1',
        );
        expect(
          c.channelUrl('yt-UCfT_PJPR2vuqqKcCgEf3scA'),
          '$_base/channels/yt-UCfT_PJPR2vuqqKcCgEf3scA',
        );
        expect(
          c.channelEpisodesUrl('tribina', after: 'X'),
          '$_base/channels/tribina/episodes?limit=30&cursor=X',
        );
      },
    );

    test('directory 200 → Found; drugi poziv iz spremljenog', () async {
      final c = client((_) async => ok(_directory));
      final r = await c.directory();
      expect(r, isA<CatalogDirectoryFound>());
      expect(r.page!.items, hasLength(3));
      expect(requests.single.url.toString(), '$_base/directory?limit=30');
      final again = await c.directory();
      expect(again.page!.items, hasLength(3));
    });

    test('directory: 5xx, nečitljivo, timeout → Unavailable', () async {
      expect(
        await client((_) async => http.Response('x', 503)).directory(),
        isA<CatalogDirectoryUnavailable>(),
      );
      expect(
        await client((_) async => ok('<html>')).directory(),
        isA<CatalogDirectoryUnavailable>(),
      );
      final never = Completer<http.Response>();
      expect(
        await client(
          (_) => never.future,
          timeout: const Duration(milliseconds: 10),
        ).directory(),
        isA<CatalogDirectoryUnavailable>(),
      );
    });

    test('channel: 200 → Found, 404 → NotFound, 500 → Unavailable', () async {
      expect(
        (await client(
          (_) async => ok(_channel),
        ).channel('tribina')).channel!.name,
        'Tribina',
      );
      expect(
        await client(
          (_) async => http.Response(_notFound, 404),
        ).channel('nema'),
        isA<CatalogChannelNotFound>(),
      );
      expect(
        // Drugi slug: spremište je zajedničko, a `tribina` je već spremljena.
        await client((_) async => http.Response('x', 500)).channel('drugi'),
        isA<CatalogChannelUnavailable>(),
      );
      expect(requests.first.url.path, '/api/katalog/v1/channels/tribina');
    });

    test('channelEpisodes: 200, 404, nečitljivo', () async {
      final r = await client(
        (_) async => ok(_episodes),
      ).channelEpisodes('tribina', limit: 2);
      expect(r.page!.items, hasLength(2));
      expect(
        requests.single.url.toString(),
        '$_base/channels/tribina/episodes?limit=2',
      );
      expect(
        await client(
          (_) async => http.Response(_notFound, 404),
        ).channelEpisodes('nema'),
        isA<CatalogChannelEpisodesNotFound>(),
      );
      expect(
        await client((_) async => ok('{}')).channelEpisodes('tribina'),
        isA<CatalogChannelEpisodesUnavailable>(),
      );
    });

    test('brend bez kataloga: nijedan zahtjev, sve Unavailable', () async {
      final c = client((_) async => ok(_directory), base: '');
      expect(c.enabled, isFalse);
      expect(await c.directory(), isA<CatalogDirectoryUnavailable>());
      expect(await c.channel('tribina'), isA<CatalogChannelUnavailable>());
      expect(
        await c.channelEpisodes('tribina'),
        isA<CatalogChannelEpisodesUnavailable>(),
      );
      expect(requests, isEmpty);
    });
  });
}
