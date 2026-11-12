/// Postavke kanala (S5) na ekranima: povučen/obrisan `/c/` (`ChannelGoneView`),
/// rute donacija i oglasa (`ChannelFeatureOffGuard`) i zvonce obavijesti
/// (`FollowButton`, `push_notifications`). Par: isključeno → nema;
/// bez retka postavki → kao danas. Bez mreže.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:podcast_core/l10n/app_localizations.dart';
import 'package:podcast_core/models/channel_index.dart';
import 'package:podcast_core/services/channel_cache.dart';
import 'package:podcast_core/services/channel_setting_keys.dart';
import 'package:podcast_core/services/channel_visibility.dart';
import 'package:podcast_core/widgets/channel_feature_off_guard.dart';
import 'package:podcast_core/widgets/channel_gone_view.dart';

const _uc = 'UCgoneaaaaaaaaaaaaaaaaaa';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('hr'),
  home: Scaffold(body: child),
);

void main() {
  late ChannelVisibility original;

  setUp(() {
    original = ChannelVisibility.instance;
    ChannelVisibility.instance = ChannelVisibility();
    channelCache.resetForTest();
  });

  tearDown(() {
    ChannelVisibility.instance = original;
    channelCache.resetForTest();
  });

  group('channel_enabled — /c/ povučen ili obrisan (ChannelGoneView)', () {
    testWidgets('povučen: tekst, YouTube gumb na kanal, na naslovnicu', (
      tester,
    ) async {
      var home = 0;
      await tester.pumpWidget(
        _app(ChannelGoneView(ucId: _uc, onBackHome: () => home++)),
      );
      expect(
        find.text('Vlasnik je povukao ovaj sadržaj s domovina.ai'),
        findsOneWidget,
      );
      expect(
        find.text('Snimka je i dalje dostupna na YouTubeu.'),
        findsOneWidget,
      );
      expect(find.text('Otvori na YouTubeu'), findsOneWidget);
      expect(
        const ChannelGoneView(ucId: _uc).resolvedYoutubeUrl,
        'https://www.youtube.com/channel/$_uc',
      );
      await tester.tap(find.text('Na naslovnicu'));
      expect(home, 1);
      expect(find.textContaining('epizod'), findsNothing);
    });

    testWidgets('obrisan: datum dd. mm. gggg., bez YouTube gumba', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          ChannelGoneView(
            ucId: _uc,
            isDeleted: true,
            deletedAt: DateTime(2026, 11, 5, 12),
          ),
        ),
      );
      expect(
        find.text('Kanal je trajno uklonjen s domovina.ai 05. 11. 2026.'),
        findsOneWidget,
      );
      expect(find.textContaining('05. 11. 2026.'), findsOneWidget);
      expect(find.textContaining('trajno uklonjen'), findsOneWidget);
      expect(find.text('Otvori na YouTubeu'), findsNothing);
      expect(find.text('Na naslovnicu'), findsOneWidget);
    });

    testWidgets('obrisan bez datuma', (tester) async {
      await tester.pumpWidget(
        _app(const ChannelGoneView(ucId: _uc, isDeleted: true)),
      );
      expect(
        find.text('Kanal je trajno uklonjen s domovina.ai.'),
        findsOneWidget,
      );
    });
  });

  group('donations / paid_sponsor_moments — ruta značajke', () {
    Widget guard(String key) => ChannelFeatureOffGuard(
      featureKey: key,
      ucId: _uc,
      child: const Text('ZID'),
    );

    for (final key in [ChannelKey.donations, ChannelKey.paidSponsorMoments]) {
      testWidgets('$key isključen → poruka umjesto zida', (tester) async {
        ChannelVisibility.instance.setForTest({
          _uc: channelOff([key]),
        });
        await tester.pumpWidget(_app(guard(key)));
        await tester.pumpAndSettle();
        expect(find.text('ZID'), findsNothing);
        expect(
          find.text('Vlasnik kanala je isključio ovu mogućnost.'),
          findsOneWidget,
        );
      });

      testWidgets('$key bez retka postavki → zid kao danas', (tester) async {
        ChannelVisibility.instance.setForTest({});
        await tester.pumpWidget(_app(guard(key)));
        await tester.pumpAndSettle();
        expect(find.text('ZID'), findsOneWidget);
      });
    }

    testWidgets('povučen kanal na ruti donacija → prikaz povučenog', (
      tester,
    ) async {
      ChannelVisibility.instance.setForTest({
        _uc: channelOff(const ['channel_enabled'], status: 'withdrawn'),
      });
      await tester.pumpWidget(_app(guard(ChannelKey.donations)));
      await tester.pumpAndSettle();
      expect(find.text('ZID'), findsNothing);
      expect(find.byType(ChannelGoneView), findsOneWidget);
    });
  });

  // FollowButton crta zvonce samo uz PersonChannelFlag + PushTopics +
  // praćenje; u widget testu se zvonce nije pojavilo ni BEZ postavki, pa je
  // ovdje provjeren isti uvjet koji `_bell` čita (`channelAllows`).
  group('push_notifications — uvjet zvonca u FollowButtonu', () {
    setUp(() {
      channelCache.seedIndexForTest(
        const ChannelIndex(
          version: '1',
          channelCount: 1,
          channels: [
            ChannelSummary(
              id: 'kanal',
              name: 'Kanal',
              youtubeChannelUrl: 'https://www.youtube.com/channel/$_uc',
              youtubeChannelId: _uc,
              videoCount: 1,
              totalDurationSeconds: 1,
            ),
          ],
        ),
      );
    });

    test('bez retka postavki: zvonce se nudi', () {
      expect(
        channelCache.channelAllows('kanal', ChannelKey.pushNotifications),
        isTrue,
      );
    });

    test('isključen: zvonce se ne nudi, ostali ključevi rade', () {
      ChannelVisibility.instance.setForTest({
        _uc: channelOff(const ['push_notifications']),
      });
      expect(
        channelCache.channelAllows('kanal', ChannelKey.pushNotifications),
        isFalse,
      );
      expect(channelCache.channelAllows('kanal', ChannelKey.donations), isTrue);
    });
  });
}
