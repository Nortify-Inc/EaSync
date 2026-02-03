import 'package:flutter/material.dart';
import '../../../state/deviceStore.dart';
import 'package:provider/provider.dart';

import '../../widgets/section.dart';

class DevicesConfig extends StatelessWidget {
  const DevicesConfig({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DeviceStore>();

    return Section(
      title: 'Dispositivos',
      child: Column(
        children: store.devices.map((device) {
          return SwitchListTile(
            title: Text(device.name),
            subtitle: Text(device.type.name),
            value: device.power,
            onChanged: (v) {
              store.updateDevice(
                device.copyWith(power: v),
              );
            },
          );
        }).toList(),
      ),
    );
  }
}
