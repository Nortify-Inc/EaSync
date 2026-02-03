import 'package:flutter/material.dart';
import '../../models/device.dart';
import 'capabilityChip.dart';

class DeviceCard extends StatelessWidget {
  final Device device;
  final VoidCallback onOpen;

  const DeviceCard({
    super.key,
    required this.device,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpen,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                device.name,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: device.capabilities.entries.map((entry) {
                  final cap = entry.value;

                  return CapabilityChip(
                    capability: cap,
                    onChanged: (value) {
                      // sendEvent aqui
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
