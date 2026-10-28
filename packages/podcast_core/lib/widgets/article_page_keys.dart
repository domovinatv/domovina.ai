import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

/// Home / End / PageUp / PageDown (i strelice) pomiču glavni scroll stranice,
/// kao u pregledniku.
///
/// Flutter nema DOM koji bi to radio sam. `WidgetsApp` doduše veže PageUp,
/// PageDown i strelice na [ScrollIntent], ali [ScrollAction] pomiče scrollable
/// u kojem je FOKUS — a na ekranu epizode fokus je obično na ruti (nijedan
/// scrollable) ili u panelu playera, pa tipke ne rade ništa ili pomiču krivu
/// listu. Home i End Flutter uopće ne veže za scroll.
///
/// Zato: [ScrollIntent] se u ovom podstablu preusmjerava na [controller], a
/// Home/End dobivaju vlastiti intent. Oboje radi samo dok je fokus u ovom
/// podstablu, pa widget drži fokus u sebi: autofocus, i vraćanje fokusa kad
/// padne natrag na rutu (polje za pretragu ga nakon tipkanja preda ruti).
///
/// Tekstna polja i panel koji prekriva članak ([active] == false) dobivaju
/// zadano ponašanje: Home/End miču kursor, PageUp/PageDown pomiču fokusiranu
/// listu.
class ArticlePageKeys extends StatefulWidget {
  const ArticlePageKeys({
    super.key,
    required this.controller,
    required this.active,
    required this.child,
  });

  final ScrollController controller;

  /// Je li članak trenutno ono što korisnik gleda (npr. nije ga prekrio panel).
  final bool Function() active;

  final Widget child;

  @override
  State<ArticlePageKeys> createState() => _ArticlePageKeysState();
}

class _ArticleEdgeIntent extends Intent {
  const _ArticleEdgeIntent({required this.end});
  final bool end;
}

class _ArticlePageKeysState extends State<ArticlePageKeys> {
  final _focus = FocusNode(debugLabel: 'ArticlePageKeys', skipTraversal: true);

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_reclaimFocus);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_reclaimFocus);
    _focus.dispose();
    super.dispose();
  }

  /// Fokus je pao na scope rute (nitko unutar nje nije fokusiran) — tipke
  /// tada ne bi stigle ni do jednog Shortcuts ispod rute.
  void _reclaimFocus() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null || primary != _focus.enclosingScope) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
      if (FocusManager.instance.primaryFocus == _focus.enclosingScope) {
        _focus.requestFocus();
      }
    });
  }

  bool get _articleTakesKeys {
    if (!widget.controller.hasClients || !widget.active()) return false;
    // Tekstno polje: Home/End pripadaju kursoru.
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx == null ||
        ctx.findAncestorStateOfType<EditableTextState>() == null;
  }

  void _moveTo(double target) {
    final pos = widget.controller.position;
    final clamped = target.clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if (clamped == pos.pixels) return;
    pos.moveTo(
      clamped,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.home): _ArticleEdgeIntent(
          end: false,
        ),
        SingleActivator(LogicalKeyboardKey.end): _ArticleEdgeIntent(end: true),
      },
      child: Actions(
        actions: {
          ScrollIntent: _ArticleScrollAction(this),
          _ArticleEdgeIntent: _ArticleEdgeAction(this),
        },
        child: Focus(focusNode: _focus, autofocus: true, child: widget.child),
      ),
    );
  }
}

/// [ScrollAction] koji vertikalni scroll šalje u članak; sve ostalo (tekstno
/// polje, prekriven članak, vodoravni railovi) prepušta zadanom ponašanju.
class _ArticleScrollAction extends ScrollAction {
  _ArticleScrollAction(this._s);
  final _ArticlePageKeysState _s;

  bool _mine(ScrollIntent intent) =>
      axisDirectionToAxis(intent.direction) == Axis.vertical &&
      _s._articleTakesKeys;

  @override
  bool isEnabled(ScrollIntent intent, [BuildContext? context]) =>
      _mine(intent) || super.isEnabled(intent, context);

  @override
  void invoke(ScrollIntent intent, [BuildContext? context]) {
    if (!_mine(intent)) return super.invoke(intent, context);
    final pos = _s.widget.controller.position;
    // Isti iznosi kao Flutterov ScrollAction: 80 % viewporta / 50 px.
    final step = switch (intent.type) {
      ScrollIncrementType.page => pos.viewportDimension * 0.8,
      ScrollIncrementType.line => 50.0,
    };
    final down = intent.direction == AxisDirection.down;
    _s._moveTo(pos.pixels + (down ? step : -step));
  }
}

class _ArticleEdgeAction extends Action<_ArticleEdgeIntent> {
  _ArticleEdgeAction(this._s);
  final _ArticlePageKeysState _s;

  // Isključen = tipka ide dalje (Home/End u tekstnom polju).
  @override
  bool isEnabled(_ArticleEdgeIntent intent) => _s._articleTakesKeys;

  @override
  void invoke(_ArticleEdgeIntent intent) => _jump(intent.end, 5);

  /// Skok, ne animacija: `maxScrollExtent` lijeno građenog sliver popisa je
  /// procjena koja raste kako se dno izgradi, pa se End ponavlja dok ne stane.
  void _jump(bool end, int left) {
    final c = _s.widget.controller;
    if (!_s.mounted || !c.hasClients) return;
    final pos = c.position;
    final target = end ? pos.maxScrollExtent : pos.minScrollExtent;
    if (pos.pixels == target || left == 0) return;
    pos.jumpTo(target);
    WidgetsBinding.instance.addPostFrameCallback((_) => _jump(end, left - 1));
  }
}
