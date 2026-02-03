import 'package:flutter/material.dart';
import '../../../state/groupStore.dart';
import '../../widgets/section.dart';
import '../dialogs/createGroupDialog.dart';
import 'package:provider/provider.dart';

class GroupsConfig extends StatelessWidget {
  const GroupsConfig({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<GroupStore>();

    return Section(
      title: 'Grupos',
      trailing: IconButton(
        icon: const Icon(Icons.add),
        onPressed: () => showCreateGroupDialog(context),
      ),
      child: Column(
        children: store.groups.map((group) {
          return ListTile(
            title: Text(group.name),
            subtitle: Text('${group.deviceIds.length} dispositivos'),
            trailing: Switch(
              value: group.globalControl,
              onChanged: (v) {
                store.updateGroup(
                  group.copyWith(globalControl: v),
                );
              },
            ),
          );
        }).toList(),
      ),
    );
  }
}
