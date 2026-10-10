import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Travelgram's palette: warm neutrals, one terracotta accent for actions,
/// and a deep teal for "I'm going". Photos carry the colour; the UI doesn't.
abstract final class TG {
  static const bg = Color(0xFFFFFFFF);
  static const surface = Color(0xFFF5F5F4);
  static const surfaceHigh = Color(0xFFEDEBE9);
  static const line = Color(0xFFE7E5E4);
  static const ink = Color(0xFF1C1917);
  static const ink2 = Color(0xFF44403C);
  static const muted = Color(0xFF78716C);
  static const faint = Color(0xFFA8A29E);

  static const accent = Color(0xFFD9481F);
  static const accentSoft = Color(0xFFFCEDE7);
  static const going = Color(0xFF0F766E);
  static const goingSoft = Color(0xFFE3F2F0);
  static const like = Color(0xFFE11D48);
  static const success = Color(0xFF15803D);

  // Ammachi's call screen.
  static const night = Color(0xFF0C0A09);
  static const nightRaised = Color(0xFF1C1917);
  static const nightLine = Color(0xFF292524);

  static const budgetColors = <String, Color>{
    'stay': Color(0xFF1D4ED8),
    'transport': Color(0xFF0E7490),
    'food': Color(0xFFC2410C),
    'activities': Color(0xFFA16207),
    'other': Color(0xFF57534E),
  };

  static const budgetIcons = <String, IconData>{
    'stay': Icons.hotel_outlined,
    'transport': Icons.directions_car_outlined,
    'food': Icons.restaurant_outlined,
    'activities': Icons.local_activity_outlined,
    'other': Icons.shopping_bag_outlined,
  };

  static const budgetLabels = <String, String>{
    'stay': 'Stay',
    'transport': 'Transport',
    'food': 'Food',
    'activities': 'Activities',
    'other': 'Other',
  };
}

/// Type scale: DM Sans everywhere, Noto Sans Malayalam for Malayalam glyphs.
/// DM Sans is a variable font, so weights are set via font variations too.
abstract final class TT {
  static const _ml = ['NotoSansMalayalam'];

  static FontWeight _w(double wght) => FontWeight.values[((wght / 100).round() - 1).clamp(0, 8)];

  /// Headlines.
  static TextStyle display(double size, {double wght = 700, Color color = TG.ink, double height = 1.15, double spacing = -0.02}) => TextStyle(
    fontFamily: 'DMSans',
    fontFamilyFallback: _ml,
    fontSize: size,
    fontWeight: _w(wght),
    fontVariations: [FontVariation('wght', wght), FontVariation('opsz', size.clamp(9, 40).toDouble())],
    color: color,
    height: height,
    letterSpacing: size * spacing,
  );

  /// Body and interface text.
  static TextStyle ui(double size, {double wght = 420, Color color = TG.ink, double height = 1.4, double spacing = 0}) => TextStyle(
    fontFamily: 'DMSans',
    fontFamilyFallback: _ml,
    fontSize: size,
    fontWeight: _w(wght),
    fontVariations: [FontVariation('wght', wght), FontVariation('opsz', size.clamp(9, 40).toDouble())],
    color: color,
    height: height,
    letterSpacing: spacing,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// Small uppercase labels.
  static TextStyle label(double size, {Color color = TG.muted, double wght = 600}) => ui(size, wght: wght, color: color, spacing: size * 0.06);

  /// Malayalam text (Ammachi's words).
  static TextStyle ml(double size, {Color color = TG.ink, double wght = 420, double height = 1.6}) => TextStyle(
    fontFamily: 'NotoSansMalayalam',
    fontFamilyFallback: const ['DMSans'],
    fontSize: size,
    fontWeight: _w(wght),
    fontVariations: [FontVariation('wght', wght)],
    color: color,
    height: height,
  );
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: TG.accent,
    brightness: Brightness.light,
    surface: TG.bg,
    primary: TG.ink,
    onPrimary: Colors.white,
    secondary: TG.accent,
    error: TG.like,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: TG.bg);
  return base.copyWith(
    textTheme: base.textTheme
        .apply(fontFamily: 'DMSans', bodyColor: TG.ink, displayColor: TG.ink)
        .copyWith(bodyLarge: TT.ui(16), bodyMedium: TT.ui(14), labelLarge: TT.ui(14, wght: 600)),
    dividerTheme: const DividerThemeData(color: TG.line, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: TG.bg,
      foregroundColor: TG.ink,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      surfaceTintColor: Colors.transparent,
      shadowColor: TG.line,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      titleTextStyle: TT.display(18, wght: 650),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: TG.ink,
      contentTextStyle: TT.ui(14, color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: TG.surface,
      hintStyle: TT.ui(15, color: TG.faint),
      labelStyle: TT.ui(15, color: TG.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: TG.ink, width: 1.2)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: TG.like)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: TG.ink,
        foregroundColor: Colors.white,
        disabledBackgroundColor: TG.surfaceHigh,
        disabledForegroundColor: TG.faint,
        minimumSize: const Size(48, 50),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: TT.ui(15, wght: 600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: TG.ink,
        minimumSize: const Size(48, 46),
        side: const BorderSide(color: TG.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: TT.ui(14, wght: 600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: TG.ink, minimumSize: const Size(44, 40), textStyle: TT.ui(14, wght: 600)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: TG.bg,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder(), TargetPlatform.iOS: CupertinoPageTransitionsBuilder()},
    ),
  );
}
