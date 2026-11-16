/// Kontrakt dijeljenih kontrola reprodukcije (T2 iz
/// `docs/plans/2026-07-27-playback-overhaul.md`):
/// - brzina se vrti u krug i piše se s decimalnim separatorom JEZIKA
///   (hrvatski zarez, engleski točka) — nikad hardkodiran,
/// - prekidač pozadinske reprodukcije mijenja ikonu i potvrđuje SnackBarom,
/// - Undo pilula postoji samo dok ponuda stoji i tapom je troši.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:podcast_core/l10n/app_localizations.dart';
import 'package:podcast_core/services/background_playback.dart';
import 'package:podcast_core/services/playback_speed.dart';
import 'package:podcast_core/services/seek_undo.dart';
import 'package:podcast_core/widgets/playback_controls.dart';

Widget _wrap(Widget child, {Locale locale = const Locale('hr')}) => MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Singletoni su dijeljeni kroz cijeli fajl → svaki test kreće s 1,0× i
    // uključenom pozadinskom reprodukcijom (defaulti).
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await PlaybackSpeed.instance.setRate(1.0);
    await BackgroundPlayback.instance.setEnabled(true);
  });

  group('SpeedCycleButton', () {
    testWidgets('hrvatski piše zarez i vrti se u krug', (tester) async {
      await tester.pumpWidget(_wrap(const SpeedCycleButton()));
      await tester.pump();

      expect(find.text('1×'), findsOneWidget);

      await tester.tap(find.byType(SpeedCycleButton));
      await tester.pump();
      expect(find.text('1,25×'), findsOneWidget);
      expect(PlaybackSpeed.instance.rate, 1.25);
    });

    testWidgets('semantics label ima točno jedan „ד', (tester) async {
      final l = await AppLocalizations.delegate.load(const Locale('hr'));
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(_wrap(const SpeedCycleButton()));
      await tester.pump();
      expect(l.mediaPlaybackSpeedSet('1'), 'Brzina: 1×');
      expect(find.bySemanticsLabel(l.mediaPlaybackSpeedSet('1')),
          findsOneWidget);

      await tester.tap(find.byType(SpeedCycleButton));
      await tester.pump();
      // Brojka ide bez „ד — ključ ga već nosi; „1,25×ד bi bio bug D1.
      expect(find.bySemanticsLabel(l.mediaPlaybackSpeedSet('1,25')),
          findsOneWidget);
      expect(find.bySemanticsLabel(l.mediaPlaybackSpeedSet('1,25×')),
          findsNothing);

      handle.dispose();
    });

    testWidgets('engleski piše točku', (tester) async {
      await tester.pumpWidget(
        _wrap(const SpeedCycleButton(), locale: const Locale('en')),
      );
      await tester.pump();

      await tester.tap(find.byType(SpeedCycleButton));
      await tester.pump();
      expect(find.text('1.25×'), findsOneWidget);
    });

    testWidgets('2,0× se vrati na 1×', (tester) async {
      await PlaybackSpeed.instance.setRate(2.0);
      await tester.pumpWidget(_wrap(const SpeedCycleButton()));
      await tester.pump();
      expect(find.text('2×'), findsOneWidget);

      await tester.tap(find.byType(SpeedCycleButton));
      await tester.pump();
      expect(find.text('1×'), findsOneWidget);
    });

    testWidgets('javlja novu brzinu pozivatelju', (tester) async {
      final seen = <double>[];
      await tester.pumpWidget(
        _wrap(SpeedCycleButton(onChanged: seen.add)),
      );
      await tester.pump();

      await tester.tap(find.byType(SpeedCycleButton));
      await tester.pump();
      expect(seen, [1.25]);
    });
  });

  group('BackgroundPlaybackButton', () {
    testWidgets('tap gasi pozadinsku reprodukciju i potvrđuje SnackBarom',
        (tester) async {
      final l = await AppLocalizations.delegate.load(const Locale('hr'));

      await tester.pumpWidget(_wrap(const BackgroundPlaybackButton()));
      await tester.pump();
      expect(find.byIcon(Icons.headset), findsOneWidget);

      await tester.tap(find.byType(BackgroundPlaybackButton));
      await tester.pump();

      expect(BackgroundPlayback.instance.enabled, isFalse);
      expect(find.byIcon(Icons.headset_off), findsOneWidget);
      expect(find.text(l.mediaBackgroundPlaybackToastOff), findsOneWidget);

      // Vrati natrag — druga potvrda, druga poruka.
      await tester.tap(find.byType(BackgroundPlaybackButton));
      await tester.pump();
      expect(BackgroundPlayback.instance.enabled, isTrue);
      expect(find.text(l.mediaBackgroundPlaybackToastOn), findsOneWidget);

      // SnackBar bi inače „preživio" kraj testa (pending timer).
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  });

  group('SeekUndoPill', () {
    testWidgets('nema je bez ponude, tap je troši i vraća poziciju',
        (tester) async {
      final l = await AppLocalizations.delegate.load(const Locale('hr'));
      final positions = StreamController<Duration>.broadcast();
      addTearDown(positions.close);
      final undo = SeekUndo(positionStream: positions.stream);
      addTearDown(undo.dispose);

      Duration? undone;
      await tester.pumpWidget(
        _wrap(SeekUndoPill(undo: undo, onUndo: (d) => undone = d)),
      );
      await tester.pump();
      expect(find.byType(InkWell), findsNothing);

      // Prirodan tijek pa ručni skok naprijed → ponuda na 1:12:03.
      positions.add(const Duration(hours: 1, minutes: 12, seconds: 3));
      await tester.pump();
      positions.add(const Duration(hours: 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text(l.mediaSeekUndo('1:12:03')), findsOneWidget);

      await tester.tap(find.text(l.mediaSeekUndo('1:12:03')));
      // pumpAndSettle jer AnimatedSwitcher stari child drži do kraja fadea.
      await tester.pumpAndSettle();

      expect(undone, const Duration(hours: 1, minutes: 12, seconds: 3));
      expect(undo.undoTarget.value, isNull);
      expect(find.text(l.mediaSeekUndo('1:12:03')), findsNothing);

      // consume() otvori prozor tolerancije (1200 ms) — pusti ga da istekne,
      // inače test padne na „Timer is still pending".
      await tester.pump(const Duration(milliseconds: 1500));
    });

    testWidgets('nakon svježeg dijela postane chip; „Nastavi odavde” gasi ponudu',
        (tester) async {
      final l = await AppLocalizations.delegate.load(const Locale('hr'));
      final positions = StreamController<Duration>.broadcast();
      addTearDown(positions.close);
      final undo = SeekUndo(positionStream: positions.stream);
      addTearDown(undo.dispose);

      await tester.pumpWidget(_wrap(SeekUndoPill(undo: undo, onUndo: (_) {})));
      positions.add(const Duration(hours: 1, minutes: 23, seconds: 45));
      await tester.pump();
      positions.add(const Duration(hours: 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(l.mediaSeekUndo('1:23:45')), findsOneWidget);

      // Razgledavanje: velika pilula se skupi u chip, ali ne nestane.
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();
      expect(find.text(l.mediaSeekUndo('1:23:45')), findsNothing);
      expect(find.text('1:23:45'), findsOneWidget);

      await tester.tap(find.text(l.mediaSeekStayHere));
      await tester.pumpAndSettle();
      expect(undo.undoTarget.value, isNull);
      expect(find.text('1:23:45'), findsNothing);
    });
  });
}
