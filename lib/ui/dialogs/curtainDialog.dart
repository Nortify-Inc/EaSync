import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/device.dart';
import '../../models/capability.dart';
import '../../state/deviceStore.dart';

class CurtainDialog extends StatelessWidget {
  final Device device;
  const CurtainDialog({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    final store = context.read<DeviceStore>();
    final position = device.getCapability(CapabilityType.position);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(device.name,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            Slider(
              min: 0,
              max: 100,
              divisions: 100,
              label: '$position%',
              value: position as double,
              onChanged: (v) {
                store.setCapability(
                  device.id,
                  CapabilityType.position,
                  v as int,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
