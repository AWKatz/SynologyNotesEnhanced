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

  /// The actual primary + secondaryContainer colors an accent seed produces
  /// once themed for [brightness] — i.e. what buttons and tags/chips will
  /// really look like — rather than the raw seed value. `secondaryContainer`
  /// (not the raw `secondary` role, which the built theme never actually
  /// paints anywhere — see `_buildTheme`'s chipTheme/navigationBarTheme) is
  /// what tag chips and nav selection really use. Material's tonal algorithm
  /// (especially the `vibrant` variant) can shift these noticeably from the
  /// seed and from each other, and grey accents are computed specially (see
  /// `_monochromeOverlay`), so a swatch picker should preview both roles it
  /// actually drives, not just the raw palette entry or `primary` alone — a
  /// single-color dot can look like a different color than the tags the pick
  /// actually produces.
  static (Color primary, Color secondaryContainer) previewSchemeFor(
      Color accent, Brightness brightness) {
    final neutral =
        ColorScheme.fromSeed(seedColor: _neutralSeed, brightness: brightness);
    final cs = _isAchromatic(accent)
        ? _monochromeOverlay(accent, neutral, brightness)
        : _seededOverlay(accent, neutral, brightness);
    return (cs.primary, cs.secondaryContainer);
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
    // Material 3's default tonal mapping (tonalSpot) noticeably mutes a
    // seed's chroma at light mode's tone-40 primary — the same seed reads
    // as much punchier once placed on a dark background at a higher tone,
    // so dark mode doesn't need this. `vibrant` raises chroma across the
    // palette instead of clamping toward the muted default.
    final accented = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      dynamicSchemeVariant: brightness == Brightness.light
          ? DynamicSchemeVariant.vibrant
          : DynamicSchemeVariant.tonalSpot,
    );

    // `vibrant` still isn't enough on its own for yellow-green/cyan hues
    // (amber, green, teal): HCT's in-gamut chroma ceiling at a given tone
    // varies a lot by hue, and those hues simply top out lower than blues
    // or magentas/reds do — no scheme variant changes that ceiling. HSL
    // saturation doesn't have that same per-hue ceiling (100% is always
    // in-gamut for every hue), so boost saturation directly as a light-mode
    // finishing pass; only lightness (~contrast) is left untouched. Already-
    // vivid hues are near-saturated post-`vibrant` already, so the clamp
    // makes this a no-op for them rather than over-saturating.
    final isLight = brightness == Brightness.light;
    final primary =
        isLight ? _boostSaturation(accented.primary) : accented.primary;
    final primaryContainer = isLight
        ? _boostSaturation(accented.primaryContainer)
        : accented.primaryContainer;
    final secondary =
        isLight ? _boostSaturation(accented.secondary) : accented.secondary;
    final secondaryContainer = isLight
        ? _boostSaturation(accented.secondaryContainer)
        : accented.secondaryContainer;
    final tertiary =
        isLight ? _boostSaturation(accented.tertiary) : accented.tertiary;
    final tertiaryContainer = isLight
        ? _boostSaturation(accented.tertiaryContainer)
        : accented.tertiaryContainer;

    return neutral.copyWith(
      primary: primary,
      onPrimary: accented.onPrimary,
      primaryContainer: primaryContainer,
      onPrimaryContainer: accented.onPrimaryContainer,
      secondary: secondary,
      onSecondary: accented.onSecondary,
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: accented.onSecondaryContainer,
      tertiary: tertiary,
      onTertiary: accented.onTertiary,
      tertiaryContainer: tertiaryContainer,
      onTertiaryContainer: accented.onTertiaryContainer,
    );
  }

  /// Raises HSL saturation by [factor] at fixed hue/lightness, clamped to
  /// 100%. Unlike HCT chroma, HSL saturation's max is always in-gamut for
  /// every hue, so this is a safe way to push yellow-green/cyan hues (whose
  /// HCT chroma ceiling is much lower than blue/red/magenta's) closer to as
  /// vivid as blue/red/magenta already read post-`vibrant`.
  static Color _boostSaturation(Color c, {double factor = 1.35}) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withSaturation((hsl.saturation * factor).clamp(0.0, 1.0))
        .toColor();
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

    final container =
        isDark ? shade(channel * 0.35) : shade(channel + (1 - channel) * 0.55);
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
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: cs.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: cs.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
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
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
          textStyle:
              GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      // Samsung Notes' cards read as flat with only a hairline/soft shadow,
      // not Material's tonal elevation. Still needs a tone distinct from
      // `surface` (what most screens use as their page background), or a
      // Card becomes only visible via its shadow — surfaceContainerLow is
      // a subtle-but-real step up, flatter than the old surfaceContainer.
      cardTheme: CardThemeData(
        color: cs.surfaceContainerLow,
        elevation: 1,
        shadowColor: cs.shadow.withValues(alpha: 0.15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: EdgeInsets.zero,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        // The reference FAB is a plain (not accent-filled) circle with a
        // colored icon, so this uses a neutral tone rather than `primary` —
        // but it must still be a genuinely different tone from the panel
        // background it floats over (`surface`), or it's only visible via
        // its shadow. `surfaceContainerHigh` gives that contrast in both
        // light and dark, the way the reference's white FAB stands out
        // against its light grey page.
        backgroundColor: cs.surfaceContainerHigh,
        foregroundColor: cs.primary,
        elevation: 3,
        shape: const CircleBorder(),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
