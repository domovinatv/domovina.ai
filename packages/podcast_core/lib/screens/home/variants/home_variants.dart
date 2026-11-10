import 'package:flutter/widgets.dart';

import 'home_variant.dart';
import 'home_variant_a.dart';
import 'home_variant_b.dart';
import 'home_variant_c.dart';
import 'home_variant_data.dart';

export 'home_variant.dart';
export 'home_variant_data.dart';

/// Jedina točka ulaza iz `home_screen.dart` (grananje prije postojećeg
/// `CustomScrollView`-a). Vidi `home_variant.dart`.
Widget buildHomeVariant(HomeVariant variant, HomeVariantData data) =>
    switch (variant) {
      HomeVariant.a => HomeVariantA(data: data),
      HomeVariant.b => HomeVariantB(data: data),
      HomeVariant.c => HomeVariantC(data: data),
    };
