import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_core/widgets/citation_helpers.dart';

void main() {
  const doc =
      'https://www.magisterium.com/docs/429efa31-df0f-455d-b7e1-c104ed929e3b/ref/24';

  test('magisterium.com dobiva lang', () {
    expect(withMagisteriumLang(doc, 'hr'), '$doc?lang=hr');
    expect(withMagisteriumLang(doc, 'en'), '$doc?lang=en');
  });

  test('postojeći lang se prepisuje, ostali parametri ostaju', () {
    expect(
      withMagisteriumLang('$doc?lang=en&x=1', 'hr'),
      '$doc?lang=hr&x=1',
    );
  });

  test('ostali hostovi i smeće prolaze nepromijenjeni', () {
    const vatican = 'https://www.vatican.va/content/x.html';
    expect(withMagisteriumLang(vatican, 'hr'), vatican);
    expect(withMagisteriumLang('', 'hr'), '');
    expect(withMagisteriumLang('nije url', 'hr'), 'nije url');
    expect(
      withMagisteriumLang('https://magisterium.com.evil.example/a', 'hr'),
      'https://magisterium.com.evil.example/a',
    );
  });
}
