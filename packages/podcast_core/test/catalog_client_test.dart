import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:podcast_core/models/channel_detail.dart' show ChannelVideo;
import 'package:podcast_core/models/episode_bundle.dart';
import 'package:podcast_core/services/catalog_client.dart';
import 'package:podcast_core/services/cdn_json_cache.dart';
import 'package:podcast_core/services/cdn_store.dart';
import 'package:podcast_core/services/episode_catalog_lookup.dart';

/// Ugovor klijenta kataloga (S8, `katalog/docs/decisions.md` 800–808).
/// Fixtureovi su skraćeni stvarni odgovori produkcije od 6. 11. 2026.
const _tier1 =
    '{"version":"1","catalog":"8","item":{"id":"aue1GuuMsbA",'
    '"title":"Tko je Iva iza kamere","title_hr":"Tko je Iva iza kamere",'
    '"date":"2026-09-18","duration_seconds":9686,"magisterium_score":85,'
    '"p":31,"tier":1,"lang":null,"variant_of":null,'
    '"channel":{"slug":"iva_kraljevic","name":"Iva Kraljevic","tier":1}},'
    '"meta":{"rows_read":5}}';

const _tier2 =
    '{"version":"1","catalog":"8","item":{"id":"_YOkTkbrh_k",'
    '"title":"Novi početci | Tribina NBA","title_hr":"Novi početci | Tribina NBA",'
    '"date":"2026-11-05","duration_seconds":5715,"magisterium_score":null,'
    '"p":511,"tier":2,"lang":"hr","variant_of":null,'
    '"channel":{"slug":"tribina","name":"Tribina","tier":2}},'
    '"meta":{"rows_read":5}}';

const _base = 'https://domovina.ai/api/katalog/v1';

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

/// Lažni klijent kakav će koristiti i widget testovi ekrana.
class _FakeCatalog extends CatalogClient {
  _FakeCatalog(this.result) : super(baseUrl: _base);
  final CatalogLookup result;
  final List<String> asked = [];

  @override
  Future<CatalogLookup> lookup(String id) async {
    asked.add(id);
    return result;
  }
}

void main() {
  group('CatalogCard.tryParse', () {
    test('Tier 1: kanal je praćeni, slug s podvlakom, ruta s crticom', () {
      final card = CatalogCard.tryParse(_tier1)!;
      expect(card.id, 'aue1GuuMsbA');
      expect(card.tier, 1);
      expect(card.date, '2026-09-18');
      expect(card.catalog, '8');
      expect(
        card.channel,
        const CatalogChannel(
          slug: 'iva_kraljevic',
          name: 'Iva Kraljevic',
          tier: 1,
        ),
      );
      expect(card.channel!.hasChannelRoute, isTrue);
      expect(card.channel!.routeSlug, 'iva-kraljevic');
    });

    test('Tier 2: kanal bez rute', () {
      final card = CatalogCard.tryParse(_tier2)!;
      expect(card.tier, 2);
      expect(card.displayTitle, 'Novi početci | Tribina NBA');
      expect(card.channel!.name, 'Tribina');
      expect(card.channel!.hasChannelRoute, isFalse);
    });

    test('title_hr ima prednost, null pada na title', () {
      final j = jsonDecode(_tier1) as Map<String, dynamic>;
      (j['item'] as Map)['title_hr'] = null;
      (j['item'] as Map)['title'] = 'Izvorni';
      expect(CatalogCard.tryParse(jsonEncode(j))!.displayTitle, 'Izvorni');
    });

    test('nepoznati ključevi ne smetaju', () {
      final j = jsonDecode(_tier1) as Map<String, dynamic>;
      j['novo'] = {'x': 1};
      (j['item'] as Map)['nesto'] = [1, 2];
      ((j['item'] as Map)['channel'] as Map)['avatar'] = 'a.png';
      final card = CatalogCard.tryParse(jsonEncode(j))!;
      expect(card.channel!.slug, 'iva_kraljevic');
    });

    test('krivi tipovi neobaveznih polja → null, ne iznimka', () {
      final j = jsonDecode(_tier1) as Map<String, dynamic>;
      final item = j['item'] as Map;
      item['date'] = 20260918;
      item['title_hr'] = 7;
      item['channel'] = {'slug': 'iva_kraljevic', 'name': 3, 'tier': 1};
      j['catalog'] = 8;
      final card = CatalogCard.tryParse(jsonEncode(j))!;
      expect(card.date, isNull);
      expect(card.titleHr, isNull);
      expect(card.channel, isNull);
      expect(card.catalog, isNull);
    });

    test('nečitljivo, druga verzija ili bez obaveznih polja → null', () {
      expect(CatalogCard.tryParse('nije json'), isNull);
      expect(CatalogCard.tryParse('[]'), isNull);
      expect(
        CatalogCard.tryParse(
          _tier1.replaceFirst('"version":"1"', '"version":"2"'),
        ),
        isNull,
      );
      expect(
        CatalogCard.tryParse(
          _tier1.replaceFirst('"version":"1"', '"version":1'),
        ),
        isNull,
      );
      expect(CatalogCard.tryParse('{"version":"1","item":null}'), isNull);
      expect(
        CatalogCard.tryParse(
          _tier1.replaceFirst('"tier":1,"lang"', '"tier":"1","lang"'),
        ),
        isNull,
      );
      expect(
        CatalogCard.tryParse(
          _tier1.replaceFirst('"id":"aue1GuuMsbA"', '"id":5'),
        ),
        isNull,
      );
      expect(
        CatalogCard.tryParse('{"ok":false,"error":"episode_not_found"}'),
        isNull,
      );
    });
  });

  group('CatalogChannel.tryParse', () {
    test('odbija prazno, ne-objekt i decimalni tier', () {
      expect(CatalogChannel.tryParse(null), isNull);
      expect(CatalogChannel.tryParse('tribina'), isNull);
      expect(
        CatalogChannel.tryParse({'slug': '', 'name': 'X', 'tier': 1}),
        isNull,
      );
      expect(
        CatalogChannel.tryParse({'slug': 'x', 'name': 'X', 'tier': 1.5}),
        isNull,
      );
      expect(
        CatalogChannel.tryParse({'slug': 'x', 'name': 'X', 'tier': 2.0})!.tier,
        2,
      );
    });
  });

  group('EpisodeBundle.channel', () {
    const files = '"version":1,"files":["info.json"],"inline":{}';

    test('ključ izostaje (stara epizoda) → nepoznato', () {
      final b = EpisodeBundle.tryParse('{$files}')!;
      expect(b.channelKnown, isFalse);
      expect(b.channel, isNull);
      expect(b.has('info.json'), isTrue);
    });

    test('null → katalog zna da kanala nema', () {
      final b = EpisodeBundle.tryParse('{$files,"channel":null}')!;
      expect(b.channelKnown, isTrue);
      expect(b.channel, isNull);
    });

    test('objekt → kanal', () {
      final b = EpisodeBundle.tryParse(
        '{$files,"channel":{"slug":"tribina","name":"Tribina","tier":2}}',
      )!;
      expect(b.channelKnown, isTrue);
      expect(
        b.channel,
        const CatalogChannel(slug: 'tribina', name: 'Tribina', tier: 2),
      );
    });

    test('nečitljiv kanal → nepoznato, a ostatak bundlea vrijedi', () {
      final b = EpisodeBundle.tryParse('{$files,"channel":"tribina"}')!;
      expect(b.channelKnown, isFalse);
      expect(b.channel, isNull);
      expect(b.has('info.json'), isTrue);
    });
  });

  group('CatalogClient.lookup', () {
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

    setUp(() {
      store = _MemStore();
      requests = [];
    });

    test('200 → kartica, URL je /episodes/:id/card', () async {
      final c = client(
        (_) async => http.Response.bytes(utf8.encode(_tier2), 200),
      );
      final r = await c.lookup('_YOkTkbrh_k');
      expect(r, isA<CatalogFound>());
      expect(r.card!.channel!.slug, 'tribina');
      expect(
        requests.single.url.toString(),
        '$_base/episodes/_YOkTkbrh_k/card',
      );
    });

    test('drugi poziv čita spremljeno (stale-while-revalidate)', () async {
      final c = client(
        (_) async => http.Response.bytes(utf8.encode(_tier1), 200),
      );
      await c.lookup('aue1GuuMsbA');
      final again = await c.lookup('aue1GuuMsbA');
      expect(again.card!.id, 'aue1GuuMsbA');
    });

    test('404 → CatalogNotFound', () async {
      final c = client(
        (_) async =>
            http.Response('{"ok":false,"error":"episode_not_found"}', 404),
      );
      expect(await c.lookup('xxxxxxxxxxx'), isA<CatalogNotFound>());
      expect(await c.card('xxxxxxxxxxx'), isNull);
    });

    test('5xx, mreža i nečitljiv odgovor → CatalogUnavailable', () async {
      expect(
        await client((_) async => http.Response('', 503)).lookup('a'),
        isA<CatalogUnavailable>(),
      );
      expect(
        await client(
          (_) async => throw http.ClientException('offline'),
        ).lookup('b'),
        isA<CatalogUnavailable>(),
      );
      expect(
        await client((_) async => http.Response('<html>', 200)).lookup('c'),
        isA<CatalogUnavailable>(),
      );
    });

    test('timeout → CatalogUnavailable', () async {
      final never = Completer<http.Response>();
      final c = client(
        (_) => never.future,
        timeout: const Duration(milliseconds: 20),
      );
      expect(await c.lookup('d'), isA<CatalogUnavailable>());
    });

    test('brend bez kataloga: nijedan zahtjev', () async {
      final c = client((_) async => http.Response(_tier1, 200), base: '');
      expect(c.enabled, isFalse);
      expect(await c.lookup('aue1GuuMsbA'), isA<CatalogUnavailable>());
      expect(requests, isEmpty);
    });
  });

  group('findQueuedEpisode', () {
    final listed = (
      channelId: 'iva_kraljevic',
      channelName: 'Iva Kraljevic',
      video: const ChannelVideo(
        id: 'aue1GuuMsbA',
        title: 'Izvorni',
        titleHr: 'Naslov',
        date: '2026-09-18',
      ),
    );

    test('pogodak u katalogu: listinzi se ne skidaju', () async {
      var listingCalls = 0;
      final r = await findQueuedEpisode(
        '_YOkTkbrh_k',
        catalog: _FakeCatalog(CatalogFound(CatalogCard.tryParse(_tier2)!)),
        findVideo: (_) async {
          listingCalls++;
          return null;
        },
      );
      expect(listingCalls, 0);
      expect(r!.source, QueuedEpisodeSource.catalog);
      expect(r.channelName, 'Tribina');
      expect(r.channelSlug, isNull, reason: 'Tier 2 kanal nema /c/ rutu');
      expect(r.date, '2026-11-05');
    });

    test('Tier 1 iz kataloga: slug u obliku rute', () async {
      final r = await findQueuedEpisode(
        'aue1GuuMsbA',
        catalog: _FakeCatalog(CatalogFound(CatalogCard.tryParse(_tier1)!)),
        findVideo: (_) async => null,
      );
      expect(r!.channelSlug, 'iva-kraljevic');
    });

    for (final miss in const <CatalogLookup>[
      CatalogNotFound(),
      CatalogUnavailable(),
    ]) {
      test('${miss.runtimeType}: pad na listinge', () async {
        final r = await findQueuedEpisode(
          'aue1GuuMsbA',
          catalog: _FakeCatalog(miss),
          findVideo: (_) async => listed,
        );
        expect(r!.source, QueuedEpisodeSource.listing);
        expect(r.title, 'Naslov');
        expect(
          r.channelSlug,
          'iva_kraljevic',
          reason: 'isto kao prije kataloga',
        );
      });
    }

    test('brend bez kataloga: samo listinzi, katalog se ne pita', () async {
      final noCatalog = CatalogClient(baseUrl: '');
      final r = await findQueuedEpisode(
        'aue1GuuMsbA',
        catalog: noCatalog,
        findVideo: (_) async => listed,
      );
      expect(r!.source, QueuedEpisodeSource.listing);
      expect(
        await findQueuedEpisode(
          'x',
          catalog: noCatalog,
          findVideo: (_) async => null,
        ),
        isNull,
      );
    });
  });

  group('catalogChannelFor', () {
    const tribina = CatalogChannel(slug: 'tribina', name: 'Tribina', tier: 2);

    test('kanal iz episode.json: kartica se ne pita', () async {
      final fake = _FakeCatalog(const CatalogUnavailable());
      final ch = await catalogChannelFor(
        '_YOkTkbrh_k',
        catalog: fake,
        bundle: () async => const EpisodeBundle(
          files: {},
          inline: {},
          channelKnown: true,
          channel: tribina,
        ),
      );
      expect(ch, tribina);
      expect(fake.asked, isEmpty);
    });

    test('episode.json kaže „bez kanala”: null, kartica se ne pita', () async {
      final fake = _FakeCatalog(CatalogFound(CatalogCard.tryParse(_tier2)!));
      final ch = await catalogChannelFor(
        '_YOkTkbrh_k',
        catalog: fake,
        bundle: () async =>
            const EpisodeBundle(files: {}, inline: {}, channelKnown: true),
      );
      expect(ch, isNull);
      expect(fake.asked, isEmpty);
    });

    test('stari bundle ili bez bundlea: kartica', () async {
      final fake = _FakeCatalog(CatalogFound(CatalogCard.tryParse(_tier2)!));
      expect(
        await catalogChannelFor(
          '_YOkTkbrh_k',
          catalog: fake,
          bundle: () async => const EpisodeBundle(files: {}, inline: {}),
        ),
        tribina,
      );
      expect(
        await catalogChannelFor(
          '_YOkTkbrh_k',
          catalog: fake,
          bundle: () async => throw Exception('mreža'),
        ),
        tribina,
      );
      expect(fake.asked, ['_YOkTkbrh_k', '_YOkTkbrh_k']);
    });

    test('brend bez kataloga: null bez ijednog upita', () async {
      var bundleAsked = false;
      final ch = await catalogChannelFor(
        '_YOkTkbrh_k',
        catalog: CatalogClient(baseUrl: ''),
        bundle: () async {
          bundleAsked = true;
          return null;
        },
      );
      expect(ch, isNull);
      expect(bundleAsked, isFalse);
    });
  });
}
