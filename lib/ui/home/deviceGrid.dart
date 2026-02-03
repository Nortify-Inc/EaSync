import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/deviceStore.dart';
import '../widgets/deviceCard.dart';
import '../dialogs/deviceDialog.dart';

class DeviceGrid extends StatelessWidget {
  const DeviceGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DeviceStore>();
    final devices = store.devices;

    return ReorderableListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: devices.length,
      onReorder: store.reorderDevices,
      itemBuilder: (context, index) {
        final device = devices[index];

        return Padding(
          key: ValueKey(device.id),
          padding: const EdgeInsets.only(bottom: 12),
          child: DeviceCard(
            device: device,
            onOpen: () => showDeviceDialog(context, device)
          ),
        );
      },
    );
  }
}
