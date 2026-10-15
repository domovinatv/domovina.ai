import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_core/models/podcast_info.dart';
import 'package:podcast_core/models/podcast_summary.dart';

/// Regresija za parsiranje info.json-a raznih izvora.
///
/// Prvi ne-YouTube (X/Twitter) video srušio je `/v/{id}` jer:
///  1. `duration` je decimalan (245.295) → stari `as int?` cast bacao TypeError,
///  2. `channel`/`view_count`/`categories` nedostaju,
///  3. `id` je sintetički pa `sourceUrl` NE smije biti youtube.com/watch link.
void main() {
  group('PodcastInfo.fromJson — X/Twitter izvor', () {
    // Skraćena, ali vjerna kopija https://cdn.domovina.ai/data/CUJmOc91C64/info.json
    final xJson = jsonDecode('''
    {
      "id": "CUJmOc91C64",
      "title": "Hobba - Meet the CEO",
      "description": "Meet the CEO of Hobba",
      "uploader": "Hobba 🟢",
      "channel_id": "1973380383166050304",
      "uploader_id": "hobba_io",
      "uploader_url": "https://twitter.com/hobba_io",
      "like_count": 61,
      "comment_count": 15,
      "duration": 245.295,
      "duration_string": "4:05",
      "thumbnail": "https://pbs.twimg.com/amplify_video_thumb/2077779999118000128/img/x.jpg?name=orig",
      "webpage_url": "https://x.com/hobba_io/status/2077782099445137475",
      "extractor": "twitter",
      "extractor_key": "Twitter",
      "upload_date": "20260716",
      "tags": [],
      "_source": "x"
    }
    ''') as Map<String, dynamic>;

    test('ne baca na decimalnom duration-u i zaokružuje na int', () {
      final info = PodcastInfo.fromJson(xJson);
      expect(info.duration, 245);
    });

    test('channel fallback na uploader kad channel nedostaje', () {
      final info = PodcastInfo.fromJson(xJson);
      expect(info.channel, 'Hobba 🟢');
    });

    test('nedostajuća polja su sigurna (view_count=0, categories=[])', () {
      final info = PodcastInfo.fromJson(xJson);
      expect(info.viewCount, 0);
      expect(info.categories, isEmpty);
      expect(info.commentCount, 15);
    });

    test('prepoznaje X izvor', () {
      final info = PodcastInfo.fromJson(xJson);
      expect(info.isX, isTrue);
      expect(info.source, 'x');
      expect(info.extractor, 'twitter');
    });

    test('sourceUrl vodi na X post, NE na youtube.com/watch sa sintetičkim id-om',
        () {
      final info = PodcastInfo.fromJson(xJson);
      expect(info.sourceUrl, 'https://x.com/hobba_io/status/2077782099445137475');
      expect(info.sourceUrl, isNot(contains('youtube.com')));
      expect(info.sourceUrl, isNot(contains('CUJmOc91C64')));
    });
  });

  group('PodcastInfo.fromJson — YouTube izvor (regresija)', () {
    final ytJson = jsonDecode('''
    {
      "id": "dQw4w9WgXcQ",
      "title": "Neka epizoda",
      "channel": "Neki Kanal",
      "channel_id": "UCuAXFkgsw1L7xaCfnd5JJOw",
      "uploader": "Neki Kanal",
      "upload_date": "20260101",
      "duration": 3600,
      "duration_string": "1:00:00",
      "view_count": 12345,
      "like_count": 678,
      "comment_count": 90,
      "description": "opis",
      "thumbnail": "https://i.ytimg.com/vi/dQw4w9WgXcQ/hq720.jpg",
      "webpage_url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
      "tags": ["a", "b"],
      "categories": ["News & Politics"],
      "extractor": "youtube"
    }
    ''') as Map<String, dynamic>;

    test('parsira standardni YouTube info.json bez promjena ponašanja', () {
      final info = PodcastInfo.fromJson(ytJson);
      expect(info.channel, 'Neki Kanal');
      expect(info.duration, 3600);
      expect(info.viewCount, 12345);
      expect(info.categories, ['News & Politics']);
      expect(info.isX, isFalse);
      expect(info.sourceUrl, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    });
  });

  group('PodcastSummary.fromJson — decimalan duration_seconds (X)', () {
    // X summary.json ima `source.duration_seconds: 245.295`. Ako pukne na castu,
    // loadSummary baci, trackOptional to proguta → summary=null → `summaryFor(...)!`
    // u episode buildu = BIJELI EKRAN (dok audio već svira).
    final xSummary = jsonDecode('''
    {
      "version": "1.0",
      "generated_at": "2026-07-24T09:23:23.412Z",
      "model": "gemini-3.5-flash",
      "source": {
        "filename": "20260716_unlisted_yt_CUJmOc91C64",
        "channel": "_unlisted",
        "youtube_id": "CUJmOc91C64",
        "title": "Hobba",
        "upload_date": "2026-07-16",
        "duration_seconds": 245.295
      },
      "summary": {
        "title_hr": "Upoznajte Hobba-u",
        "abstract_hr": "opis",
        "key_topics": ["defi"],
        "speakers": [],
        "key_points": [],
        "mentioned_people": [],
        "mentioned_places": [],
        "mentioned_organizations": [],
        "language": "hr"
      }
    }
    ''') as Map<String, dynamic>;

    test('ne baca i zaokružuje decimalan duration_seconds', () {
      final s = PodcastSummary.fromJson(xSummary);
      expect(s.source.durationSeconds, 245);
      expect(s.summary.titleHr, 'Upoznajte Hobba-u');
    });
  });

  group('playable_in_embed — smije li se epizoda ugraditi', () {
    test('YouTube info.json nosi zastavicu', () {
      final on = PodcastInfo.fromJson(const {
        'id': 'ZYG_ksNDl3s',
        'playable_in_embed': true,
      });
      final off = PodcastInfo.fromJson(const {
        'id': 'ZYG_ksNDl3s',
        'playable_in_embed': false,
      });
      expect(on.playableInEmbed, isTrue);
      expect(off.playableInEmbed, isFalse);
    });

    test('bez polja pretpostavljamo da smije — stari info.json ga nema', () {
      expect(
        PodcastInfo.fromJson(const {'id': 'x'}).playableInEmbed,
        isTrue,
      );
    });
  });

  group('PodcastInfo.fromJson — varijanta epizode (`_variant_of`)', () {
    test('sintetički id ostaje za CDN, YouTube ide na _variant_of', () {
      final info = PodcastInfo.fromJson(<String, dynamic>{
        'id': 'OspwepfLO_2',
        'title': 'Epizoda',
        'webpage_url': 'https://www.youtube.com/watch?v=OspwepfLObY',
        '_variant_of': 'OspwepfLObY',
        '_variant': {'n': 2, 'label': 'Canary + pyannote → Opus'},
      });
      expect(info.id, 'OspwepfLO_2');
      expect(info.isVariant, isTrue);
      expect(info.variantOf, 'OspwepfLObY');
      expect(info.variantNumber, 2);
      expect(info.variantLabel, 'Canary + pyannote → Opus');
      expect(info.youtubeVideoId, 'OspwepfLObY');
      expect(info.sourceUrl, 'https://www.youtube.com/watch?v=OspwepfLObY');
    });

    test('bez polja, prazno ili krivog tipa → nije varijanta', () {
      for (final extra in <Map<String, dynamic>>[
        {},
        {'_variant_of': '', '_variant': 'x'},
        {
          '_variant_of': 42,
          '_variant': {'n': 'dva', 'label': 7},
        },
      ]) {
        final info = PodcastInfo.fromJson(<String, dynamic>{
          'id': 'OspwepfLObY',
          ...extra,
        });
        expect(info.isVariant, isFalse, reason: '$extra');
        expect(info.variantOf, isNull);
        expect(info.variantLabel, isNull);
        expect(info.youtubeVideoId, 'OspwepfLObY');
      }
    });
  });
}
