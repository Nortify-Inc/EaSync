import 'package:flutter/material.dart';
import '../../models/capability.dart';

class CapabilityChip extends StatelessWidget {
  final Capability capability;
  final ValueChanged<int> onChanged;

  const CapabilityChip({
    super.key,
    required this.capability,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () {
        if (capability.type == CapabilityType.power) {
          onChanged(capability.value == 1 ? 0 : 1);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: capability.isOn
              ? theme.colorScheme.primary.withValues(alpha: 0.15)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: capability.isOn
                ? theme.colorScheme.primary
                : theme.dividerColor,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              capability.name,
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            Text(
              capability.displayValue,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
