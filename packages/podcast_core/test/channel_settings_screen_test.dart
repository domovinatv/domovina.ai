/// Ekran postavki kanala (lanac `postavke-kanala/`, S4) s lažnim backendom,
/// bez mreže: 20 prekidača, glavni gasi ostale, ovisni siv s objašnjenjem,
/// log od najnovijeg, optimistični red i povrat na grešku, trajno brisanje
/// (ime, telefon, otkazivanje, stanje pri otvaranju), samo-čitanje za
/// istekli claim, i traka „donacije isključene” na ekranu kampanja.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:podcast_core/l10n/app_localizations.dart';
import 'package:podcast_core/models/channel_claim.dart';
import 'package:podcast_core/screens/ownership/channel_settings_screen.dart';
import 'package:podcast_core/services/channel_settings_service.dart';

const _uc = 'UCabcdefghijklmnopqrstuv';
const _me = 'acc-me';
const _title = 'Moj kanal';

final AppLocalizations l = lookupAppLocalizations(const Locale('hr'));

ChannelClaim _claim({
  int ageDays = 10,
  ClaimStatus status = ClaimStatus.verified,
}) => ChannelClaim(
  id: 'c1',
  accountId: _me,
  youtubeChannelId: _uc,
  channelTitle: _title,
  role: ClaimRole.primary,
  status: status,
  verifiedAt: DateTime.now().subtract(Duration(days: ageDays)),
);

/// Svi ključevi true osim navedenih.
Map<String, bool> _eff([Map<String, bool> off = const {}]) => {
  for (final k in kChannelSettingKeys) k: off[k] ?? true,
};

class FakeBackend implements ChannelSettingsBackend {
  FakeBackend({
    this.userId = _me,
    ChannelClaim? claim,
    this.settings = ChannelSettings.defaults,
    List<ChannelSettingsEvent>? log,
    this.deletion,
  }) : claim = claim ?? _claim(),
       log = log ?? [];

  String? userId;
  ChannelClaim? claim;
  ChannelSettings settings;
  List<ChannelSettingsEvent> log;
  ChannelDeletionRequest? deletion;

  /// Kad je postavljen, `setSetting` čeka ovaj completer.
  Completer<Map<String, dynamic>>? pendingSet;
  final List<(String, bool)> sets = [];
  final List<String> deletionNames = [];
  int cancels = 0;
  int logFetches = 0;

  @override
  String? get currentUserId => userId;

  @override
  Future<ChannelClaim?> myClaim(String ucId) async => claim;

  @override
  Future<ChannelSettings> fetchSettings(String ucId) async => settings;

  @override
  Future<Map<String, dynamic>> setSetting(
    String ucId,
    String key,
    bool value,
  ) async {
    sets.add((key, value));
    final c = pendingSet;
    if (c != null) return c.future;
    return _eff({key: value});
  }

  @override
  Future<List<ChannelSettingsEvent>> fetchLog(
    String ucId, {
    int limit = 50,
    int? before,
  }) async {
    logFetches++;
    return [
      for (final e in log)
        if (before == null || (e.id ?? 0) < before) e,
    ].take(limit).toList();
  }

  @override
  Future<ChannelDeletionRequest?> fetchOpenDeletionRequest(String ucId) async =>
      deletion != null && deletion!.isOpen ? deletion : null;

  @override
  Future<String> requestDeletion(String ucId, String confirmName) async {
    deletionNames.add(confirmName);
    if (confirmName != _title) {
      throw const ChannelSettingsException('confirm_name_mismatch');
    }
    deletion = ChannelDeletionRequest(
      id: 'r1',
      youtubeChannelId: ucId,
      channelTitle: _title,
      state: ChannelDeletionState.requested,
      requestedAt: DateTime.utc(2026, 11, 12, 9, 30),
    );
    log = [
      ChannelSettingsEvent(
        id: 100,
        kind: ChannelSettingsEventKind.deletionRequested,
        accountId: _me,
        role: 'primary',
        createdAt: DateTime.utc(2026, 11, 12, 9, 30),
      ),
      ...log,
    ];
    return 'r1';
  }

  @override
  Future<String> cancelDeletion(String ucId) async {
    cancels++;
    deletion = null;
    return 'r1';
  }
}

ChannelSettingsEvent _ev(
  int id, {
  String key = 'donations',
  bool from = true,
  bool to = false,
  String? account,
  String role = 'primary',
  String source = 'app',
  ChannelSettingsEventKind kind = ChannelSettingsEventKind.setting,
}) => ChannelSettingsEvent(
  id: id,
  kind: kind,
  key: kind == ChannelSettingsEventKind.setting ? key : null,
  oldValue: kind == ChannelSettingsEventKind.setting ? from : null,
  newValue: kind == ChannelSettingsEventKind.setting ? to : null,
  accountId: account,
  role: source == 'app' ? role : null,
  source: source,
  createdAt: DateTime.utc(2026, 11, id.clamp(1, 28), 10),
);

Future<void> _pump(
  WidgetTester tester,
  FakeBackend backend, {
  Future<bool> Function(Uri)? launcher,
  Size size = const Size(1000, 9000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('hr'),
      home: ChannelSettingsScreen(
        youtubeChannelId: _uc,
        backend: backend,
        launcher: launcher,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

SwitchListTile _tile(WidgetTester tester, String key) =>
    tester.widget<SwitchListTile>(find.byKey(ValueKey('channel-setting-$key')));

void main() {
  // Stvarno „stane bez scrolla” se ne da izmjeriti ovdje: testni font
  // (Ahem) je širi od Intera pa je svaki redak viši nego u pregledniku.
  // Test zato čuva broj stupaca po širini; visinu provjeri u pregledniku.
  for (final (width, columns) in [(390.0, 1), (1000.0, 2), (1440.0, 3)]) {
    testWidgets('širina $width: $columns stupac/a prekidača', (tester) async {
      await _pump(tester, FakeBackend(), size: Size(width, 9000));
      final xs = {
        for (final k in kChannelSettingKeys.skip(1))
          tester.getRect(find.byKey(ValueKey('channel-setting-$k'))).left,
      };
      expect(xs, hasLength(columns));
    });
  }

  testWidgets('točno 20 prekidača, svi uključeni i omogućeni', (tester) async {
    await _pump(tester, FakeBackend());
    expect(find.byType(SwitchListTile), findsNWidgets(20));
    for (final k in kChannelSettingKeys) {
      final t = _tile(tester, k);
      expect(t.value, isTrue, reason: k);
      expect(t.onChanged, isNotNull, reason: k);
    }
    // Naslovi skupina i napomena ispod reprodukcije s CDN-a.
    expect(find.text(l.channelSettingsGroupPresence), findsOneWidget);
    expect(find.text(l.channelSettingsGroupMoney), findsOneWidget);
    expect(find.text(l.channelSettingsCdnPlaybackNote), findsOneWidget);
  });

  testWidgets('glavni isključen: ostalih 19 vidljivo i onemogućeno', (
    tester,
  ) async {
    await _pump(
      tester,
      FakeBackend(
        settings: ChannelSettings(
          raw: const {'channel_enabled': false},
          effective: {for (final k in kChannelSettingKeys) k: false},
        ),
      ),
    );
    final master = _tile(tester, 'channel_enabled');
    expect(master.value, isFalse);
    expect(master.onChanged, isNotNull);
    for (final k in kChannelSettingKeys.skip(1)) {
      final t = _tile(tester, k);
      expect(t.onChanged, isNull, reason: k);
      expect(t.value, isTrue, reason: '$k: prikaz je SIROVA vrijednost');
    }
    expect(find.text(l.channelSettingsBlockedByMaster), findsNWidgets(19));
  });

  testWidgets(
    'ovisni prekidač onemogućen s objašnjenjem koji ga roditelj gasi',
    (tester) async {
      const aiOff = {
        'transcript_subtitles': false,
        'article_summary': false,
        'english_translation': false,
        'magisterium': false,
        'highlights_reels': false,
        'persons_mentions': false,
        'news_portal': false,
        'ai_assistants': false,
        'ebook': false,
        'share_clips': false,
      };
      await _pump(
        tester,
        FakeBackend(
          settings: ChannelSettings(
            raw: const {'transcript_subtitles': false},
            effective: _eff(aiOff),
          ),
        ),
      );
      final parent = _tile(tester, 'transcript_subtitles');
      expect(parent.value, isFalse);
      expect(parent.onChanged, isNotNull);

      final ebook = _tile(tester, 'ebook');
      expect(ebook.value, isTrue);
      expect(ebook.onChanged, isNull);
      final why = l.channelSettingsBlockedByParent(
        l.channelSettingsKeyTranscriptSubtitles,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('channel-setting-ebook')),
          matching: find.text(why),
        ),
        findsOneWidget,
      );
      // 9 ovisnih (7 AI + ebook + share_clips) nosi isto objašnjenje.
      expect(find.text(why), findsNWidgets(9));
      // Neovisni ostaju omogućeni.
      expect(_tile(tester, 'donations').onChanged, isNotNull);
      expect(_tile(tester, 'cdn_playback').onChanged, isNotNull);
    },
  );

  testWidgets('članak isključen: Magisterium siv zbog članka', (tester) async {
    await _pump(
      tester,
      FakeBackend(
        settings: ChannelSettings(
          raw: const {'article_summary': false},
          effective: _eff(const {
            'article_summary': false,
            'ebook': false,
            'magisterium': false,
            'english_translation': false,
            'share_clips': false,
            'news_portal': false,
          }),
        ),
      ),
    );
    expect(_tile(tester, 'magisterium').onChanged, isNull);
    expect(_tile(tester, 'highlights_reels').onChanged, isNotNull);
    expect(
      find.text(
        l.channelSettingsBlockedByParent(l.channelSettingsKeyArticleSummary),
      ),
      findsNWidgets(5),
    );
  });

  testWidgets('log je poredan od najnovijeg, s ulogom i „ti”', (tester) async {
    await _pump(
      tester,
      FakeBackend(
        log: [
          _ev(1, key: 'ebook', account: 'netko'),
          _ev(3, key: 'donations', account: _me),
          _ev(
            2,
            source: 'phone',
            kind: ChannelSettingsEventKind.deletionPhoneConfirmed,
          ),
        ],
      ),
    );
    final y3 = tester
        .getTopLeft(find.byKey(const ValueKey('channel-settings-log-3')))
        .dy;
    final y2 = tester
        .getTopLeft(find.byKey(const ValueKey('channel-settings-log-2')))
        .dy;
    final y1 = tester
        .getTopLeft(find.byKey(const ValueKey('channel-settings-log-1')))
        .dy;
    expect(y3, lessThan(y2));
    expect(y2, lessThan(y1));

    expect(
      find.text(
        l.channelSettingsLogSettingChange(
          l.channelSettingsKeyDonations,
          l.channelSettingsValueOff,
          l.channelSettingsValueOn,
        ),
      ),
      findsOneWidget,
    );
    Finder sub(int id, String prefix) => find.descendant(
      of: find.byKey(ValueKey('channel-settings-log-$id')),
      matching: find.textContaining(prefix),
    );
    expect(
      sub(3, l.channelSettingsWhoYou(l.channelSettingsRoleOwner)),
      findsOneWidget,
    );
    expect(sub(2, l.channelSettingsRoleOperator), findsOneWidget);
    expect(sub(1, '${l.channelSettingsRoleOwner} ·'), findsOneWidget);
    expect(
      find.text(l.channelSettingsLogDeletionPhoneConfirmed),
      findsOneWidget,
    );
  });

  testWidgets('optimistično: red „sprema se”, pa povrat i SnackBar na grešku', (
    tester,
  ) async {
    final backend = FakeBackend()..pendingSet = Completer();
    await _pump(tester, backend);

    await tester.tap(find.byKey(const ValueKey('channel-setting-donations')));
    await tester.pump();
    expect(_tile(tester, 'donations').value, isFalse);
    expect(
      find.byKey(const ValueKey('channel-settings-log-pending-donations')),
      findsOneWidget,
    );
    expect(find.text(l.channelSettingsLogSaving), findsOneWidget);
    expect(backend.sets, [('donations', false)]);

    backend.pendingSet!.completeError(
      const ChannelSettingsException('not_owner'),
    );
    await tester.pump();
    await tester.pump();
    expect(_tile(tester, 'donations').value, isTrue);
    expect(
      find.byKey(const ValueKey('channel-settings-log-pending-donations')),
      findsNothing,
    );
    expect(find.text(l.channelSettingsErrorNotOwner), findsOneWidget);
  });

  testWidgets(
    'optimistično: uspjeh uzima efektivno stanje i ponovno čita log',
    (tester) async {
      final backend = FakeBackend()..pendingSet = Completer();
      await _pump(tester, backend);
      final fetchesBefore = backend.logFetches;

      await tester.tap(
        find.byKey(const ValueKey('channel-setting-article_summary')),
      );
      await tester.pump();
      expect(_tile(tester, 'ebook').onChanged, isNotNull);

      backend.log = [_ev(7, key: 'article_summary', account: _me)];
      backend.pendingSet!.complete(
        _eff(const {
          'article_summary': false,
          'ebook': false,
          'magisterium': false,
          'english_translation': false,
          'share_clips': false,
          'news_portal': false,
        }),
      );
      await tester.pumpAndSettle();
      expect(backend.logFetches, fetchesBefore + 1);
      expect(_tile(tester, 'article_summary').value, isFalse);
      // Efektivno iz odgovora: ebook je sad siv.
      expect(_tile(tester, 'ebook').onChanged, isNull);
      expect(
        find.byKey(
          const ValueKey('channel-settings-log-pending-article_summary'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('channel-settings-log-7')),
        findsOneWidget,
      );
    },
  );

  testWidgets('brisanje: gumb tek uz točno ime, pa telefon i tel: poveznica', (
    tester,
  ) async {
    final launched = <Uri>[];
    final backend = FakeBackend();
    await _pump(
      tester,
      backend,
      launcher: (u) async {
        launched.add(u);
        return true;
      },
    );
    ButtonStyleButton button() => tester.widget<ButtonStyleButton>(
      find.byKey(const ValueKey('channel-settings-delete-button')),
    );
    expect(button().onPressed, isNull);

    final field = find.byKey(const ValueKey('channel-settings-delete-name'));
    await tester.enterText(field, 'Moj kana');
    await tester.pump();
    expect(button().onPressed, isNull);
    await tester.enterText(field, 'moj kanal');
    await tester.pump();
    expect(button().onPressed, isNull);
    await tester.enterText(field, '  $_title ');
    await tester.pump();
    expect(button().onPressed, isNotNull);

    await tester.tap(
      find.byKey(const ValueKey('channel-settings-delete-button')),
    );
    await tester.pumpAndSettle();
    expect(backend.deletionNames, [_title]);
    expect(field, findsNothing);
    expect(
      find.byKey(const ValueKey('channel-settings-deletion-requested')),
      findsOneWidget,
    );
    expect(find.text(l.channelSettingsDeleteCallToFinish), findsOneWidget);
    expect(find.text(kChannelDeletionPhoneDisplay), findsOneWidget);
    expect(find.text(l.channelSettingsLogDeletionRequested), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('channel-settings-phone-link')));
    await tester.pump();
    expect(launched, [Uri.parse('tel:+385989679022')]);
  });

  testWidgets('otkazivanje vraća obrazac', (tester) async {
    final backend = FakeBackend(
      deletion: ChannelDeletionRequest(
        id: 'r1',
        youtubeChannelId: _uc,
        state: ChannelDeletionState.requested,
        requestedAt: DateTime.utc(2026, 11, 12, 9),
      ),
    );
    await _pump(tester, backend);
    expect(
      find.byKey(const ValueKey('channel-settings-delete-name')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('channel-settings-cancel-deletion')),
    );
    await tester.pumpAndSettle();
    expect(backend.cancels, 1);
    expect(
      find.byKey(const ValueKey('channel-settings-delete-name')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('channel-settings-phone-link')),
      findsNothing,
    );
    expect(find.text(l.channelSettingsDeleteCancelledSnack), findsOneWidget);
  });

  testWidgets('stanje zahtjeva učitano pri otvaranju', (tester) async {
    await _pump(
      tester,
      FakeBackend(
        deletion: ChannelDeletionRequest(
          id: 'r1',
          youtubeChannelId: _uc,
          state: ChannelDeletionState.requested,
          requestedAt: DateTime.utc(2026, 11, 12, 9),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('channel-settings-deletion-requested')),
      findsOneWidget,
    );
    expect(find.text(kChannelDeletionPhoneDisplay), findsOneWidget);
    expect(
      find.byKey(const ValueKey('channel-settings-cancel-deletion')),
      findsOneWidget,
    );
  });

  testWidgets('poziv potvrđen: brisanje slijedi, nema otkazivanja', (
    tester,
  ) async {
    await _pump(
      tester,
      FakeBackend(
        deletion: ChannelDeletionRequest(
          id: 'r1',
          youtubeChannelId: _uc,
          state: ChannelDeletionState.phoneConfirmed,
          requestedAt: DateTime.utc(2026, 11, 12, 9),
          phoneConfirmedAt: DateTime.utc(2026, 11, 12, 11),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('channel-settings-deletion-confirmed')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('channel-settings-cancel-deletion')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('channel-settings-delete-name')),
      findsNothing,
    );
  });

  testWidgets('istekli claim (> 90 dana): samo za čitanje, log vidljiv', (
    tester,
  ) async {
    await _pump(
      tester,
      FakeBackend(
        claim: _claim(ageDays: 120),
        log: [_ev(5, account: _me)],
      ),
    );
    expect(find.text(l.channelSettingsReverifyBody), findsOneWidget);
    expect(
      find.byKey(const ValueKey('channel-settings-reverify')),
      findsOneWidget,
    );
    for (final k in kChannelSettingKeys) {
      expect(_tile(tester, k).onChanged, isNull, reason: k);
    }
    expect(
      find.byKey(const ValueKey('channel-settings-log-5')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('channel-settings-delete-name')),
      findsNothing,
    );
  });

  testWidgets('odjavljen i nepotvrđen claim: poruka, bez prekidača', (
    tester,
  ) async {
    await _pump(tester, FakeBackend(userId: null));
    expect(find.text(l.channelSettingsSignIn), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await _pump(
      tester,
      FakeBackend(claim: _claim(status: ClaimStatus.pending)),
    );
    expect(find.text(l.channelSettingsNotOwner), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);
  });

  group('kampanje: traka „donacije isključene”', () {
    Future<void> pumpBanner(WidgetTester tester, ChannelSettings s) =>
        tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('hr'),
            home: Scaffold(
              body: ChannelDonationsOffBanner(
                youtubeChannelId: _uc,
                settings: s,
              ),
            ),
          ),
        );

    testWidgets('donacije efektivno isključene: traka i gumb na postavke', (
      tester,
    ) async {
      await pumpBanner(
        tester,
        ChannelSettings(
          raw: const {'channel_enabled': false},
          effective: _eff(const {'donations': false}),
        ),
      );
      expect(find.text(l.channelSettingsDonationsOffBanner), findsOneWidget);
      expect(find.text(l.channelSettingsOpenAction), findsOneWidget);
      expect(channelSettingsLocation(_uc), '/account/channels/$_uc/postavke');
    });

    testWidgets('donacije uključene: nema trake', (tester) async {
      await pumpBanner(tester, ChannelSettings.defaults);
      expect(
        find.byKey(const ValueKey('channel-donations-off-banner')),
        findsNothing,
      );
    });
  });
}
