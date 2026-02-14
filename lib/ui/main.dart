import 'handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Bridge.init();

  runApp(const EaSync());
}

class EaSync extends StatelessWidget {
  const EaSync({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: Home());
  }
}
