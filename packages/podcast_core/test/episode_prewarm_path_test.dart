import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_core/services/data_service.dart';

/// `DataService.prewarmForLocation` na hladnom startu pokreće `episode.json`
/// samo za rute ekrana epizode; ostale rute ne smiju okinuti dohvat.
void main() {
  final id = DataService.episodeIdFromPath;

  test('rute ekrana epizode', () {
    expect(id('/v/RdEN7Ny1bV8'), 'RdEN7Ny1bV8');
    expect(id('/v/RdEN7Ny1bV8/'), 'RdEN7Ny1bV8');
    expect(id('/v/RdEN7Ny1bV8/en'), 'RdEN7Ny1bV8');
    expect(id('/v/RdEN7Ny1bV8/t/83'), 'RdEN7Ny1bV8');
    expect(id('/v/RdEN7Ny1bV8/t/1h23m45s/en'), 'RdEN7Ny1bV8');
    expect(id('/v/a-b_c123'), 'a-b_c123');
  });

  test('ostale rute ne', () {
    expect(id('/'), isNull);
    expect(id('/c/muzevni_budite'), isNull);
    expect(id('/m/RdEN7Ny1bV8'), isNull);
    expect(id('/v/RdEN7Ny1bV8/sponzoriraj'), isNull);
    expect(id('/v/RdEN7Ny1bV8/read'), isNull);
    expect(id('/v/'), isNull);
  });
}
