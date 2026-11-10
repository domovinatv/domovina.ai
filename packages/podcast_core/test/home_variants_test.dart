import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:podcast_core/l10n/app_localizations.dart';
import 'package:podcast_core/models/channel_detail.dart';
import 'package:podcast_core/models/channel_index.dart';
import 'package:podcast_core/screens/home/home_feed.dart';
import 'package:podcast_core/screens/home/variants/home_variants.dart';
import 'package:podcast_core/services/watch_progress_service.dart';
import 'package:podcast_core/theme/app_theme.dart';

import 'support/fake_asset_bundle.dart';

/// Varijante naslovnice iza `?home=a|b|c`
/// (`docs/plans/2026-11-10-naslovnica-varijante-abc.md`).
///
/// Dvije vrste ugovora:
/// 1. **Regresijska vrata**: bez parametra varijante nema, a postojeća
///    naslovnica gradi isti popis slivera, istim redom, kao prije uvođenja
///    varijanti.
/// 2. Svaka varijanta se gradi bez iznimke (overflow, intrinsics) na 390 i
///    1440 px — i za povratnika i za gosta.
void main() {
  group('HomeVariantFlag', () {
    test('bez parametra nema varijante', () {
      expect(HomeVariantFlag.overrideFromUri(Uri.parse('https://x/')), isNull);
      expect(HomeVariantFlag.overrideFromUri(null), isNull);
      expect(HomeVariantFlag.decode(null), isNull);
      expect(HomeVariantFlag.decode(''), isNull);
    });

    test('a|b|c postavlja, 0/off briše, nepoznato ignorira', () {
      HomeVariant? set(String q) {
        final o = HomeVariantFlag.overrideFromUri(Uri.parse('https://x/?$q'));
        return o is HomeVariantSet ? o.variant : null;
      }

      expect(set('home=a'), HomeVariant.a);
      expect(set('home=B'), HomeVariant.b);
      expect(set('home=c'), HomeVariant.c);
      expect(
        HomeVariantFlag.overrideFromUri(Uri.parse('https://x/?home=0')),
        isA<HomeVariantClear>(),
      );
      expect(
        HomeVariantFlag.overrideFromUri(Uri.parse('https://x/?home=off')),
        isA<HomeVariantClear>(),
      );
      expect(
        HomeVariantFlag.overrideFromUri(Uri.parse('https://x/?home=d')),
        isNull,
      );
    });

    test('native (VM) nikad nema varijantu', () {
      HomeVariantFlag.debugReset();
      expect(HomeVariantFlag.current, isNull);
    });
  });

  test('postojeća naslovnica: isti sliveri, isti redoslijed', () {
    final src = File('lib/screens/home/home_screen.dart').readAsStringSync();
    final branch = src.indexOf('final variant = HomeVariantFlag.current;');
    expect(branch, greaterThan(0), reason: 'grananje mora postojati');
    expect('HomeVariantFlag.current'.allMatches(src).length, 1);
    expect(src.substring(branch), contains('if (variant != null) {'));

    // Puni sadržaj = zadnji `return CustomScrollView(` u datoteci, IZA grananja.
    final start = src.lastIndexOf('return CustomScrollView(');
    expect(start, greaterThan(branch));
    final block = src.substring(start, src.indexOf('// "Svi kanali" CTA'));

    const expected = [
      'HomeAppBar(',
      '_HomeHeader(',
      'HeroSkeleton(',
      'HeroCarousel(',
      'VotingRail(',
      'l.homeRailContinue',
      'FollowedRail(',
      'l.homeRailFeaturedShows',
      'l.homeRailLatest',
      'RailSkeleton(',
      'l.homeRailFreshlyArrived',
      'CatalogDayRail(',
      'PersonsRail(',
      'FavoritesRail(',
      '_AllChannelsCta(',
      'HomeFooter(',
    ];
    var at = 0;
    for (final token in expected) {
      final i = block.indexOf(token, at);
      expect(
        i,
        greaterThanOrEqualTo(0),
        reason: '$token nedostaje ili je premješten',
      );
      at = i + token.length;
    }
    // Varijante ne smiju curiti u postojeći layout.
    expect(block, isNot(contains('Variant')));
  });

  group('varijante se grade', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    for (final variant in HomeVariant.values) {
      for (final width in [390.0, 1440.0]) {
        for (final returning in [true, false]) {
          final who = returning ? 'povratnik' : 'gost';
          testWidgets('${variant.name} · ${width.toInt()} px · $who', (
            tester,
          ) async {
            tester.view.physicalSize = Size(width, 2400);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);

            final controller = ScrollController();
            addTearDown(controller.dispose);
            await tester.pumpWidget(
              _host(
                buildHomeVariant(
                  variant,
                  _data(width: width, returning: returning, ctrl: controller),
                ),
              ),
            );
            await tester.pump(const Duration(milliseconds: 400));
            expect(tester.takeException(), isNull);
            expect(find.byType(CustomScrollView), findsOneWidget);

            // Do dna (footer, Otkrij) — overflow bi pao tek ondje.
            await tester.drag(
              find.byType(CustomScrollView),
              const Offset(0, -6000),
            );
            await tester.pump(const Duration(milliseconds: 400));
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });
}

Widget _host(Widget child) => DefaultAssetBundle(
  bundle: FakeAssetBundle(),
  child: MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('hr'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ),
);

FeedVideo _fv(String id, {bool processed = true, String date = '2026-11-09'}) =>
    (
      channelId: 'ch',
      channelName: 'Kanal',
      video: ChannelVideo(
        id: id,
        title: 'Naslov epizode $id koji je dovoljno dug da prelomi',
        date: date,
        durationDisplay: '1:02:03',
        magisteriumScore: processed ? 88 : null,
        pipeline: VideoPipeline(
          hasTranscript: processed,
          hasDiarized: processed,
          hasSummary: processed,
          hasArticle: processed,
          hasMagisterium: processed,
        ),
      ),
    );

HomeVariantData _data({
  required double width,
  required bool returning,
  required ScrollController ctrl,
}) {
  final vids = [for (var i = 0; i < 14; i++) _fv('v$i')];
  final fresh = [for (var i = 0; i < 4; i++) _fv('f$i', processed: false)];
  final picks = [
    for (final v in vids.take(3))
      FeaturedPick(
        video: v,
        reason: FeaturedReason.hiQualityRecent,
        candidatePool: 12,
        magisteriumScore: 88,
        daysAgo: 1,
      ),
  ];
  return HomeVariantData(
    featuredPicks: picks,
    allVids: vids,
    continueWatching: returning
        ? [
            for (var i = 0; i < 4; i++)
              WatchProgress(
                episodeId: 'v$i',
                positionSeconds: 1200,
                durationSeconds: 3600,
                episodeTitle: 'Započeta epizoda $i',
                lastWatchedAt: DateTime(2026, 11, 9),
              ),
          ]
        : const [],
    freshlyArrived: fresh,
    channels: [
      for (var i = 0; i < 8; i++)
        ChannelSummary(
          id: 'kanal_$i',
          name: 'Kanal $i',
          youtubeChannelUrl: 'https://youtube.com/@k$i',
          videoCount: 10,
          totalDurationSeconds: 36000,
        ),
    ],
    hasMinData: true,
    width: width,
    scrollController: ctrl,
    onSearchTap: () {},
    onVideoTap: (_) {},
  );
}
