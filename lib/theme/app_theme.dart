import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  /// Default accent seed color, used until the user picks one in Settings.
  static const defaultSeed = Color(0xFF2C76DD);

  /// Fixed neutral seed for surfaces/background — deliberately NOT the
  /// accent color. `ColorScheme.fromSeed` only applies a faint, low-chroma
  /// hue tint to neutrals regardless of the seed, so under the old
  /// single-seed-drives-everything model, a "dark grey" accent and a "blue"
  /// accent produced nearly identical-looking backgrounds — the visible
  /// difference only ever showed up in primary/secondary. Deriving surfaces
  /// from this fixed grey instead means the background is 100% identical
  /// across every accent choice, controlled only by System/Light/Dark.
  static const _neutralSeed = Color(0xFF6B6B6B);

  /// A curated palette users can pick an accent color from. Each seed
  /// supplies ONLY the primary/secondary/tertiary roles (buttons, tags,
  /// selected states, focus rings) — never the background/surface colors,
  /// which come from [_neutralSeed] and the System/Light/Dark choice.
  ///
  /// Hues are spaced ~45° apart around the color wheel by construction (not
  /// picked ad hoc), so adjacent swatches read as clearly different colors.
  static const accentPalette = [
    defaultSeed, // blue (default)
    Color(0xFFEF9906), // amber
    Color(0xFF64962C), // lime
    Color(0xFF259349), // green
    Color(0xFF0C9097), // teal
    Color(0xFF6C3DB8), // violet
    Color(0xFFBD2887), // magenta
    Color(0xFFDB2433), // red
    Color(0xFFE1E1E1), // light grey — high-contrast monochrome accent
  ];

  static ThemeData light([Color accent = defaultSeed]) =>
      _themeFor(accent, Brightness.light);

  static ThemeData dark([Color accent = defaultSeed]) =>
      _themeFor(accent, Brightness.dark);

  /// The actual `primary` color an accent seed produces once themed for
  /// [brightness] — i.e. what buttons/tags will really look like — rather
  /// than the raw seed value. Material's tonal algorithm can shift a seed's
  /// brightness/tone noticeably from the seed itself, and grey accents are
  /// computed specially (see `_monochromeOverlay`), so a swatch picker
  /// should preview this, not the raw palette entry, to avoid the color you
  /// pick looking different from the swatch you picked it from.
  static Color previewColorFor(Color accent, Brightness brightness) {
    final neutral =
        ColorScheme.fromSeed(seedColor: _neutralSeed, brightness: brightness);
    final cs = _isAchromatic(accent)
        ? _monochromeOverlay(accent, neutral, brightness)
        : _seededOverlay(accent, neutral, brightness);
    return cs.primary;
  }

  static ThemeData _themeFor(Color accent, Brightness brightness) {
    final neutral =
        ColorScheme.fromSeed(seedColor: _neutralSeed, brightness: brightness);

    // `ColorScheme.fromSeed` derives hue/chroma via the HCT color space,
    // where hue is ill-defined right at (or very near) zero saturation —
    // in practice this makes a grey seed come out with a stray green/purple
    // tint instead of neutral. Bypass seed-derivation entirely for
    // achromatic accents and compute the roles as true greyscale instead.
    final cs = _isAchromatic(accent)
        ? _monochromeOverlay(accent, neutral, brightness)
        : _seededOverlay(accent, neutral, brightness);

    return _buildTheme(cs, brightness);
  }

  static bool _isAchromatic(Color c) {
    final argb = c.toARGB32();
    final r = (argb >> 16) & 0xFF, g = (argb >> 8) & 0xFF, b = argb & 0xFF;
    return r == g && g == b;
  }

  // Background/surface roles stay neutral (from [neutral]); only the
  // accent-driven roles (buttons, tags/chips, selection, focus) come from
  // the chosen color's own seeded scheme.
  static ColorScheme _seededOverlay(
      Color accent, ColorScheme neutral, Brightness brightness) {
    final accented =
        ColorScheme.fromSeed(seedColor: accent, brightness: brightness);
    return neutral.copyWith(
      primary: accented.primary,
      onPrimary: accented.onPrimary,
      primaryContainer: accented.primaryContainer,
      onPrimaryContainer: accented.onPrimaryContainer,
      secondary: accented.secondary,
      onSecondary: accented.onSecondary,
      secondaryContainer: accented.secondaryContainer,
      onSecondaryContainer: accented.onSecondaryContainer,
      tertiary: accented.tertiary,
      onTertiary: accented.onTertiary,
      tertiaryContainer: accented.tertiaryContainer,
      onTertiaryContainer: accented.onTertiaryContainer,
    );
  }

  // Grey accents computed as plain greyscale (equal R=G=B throughout) —
  // no HCT hue/chroma involved anywhere, so there's no way for a stray tint
  // to sneak in. `grey` becomes primary/secondary/tertiary directly; the
  // container tones push toward the opposite pole (lighter in dark mode,
  // deeper in light mode) the way a color relates to its own container in
  // a normal seeded scheme; "on" colors are picked by simple contrast.
  static ColorScheme _monochromeOverlay(
      Color grey, ColorScheme neutral, Brightness brightness) {
    final channel = (grey.toARGB32() & 0xFF) / 255.0; // R=G=B already
    final isDark = brightness == Brightness.dark;

    Color shade(double lightness) {
      final v = (lightness.clamp(0.0, 1.0) * 255).round();
      return Color.fromARGB(255, v, v, v);
    }

    Color onFor(Color bg) =>
        (bg.toARGB32() & 0xFF) > 140 ? const Color(0xFF1A1A1A) : Colors.white;

    final container = isDark
        ? shade(channel * 0.35)
        : shade(channel + (1 - channel) * 0.55);
    final onMain = onFor(grey);
    final onContainer = onFor(container);

    return neutral.copyWith(
      primary: grey,
      onPrimary: onMain,
      primaryContainer: container,
      onPrimaryContainer: onContainer,
      secondary: grey,
      onSecondary: onMain,
      secondaryContainer: container,
      onSecondaryContainer: onContainer,
      tertiary: grey,
      onTertiary: onMain,
      tertiaryContainer: container,
      onTertiaryContainer: onContainer,
    );
  }

  static ThemeData _buildTheme(ColorScheme cs, Brightness brightness) {
    final base = ThemeData(brightness: brightness);

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      brightness: brightness,
      scaffoldBackgroundColor: cs.surface,
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.inter(
          color: cs.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: cs.outlineVariant,
        thickness: 1,
        space: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.error, width: 2),
        ),
        labelStyle: TextStyle(color: cs.onSurfaceVariant),
        hintStyle: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
        prefixIconColor: cs.onSurfaceVariant,
        suffixIconColor: cs.onSurfaceVariant,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          disabledBackgroundColor: cs.onSurface.withValues(alpha: 0.12),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
          textStyle:
              GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      cardTheme: CardThemeData(
        color: cs.surfaceContainer,
        elevation: 0,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: cs.secondaryContainer,
        labelStyle: TextStyle(
          color: cs.onSecondaryContainer,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
        padding: EdgeInsets.zero,
        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return cs.onPrimary;
          return cs.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return cs.primary;
          return cs.surfaceContainerHighest;
        }),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cs.surfaceContainer,
        indicatorColor: cs.secondaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: cs.onSecondaryContainer);
          }
          return IconThemeData(color: cs.onSurfaceVariant);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.inter(
              color: cs.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            );
          }
          return GoogleFonts.inter(color: cs.onSurfaceVariant, fontSize: 12);
        }),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: cs.surfaceContainerHigh,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
        textStyle: TextStyle(color: cs.onSurface),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: cs.primary),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
      ),
    );
  }
}
