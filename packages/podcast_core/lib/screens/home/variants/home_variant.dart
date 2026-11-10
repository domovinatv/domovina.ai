/// Eksperimentalne varijante layouta naslovnice iza `?home=a|b|c`.
///
/// Plan: `docs/plans/2026-11-10-naslovnica-varijante-abc.md`. Služi samo za
/// usporedbu nad stvarnim podacima; bez parametra se crta postojeća
/// naslovnica, netaknuta.
///
/// - `?home=a|b|c` → pali tu varijantu i **pamti** je u localStorage, da
///   preživi navigaciju unutar aplikacije i povratak na `/`.
/// - `?home=0` (ili `off`) → briše spremljeni izbor.
/// - Nepoznata vrijednost → ignorira se (vrijedi spremljeno, inače današnji
///   layout).
///
/// Čita se SINKRONO (Uri.base + localStorage), pa nema frejma u kojem bi
/// se nacrtao krivi layout pa preskočio. Na nativeu nema URL-a ni
/// localStorage-a — varijanta je uvijek `null`.
library;

import 'package:flutter/foundation.dart';

import '../../../services/local_prefs.dart';

const String kHomeVariantParam = 'home';
const String _storageKey = 'home_variant';

enum HomeVariant { a, b, c }

/// Rezultat čitanja URL parametra: [clear] = izričito ugasi.
@visibleForTesting
sealed class HomeVariantOverride {
  const HomeVariantOverride();
}

@visibleForTesting
class HomeVariantSet extends HomeVariantOverride {
  final HomeVariant variant;
  const HomeVariantSet(this.variant);
}

@visibleForTesting
class HomeVariantClear extends HomeVariantOverride {
  const HomeVariantClear();
}

class HomeVariantFlag {
  HomeVariantFlag._();

  static bool _resolved = false;
  static HomeVariant? _current;

  /// Aktivna varijanta, ili `null` za postojeću naslovnicu.
  static HomeVariant? get current {
    if (_resolved) return _current;
    _resolved = true;
    if (!kIsWeb) return _current = null;
    final override = overrideFromUri(Uri.base);
    switch (override) {
      case HomeVariantSet(:final variant):
        setLocalStorageString(_storageKey, variant.name);
        return _current = variant;
      case HomeVariantClear():
        setLocalStorageString(_storageKey, '');
        return _current = null;
      case null:
        return _current = decode(getLocalStorageString(_storageKey));
    }
  }

  /// `?home=a|b|c` → postavi, `?home=0|off|false` → obriši, ostalo → null.
  @visibleForTesting
  static HomeVariantOverride? overrideFromUri(Uri? uri) {
    final raw = uri?.queryParameters[kHomeVariantParam];
    if (raw == null) return null;
    final v = raw.trim().toLowerCase();
    if (v == '0' || v == 'off' || v == 'false') return const HomeVariantClear();
    final variant = decode(v);
    return variant == null ? null : HomeVariantSet(variant);
  }

  /// Spremljena vrijednost → varijanta; sve nepoznato → `null`.
  @visibleForTesting
  static HomeVariant? decode(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'a':
        return HomeVariant.a;
      case 'b':
        return HomeVariant.b;
      case 'c':
        return HomeVariant.c;
      default:
        return null;
    }
  }

  @visibleForTesting
  static void debugSet(HomeVariant? v) {
    _resolved = true;
    _current = v;
  }

  @visibleForTesting
  static void debugReset() {
    _resolved = false;
    _current = null;
  }
}
