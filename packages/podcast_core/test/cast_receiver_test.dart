import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_core/models/sponsored_moment.dart';
import 'package:podcast_core/services/cast_receiver.dart';

void main() {
  SponsoredMoments moments(List<Map<String, Object?>> rows) =>
      SponsoredMoments.fromRows(rows);

  group('castCustomData', () {
    test('nosi verziju, oznaku i trenutke poredane po početku', () {
      final data = castCustomData(
        videoId: 'aue1GuuMsbA',
        sponsoredLabel: 'Sponzorirano',
        sponsored: moments([
          {
            'youtube_id': 'aue1GuuMsbA',
            'slot_key': 'b',
            'start_sec': 600,
            'end_sec': 630,
            'brand': 'Drugi',
          },
          {
            'youtube_id': 'aue1GuuMsbA',
            'slot_key': 'a',
            'start_sec': 60,
            'end_sec': 90,
            'brand': 'Prvi d.o.o.',
            'tagline': 'Jedna rečenica.',
            'logo_url': 'https://api.domovina.ai/storage/v1/logo.png',
            'link_url': 'https://primjer.hr',
          },
        ]),
      );

      expect(data['v'], kCastCustomDataVersion);
      expect(data['videoId'], 'aue1GuuMsbA');
      expect(data['labels'], {'sponsored': 'Sponzorirano'});
      expect(data['sponsored'], [
        {
          'slot': 'a',
          'start': 60,
          'end': 90,
          'brand': 'Prvi d.o.o.',
          'tagline': 'Jedna rečenica.',
          'logo': 'https://api.domovina.ai/storage/v1/logo.png',
        },
        {'slot': 'b', 'start': 600, 'end': 630, 'brand': 'Drugi'},
      ]);
      // Prolazi kroz JSON (Cast SDK customData serijalizira kao JSON).
      expect(() => jsonEncode(data), returnsNormally);
    });

    test('link se ne šalje, http logo se odbacuje', () {
      final data = castCustomData(
        videoId: 'x',
        sponsoredLabel: 'Sponsored',
        sponsored: moments([
          {
            'youtube_id': 'x',
            'start_sec': 1,
            'end_sec': 2,
            'brand': 'B',
            'logo_url': 'http://127.0.0.1:54321/logo.png',
            'link_url': 'https://primjer.hr',
          },
        ]),
      );
      final row = (data['sponsored'] as List).single as Map;
      expect(row.containsKey('logo'), isFalse);
      expect(row.containsKey('link'), isFalse);
      expect(row.containsKey('link_url'), isFalse);
    });

    test('bez trenutaka je lista prazna, ne null', () {
      final data = castCustomData(
        videoId: 'x',
        sponsoredLabel: 'Sponzorirano',
        sponsored: SponsoredMoments.empty,
      );
      expect(data['sponsored'], isEmpty);
    });
  });

  group('App ID', () {
    test('format je 8 heksadecimalnih znakova', () {
      expect(isValidCastAppId('CC1AD845'), isTrue);
      expect(isValidCastAppId('a1b2c3d4'), isTrue);
      expect(isValidCastAppId(''), isFalse);
      expect(isValidCastAppId('XXXXXXXX'), isFalse);
      expect(isValidCastAppId('CC1AD8451'), isFalse);
    });

    test('bez --dart-define receiver nije konfiguriran', () {
      // Testovi se ne pokreću s CAST_RECEIVER_APP_ID; nitko ne smije
      // hardkodirati App ID (ni Default Media Receiver CC1AD845) kao default.
      expect(castReceiverAppId, isEmpty);
      expect(castReceiverConfigured, isFalse);
    });
  });

  // Ugovor živi na dvije strane; receiver je u ljusci, pa ga paket vidi samo
  // unutar DOMOVINA repoa (Podcasterium ljuska ga nema — test se preskače).
  group('paritet s web/cast-receiver.html', () {
    final receiver = File('../../web/cast-receiver.html');

    test(
      'receiver čita istu verziju i ista polja',
      () {
        final html = receiver.readAsStringSync();
        expect(
          html,
          contains('CUSTOM_DATA_VERSION = $kCastCustomDataVersion;'),
          reason: 'verzija ugovora mora biti ista na obje strane',
        );
        for (final field in [
          'customData.v',
          'customData.sponsored',
          'customData.labels',
          'labels.sponsored',
          'r.brand',
          'r.start',
          'r.end',
          'r.tagline',
          'r.logo',
        ]) {
          expect(html, contains(field), reason: 'receiver ne čita $field');
        }
        // Brand i tagline su korisnički unos: nikad kao HTML.
        expect(html, isNot(contains('innerHTML')));
      },
      skip: receiver.existsSync() ? false : 'nema web/cast-receiver.html',
    );
  });
}
