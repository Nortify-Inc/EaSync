/*!
 * @file dashboard.dart
 * @brief Dashboard screen with visualization and quick control of devices.
 * @param uuid Identifier of the selected device for interaction.
 * @return Widgets and handlers for state updates.
 * @author Erick Radmann
 */

import 'handler.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> with TickerProviderStateMixin {
  static const double _capRowGap = 12;
  static const double _dotFadeOutThreshold = 0.035;
  static const List<String> _templateCategories = [
    'acs',
    'lamps',
    'fridges',
    'locks',
    'curtains',
    'heated_floors',
    'mocks',
  ];

  bool loading = true;
  String? error;

  List<DeviceInfo> devices = [];

  final Map<String, int> capIndexByDevice = {};
  final Map<String, double> animatedProgress = {};
  final Map<String, double> previousProgress = {};
  final Map<String, Color> ringColorByDevice = {};
  final Map<String, Color> previousRingColorByDevice = {};
  final Set<String> initializedDevices = {};
  final Map<String, String> _assetByBrandModel = {};
  final Map<String, String> _assetByModel = {};
  bool _templateAssetsLoaded = false;

  StreamSubscription<String>? _stateSub;
  StreamSubscription<CoreEventData>? _eventSub;
  final PageStorageBucket _bucket = PageStorageBucket();

  double _snapStep(double value, double step) {
    if (step <= 0) return value;
    return (value / step).round() * step;
  }

  int _divisions(double min, double max, double step) {
    if (step <= 0) return 1;
    final raw = ((max - min) / step).round();
    return raw.clamp(1, 400);
  }

  double _clampByConstraint(
    String uuid,
    String key,
    double value,
    double fallbackMin,
    double fallbackMax,
  ) {
    final min = Bridge.constraintMin(uuid, key, fallbackMin);
    final max = Bridge.constraintMax(uuid, key, fallbackMax);
    return value.clamp(min, max);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDevices());
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _eventSub?.cancel();
    super.dispose();
  }

  Future<void> _ensureTemplateAssetsLoaded() async {
    if (_templateAssetsLoaded) return;

    try {
      final loaded = await Future.wait(
        _templateCategories.map((c) => TemplateRepository.loadCategory(c)),
      );

      for (final templates in loaded) {
        for (final t in templates) {
          final asset = t.asset;
          if (asset == null || asset.trim().isEmpty) continue;

          final brand = t.brand.trim().toLowerCase();
          final model = t.model.trim().toLowerCase();
          if (model.isEmpty) continue;

          _assetByModel.putIfAbsent(model, () => asset);

          if (brand.isNotEmpty) {
            _assetByBrandModel.putIfAbsent('$brand|$model', () => asset);
          }
        }
      }
    } catch (_) {
      // keep icon fallback if template assets cannot be loaded
    } finally {
      _templateAssetsLoaded = true;
    }
  }

  String? _resolveAssetForDevice(DeviceInfo d) {
    final existing = Bridge.deviceAsset(d.uuid);
    if (existing != null && existing.trim().isNotEmpty) {
      final normalized = existing.trim();
      if (normalized.toLowerCase().endsWith('.jpg')) {
        return '${normalized.substring(0, normalized.length - 4)}.png';
      }
      return normalized;
    }

    final brand = d.brand.trim().toLowerCase();
    final model = d.model.trim().toLowerCase();

    if (brand.isNotEmpty && model.isNotEmpty) {
      final byPair = _assetByBrandModel['$brand|$model'];
      if (byPair != null) return byPair;
    }

    if (model.isNotEmpty) {
      final byModel = _assetByModel[model];
      if (byModel != null) return byModel;
    }

    final lowerName = d.name.toLowerCase();
    for (final entry in _assetByModel.entries) {
      if (lowerName.contains(entry.key)) return entry.value;
    }

    return null;
  }

  Future<void> _loadDevices() async {
    setState(() => loading = true);

    try {
      await _ensureTemplateAssetsLoaded();

      devices = Bridge.listDevices();

      for (final d in devices) {
        final resolved = _resolveAssetForDevice(d);
        if (resolved != null) {
          Bridge.setDeviceAsset(d.uuid, resolved);
        }
      }

      for (var d in devices) {
        if (d.capabilities.isEmpty) continue;

        final stored =
            PageStorage.of(context).readState(context, identifier: d.uuid)
                as int?;
        final rawCapIndex = stored ?? capIndexByDevice[d.uuid] ?? 0;
        final capIndex = rawCapIndex.clamp(0, d.capabilities.length - 1);
        final cap = d.capabilities[capIndex];

        final progress = _capProgress(d, cap);
        previousProgress[d.uuid] = animatedProgress[d.uuid] ?? progress;
        animatedProgress[d.uuid] = progress;

        final color = _capColor(d, cap);
        previousRingColorByDevice[d.uuid] =
          ringColorByDevice[d.uuid] ?? color;
        ringColorByDevice[d.uuid] = color;

        capIndexByDevice[d.uuid] = capIndex;
      }

      _stateSub ??= Bridge.onStateChanged.listen((uuid) {
        if (devices.isEmpty) return;

        final maybeDevice = devices.where((d) => d.uuid == uuid);
        if (maybeDevice.isEmpty) {
          _loadDevices();
          return;
        }

        final device = maybeDevice.first;
        if (device.capabilities.isEmpty) return;

        final safeIndex = (capIndexByDevice[uuid] ?? 0).clamp(
          0,
          device.capabilities.length - 1,
        );
        capIndexByDevice[uuid] = safeIndex;

        final cap = device.capabilities[safeIndex];

        final newProgress = _capProgress(device, cap);
        final oldProgress = animatedProgress[uuid] ?? newProgress;
        final newRingColor = _capColor(device, cap);
        final oldRingColor = ringColorByDevice[uuid] ?? newRingColor;

        if ((newProgress - oldProgress).abs() > 0.001) {
          previousProgress[uuid] = oldProgress;
          animatedProgress[uuid] = newProgress;
        }

        if (oldRingColor.toARGB32() != newRingColor.toARGB32()) {
          previousRingColorByDevice[uuid] = oldRingColor;
          ringColorByDevice[uuid] = newRingColor;
        }

        if (mounted) setState(() {});
      });

      _eventSub ??= Bridge.onEvents.listen((event) {
        if (event.type == CoreEventType.CORE_EVENT_DEVICE_ADDED ||
            event.type == CoreEventType.CORE_EVENT_DEVICE_REMOVED) {
          _loadDevices();
        }
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

    double normalize(double value, double min, double max) {
      final span = (max - min).abs();
      if (span < 0.000001) return 0;
      return ((value - min) / (max - min)).clamp(0.0, 1.0);
    }

    switch (cap) {
      case CoreCapability.CORE_CAP_POWER:
        return s.power ? 1 : 0;

      case CoreCapability.CORE_CAP_BRIGHTNESS:
        final min = Bridge.constraintMin(device.uuid, 'brightness', 0);
        final max = Bridge.constraintMax(device.uuid, 'brightness', 100);
        return normalize(s.brightness.toDouble(), min, max);

      case CoreCapability.CORE_CAP_TEMPERATURE:
        final min = Bridge.constraintMin(device.uuid, 'temperature', 16);
        final max = Bridge.constraintMax(device.uuid, 'temperature', 30);
        return normalize(s.temperature, min, max);

      case CoreCapability.CORE_CAP_TEMPERATURE_FRIDGE:
        final min = Bridge.constraintMin(device.uuid, 'temperature_fridge', 1);
        final max = Bridge.constraintMax(device.uuid, 'temperature_fridge', 8);
        return 1 - normalize(s.temperatureFridge, min, max);

      case CoreCapability.CORE_CAP_TEMPERATURE_FREEZER:
        final min = Bridge.constraintMin(
          device.uuid,
          'temperature_freezer',
          -24,
        );
        final max = Bridge.constraintMax(
          device.uuid,
          'temperature_freezer',
          -14,
        );
        return 1 - normalize(s.temperatureFreezer, min, max);

      case CoreCapability.CORE_CAP_COLOR:
        return HSVColor.fromColor(Color(0xFF000000 | s.color)).value;

      case CoreCapability.CORE_CAP_COLOR_TEMPERATURE:
        final min = Bridge.constraintMin(device.uuid, 'colorTemperature', 1500);
        final max = Bridge.constraintMax(device.uuid, 'colorTemperature', 9000);
        return normalize(s.colorTemperature.toDouble(), min, max);

      case CoreCapability.CORE_CAP_LOCK:
        return s.lock ? 1 : 0;

      case CoreCapability.CORE_CAP_MODE:
        final maxIndex = (Bridge.modeCount(device.uuid) - 1).clamp(1, 20);
        return (s.mode.clamp(0, maxIndex) / maxIndex).clamp(0.0, 1.0);

      case CoreCapability.CORE_CAP_POSITION:
        return (s.position / 100).clamp(0.0, 1.0);

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
        return s.power
            ? const Color.fromARGB(255, 0, 255, 90)
            : const Color.fromARGB(255, 255, 36, 36);

      case CoreCapability.CORE_CAP_BRIGHTNESS:
        return const Color.fromARGB(255, 255, 128, 0);

      case CoreCapability.CORE_CAP_TEMPERATURE:
        return const Color.fromARGB(255, 140, 0, 255);

      case CoreCapability.CORE_CAP_TEMPERATURE_FRIDGE:
        return const Color.fromARGB(255, 0, 204, 255);

      case CoreCapability.CORE_CAP_TEMPERATURE_FREEZER:
        return const Color.fromARGB(255, 0, 153, 255);

      case CoreCapability.CORE_CAP_TIMESTAMP:
        return const Color.fromARGB(255, 50, 120, 255);

      case CoreCapability.CORE_CAP_COLOR_TEMPERATURE:
        return const Color.fromARGB(255, 255, 191, 0);

      case CoreCapability.CORE_CAP_LOCK:
        return s.lock
            ? const Color.fromARGB(255, 255, 40, 40)
            : const Color.fromARGB(255, 64, 255, 128);

      case CoreCapability.CORE_CAP_MODE:
        return const Color.fromARGB(255, 90, 80, 255);

      case CoreCapability.CORE_CAP_POSITION:
        return const Color.fromARGB(255, 0, 220, 180);

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
      case CoreCapability.CORE_CAP_TEMPERATURE_FRIDGE:
        return Icons.kitchen_outlined;
      case CoreCapability.CORE_CAP_TEMPERATURE_FREEZER:
        return Icons.ac_unit;
      case CoreCapability.CORE_CAP_TIMESTAMP:
        return Icons.schedule;
      case CoreCapability.CORE_CAP_COLOR_TEMPERATURE:
        return Icons.tonality;
      case CoreCapability.CORE_CAP_LOCK:
        return Icons.lock_outline;
      case CoreCapability.CORE_CAP_MODE:
        return Icons.tune;
      case CoreCapability.CORE_CAP_POSITION:
        return Icons.straighten;
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
        final b = _clampByConstraint(
          device.uuid,
          'brightness',
          s.brightness.toDouble(),
          0,
          100,
        );
        return "${b.round()}%";

      case CoreCapability.CORE_CAP_COLOR:
        return s.color;

      case CoreCapability.CORE_CAP_TEMPERATURE:
        final t = _clampByConstraint(
          device.uuid,
          'temperature',
          s.temperature,
          16,
          30,
        );
        return "${t.toStringAsFixed(1)}°C";

      case CoreCapability.CORE_CAP_TEMPERATURE_FRIDGE:
        final t = _clampByConstraint(
          device.uuid,
          'temperature_fridge',
          s.temperatureFridge,
          1,
          8,
        );
        return "${t.toStringAsFixed(1)}°C";

      case CoreCapability.CORE_CAP_TEMPERATURE_FREEZER:
        final t = _clampByConstraint(
          device.uuid,
          'temperature_freezer',
          s.temperatureFreezer,
          -24,
          -14,
        );
        return "${t.toStringAsFixed(1)}°C";

      case CoreCapability.CORE_CAP_COLOR_TEMPERATURE:
        final c = _clampByConstraint(
          device.uuid,
          'colorTemperature',
          s.colorTemperature.toDouble(),
          1500,
          9000,
        );
        return "${c.round()}K";

      case CoreCapability.CORE_CAP_LOCK:
        return s.lock ? "Locked" : "Unlocked";

      case CoreCapability.CORE_CAP_MODE:
        final idx = s.mode.clamp(0, Bridge.modeCount(device.uuid) - 1);
        return Bridge.modeName(device.uuid, idx);

      case CoreCapability.CORE_CAP_POSITION:
        final p = _clampByConstraint(
          device.uuid,
          'position',
          s.position,
          0,
          100,
        );
        return "${p.toStringAsFixed(0)}%";

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
    final targetColor = _capColor(device, caps[next]);

    previousProgress[device.uuid] = animatedProgress[device.uuid] ?? target;

    animatedProgress[device.uuid] = target;

    final oldColor = ringColorByDevice[device.uuid] ?? targetColor;
    previousRingColorByDevice[device.uuid] = oldColor;
    ringColorByDevice[device.uuid] = targetColor;

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

    final brightMin = Bridge.constraintMin(device.uuid, 'brightness', 0.0);
    final brightMax = Bridge.constraintMax(device.uuid, 'brightness', 100.0);
    final brightStep = Bridge.constraintStep(device.uuid, 'brightness', 1.0);

    final tempMin = Bridge.constraintMin(device.uuid, 'temperature', 16.0);
    final tempMax = Bridge.constraintMax(device.uuid, 'temperature', 30.0);
    final tempStep = Bridge.constraintStep(device.uuid, 'temperature', 0.5);

    final fridgeMin = Bridge.constraintMin(
      device.uuid,
      'temperature_fridge',
      1.0,
    );
    final fridgeMax = Bridge.constraintMax(
      device.uuid,
      'temperature_fridge',
      8.0,
    );
    final fridgeStep = Bridge.constraintStep(
      device.uuid,
      'temperature_fridge',
      0.5,
    );

    final freezerMin = Bridge.constraintMin(
      device.uuid,
      'temperature_freezer',
      -24.0,
    );
    final freezerMax = Bridge.constraintMax(
      device.uuid,
      'temperature_freezer',
      -14.0,
    );
    final freezerStep = Bridge.constraintStep(
      device.uuid,
      'temperature_freezer',
      0.5,
    );

    final colorTempMin = Bridge.constraintMin(
      device.uuid,
      'colorTemperature',
      1500.0,
    );
    final colorTempMax = Bridge.constraintMax(
      device.uuid,
      'colorTemperature',
      9000.0,
    );

    int brightness = state.brightness.clamp(
      brightMin.toInt(),
      brightMax.toInt(),
    );
    double temperature = state.temperature.clamp(tempMin, tempMax);
    int color = state.color;
    bool power = state.power;
    double temperatureFridge = state.temperatureFridge.clamp(
      fridgeMin,
      fridgeMax,
    );
    double temperatureFreezer = state.temperatureFreezer.clamp(
      freezerMin,
      freezerMax,
    );
    int colorTemperature = state.colorTemperature.clamp(
      colorTempMin.toInt(),
      colorTempMax.toInt(),
    );
    bool lock = state.lock;
    int mode = state.mode;
    double position = state.position;

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
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    tickMarkShape: SliderTickMarkShape.noTickMark,
                    showValueIndicator: ShowValueIndicator.never,
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
                            const SizedBox(height: _capRowGap),
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
                              min: brightMin,
                              max: brightMax,
                              divisions: _divisions(
                                brightMin,
                                brightMax,
                                brightStep,
                              ),
                              value: brightness.toDouble().clamp(
                                brightMin,
                                brightMax,
                              ),
                              activeColor: EaColor.fore,
                              inactiveColor: EaColor.fore.withValues(
                                alpha: .25,
                              ),
                              onChanged: (v) {
                                final snapped = _snapStep(
                                  v,
                                  brightStep,
                                ).clamp(brightMin, brightMax).round();
                                setInnerState(() => brightness = snapped);
                                Bridge.setBrightness(device.uuid, snapped);
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
                            Icon(
                              Icons.color_lens,
                              size: 18,
                              color: EaColor.fore,
                            ),
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
                                  () =>
                                      color = selected.toARGB32() & 0xFFFFFFFF,
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
                            const SizedBox(height: _capRowGap),
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
                              min: tempMin,
                              max: tempMax,
                              divisions: _divisions(tempMin, tempMax, tempStep),
                              value: temperature,
                              activeColor: EaColor.fore,
                              inactiveColor: EaColor.fore.withValues(
                                alpha: .25,
                              ),
                              onChanged: (v) {
                                final snapped = _snapStep(
                                  v,
                                  tempStep,
                                ).clamp(tempMin, tempMax);
                                setInnerState(() => temperature = snapped);
                                Bridge.setTemperature(device.uuid, snapped);
                                setState(() {});
                              },
                              onChangeEnd: (_) {},
                            ),
                          ],
                        ),
                      if (device.capabilities.contains(
                        CoreCapability.CORE_CAP_TEMPERATURE_FRIDGE,
                      ))
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: _capRowGap),
                            Row(
                              children: [
                                const Icon(
                                  Icons.kitchen_outlined,
                                  size: 18,
                                  color: EaColor.fore,
                                ),

                                const SizedBox(width: 8),

                                Text("Fridge", style: EaText.secondary),

                                const Spacer(),

                                Text(
                                  "${temperatureFridge.toStringAsFixed(1)}°C",
                                  style: EaText.secondary.copyWith(
                                    color: EaColor.fore,
                                  ),
                                ),

                                SizedBox(width: 10),
                              ],
                            ),

                            Slider(
                              min: fridgeMin,
                              max: fridgeMax,
                              divisions: _divisions(
                                fridgeMin,
                                fridgeMax,
                                fridgeStep,
                              ),
                              value: temperatureFridge,
                              activeColor: EaColor.fore,
                              inactiveColor: EaColor.fore.withValues(
                                alpha: .25,
                              ),
                              onChanged: (v) {
                                final snapped = _snapStep(
                                  v,
                                  fridgeStep,
                                ).clamp(fridgeMin, fridgeMax);
                                setInnerState(
                                  () => temperatureFridge = snapped,
                                );
                                Bridge.setTemperatureFridge(
                                  device.uuid,
                                  snapped,
                                );
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                      if (device.capabilities.contains(
                        CoreCapability.CORE_CAP_TEMPERATURE_FREEZER,
                      ))
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: _capRowGap),
                            Row(
                              children: [
                                const Icon(
                                  Icons.ac_unit,
                                  size: 18,
                                  color: EaColor.fore,
                                ),

                                const SizedBox(width: 8),

                                Text("Freezer", style: EaText.secondary),

                                const Spacer(),

                                Text(
                                  "${temperatureFreezer.toStringAsFixed(1)}°C",
                                  style: EaText.secondary.copyWith(
                                    color: EaColor.fore,
                                  ),
                                ),

                                SizedBox(width: 10),
                              ],
                            ),

                            Slider(
                              min: freezerMin,
                              max: freezerMax,
                              divisions: _divisions(
                                freezerMin,
                                freezerMax,
                                freezerStep,
                              ),
                              value: temperatureFreezer,
                              activeColor: EaColor.fore,
                              inactiveColor: EaColor.fore.withValues(
                                alpha: .25,
                              ),
                              onChanged: (v) {
                                final snapped = _snapStep(
                                  v,
                                  freezerStep,
                                ).clamp(freezerMin, freezerMax);
                                setInnerState(
                                  () => temperatureFreezer = snapped,
                                );
                                Bridge.setTemperatureFreezer(
                                  device.uuid,
                                  snapped,
                                );
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                      if (device.capabilities.contains(
                        CoreCapability.CORE_CAP_COLOR_TEMPERATURE,
                      ))
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: _capRowGap),
                            Row(
                              children: [
                                const Icon(
                                  Icons.tonality,
                                  size: 18,
                                  color: EaColor.fore,
                                ),

                                const SizedBox(width: 8),

                                Text(
                                  "Color temperature",
                                  style: EaText.secondary,
                                ),

                                const Spacer(),

                                Text(
                                  "${colorTemperature.round()}K",
                                  style: EaText.secondary.copyWith(
                                    color: EaColor.fore,
                                  ),
                                ),

                                SizedBox(width: 10),
                              ],
                            ),

                            Slider(
                              min: colorTempMin,
                              max: colorTempMax,
                              divisions: _divisions(
                                colorTempMin,
                                colorTempMax,
                                100,
                              ),
                              value: colorTemperature
                                  .clamp(
                                    colorTempMin.toInt(),
                                    colorTempMax.toInt(),
                                  )
                                  .toDouble(),
                              activeColor: EaColor.fore,
                              inactiveColor: EaColor.fore.withValues(
                                alpha: .25,
                              ),
                              onChanged: (v) {
                                setInnerState(
                                  () => colorTemperature = v.round(),
                                );
                                Bridge.setColorTemperature(
                                  device.uuid,
                                  v.round(),
                                );
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                      if (device.capabilities.contains(
                        CoreCapability.CORE_CAP_LOCK,
                      ))
                        Row(
                          children: [
                            const Icon(
                              Icons.lock_outline,
                              size: 18,
                              color: EaColor.fore,
                            ),

                            const SizedBox(width: 8),

                            Text("Lock", style: EaText.secondary),

                            const Spacer(),

                            Switch(
                              value: lock,
                              activeThumbColor: EaColor.fore,
                              inactiveTrackColor: EaColor.back,
                              onChanged: (v) {
                                setInnerState(() => lock = v);
                                Bridge.setLock(device.uuid, v);
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                      if (device.capabilities.contains(
                        CoreCapability.CORE_CAP_MODE,
                      ))
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: _capRowGap),
                            Row(
                              children: [
                                const Icon(
                                  Icons.tune,
                                  size: 18,
                                  color: EaColor.fore,
                                ),

                                const SizedBox(width: 8),

                                Text("Mode", style: EaText.secondary),

                                const Spacer(),

                                Text(
                                  Bridge.modeName(device.uuid, mode),
                                  style: EaText.secondary.copyWith(
                                    color: EaColor.fore,
                                  ),
                                ),
                                SizedBox(width: 10),
                              ],
                            ),

                            Slider(
                              min: 0,
                              max: (Bridge.modeCount(device.uuid) - 1)
                                  .toDouble(),
                              divisions: (Bridge.modeCount(device.uuid) - 1)
                                  .clamp(1, 20),
                              value: mode.toDouble().clamp(
                                0,
                                (Bridge.modeCount(device.uuid) - 1).toDouble(),
                              ),
                              activeColor: EaColor.fore,
                              inactiveColor: EaColor.fore.withValues(
                                alpha: .25,
                              ),
                              onChanged: (v) {
                                setInnerState(() => mode = v.round());
                                Bridge.setMode(device.uuid, v.round());
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                      if (device.capabilities.contains(
                        CoreCapability.CORE_CAP_POSITION,
                      ))
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                const Icon(
                                  Icons.straighten,
                                  size: 18,
                                  color: EaColor.fore,
                                ),

                                const SizedBox(width: 8),

                                Text("Position", style: EaText.secondary),

                                const Spacer(),

                                Text(
                                  "${position.round()}%",
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
                              value: position.clamp(0, 100),
                              activeColor: EaColor.fore,
                              inactiveColor: EaColor.fore.withValues(
                                alpha: .25,
                              ),
                              onChanged: (v) {
                                setInnerState(() => position = v);
                                Bridge.setPosition(device.uuid, v);
                                setState(() {});
                              },
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
    int selectedMinutes = state.timestamp;

    TimeOfDay? toTime(int? m) {
      if (m == null || m < 0) return null;

      final h = m ~/ 60;
      final min = m % 60;

      return TimeOfDay(hour: h, minute: min);
    }

    int toMinutes(TimeOfDay t) {
      return t.hour * 60 + t.minute;
    }

    final time = toTime(selectedMinutes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: _capRowGap),

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
                    setInnerState(() {
                      selectedMinutes = minutes;
                    });
                    setState(() {});
                    Bridge.setTime(device.uuid, minutes);
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
    final deviceAssetPath = Bridge.deviceAsset(device.uuid);

    final target = animatedProgress[device.uuid] ?? _capProgress(device, cap);

    final begin = previousProgress[device.uuid] ?? target;

    final ringColorTarget = _capColor(device, cap);

    double dragStartX = 0;
    double dragDelta = 0;

    return SizedBox(
      width: size + 40,
      height: size + 80,
      child: Column(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: begin, end: target),
            duration: const Duration(milliseconds: 720),
            curve: Curves.easeOutSine,
            builder: (_, animated, _) {
              return TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: ringColorTarget),
                duration: const Duration(milliseconds: 360),
                curve: Curves.easeOutCubic,
                builder: (_, animatedColor, child) {
                  final effectiveRingColor = animatedColor ?? ringColorTarget;

                  return RepaintBoundary(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween(
                            end: animated > _dotFadeOutThreshold ? 1.0 : 0.0,
                          ),
                          duration: const Duration(milliseconds: 360),
                          curve: Curves.easeOutCubic,
                          builder: (_, dotOpacity, _) {
                            return CustomPaint(
                              size: Size(size + 30, size + 30),
                              painter: _RingPainter(
                                ringColor: effectiveRingColor,
                                progress: animated,
                                showDot: true,
                                dotOpacity: dotOpacity,
                              ),
                            );
                          },
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
                        border: Border.all(color: effectiveRingColor, width: 1.4),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          SizedBox(height: 15),
                          deviceAssetPath != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.asset(
                                    'assets/$deviceAssetPath',
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Icon(
                                      _capIcon(cap),
                                      size: 28,
                                      color: EaColor.fore,
                                    ),
                                  ),
                                )
                              : Icon(
                                  _capIcon(cap),
                                  size: 28,
                                  color: EaColor.fore,
                                ),
                          Spacer(),
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
                                        color: effectiveRingColor,
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
                    ),
                  );
                },
              );
            },
          ),
          SizedBox(
            height: 34,
            child: Text(
              device.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: EaText.secondary.copyWith(fontSize: 12, height: 1.2),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final Color ringColor;
  final double progress;
  final bool showDot;
  final double dotOpacity;
  double ringWidth = 6;

  _RingPainter({
    required this.ringColor,
    required this.progress,
    required this.showDot,
    this.dotOpacity = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final normalized = progress.clamp(0.0, 1.0);

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
      ..color = EaColor.background;

    canvas.drawCircle(center, radius, baseRing);

    final start = (5 * pi) / 4;
    final end = (6 * pi) / 4;

    final sweep = end * normalized;

    if (normalized > 0.0001) {
      const totalSegments = 720;
      final visibleSegments = max(1, (totalSegments * normalized).round());
      final segmentSweep = sweep / visibleSegments;
      const overlap = 0.00035;

      final localRect = Rect.fromCircle(center: Offset.zero, radius: radius);

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(-start);

      for (int i = 0; i < visibleSegments; i++) {
        final t = visibleSegments == 1 ? 1.0 : i / (visibleSegments - 1);
        final segmentPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringWidth
          ..strokeCap = StrokeCap.butt
          ..isAntiAlias = true
          ..color = Color.lerp(EaColor.background, ringColor, t) ?? ringColor;

        canvas.drawArc(
          localRect,
          segmentSweep * i,
          segmentSweep + overlap,
          false,
          segmentPaint,
        );
      }

      canvas.restore();
    }

    final effectiveDotOpacity = dotOpacity.clamp(0.0, 1.0);

    if (!showDot || normalized <= 0.0001 || effectiveDotOpacity <= 0.001) {
      return;
    }

    final angle = -start + sweep;

    final dotOffset = Offset(
      center.dx + cos(angle) * radius,
      center.dy + sin(angle) * radius,
    );

    final dotPaint = Paint()
      ..color = ringColor.withValues(alpha: effectiveDotOpacity);

    canvas.drawCircle(dotOffset, ringWidth * 1.4, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) {
    return old.progress != progress ||
        old.ringColor != ringColor ||
        old.showDot != showDot ||
        old.dotOpacity != dotOpacity;
  }
}
