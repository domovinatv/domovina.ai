import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:podcast_core/brand/app_brand.dart';
import 'package:podcast_core/brand/domovina_brand.dart';
import 'package:podcast_core/l10n/app_localizations.dart';
import 'package:podcast_core/models/podcast_info.dart';
import 'package:podcast_core/router/nav.dart';
import 'package:podcast_core/services/channel_feature_gate.dart';
import 'package:podcast_core/services/channel_settings_service.dart';
import 'package:podcast_core/services/channel_visibility.dart';
import 'package:podcast_core/services/data_service.dart';
import 'package:podcast_core/services/episode_language.dart';
import 'package:podcast_core/services/share_links.dart';
import 'package:podcast_core/widgets/clip_share_sheet.dart';
import 'package:podcast_core/widgets/episode_channel_owner.dart';

/// Postavke kanala na ekranu epizode (S5): površine koje traže widget —
/// povučen/obrisan prikaz, isječci, engleski share URL, tekst umjesto ocjene.
const _uc = 'UCXXhnehl2pss0uYdfLRDtyw';

EpisodeData _episode({
  String status = 'active',
  DateTime? at,
  List<String> off = const [],
}) => EpisodeData(
  youtubeId: 'abcdefghijk',
  info: PodcastInfo.fromJson({'id': 'abcdefghijk', 'channel_id': _uc}),
  videoUri: '',
  mediaKind: EpisodeMediaKind.none,
  channelSettings: status == 'active' && off.isEmpty
      ? null
      : channelOff(off, status: status, deletedAt: at),
);

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('hr'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

void main() {
  setUp(() {
    AppBrand.init(domovinaBrand);
    DataService.resetMemoryForTest();
    ChannelVisibility.instance = ChannelVisibility(
      catalog: ChannelSettingsCatalog(baseUrl: ''),
    );
  });
  tearDown(() {
    DataService.resetMemoryForTest();
    ChannelVisibility.instance = ChannelVisibility();
  });

  group('channel_enabled na /v/', () {
    testWidgets('povučen: naslov, YouTube poveznica, bez playera', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(EpisodeChannelGoneScreen(data: _episode(status: 'withdrawn'))),
      );
      final l = await AppLocalizations.delegate.load(const Locale('hr'));
      expect(find.text(l.channelGoneWithdrawn), findsOneWidget);
      expect(find.text(l.channelGoneOpenYouTube), findsOneWidget);
    });

    testWidgets('obrisan: datum, bez YouTube poveznice', (tester) async {
      await tester.pumpWidget(
        _app(
          EpisodeChannelGoneScreen(
            data: _episode(status: 'deleted', at: DateTime(2026, 11, 12, 12)),
          ),
        ),
      );
      final l = await AppLocalizations.delegate.load(const Locale('hr'));
      expect(find.text(l.channelGoneDeleted('12. 11. 2026.')), findsOneWidget);
      expect(find.text(l.channelGoneOpenYouTube), findsNothing);
    });

    test('bez postavki epizoda nije povučena', () {
      expect(_episode().isChannelGone, isFalse);
      expect(_episode().featureOn(EpisodeKey.donations), isTrue);
    });
  });

  group('share_clips', () {
    Future<void> pumpClip(WidgetTester tester) => tester.pumpWidget(
      _app(
        const Scaffold(
          body: ClipShareButton(
            videoId: 'clip0000001',
            startSec: 10,
            endSec: 70,
            title: 'Poglavlje',
          ),
        ),
      ),
    );

    testWidgets('isključen: nema gumba za isječak', (tester) async {
      ChannelFeatureGate.rememberKnown('clip0000001', _uc);
      ChannelVisibility.instance.setForTest({
        _uc: channelOff([EpisodeKey.shareClips]),
      });
      await pumpClip(tester);
      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('bez postavki: gumb je tu', (tester) async {
      ChannelFeatureGate.rememberKnown('clip0000001', _uc);
      await pumpClip(tester);
      expect(find.byType(IconButton), findsOneWidget);
    });
  });

  group('english_translation', () {
    test('isključen: episodeShareUrl ne vraća /en', () {
      ChannelFeatureGate.rememberKnown('enoff000001', _uc);
      ChannelVisibility.instance.setForTest({
        _uc: channelOff([EpisodeKey.englishTranslation]),
      });
      expect(
        episodeShareUrl('enoff000001', seconds: 90, lang: EpisodeLanguage.en),
        allOf(endsWith('/t/90'), isNot(endsWith('/en'))),
      );
    });

    test('bez postavki: /en ostaje', () {
      ChannelFeatureGate.rememberKnown('enon0000001', _uc);
      expect(
        episodeShareUrl('enon0000001', seconds: 90, lang: EpisodeLanguage.en),
        endsWith('/t/90/en'),
      );
    });

    test('withoutEnSuffix: /en se skida, ostalo ostaje (odluka 503)', () {
      expect(withoutEnSuffix('/v/abc/en'), '/v/abc');
      expect(withoutEnSuffix('/v/abc/t/30/en?p=ivo'), '/v/abc/t/30?p=ivo');
      expect(withoutEnSuffix('/m/abc/en'), '/m/abc');
      expect(withoutEnSuffix('/v/abc'), '/v/abc');
    });
  });

  group('magisterium', () {
    testWidgets('isključen: tekst „Vlasnik je isključio procjenu”', (
      tester,
    ) async {
      final data = _episode(off: [EpisodeKey.magisterium]);
      expect(episodeMagisteriumOffByOwner(data), isTrue);
      await tester.pumpWidget(
        _app(const Scaffold(body: MagisteriumOffNotice())),
      );
      final l = await AppLocalizations.delegate.load(const Locale('hr'));
      expect(find.text(l.magisteriumOffByOwner), findsOneWidget);
    });

    test('bez postavki: nema teksta', () {
      expect(episodeMagisteriumOffByOwner(_episode()), isFalse);
    });
  });

  group('donations / persons_mentions / cdn_playback (odluka iz snimke)', () {
    test('isključeni ključevi gase površine, ostali ostaju', () {
      final data = _episode(
        off: [
          EpisodeKey.donations,
          EpisodeKey.personsMentions,
          EpisodeKey.cdnPlayback,
        ],
      );
      expect(data.featureOn(EpisodeKey.donations), isFalse);
      expect(data.featureOn(EpisodeKey.personsMentions), isFalse);
      expect(episodeYouTubeOnly(data), isTrue);
      expect(data.featureOn(EpisodeKey.ebook), isTrue);
      expect(episodeYouTubeOnly(_episode()), isFalse);
    });
  });
}
