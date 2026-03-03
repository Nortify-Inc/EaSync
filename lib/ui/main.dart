/*!
 * @file main.dart
 * @brief Entry point of the EaSync Flutter application.
 * @param args Unused in the Flutter entrypoint.
 * @return `void`.
 * @author Erick Radmann
 */

import 'handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Bridge.init();
  runApp(const EaSync());
}

class EaSync extends StatelessWidget {
  const EaSync({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeAnimationCurve: Curves.easeOutCubic,
      themeAnimationDuration: const Duration(milliseconds: 280),
      theme: ThemeData(
        scaffoldBackgroundColor: EaColor.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: EaColor.fore,
          brightness: Brightness.dark,
        ).copyWith(primary: EaColor.fore, secondary: EaColor.fore),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
            TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
            TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          },
        ),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: EaColor.fore,
          selectionColor: EaColor.border,
          selectionHandleColor: EaColor.fore,
        ),
      ),
      home: const Splash(),
    );
  }
}
