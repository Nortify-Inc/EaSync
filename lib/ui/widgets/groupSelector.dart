import 'package:flutter/material.dart';
import '../../models/groups.dart';

class GroupSelector extends StatelessWidget {
  final List<DeviceGroup> groups;
  final DeviceGroup? selected;
  final ValueChanged<DeviceGroup?> onChanged;

  const GroupSelector({
    super.key,
    required this.groups,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<DeviceGroup>(
      initialValue: selected,
      decoration: const InputDecoration(labelText: 'Grupo'),
      items: groups
          .map(
            (g) => DropdownMenuItem(
              value: g,
              child: Text(g.name),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}
