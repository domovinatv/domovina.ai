import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_core/models/channel_detail.dart';
import 'package:podcast_core/services/meili_client.dart';
import 'package:podcast_core/services/search_service.dart';
import 'package:podcast_core/services/unified_search.dart';

/// Evaluacija spajanja nad snimljenim odgovorima produkcije — vidi
/// `docs/2026-10-13-pretraga-mali-gpu-i-pametni-search.md` §5. Bez `FIX` se
/// preskače (nije dio obične regresije).
void main() {
  test('eval', skip: Platform.environment['FIX'] == null, () {
    final fx = jsonDecode(File(Platform.environment['FIX']!).readAsStringSync())
        as List<dynamic>;
    final variant = Platform.environment['VARIANT']!;
    final out = <Map<String, dynamic>>[];
    for (final q in fx.cast<Map<String, dynamic>>()) {
      final v = q[variant] as Map<String, dynamic>;
      final hits = mergeSearchResults(
        query: q['query'] as String,
        local: [
          for (final l in (v['local'] as List).cast<Map<String, dynamic>>())
            (
              channelId: 'x',
              channelName: l['channel'] as String,
              video: ChannelVideo(id: l['id'] as String, title: l['title'] as String),
              titleMatch: l['titleMatch'] as bool,
              snippet: null,
            ),
        ],
        meili: MeiliResponse.fromJson(v['meili'] as Map<String, dynamic>).hits,
        semantic: [
          for (final r in ((q['semantic'] as Map)['results'] as List))
            SemanticResult.fromJson(r as Map<String, dynamic>),
        ],
        channelName: (s) => s,
      );
      out.add({
        'query': q['query'],
        'hits': [
          for (final h in hits.take(10))
            {
              'id': h.youtubeId,
              'tier': h.tier.name,
              'src': h.sources.map((s) => s.name[0]).join(),
              'title': h.title.text,
            },
        ],
      });
    }
    File(Platform.environment['OUT']!).writeAsStringSync(jsonEncode(out));
  });
}
