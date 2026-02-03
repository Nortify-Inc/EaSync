import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/device.dart';
import '../../models/capability.dart';
import '../../state/deviceStore.dart';

class FridgeDialog extends StatelessWidget {
  final Device device;
  const FridgeDialog({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    final store = context.read<DeviceStore>();
    final temp = (device.getCapability(CapabilityType.temperature) ?? 0).toDouble();
    
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
            Text('Temperatura interna'),
            Text('$temp°C',
                style:
                    const TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
            Slider(
              min: 1,
              max: 10,
              divisions: 9,
              value: temp as double,
              onChanged: (v) {
                store.setCapability(
                  device.id,
                  CapabilityType.temperature,
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
