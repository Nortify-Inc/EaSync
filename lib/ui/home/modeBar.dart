import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/modeStore.dart';

class ModeBar extends StatelessWidget {
  const ModeBar({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ModeStore>();

    return SizedBox(
      height: 70,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: store.modes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final mode = store.modes[i];

          return GestureDetector(
            onTap: () => store.applyMode(mode.id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Icon(Icons.circle, size: 10),
                  const SizedBox(width: 8),
                  Text(
                    mode.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
