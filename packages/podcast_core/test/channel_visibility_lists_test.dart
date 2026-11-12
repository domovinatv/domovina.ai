/// Postavke kanala (S5) na popisima, naslovnici, pretrazi, osobama i
/// karticama: svaki ključ ima par — isključen → element nema; bez retka
/// postavki → kao danas (tvrdi uvjet 4, matrica §B). Bez mreže: cache se
/// puni `seed*ForTest`, stanje `ChannelVisibility.setForTest`.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:podcast_core/models/catalog_card.dart';
import 'package:podcast_core/models/catalog_channel_page.dart';
import 'package:podcast_core/models/catalog_day.dart';
import 'package:podcast_core/models/channel_detail.dart';
import 'package:podcast_core/models/channel_index.dart';
import 'package:podcast_core/models/home_snapshot.dart';
import 'package:podcast_core/models/person_hub.dart';
import 'package:podcast_core/screens/catalog_day/catalog_card_meta.dart';
import 'package:podcast_core/screens/favorites/favorites_resolver.dart';
import 'package:podcast_core/screens/home/home_feed.dart';
import 'package:podcast_core/screens/home/sort_mode.dart';
import 'package:podcast_core/services/channel_cache.dart';
import 'package:podcast_core/services/channel_visibility.dart';
import 'package:podcast_core/services/channel_visibility_filters.dart';
import 'package:podcast_core/services/favorites_service.dart';
import 'package:podcast_core/services/meili_client.dart';
import 'package:podcast_core/services/search_service.dart';
import 'package:podcast_core/services/unified_search.dart';
import 'package:podcast_core/services/watch_progress_service.dart';

// Pet kanala: po jedan za svaki slučaj, plus „obican” kao kontrola.
const ucGone = 'UCgoneaaaaaaaaaaaaaaaaaa';
const ucHome = 'UChomeaaaaaaaaaaaaaaaaaa';
const ucSearch = 'UCsearchaaaaaaaaaaaaaaaa';
const ucMag = 'UCmagaaaaaaaaaaaaaaaaaaa';
const ucOk = 'UCokaaaaaaaaaaaaaaaaaaaa';

const _channels = {
  'povucen': ucGone,
  'bez_naslovnice': ucHome,
  'bez_pretrage': ucSearch,
  'bez_ocjene': ucMag,
  'obican': ucOk,
};

String _today(int daysAgo) => DateTime.now()
    .subtract(Duration(days: daysAgo))
    .toIso8601String()
    .split('T')
    .first;

ChannelVideo _video(String id, {bool article = true, int day = 1}) =>
    ChannelVideo(
      id: id,
      title: 'Epizoda $id',
      date: _today(day),
      magisteriumScore: 88,
      pipeline: VideoPipeline(
        hasTranscript: article,
        hasDiarized: article,
        hasSummary: article,
        hasArticle: article,
        hasMagisterium: article,
      ),
    );

ChannelSummary _summary(String id, String uc) => ChannelSummary(
  id: id,
  name: 'Kanal $id',
  youtubeChannelUrl: 'https://www.youtube.com/channel/$uc',
  youtubeChannelId: uc,
  videoCount: 2,
  totalDurationSeconds: 3600,
  avgMagisteriumScore: 80,
  latestVideo: LatestVideo(id: '$id-a', date: _today(1), title: 'x'),
);

ChannelDetail _detail(String id, String uc) => ChannelDetail(
  version: '1',
  id: id,
  name: 'Kanal $id',
  youtubeChannelUrl: 'https://www.youtube.com/channel/$uc',
  youtubeChannelId: uc,
  videoCount: 2,
  totalDurationSeconds: 3600,
  avgMagisteriumScore: 80,
  videos: [
    _video('$id-a'),
    _video('$id-b', day: 2),
    _video('$id-svjeza', article: false),
  ],
);

void _seedCache() {
  channelCache.resetForTest();
  channelCache.seedIndexForTest(
    ChannelIndex(
      version: '1',
      channelCount: _channels.length,
      channels: [for (final e in _channels.entries) _summary(e.key, e.value)],
    ),
  );
  for (final e in _channels.entries) {
    channelCache.seedForTest(_detail(e.key, e.value));
  }
}

/// Stanje iz `/v1/settings`: povučen, bez naslovnice, bez pretrage, bez
/// ocjene, bez osoba, bez obavijesti.
Map<String, dynamic> _restricted() => {
  ucGone: channelOff(const ['channel_enabled'], status: 'withdrawn'),
  ucHome: channelOff(const ['home_featured', 'push_notifications']),
  ucSearch: channelOff(const ['in_app_search', 'persons_mentions']),
  ucMag: channelOff(const ['magisterium']),
};

Set<String> _ids(Iterable<FeedVideo> list) => {
  for (final v in list) v.video.id,
};

void main() {
  late ChannelVisibility original;

  setUp(() {
    original = ChannelVisibility.instance;
    ChannelVisibility.instance = ChannelVisibility();
    _seedCache();
  });

  tearDown(() {
    ChannelVisibility.instance = original;
    channelCache.resetForTest();
  });

  void restrict() =>
      ChannelVisibility.instance.setForTest(_restricted().cast());

  group('channel_enabled — povučen kanal nestaje iz popisa', () {
    test('index, popis kanala i redoslijed naslovnice', () {
      restrict();
      final ids = channelCache.index!.channels.map((c) => c.id);
      expect(ids, isNot(contains('povucen')));
      expect(
        ids,
        contains('bez_naslovnice'),
      ); // home_featured ne dira /channels
      // Sirovi index i dalje zna kanal (UC, ime) — za prikaz povučenog.
      expect(
        channelCache.rawIndex!.channels.map((c) => c.id),
        contains('povucen'),
      );
      expect(channelCache.ucFor('povucen'), ucGone);
      expect(channelCache.isChannelGone('povucen'), isTrue);

      channelCache.setOrderedChannels(channelCache.rawIndex!.channels);
      expect(
        channelCache.orderedChannels!.map((c) => c.id),
        isNot(contains('povucen')),
      );
    });

    test('bez retka postavki: index je isti objekt, ništa ne nedostaje', () {
      final idx = channelCache.index!;
      expect(identical(idx, channelCache.rawIndex), isTrue);
      expect(idx.channels.map((c) => c.id), contains('povucen'));
    });

    test('allVideos i feedVideos (home.json) bez epizoda povučenog kanala', () {
      channelCache.seedHomeSnapshotForTest(
        HomeSnapshot(
          version: 1,
          generatedAt: null,
          episodes: [
            HomeSnapshotEpisode(channelId: 'povucen', video: _video('snap-g')),
            HomeSnapshotEpisode(channelId: 'obican', video: _video('snap-o')),
          ],
        ),
      );
      expect(
        _ids(channelCache.feedVideos),
        containsAll(['snap-g', 'povucen-a']),
      );

      restrict();
      expect(_ids(channelCache.allVideos), isNot(contains('povucen-a')));
      final feed = _ids(channelCache.feedVideos);
      expect(feed, isNot(contains('snap-g')));
      expect(feed, isNot(contains('povucen-a')));
      expect(feed, containsAll(['snap-o', 'obican-a']));
      // Izravan /v/<id> i dalje nalazi epizodu (ekran epizode crta povučeno).
      expect(channelCache.findVideo('povucen-a'), isNotNull);
    });

    test('„Nastavi slušati”: kartica nestaje, zapis ostaje (odluka 502)', () {
      WatchProgress wp(String id, {String? uc}) => WatchProgress(
        episodeId: id,
        channelId: uc,
        positionSeconds: 10,
        durationSeconds: 100,
        lastWatchedAt: DateTime(2026, 11, 1),
      );
      final list = [
        wp('povucen-a', uc: ucGone), // UC iz info.json
        wp('povucen-b'), // bez UC-a → po listingu
        wp('obican-a', uc: ucOk),
      ];
      expect(visibleContinueWatching(list), same(list));

      restrict();
      final shown = visibleContinueWatching(list);
      expect(shown.map((w) => w.episodeId), ['obican-a']);
      expect(list, hasLength(3)); // ulaz netaknut
    });

    test('favoriti: kartica nestaje, bez postavki ostaje', () {
      const entries = [
        FavoriteEntry(episodeId: 'povucen-a'),
        FavoriteEntry(episodeId: 'nepoznata', channelName: 'Kanal povucen'),
        FavoriteEntry(episodeId: 'obican-a'),
      ];
      expect(resolveFavorites(entries), hasLength(3));

      restrict();
      final shown = resolveFavorites(entries).map((f) => f.episodeId);
      expect(shown, ['obican-a']);
    });

    test('katalog: popis kanala i dan bez povučenih, stanje /channels/:slug', () {
      final dir = CatalogDirectoryPage.tryParse(
        '{"version":"1","items":['
        '{"slug":"a","name":"A","tier":2},'
        '{"slug":"b","name":"B","tier":2,"settings":{"channel_enabled":false}}'
        ']}',
      )!;
      expect(dir.items.map((c) => c.slug), ['a']);

      final day = CatalogDayPage.tryParse(
        '{"version":"1","items":['
        '{"id":"x1","title":"X","tier":1},'
        '{"id":"x2","title":"Y","tier":1,"status":"withdrawn"},'
        '{"id":"x3","title":"Z","tier":1,"status":"deleted"}'
        ']}',
        date: '2026-11-12',
      )!;
      expect(day.items.map((c) => c.id), ['x1']);

      final withdrawn = CatalogChannelInfo.tryParseResponse(
        '{"version":"1","state":"withdrawn",'
        '"item":{"slug":"t","name":"T","tier":2,"youtube_channel_id":"$ucGone"}}',
      )!;
      expect(withdrawn.isWithdrawn, isTrue);
      expect(withdrawn.isGone, isTrue);

      final deleted = CatalogChannelInfo.tryParseResponse(
        '{"version":"1","state":"deleted","deleted_at":"2026-11-05T10:00:00Z",'
        '"item":{"slug":"t","name":"T","tier":2}}',
      )!;
      expect(deleted.isDeleted, isTrue);
      expect(deleted.deletedAt, DateTime.utc(2026, 11, 5, 10));

      final active = CatalogChannelInfo.tryParseResponse(
        '{"version":"1","item":{"slug":"t","name":"T","tier":2}}',
      )!;
      expect(active.isGone, isFalse);
      expect(active.state, isNull);
    });
  });

  group('home_featured — urednički izbor naslovnice', () {
    test('hero, Najnovije, Upravo stiglo i istaknuti bez kanala', () {
      final all = channelCache.feedVideos;
      // Kontrola: bez retka postavki kanal je posvuda.
      expect(
        _ids(HomeFeed.latestEpisodes(all, limit: 100)),
        contains('bez_naslovnice-a'),
      );
      expect(
        _ids(HomeFeed.freshlyArrived(all, limit: 100)),
        contains('bez_naslovnice-svjeza'),
      );

      restrict();
      final now = channelCache.feedVideos;
      final hero = HomeFeed.pickFeaturedCarousel(now, limit: 50);
      expect(hero, isNotEmpty);
      expect(
        hero.map((p) => p.video.channelId),
        isNot(contains('bez_naslovnice')),
      );
      expect(
        _ids(HomeFeed.latestEpisodes(now, limit: 100)),
        isNot(contains('bez_naslovnice-a')),
      );
      expect(
        _ids(HomeFeed.freshlyArrived(now, limit: 100)),
        isNot(contains('bez_naslovnice-svjeza')),
      );
      expect(
        HomeFeed.featuredShows(
          now,
          featuredChannels: const ['bez_naslovnice', 'obican'],
        ).map((v) => v.channelId),
        everyElement('obican'),
      );
      // Kanal ostaje u popisu kanala i u bazenu (korisnikovi popisi, /c/).
      expect(
        channelCache.index!.channels.map((c) => c.id),
        contains('bez_naslovnice'),
      );
      expect(_ids(channelCache.allVideos), contains('bez_naslovnice-a'));
    });

    test('bez retka postavki hero može izabrati kanal', () {
      final hero = HomeFeed.pickFeaturedCarousel(
        channelCache.feedVideos,
        limit: 50,
      );
      expect(hero.map((p) => p.video.channelId), contains('bez_naslovnice'));
    });
  });

  group('in_app_search — pogoci kanala iz sva tri izvora', () {
    List<EpisodeHit> merge() {
      LocalEpisodeMatch local(String ch) => (
        channelId: ch,
        channelName: 'Kanal $ch',
        video: _video('$ch-a'),
        titleMatch: true,
        snippet: null,
      );
      MeiliHit meili(String id, String ch) => MeiliHit(
        youtubeId: id,
        title: 'Epizoda $id',
        channel: ch,
        uploadDate: '2026-11-01',
        sectionTitles: const [],
        deepLink: '/v/$id',
        formattedTitle: 'Epizoda <em>$id</em>',
        formattedArticleSnippet: '',
      );
      SemanticResult sem(String id, String ch) => SemanticResult(
        chunkId: '$id-1',
        youtubeId: id,
        channel: ch,
        uploadDate: '2026-11-01',
        episodeTitle: 'Epizoda $id',
        speakers: const [],
        startTs: 0,
        endTs: 10,
        text: 'tekst',
        score: 0.9,
        deepLink: '/v/$id',
      );
      return mergeSearchResults(
        query: 'epizoda',
        local: [local('bez_pretrage'), local('obican')],
        // Meili nosi slug s crticom, semantika s podvlakom.
        meili: [
          meili('bez_pretrage-b', 'bez-pretrage'),
          meili('obican-b', 'obican'),
        ],
        semantic: [
          sem('bez_pretrage-svjeza', 'bez_pretrage'),
          sem('obican-svjeza', 'obican'),
        ],
        channelName: (slug) => 'Kanal $slug',
      );
    }

    test('isključen: nijedan izvor ne vraća kanal', () {
      restrict();
      final ids = merge().map((h) => h.youtubeId).toSet();
      expect(ids, {'obican-a', 'obican-b', 'obican-svjeza'});
    });

    test('bez retka postavki: svi pogoci', () {
      final ids = merge().map((h) => h.youtubeId).toSet();
      expect(
        ids,
        containsAll([
          'bez_pretrage-a',
          'bez_pretrage-b',
          'bez_pretrage-svjeza',
        ]),
      );
    });

    test('povučen kanal ne izlazi ni u pretrazi', () {
      restrict();
      expect(isSearchable('povucen-a', channelSlug: 'povucen'), isFalse);
      expect(isSearchable('obican-a', channelSlug: 'obican'), isTrue);
      // Pogodak samo s video ID-em: kanal se traži po epizodi.
      expect(isSearchable('bez_pretrage-a'), isFalse);
    });
  });

  group('magisterium — kartica bez ocjene i značke (odluka 504)', () {
    test('listing, index i ranker vide kanal bez ocjene', () {
      FeedVideo? find(String id) =>
          channelCache.allVideos.where((v) => v.video.id == id).firstOrNull;
      expect(find('bez_ocjene-a')!.video.magisteriumScore, 88);
      expect(HomeFeed.magisteriumScore(find('bez_ocjene-a')!), 88);

      restrict();
      final v = find('bez_ocjene-a')!;
      expect(v.video.magisteriumScore, isNull);
      expect(v.video.pipeline!.hasMagisterium, isFalse);
      expect(v.video.pipeline!.hasArticle, isTrue);
      expect(HomeFeed.magisteriumScore(v), isNull);
      expect(
        channelCache.get('bez_ocjene')!.videos.first.magisteriumScore,
        isNull,
      );
      expect(channelCache.get('obican')!.videos.first.magisteriumScore, 88);
      expect(find('obican-a')!.video.magisteriumScore, 88);

      final summary = channelCache.index!.channels.firstWhere(
        (c) => c.id == 'bez_ocjene',
      );
      expect(summary.avgMagisteriumScore, isNull);
      // Sortiranje po ocjeni: kanal bez ocjene ide iza ocijenjenih.
      final sorted = applySortMode(
        channelCache.index!.channels,
        ChannelSortMode.magisterium,
      );
      expect(sorted.last.id, 'bez_ocjene');
    });

    test('kartica iz kataloga: magisterium_off i svježa mapa postavki', () {
      final off = CatalogCard.fromItem({
        'id': 'k1',
        'title': 'K',
        'tier': 1,
        'magisterium_score': 77,
        'magisterium_off': true,
      })!;
      expect(off.magisteriumOff, isTrue);
      expect(off.magisteriumScore, isNull);
      expect(CatalogCardMeta.scoreOf(off), isNull);

      final card = CatalogCard.fromItem({
        'id': 'k2',
        'title': 'K',
        'tier': 1,
        'magisterium_score': 77,
        'channel': {'slug': 'bez_ocjene', 'name': 'K', 'tier': 1},
      })!;
      expect(CatalogCardMeta.scoreOf(card), 77);
      restrict();
      expect(CatalogCardMeta.scoreOf(card), isNull);
    });
  });

  group('persons_mentions — profil osobe', () {
    PersonEpisode ep(String id, String ch, {String? uc, bool cameo = false}) =>
        PersonEpisode(
          youtubeId: id,
          title: 'Epizoda $id',
          channel: ch,
          uploadDate: '2026-11-01',
          firstTs: 0,
          deepLink: '/v/$id',
          channelYoutubeId: uc,
          durationSeconds: 600,
          tier: cameo ? PersonEpisodeTier.cameo : PersonEpisodeTier.primary,
        );

    PersonHub hub() => PersonHub(
      name: 'Ana Anić',
      slug: 'ana-anic',
      avatarUrl: null,
      channelCount: 2,
      episodeCount: 3,
      channels: const [
        PersonChannelCount(channel: 'bez_pretrage', count: 2),
        PersonChannelCount(channel: 'obican', count: 1),
      ],
      episodes: [
        ep('bez_pretrage-a', 'bez_pretrage', uc: ucSearch),
        ep('obican-a', 'obican', uc: ucOk),
      ],
      cameoEpisodes: [ep('bez_pretrage-b', 'bez_pretrage', cameo: true)],
      cameoEpisodeCount: 1,
      mentions: [
        ep('bez_pretrage-svjeza', 'bez_pretrage'),
        ep('obican-b', 'obican'),
      ],
      mentionCount: 2,
      mentionChannels: const [
        PersonChannelCount(channel: 'bez_pretrage', count: 1),
        PersonChannelCount(channel: 'obican', count: 1),
      ],
      timeline: const [],
      totalDurationSeconds: 1800,
    );

    test('isključen: kanal izostaje iz nastupa i spomena', () {
      restrict();
      final h = visiblePersonHub(hub());
      expect(h.allAppearances.map((e) => e.youtubeId), ['obican-a']);
      expect(h.mentions.map((e) => e.youtubeId), ['obican-b']);
      expect(h.cameoEpisodes, isEmpty);
      expect(h.channels.map((c) => c.channel), ['obican']);
      expect(h.mentionChannels.map((c) => c.channel), ['obican']);
      expect(h.channelCount, 1);
      expect(h.episodeCount, 1);
      expect(h.mentionCount, 1);
      expect(h.totalDurationSeconds, 600);
    });

    test('bez retka postavki: isti profil', () {
      final original = hub();
      expect(visiblePersonHub(original), same(original));
    });
  });
}
