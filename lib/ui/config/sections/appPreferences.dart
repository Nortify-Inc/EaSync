import 'package:flutter/material.dart';
import '../../../services/persistence.dart';
import '../../widgets/section.dart';


class AppPreferences extends StatelessWidget {
  final PersistenceService persistence;

  const AppPreferences({
    super.key,
    required this.persistence,
  });

  @override
  Widget build(BuildContext context) {
    return Section(
      title: 'Preferências',
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Salvar estado automaticamente'),
            value: persistence.autoSaveEnabled,
            onChanged: persistence.setAutoSave,
          ),
          SwitchListTile(
            title: const Text('Animações avançadas'),
            value: persistence.animationsEnabled,
            onChanged: persistence.setAnimations,
          ),
        ],
      ),
    );
  }
}

