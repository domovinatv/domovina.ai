import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Svaki događaj analitike koji klijent šalje mora biti naveden u pravnim
/// dokumentima: evidenciji obrade (Obrada E) i deklaracijama za store. Novi
/// događaj bez izmjene tih dokumenata ovdje pada — i podsjeća da se uz njih
/// mijenja i politika privatnosti (`legalPrivacyAnalytics*`) ako događaj nosi
/// novu vrstu podatka. Pravilo: CLAUDE.md, „Vlastita analitika”.
///
/// U dokumentu se ime piše u backtickovima; `prefiks_*` pokriva cijelu
/// obitelj (`playback_*`).
void main() {
  const docs = [
    '../../docs/compliance/data-protection.md',
    '../../docs/compliance/store-privacy-labels.md',
  ];

  // Prvi argument poziva koji imenuje događaj: `track('x'`, `_enqueue('x'`,
  // `_emit(a ? 'x' : 'y'`, `_sink('x'`.
  final call = RegExp(r"\b(?:track|_enqueue|_emit|_sink)\(\s*([^,)]*)");
  final literal = RegExp(r"'([a-z][a-z0-9_]*)(\$\{[^}]*\})?'");

  Set<String> emittedEvents() {
    final names = <String>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      if (!src.contains('Analytics')) continue;
      for (final m in call.allMatches(src)) {
        for (final l in literal.allMatches(m.group(1)!)) {
          names.add(l.group(2) == null ? l.group(1)! : '${l.group(1)}*');
        }
      }
    }
    return names;
  }

  Set<String> documented(String path) {
    final tokens = <String>{};
    for (final m in RegExp('`([^`]+)`').allMatches(File(path).readAsStringSync())) {
      tokens.addAll(m.group(1)!.split(RegExp(r'[^a-z0-9_*]+')));
    }
    return tokens;
  }

  bool covered(String name, Set<String> tokens) {
    if (tokens.contains(name)) return true;
    final prefix = name.endsWith('*') ? name.substring(0, name.length - 1) : name;
    return tokens.any((t) =>
        t.endsWith('*') && prefix.startsWith(t.substring(0, t.length - 1)));
  }

  test('ekstrakcija nalazi poznate događaje', () {
    final names = emittedEvents();
    expect(names, containsAll(['session_start', 'screen_view', 'heartbeat',
        'search', 'playback_start', 'playback_pause', 'sponsored_*']));
  });

  for (final doc in docs) {
    test('svaki događaj je u ${doc.split('/').last}', () {
      final tokens = documented(doc);
      final missing = [
        for (final n in emittedEvents()) if (!covered(n, tokens)) n,
      ];
      expect(missing, isEmpty,
          reason: 'Događaji bez zapisa u $doc. Dopuni dokument, a ako '
              'događaj nosi novu vrstu podatka i politiku privatnosti '
              '(legalPrivacyAnalytics*, docs/compliance/privacy-policy-hr.md).');
    });
  }
}
