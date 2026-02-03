import 'package:flutter/material.dart';
import '../../../state/modeStore.dart';
import '../../widgets/section.dart';
import '../dialogs/createModeDialog.dart';
import 'package:provider/provider.dart';

class ModesConfig extends StatelessWidget {
  const ModesConfig({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ModeStore>();

    return Section(
      title: 'Modos',
      trailing: IconButton(
        icon: const Icon(Icons.add),
        onPressed: () => showCreateModeDialog(context),
      ),
      child: Column(
        children: store.modes.map((mode) {
          return ListTile(
            leading: Icon(mode.icon),
            title: Text(mode.name),
            trailing: Switch(
              value: store.activeModeId == mode.id,
              onChanged: (_) => store.applyMode(mode.id),
            ),
          );
        }).toList(),
      ),
    );
  }
}
