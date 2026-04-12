/*!
 * @file main.dart
 * @brief Entry point of the EaSync Flutter application.
 * @param args Unused in the Flutter entrypoint.
 * @return `void`.
 * @author Erick Radmann
 */

import 'handler.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await EaAppSettings.instance.load().timeout(const Duration(seconds: 4));
  } catch (e) {
    debugPrint('[boot] Settings load skipped: $e');
  }

  await dotenv.load(fileName: '.env');
  runApp(const EaSync());

  Future<void>(() async {
    try {
      await TrustedPresenceService.instance.start();
    } catch (e) {
      debugPrint('[boot] Trusted presence start skipped: $e');
    }

    try {
      await Bridge.init().timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[boot] Bridge init skipped/timed out: $e');
    }
  });
}

class EaSync extends StatelessWidget {
  const EaSync({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: EaAppSettings.instance,
      builder: (_, _) {
        return MaterialApp(
          navigatorKey: eaNavigatorKey,
          debugShowCheckedModeBanner: false,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],

          supportedLocales: EaI18n.supportedLocales,
          locale: EaAppSettings.instance.localeOverride,

          localeResolutionCallback: (locale, supportedLocales) {
            if (locale == null) return const Locale('en');
            if (locale.languageCode.toLowerCase() == 'pt') {
              return const Locale('pt', 'BR');
            }
            return const Locale('en');
          },

          themeAnimationCurve: Curves.easeOutCubic,
          themeAnimationDuration: const Duration(milliseconds: 280),
          themeMode: EaAppSettings.instance.themeMode,
          theme: EaTheme.light(),
          darkTheme: EaTheme.dark(),
          builder: (context, child) {
            if (child == null) return const SizedBox.shrink();
            return RecommendationToastHost(child: child);
          },
          home: const Splash(),
        );
      },
    );
  }
}
