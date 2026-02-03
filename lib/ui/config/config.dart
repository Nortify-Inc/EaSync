import 'package:easync/services/persistence.dart';
import 'package:flutter/material.dart';
import 'sections/devicesConfig.dart';
import 'sections/groupConfig.dart';
import 'sections/modesConfig.dart';
import 'sections/appPreferences.dart';

class ConfigScreen extends StatelessWidget {
  const ConfigScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final persistenceService = PersistenceService();
    persistenceService.init();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurações'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const DevicesConfig(),
          const SizedBox(height: 24),
          const GroupsConfig(),
          const SizedBox(height: 24),
          const ModesConfig(),
          const SizedBox(height: 24),
          AppPreferences(persistence: persistenceService),
        ],
      ),
    );
  }
}
