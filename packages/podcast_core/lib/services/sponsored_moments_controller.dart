/// Stanje plaćenih trenutaka na ekranu epizode: koji trenutak upravo svira i
/// mjerenje (`impression`, `play_through`, `click`).
///
/// Jedan kontroler po ekranu epizode; vlasnik je ekran (drži `Player`) i
/// hrani ga pozicijom iz istog listenera koji već radi URL sync. Widgeti
/// (oznaka preko videa, traka u panelu, traka u jednostavnom prikazu) slušaju
/// [active] — isti objekt putuje kroz sva tri stabla, pa nijedno ne računa
/// „je li ovo trenutak" na svoju ruku.
///
/// Mjerenje (plan §2.2, „Mjerenje"):
/// - `impression` — pozicija UŠLA u `[start, end)`; jednom po sesiji po
///   trenutku (memorija živi do zatvaranja taba/aplikacije, ne preko sesije);
/// - `play_through` — pozicija izašla na `end` bez skoka unutar trenutka i bez
///   ulaska skokom;
/// - `click` — tap na poveznicu branda.
///
/// Skok se prepoznaje isto kao u `services/seek_undo.dart`: razlika dviju
/// uzastopnih pozicija veća od [jumpThreshold]. **Prag ne spuštati ispod
/// 1 s** — `position` stream fira ~5×/s, pa je pri brzini 2,0× prirodan
/// korak ~0,4 s.
///
/// Ništa se ne naplaćuje po prikazu; brojke su informacija kupcu.
library;

import 'package:flutter/foundation.dart';

import '../src/log.dart' show log;
import 'analytics/analytics.dart';
import '../models/sponsored_moment.dart';

enum SponsoredMomentEvent {
  impression('impression'),
  playThrough('play_through'),
  click('click');

  const SponsoredMomentEvent(this.wire);

  /// Ime događaja kako ga piše plan (i budući insert-only zapis).
  final String wire;
}

/// Kamo idu događaji mjerenja.
abstract class SponsoredMomentSink {
  void record(SponsoredMomentEvent event, SponsoredMoment moment);
}

/// Ugovor v1 NEMA tablicu za mjerenje u Supabaseu; događaji idu u log i u
/// vlastitu analitiku (`sponsored_impression`, `sponsored_play_through`,
/// `sponsored_click`). Logika detekcije ne ovisi o tome kamo idu.
class LogSponsoredMomentSink implements SponsoredMomentSink {
  const LogSponsoredMomentSink();

  @override
  void record(SponsoredMomentEvent event, SponsoredMoment moment) {
    log('SponsoredMoment: ${event.wire} ${moment.slotKey}');
    Analytics.instance.track(
      'sponsored_${event.wire}',
      videoId: moment.youtubeId,
      props: {
        'slot_key': moment.slotKey,
        'brand': moment.brand,
        'start': moment.start,
        'end': moment.end,
      },
    );
  }
}

class SponsoredMomentsController {
  SponsoredMomentsController(
    SponsoredMoments moments, {
    DateTime Function()? clock,
    SponsoredMomentSink sink = const LogSponsoredMomentSink(),
    this.jumpThreshold = const Duration(seconds: 2),
    this.endSlack = const Duration(seconds: 3),
  }) : _sink = sink,
       _clock = clock ?? DateTime.now,
       _all = moments,
       assert(jumpThreshold >= const Duration(seconds: 1)) {
    _refilter();
  }

  final SponsoredMoments _all;
  final DateTime Function() _clock;
  late SponsoredMoments _live;
  DateTime? _nextExpiry;

  /// Trenuci kojima zakup SADA traje. Ekran epizode zna stajati otvoren
  /// preko `live_until` — istekao trenutak tada nestaje iz oznake, trake,
  /// pojasa i mjerenja (provjera ide uz poziciju, ne uz timer).
  SponsoredMoments get moments => _live;

  void _refilter() {
    _live = _all.liveAt(_clock());
    _nextExpiry = _live.nextExpiry;
  }
  final SponsoredMomentSink _sink;
  final Duration jumpThreshold;

  /// Koliko iza `end` prva pozicija smije pasti da se izlazak računa kao
  /// prirodan (stream ne javi točno `end`).
  final Duration endSlack;

  /// Trenutni slot — null kad trenutak ne svira.
  final ValueNotifier<SponsoredMoment?> active = ValueNotifier(null);

  /// Impresije viđene u ovoj sesiji aplikacije (svi ekrani, svi kontroleri).
  static final Set<String> _impressedThisSession = {};

  @visibleForTesting
  static void resetSessionForTest() => _impressedThisSession.clear();

  Duration? _last;
  SponsoredMoment? _inside;
  bool _jumpedInside = false;

  void onPosition(Duration position) {
    final expiry = _nextExpiry;
    if (expiry != null && !_clock().isBefore(expiry)) {
      _refilter();
      if (_inside != null && !_live.moments.contains(_inside)) _inside = null;
    }
    final last = _last;
    _last = position;
    final jump = last != null && (position - last).abs() > jumpThreshold;
    final now = moments.activeAt(position);

    final inside = _inside;
    if (inside != null) {
      if (identical(now, inside)) {
        if (jump) _jumpedInside = true;
        return;
      }
      // Izlazak iz trenutka. Prirodan kraj = pozicija je upravo prešla `end`.
      final natural =
          !jump &&
          !_jumpedInside &&
          position >= inside.endPosition &&
          position < inside.endPosition + endSlack;
      if (natural) _sink.record(SponsoredMomentEvent.playThrough, inside);
      _inside = null;
    }

    if (now != null) {
      _inside = now;
      // Ulazak skokom (tap na „Poslušaj", seek bar) je impresija, ali ne može
      // postati `play_through` — nije odgledan od početka.
      _jumpedInside = jump || last == null;
      if (_impressedThisSession.add(now.slotKey)) {
        _sink.record(SponsoredMomentEvent.impression, now);
      }
    }
    if (active.value != now) active.value = now;
  }

  void recordClick(SponsoredMoment moment) =>
      _sink.record(SponsoredMomentEvent.click, moment);

  void dispose() => active.dispose();
}
