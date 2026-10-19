import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_core/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:podcast_core/widgets/citation_helpers.dart';

void main() {
  final hr = lookupAppLocalizations(const Locale('hr'));
  final en = lookupAppLocalizations(const Locale('en'));

  test('goli broj je paragraf', () {
    expect(citationRefLabel('74', hr), 'br. 74');
    expect(citationRefLabel('74', en), 'no. 74');
  });

  test('pageN iz Acta Apostolicae Sedis je stranica', () {
    expect(citationRefLabel('page65', hr), 'str. 65');
    expect(citationRefLabel('page65', en), 'p. 65');
  });

  test('para-N je paragraf', () {
    expect(citationRefLabel('para-3', hr), 'br. 3');
  });

  test('naslov poglavlja i rimski broj ostaju kako jesu', () {
    expect(citationRefLabel('IV.', hr), 'IV.');
    expect(citationRefLabel('Introduction', hr), 'Introduction');
  });
}
