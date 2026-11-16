/// Oblačić s vremenom iznad seek bara — YouTube stil.
///
/// Dok mišem prelaziš preko trake (desktop) ili je vučeš mišem ili prstom
/// (svugdje), iznad pokazivača stoji vrijeme na koje će skok pasti, i ime
/// poglavlja kad ga znamo. Tako se seek radi na točnu sekundu umjesto
/// naslijepo.
///
/// Widget ne mijenja ponašanje trake ispod sebe: sluša pokazivač
/// prozirno (`HitTestBehavior.translucent`, `MouseRegion(opaque: false)`), pa
/// Slider / media_kitova traka i dalje dobivaju svaki događaj. Zato se može
/// staviti i preko trake koju ne posjedujemo (media_kit u `EpisodeVideo`).
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// `1:02:03` ili `12:03` — isti format kao vrijeme ispod playera.
String formatScrubTime(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$s';
  return '$m:$s';
}

/// Pozicija pokazivača → vrijeme. [inset] je koliko je track uvučen od ruba
/// s obje strane (radijus overlaya Slidera, margina media_kitove trake) —
/// bez toga bi oblačić pri rubovima odstupao od mjesta na koje skok padne.
@visibleForTesting
Duration scrubTimeAt(
  double dx, {
  required double width,
  required double inset,
  required Duration total,
}) {
  final track = width - 2 * inset;
  if (track <= 0 || total <= Duration.zero) return Duration.zero;
  final f = ((dx - inset) / track).clamp(0.0, 1.0);
  // Na sekundu: oblačić pokazuje sekunde, pa i skok ide na tu sekundu.
  return Duration(seconds: (total.inMilliseconds * f / 1000).round());
}

class ScrubPreview extends StatefulWidget {
  /// Traka nad kojom se prati pokazivač.
  final Widget child;

  /// Ukupno trajanje; dok je nula oblačića nema.
  final Duration total;

  /// Uvlaka tracka od lijevog i desnog ruba [child]a.
  final double inset;

  /// Ime poglavlja (ili bilo čega) za dano vrijeme; `null` = samo vrijeme.
  final String? Function(Duration at)? labelAt;

  /// Razmak između vrha [child]a i dna oblačića.
  final double gap;

  /// Javlja vrijeme koje oblačić pokazuje kad se vučenje završi — za trake
  /// koje same ne znaju točnu sekundu (ovdje je zaokruženo na sekundu).
  final ValueChanged<Duration>? onScrubEnd;

  const ScrubPreview({
    super.key,
    required this.child,
    required this.total,
    required this.inset,
    this.labelAt,
    this.gap = 6,
    this.onScrubEnd,
  });

  @override
  State<ScrubPreview> createState() => _ScrubPreviewState();
}

class _ScrubPreviewState extends State<ScrubPreview> {
  double? _dx;
  bool _dragging = false;
  int? _pointer;

  /// Miš koji stoji na traci: media_kit nakon par sekundi sakrije kontrole,
  /// pa oblačić ne smije ostati visjeti nad videom.
  Timer? _idle;
  static const _idleHide = Duration(seconds: 3);

  @override
  void dispose() {
    _idle?.cancel();
    super.dispose();
  }

  void _show(double dx) {
    _idle?.cancel();
    if (!_dragging) {
      _idle = Timer(_idleHide, () {
        if (mounted && !_dragging) setState(() => _dx = null);
      });
    }
    if (_dx != dx) setState(() => _dx = dx);
  }

  void _hide() {
    _idle?.cancel();
    if (_dx != null || _dragging) {
      setState(() {
        _dx = null;
        _dragging = false;
      });
    }
  }

  void _down(PointerDownEvent e) {
    if (e.kind == PointerDeviceKind.mouse && e.buttons != kPrimaryButton) {
      return;
    }
    _pointer = e.pointer;
    _dragging = true;
    _show(e.localPosition.dx);
  }

  void _up(PointerEvent e, double width) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    final at = scrubTimeAt(
      e.localPosition.dx,
      width: width,
      inset: widget.inset,
      total: widget.total,
    );
    _dragging = false;
    if (e is PointerUpEvent) widget.onScrubEnd?.call(at);
    // Miš ostaje iznad trake → nastavi kao hover; prst je otišao → sakrij.
    if (e.kind == PointerDeviceKind.mouse && e is PointerUpEvent) {
      _show(e.localPosition.dx);
    } else {
      _hide();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        final dx = _dx;
        final showing = dx != null && widget.total > Duration.zero;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            MouseRegion(
              opaque: false,
              hitTestBehavior: HitTestBehavior.translucent,
              onHover: (e) => _show(e.localPosition.dx),
              onExit: (_) {
                if (!_dragging) _hide();
              },
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: _down,
                onPointerMove: (e) {
                  if (e.pointer == _pointer) _show(e.localPosition.dx);
                },
                onPointerUp: (e) => _up(e, width),
                onPointerCancel: (e) => _up(e, width),
                child: widget.child,
              ),
            ),
            if (showing)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                top: 0,
                child: IgnorePointer(
                  child: CustomSingleChildLayout(
                    delegate: _BubbleLayout(
                      x: dx.clamp(widget.inset, width - widget.inset),
                      gap: widget.gap,
                    ),
                    child: _Bubble(
                      time: scrubTimeAt(
                        dx,
                        width: width,
                        inset: widget.inset,
                        total: widget.total,
                      ),
                      labelAt: widget.labelAt,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Oblačić centriran na [x], iznad vrha trake, stisnut u širinu trake.
class _BubbleLayout extends SingleChildLayoutDelegate {
  final double x;
  final double gap;

  const _BubbleLayout({required this.x, required this.gap});

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(maxWidth: constraints.maxWidth.clamp(0, 260));

  @override
  Offset getPositionForChild(Size size, Size child) {
    final maxLeft = (size.width - child.width).clamp(0.0, double.infinity);
    final left = (x - child.width / 2).clamp(0.0, maxLeft);
    return Offset(left, -child.height - gap);
  }

  @override
  bool shouldRelayout(_BubbleLayout old) => old.x != x || old.gap != gap;
}

class _Bubble extends StatelessWidget {
  final Duration time;
  final String? Function(Duration at)? labelAt;

  const _Bubble({required this.time, this.labelAt});

  @override
  Widget build(BuildContext context) {
    final label = labelAt?.call(time);
    final base = DefaultTextStyle.of(context).style;
    // Ista podloga kao titl (crna, poluprozirna, zaobljena) — čita se i preko
    // svijetle slike i na svijetloj temi ispod playera.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(215),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Cijeli naslov poglavlja, u više redaka (do 260 px širine) — bez
          // ellipsisa, kao i titl: skraćeni naslov ne govori kamo skačeš.
          if (label != null && label.isNotEmpty)
            Text(
              label,
              textAlign: TextAlign.center,
              style: base.copyWith(
                color: Colors.white.withAlpha(200),
                fontSize: 11,
                height: 1.2,
              ),
            ),
          Text(
            formatScrubTime(time),
            style: base.copyWith(
              color: Colors.white,
              fontSize: 13,
              height: 1.2,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
