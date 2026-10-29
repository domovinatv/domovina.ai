import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_fonts/google_fonts.dart';

/// Editorial typography za DOMOVINA.ai.
///
/// **Fontovi se registriraju kroz `google_fonts` na SVIM platformama, i na
/// webu.** Ranije je web imao zasebnu granu koja je samo postavljala
/// `fontFamily: 'Playfair Display'` i računala da će font stići preko
/// `<link>`-a u `web/index.html`. To je radilo dok je postojao HTML renderer;
/// canvaskit/skwasm ne čita `@font-face` iz dokumenta, pa je Flutter tekst
/// padao na ugrađeni fallback — naslovi i wordmark su se na webu crtali
/// sans-serifom umjesto Playfairom, a pojedini glyphovi bi nestali dok
/// asinkroni Noto fallback ne stigne.
///
/// `<link>` u `web/index.html` NIJE višak — njime se crta HTML boot-intro
/// splash (pravi DOM, prije nego Flutter uopće starta).
///
/// [startPreload] + [awaitPreload] skidaju sve varijante PRIJE `runApp` da
/// tekst ne bljesne u fallback fontu pa se prelomi kad pravi font stigne.
class AppTypography {
  /// Sve (obitelj, težina) kombinacije koje tema stvarno koristi. Preload ih
  /// vrti redom; nova težina u [textTheme] mora doći i ovamo, inače ta grana
  /// prvi put stiže tek u buildu (i bljesne).
  static final List<TextStyle Function()> _usedVariants = [
    () => _playfairStyle(fontSize: 16, fontWeight: FontWeight.w600),
    () => _playfairStyle(fontSize: 16, fontWeight: FontWeight.w700),
    () => _playfairStyle(fontSize: 16, fontWeight: FontWeight.w800),
    () => _loraStyle(fontSize: 16, fontWeight: FontWeight.w400),
    () => _interStyle(fontSize: 16, fontWeight: FontWeight.w400),
    () => _interStyle(fontSize: 16, fontWeight: FontWeight.w500),
    () => _interStyle(fontSize: 16, fontWeight: FontWeight.w600),
  ];

  static bool _preloadStarted = false;

  /// Pokreni skidanje svih korištenih varijanti. Zovi ODMAH na početku
  /// `main()` — dok teku ostali `await`-ovi (Supabase, auth, prefs) fontovi
  /// stignu u pozadini, pa [awaitPreload] na kraju obično čeka ~0 ms.
  static void startPreload() {
    if (_preloadStarted) return;
    _preloadStarted = true;
    // Varijante iz _usedVariants su u assetima paketa (assets/google_fonts/),
    // pa ih google_fonts uzima odande umjesto s fonts.gstatic.com: na webu
    // s našeg hosta (Inter srezan, ~0,4 MB manje), na nativeu bez mreže.
    // OFL traži da licenca putuje s fontom.
    LicenseRegistry.addLicense(_fontLicenses);
    for (final variant in _usedVariants) {
      variant();
    }
  }

  static Stream<LicenseEntry> _fontLicenses() async* {
    for (final (family, file) in const [
      ('Playfair Display', 'OFL-PlayfairDisplay.txt'),
      ('Lora', 'OFL-Lora.txt'),
      ('Inter', 'OFL-Inter.txt'),
    ]) {
      final text = await rootBundle
          .loadString('packages/podcast_core/assets/google_fonts/$file');
      yield LicenseEntryWithLineBreaks([family], text);
    }
  }

  /// Pričekaj da preload završi, ali ne duže od [timeout] — spor gstatic ne
  /// smije zaustaviti boot. Ako istekne, tekst se jednom prelomi kad font
  /// naknadno stigne (isto ponašanje kao prije, samo rijetko).
  static Future<void> awaitPreload({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    startPreload();
    try {
      await GoogleFonts.pendingFonts().timeout(timeout);
    } catch (_) {
      // Nema mreže / spor CDN — nastavi s fallback fontom.
    }
  }

  /// Playfair Display — display/headline (editorial serif).
  static TextStyle _playfairStyle({
    required double fontSize,
    required FontWeight fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.playfairDisplay(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static TextStyle _loraStyle({
    required double fontSize,
    required FontWeight fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.lora(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static TextStyle _interStyle({
    required double fontSize,
    required FontWeight fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  /// Material 3 TextTheme mapping. Display + headline koriste Playfair
  /// (editorial), title + label + bodyMedium/Small koriste Inter (UI), a
  /// bodyLarge koristi Lora (serif za long-form text poput hero opisa).
  static TextTheme textTheme(ColorScheme scheme) {
    final onSurface = scheme.onSurface;

    return TextTheme(
      // Hero / display
      displayLarge: _playfairStyle(
        fontSize: 56,
        fontWeight: FontWeight.w800,
        color: onSurface,
        height: 1.05,
        letterSpacing: -0.5,
      ),
      displayMedium: _playfairStyle(
        fontSize: 44,
        fontWeight: FontWeight.w700,
        color: onSurface,
        height: 1.1,
        letterSpacing: -0.3,
      ),
      displaySmall: _playfairStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: onSurface,
        height: 1.15,
      ),

      // Section headlines, channel card titles
      headlineLarge: _playfairStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: onSurface,
        height: 1.2,
      ),
      headlineMedium: _playfairStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: onSurface,
        height: 1.25,
      ),
      headlineSmall: _playfairStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: onSurface,
        height: 1.3,
      ),

      // Titles (UI sans-serif)
      titleLarge: _interStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: onSurface,
        height: 1.3,
      ),
      titleMedium: _interStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: onSurface,
        height: 1.35,
        letterSpacing: 0.1,
      ),
      titleSmall: _interStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: onSurface,
        height: 1.4,
        letterSpacing: 0.1,
      ),

      // Body — bodyLarge je serif (Lora) za hero description / editorial body.
      bodyLarge: _loraStyle(
        fontSize: 17,
        fontWeight: FontWeight.w400,
        color: onSurface,
        height: 1.55,
      ),
      bodyMedium: _interStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: onSurface,
        height: 1.5,
        letterSpacing: 0.15,
      ),
      bodySmall: _interStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: scheme.onSurfaceVariant,
        height: 1.45,
        letterSpacing: 0.2,
      ),

      // Labels — buttons, chips, all-caps section eyebrows.
      labelLarge: _interStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: onSurface,
        letterSpacing: 0.3,
      ),
      labelMedium: _interStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: onSurface,
        letterSpacing: 0.5,
      ),
      // labelSmall se koristi kao "eyebrow" all-caps oznaka iznad sekcija
      // (npr. "ISTAKNUTO", "NASTAVI SLUŠATI"). Veliki letterSpacing.
      labelSmall: _interStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: scheme.onSurfaceVariant,
        letterSpacing: 1.4,
      ),
    );
  }

  /// Wordmark stil za "DOMOVINA.ai" u app baru (Playfair 800).
  static TextStyle wordmarkStyle({required Color color, double fontSize = 22}) {
    return _playfairStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      color: color,
      letterSpacing: 0.5,
    );
  }

  /// Eyebrow stil — all-caps mala oznaka iznad sekcija ("ISTAKNUTO").
  static TextStyle eyebrowStyle(ColorScheme scheme) {
    return _interStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: scheme.onSurfaceVariant,
      letterSpacing: 1.6,
    );
  }
}
