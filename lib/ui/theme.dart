/*!
 * @file theme.dart
 * @brief Centralized palette and typography definitions for the EaSync UI.
 * @param No external parameters.
 * @return Utility classes with reusable static styles.
 * @author Erick Radmann
 */

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EaAppSettings extends ChangeNotifier {
  static const String _kThemeMode = 'app.theme_mode';
  static const String _kAnimationsEnabled = 'app.animations_enabled';
  static const String _kSkeletonEnabled = 'app.skeleton_enabled';
  static const String _kCompactMode = 'app.compact_mode';
  static const String _kHapticsEnabled = 'app.haptics_enabled';

  static const String _kAiUseLocation = 'ai.use_location';
  static const String _kAiUseWeather = 'ai.use_weather';
  static const String _kAiUseUsageHistory = 'ai.use_usage_history';
  static const String _kAiAllowDeviceControl = 'ai.allow_device_control';
  static const String _kAiAllowAutoRoutines = 'ai.allow_auto_routines';
  static const String _kAiTemperament = 'ai.temperament';

  static const String _kTelemetryEnabled = 'usage.telemetry_enabled';
  static const String _kOfflineCache = 'usage.offline_cache';
  static const String _kLowDataMode = 'usage.low_data_mode';
  static const String _kUsagePattern = 'usage.pattern';

  static final EaAppSettings instance = EaAppSettings._();
  EaAppSettings._();

  ThemeMode themeMode = ThemeMode.dark;

  bool animationsEnabled = true;
  bool skeletonEnabled = true;
  bool compactMode = false;
  bool hapticsEnabled = true;

  bool aiUseLocationData = true;
  bool aiUseWeatherData = true;
  bool aiUseUsageHistory = true;
  bool aiAllowDeviceControl = true;
  bool aiAllowAutoRoutines = true;
  int aiTemperament = 0;

  bool telemetryEnabled = true;
  bool offlineCache = true;
  bool lowDataMode = false;
  String usagePattern = 'balanced';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final modeRaw = prefs.getString(_kThemeMode);
    themeMode = switch (modeRaw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.dark,
    };

    animationsEnabled = prefs.getBool(_kAnimationsEnabled) ?? true;
    skeletonEnabled = prefs.getBool(_kSkeletonEnabled) ?? true;
    compactMode = prefs.getBool(_kCompactMode) ?? false;
    hapticsEnabled = prefs.getBool(_kHapticsEnabled) ?? true;

    aiUseLocationData = prefs.getBool(_kAiUseLocation) ?? true;
    aiUseWeatherData = prefs.getBool(_kAiUseWeather) ?? true;
    aiUseUsageHistory = prefs.getBool(_kAiUseUsageHistory) ?? true;
    aiAllowDeviceControl = prefs.getBool(_kAiAllowDeviceControl) ?? true;
    aiAllowAutoRoutines = prefs.getBool(_kAiAllowAutoRoutines) ?? true;
    aiTemperament = (prefs.getInt(_kAiTemperament) ?? 0).clamp(0, 2);

    telemetryEnabled = prefs.getBool(_kTelemetryEnabled) ?? true;
    offlineCache = prefs.getBool(_kOfflineCache) ?? true;
    lowDataMode = prefs.getBool(_kLowDataMode) ?? false;
    usagePattern = prefs.getString(_kUsagePattern) ?? 'balanced';
  }

  Future<void> setThemeMode(ThemeMode next) async {
    if (themeMode == next) return;
    themeMode = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kThemeMode,
      next == ThemeMode.light ? 'light' : 'dark',
    );
    notifyListeners();
  }

  Future<void> persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAnimationsEnabled, animationsEnabled);
    await prefs.setBool(_kSkeletonEnabled, skeletonEnabled);
    await prefs.setBool(_kCompactMode, compactMode);
    await prefs.setBool(_kHapticsEnabled, hapticsEnabled);

    await prefs.setBool(_kAiUseLocation, aiUseLocationData);
    await prefs.setBool(_kAiUseWeather, aiUseWeatherData);
    await prefs.setBool(_kAiUseUsageHistory, aiUseUsageHistory);
    await prefs.setBool(_kAiAllowDeviceControl, aiAllowDeviceControl);
    await prefs.setBool(_kAiAllowAutoRoutines, aiAllowAutoRoutines);
    await prefs.setInt(_kAiTemperament, aiTemperament.clamp(0, 2));

    await prefs.setBool(_kTelemetryEnabled, telemetryEnabled);
    await prefs.setBool(_kOfflineCache, offlineCache);
    await prefs.setBool(_kLowDataMode, lowDataMode);
    await prefs.setString(_kUsagePattern, usagePattern);
    notifyListeners();
  }
}

class EaTheme {
  static ThemeData dark() {
    final base = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: EaColor.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: EaColor.fore,
        brightness: Brightness.dark,
      ).copyWith(primary: EaColor.fore, secondary: EaColor.fore),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: EaColor.fore,
        selectionColor: EaColor.border,
        selectionHandleColor: EaColor.fore,
      ),
      cardTheme: CardThemeData(
        color: EaColor.secondaryBack,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: EaColor.border),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) return EaColor.fore;
          return EaColor.textDisabled;
        }),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: EaColor.textPrimary,
        titleTextStyle: EaText.primary.copyWith(
          fontSize: 19,
          color: EaColor.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: EaColor.back,
        elevation: 0,
        contentTextStyle: EaText.secondary.copyWith(
          fontSize: 12,
          color: EaColor.textPrimary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: EaColor.fore),
        ),
      ),
    );

    return base.copyWith(
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  static ThemeData light() {
    final base = ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF5F7FC),
      colorScheme: ColorScheme.fromSeed(
        seedColor: EaColor.fore,
        brightness: Brightness.light,
      ).copyWith(primary: EaColor.fore, secondary: const Color(0xFF5D73DB)),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: EaColor.fore,
        selectionColor: Color(0xFFCFD7FF),
        selectionHandleColor: EaColor.fore,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFE1E6F2)),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: const Color(0xFF1A2134),
        titleTextStyle: EaText.primary.copyWith(
          fontSize: 19,
          color: const Color(0xFF1A2134),
          fontWeight: FontWeight.w600,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: EaColor.back,
        elevation: 0,
        contentTextStyle: EaText.secondary.copyWith(
          fontSize: 12,
          color: EaColor.textPrimary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: EaColor.fore),
        ),
      ),
    );

    return base.copyWith(
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}

class EaMotion {
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration normal = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);
}

class EaAdaptiveColor {
  static bool _dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color pageBackground(BuildContext context) =>
      _dark(context) ? EaColor.background : const Color(0xFFF1F4FB);

  static Color surface(BuildContext context) =>
      _dark(context) ? EaColor.secondaryBack : Colors.white;

  static Color field(BuildContext context) =>
      _dark(context) ? EaColor.back : const Color(0xFFE9EEF8);

  static Color border(BuildContext context) =>
      _dark(context) ? EaColor.border : const Color(0xFFC9D4EA);

  static Color bodyText(BuildContext context) =>
      _dark(context) ? EaColor.textPrimary : const Color(0xFF1A2134);

  static Color secondaryText(BuildContext context) =>
      _dark(context) ? EaColor.textSecondary : const Color(0xFF5C667F);

  static Color scrim(BuildContext context) => _dark(context)
      ? Colors.black.withOpacity(0.32)
      : const Color(0xFF2A3458).withOpacity(0.18);
}

class EaDecoration {
  static LinearGradient primaryButtonGradient() {
    return const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      stops: [0.0, 0.52, 1.0],
      colors: [Color(0xFF9AAEFF), EaColor.fore, Color(0xFF3E4A86)],
    );
  }

  static LinearGradient roundOrbGradient(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      stops: const [0.0, 0.46, 1.0],
      colors: dark
          ? [
              EaColor.fore.withValues(alpha: 0.85),
              const Color(0xFF59639C),
              EaColor.back,
            ]
          : [
              const Color(0xFFAEBBFF),
              const Color(0xFF8190E4),
              const Color(0xFF59639C),
            ],
    );
  }
}

class EaButtonStyle {
  static ButtonStyle gradientFilled({
    required BuildContext context,
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(12)),
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(vertical: 14),
  }) {
    return ElevatedButton.styleFrom(
      backgroundColor: Colors.transparent,
      foregroundColor: EaColor.back,
      shadowColor: Colors.transparent,
      padding: padding,
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
    );
  }
}

class EaGradientButtonFrame extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;

  const EaGradientButtonFrame({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: EaDecoration.primaryButtonGradient(),
        borderRadius: borderRadius,
      ),
      child: ClipRRect(borderRadius: borderRadius, child: child),
    );
  }
}

class EaColor {
  // Accent (soft blue)
  static const Color fore = Color.fromARGB(255, 103, 117, 199);
  static const Color secondaryFore = Color(0xFF9AAEFF);

  // Surfaces
  static const Color back = Color.fromARGB(255, 32, 32, 32);
  static const Color secondaryBack = Color(0xFF2A2A2D);

  // Main background
  static const Color background = Color.fromARGB(255, 9, 9, 17);

  // Text
  static const Color textPrimary = Color(0xFFEDEDED);
  static const Color textSecondary = Color(0xFF9A9AA0);
  static const Color textDisabled = Color(0xFF6B6B70);

  // Border
  static const Color border = Color(0xFF2F2F34);
}

class EaText {
  static final TextStyle primary = GoogleFonts.poppins(
    color: EaColor.textPrimary,
    fontSize: 20,
    fontWeight: FontWeight.w600,
  );

  static final TextStyle primaryTranslucent = GoogleFonts.poppins(
    color: EaColor.textPrimary.withValues(alpha: 0.5),
    fontSize: 20,
  );

  static final TextStyle primaryBack = GoogleFonts.poppins(
    color: EaColor.back,
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  static final TextStyle secondary = GoogleFonts.poppins(
    color: EaColor.textPrimary,
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  static final TextStyle secondaryTranslucent = GoogleFonts.poppins(
    color: EaColor.textPrimary.withValues(alpha: 0.5),
    fontSize: 14,
  );

  static final TextStyle secondaryBack = GoogleFonts.poppins(
    color: EaColor.back,
    fontSize: 14,
    fontWeight: FontWeight.w300,
  );

  static final TextStyle accent = GoogleFonts.poppins(
    color: EaColor.fore,
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  static final TextStyle small = GoogleFonts.poppins(
    color: EaColor.textPrimary,
    fontSize: 12,
  );
}
