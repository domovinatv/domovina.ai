import 'package:flutter/material.dart';

import '../utils/text_search.dart';

/// Tekst s istaknutim (crveno + bold) dijelovima koji odgovaraju [query]-ju.
///
/// Dijakritik-neosjetljivo (preko [highlightRanges]). Ako nema podudaranja
/// (ili je query prazan), ponaša se kao običan [Text].
class QueryHighlightText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle? style;
  final TextStyle? highlightStyle;
  final int? maxLines;
  final TextOverflow overflow;

  /// Gotovi rasponi `[start, end)` (npr. Meilijevi `<em>`, koji hvata i
  /// tipfelere). Spajaju se s rasponima iz [query].
  final List<List<int>> ranges;

  const QueryHighlightText(
    this.text, {
    required this.query,
    this.style,
    this.highlightStyle,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.ranges = const [],
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final ranges = _merge([...highlightRanges(text, query), ...this.ranges]);
    if (ranges.isEmpty) {
      return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    }

    final theme = Theme.of(context);
    final red = theme.brightness == Brightness.dark
        ? const Color(0xFFFF6B6B)
        : const Color(0xFFD32F2F);
    final hl = highlightStyle ??
        (style ?? const TextStyle()).copyWith(
          color: red,
          fontWeight: FontWeight.w700,
        );

    final spans = <TextSpan>[];
    var cursor = 0;
    for (final r in ranges) {
      final s = r[0], e = r[1];
      if (s > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, s), style: style));
      }
      spans.add(TextSpan(text: text.substring(s, e), style: hl));
      cursor = e;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: style));
    }

    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  static List<List<int>> _merge(List<List<int>> rs) {
    if (rs.length < 2) return rs;
    rs.sort((a, b) => a[0].compareTo(b[0]));
    final out = <List<int>>[rs.first];
    for (final r in rs.skip(1)) {
      final last = out.last;
      if (r[0] <= last[1]) {
        if (r[1] > last[1]) out[out.length - 1] = [last[0], r[1]];
      } else {
        out.add(r);
      }
    }
    return out;
  }
}
