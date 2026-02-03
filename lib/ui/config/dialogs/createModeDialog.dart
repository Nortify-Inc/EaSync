import 'package:flutter/material.dart';
import '../../../state/modeStore.dart';
import '../../widgets/iconSelector.dart';
import '../iconCatalog.dart';
import 'package:provider/provider.dart';

Future<void> showCreateModeDialog(BuildContext context) {
  return showDialog(
    context: context,
    builder: (_) => const _CreateModeDialog(),
  );
}

class _CreateModeDialog extends StatefulWidget {
  const _CreateModeDialog();

  @override
  State<_CreateModeDialog> createState() => _CreateModeDialogState();
}

class _CreateModeDialogState extends State<_CreateModeDialog> {
  final controller = TextEditingController();
  IconData selectedIcon = modeIcons.first;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novo modo'),
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconSelector(
            selected: selectedIcon,
            onSelect: (icon) => setState(() => selectedIcon = icon),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Nome do modo',
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            if (controller.text.trim().isEmpty) return;

            context.read<ModeStore>().createMode(
              controller.text.trim(),
              selectedIcon,
            );

            Navigator.of(context).pop();
          },
          child: const Text('Criar'),
        ),
      ],
    );
  }
}
