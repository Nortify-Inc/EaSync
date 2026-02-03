import 'package:flutter/material.dart';
import '../config/iconCatalog.dart';

class IconSelector extends StatelessWidget {
  final IconData selected;
  final ValueChanged<IconData> onSelect;

  const IconSelector({
    super.key, 
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      child: Column(
        children: modeIcons.map((icon) {
          final isSelected = icon == selected;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: GestureDetector(
              onTap: () => onSelect(icon),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(8),
                child: Icon(
                  icon,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).iconTheme.color,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
