import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_core/router/url_params.dart';

void main() {
  test('parseStartTime prihvaća YouTube oblike i h:mm:ss', () {
    expect(parseStartTime('5025'), 5025);
    expect(parseStartTime('5025s'), 5025);
    expect(parseStartTime('83m45s'), 5025);
    expect(parseStartTime('1h23m45s'), 5025);
    expect(parseStartTime('1h'), 3600);
    expect(parseStartTime('1:23:45'), 5025);
    expect(parseStartTime('83:45'), 5025);
    expect(parseStartTime(null), isNull);
    expect(parseStartTime(''), isNull);
    expect(parseStartTime('abc'), isNull);
    expect(parseStartTime('-5'), isNull);
    expect(parseStartTime('1:x'), isNull);
  });

  test('parseAutoplay: zadano true, gasi samo izričito', () {
    expect(parseAutoplay(null), isTrue);
    expect(parseAutoplay('1'), isTrue);
    expect(parseAutoplay('true'), isTrue);
    for (final off in ['0', 'false', 'FALSE', 'no', 'off']) {
      expect(parseAutoplay(off), isFalse, reason: off);
    }
  });
}
