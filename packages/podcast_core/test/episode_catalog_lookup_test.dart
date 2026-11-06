import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:podcast_core/brand/app_brand.dart';
import 'package:podcast_core/brand/domovina_brand.dart';
import 'package:podcast_core/models/channel_detail.dart' show ChannelVideo;
import 'package:podcast_core/models/episode_bundle.dart';
import 'package:podcast_core/services/catalog_client.dart';
import 'package:podcast_core/services/cdn_json_cache.dart';
import 'package:podcast_core/services/cdn_store.dart';
import 'package:podcast_core/services/episode_catalog_lookup.dart';

import 'support/test_brands.dart';

/// Ekran epizode nad katalogom (S8 dio b, `katalog/docs/decisions.md`
/// 801–808): Tier 2 kanal na breadcrumbu, pad na listinge, brend bez
/// kataloga i ograda za sintetičke ID-eve. Bez mreže: lažni klijent ili
/// `MockClient` koji broji zahtjeve.

String _card({
  String id = '_YOkTkbrh_k',
  String? variantOf,
  String channel = '{"slug":"tribina","name":"Tribina","tier":2}',
}) =>
    '{"version":"1","catalog":"8","item":{"id":"$id",'
    '"title":"Novi početci","title_hr":null,"date":"2026-11-05",'
    '"duration_seconds":5715,"magisterium_score":null,"p":511,"tier":2,'
    '"lang":"hr","variant_of":${variantOf == null ? 'null' : '"$variantOf"'},'
    '"channel":$channel},"meta":{"rows_read":5}}';

class _FakeCatalog extends CatalogClient {
  _FakeCatalog(this.result) : super(baseUrl: 'https://katalog.test/v1');
  final CatalogLookup result;
  final List<String> asked = [];

  @override
  Future<CatalogLookup> lookup(String id) async {
    asked.add(id);
    return result;
  }
}

CatalogFound _found(String body) => CatalogFound(CatalogCard.tryParse(body)!);

typedef _Listed = ({String channelId, String channelName, ChannelVideo video});

_Listed _listed(String id, {String? youtubeUrl, String? source}) => (
  channelId: 'iva_kraljevic',
  channelName: 'Iva Kraljevic',
  video: ChannelVideo(
    id: id,
    title: 'Naslov',
    date: '2026-09-18',
    youtubeUrl: youtubeUrl,
    source: source,
  ),
);

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
  group('Tier 2 kanal na breadcrumbu (odluka 802)', () {
    const tribina = CatalogChannel(slug: 'tribina', name: 'Tribina', tier: 2);

    test(
      'iz episode.json channel: ime bez linka, kartica se ne pita',
      () async {
        final fake = _FakeCatalog(const CatalogUnavailable());
        final ch = await catalogChannelFor(
          '_YOkTkbrh_k',
          catalog: fake,
          bundle: () async => EpisodeBundle.tryParse(
            '{"version":1,"files":["info.json"],"inline":{},'
            '"channel":{"slug":"tribina","name":"Tribina","tier":2}}',
          ),
        );
        expect(ch, tribina);
        expect(fake.asked, isEmpty);
        expect(ch!.hasChannelRoute, isFalse);
        // Ekran za kanal bez rute postavlja samo ime i `showUnlinked`.
        final node = episodeBreadcrumbChannel(
          name: ch.name,
          slug: null,
          showUnlinked: true,
        );
        expect(node!.name, 'Tribina');
        expect(node.route, isNull);
      },
    );

    test('iz kartice (stari bundle bez ključa channel)', () async {
      final fake = _FakeCatalog(_found(_card()));
      final ch = await catalogChannelFor(
        '_YOkTkbrh_k',
        catalog: fake,
        bundle: () async => EpisodeBundle.tryParse(
          '{"version":1,"files":["info.json"],"inline":{}}',
        ),
      );
      expect(fake.asked, ['_YOkTkbrh_k']);
      expect(ch, tribina);
    });

    test('ekran u obradi: Tier 2 kanal iz kartice je ime bez linka', () async {
      final r = await findQueuedEpisode(
        '_YOkTkbrh_k',
        catalog: _FakeCatalog(_found(_card())),
        findVideo: (_) async => null,
      );
      final node = episodeBreadcrumbChannel(
        name: r!.channelName,
        slug: r.channelSlug,
        showUnlinked: r.source == QueuedEpisodeSource.catalog,
      );
      expect(node!.name, 'Tribina');
      expect(node.route, isNull);
    });

    test('Tier 1 iz kartice: link na /c/ s crticom', () async {
      final r = await findQueuedEpisode(
        'aue1GuuMsbA',
        catalog: _FakeCatalog(
          _found(
            _card(
              id: 'aue1GuuMsbA',
              channel:
                  '{"slug":"iva_kraljevic","name":"Iva Kraljevic","tier":1}',
            ),
          ),
        ),
        findVideo: (_) async => null,
      );
      final node = episodeBreadcrumbChannel(
        name: r!.channelName,
        slug: r.channelSlug,
        showUnlinked: true,
      );
      expect(node!.route, '/c/iva-kraljevic');
    });

    test('kartica bez kanala: nema čvora kanala', () async {
      final r = await findQueuedEpisode(
        '_YOkTkbrh_k',
        catalog: _FakeCatalog(_found(_card(channel: 'null'))),
        findVideo: (_) async => null,
      );
      expect(r!.channelName, isEmpty);
      expect(
        episodeBreadcrumbChannel(
          name: r.channelName,
          slug: r.channelSlug,
          showUnlinked: true,
        ),
        isNull,
      );
    });

    test('bez showUnlinked isto kao prije S8: čvor samo uz ime i slug', () {
      expect(episodeBreadcrumbChannel(name: 'Tribina', slug: null), isNull);
      expect(episodeBreadcrumbChannel(name: 'Tribina', slug: ''), isNull);
      expect(episodeBreadcrumbChannel(name: '', slug: 'tribina'), isNull);
      expect(
        episodeBreadcrumbChannel(name: 'Iva', slug: 'iva-kraljevic')!.route,
        '/c/iva-kraljevic',
      );
    });
  });

  group('findQueuedEpisode: kad se skidaju listinzi (odluka 804)', () {
    Future<int> listingCalls(CatalogLookup result) async {
      var calls = 0;
      await findQueuedEpisode(
        'aue1GuuMsbA',
        catalog: _FakeCatalog(result),
        findVideo: (_) async {
          calls++;
          return _listed('aue1GuuMsbA');
        },
      );
      return calls;
    }

    test('pogodak: findVideoAsync se ne zove', () async {
      expect(await listingCalls(_found(_card(id: 'aue1GuuMsbA'))), 0);
    });

    test('CatalogUnavailable: findVideoAsync jednom', () async {
      expect(await listingCalls(const CatalogUnavailable()), 1);
    });

    test('CatalogNotFound: findVideoAsync jednom', () async {
      expect(await listingCalls(const CatalogNotFound()), 1);
    });
  });

  group('brend bez Endpoints.catalog (odluka 800)', () {
    late List<http.Request> requests;
    late CdnJsonCache savedCache;
    late CatalogClient savedClient;

    setUp(() {
      requests = [];
      savedCache = CdnJsonCache.instance;
      savedClient = CatalogClient.instance;
      // Svaki zahtjev kroz dijeljeni cache bi se ovdje vidio.
      CdnJsonCache.instance = CdnJsonCache(
        store: _MemStore(),
        enabled: true,
        client: MockClient((req) async {
          requests.add(req);
          return http.Response(_card(), 200);
        }),
      );
      CatalogClient.instance = CatalogClient();
      AppBrand.init(brandWithoutCatalog());
    });

    tearDown(() {
      AppBrand.init(domovinaBrand);
      CdnJsonCache.instance = savedCache;
      CatalogClient.instance = savedClient;
    });

    test('zadani klijent čita brend: isključen, nijedan zahtjev', () async {
      expect(CatalogClient.instance.enabled, isFalse);
      expect(
        await CatalogClient.instance.lookup('_YOkTkbrh_k'),
        isA<CatalogUnavailable>(),
      );
      expect(requests, isEmpty);
    });

    test('ekran u obradi: stari tok kroz listinge', () async {
      var calls = 0;
      final r = await findQueuedEpisode(
        'aue1GuuMsbA',
        findVideo: (_) async {
          calls++;
          return _listed(
            'aue1GuuMsbA',
            youtubeUrl: 'https://www.youtube.com/watch?v=aue1GuuMsbA',
          );
        },
      );
      expect(calls, 1);
      expect(r!.source, QueuedEpisodeSource.listing);
      expect(r.channelSlug, 'iva_kraljevic');
      expect(r.youtubeVideoId, 'aue1GuuMsbA');
      expect(requests, isEmpty);
    });

    test('glavni ekran: kanal se ne traži, bundle se ne čita', () async {
      var bundleAsked = false;
      final ch = await catalogChannelFor(
        '_YOkTkbrh_k',
        bundle: () async {
          bundleAsked = true;
          return null;
        },
      );
      expect(ch, isNull);
      expect(bundleAsked, isFalse);
      expect(requests, isEmpty);
    });

    test('DOMOVINA ima katalog', () {
      AppBrand.init(domovinaBrand);
      expect(CatalogClient.instance.enabled, isTrue);
      expect(
        CatalogClient.instance.cardUrl('a b'),
        'https://domovina.ai/api/katalog/v1/episodes/a%20b/card',
      );
    });
  });

  group('sintetički ID bez embeda (odluka 808)', () {
    Future<String?> viaCard(String body) async => (await findQueuedEpisode(
      'id',
      catalog: _FakeCatalog(_found(body)),
      findVideo: (_) async => null,
    ))!.youtubeVideoId;

    Future<String?> viaListing(_Listed listed) async =>
        (await findQueuedEpisode(
          listed.video.id,
          catalog: CatalogClient(baseUrl: ''),
          findVideo: (_) async => listed,
        ))!.youtubeVideoId;

    test('pravi YouTube ID iz kartice i listinga: embed', () async {
      expect(await viaCard(_card()), '_YOkTkbrh_k');
      expect(
        await viaListing(
          _listed(
            'aue1GuuMsbA',
            youtubeUrl: 'https://www.youtube.com/watch?v=aue1GuuMsbA',
          ),
        ),
        'aue1GuuMsbA',
      );
      expect(
        await viaListing(_listed('aue1GuuMsbA')),
        'aue1GuuMsbA',
        reason: 'listing bez youtube_url: kao prije',
      );
      expect(
        await viaListing(
          _listed('aue1GuuMsbA', youtubeUrl: 'https://youtu.be/aue1GuuMsbA'),
        ),
        'aue1GuuMsbA',
      );
    });

    test('varijanta: embed osnovnog ID-a, ne sintetičkog', () async {
      expect(
        await viaCard(_card(id: 'OspwepfLO_2', variantOf: 'OspwepfLOab')),
        'OspwepfLOab',
      );
    });

    test('X autor (kanal x-…): bez embeda', () async {
      expect(
        await viaCard(
          _card(
            id: 'CUJmOc91C64',
            channel:
                '{"slug":"x-1973380383166050304","name":"Hobba",'
                '"tier":2}',
          ),
        ),
        isNull,
      );
    });

    test('RSS / beamly heks ID: bez embeda', () async {
      // ingest_rss.mjs: sha1(guid)[:11]; ingest_beamly.mjs: ObjectId[-11:].
      expect(
        await viaCard(
          _card(
            id: '3f9a0c1b2d4',
            channel: '{"slug":"dijalog","name":"Dijalog","tier":1}',
          ),
        ),
        isNull,
      );
      expect(await viaListing(_listed('a1b2c3d4e5f')), isNull);
    });

    test('ID krivog oblika: bez embeda', () async {
      expect(await viaCard(_card(id: 'nije-youtube-id')), isNull);
    });

    test('listing s ne-YouTube izvorom: bez embeda', () async {
      expect(
        await viaListing(
          _listed(
            'CUJmOc91C64',
            youtubeUrl: 'https://x.com/hobba_io/status/2077782099445137475',
          ),
        ),
        isNull,
      );
      expect(
        await viaListing(
          _listed(
            'CUJmOc91C64',
            youtubeUrl: 'https://launchedfm.com/episode/abc',
          ),
        ),
        isNull,
      );
      expect(await viaListing(_listed('CUJmOc91C64', source: 'x')), isNull);
      expect(
        await viaListing(_listed('CUJmOc91C64', source: 'youtube')),
        'CUJmOc91C64',
      );
    });
  });
}
