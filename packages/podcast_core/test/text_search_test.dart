import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_core/l10n/app_localizations.dart';
import 'package:podcast_core/utils/text_search.dart';
import 'package:podcast_core/widgets/episode_age.dart';

// Vrati podstringove [text]-a koji bi bili highlightani za [query].
List<String> hl(String text, String query) =>
    highlightRanges(text, query).map((r) => text.substring(r[0], r[1])).toList();

void main() {
  group('foldText', () {
    test('lowercase + fold dijakritika, ista duljina', () {
      expect(foldText('Čušpajž'), 'cuspajz');
      expect(foldText('Žižek'), 'zizek');
      expect(foldText('ĐĆŠ').length, 3);
    });
  });

  group('foldText — ASCII brzi put', () {
    test('isto kao lowercase za ASCII, dijakritici foldani', () {
      expect(foldText('Fra Stjepan BRČINA 2026!'), 'fra stjepan brcina 2026!');
      const s = 'Dobrodošlica i predstavljanje Đ';
      expect(foldText(s).length, s.length);
    });
  });

  group('normalizeQuery / queryTokens', () {
    test('razmak na kraju ne mijenja upit', () {
      expect(normalizeQuery('fra '), 'fra');
      expect(normalizeQuery('  fra   stjepan '), 'fra stjepan');
    });

    test('tokeni su foldani', () {
      expect(queryTokens('Fra  Šterc'), ['fra', 'sterc']);
      expect(queryTokens('   '), isEmpty);
    });

    test('localMatchScoreFolded == localMatchScore', () {
      const hay = 'POPcast | Fra Stjepan Brčina - duhovni reset';
      for (final q in ['fra', 'fra stjepan', 'brcina', 'xyz']) {
        expect(localMatchScoreFolded(queryTokens(q), foldText(hay)),
            localMatchScore(q, hay));
      }
    });
  });

  group('highlightRanges — sklonjeni oblici', () {
    test('upit "demografska obnova" hvata "demografsku obnovu"', () {
      final m = hl('predlaže modele za demografsku obnovu danas', 'demografska obnova');
      expect(m, containsAll(<String>['demografsku', 'obnovu']));
    });

    test('dijakritik-neosjetljivo: "sterc" → "Šterc"', () {
      expect(hl('Profesor Šterc kaže', 'sterc'), contains('Šterc'));
    });

    test('ne highlighta nepovezane riječi', () {
      expect(hl('potpuno druga rečenica', 'demografija'), isEmpty);
    });

    test('kratki token egzaktno', () {
      expect(hl('EU i euro', 'eu'), containsAll(<String>['EU', 'euro']));
    });
  });

  group('snippetAround', () {
    test('centrira prozor oko pogotka s elipsom', () {
      final long = '${'a' * 200} demografska obnova ${'b' * 200}';
      final s = snippetAround(long, 'demografska obnova');
      expect(s.contains('demografska obnova'), isTrue);
      expect(s.startsWith('…'), isTrue);
      expect(s.endsWith('…'), isTrue);
      expect(s.length, lessThan(long.length));
    });

    test('kratak tekst se vraća cijel', () {
      expect(snippetAround('kratko demografska', 'demografska'), 'kratko demografska');
    });
  });

  group('localMatchScore', () {
    test('AND semantika + dijakritici', () {
      expect(localMatchScore('zizek', 'Slavoj Žižek o ideologiji') > 0, isTrue);
      expect(localMatchScore('nepostojeci', 'Slavoj Žižek'), 0);
    });

    test('„dj" bez kvačica nalazi „đ"', () {
      expect(localMatchScore('medjugorje', 'Marija i Međugorje') > 0, isTrue);
      expect(localMatchScore('djeca', 'Djeca nisu kriva') > 0, isTrue);
    });
  });

  group('contentQuery', () {
    test('miče funkcijske riječi, čuva dijakritike', () {
      expect(contentQuery('što je rekao papa o ratu u ukrajini'),
          'rekao papa ratu ukrajini');
      expect(contentQuery('Zašto mladi napuštaju Crkvu'),
          'mladi napuštaju Crkvu');
      expect(contentQuery('život nakon smrti'), 'život nakon smrti');
    });

    test('upit samo od funkcijskih riječi ostaje kakav jest', () {
      expect(contentQuery('što je to'), 'što je to');
    });

    test('broj sadržajnih riječi', () {
      expect(contentWordCount('damir sabol'), 2);
      expect(contentWordCount('kako se nositi s tugom nakon smrti djeteta'), 5);
    });
  });

  group('episode age', () {
    test('label gradacija', () {
      final l = lookupAppLocalizations(const Locale('hr'));
      expect(episodeAgeLabel(0, l), 'danas');
      expect(episodeAgeLabel(1, l), 'jučer');
      expect(episodeAgeLabel(3, l), 'prije 3 dana');
      expect(episodeAgeLabel(10, l), 'prije tjedan');
      expect(episodeAgeLabel(90, l), 'prije 3 mj.');
      expect(episodeAgeLabel(800, l), 'prije 2 god.');
    });

    test('boja: novije zelena, staro crvena', () {
      expect(episodeAgeColor(5), isNot(episodeAgeColor(500)));
      expect(episodeAgeColor(5), const Color(0xFF2E7D32));
      expect(episodeAgeColor(500), const Color(0xFFC62828));
    });

    test('parse + age days', () {
      final d = parseEpisodeDate('2024-05-14');
      expect(d, isNotNull);
      final days = episodeAgeDays(d!, now: DateTime(2024, 5, 24));
      expect(days, 10);
    });

    test('null/loš datum', () {
      expect(parseEpisodeDate(null), isNull);
      expect(parseEpisodeDate('  '), isNull);
    });
  });
}
