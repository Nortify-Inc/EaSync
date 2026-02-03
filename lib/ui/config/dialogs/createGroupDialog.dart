import 'package:flutter/material.dart';
import '../../../state/groupStore.dart';
import 'package:provider/provider.dart';

Future<void> showCreateGroupDialog(BuildContext context) {
  final controller = TextEditingController();

  return showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Novo grupo'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(labelText: 'Nome do grupo'),
      ),
      actions: [
        TextButton(onPressed: Navigator.of(context).pop, child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: () {
            context.read<GroupStore>().createGroup(controller.text);
            Navigator.of(context).pop();
          },
          child: const Text('Criar'),
        ),
      ],
    ),
  );
}
