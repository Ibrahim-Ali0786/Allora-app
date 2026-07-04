import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Central design tokens for Allora.
///
/// Every screen reads colors through [AlloraColors.of] (via `context.allora`)
/// instead of hard-coding hex values, so light/dark theming stays consistent
/// across the whole app.
class AlloraColors extends ThemeExtension<AlloraColors> {
  final Color canvas; // page background
  final Color surface; // cards, sheets, bubbles (theirs)
  final Color surfaceAlt; // input fills, chips
  final Color outline; // hairline borders
  final Color text;
  final Color textSecondary;
  final Color textTertiary;
  final Color accent;
  final Color onAccent;
  final Color bubbleMine;
  final Color bubbleMineDeep; // gradient end for own bubbles
  final Color success;
  final Color danger;
  final Color warning;

  const AlloraColors({
    required this.canvas,
    required this.surface,
    required this.surfaceAlt,
    required this.outline,
    required this.text,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.onAccent,
    required this.bubbleMine,
    required this.bubbleMineDeep,
    required this.success,
    required this.danger,
    required this.warning,
  });

  static const light = AlloraColors(
    canvas: Color(0xFFF7F7FA),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF1F2F6),
    outline: Color(0xFFE7E8EE),
    text: Color(0xFF17181C),
    textSecondary: Color(0xFF6E7076),
    textTertiary: Color(0xFFA6A8B1),
    accent: Color(0xFF3A6FF8),
    onAccent: Colors.white,
    bubbleMine: Color(0xFF3A6FF8),
    bubbleMineDeep: Color(0xFF2F5CE0),
    success: Color(0xFF1F9D55),
    danger: Color(0xFFE5484D),
    warning: Color(0xFFF5A623),
  );

  static const dark = AlloraColors(
    canvas: Color(0xFF0D0E12),
    surface: Color(0xFF17181D),
    surfaceAlt: Color(0xFF1F2026),
    outline: Color(0xFF2A2C33),
    text: Color(0xFFF4F5F7),
    textSecondary: Color(0xFFA0A2AB),
    textTertiary: Color(0xFF5F6169),
    accent: Color(0xFF5B87FF),
    onAccent: Colors.white,
    bubbleMine: Color(0xFF3A6FF8),
    bubbleMineDeep: Color(0xFF2E56C9),
    success: Color(0xFF2FBF71),
    danger: Color(0xFFFF6369),
    warning: Color(0xFFFFB224),
  );

  /// Pure-black variant for OLED screens.
  static const amoled = AlloraColors(
    canvas: Color(0xFF000000),
    surface: Color(0xFF0B0B0D),
    surfaceAlt: Color(0xFF161619),
    outline: Color(0xFF232327),
    text: Color(0xFFF4F5F7),
    textSecondary: Color(0xFF9EA0A9),
    textTertiary: Color(0xFF5A5C64),
    accent: Color(0xFF5B87FF),
    onAccent: Colors.white,
    bubbleMine: Color(0xFF3A6FF8),
    bubbleMineDeep: Color(0xFF2E56C9),
    success: Color(0xFF2FBF71),
    danger: Color(0xFFFF6369),
    warning: Color(0xFFFFB224),
  );

  static AlloraColors of(BuildContext context) =>
      Theme.of(context).extension<AlloraColors>() ?? light;

  @override
  AlloraColors copyWith({Color? accent, Color? bubbleMine, Color? bubbleMineDeep}) {
    return AlloraColors(
      canvas: canvas,
      surface: surface,
      surfaceAlt: surfaceAlt,
      outline: outline,
      text: text,
      textSecondary: textSecondary,
      textTertiary: textTertiary,
      accent: accent ?? this.accent,
      onAccent: onAccent,
      bubbleMine: bubbleMine ?? this.bubbleMine,
      bubbleMineDeep: bubbleMineDeep ?? this.bubbleMineDeep,
      success: success,
      danger: danger,
      warning: warning,
    );
  }

  @override
  AlloraColors lerp(ThemeExtension<AlloraColors>? other, double t) {
    if (other is! AlloraColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AlloraColors(
      canvas: l(canvas, other.canvas),
      surface: l(surface, other.surface),
      surfaceAlt: l(surfaceAlt, other.surfaceAlt),
      outline: l(outline, other.outline),
      text: l(text, other.text),
      textSecondary: l(textSecondary, other.textSecondary),
      textTertiary: l(textTertiary, other.textTertiary),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      bubbleMine: l(bubbleMine, other.bubbleMine),
      bubbleMineDeep: l(bubbleMineDeep, other.bubbleMineDeep),
      success: l(success, other.success),
      danger: l(danger, other.danger),
      warning: l(warning, other.warning),
    );
  }
}

extension AlloraColorsX on BuildContext {
  AlloraColors get allora => AlloraColors.of(this);
}

/// Selectable accent presets (Settings > Appearance).
class AlloraAccent {
  final String name;
  final Color color;
  final Color deep;
  const AlloraAccent(this.name, this.color, this.deep);
}

const kAccentPresets = <AlloraAccent>[
  AlloraAccent('Allora Blue', Color(0xFF3A6FF8), Color(0xFF2F5CE0)),
  AlloraAccent('Violet', Color(0xFF7C5CFC), Color(0xFF6847E6)),
  AlloraAccent('Teal', Color(0xFF00A3AD), Color(0xFF008A93)),
  AlloraAccent('Rose', Color(0xFFE45794), Color(0xFFCC417E)),
  AlloraAccent('Amber', Color(0xFFE8930C), Color(0xFFCB7E05)),
  AlloraAccent('Green', Color(0xFF1FA45B), Color(0xFF178A4B)),
];

class AppTheme {
  AppTheme._();

  /// Tests (and font-less environments) can disable Google Fonts so theme
  /// construction never depends on a bundled asset or the network.
  static bool useGoogleFonts = true;

  /// GoogleFonts.inter with a graceful fallback to the system font.
  static TextStyle _interSafe({
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
  }) {
    if (useGoogleFonts) {
      try {
        return GoogleFonts.inter(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: letterSpacing,
        );
      } catch (_) {
        // fall through to the system font
      }
    }
    return TextStyle(
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
    );
  }

  static ThemeData light({
    int accentIndex = 0,
    bool highContrast = false,
    bool reduceMotion = false,
  }) =>
      _build(
        highContrast ? _boostContrast(AlloraColors.light) : AlloraColors.light,
        Brightness.light,
        accentIndex,
        reduceMotion,
      );

  static ThemeData dark({
    int accentIndex = 0,
    bool amoled = false,
    bool highContrast = false,
    bool reduceMotion = false,
  }) {
    var base = amoled ? AlloraColors.amoled : AlloraColors.dark;
    if (highContrast) base = _boostContrast(base);
    return _build(base, Brightness.dark, accentIndex, reduceMotion);
  }

  /// Darkens/strengthens outlines and secondary text so structure is easier
  /// to see — the Accessibility "High contrast" toggle.
  static AlloraColors _boostContrast(AlloraColors c) => AlloraColors(
        canvas: c.canvas,
        surface: c.surface,
        surfaceAlt: c.surfaceAlt,
        outline: Color.alphaBlend(
            c.text.withValues(alpha: 0.35), c.outline),
        text: c.text,
        textSecondary: Color.alphaBlend(
            c.text.withValues(alpha: 0.35), c.textSecondary),
        textTertiary: Color.alphaBlend(
            c.text.withValues(alpha: 0.30), c.textTertiary),
        accent: c.accent,
        onAccent: c.onAccent,
        bubbleMine: c.bubbleMine,
        bubbleMineDeep: c.bubbleMineDeep,
        success: c.success,
        danger: c.danger,
        warning: c.warning,
      );

  static ThemeData _build(AlloraColors base, Brightness brightness,
      int accentIndex, [bool reduceMotion = false]) {
    final preset = kAccentPresets[accentIndex.clamp(0, kAccentPresets.length - 1)];
    final c = base.copyWith(
      accent: brightness == Brightness.dark
          ? Color.lerp(preset.color, Colors.white, 0.12)
          : preset.color,
      bubbleMine: preset.color,
      bubbleMineDeep: preset.deep,
    );

    final scheme = ColorScheme.fromSeed(
      seedColor: c.accent,
      brightness: brightness,
      surface: c.surface,
    );

    final baseTextTheme = brightness == Brightness.dark
        ? ThemeData.dark().textTheme
        : ThemeData.light().textTheme;
    TextTheme interTheme = baseTextTheme;
    if (useGoogleFonts) {
      try {
        interTheme = GoogleFonts.interTextTheme(baseTextTheme);
      } catch (_) {
        interTheme = baseTextTheme;
      }
    }
    final textTheme =
        interTheme.apply(bodyColor: c.text, displayColor: c.text);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.canvas,
      splashFactory: InkSparkle.splashFactory,
      textTheme: textTheme,
      extensions: [c],
      appBarTheme: AppBarTheme(
        backgroundColor: c.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: c.text),
        titleTextStyle: AppTheme._interSafe(
          color: c.text,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      dividerTheme: DividerThemeData(color: c.outline, thickness: 1, space: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: c.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
        dragHandleColor: c.outline,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: brightness == Brightness.dark ? c.surfaceAlt : const Color(0xFF26272C),
        contentTextStyle: AppTheme._interSafe(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: AppTheme._interSafe(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.text,
          side: BorderSide(color: c.outline),
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: AppTheme._interSafe(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accent,
          textStyle: AppTheme._interSafe(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceAlt,
        hintStyle: AppTheme._interSafe(color: c.textTertiary, fontSize: 15),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c.accent, width: 1.4),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.textSecondary,
        titleTextStyle: AppTheme._interSafe(
            color: c.text, fontSize: 15.5, fontWeight: FontWeight.w500),
        subtitleTextStyle: AppTheme._interSafe(color: c.textSecondary, fontSize: 13),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? c.onAccent : c.textTertiary),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? c.accent : c.surfaceAlt),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? Colors.transparent : c.outline),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceAlt,
        selectedColor: c.accent,
        labelStyle: AppTheme._interSafe(
            fontSize: 13, fontWeight: FontWeight.w600, color: c.textSecondary),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: AppTheme._interSafe(color: c.text, fontSize: 14.5),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent),
      tabBarTheme: TabBarThemeData(
        labelColor: c.accent,
        unselectedLabelColor: c.textSecondary,
        indicatorColor: c.accent,
        dividerColor: Colors.transparent,
      ),
      // Premium navigation: iOS-style slide + parallax with edge
      // swipe-to-go-back on Android and iOS. Reduce-motion swaps every push
      // for a plain cross-fade.
      pageTransitionsTheme: PageTransitionsTheme(
        builders: reduceMotion
            ? const {
                TargetPlatform.android: _FadeThroughBuilder(),
                TargetPlatform.iOS: _FadeThroughBuilder(),
              }
            : const {
                TargetPlatform.android: CupertinoPageTransitionsBuilder(),
                TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
              },
      ),
    );
  }
}

/// Cross-fade page transition used when "Reduce motion" is on.
class _FadeThroughBuilder extends PageTransitionsBuilder {
  const _FadeThroughBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    );
  }
}
