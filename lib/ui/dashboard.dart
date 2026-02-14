import 'dart:ui';
import 'handler.dart';
import 'package:flutter/material.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  List<DeviceInfo> devices = [];
  final Set<int> selectedCapabilities = {};

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  void _loadDevices() {
    try {
      final list = Bridge.listDevices();
      setState(() {
        devices = list;
      });
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  List<DeviceInfo> get filteredDevices {
    if (selectedCapabilities.isEmpty) return devices;

    return devices.where((d) {
      return selectedCapabilities.any(
        (cap) => d.capabilities.contains(cap),
      );
    }).toList();
  }

  void _clearFilters() {
    setState(() {
      selectedCapabilities.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Spacer(),
                GestureDetector(
                  onTap: _clearFilters,
                  child: Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.3),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Text(
                      "Clear",
                      style: EaText.secondary.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildFilters(),
            const SizedBox(height: 24),
            Expanded(child: _buildDeviceList()),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildFilter(
                "Power",
                CoreCapability.CORE_CAP_POWER,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _buildFilter(
                "Color",
                CoreCapability.CORE_CAP_COLOR,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _buildFilter(
                "Time",
                CoreCapability.CORE_CAP_TIMESTAMP,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildFilter(
                "Temperature",
                CoreCapability.CORE_CAP_TEMPERATURE,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _buildFilter(
                "Brightness",
                CoreCapability.CORE_CAP_BRIGHTNESS,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFilter(String label, int cap) {
    final selected = selectedCapabilities.contains(cap);

    return FilterChipButton(
      label: label,
      selected: selected,
      onTap: () {
        setState(() {
          if (selected) {
            selectedCapabilities.remove(cap);
          } else {
            selectedCapabilities.add(cap);
          }
        });
      },
    );
  }

  Widget _buildDeviceList() {
    if (devices.isEmpty) {
      return _buildEmpty("Your devices will appear here");
    }

    if (filteredDevices.isEmpty) {
      return _buildEmpty("No devices match this filter");
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: filteredDevices.length,
      itemBuilder: (context, index) {
        return _DeviceCard(device: filteredDevices[index]);
      },
    );
  }

  Widget _buildEmpty(String text) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.devices,
            size: 90,
            color: EaColor.fore.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 12),
          Text(
            text,
            style: EaText.primaryTranslucent,
          ),
        ],
      ),
    );
  }
}

/* ===========================
   FILTER BUTTON
=========================== */

class FilterChipButton extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const FilterChipButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<FilterChipButton> createState() => _FilterChipButtonState();
}

class _FilterChipButtonState extends State<FilterChipButton> {
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    const double radius = 50;

    final double scale =
        (pressed || widget.selected) ? 0.96 : 1.0;

    final Color background =
        widget.selected ? EaColor.fore : EaColor.back;

    final Color textColor =
        widget.selected ? EaColor.back : EaColor.fore;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (_) => setState(() => pressed = true),
      onTapUp: (_) {
        setState(() => pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => pressed = false),
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(radius),
            boxShadow: widget.selected
                ? [
                    BoxShadow(
                      color: EaColor.fore.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              widget.label,
              style: EaText.secondary.copyWith(
                color: textColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final DeviceInfo device;

  const _DeviceCard({
    required this.device,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: EaColor.back.withValues(alpha: 0.9),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(device.name, style: EaText.primary),
            const SizedBox(height: 6),
            Text(device.uuid, style: EaText.secondary),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: device.capabilities
                  .map(_capToChip)
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _capToChip(int cap) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: EaColor.fore.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _capName(cap),
        style: EaText.secondary.copyWith(fontSize: 12),
      ),
    );
  }

  String _capName(int cap) {
    switch (cap) {
      case CoreCapability.CORE_CAP_POWER:
        return "Power";
      case CoreCapability.CORE_CAP_BRIGHTNESS:
        return "Brightness";
      case CoreCapability.CORE_CAP_COLOR:
        return "Color";
      case CoreCapability.CORE_CAP_TEMPERATURE:
        return "Temp";
      case CoreCapability.CORE_CAP_TIMESTAMP:
        return "Time";
      default:
        return "Unknown";
    }
  }
}
