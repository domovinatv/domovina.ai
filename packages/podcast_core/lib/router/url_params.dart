/// Query parametri epizode koje dijelimo s YouTubeom.
library;

/// `?t=` u svim oblicima koje YouTube prihvaća: `5025`, `5025s`, `83m45s`,
/// `1h23m45s`, i usput `1:23:45` / `83:45` (kako se vrijeme prepisuje iz
/// playera). Vraća sekunde ili `null` kad vrijednost nije vrijeme.
int? parseStartTime(String? raw) {
  final t = raw?.trim().toLowerCase();
  if (t == null || t.isEmpty) return null;
  final plain = int.tryParse(t);
  if (plain != null) return plain >= 0 ? plain : null;

  if (t.contains(':')) {
    final parts = t.split(':');
    if (parts.length > 3) return null;
    var total = 0;
    for (final p in parts) {
      final v = int.tryParse(p);
      if (v == null || v < 0) return null;
      total = total * 60 + v;
    }
    return total;
  }

  final m = RegExp(r'^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$').firstMatch(t);
  if (m == null || m.group(0)!.isEmpty) return null;
  int g(int i) => int.parse(m.group(i) ?? '0');
  return g(1) * 3600 + g(2) * 60 + g(3);
}

/// `?autoplay=0|false|no|off` → `false`; sve ostalo (i bez parametra) →
/// `true`. Zadano epizoda kreće odmah, kao na YouTubeu.
bool parseAutoplay(String? raw) =>
    !const {'0', 'false', 'no', 'off'}.contains(raw?.trim().toLowerCase());
