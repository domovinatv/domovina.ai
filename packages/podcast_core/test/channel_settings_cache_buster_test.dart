import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_core/services/channel_settings_service.dart';

/// Odluka 510: preglednik ne smije posluživati `/settings` iz HTTP cachea
/// dulje od minute; `t` je minutni bucket, isti unutar minute.
void main() {
  test('requestUrl nosi minutni bucket t', () {
    var now = DateTime.utc(2026, 11, 12, 13, 15, 5);
    final c = ChannelSettingsCatalog(
      baseUrl: 'https://katalog.test/v1',
      now: () => now,
    );
    final a = Uri.parse(c.requestUrl);
    expect(a.path, '/v1/settings');
    expect(a.queryParameters['t'], '${now.millisecondsSinceEpoch ~/ 60000}');

    now = now.add(const Duration(seconds: 40)); // ista minuta? 13:15:45
    expect(c.requestUrl, a.toString());

    now = now.add(const Duration(seconds: 20)); // 13:16:05
    expect(c.requestUrl, isNot(a.toString()));
  });
}
