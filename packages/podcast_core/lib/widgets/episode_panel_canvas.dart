import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Strana bočnog panela na [EpisodePanelCanvas].
enum EpisodePanelSide { left, right }

/// Tri stupca na jednom vodoravnom platnu: `[lijevo] [centar] [desno]`.
///
/// Zamjena za Scaffold `drawer`/`endDrawer` na uskom ekranu epizode. Panel se
/// ne crta PREKO članka nego ga **gura**:
///
/// - kad uz panel ostane barem [minCenterWidth] za centar (landscape na
///   mobitelu, tablet), centar se suzi i oba su stupca vidljiva istovremeno;
/// - inače (portret) centar zadrži punu širinu i odklizi s ekrana, a njegov
///   rub viri ([minPeek]) — tap ili povlačenje po njemu zatvara panel.
///
/// Paneli su montirani cijelo vrijeme, samo izvan vidljivog dijela platna.
/// To nije kozmetika: `Video` u desnom panelu tako se nikad ne premješta u
/// DOM-u, a premještanje `<video>` elementa ga po HTML specu pauzira (zamka
/// zbog koje je endDrawer trebao resume nakon svakog otvaranja/zatvaranja).
class EpisodePanelCanvas extends StatefulWidget {
  final Widget center;
  final Widget? left;
  final Widget? right;
  final double leftWidth;
  final double rightWidth;

  /// Ispod ove širine centar se ne sužava nego odlazi s ekrana.
  final double minCenterWidth;

  /// Koliko se panel smije suziti da bi centar stao uz njega. iPhone u
  /// landscapeu ima ~750 px: player od 360 bi članku ostavio 390, pa ga
  /// radije suzimo nego da članak izguramo s ekrana.
  final double minLeftWidth;
  final double minRightWidth;

  /// Koliko centra uvijek ostane vidljivo kad ga panel izgura.
  final double minPeek;

  /// Javlja promjenu otvorenog panela (null = zatvoreno). Poziva se na
  /// POČETKU animacije, kao `onDrawerChanged`.
  final ValueChanged<EpisodePanelSide?>? onChanged;

  /// Centar je upravo počeo mijenjati širinu (panel se otvara/zatvara UZ
  /// njega, ne preko njega). Poziva se PRIJE prvog layouta nove širine — dok
  /// je stari raspored još na ekranu, pa je to trenutak za snimiti sidro
  /// čitanja.
  final VoidCallback? onCenterReflowStart;

  /// Nakon svakog framea u kojem je centar dobio novu širinu (post-frame,
  /// layout je gotov) — trenutak za vratiti sidro čitanja.
  final VoidCallback? onCenterReflow;

  /// Širina centra se smirila (panel otvoren ili zatvoren do kraja).
  final VoidCallback? onCenterReflowEnd;

  const EpisodePanelCanvas({
    super.key,
    required this.center,
    this.left,
    this.right,
    this.leftWidth = 248,
    this.rightWidth = 360,
    this.minCenterWidth = 320,
    this.minLeftWidth = 200,
    this.minRightWidth = 280,
    this.minPeek = 32,
    this.onChanged,
    this.onCenterReflowStart,
    this.onCenterReflow,
    this.onCenterReflowEnd,
  });

  @override
  State<EpisodePanelCanvas> createState() => EpisodePanelCanvasState();
}

class EpisodePanelCanvasState extends State<EpisodePanelCanvas>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 260);
  static const _edgeDragWidth = 20.0;

  /// -1 = lijevi panel potpuno otvoren, 0 = zatvoreno, 1 = desni otvoren.
  late final AnimationController _c = AnimationController(
    vsync: this,
    lowerBound: -1,
    upperBound: 1,
    value: 0,
    duration: _duration,
  );

  EpisodePanelSide? _open;

  /// Geometrija iz zadnjeg layouta — trebaju je gestovi i [_onTick].
  double _w = 0;
  double _lw = 0;
  double _rw = 0;
  bool _leftFits = false;
  bool _rightFits = false;

  /// Širina centra koju su slušatelji zadnju vidjeli; null dok nema layouta.
  double? _reportedCenterWidth;
  bool _reflowing = false;
  bool _silent = false;

  EpisodePanelSide? get openSide => _open;
  bool get isOpen => _open != null;

  /// Otvoreni panel nije stao uz centar nego ga je gurnuo s ekrana.
  bool get centerHidden => switch (_open) {
    EpisodePanelSide.left => !_leftFits,
    EpisodePanelSide.right => !_rightFits,
    null => false,
  };

  @override
  void initState() {
    super.initState();
    _c.addListener(_onTick);
  }

  @override
  void didUpdateWidget(EpisodePanelCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Otvoreni panel je nestao (ekran je prešao prag pa je sadržaj/player
    // postao stalni stupac). Bez reseta bi `_open` ostao postavljen, roditelj
    // bi i dalje mislio da je panel otvoren i Back bi „zatvarao" ništa.
    final side = _open ?? _sideOf(_c.value);
    if (side != null && !_has(side)) {
      final wasReflowing = _reflowing;
      // Bez ticka: `_onTick` bi usred buildanja roditelja zvao
      // `onCenterReflowStart` i čitao geometriju rasporeda koji upravo nestaje.
      _silent = true;
      _c.stop();
      _c.value = 0;
      _silent = false;
      _open = null;
      _reflowing = false;
      _reportedCenterWidth = null; // izmjeri ga sljedeći layout
      // didUpdateWidget teče usred buildanja roditelja — povratni pozivi
      // (setState kod roditelja) smiju tek nakon framea.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (wasReflowing) widget.onCenterReflowEnd?.call();
        if (_open == null) widget.onChanged?.call(null);
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static EpisodePanelSide? _sideOf(double v) => v < 0
      ? EpisodePanelSide.left
      : v > 0
      ? EpisodePanelSide.right
      : null;

  /// Širina centra za položaj platna [v] (vidi `_c`).
  double _centerWidthAt(double v) {
    if (v < 0 && _leftFits) return _w - _lw * -v;
    if (v > 0 && _rightFits) return _w - _rw * v;
    return _w;
  }

  /// Javlja reflow centra. Listener kontrolera okida sinkrono kad se vrijednost
  /// promijeni, a layout nove širine tek u sljedećem frameu — pa
  /// `onCenterReflowStart` stigne snimiti stari raspored.
  void _onTick() {
    if (_silent) return;
    final before = _reportedCenterWidth;
    if (before == null) return;
    final cw = _centerWidthAt(_c.value);
    if (cw == before) return;
    _reportedCenterWidth = cw;
    if (!_reflowing) {
      _reflowing = true;
      widget.onCenterReflowStart?.call();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_reflowing) return;
      widget.onCenterReflow?.call();
      _endReflowIfSettled();
    });
  }

  void _endReflowIfSettled() {
    final v = _c.value;
    if (!_reflowing || _c.isAnimating || (v != -1 && v != 0 && v != 1)) {
      return;
    }
    _reflowing = false;
    widget.onCenterReflowEnd?.call();
  }

  void _setOpen(EpisodePanelSide? side) {
    if (_open == side) return;
    _open = side;
    widget.onChanged?.call(side);
  }

  bool _has(EpisodePanelSide side) =>
      (side == EpisodePanelSide.left ? widget.left : widget.right) != null;

  void open(EpisodePanelSide side) {
    if (!_has(side)) return;
    _setOpen(side);
    _c.animateTo(
      side == EpisodePanelSide.left ? -1 : 1,
      curve: Curves.easeOutCubic,
    );
    // Povlačenje koje je već stiglo do kraja ne daje novi tick.
    _endReflowIfSettled();
  }

  void close() {
    _setOpen(null);
    _c.animateTo(0, curve: Curves.easeOutCubic);
    _endReflowIfSettled();
  }

  void toggle(EpisodePanelSide side) => _open == side ? close() : open(side);

  // ---------- gestovi ------------------------------------------------------

  /// Panel kojim upravlja tekuće povlačenje. Određuje ga MJESTO početka
  /// (rubni pojas, sam panel, izgurani rub centra), ne smjer prvog pomaka —
  /// inače bi povlačenje od desnog ruba udesno otvorilo lijevi panel.
  EpisodePanelSide? _dragSide;

  void _dragStart(EpisodePanelSide? side) {
    _c.stop();
    final s = side ?? _sideOf(_c.value);
    _dragSide = s != null && _has(s) ? s : null;
  }

  void _dragUpdate(DragUpdateDetails d) {
    final side = _dragSide;
    if (side == null) return;
    final w = side == EpisodePanelSide.right ? _rw : _lw;
    if (w <= 0) return;
    // Pomak prsta udesno vuče platno udesno: zatvara desni / otvara lijevi.
    final next = _c.value - d.delta.dx / w;
    _c.value = side == EpisodePanelSide.right
        ? next.clamp(0.0, 1.0)
        : next.clamp(-1.0, 0.0);
  }

  void _dragEnd(double vx) {
    final side = _dragSide;
    _dragSide = null;
    if (side == null) return;
    final v = _c.value;
    final bool keepOpen;
    if (vx.abs() > 365) {
      keepOpen = side == EpisodePanelSide.right ? vx < 0 : vx > 0;
    } else {
      keepOpen = v.abs() > 0.5;
    }
    keepOpen ? open(side) : close();
  }

  Widget _drag(Widget child, {EpisodePanelSide? side}) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onHorizontalDragStart: (_) => _dragStart(side),
    onHorizontalDragUpdate: _dragUpdate,
    onHorizontalDragEnd: (d) => _dragEnd(d.velocity.pixelsPerSecond.dx),
    // Prekinuto povlačenje (npr. sistemska gesta) ne smije ostaviti panel
    // napola otvoren.
    onHorizontalDragCancel: () => _dragEnd(0),
    child: child,
  );

  // ---------- layout -------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = _w = constraints.maxWidth;
        final maxPanel = math.max(0.0, w - widget.minPeek);
        _lw = widget.left == null
            ? 0
            : _fitPanel(w, widget.leftWidth, widget.minLeftWidth, maxPanel);
        _rw = widget.right == null
            ? 0
            : _fitPanel(w, widget.rightWidth, widget.minRightWidth, maxPanel);
        final leftFits = _leftFits = w - _lw >= widget.minCenterWidth;
        final rightFits = _rightFits = w - _rw >= widget.minCenterWidth;
        // Promjenu širine izvana (rotacija) ne javljamo kao reflow panela.
        if (!_reflowing) _reportedCenterWidth = _centerWidthAt(_c.value);

        return AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final v = _c.value;
            final lt = v < 0 ? -v : 0.0; // koliko je lijevi otvoren
            final rt = v > 0 ? v : 0.0; // koliko je desni otvoren

            var centerLeft = 0.0;
            var centerWidth = w;
            if (lt > 0) {
              centerLeft = _lw * lt;
              if (leftFits) centerWidth = w - _lw * lt;
            } else if (rt > 0) {
              if (rightFits) {
                centerWidth = w - _rw * rt;
              } else {
                centerLeft = -_rw * rt;
              }
            }
            // Panel koji GURA centar s ekrana — centar je tada samo rub
            // koji zatvara panel, ne površina za čitanje.
            final covering = (lt > 0 && !leftFits) || (rt > 0 && !rightFits);
            final closed = v == 0;

            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  key: const ValueKey('center'),
                  left: centerLeft,
                  top: 0,
                  bottom: 0,
                  width: centerWidth,
                  child: widget.center,
                ),
                Positioned(
                  key: const ValueKey('scrim'),
                  left: centerLeft,
                  top: 0,
                  bottom: 0,
                  width: centerWidth,
                  child: IgnorePointer(
                    ignoring: !covering,
                    child: _drag(
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: close,
                        child: ColoredBox(
                          color: Colors.black.withValues(
                            alpha: covering ? 0.32 * math.max(lt, rt) : 0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.left != null)
                  Positioned(
                    key: const ValueKey('left'),
                    left: -_lw + _lw * lt,
                    top: 0,
                    bottom: 0,
                    width: _lw,
                    child: _panel(
                      theme,
                      widget.left!,
                      EpisodePanelSide.left,
                      hidden: lt == 0,
                    ),
                  ),
                if (widget.right != null)
                  Positioned(
                    key: const ValueKey('right'),
                    left: w - _rw * rt,
                    top: 0,
                    bottom: 0,
                    width: _rw,
                    child: _panel(
                      theme,
                      widget.right!,
                      EpisodePanelSide.right,
                      hidden: rt == 0,
                    ),
                  ),
                // Rubni pojas za otvaranje povlačenjem, kao kod drawera.
                if (widget.left != null)
                  Positioned(
                    key: const ValueKey('edge-left'),
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: _edgeDragWidth,
                    child: IgnorePointer(
                      ignoring: !closed,
                      child: _drag(
                        const SizedBox.expand(),
                        side: EpisodePanelSide.left,
                      ),
                    ),
                  ),
                if (widget.right != null)
                  Positioned(
                    key: const ValueKey('edge-right'),
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: _edgeDragWidth,
                    child: IgnorePointer(
                      ignoring: !closed,
                      child: _drag(
                        const SizedBox.expand(),
                        side: EpisodePanelSide.right,
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  /// Puna širina panela, ili uža (do [min]) ako se tako centar uz njega
  /// zadrži na [EpisodePanelCanvas.minCenterWidth].
  double _fitPanel(double w, double full, double min, double maxPanel) {
    final width = math.min(full, maxPanel);
    final room = w - widget.minCenterWidth;
    if (w - width >= widget.minCenterWidth || room < min) return width;
    return room;
  }

  Widget _panel(
    ThemeData theme,
    Widget child,
    EpisodePanelSide side, {
    required bool hidden,
  }) {
    final border = BorderSide(color: theme.colorScheme.outlineVariant);
    // Zatvoren panel ostaje montiran (vidi doc klase), ali ga čitač zaslona i
    // Tab ne smiju doseći — Drawer ga je dosad demontirao. Omotači su uvijek
    // u stablu da se `Video` nikad ne premjesti.
    // `TickerMode` gasi animacije u zatvorenom panelu; widgeti koji se
    // crtaju iz streamova (titlovi) ga čitaju i ne rade ništa dok je off.
    return TickerMode(
      enabled: !hidden,
      child: ExcludeSemantics(
        excluding: hidden,
        child: ExcludeFocus(
          excluding: hidden,
          child: _panelBody(theme, border, child, side),
        ),
      ),
    );
  }

  Widget _panelBody(
    ThemeData theme,
    BorderSide border,
    Widget child,
    EpisodePanelSide side,
  ) {
    return _drag(
      side: side,
      Material(
        color: theme.colorScheme.surface,
        child: DecoratedBox(
          // Lijevi panel (sadržaj) već crta svoj desni rub.
          decoration: BoxDecoration(
            border: side == EpisodePanelSide.right
                ? Border(left: border)
                : null,
          ),
          // Platno je u tijelu Scaffolda ispod `SafeArea(top: false)` — app
          // bar je sliver u centru — pa paneli sami čuvaju gornji inset.
          child: SafeArea(
            left: false,
            right: false,
            bottom: false,
            child: child,
          ),
        ),
      ),
    );
  }
}
