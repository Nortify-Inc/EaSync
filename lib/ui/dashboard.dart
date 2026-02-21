import 'handler.dart';
import 'package:flutter/material.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  bool loading = true;
  String? error;

  final Map<String, int> capIndexByDevice = {};

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  StreamSubscription<String>? _stateSub;

  @override
  void dispose() {
    _stateSub?.cancel();
    super.dispose();
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
        for (var d in devices) {
          capIndexByDevice.putIfAbsent(d.uuid, () => 0);
        }
      });
      // subscribe to state changes after devices are loaded
      _stateSub ??= Bridge.onStateChanged.listen((uuid) {
        // trigger rebuild so latest Bridge.getState is read in cards
        setState(() {});
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  void _nextCap(DeviceInfo device) {
    setState(() {
      final current = capIndexByDevice[device.uuid] ?? 0;
      capIndexByDevice[device.uuid] =
          (current + 1) % device.capabilities.length;
    });
  }

  void _prevCap(DeviceInfo device) {
    setState(() {
      final current = capIndexByDevice[device.uuid] ?? 0;
      capIndexByDevice[device.uuid] =
          (current - 1 + device.capabilities.length) %
          device.capabilities.length;
    });
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
    final caps = device.capabilities;
    double dragStartX = 0;
    double dragDelta = 0;

    final Map<int, String> unitMap = {
      CoreCapability.CORE_CAP_POWER: "",
      CoreCapability.CORE_CAP_BRIGHTNESS: "%",
      CoreCapability.CORE_CAP_COLOR: "",
      CoreCapability.CORE_CAP_TEMPERATURE: "°C",
      CoreCapability.CORE_CAP_TIMESTAMP: "",
    };

    final Map<int, dynamic> valueMap = {
      CoreCapability.CORE_CAP_POWER: state.power ? "On" : "Off",
      CoreCapability.CORE_CAP_BRIGHTNESS: state.brightness,
      CoreCapability.CORE_CAP_COLOR: state.color,
      CoreCapability.CORE_CAP_TEMPERATURE: state.temperature.toStringAsFixed(1),
      CoreCapability.CORE_CAP_TIMESTAMP:
          "${DateTime.fromMillisecondsSinceEpoch(state.timestamp * 1000).hour.toString().padLeft(2, '0')}:${DateTime.fromMillisecondsSinceEpoch(state.timestamp * 1000).minute.toString().padLeft(2, '0')}",
    };

    final int currentCapIndex = capIndexByDevice[device.uuid] ?? 0;
    final cap = caps[currentCapIndex];
    final val = valueMap[cap];
    final unit = unitMap[cap] ?? "";

    return GestureDetector(
      onTap: () => _openDeviceControl(device),
      onHorizontalDragStart: (d) => dragStartX = d.globalPosition.dx,
      onHorizontalDragUpdate: (d) =>
          dragDelta = d.globalPosition.dx - dragStartX,
      onHorizontalDragEnd: (d) {
        if (dragDelta.abs() > 50) {
          dragDelta < 0 ? _nextCap(device) : _prevCap(device);
        }
        dragDelta = 0;
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: EaColor.back,
          shape: BoxShape.circle,
          border: Border.all(
            color: EaColor.fore, 
            width: 1.5
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.tungsten, size: 60, color: EaColor.fore),
            const SizedBox(height: 15),
            Row(
              children: [
                Icon(
                  Icons.arrow_left_rounded,
                  size: 30,
                  color: EaColor.secondaryFore,
                ),
                SizedBox(width: 8),
                Icon(
                  cap == CoreCapability.CORE_CAP_POWER
                      ? Icons.power_settings_new
                      : cap == CoreCapability.CORE_CAP_BRIGHTNESS
                          ? Icons.brightness_6_outlined
                          : cap == CoreCapability.CORE_CAP_COLOR
                              ? Icons.color_lens
                              : cap == CoreCapability.CORE_CAP_TEMPERATURE
                                  ? Icons.thermostat
                                  : Icons.info_outline,
                  size: 30,
                  color: EaColor.fore,
                ),
                Spacer(),
                cap == CoreCapability.CORE_CAP_COLOR
                    ? Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Color(0xFF000000 | (val is int ? val : 0)),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: EaColor.fore,
                            width: 2,
                          ),
                        ),
                      )
                    : Text(
                        "$val$unit",
                        style: EaText.secondary,
                      ),
                Spacer(),
                Icon(
                  Icons.arrow_right_rounded,
                  size: 30,
                  color: EaColor.secondaryFore,
                )
              ],
            ),
            
            SizedBox(height: 12),
            Text(
              device.name,
              textAlign: TextAlign.center,
              style: EaText.secondary,
            ),
            Spacer()
          ],
        ),
      ),
    );
  }

  Future<void> _openDeviceControl(DeviceInfo device) async {
    final state = Bridge.getState(device.uuid);
    double brightness = state.brightness.toDouble();
    double temperature = state.temperature;
    int color = state.color;
    bool power = state.power;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setInnerState) {
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
                      style: EaText.primary
                    ),
                    const SizedBox(height: 16),
                    if (device.capabilities.contains(
                      CoreCapability.CORE_CAP_POWER,
                    ))
                      Row(
                        children: [
                          const Icon(Icons.power_settings_new, size: 18, color: EaColor.fore),

                          const SizedBox(width: 8),

                          Text("Power", style: EaText.secondary),

                          const Spacer(),

                          Switch(
                            value: power,

                            activeThumbColor: EaColor.fore,
                            inactiveTrackColor: EaColor.back,

                            onChanged: (v) {
                              setInnerState(() => power = v);
                              Bridge.setPower(device.uuid, v);
                              setState(() {});
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
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              const Icon(Icons.brightness_6_outlined, size: 18, color: EaColor.fore),

                              const SizedBox(width: 8),

                              Text("Brightness", style: EaText.secondary),

                              const Spacer(),

                              Text("${brightness.round()}%",
                                  style: EaText.secondary.copyWith(
                                    color: EaColor.fore,
                                  )
                              ),

                              SizedBox(width: 10)
                            ],
                          ),
                          
                          Slider(
                            min: 0,
                            max: 100,
                            divisions: 100,
                            value: brightness,
                            activeColor: EaColor.fore,
                            inactiveColor: EaColor.fore.withValues(alpha: .25),
                            onChanged: (v) {
                              setInnerState(() => brightness = v);
                              Bridge.setBrightness(device.uuid, v.round());
                              setState(() {});
                            },
                          ),
                          
                          SizedBox(height: 8),
                        ],
                      ),
                    if (device.capabilities.contains(
                      CoreCapability.CORE_CAP_COLOR,
                    ))
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 12),
                          Icon(Icons.color_lens, size: 18, color: EaColor.fore),
                          const SizedBox(width: 8),
                          Text("Color", style: EaText.secondary),
                          Spacer(),
                          GestureDetector(
                            onTap: () async {
                              Color pickedColor = Color(0xFF000000 | color);
                              Color selected = pickedColor;

                              await showModalBottomSheet(
                                context: context,
                                backgroundColor: EaColor.back,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(20),
                                  ),
                                ),
                                builder: (_) {
                                  return StatefulBuilder(
                                    builder: (context, setModalState) {
                                      return Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 40,
                                              height: 40,
                                              margin:
                                                  const EdgeInsets.only(bottom: 16),
                                              decoration: BoxDecoration(
                                                color: selected,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: EaColor.fore,
                                                  width: 2,
                                                ),
                                              ),
                                            ),

                                            RgbColorWheel(
                                              
                                              color: selected,
                                              onChanged: (c) {
                                                setModalState(() => selected = c);
                                              },
                                            ),

                                            const SizedBox(height: 16),
                                            ElevatedButton(
                                              onPressed: () {
                                                final rgb = selected.toARGB32() & 0xFFFFFFFF;
                                                Bridge.setColor(device.uuid, rgb);
                                                setState(() {});
                                                Navigator.pop(context);
                                              },
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: EaColor.fore,
                                              ),
                                              child: Text(
                                                "Apply",
                                                style: EaText.secondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  );
                                },
                              );

                              setInnerState(() => color = selected.toARGB32() & 0xFFFFFFFF);
                              setState(() {});
                            },
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Color(0xFF000000 | color),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: EaColor.fore,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 10)
                        ],
                      ),
                       if (device.capabilities.contains(
                        CoreCapability.CORE_CAP_TEMPERATURE,
                      ))
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                const Icon(Icons.thermostat, size: 18, color: EaColor.fore),

                                const SizedBox(width: 8),

                                Text("Temperature", style: EaText.secondary),

                                const Spacer(),

                                Text("${temperature.toStringAsFixed(1)}°C",
                                    style: EaText.secondary.copyWith(
                                      color: EaColor.fore,
                                    )
                                ),

                                SizedBox(width: 10)
                              ],
                            ),

                            Slider(
                              min: -10,
                              max: 36,
                              value: temperature,
                              activeColor: EaColor.fore,
                              inactiveColor: EaColor.fore.withValues(alpha: .25),
                              onChanged: (v) {
                                setInnerState(() => temperature = v);
                                Bridge.setTemperature(device.uuid, v);
                                setState(() {});
                              },
                              onChangeEnd: (_) {},
                            ),
                          ],
                        ),
                  if (device.capabilities.contains(
                    CoreCapability.CORE_CAP_TIMESTAMP,
                  ))
                    _buildScheduleControl(device, setInnerState),
                  ],
                ),
              )
            );
          },
        );
      },
    );
    setState(() {});
  }

  Widget _buildScheduleControl(DeviceInfo device, void Function(void Function()) setInnerState) {
    final state = Bridge.getState(device.uuid);

    TimeOfDay? toTime(int? m) {
      if (m == null || m < 0) return null;

      final h = m ~/ 60;
      final min = m % 60;

      return TimeOfDay(hour: h, minute: min);
    }

    int toMinutes(TimeOfDay t) {
      return t.hour * 60 + t.minute;
    }

    final time = toTime(state.timestamp);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),

        Row(
          children: [
            const Icon(Icons.schedule, size: 18, color: EaColor.fore),
            const SizedBox(width: 8),
            Text("Schedule", style: EaText.secondary),
          ],
        ),

        const SizedBox(height: 6),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: EaColor.back,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: EaColor.border),
          ),
          child: Row(
            children: [
              Text(
                time != null
                    ? "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}"
                    : "Not set",
                style: EaText.secondary,
              ),

              const Spacer(),

              IconButton(
                icon: const Icon(Icons.edit, size: 18, color: EaColor.fore),
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,

                    helpText: "Select time",
                    
                    initialEntryMode: TimePickerEntryMode.inputOnly,
                    initialTime: time ?? TimeOfDay.now(),

                    builder: (context, child) {
                      final base = Theme.of(context);

                      return Theme(
                        data: base.copyWith(
                          colorScheme: base.colorScheme.copyWith(
                            primary: EaColor.fore,
                          ),

                          inputDecorationTheme: InputDecorationTheme(
                            labelStyle: EaText.secondary.copyWith(
                              color: EaColor.fore,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: EaColor.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: EaColor.fore,     // borda ativa (adeus roxo)
                                width: 2,
                              ),
                            ),
                          ),

                          timePickerTheme: TimePickerThemeData(
                            helpTextStyle: EaText.secondary,
                            
                            backgroundColor: EaColor.back,

                            hourMinuteColor: EaColor.back,
                            hourMinuteTextColor: EaColor.fore,
                            hourMinuteTextStyle: EaText.primary,
                            
                            shape: RoundedRectangleBorder(
                              side: BorderSide(color: EaColor.border),
                            ),

                            hourMinuteShape: RoundedRectangleBorder(
                              side: BorderSide(color: EaColor.border),
                            ),

                            confirmButtonStyle: ButtonStyle(
                              textStyle: WidgetStatePropertyAll(EaText.secondary),
                              foregroundColor: WidgetStateColor.fromMap({
                                WidgetState.any: EaColor.fore,
                                WidgetState.pressed:
                                    EaColor.fore.withValues(alpha: .75),
                              }),
                            ),

                            cancelButtonStyle: ButtonStyle(
                              textStyle: WidgetStatePropertyAll(EaText.secondary),
                              foregroundColor: WidgetStateColor.fromMap({
                                WidgetState.any: EaColor.fore,
                                WidgetState.pressed:
                                    EaColor.fore.withValues(alpha: .75),
                              }),
                            ),
                          ),
                        ),
                        child: child!,
                      );
                    }
                  );
                  if (picked != null) {
                    final minutes = toMinutes(picked);
                    setState(() => state.timestamp = minutes);
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
