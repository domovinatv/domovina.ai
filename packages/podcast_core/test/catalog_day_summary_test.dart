/// Brojač na vrhu `/dani/:datum` broji po pravilu podcast.domovina.ai/dani/
/// (`build-catalog.mjs`): kanal po slugu, epizoda bez kanala kao zaseban
/// kanal, minute po epizodi zaokružene, od 90 min sati.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:podcast_core/l10n/app_localizations_en.dart';
import 'package:podcast_core/l10n/app_localizations_hr.dart';
import 'package:podcast_core/screens/catalog_day/catalog_day_summary.dart';

import 'support/fake_catalog_days.dart';

void main() {
  final hr = AppLocalizationsHr();
  final en = AppLocalizationsEn();

  test('kanal po slugu; epizoda bez kanala je zaseban kanal', () {
    final s = CatalogDaySummary.of([
      fakeDayCard('a', channel: 'Radio', durationSeconds: 2770),
      fakeDayCard('b', channel: 'Radio', durationSeconds: 2770),
      fakeDayCard('c', channel: 'Tribina', durationSeconds: 3780),
      fakeDayCard('d', durationSeconds: 1800),
      fakeDayCard('e'),
    ]);
    expect(s.episodes, 5);
    expect(s.channels, 4);
    expect(s.minutes, 46 + 46 + 63 + 30);
    expect(s.label(hr), '5 novih epizoda iz 4 kanala · 3 h slušanja');
    expect(s.label(en), '5 new episodes from 4 channels · 3 h of listening');
  });

  test('jedan kanal s više podcasta broji se po podcastu (HRT, 19. 11.)', () {
    final s = CatalogDaySummary.of([
      fakeDayCard('a', channel: 'hrt', podcast: 'hrt-na-rubu-znanosti'),
      fakeDayCard('b', channel: 'hrt', podcast: 'occamova-britva'),
      fakeDayCard('c', channel: 'hrt', podcast: 'occamova-britva'),
      fakeDayCard('d', channel: 'hrt', podcast: 'viza'),
      fakeDayCard('e', channel: 'tribina'),
    ]);
    expect(s.channels, 4);
  });

  test('ispod 90 min minute; plural; bez trajanja nema dijela o slušanju', () {
    expect(
      CatalogDaySummary.of([
        fakeDayCard('a', channel: 'X', durationSeconds: 89 * 60),
      ]).label(hr),
      '1 nova epizoda iz 1 kanala · 89 min slušanja',
    );
    expect(
      CatalogDaySummary.of([
        fakeDayCard('a', channel: 'X'),
        fakeDayCard('b', channel: 'Y'),
        fakeDayCard('c', channel: 'Z'),
      ]).label(hr),
      '3 nove epizode iz 3 kanala',
    );
  });

  test('20. 11. 2026.: 30 epizoda, 28 kanala, 30 h kao na podcast.domovina.ai', () {
    // 24 sluga (dva s po dvije epizode) + 4 epizode bez kanala.
    final cards = [
      for (var i = 0; i < 22; i++)
        fakeDayCard('s$i', channel: 'k$i', durationSeconds: 3600),
      for (var i = 0; i < 2; i++) ...[
        fakeDayCard('d${i}a', channel: 'dup$i', durationSeconds: 3600),
        fakeDayCard('d${i}b', channel: 'dup$i', durationSeconds: 3600),
      ],
      for (var i = 0; i < 4; i++) fakeDayCard('n$i', durationSeconds: 3600),
    ];
    expect(
      CatalogDaySummary.of(cards).label(hr),
      '30 novih epizoda iz 28 kanala · 30 h slušanja',
    );
  });
}
