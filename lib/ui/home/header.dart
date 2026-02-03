import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/deviceStore.dart';
import '../../models/device.dart';

class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.read<DeviceStore>();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          const Text(
            'EaSync',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          PopupMenuButton<DeviceType>(
            icon: const Icon(Icons.filter_list),
            onSelected: (type) {
              store.setFilter(DeviceFilter.byType, type: type);
            },
            itemBuilder: (_) => DeviceType.values
                .map(
                  (t) => PopupMenuItem(
                    value: t,
                    child: Text(t.name),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
