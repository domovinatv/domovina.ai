import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/refresh_all.dart';

/// Omotač oko cijele aplikacije (`MaterialApp.builder`) koji uz
/// `?osvjezi=1` crta mali gumb „Osvježi sve" u donjem lijevom kutu.
/// Bez zastavice vraća [child] netaknut. Vidi `services/refresh_all.dart`.
///
/// Iznad je Navigatora, pa nema `Overlay` — zato bez `Tooltip`a, samo
/// `Semantics` oznaka.
class RefreshAllOverlay extends StatefulWidget {
  const RefreshAllOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<RefreshAllOverlay> createState() => _RefreshAllOverlayState();
}

class _RefreshAllOverlayState extends State<RefreshAllOverlay> {
  late final bool _visible = refreshAllButtonVisible();
  bool _busy = false;

  Future<void> _onTap() async {
    if (_busy) return;
    setState(() => _busy = true);
    await refreshAll();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return widget.child;
    final scheme = Theme.of(context).colorScheme;
    final label = AppLocalizations.of(context).devRefreshAll;
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 12,
          bottom: 96,
          child: SafeArea(
            child: Semantics(
              button: true,
              label: label,
              child: Material(
                color: scheme.tertiary,
                shape: const CircleBorder(),
                elevation: 4,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _onTap,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: _busy
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: scheme.onTertiary,
                              ),
                            )
                          : Icon(Icons.refresh, color: scheme.onTertiary),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
