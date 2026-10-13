// Smoke test na pravom uređaju: aplikacija se digne i prođe glavne ekrane
// bez Flutter greške i bez rušenja. Plan i zašto baš ove rute:
// docs/plans/2026-10-13-smoke-testovi-na-uredajima.md.
//
// Pokreni (defineovi iz .env, kao store build):
//   ./scripts/smoke-device.sh                # prvi spojeni uređaj
//   ./scripts/smoke-device.sh <device-id>
//
// Testovi idu na živi CDN i backend, pa traže mrežu.
//
// Namjerno JEDAN testWidgets: runPodcastApp() inicijalizira Supabase,
// audio_service i ostale singletone, a oni se ne smiju inicijalizirati
// dvaput u istom procesu.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:domovina_ai/main.dart' as app;

/// Epizoda s punim AI sadržajem i `video_h264.mp4` (provjereno 13.10.2026.).
const kEpisodeId = 'H-p2Hl6x7I0';
const kChannelSlug = '40-dana-za-zivot';
const kPersonSlug = 'marko-matijasevic';

/// Greške koje dolaze od mreže, a ne od koda aplikacije (slika nije
/// stigla, CDN je spor). Smoke traži pad aplikacije, ne stanje mreže.
bool _isNetworkNoise(FlutterErrorDetails d) {
  final s = d.exception.toString();
  return s.contains('NetworkImageLoadException') ||
      s.contains('HttpException') ||
      s.contains('SocketException') ||
      s.contains('ClientException') ||
      s.contains('HandshakeException');
}

Future<bool> _waitForNetwork(Duration timeout) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    try {
      final r = await InternetAddress.lookup('cdn.domovina.ai');
      if (r.isNotEmpty) return true;
    } on SocketException {
      // još nema mreže
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  return false;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'smoke: start, epizoda, seek, kanal, osoba, pretraga — portrait i landscape',
    (tester) async {
      // Testov handler obara test na svaku Flutter grešku. runPodcastApp ga
      // pregazi vlastitim (logira i prikaže grešku), pa ga nakon starta vratimo
      // i ispred njega stavimo aplikacijin log, da ispis ostane isti kao u
      // produkciji.
      // Svježe instalirana aplikacija na nekim uređajima prvih sekundi nema
      // mrežu (Moto Secure skenira APK nakon instalacije; izmjereno 13.10.2026.
      // na moto g86: `adb shell ping` radi, a proces aplikacije ne razrješava
      // DNS). Čekamo da mreža proradi U OVOM procesu. Ako ne proradi, to je
      // „ne mogu provjeriti” (exit 2 u skripti), ne pad aplikacije.
      final netReady = await _waitForNetwork(const Duration(seconds: 60));
      if (!netReady) {
        // ignore: avoid_print
        print('SMOKE_NO_NETWORK');
        fail('uređaj ne razrješava cdn.domovina.ai iz procesa aplikacije');
      }

      final testHandler = FlutterError.onError!;
      await app.main();
      final appHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        appHandler?.call(details);
        // Nehvaćena async greška MORA proći kroz testov handler — framework
        // inače padne na vlastitoj assertiji umjesto da prijavi grešku.
        final uncaught = details.library == 'Flutter test framework';
        if (uncaught || !_isNetworkNoise(details)) testHandler(details);
      };

      // pumpAndSettle ovdje ne radi: video, skeletoni i karuseli animiraju
      // stalno, pa „settle” nikad ne dođe. Pumpamo zadano vrijeme.
      Future<void> pumpFor(Duration d) async {
        final end = DateTime.now().add(d);
        while (DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      // Ruta se šalje istim kanalom kojim OS predaje deep link
      // (`flutter/navigation` → `pushRouteInformation`), pa smoke usput
      // provjerava i obradu deep linka.
      Future<void> openRoute(String path) async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'flutter/navigation',
          const JSONMethodCodec().encodeMethodCall(
            MethodCall('pushRouteInformation', {
              'location': path,
              'state': null,
            }),
          ),
          (_) {},
        );
      }

      String currentPath() =>
          Router.of(tester.element(find.byType(Scaffold).first))
              .routeInformationProvider!
              .value
              .uri
              .path;

      Future<void> step(
        String name,
        String? path,
        Duration wait, {
        void Function()? expectations,
      }) async {
        // ignore: avoid_print
        print('SMOKE step: $name ${path ?? ''}');
        if (path != null) await openRoute(path);
        await pumpFor(wait);
        expect(
          find.byType(ErrorWidget),
          findsNothing,
          reason: '$name: ErrorWidget na ekranu',
        );
        expectations?.call();
      }

      // Ekran epizode koji se nacrta, a ne svira, za korisnika je pokvaren —
      // a ostale provjere bi ga pustile (crni player nije ErrorWidget).
      // Pozicija mora rasti: `playing` sam po sebi ne znači da stižu frameovi.
      Future<void> expectPlayback(
        String name, {
        required int minSeconds,
      }) async {
        Duration? first;
        final end = DateTime.now().add(const Duration(seconds: 25));
        while (DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 250));
          final videos = find.byType(Video);
          if (videos.evaluate().isEmpty) continue;
          final pos = tester
              .widget<Video>(videos.first)
              .controller
              .player
              .state
              .position;
          if (pos.inSeconds < minSeconds) continue;
          first ??= pos;
          if (pos - first >= const Duration(seconds: 2)) {
            // ignore: avoid_print
            print('SMOKE playback ok: $name @${pos.inSeconds}s');
            return;
          }
        }
        fail(
          '$name: reprodukcija ne napreduje (Video '
          '${find.byType(Video).evaluate().isEmpty ? 'ne postoji' : 'stoji'}'
          ', prva pozicija ${first?.inSeconds})',
        );
      }

      // Obje orijentacije, namjerno: inače rezultat ovisi o tome kako
      // telefon leži na stolu. Landscape na mobitelu je drugi layout (split
      // hero od 600 px širine, nizak panel playera) i 13.10.2026. je na
      // iPhoneima uhvatio 5 overflowa koje portrait ne vidi.
      Future<void> pass(String o, List<DeviceOrientation> orientations) async {
        await SystemChrome.setPreferredOrientations(orientations);
        await step(
          '$o naslovnica',
          '/',
          const Duration(seconds: 12),
          expectations: () => expect(find.byType(Scaffold), findsWidgets),
        );
        await step(
          '$o epizoda',
          '/v/$kEpisodeId',
          const Duration(seconds: 15),
          expectations: () => expect(currentPath(), '/v/$kEpisodeId'),
        );
        await step(
          '$o epizoda-seek',
          '/v/$kEpisodeId/t/120',
          const Duration(seconds: 3),
        );
        await expectPlayback('$o epizoda-seek', minSeconds: 115);
        await step(
          '$o epizoda-en',
          '/v/$kEpisodeId/en',
          const Duration(seconds: 8),
        );
        await step('$o kanal', '/c/$kChannelSlug', const Duration(seconds: 8));
        await step('$o osoba', '/p/$kPersonSlug', const Duration(seconds: 8));
        await step(
          '$o pretraga',
          '/search?q=molitva',
          const Duration(seconds: 8),
        );
      }

      await pass('portrait', const [DeviceOrientation.portraitUp]);
      await pass('landscape', const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      await step('natrag-naslovnica', '/', const Duration(seconds: 5));

      FlutterError.onError = testHandler;
    },
  );
}
