import 'package:flutter/material.dart';
import '../../models/mode.dart';

class ModeQuickAction extends StatelessWidget {
  final Mode mode;
  final VoidCallback onActivate;

  const ModeQuickAction({
    super.key,
    required this.mode,
    required this.onActivate,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onActivate,
      style: ElevatedButton.styleFrom(
        backgroundColor:
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(mode.icon),
          const SizedBox(height: 6),
          Text(mode.name),
        ],
      ),
    );
  }
}
