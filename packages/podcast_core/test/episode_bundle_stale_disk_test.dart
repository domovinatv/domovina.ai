import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:podcast_core/services/cdn_json_cache.dart';
import 'package:podcast_core/services/cdn_store.dart';
import 'package:podcast_core/services/data_service.dart';

/// `episode.json` s diska (Cache Storage) može biti star: pipeline je u
/// međuvremenu dodao datoteku. Prije nego `_get` kaže 404 bez mreže, mora
/// pričekati revalidaciju. Izmjereno 29.10.2026. na `MNk-eEpDb3E`
/// (Magisterium se nije vidio ni nakon Ctrl+Shift+R).
class _MemStore implements CdnStore {
  final Map<String, StoredEntry> data = {};

  @override
  Future<StoredEntry?> get(StoreBucket b, String url) async =>
      data['${b.name}|$url'];
  @override
  Future<void> put(StoreBucket b, String url, StoredEntry e) async =>
      data['${b.name}|$url'] = e;
  @override
  Future<void> clear() async => data.clear();
  @override
  bool supports(StoreBucket b) => b != StoreBucket.immutable;
}

void main() {
  const id = 'stale1';
  const bundleUrl = 'https://cdn.domovina.ai/data/$id/episode.json';
  final original = CdnJsonCache.instance;
  late _MemStore store;

  String bundle(List<String> files) =>
      jsonEncode({'version': 1, 'files': files, 'inline': {}});

  setUp(() {
    DataService.resetMemoryForTest();
    store = _MemStore();
    CdnJsonCache.instance = CdnJsonCache(store: store, enabled: true);
  });
  tearDown(() => CdnJsonCache.instance = original);

  Future<(String?, List<String>)> loadMag(String cdnBundle) async {
    final log = <String>[];
    final body = await http.runWithClient(
      () async {
        final r = await DataService(youtubeId: id).loadMagisterium();
        return r?.sourceArticle;
      },
      () => MockClient((req) async {
        log.add(req.url.path);
        if (req.url.path.endsWith('/episode.json')) {
          return http.Response(cdnBundle, 200);
        }
        if (req.url.path.endsWith('/article.magisterium.json')) {
          return http.Response(
              jsonEncode({'source_article': 'svjez', 'sections': []}), 200);
        }
        return http.Response('', 404);
      }),
    );
    return (body, log);
  }

  test('datoteka dodana nakon spremanja popisa se ipak dohvati', () async {
    store.data['episode|$bundleUrl'] =
        StoredEntry(bundle(['info.json', 'article.json']));

    final (mag, log) = await loadMag(
        bundle(['info.json', 'article.json', 'article.magisterium.json']));

    expect(mag, 'svjez');
    expect(log, [
      '/data/$id/episode.json',
      '/data/$id/article.magisterium.json',
    ]);
  });

  test('datoteke kojih nema ni na CDN-u ostaju 404 bez dohvata', () async {
    final same = bundle(['info.json', 'article.json']);
    store.data['episode|$bundleUrl'] = StoredEntry(same);

    final (mag, log) = await loadMag(same);

    expect(mag, isNull);
    expect(log, ['/data/$id/episode.json']);
  });
}
