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
      theme: ThemeData(
        scaffoldBackgroundColor: EaColor.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: EaColor.fore,
          brightness: Brightness.dark,
        ).copyWith(
          primary: EaColor.fore,
          secondary: EaColor.fore,
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
