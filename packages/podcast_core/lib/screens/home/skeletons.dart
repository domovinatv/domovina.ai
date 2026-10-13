import 'package:flutter/material.dart';

import 'hero_carousel.dart' show kHeroControlBarHeight;
import 'hero_section.dart' show heroSplitImageWidth, heroSplitTextPadding;

/// Animated shimmer box — koristi se kao loading placeholder.
///
/// Custom implementacija bez paketa: AnimationController + LinearGradient
/// koji se animira preko Container-a.
class ShimmerBox extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  const ShimmerBox({super.key, this.width, this.height, this.borderRadius});

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.colorScheme.surfaceContainerHigh;
    final highlightColor = theme.colorScheme.surfaceContainerHighest;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2 * t, -0.3),
              end: Alignment(1.0 + 2 * t, 0.3),
              colors: [baseColor, highlightColor, baseColor],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton za horizontalni rail — eyebrow + 4 kartice s placeholderom.
class RailSkeleton extends StatelessWidget {
  final bool isMobile;

  const RailSkeleton({super.key, required this.isMobile});

  @override
  Widget build(BuildContext context) {
    final cardWidth = isMobile ? 180.0 : 220.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ShimmerBox(
              height: 12,
              width: 140,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: isMobile ? 240 : 270,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 5,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final coverH = cardWidth * 9 / 16;
                return SizedBox(
                  width: cardWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShimmerBox(
                        height: coverH,
                        width: cardWidth,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      const SizedBox(height: 10),
                      ShimmerBox(
                        height: 11,
                        width: cardWidth * 0.5,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 8),
                      ShimmerBox(
                        height: 14,
                        width: cardWidth,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 6),
                      ShimmerBox(
                        height: 14,
                        width: cardWidth * 0.7,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton za channel grid — N kartica u Wrap-u.
class ChannelGridSkeleton extends StatelessWidget {
  final bool isMobile;
  final int count;

  const ChannelGridSkeleton({
    super.key,
    required this.isMobile,
    this.count = 6,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - 32;
        final columns = isMobile ? 1 : (width / 360).floor().clamp(2, 99);
        final cardWidth = columns == 1
            ? width
            : (width - (columns - 1) * 16) / columns;
        final coverH = cardWidth * 9 / 16;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: List.generate(count, (_) {
              return SizedBox(
                width: cardWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox(
                      height: coverH,
                      width: cardWidth,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    const SizedBox(height: 14),
                    ShimmerBox(
                      height: 11,
                      width: cardWidth * 0.6,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 10),
                    ShimmerBox(
                      height: 22,
                      width: cardWidth * 0.85,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

/// Hero skeleton — split layout (slika lijevo, text desno) na desktop,
/// stack (slika gore, text dolje) na mobile.
class HeroSkeleton extends StatelessWidget {
  final bool isMobile;

  /// Mjesto za kontrolnu traku karusela ("U ROTACIJI" + dots), koju
  /// [HeroCarousel] crta ispod kartice. Rezerviramo ga da otkrivanje hero-a ne
  /// pomakne cijelu stranicu prema dolje.
  ///
  /// **Rule**: dimenzije ispod nisu dekorativne — namjerno reproduciraju
  /// visinu pravog [HeroSection]a (2-redni naslov). Ako se hero layout mijenja,
  /// mijenja se i ovaj skeleton, inace se vrati skok pri otkrivanju.
  final bool reserveControlBar;

  const HeroSkeleton({
    super.key,
    required this.isMobile,
    this.reserveControlBar = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          // Isti padding kao slide u karuselu (donji je stisnut jer kontrolna
          // traka dolazi ispod).
          padding: reserveControlBar
              ? const EdgeInsets.fromLTRB(16, 8, 16, 4)
              : const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: isMobile ? _mobile() : _desktop(),
          ),
        ),
        if (reserveControlBar) _controlBar(),
      ],
    );
  }

  Widget _desktop() {
    // Isto pravilo širine kao HeroSection._desktopLayout.
    return LayoutBuilder(
      builder: (context, constraints) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: heroSplitImageWidth(constraints.maxWidth),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: const ShimmerBox(borderRadius: BorderRadius.zero),
              ),
            ),
            Expanded(
              child: Padding(
                padding: heroSplitTextPadding(constraints.maxWidth),
                child: _textLines(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mobile() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: const ShimmerBox(borderRadius: BorderRadius.zero),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: _textLines(),
        ),
      ],
    );
  }

  /// Visine prate `HeroSection._content` red po red (izmjereno widget testom,
  /// `test/hero_slot_layout_test.dart`):
  /// eyebrow 17 + 12 + naslov 2 retka 56 (24 px × height 1.15) + 10 +
  /// meta red 21 + 16 + CTA gumbi 48 = **180 px**.
  ///
  /// Meta red je ovdje uvijek jedan redak. `HeroSection` ga crta `Wrap`-om, pa
  /// na jako uskom ekranu s dugim imenom kanala može prijeći u dva retka —
  /// tada je pravi hero za jedan redak viši od skeletona.
  Widget _textLines() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Eyebrow ("— ISTAKNUTO  (?) ZAŠTO?")
        ShimmerBox(
          height: 17,
          width: 150,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 12),
        // Naslov, 2 retka (20 + 16 + 20 = 56)
        ShimmerBox(
          height: 20,
          width: 340,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 16),
        ShimmerBox(
          height: 20,
          width: 250,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 10),
        // Meta red (kanal · datum · trajanje)
        ShimmerBox(
          height: 21,
          width: 220,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 16),
        // CTA gumbi ("Slušaj" / "Spremi") — 48 px zbog padded tap targeta.
        // scaleDown kao u HeroSection: na uskom splitu se smanje, ne probiju.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShimmerBox(
                height: 48,
                width: 118,
                borderRadius: BorderRadius.circular(10),
              ),
              const SizedBox(width: 10),
              ShimmerBox(
                height: 48,
                width: 118,
                borderRadius: BorderRadius.circular(10),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Prazna kontrolna traka karusela — badge lijevo, dots desno. Visina mora
  /// ostati [kHeroControlBarHeight], jednako `_HeroCarouselState._controlBar`.
  Widget _controlBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 18),
      child: Row(
        children: [
          ShimmerBox(
            height: 20,
            width: 96,
            borderRadius: BorderRadius.circular(20),
          ),
          const Spacer(),
          for (var i = 0; i < 5; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: ShimmerBox(
                height: 7,
                width: i == 0 ? 22 : 7,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }
}
