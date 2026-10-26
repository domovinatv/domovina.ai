import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:podcast_core/brand/app_brand.dart';
import 'package:podcast_core/brand/domovina_brand.dart';
import 'package:podcast_core/l10n/app_localizations.dart';
import 'package:podcast_core/models/episode_reels.dart';
import 'package:podcast_core/widgets/reel_share_sheet.dart';

void main() {
  setUp(() => AppBrand.init(domovinaBrand));

  const reel = EpisodeReel(
    rank: 1,
    startSec: 3149.4,
    endSec: 3215.2,
    title: 'Što je rekao o obitelji?',
    render: EpisodeReelRender(
      url: 'https://cdn.domovina.ai/data/abc/reels/1-deadbeef.mp4',
      clipStartSec: 3149.4,
      durationSec: 65.8,
    ),
  );

  testWidgets('list nudi 9:16 datoteku i 16:9 isječak s cuttera', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('hr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showReelShareSheet(
                context,
                reel: reel,
                youtubeId: 'abc',
                episodeUrl: 'https://domovina.ai/v/abc/t/3149',
                messenger: ScaffoldMessenger.of(context),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // Preuzimanje u testu ne završi (spinner), pa nema pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('(9:16)'), findsOneWidget);
    expect(find.text('Kopiraj vezu na video'), findsOneWidget);
    expect(find.text('Preuzmi vodoravni isječak (16:9)'), findsOneWidget);

    await tester.tap(find.text('Kopiraj vezu na vodoravni isječak (16:9)'));
    await tester.pump(const Duration(seconds: 1));
    // Raspon: početak zaokružen dolje, kraj gore — cijeli trenutak stane.
    expect(copied, 'https://cutter.domovina.ai/clip/abc/r/3149-3216.mp4');
  });
}
