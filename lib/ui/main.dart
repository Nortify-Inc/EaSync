/*!
 * @file main.dart
 * @brief Entry point of the EaSync Flutter application.
 * @param args Unused in the Flutter entrypoint.
 * @return `void`.
 * @author Erick Radmann
 */

import 'handler.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      await Firebase.initializeApp().timeout(const Duration(seconds: 6));
    } else {
      debugPrint('[boot] Firebase init skipped: unsupported platform');
    }
  } catch (e) {
    debugPrint('[boot] Firebase init skipped: $e');
  }

  try {
    await Bridge.init().timeout(const Duration(seconds: 8));
  } catch (e) {
    debugPrint('[boot] Bridge init skipped/timed out: $e');
  }

  try {
    await EaAppSettings.instance.load().timeout(const Duration(seconds: 4));
  } catch (e) {
    debugPrint('[boot] Settings load skipped: $e');
  }

  runApp(const EaSync());
}

class EaSync extends StatelessWidget {
  const EaSync({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: EaAppSettings.instance,
      builder: (_, _) {
        return MaterialApp(
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
          home: const Splash(),
        );
      },
    );
  }
}
