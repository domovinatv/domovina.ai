import 'package:flutter_test/flutter_test.dart';

import 'package:podcast_core/models/podcast_summary.dart';

/// `summary.en.json` → `speakers[]`: `role_en` i (od 29.10.2026.)
/// `suggested_name_en` za generička imena. Stari prijevodi polje nemaju.
void main() {
  SummarySpeaker sp(Map<String, dynamic> json) => SummarySpeaker.fromJson(json);

  test('generičko ime i uloga na EN, pad na HR kad prijevoda nema', () {
    final audience = sp({
      'id': 'SPEAKER_04',
      'suggested_name': 'Sudionica iz publike',
      'suggested_name_en': 'Audience member',
      'role': 'sugovornik',
      'role_en': 'participant',
    });
    expect(audience.displayNameFor(true), 'Audience member');
    expect(audience.roleLabelFor(true), 'Participant');
    expect(audience.displayNameFor(false), 'Sudionica iz publike');
    expect(audience.roleLabelFor(false), 'Sugovornik');

    final old = sp({
      'id': 'SPEAKER_01',
      'suggested_name': 'Sudionik iz publike 1',
      'role': 'sugovornik',
    });
    expect(old.displayNameFor(true), 'Sudionik iz publike 1');
    expect(old.roleLabelFor(true), 'Sugovornik');
  });

  test('anonimni voditelj ostaje bez imena i na EN', () {
    final host = sp({
      'id': 'SPEAKER_00',
      'suggested_name': 'voditelj',
      'suggested_name_en': 'host',
      'role': 'voditelj',
      'role_en': 'host',
    });
    expect(host.displayNameFor(true), isNull);
    expect(host.roleLabelFor(true), 'Host');
  });
}
