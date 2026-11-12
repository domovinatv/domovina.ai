/// Model postavki kanala (lanac `postavke-kanala/`, S4): 20 ključeva redom iz
/// odluke 1, rijetko sirovo stanje (odluka 203), ovisnosti samo za tekst
/// objašnjenja (odluka 108/200), log, zahtjev za brisanje, kodovi grešaka i
/// parsiranje kataloga `GET /v1/settings` (odluka 312). Bez mreže.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:podcast_core/services/channel_settings_service.dart';

void main() {
  group('ključevi (odluka 1)', () {
    test('20 ključeva, jedinstveni, redom iz odluke', () {
      expect(kChannelSettingKeys, hasLength(20));
      expect(kChannelSettingKeys.toSet(), hasLength(20));
      expect(kChannelSettingKeys.first, 'channel_enabled');
      expect(kChannelSettingKeys.last, 'sponsors_in_video');
    });

    test('skupine', () {
      expect(channelSettingKeysOf(ChannelSettingGroup.main), [
        'channel_enabled',
      ]);
      expect(channelSettingKeysOf(ChannelSettingGroup.presence), hasLength(5));
      expect(channelSettingKeysOf(ChannelSettingGroup.media), [
        'cdn_playback',
        'share_clips',
        'ebook',
      ]);
      expect(channelSettingKeysOf(ChannelSettingGroup.ai), hasLength(8));
      expect(channelSettingKeysOf(ChannelSettingGroup.money), [
        'donations',
        'paid_sponsor_moments',
        'sponsors_in_video',
      ]);
    });

    test('ovisnosti: transcript gasi i ono što ovisi o članku', () {
      expect(channelSettingDependsOn('ebook', 'transcript_subtitles'), isTrue);
      expect(
        channelSettingDependsOn('share_clips', 'transcript_subtitles'),
        isTrue,
      );
      expect(channelSettingDependsOn('ebook', 'article_summary'), isTrue);
      expect(
        channelSettingDependsOn('highlights_reels', 'article_summary'),
        isFalse,
      );
      expect(
        channelSettingDependsOn('donations', 'transcript_subtitles'),
        isFalse,
      );
      expect(channelSettingDependsOn('donations', 'channel_enabled'), isTrue);
      expect(
        channelSettingDependsOn('channel_enabled', 'channel_enabled'),
        isFalse,
      );
    });
  });

  group('ChannelSettings', () {
    test('kanal bez retka: sve uključeno, nepoznat ključ = true', () {
      final s = ChannelSettings.fromView(null);
      for (final k in kChannelSettingKeys) {
        expect(s.rawValue(k), isTrue);
        expect(s.effectiveValue(k), isTrue);
      }
      expect(s.rawValue('neki_novi_kljuc'), isTrue);
      expect(s.tombstoned, isFalse);
    });

    test('fromView čita rijetko sirovo i efektivno', () {
      final s = ChannelSettings.fromView({
        'youtube_channel_id': 'UCabcdefghijklmnopqrstuv',
        'settings': {'article_summary': false, 'ne_bool': 'x'},
        'effective': {
          'article_summary': false,
          'ebook': false,
          'magisterium': false,
        },
        'updated_at': '2026-11-12T10:00:00+00:00',
        'tombstoned': false,
      });
      expect(s.raw, {'article_summary': false});
      expect(s.rawValue('ebook'), isTrue);
      expect(s.effectiveValue('ebook'), isFalse);
      expect(s.isOverridden('ebook'), isTrue);
      expect(s.isOverridden('article_summary'), isFalse);
      expect(s.blockingParent('ebook'), 'article_summary');
      expect(s.blockingParent('donations'), isNull);
      expect(s.updatedAt, isNotNull);
    });

    test('blockingParent: glavni ima prednost, pa transcript, pa članak', () {
      var s = const ChannelSettings(
        raw: {'transcript_subtitles': false, 'article_summary': false},
      );
      expect(s.blockingParent('ebook'), 'transcript_subtitles');
      s = s.withRaw('channel_enabled', false);
      expect(s.blockingParent('ebook'), 'channel_enabled');
      expect(s.blockingParent('channel_enabled'), isNull);
    });

    test('withRaw mijenja samo sirovo, withEffective samo efektivno', () {
      const s = ChannelSettings(effective: {'donations': true});
      final a = s.withRaw('donations', false);
      expect(a.rawValue('donations'), isFalse);
      expect(a.effectiveValue('donations'), isTrue);
      final b = a.withEffective({'donations': false});
      expect(b.rawValue('donations'), isFalse);
      expect(b.effectiveValue('donations'), isFalse);
    });
  });

  group('log i zahtjev za brisanje', () {
    test('ChannelSettingsEvent.fromJson', () {
      final e = ChannelSettingsEvent.fromJson({
        'id': 42,
        'youtube_channel_id': 'UCabcdefghijklmnopqrstuv',
        'kind': 'setting',
        'key': 'donations',
        'old_value': true,
        'new_value': false,
        'account_id': 'u1',
        'role': 'collaborator',
        'source': 'app',
        'request_id': null,
        'note': null,
        'created_at': '2026-11-12T10:00:00+00:00',
      });
      expect(e.id, 42);
      expect(e.kind, ChannelSettingsEventKind.setting);
      expect(e.oldValue, isTrue);
      expect(e.newValue, isFalse);
      expect(e.role, 'collaborator');
      expect(e.pending, isFalse);
      expect(
        ChannelSettingsEventKind.fromJson('deletion_phone_confirmed'),
        ChannelSettingsEventKind.deletionPhoneConfirmed,
      );
      expect(
        ChannelSettingsEventKind.fromJson('nesto'),
        ChannelSettingsEventKind.unknown,
      );
    });

    test('ChannelDeletionRequest: otvoren i otkaziv', () {
      ChannelDeletionRequest r(String state) =>
          ChannelDeletionRequest.fromJson({
            'id': 'r1',
            'youtube_channel_id': 'UCabcdefghijklmnopqrstuv',
            'channel_title': 'Kanal',
            'state': state,
            'requested_at': '2026-11-12T10:00:00+00:00',
          });
      expect(r('requested').isOpen, isTrue);
      expect(r('requested').canCancel, isTrue);
      expect(r('phone_confirmed').isOpen, isTrue);
      expect(r('phone_confirmed').canCancel, isFalse);
      expect(r('cancelled').isOpen, isFalse);
      expect(r('executed').isOpen, isFalse);
      expect(r('requested').requestedAt, isNotNull);
    });
  });

  group('kodovi grešaka (prefiks do dvotočke)', () {
    test('poznati kodovi', () {
      expect(ChannelSettingsException.codeFrom('not_owner'), 'not_owner');
      expect(
        ChannelSettingsException.codeFrom('unknown_key: foo'),
        'unknown_key',
      );
      expect(
        ChannelSettingsException.codeFrom(
          'invalid_value: vrijednost mora biti true ili false',
        ),
        'invalid_value',
      );
      expect(
        ChannelSettingsException.codeFrom('confirm_name_mismatch'),
        'confirm_name_mismatch',
      );
    });

    test('nepoznato i prazno = unknown', () {
      expect(ChannelSettingsException.codeFrom(null), 'unknown');
      expect(ChannelSettingsException.codeFrom(''), 'unknown');
      expect(
        ChannelSettingsException.codeFrom('permission denied for table x'),
        'unknown',
      );
    });
  });

  group('katalog /v1/settings (odluka 312)', () {
    test('stvarni prazan odgovor produkcije', () {
      final m = ChannelSettingsCatalog.parse(
        '{"version":"1","catalog":"283","settings":{},"meta":{"rows_read":5}}',
      );
      expect(m, isNotNull);
      expect(m, isEmpty);
    });

    test('aktivan, povučen i obrisan kanal', () {
      final m = ChannelSettingsCatalog.parse('''
{"version":"1","catalog":"300","settings":{
  "UCaaaaaaaaaaaaaaaaaaaaaa":{"status":"active","off":["donations","ebook"]},
  "UCbbbbbbbbbbbbbbbbbbbbbb":{"status":"withdrawn","off":["channel_enabled"]},
  "UCcccccccccccccccccccccc":{"status":"deleted","off":["ebook"],"deleted_at":"2026-11-12T10:00:00Z"}
}}''')!;
      final a = m['UCaaaaaaaaaaaaaaaaaaaaaa']!;
      expect(a.status, 'active');
      expect(a.isEnabled('donations'), isFalse);
      expect(a.isEnabled('magisterium'), isTrue);
      expect(m['UCbbbbbbbbbbbbbbbbbbbbbb']!.isWithdrawn, isTrue);
      final c = m['UCcccccccccccccccccccccc']!;
      expect(c.isDeleted, isTrue);
      expect(c.deletedAt, DateTime.utc(2026, 11, 12, 10));
    });

    test('nečitljiv odgovor = null', () {
      expect(ChannelSettingsCatalog.parse('nije json'), isNull);
      expect(ChannelSettingsCatalog.parse('{"version":"1"}'), isNull);
    });

    test('fetch: 200 parsira, 5xx i brend bez kataloga daju null', () async {
      final asked = <Uri>[];
      final ok = ChannelSettingsCatalog(
        baseUrl: 'https://example.test/api/katalog/v1',
        client: MockClient((req) async {
          asked.add(req.url);
          return http.Response(
            '{"settings":{"UCaaaaaaaaaaaaaaaaaaaaaa":{"status":"active","off":["donations"]}}}',
            200,
          );
        }),
      );
      final m = await ok.fetch();
      expect(
        asked.single.toString(),
        'https://example.test/api/katalog/v1/settings',
      );
      expect(m!['UCaaaaaaaaaaaaaaaaaaaaaa']!.off, {'donations'});

      final down = ChannelSettingsCatalog(
        baseUrl: 'https://example.test/v1',
        client: MockClient((_) async => http.Response('x', 503)),
      );
      expect(await down.fetch(), isNull);

      var called = false;
      final none = ChannelSettingsCatalog(
        baseUrl: '',
        client: MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );
      expect(await none.fetch(), isNull);
      expect(called, isFalse);
    });
  });
}
