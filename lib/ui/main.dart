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
  await EaAppSettings.instance.load();
  Bridge.aiObserveAppOpen();
  runApp(const EaSync());
}

class EaSync extends StatelessWidget {
  const EaSync({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: EaAppSettings.instance,
      builder: (_, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          themeAnimationCurve: Curves.easeOutCubic,
          themeAnimationDuration: const Duration(milliseconds: 280),
          themeMode: EaAppSettings.instance.themeMode,
          theme: EaTheme.light(),
          darkTheme: EaTheme.dark(),
          home: const Splash(),
        );
      },
    );
  }
}
