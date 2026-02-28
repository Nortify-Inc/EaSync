import 'handler.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> with TickerProviderStateMixin {
  bool loading = true;
  String? error;

  List<DeviceInfo> devices = [];

  final Map<String, int> capIndexByDevice = {};
  final Map<String, double> animatedProgress = {};
  final Map<String, double> previousProgress = {};
  final Set<String> initializedDevices = {};

  StreamSubscription<String>? _stateSub;
  final PageStorageBucket _bucket = PageStorageBucket();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDevices());
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    setState(() => loading = true);

    try {
      devices = Bridge.listDevices();
      for (var d in devices) {
        final stored =
            PageStorage.of(context).readState(context, identifier: d.uuid)
                as int?;
        final capIndex = stored ?? capIndexByDevice[d.uuid] ?? 0;
        final cap = d.capabilities[capIndex];

        previousProgress[d.uuid] = 0.0;
        animatedProgress[d.uuid] = _capProgress(d, cap);

        capIndexByDevice[d.uuid] = capIndex;
      }

      _stateSub ??= Bridge.onStateChanged.listen((uuid) {
        final device = devices.firstWhere(
          (d) => d.uuid == uuid,
          orElse: () => devices.first,
        );

        final index = capIndexByDevice[uuid] ?? 0;
        final cap = device.capabilities[index];

        final newProgress = _capProgress(device, cap);
        final oldProgress = animatedProgress[uuid] ?? newProgress;

        if ((newProgress - oldProgress).abs() > 0.001) {
          previousProgress[uuid] = oldProgress;
          animatedProgress[uuid] = newProgress;
        }

        setState(() {});
      });

      loading = false;

      setState(() {});

      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {});
      });
    } catch (e) {
      error = e.toString();
      loading = false;
      setState(() {});
    }
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

  double _capProgress(DeviceInfo device, int cap) {
    final s = Bridge.getState(device.uuid);

    switch (cap) {
      case CoreCapability.CORE_CAP_POWER:
        return s.power ? 1 : 0;

      case CoreCapability.CORE_CAP_BRIGHTNESS:
        return (s.brightness / 100).clamp(0.0, 1.0);

      case CoreCapability.CORE_CAP_TEMPERATURE:
        return ((s.temperature + 10) / 46).clamp(0.0, 1.0);

      case CoreCapability.CORE_CAP_COLOR:
        return HSVColor.fromColor(Color(0xFF000000 | s.color)).value;

      case CoreCapability.CORE_CAP_TIMESTAMP:
        return (s.timestamp % 1440) / 1440;

      default:
        return 0;
    }
  }

  Color _capColor(DeviceInfo device, int cap) {
    final s = Bridge.getState(device.uuid);

    switch (cap) {
      case CoreCapability.CORE_CAP_POWER:
        return s.power ? Colors.green : Colors.red;

      case CoreCapability.CORE_CAP_BRIGHTNESS:
        return Colors.amber;

      case CoreCapability.CORE_CAP_TEMPERATURE:
        return Colors.orange;

      case CoreCapability.CORE_CAP_TIMESTAMP:
        return Colors.blue;

      case CoreCapability.CORE_CAP_COLOR:
        return Color(0xFF000000 | s.color);

      default:
        return EaColor.fore;
    }
  }

  IconData _capIcon(int cap) {
    switch (cap) {
      case CoreCapability.CORE_CAP_POWER:
        return Icons.power_settings_new;
      case CoreCapability.CORE_CAP_BRIGHTNESS:
        return Icons.brightness_6_outlined;
      case CoreCapability.CORE_CAP_COLOR:
        return Icons.color_lens;
      case CoreCapability.CORE_CAP_TEMPERATURE:
        return Icons.thermostat;
      case CoreCapability.CORE_CAP_TIMESTAMP:
        return Icons.schedule;
      default:
        return Icons.info_outline;
    }
  }

  dynamic _capValue(DeviceInfo device, int cap) {
    final s = Bridge.getState(device.uuid);

    switch (cap) {
      case CoreCapability.CORE_CAP_POWER:
        return s.power ? "On" : "Off";

      case CoreCapability.CORE_CAP_BRIGHTNESS:
        return "${s.brightness}%";

      case CoreCapability.CORE_CAP_COLOR:
        return s.color;

      case CoreCapability.CORE_CAP_TEMPERATURE:
        return "${s.temperature.toStringAsFixed(1)}°C";

      case CoreCapability.CORE_CAP_TIMESTAMP:
        final h = (s.timestamp ~/ 60).toString().padLeft(2, '0');
        final m = (s.timestamp % 60).toString().padLeft(2, '0');

        return "$h:$m";

      default:
        return "";
    }
  }

  void _changeCap(DeviceInfo device, int dir) {
    final caps = device.capabilities;

    final current = capIndexByDevice[device.uuid] ?? 0;
    final next = (current + dir + caps.length) % caps.length;

    capIndexByDevice[device.uuid] = next;
    PageStorage.of(context).writeState(context, next, identifier: device.uuid);

    final target = _capProgress(device, caps[next]);

    previousProgress[device.uuid] = animatedProgress[device.uuid] ?? target;

    animatedProgress[device.uuid] = target;

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return _loading();
    if (error != null) return _errorState();
    if (devices.isEmpty) return _emptyState();

    return PageStorage(
      bucket: _bucket,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Wrap(
          spacing: 18,
          runSpacing: 18,
          children: devices.map((d) => _deviceCard(d)).toList(),
        ),
      ),
    );
  }

  Future<void> _openDeviceControl(DeviceInfo device) async {
    final state = Bridge.getState(device.uuid);
    int brightness = state.brightness;
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
                    Text(device.name, style: EaText.primary),
                    const SizedBox(height: 16),
                    if (device.capabilities.contains(
                      CoreCapability.CORE_CAP_POWER,
                    ))
                      Row(
                        children: [
                          const Icon(
                            Icons.power_settings_new,
                            size: 18,
                            color: EaColor.fore,
                          ),

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
                              const Icon(
                                Icons.brightness_6_outlined,
                                size: 18,
                                color: EaColor.fore,
                              ),

                              const SizedBox(width: 8),

                              Text("Brightness", style: EaText.secondary),

                              const Spacer(),

                              Text(
                                "${brightness.round()}%",
                                style: EaText.secondary.copyWith(
                                  color: EaColor.fore,
                                ),
                              ),

                              SizedBox(width: 10),
                            ],
                          ),

                          Slider(
                            min: 0,
                            max: 100,
                            divisions: 100,
                            value: brightness.toDouble(),
                            activeColor: EaColor.fore,
                            inactiveColor: EaColor.fore.withValues(alpha: .25),
                            onChanged: (v) {
                              setInnerState(() => brightness = v.round());
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
                                              margin: const EdgeInsets.only(
                                                bottom: 16,
                                              ),
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
                                                setModalState(
                                                  () => selected = c,
                                                );
                                              },
                                            ),

                                            const SizedBox(height: 16),
                                            ElevatedButton(
                                              onPressed: () {
                                                final rgb =
                                                    selected.toARGB32() &
                                                    0xFFFFFFFF;
                                                Bridge.setColor(
                                                  device.uuid,
                                                  rgb,
                                                );
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

                              setInnerState(
                                () => color = selected.toARGB32() & 0xFFFFFFFF,
                              );
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

                          const SizedBox(width: 10),
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
                              const Icon(
                                Icons.thermostat,
                                size: 18,
                                color: EaColor.fore,
                              ),

                              const SizedBox(width: 8),

                              Text("Temperature", style: EaText.secondary),

                              const Spacer(),

                              Text(
                                "${temperature.toStringAsFixed(1)}°C",
                                style: EaText.secondary.copyWith(
                                  color: EaColor.fore,
                                ),
                              ),

                              SizedBox(width: 10),
                            ],
                          ),

                          Slider(
                            min: -10,
                            max: 36,
                            divisions: (10 + 36) * 2,
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
              ),
            );
          },
        );
      },
    );
    setState(() {});
  }

  Widget _buildScheduleControl(
    DeviceInfo device,
    void Function(void Function()) setInnerState,
  ) {
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
                                color: EaColor.fore,
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
                              textStyle: WidgetStatePropertyAll(
                                EaText.secondary,
                              ),
                              foregroundColor: WidgetStateColor.fromMap({
                                WidgetState.any: EaColor.fore,
                                WidgetState.pressed: EaColor.fore.withValues(
                                  alpha: .75,
                                ),
                              }),
                            ),

                            cancelButtonStyle: ButtonStyle(
                              textStyle: WidgetStatePropertyAll(
                                EaText.secondary,
                              ),
                              foregroundColor: WidgetStateColor.fromMap({
                                WidgetState.any: EaColor.fore,
                                WidgetState.pressed: EaColor.fore.withValues(
                                  alpha: .75,
                                ),
                              }),
                            ),
                          ),
                        ),
                        child: child!,
                      );
                    },
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

  Widget _deviceCard(DeviceInfo device) {
    double size = 145;
    final caps = device.capabilities;
    final index = capIndexByDevice[device.uuid] ?? 0;
    final cap = caps[index];

    final target = animatedProgress[device.uuid] ?? _capProgress(device, cap);

    final begin = previousProgress[device.uuid] ?? target;

    final ringColor = _capColor(device, cap);

    double dragStartX = 0;
    double dragDelta = 0;

    return SizedBox(
      width: size + 40,
      height: size + 60,
      child: Column(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: begin, end: target),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutSine,
            builder: (_, animated, _) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: Size(size + 30, size + 30),
                    painter: _RingPainter(
                      ringColor: ringColor,
                      progress: animated,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      _openDeviceControl(device);
                    },
                    onHorizontalDragStart: (d) {
                      dragStartX = d.globalPosition.dx;
                    },
                    onHorizontalDragUpdate: (d) {
                      dragDelta = d.globalPosition.dx - dragStartX;
                    },
                    onHorizontalDragEnd: (_) {
                      if (dragDelta.abs() > 50) {
                        _changeCap(device, dragDelta < 0 ? 1 : -1);
                      }
                    },
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: ringColor, width: 1.4),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                width: cap != CoreCapability.CORE_CAP_COLOR
                                    ? null
                                    : 30,
                                height: 30,
                                alignment: Alignment.center,
                                decoration: cap != CoreCapability.CORE_CAP_COLOR
                                    ? BoxDecoration(
                                        color: EaColor.back,
                                        border: BoxBorder.all(
                                          color: EaColor.fore,
                                        ),
                                        borderRadius: BorderRadius.circular(20),
                                      )
                                    : BoxDecoration(
                                        color: ringColor,
                                        border: BoxBorder.all(
                                          color: EaColor.fore,
                                        ),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                child: cap != CoreCapability.CORE_CAP_COLOR
                                    ? Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Icon(
                                            _capIcon(cap),
                                            size: 20,
                                            color: EaColor.secondaryFore,
                                          ),
                                          SizedBox(width: 3),
                                          Text(
                                            _capValue(device, cap),
                                            style: EaText.secondary,
                                          ),
                                        ],
                                      )
                                    : null,
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          Text(
            device.name,
            textAlign: TextAlign.center,
            style: EaText.secondary.copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final Color ringColor;
  final double progress;
  double ringWidth = 6;

  _RingPainter({required this.ringColor, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = min(size.width, size.height) / 2;
    final radius = maxR - ringWidth / 2 - 4;

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [EaColor.background, EaColor.background],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 1.2));

    canvas.drawCircle(center, radius * 1.2, glowPaint);

    final baseRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..color = ringColor.withValues(alpha: .05);

    canvas.drawCircle(center, radius, baseRing);

    final start = (5 * pi) / 4;
    final end = (6 * pi) / 4;

    final sweep = end * progress.clamp(0.0, 1.0);

    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..strokeCap = StrokeCap.round
      ..color = ringColor;

    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(rect, -start, sweep, false, progressPaint);

    final angle = -start + sweep;

    final dotOffset = Offset(
      center.dx + cos(angle) * radius,
      center.dy + sin(angle) * radius,
    );

    final dotPaint = Paint()..color = ringColor;

    canvas.drawCircle(dotOffset, ringWidth * 1.4, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) {
    return old.progress != progress || old.ringColor != ringColor;
  }
}
