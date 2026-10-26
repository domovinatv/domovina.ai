import 'package:flutter_test/flutter_test.dart';

import 'package:podcast_core/brand/app_brand.dart';
import 'package:podcast_core/brand/domovina_brand.dart';
import 'package:podcast_core/router/nav.dart';

import 'support/test_brands.dart';

/// Ugovor za „gore" (Android Up), odvojen od „nazad" (Back).
///
/// Back popa stog; Up ide na semantičkog roditelja i koristi se SAMO kad stoga
/// nema — dolazak sa share linka, hard refresh, otvaranje iz drugog appa. Do
/// 6.9.2026. su svi ekrani u tom slučaju padali na `/`, pa je ← s epizode
/// otvorene iz kataloga vodio na naslovnicu umjesto natrag na kanal.
void main() {
  group('upTarget — epizoda', () {
    test('bez razriješenog kanala pada na naslovnicu', () {
      expect(upTarget('/v/abc123'), '/');
      expect(upTarget('/m/abc123'), '/');
    });

    test('s razriješenim kanalom ide na kanal, ne na naslovnicu', () {
      expect(upTarget('/v/abc123', channelSlug: 'muzevni-budite'),
          '/c/muzevni-budite');
      expect(upTarget('/m/abc123', channelSlug: 'muzevni-budite'),
          '/c/muzevni-budite');
    });

    test('timestamp i jezični sufiks ne mijenjaju roditelja', () {
      expect(upTarget('/v/abc123/t/840', channelSlug: 'x'), '/c/x');
      expect(upTarget('/v/abc123/t/840/en', channelSlug: 'x'), '/c/x');
      expect(upTarget('/v/abc123/en', channelSlug: 'x'), '/c/x');
    });

    test('prazan slug se tretira kao nerazriješen', () {
      expect(upTarget('/v/abc123', channelSlug: ''), '/');
    });

    test('`?p=` marker ne mijenja roditelja', () {
      expect(upTarget('/v/abc123?p=don-damir-stojic', channelSlug: 'x'),
          '/c/x');
    });
  });

  group('upTarget — kanal i osoba', () {
    test('kanal ide na katalog, ne na naslovnicu', () {
      expect(upTarget('/c/muzevni-budite'), '/channels');
    });

    test('podstranica kanala ide na sam kanal', () {
      expect(upTarget('/c/muzevni-budite/doniraj'), '/c/muzevni-budite');
      expect(upTarget('/c/muzevni-budite/support'), '/c/muzevni-budite');
      expect(upTarget('/c/muzevni-budite/claim'), '/c/muzevni-budite');
    });

    // Osobe žive u ISTOM katalogu kao kanali, samo s odabranim filtrom
    // (odluka O9 u docs/plans/virtualni-kanali.md) — zato query param, a ne
    // zasebna `/osobe` ruta.
    test('osoba ide na katalog s filtrom „Osobe"', () {
      expect(upTarget('/p/don-damir-stojic'), '/channels?prikaz=osobe');
    });
  });

  group('upTarget — glasanje i račun', () {
    setUp(() => AppBrand.init(brandWithVoting()));
    tearDown(() => AppBrand.init(domovinaBrand));

    test('detalj kandidata ide na ljestvicu', () {
      expect(upTarget('/glasanje/abbacast'), '/glasanje');
    });

    test('sama ljestvica ide na naslovnicu', () {
      expect(upTarget('/glasanje'), '/');
    });

    test('račun se penje korak po korak', () {
      expect(upTarget('/account'), '/');
      expect(upTarget('/account/channels'), '/account');
      expect(upTarget('/account/channels/UC123'), '/account/channels');
      expect(upTarget('/account/channels/UC123/campaigns'),
          '/account/channels/UC123');
      expect(upTarget('/account/channels/UC123/campaigns/c1'),
          '/account/channels/UC123');
    });
  });

  group('upTarget — rubovi', () {
    test('korijen i nepoznata ruta padaju na naslovnicu', () {
      expect(upTarget('/'), '/');
      expect(upTarget(''), '/');
      expect(upTarget('/favorites'), '/');
      expect(upTarget('/search'), '/');
      expect(upTarget('/privacy'), '/');
    });

    test('katalog s filtrom ne pokazuje sam na sebe', () {
      expect(upTarget('/channels?prikaz=osobe'), '/');
      expect(upTarget('/channels'), '/');
    });
  });
}
