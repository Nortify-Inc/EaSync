import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/device.dart';
import '../../state/deviceStore.dart';

class LockDialog extends StatelessWidget {
  final Device device;
  const LockDialog({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    final store = context.read<DeviceStore>();

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
            ElevatedButton(
              onPressed: () {
                store.togglePower(device.id, !device.power);
                Navigator.pop(context);
              },
              child: Text(device.power ? 'Trancar' : 'Destrancar'),
            ),
          ],
        ),
      ),
    );
  }
}
