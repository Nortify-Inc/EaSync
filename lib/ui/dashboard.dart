import 'handler.dart';
import 'package:flutter/material.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  List<DeviceInfo> devices = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final list = Bridge.listDevices();
      setState(() {
        devices = list;
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(child: _body());
  }

  Widget _body() {
    if (loading) return _loading();
    if (error != null) return _errorState();
    if (devices.isEmpty) return _emptyState();
    return _grid();
  }

  Widget _loading() =>
      const Center(child: CircularProgressIndicator(color: EaColor.fore));

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text("Core error", style: EaText.primary),
            const SizedBox(height: 8),
            Text(
              error ?? "",
              textAlign: TextAlign.center,
              style: EaText.secondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    EaColor.fore.withValues(alpha: .25),
                    EaColor.fore.withValues(alpha: .08),
                  ],
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.tungsten, size: 30, color: EaColor.fore),
                  Icon(Icons.color_lens, size: 30, color: EaColor.fore),
                  Icon(Icons.thermostat, size: 30, color: EaColor.fore),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "No devices yet",
              style: EaText.primary.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Your devices will appear here",
              textAlign: TextAlign.center,
              style: EaText.secondaryTranslucent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid() {
    return RefreshIndicator(
      color: EaColor.fore,
      onRefresh: _loadDevices,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 18,
          crossAxisSpacing: 18,
          childAspectRatio: 1,
        ),
        itemCount: devices.length,
        itemBuilder: (_, i) => _deviceCard(devices[i]),
      ),
    );
  }

  Widget _deviceCard(DeviceInfo device) {
    final state = Bridge.getState(device.uuid);

    final Map<int, String> nameMap = {
      CoreCapability.CORE_CAP_POWER: "Power:",
      CoreCapability.CORE_CAP_BRIGHTNESS: "Brightness:",
      CoreCapability.CORE_CAP_COLOR: "Color: ",
      CoreCapability.CORE_CAP_TEMPERATURE: "Temp:",
      CoreCapability.CORE_CAP_TIMESTAMP: "Time:"
    };

    final Map<int, String> unitMap = {
      CoreCapability.CORE_CAP_POWER: "",
      CoreCapability.CORE_CAP_BRIGHTNESS: "%",
      CoreCapability.CORE_CAP_COLOR: "",
      CoreCapability.CORE_CAP_TEMPERATURE: "°C",
      CoreCapability.CORE_CAP_TIMESTAMP: ""
    };

    final Map<int, dynamic> valueMap = {
      CoreCapability.CORE_CAP_POWER: state.power ? "On" : "Off",
      CoreCapability.CORE_CAP_BRIGHTNESS: state.brightness,
      CoreCapability.CORE_CAP_COLOR: "#${state.color.toRadixString(16).padLeft(6, '0').toUpperCase()}",
      CoreCapability.CORE_CAP_TEMPERATURE: state.temperature.toStringAsFixed(1),
      CoreCapability.CORE_CAP_TIMESTAMP: "${DateTime.fromMillisecondsSinceEpoch(state.timestamp * 1000).hour.toString().padLeft(2,'0')}:${DateTime.fromMillisecondsSinceEpoch(state.timestamp * 1000).minute.toString().padLeft(2,'0')}"
    };

    return GestureDetector(
      onTap: () => _openDeviceControl(device),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: EaColor.back,
          shape: BoxShape.circle,
          border: Border.all(color: EaColor.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.devices, size: 36, color: EaColor.fore),
            const SizedBox(height: 12),
            Text(
              device.name,
              textAlign: TextAlign.center,
              style: EaText.primary,
            ),
            const SizedBox(height: 6),
            Icon(
              Icons.circle,
              size: 12,
              color: state.power ? Colors.greenAccent : Colors.redAccent,
            ),
            const SizedBox(height: 6),
            Flexible(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: device.capabilities.map((cap) {
                    if (!valueMap.containsKey(cap)) return const SizedBox.shrink();
                    final name = nameMap[cap];
                    final val = valueMap[cap];
                    final unit = unitMap[cap] ?? "";
                    return Text(
                      "$name $val $unit",
                      style: EaText.secondary.copyWith(fontSize: 10),
                      textAlign: TextAlign.center,
                    );
                  }).toList(),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }


  void _openDeviceControl(DeviceInfo device) {
    final state = Bridge.getState(device.uuid);
    double brightness = state.brightness.toDouble();
    double temperature = state.temperature;
    int color = state.color;
    bool power = state.power;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: EaColor.back,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  device.name,
                  style: EaText.primary.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                if (device.capabilities.contains(CoreCapability.CORE_CAP_POWER))
                  Row(
                    children: [
                      Text("Power", style: EaText.secondary),
                      const Spacer(),
                      Switch(
                        value: power,
                        activeThumbColor: EaColor.fore,
                        onChanged: (v) {
                          setState(() => power = v);
                          Bridge.setPower(device.uuid, v);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                "${device.name} turned ${v ? "on" : "off"}",
                                style: EaText.secondary,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                if (device.capabilities.contains(
                  CoreCapability.CORE_CAP_BRIGHTNESS,
                ))
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      Text("Brightness", style: EaText.secondary),
                      Slider(
                        min: 0,
                        max: 100,
                        divisions: 100,
                        value: brightness,
                        activeColor: EaColor.fore,
                        inactiveColor: EaColor.fore.withValues(alpha: .25),
                        onChanged: (v) => setState(() => brightness = v),
                        onChangeEnd: (v) {
                          Bridge.setBrightness(device.uuid, v.round());
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                "${device.name} brightness set to ${v.round()}",
                                style: EaText.secondary,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                if (device.capabilities.contains(
                  CoreCapability.CORE_CAP_TEMPERATURE,
                ))
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      Text("Temperature", style: EaText.secondary),
                      Slider(
                        min: 0,
                        max: 36,
                        divisions: 36,
                        value: temperature,
                        activeColor: EaColor.fore,
                        inactiveColor: EaColor.fore.withValues(alpha: .25),
                        onChanged: (v) => setState(() => temperature = v),
                        onChangeEnd: (v) {
                          Bridge.setTemperature(device.uuid, v);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                "${device.name} temperature set to ${v.toStringAsFixed(1)}°C",
                                style: EaText.secondary,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                if (device.capabilities.contains(CoreCapability.CORE_CAP_COLOR))
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      Text("Color", style: EaText.secondary),
                      GestureDetector(
                        onTap: () async {
                          Color pickedColor = Color(0xFF000000 | color);
                          await showModalBottomSheet(
                            context: context,
                            backgroundColor: EaColor.back,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(20),
                              ),
                            ),
                            builder: (_) {
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  RgbColorWheel(
                                    color: pickedColor,
                                    onChanged: (c) => pickedColor = c,
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: () {
                                      final rgb =
                                          pickedColor.toARGB32() & 0xFFFFFFFF;
                                      Bridge.setColor(device.uuid, rgb);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            "${device.name} color updated",
                                            style: EaText.secondary,
                                          ),
                                        ),
                                      );
                                      Navigator.pop(context);
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: EaColor.fore,
                                    ),
                                    child: const Text("Apply"),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Color(0xFF000000 | color),
                            shape: BoxShape.circle,
                            border: Border.all(color: EaColor.fore, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
