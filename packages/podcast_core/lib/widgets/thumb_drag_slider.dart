/// Seek bar koji prstom vuče SAMO kružić.
///
/// Flutterov `Slider` prima horizontalno povlačenje s bilo kojeg mjesta na
/// traci i skoči na prst. U bočnom panelu playera (`EpisodePanelCanvas`) isti
/// pokret prstom zatvara panel, pa je zatvaranje panela preko trake tiho
/// premjestilo reprodukciju — i izgubilo mjesto gledanja, najvrjedniju stvar
/// za „gledaj kasnije”.
///
/// Pravila za dodir (prst, olovka):
/// - povlačenje koje KRENE s kružića (±[thumbHitRadius]) vuče položaj,
///   relativno, bez skoka na prst;
/// - povlačenje koje krene bilo gdje drugdje traka ni ne vidi — gesta ide
///   roditelju (panel se zatvara, ništa se ne seeka);
/// - kratak dodir na traku i dalje skoči na to mjesto (izričita radnja).
///
/// Miš se ponaša kao i prije: vuče i klikne s bilo kojeg mjesta.
///
/// Pravi `Slider` ostaje u stablu ispod sloja za geste — crta traku po
/// `SliderTheme`u i zadržava semantiku i tipkovnicu.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Je li [dx] dovoljno blizu kružića da dodir smije vući.
bool isOnThumb({
  required double dx,
  required double width,
  required double inset,
  required double fraction,
  double hitRadius = ThumbDragSlider.defaultThumbHitRadius,
}) {
  final track = width - 2 * inset;
  if (track <= 0) return false;
  final thumbX = inset + fraction.clamp(0.0, 1.0) * track;
  return (dx - thumbX).abs() <= hitRadius;
}

class ThumbDragSlider extends StatefulWidget {
  /// Pola od 48 dp — Materialova minimalna površina za dodir.
  static const double defaultThumbHitRadius = 24;

  final double value;
  final double min;
  final double max;

  /// Uvlaka tracka od ruba = `overlayRadius` iz `SliderTheme`a.
  final double inset;
  final double thumbHitRadius;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  const ThumbDragSlider({
    super.key,
    required this.value,
    this.min = 0,
    this.max = 1,
    required this.inset,
    this.thumbHitRadius = defaultThumbHitRadius,
    this.onChangeStart,
    required this.onChanged,
    this.onChangeEnd,
  });

  @override
  State<ThumbDragSlider> createState() => _ThumbDragSliderState();
}

class _ThumbDragSliderState extends State<ThumbDragSlider> {
  double _width = 0;
  double _dragValue = 0;
  double _dragStartDx = 0;
  double _dragStartValue = 0;
  bool _relative = false;

  /// `onCancel` stiže i kad drag nije ni krenuo (dodir na kružić koji je
  /// postao tap) — tada nema što završiti.
  bool _dragging = false;

  double get _range => widget.max - widget.min;

  double get _fraction =>
      _range <= 0 ? 0 : (widget.value - widget.min) / _range;

  double get _track => _width - 2 * widget.inset;

  double _valueAt(double dx) {
    if (_track <= 0) return widget.value;
    final f = ((dx - widget.inset) / _track).clamp(0.0, 1.0);
    return widget.min + f * _range;
  }

  bool _onThumb(double dx) => isOnThumb(
    dx: dx,
    width: _width,
    inset: widget.inset,
    fraction: _fraction,
    hitRadius: widget.thumbHitRadius,
  );

  bool _allows(PointerDownEvent e) =>
      e.kind == PointerDeviceKind.mouse || _onThumb(e.localPosition.dx);

  void _start(DragStartDetails d) {
    final dx = d.localPosition.dx;
    // S kružića: relativno, da prst koji ga je uhvatio 20 px sa strane ne
    // pomakne položaj već samim hvatom. Mišem s trake: skok, kao Slider.
    _dragging = true;
    _relative = _onThumb(dx);
    _dragStartDx = dx;
    _dragStartValue = widget.value;
    _dragValue = _relative ? widget.value : _valueAt(dx);
    widget.onChangeStart?.call(_dragValue);
    if (!_relative) widget.onChanged(_dragValue);
  }

  void _update(DragUpdateDetails d) {
    if (!_dragging) return;
    final dx = d.localPosition.dx;
    if (_relative) {
      if (_track <= 0) return;
      _dragValue = (_dragStartValue + (dx - _dragStartDx) / _track * _range)
          .clamp(widget.min, widget.max);
    } else {
      _dragValue = _valueAt(dx);
    }
    widget.onChanged(_dragValue);
  }

  void _end() {
    if (!_dragging) return;
    _dragging = false;
    widget.onChangeEnd?.call(_dragValue);
  }

  void _tap(TapUpDetails d) {
    final v = _valueAt(d.localPosition.dx);
    widget.onChangeStart?.call(v);
    widget.onChanged(v);
    widget.onChangeEnd?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        _width = c.maxWidth;
        return Stack(
          children: [
            Slider(
              value: widget.value.clamp(widget.min, widget.max),
              min: widget.min,
              max: widget.max,
              onChangeStart: widget.onChangeStart,
              onChanged: widget.onChanged,
              onChangeEnd: widget.onChangeEnd,
            ),
            // Neprozirni sloj iznad Slidera: dodir ne stiže do njegovih
            // recognizera, semantika i fokus ostaju njegovi.
            Positioned.fill(
              child: RawGestureDetector(
                behavior: HitTestBehavior.opaque,
                gestures: {
                  _GatedDragRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        _GatedDragRecognizer
                      >(() => _GatedDragRecognizer(_allows), (r) {
                        r
                          ..allows = _allows
                          ..dragStartBehavior = DragStartBehavior.down
                          ..onStart = _start
                          ..onUpdate = _update
                          ..onEnd = (_) {
                            _end();
                          }
                          ..onCancel = () {
                            _end();
                          };
                      }),
                  TapGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        TapGestureRecognizer
                      >(TapGestureRecognizer.new, (r) {
                        r.onTapUp = _tap;
                      }),
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Horizontalni drag koji u arenu ulazi samo za dopušten pokazivač. Odbijeni
/// pokazivač ovdje ne postoji, pa roditeljev drag (panel) pobjeđuje bez borbe.
class _GatedDragRecognizer extends HorizontalDragGestureRecognizer {
  bool Function(PointerDownEvent) allows;

  _GatedDragRecognizer(this.allows);

  @override
  bool isPointerAllowed(PointerEvent event) =>
      super.isPointerAllowed(event) &&
      (event is! PointerDownEvent || allows(event));
}
