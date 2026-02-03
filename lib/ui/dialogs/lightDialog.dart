import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/device.dart';
import '../../models/capability.dart';
import '../../state/deviceStore.dart';

class LightDialog extends StatefulWidget {
  final Device device;
  const LightDialog({super.key, required this.device});

  @override
  State<LightDialog> createState() => _LightDialogState();
}

class _LightDialogState extends State<LightDialog> {
  late int brightness;

  @override
  void initState() {
    super.initState();
    brightness = widget.device.getCapability(CapabilityType.brightness) as int;
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
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 24),
            SwitchListTile(
              title: const Text('Ligado'),
              value: widget.device.power,
              onChanged: (v) {
                store.togglePower(widget.device.id, v);
                setState(() {});
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Brilho'),
                Expanded(
                  child: Slider(
                    value: brightness as double,
                    min: 0,
                    max: 100,
                    divisions: 100,
                    label: '$brightness%',
                    onChanged: widget.device.power
                        ? (v) {
                            setState(() => brightness = v as int);
                            store.setCapability(
                              widget.device.id,
                              CapabilityType.brightness,
                              brightness,
                            );
                          }
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
