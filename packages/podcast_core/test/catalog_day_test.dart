import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:podcast_core/services/catalog_client.dart';
import 'package:podcast_core/services/cdn_json_cache.dart';
import 'package:podcast_core/services/cdn_store.dart';

/// Ugovor `GET /days/:date` (S9, `katalog/contract/v1/days.schema.json`).
/// Fixture je skraćen stvarni odgovor produkcije od 6. 11. 2026.
/// (`/days/2026-11-04?limit=2`).
const _day =
    '{"version":"1","catalog":"8","items":['
    '{"id":"y0J491L5J9s","title":"Otvoreno: Gospić i dalje čeka odgovore",'
    '"title_hr":"Otvoreno: Gospić i dalje čeka odgovore","date":"2026-11-04",'
    '"duration_seconds":1956,"magisterium_score":null,"p":511,"tier":2,'
    '"lang":"hr","variant_of":null,"channel":null},'
    '{"id":"xGAmPf_ihm4","title":"🔵 KIŠOVIZIJA #100 | Kišobran UNIRI",'
    '"title_hr":"KIŠOVIZIJA #100 | Kišobran UNIRI","date":"2026-11-04",'
    '"duration_seconds":4312,"magisterium_score":null,"p":511,"tier":2,'
    '"lang":"hr","variant_of":null,"channel":{"slug":"kisobran-uniri-podcast",'
    '"name":"Kišobran UNIRI Podcast","tier":2}}],'
    '"next":"WyIyMDI2LTExLTA0IiwieEdBbVBmX2lobTQiXQ","meta":{"rows_read":8}}';

const _empty =
    '{"version":"1","catalog":"8","items":[],"next":null,'
    '"meta":{"rows_read":3}}';

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

void main() {
  group('CatalogDayPage.tryParse', () {
    test('stvarni odgovor: stavke, kursor, kanal ili null', () {
      final page = CatalogDayPage.tryParse(_day, date: '2026-11-04')!;
      expect(page.date, '2026-11-04');
      expect(page.catalog, '8');
      expect(page.items, hasLength(2));
      expect(page.hasMore, isTrue);
      expect(page.next, 'WyIyMDI2LTExLTA0IiwieEdBbVBmX2lobTQiXQ');
      expect(page.items[0].channel, isNull);
      expect(page.items[0].tier, 2);
      expect(page.items[1].displayTitle, 'KIŠOVIZIJA #100 | Kišobran UNIRI');
      expect(page.items[1].channel!.name, 'Kišobran UNIRI Podcast');
      expect(page.items[1].catalog, '8');
    });

    test('trajanje, ocjena i sat objave: aditivna polja, krivi tip → null', () {
      CatalogCard card(Map<String, Object?> extra) => CatalogCard.fromItem({
        'id': 'aaaaaaaaaaa',
        'title': 'T',
        'tier': 1,
        ...extra,
      })!;
      final full = card({
        'duration_seconds': 3961.4,
        'magisterium_score': 79,
        'published_at': '2026-11-10T17:00:35Z',
      });
      expect(full.durationSeconds, 3961);
      expect(full.durationDisplay, '1:06:01');
      expect(full.magisteriumScore, 79);
      expect(full.publishedAt, DateTime.utc(2026, 11, 10, 17, 0, 35));
      expect(card({'duration_seconds': 808}).durationDisplay, '13:28');

      final none = card({
        'duration_seconds': null,
        'magisterium_score': null,
      });
      expect(none.durationDisplay, isNull);
      expect(none.magisteriumScore, isNull);
      expect(none.publishedAt, isNull, reason: 'stari odgovor nema polje');

      final bad = card({
        'duration_seconds': '3961',
        'magisterium_score': 140,
        'published_at': 'jučer',
      });
      expect(bad.durationSeconds, isNull);
      expect(bad.magisteriumScore, isNull);
      expect(bad.publishedAt, isNull);
    });

    test('prazan dan je stranica, ne greška', () {
      final page = CatalogDayPage.tryParse(_empty, date: '2026-11-06')!;
      expect(page.isEmpty, isTrue);
      expect(page.hasMore, isFalse);
    });

    test('nečitljiva stavka se preskače, ostatak vrijedi', () {
      final page = CatalogDayPage.tryParse(
        '{"version":"1","catalog":null,"items":[{"id":""},'
        '{"id":"a","title":"A","tier":1},7],"next":"","meta":{"rows_read":1}}',
        date: '2026-11-05',
      )!;
      expect(page.items.map((c) => c.id), ['a']);
      expect(page.next, isNull, reason: 'prazan kursor = nema dalje');
      expect(page.catalog, isNull);
    });

    test('kriva verzija, items nije lista, nije JSON → null', () {
      expect(
        CatalogDayPage.tryParse(
          '{"version":"2","items":[],"next":null}',
          date: '2026-11-05',
        ),
        isNull,
      );
      expect(
        CatalogDayPage.tryParse(
          '{"version":"1","items":{},"next":null}',
          date: '2026-11-05',
        ),
        isNull,
      );
      expect(CatalogDayPage.tryParse('<html>', date: '2026-11-05'), isNull);
    });
  });

  group('datumi', () {
    test('parseCatalogDate je strog', () {
      expect(parseCatalogDate('2026-11-05'), DateTime(2026, 11, 5));
      expect(parseCatalogDate('2024-02-29'), DateTime(2024, 2, 29));
      for (final bad in [
        '2026-02-30',
        '2026-13-01',
        '2026-1-5',
        '2026-11-05T00:00',
        'danas',
        '',
      ]) {
        expect(parseCatalogDate(bad), isNull, reason: bad);
      }
    });

    test('format i pomak preko mjeseca, godine i promjene vremena', () {
      expect(formatCatalogDate(DateTime(2026, 3, 9)), '2026-03-09');
      expect(
        formatCatalogDate(shiftCatalogDate(DateTime(2026, 1, 1), -1)),
        '2025-12-31',
      );
      // 25. 10. 2026. je prijelaz na zimsko vrijeme u Hrvatskoj.
      expect(
        formatCatalogDate(shiftCatalogDate(DateTime(2026, 10, 26), -1)),
        '2026-10-25',
      );
      expect(
        catalogToday(DateTime(2026, 11, 6, 12, 38)),
        DateTime(2026, 11, 6),
      );
    });
  });

  group('CatalogClient.day', () {
    late _MemStore store;
    late List<http.Request> requests;

    CatalogClient client(MockClientHandler handler, {String base = _base}) =>
        CatalogClient(
          baseUrl: base,
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

    test('URL: limit se stisne na 1–100, kursor ide kao after', () {
      final c = CatalogClient(baseUrl: _base);
      expect(
        c.dayUrl('2026-11-04', limit: 12),
        '$_base/days/2026-11-04?limit=12',
      );
      expect(
        c.dayUrl('2026-11-04', limit: 500, after: 'WyJ4Il0'),
        '$_base/days/2026-11-04?limit=100&cursor=WyJ4Il0',
      );
      expect(
        c.dayUrl('2026-11-04', limit: 0),
        '$_base/days/2026-11-04?limit=1',
      );
    });

    test('200 → stranica, i spremi se u bucket episode', () async {
      final c = client(
        (_) async => http.Response.bytes(utf8.encode(_day), 200),
      );
      final r = await c.day('2026-11-04', limit: 2);
      expect(r, isA<CatalogDayFound>());
      expect(r.page!.items, hasLength(2));
      expect(requests.single.url.toString(), '$_base/days/2026-11-04?limit=2');
      expect(store.data.keys.single, startsWith('episode|'));
    });

    test('prazan dan → CatalogDayFound s praznom stranicom', () async {
      final c = client(
        (_) async => http.Response.bytes(utf8.encode(_empty), 200),
      );
      final r = await c.day('2026-11-06');
      expect(r, isA<CatalogDayFound>());
      expect(r.page!.isEmpty, isTrue);
    });

    test('neispravan datum → CatalogDayBadDate bez zahtjeva', () async {
      final c = client((_) async => http.Response('x', 200));
      expect(await c.day('2026-13-45'), isA<CatalogDayBadDate>());
      expect(requests, isEmpty);
    });

    test('HTTP 400 (bad_date) → CatalogDayBadDate', () async {
      final c = client(
        (_) async => http.Response('{"ok":false,"error":"bad_date"}', 400),
      );
      expect(await c.day('2026-11-05'), isA<CatalogDayBadDate>());
    });

    test('5xx, nečitljivo, mreža → CatalogDayUnavailable', () async {
      // Svaki slučaj sa svojom pohranom: 200 se sprema, pa bi treći upit
      // inače dobio spremljeno tijelo drugoga.
      expect(
        await client((_) async => http.Response('', 503)).day('2026-11-05'),
        isA<CatalogDayUnavailable>(),
      );
      store = _MemStore();
      expect(
        await client(
          (_) async => http.Response('<html>', 200),
        ).day('2026-11-05'),
        isA<CatalogDayUnavailable>(),
      );
      store = _MemStore();
      expect(
        await client(
          (_) async => throw http.ClientException('offline'),
        ).day('2026-11-05'),
        isA<CatalogDayUnavailable>(),
      );
    });

    test('brend bez kataloga → CatalogDayUnavailable bez zahtjeva', () async {
      final c = client((_) async => http.Response(_day, 200), base: '');
      expect(await c.day('2026-11-04'), isA<CatalogDayUnavailable>());
      expect(requests, isEmpty);
    });
  });
}
