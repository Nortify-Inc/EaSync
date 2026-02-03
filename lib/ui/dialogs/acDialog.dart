import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/device.dart';
import '../../models/capability.dart';
import '../../state/deviceStore.dart';

class AcDialog extends StatefulWidget {
  final Device device;
  const AcDialog({super.key, required this.device});

  @override
  State<AcDialog> createState() => _AcDialogState();
}

class _AcDialogState extends State<AcDialog> {
  late int temperature;

  @override
  void initState() {
    super.initState();
    temperature = widget.device.getCapability(CapabilityType.temperature) as int;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<DeviceStore>();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.device.name,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Ligado'),
              value: widget.device.power,
              onChanged: (v) {
                store.togglePower(widget.device.id, v);
                setState(() {});
              },
            ),
            const SizedBox(height: 12),
            Text(
              '$temperature°C',
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
            ),
            Slider(
              min: 16,
              max: 30,
              divisions: 14,
              value: temperature as double,
              onChanged: widget.device.power
                  ? (v) {
                      setState(() => temperature = v as int);
                      store.setCapability(
                        widget.device.id,
                        CapabilityType.temperature,
                        temperature,
                      );
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
