/// Gumb za cast na televizor postoji samo kad preglednik javi uređaj.
///
/// Na VM-u (i na svakom nativeu) `RemotePlayback` nikad ne dobije cilj, pa
/// gumb mora biti prazan — mrtav gumb koji otvori prazan izbornik je gori od
/// nikakvog. Plan: `docs/plans/2026-10-17-cast-na-tv.md` (iteracija B).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:podcast_core/l10n/app_localizations.dart';
import 'package:podcast_core/services/remote_playback.dart';
import 'package:podcast_core/widgets/playback_controls.dart';

void main() {
  testWidgets('bez uređaja u mreži gumba nema', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('hr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: Center(child: RemotePlaybackButton())),
      ),
    );

    expect(RemotePlayback.instance.target, isNull);
    expect(RemotePlayback.instance.state, RemoteState.disconnected);
    expect(find.byType(IconButton), findsNothing);
  });
}
