import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:podcast_core/l10n/app_localizations.dart';
import 'package:podcast_core/models/channel_detail.dart';
import 'package:podcast_core/screens/home/hero_carousel.dart';
import 'package:podcast_core/screens/home/home_feed.dart';
import 'package:podcast_core/screens/home/skeletons.dart';
import 'package:podcast_core/theme/app_theme.dart';

/// Kontrakt: **[HeroSkeleton] i [HeroCarousel] su jednako visoki.**
///
/// Hero se otkriva tek kad je izbor konačan (`_ChannelGridViewState` latcha
/// pickove), pa postoji točno JEDNA zamjena skeleton → hero. Ako se te dvije
/// visine raziđu, ta zamjena pomakne sve railove ispod — što je upravo skok
/// zbog kojeg je latch i uveden.
///
/// Test pokriva oba layouta (desktop split / mobile stack) i oba broja
/// kandidata (1 = bez kontrolnog chromea, >1 = badge + dots), jer skeleton ne
/// zna unaprijed koliko će ih biti.
FeaturedPick _pick(String id) => FeaturedPick(
      video: (
        channelId: 'ch',
        channelName: 'Kanal',
        video: ChannelVideo(
          id: id,
          // Dovoljno dug da naslov padne u 2 retka — skeleton je crtan za
          // 2-redni naslov (najčešći slučaj na naslovnici).
          title: 'Sasvim dovoljno dug naslov epizode koji sigurno prelama '
              'u dva retka i na uskom i na širokom ekranu',
          // Meta red mora stati u JEDAN redak: `HeroSection` ga crta Wrapom,
          // a testni font je puno širi od Intera pa bi kanal + datum +
          // trajanje prelomili u dva reda i mjerili nešto što se u produkciji
          // ne događa. Ostavljamo samo ime kanala.
          date: null,
          durationDisplay: null,
          magisteriumScore: 86,
          pipeline: const VideoPipeline(
            hasTranscript: true,
            hasDiarized: true,
            hasSummary: true,
            hasArticle: true,
            hasMagisterium: true,
          ),
        ),
      ),
      reason: FeaturedReason.hiQualityRecent,
      candidatePool: 12,
      magisteriumScore: 86,
      daysAgo: 5,
      combinedScore: 82.4,
    );

Widget _host(Widget child, double width) => MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('hr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(width: width, child: child),
        ),
      ),
    );

Future<double> _heightOf(
  WidgetTester tester,
  Widget child, {
  required double width,
}) async {
  await tester.pumpWidget(_host(child, width));
  await tester.pump(const Duration(milliseconds: 16));
  return tester.getSize(find.byWidget(child)).height;
}

void main() {
  for (final (label, isMobile, width) in [
    ('desktop', false, 1200.0),
    ('mobile', true, 390.0),
    // Split hero na mobitelu u landscapeu (isMobile = širina >= 600). S
    // fiksnom slikom od 460 px ovdje su eyebrow i CTA probijali rub —
    // overflow sam obara widget test. Smoke 13.10.2026. na iPhoneima.
    ('split 600 (najuži split)', false, 600.0),
    ('landscape iPhone SE', false, 667.0),
    ('landscape iPhone 12 mini', false, 812.0),
  ]) {
    group('hero slot — $label', () {
      testWidgets('skeleton i karusel s VIŠE kandidata su jednako visoki',
          (tester) async {
        tester.view.physicalSize = Size(width, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final skeleton = HeroSkeleton(isMobile: isMobile);
        final carousel = HeroCarousel(
          picks: [_pick('a'), _pick('b'), _pick('c')],
          isMobile: isMobile,
          onPlay: (_) {},
        );

        final hSkeleton = await _heightOf(tester, skeleton, width: width);
        final hCarousel = await _heightOf(tester, carousel, width: width);

        expect(hCarousel, closeTo(hSkeleton, 1.0),
            reason: 'skeleton $hSkeleton vs karusel $hCarousel');
      });

      testWidgets('skeleton i karusel s JEDNIM kandidatom su jednako visoki',
          (tester) async {
        tester.view.physicalSize = Size(width, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final skeleton = HeroSkeleton(isMobile: isMobile);
        final single = HeroCarousel(
          picks: [_pick('a')],
          isMobile: isMobile,
          onPlay: (_) {},
        );

        final hSkeleton = await _heightOf(tester, skeleton, width: width);
        final hSingle = await _heightOf(tester, single, width: width);

        expect(hSingle, closeTo(hSkeleton, 1.0),
            reason: 'skeleton $hSkeleton vs jedan pick $hSingle');
      });
    });
  }

  testWidgets('kontrolna traka karusela ima kHeroControlBarHeight',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final multi = HeroCarousel(
      picks: [_pick('a'), _pick('b')],
      isMobile: false,
      onPlay: (_) {},
    );
    final single = HeroCarousel(
      picks: [_pick('a')],
      isMobile: false,
      onPlay: (_) {},
    );

    final hMulti = await _heightOf(tester, multi, width: 1200);
    final hSingle = await _heightOf(tester, single, width: 1200);

    // Obje varijante nose isti rezervirani prostor ispod kartice.
    expect(hMulti, closeTo(hSingle, 1.0));
    expect(kHeroControlBarHeight, 40);
  });
}
