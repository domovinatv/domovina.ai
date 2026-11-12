/// `ChannelVisibility` (postavke kanala, S5): jedini izvor stanja u
/// aplikaciji. Fail-open: nedostupan katalog zadrži staru mapu, nepoznat
/// ključ i kanal izvan mape su uključeni, povučen kanal gasi sve, `refresh`
/// poštuje `maxAge`. Bez mreže — `MockClient`.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:podcast_core/services/channel_setting_keys.dart';
import 'package:podcast_core/services/channel_settings_service.dart';
import 'package:podcast_core/services/channel_visibility.dart';

const _uc = 'UCaaaaaaaaaaaaaaaaaaaaaa';
const _uc2 = 'UCbbbbbbbbbbbbbbbbbbbbbb';

/// Lažni katalog: vraća redom zadane odgovore (tijelo ili `null` = 503).
class _Catalog {
  _Catalog(this.bodies);
  final List<Object?> bodies;
  int calls = 0;

  ChannelSettingsCatalog get catalog => ChannelSettingsCatalog(
    baseUrl: 'https://katalog.test/v1',
    client: MockClient((req) async {
      expect(req.url.toString(), 'https://katalog.test/v1/settings');
      final body = bodies[calls < bodies.length ? calls : bodies.length - 1];
      calls++;
      if (body == null) return http.Response('down', 503);
      // Omotnica kao `GET /v1/settings` (odluka 312); string = nečitljivo.
      final json = body is Map ? {'version': '1', 'settings': body} : body;
      return http.Response.bytes(
        utf8.encode(jsonEncode(json)),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
}

void main() {
  late ChannelVisibility original;
  setUp(() => original = ChannelVisibility.instance);
  tearDown(() => ChannelVisibility.instance = original);

  test('imena ključeva provedbe postoje u ugovoru (kChannelSettingDefs)', () {
    for (final k in ChannelKey.all) {
      expect(kChannelSettingKeys, contains(k), reason: k);
    }
  });

  test('bez učitane mape: sve uključeno, ništa povučeno (kao danas)', () {
    final v = ChannelVisibility(catalog: _Catalog([{}]).catalog);
    expect(v.isLoaded, isFalse);
    expect(v.isEnabled(_uc, ChannelKey.homeFeatured), isTrue);
    expect(v.isGone(_uc), isFalse);
    expect(v.isEnabled(null, ChannelKey.donations), isTrue);
  });

  test(
    'isključen ključ gasi samo taj ključ; nepoznat ključ je uključen',
    () async {
      final cat = _Catalog([
        {
          _uc: {
            'status': 'active',
            'off': ['home_featured', 'magisterium'],
          },
        },
      ]);
      final v = ChannelVisibility(catalog: cat.catalog);
      await v.refresh();
      expect(v.isLoaded, isTrue);
      expect(v.isEnabled(_uc, ChannelKey.homeFeatured), isFalse);
      expect(v.isEnabled(_uc, ChannelKey.magisterium), isFalse);
      expect(v.isEnabled(_uc, ChannelKey.inAppSearch), isTrue);
      expect(v.isEnabled(_uc, 'kljuc_iz_buducnosti'), isTrue);
      // Drugi kanal (izvan mape) i kanal bez UC-a: sve uključeno.
      expect(v.isEnabled(_uc2, ChannelKey.homeFeatured), isTrue);
      expect(v.isEnabled('', ChannelKey.homeFeatured), isTrue);
      expect(v.isGone(_uc), isFalse);
    },
  );

  test('povučen kanal gasi sve ključeve, i kad off nije potpun', () async {
    final v = ChannelVisibility(
      catalog: _Catalog([
        {
          _uc: {
            'status': 'withdrawn',
            'off': ['channel_enabled'],
          },
        },
      ]).catalog,
    );
    await v.refresh();
    expect(v.isWithdrawn(_uc), isTrue);
    expect(v.isGone(_uc), isTrue);
    expect(v.isDeleted(_uc), isFalse);
    for (final k in ChannelKey.all) {
      expect(v.isEnabled(_uc, k), isFalse, reason: k);
    }
    expect(v.isEnabled(_uc, 'kljuc_iz_buducnosti'), isFalse);
  });

  test('obrisan kanal nosi datum brisanja', () async {
    final v = ChannelVisibility(
      catalog: _Catalog([
        {
          _uc: {
            'status': 'deleted',
            'off': kChannelSettingKeys,
            'deleted_at': '2026-11-05T10:00:00Z',
          },
        },
      ]).catalog,
    );
    await v.refresh();
    expect(v.isDeleted(_uc), isTrue);
    expect(v.isGone(_uc), isTrue);
    expect(v.deletedAt(_uc), DateTime.utc(2026, 11, 5, 10));
  });

  test('nedostupan katalog (null) zadrži zadnju poznatu mapu', () async {
    var t = DateTime(2026, 11, 12, 10);
    final cat = _Catalog([
      {
        _uc: {
          'status': 'active',
          'off': ['donations'],
        },
      },
      null, // 503
      'nije json', // nečitljiv odgovor
    ]);
    final v = ChannelVisibility(catalog: cat.catalog, now: () => t);
    await v.refresh();
    expect(v.isEnabled(_uc, ChannelKey.donations), isFalse);

    t = t.add(const Duration(minutes: 6));
    await v.refresh();
    expect(cat.calls, 2);
    expect(v.isEnabled(_uc, ChannelKey.donations), isFalse);

    await v.refresh(force: true);
    expect(cat.calls, 3);
    expect(v.isEnabled(_uc, ChannelKey.donations), isFalse);
  });

  test('refresh poštuje maxAge, a promjena mape javlja slušateljima', () async {
    var t = DateTime(2026, 11, 12, 10);
    final cat = _Catalog([
      {
        _uc: {
          'status': 'active',
          'off': ['in_app_search'],
        },
      },
      {
        _uc: {
          'status': 'withdrawn',
          'off': ['channel_enabled'],
        },
      },
    ]);
    final v = ChannelVisibility(catalog: cat.catalog, now: () => t);
    var notified = 0;
    v.addListener(() => notified++);

    await v.refresh();
    expect(cat.calls, 1);
    expect(notified, 1);

    // Unutar maxAge: nema zahtjeva.
    t = t.add(const Duration(minutes: 4));
    await v.refresh();
    await v.ready();
    expect(cat.calls, 1);
    expect(v.isGone(_uc), isFalse);

    // Nakon maxAge: novi zahtjev, nova mapa, slušatelji obaviješteni.
    t = t.add(ChannelVisibility.maxAge);
    await v.refresh();
    expect(cat.calls, 2);
    expect(v.isGone(_uc), isTrue);
    expect(notified, 2);
  });

  test('istodobni refresh dijeli jedan zahtjev', () async {
    final cat = _Catalog([{}]);
    final v = ChannelVisibility(catalog: cat.catalog);
    await Future.wait([v.refresh(), v.refresh(), v.ready()]);
    expect(cat.calls, 1);
    expect(v.isLoaded, isTrue);
    expect(v.snapshot, isEmpty);
  });
}
