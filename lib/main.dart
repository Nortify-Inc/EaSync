import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/deviceStore.dart';
import 'state/modeStore.dart';
import 'services/deviceRepository.dart';
import '../ui/home/home.dart';
import '../services/persistence.dart';

final PersistenceService persistenceService = PersistenceService();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await persistenceService.init();
  final repository = DeviceRepository(persistenceService);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => DeviceStore(repository),
        ),
        ChangeNotifierProvider(
          create: (_) => ModeStore(repository),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Home',
      theme: ThemeData.light(),
      home: const HomeScreen(),
    );
  }
}
