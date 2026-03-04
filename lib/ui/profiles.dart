/*!
 * @file profiles.dart
 * @brief Profiles screen to apply multiple batched actions to devices.
 * @param profile Selected profile for editing or execution.
 * @return Widgets and actions for profile creation and execution.
 * @author Erick Radmann
 */

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'handler.dart';

class DeviceAction {
  final String deviceId;

  bool? power;
  int? brightness;
  double? temperature;
  double? temperatureFridge;
  double? temperatureFreezer;
  int? color;
  int? colorTemperature;
  int? time;
  bool? lock;
  int? mode;
  double? position;

  DeviceAction({
    required this.deviceId,
    this.power,
    this.brightness,
    this.temperature,
    this.temperatureFridge,
    this.temperatureFreezer,
    this.color,
    this.colorTemperature,
    this.time,
    this.lock,
    this.mode,
    this.position,
  });
}

class Profile {
  final String name;
  final List<DeviceAction> actions;
  final IconData icon;

  Profile({required this.name, required this.actions, required this.icon});
}

class Profiles extends StatefulWidget {
  const Profiles({super.key});

  @override
  State<Profiles> createState() => _ProfilesState();
}

class _ProfilesState extends State<Profiles>
  with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  static const _kPowerOnByHour = 'assistant.power_on_by_hour';
  static const _kDeviceActivityById = 'assistant.device_activity_by_id';
  static const _kTempSetSum = 'assistant.temp_set_sum';
  static const _kTempSetCount = 'assistant.temp_set_count';
  static const _kBrightnessSetSum = 'assistant.brightness_set_sum';
  static const _kBrightnessSetCount = 'assistant.brightness_set_count';
  static const _kPositionSetSum = 'assistant.position_set_sum';
  static const _kPositionSetCount = 'assistant.position_set_count';

  final List<Profile> profiles = [];
  List<DeviceInfo> devices = [];
  StreamSubscription<CoreEventData>? _eventSub;
  late final AnimationController _profileApplyPulse;
  Timer? _profileApplyPulseTimer;
  String? _highlightedProfileName;
  final Map<String, int> _assistantPowerOnByHour = {};
  final Map<String, int> _assistantDeviceActivityById = {};
  double? _assistantPreferredTemp;
  int? _assistantPreferredBrightness;
  int? _assistantPreferredPosition;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _profileApplyPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 980),
    );
    _loadDevices();
    _loadAssistantPatterns();
    _eventSub = Bridge.onEvents.listen((event) {
      if (event.type == CoreEventType.CORE_EVENT_DEVICE_ADDED ||
          event.type == CoreEventType.CORE_EVENT_DEVICE_REMOVED) {
        _loadDevices();
      }
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _profileApplyPulseTimer?.cancel();
    _profileApplyPulse.dispose();
    super.dispose();
  }

  void _pulseAppliedProfile(Profile profile) {
    _profileApplyPulseTimer?.cancel();
    setState(() => _highlightedProfileName = profile.name);
    _profileApplyPulse
      ..stop()
      ..reset()
      ..forward();
    _profileApplyPulseTimer = Timer(const Duration(milliseconds: 1300), () {
      if (!mounted) return;
      setState(() => _highlightedProfileName = null);
    });
  }

  void _showTopErrorSnack(String message) {
    final overlay = Overlay.of(context, rootOverlay: true);

    final entry = OverlayEntry(
      builder: (_) {
        return Positioned(
          left: 12,
          right: 12,
          top: 30,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: EaColor.back,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: EaColor.fore),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.redAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message,
                      style: EaText.secondary.copyWith(
                        color: EaColor.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 3), () {
      entry.remove();
    });
  }

  void _showBottomSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: EaText.secondary.copyWith(color: EaColor.textPrimary),
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          backgroundColor: EaColor.back,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: EaColor.fore),
          ),
        ),
      );
  }

  void _loadDevices() {
    try {
      devices = Bridge.listDevices();
      setState(() {});
    } catch (_) {}
  }

  Map<String, int> _decodeStringIntMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, int>{};
      for (final e in decoded.entries) {
        final k = e.key.toString();
        final v = int.tryParse(e.value.toString());
        if (k.isEmpty || v == null) continue;
        out[k] = v;
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> _loadAssistantPatterns() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final powerByHour = _decodeStringIntMap(prefs.getString(_kPowerOnByHour));
      final activityById = _decodeStringIntMap(prefs.getString(_kDeviceActivityById));

      final tempSum = prefs.getDouble(_kTempSetSum) ?? 0;
      final tempCount = prefs.getInt(_kTempSetCount) ?? 0;
      final brightSum = prefs.getDouble(_kBrightnessSetSum) ?? 0;
      final brightCount = prefs.getInt(_kBrightnessSetCount) ?? 0;
      final posSum = prefs.getDouble(_kPositionSetSum) ?? 0;
      final posCount = prefs.getInt(_kPositionSetCount) ?? 0;

      if (!mounted) return;
      setState(() {
        _assistantPowerOnByHour
          ..clear()
          ..addAll(powerByHour);
        _assistantDeviceActivityById
          ..clear()
          ..addAll(activityById);
        _assistantPreferredTemp = tempCount > 0 ? (tempSum / tempCount).clamp(16, 30) : null;
        _assistantPreferredBrightness =
            brightCount > 0 ? (brightSum / brightCount).round().clamp(0, 100) : null;
        _assistantPreferredPosition =
            posCount > 0 ? (posSum / posCount).round().clamp(0, 100) : null;
      });
    } catch (_) {}
  }

  void _openEditor({Profile? profile}) {
    _loadDevices();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return _ProfileEditor(
          devices: devices,
          profile: profile,
          onSaved: (p) {
            setState(() {
              if (profile != null) {
                final i = profiles.indexOf(profile);
                profiles[i] = p;
              } else {
                profiles.add(p);
              }
            });

            Navigator.pop(context);
          },
          onDelete: profile == null
              ? null
              : () {
                  setState(() {
                    profiles.remove(profile);
                  });
                  Navigator.pop(context);
                  _showBottomSnack('Profile ${profile.name} was deleted.');
                },
        );
      },
    );
  }

  void _applyProfile(Profile profile) {
    try {
      if (profile.actions.isEmpty) {
        _showBottomSnack('Profile ${profile.name} has no actions.');
        return;
      }

      final byId = {for (final d in devices) d.uuid: d};

      for (final a in profile.actions) {
        final d = byId[a.deviceId];
        if (d == null) continue;

        bool has(int cap) => d.capabilities.contains(cap);

        if (a.power != null && has(CoreCapability.CORE_CAP_POWER)) {
          Bridge.setPower(a.deviceId, a.power!);
        }

        if (a.brightness != null && has(CoreCapability.CORE_CAP_BRIGHTNESS)) {
          Bridge.setBrightness(a.deviceId, a.brightness!);
        }

        if (a.temperature != null && has(CoreCapability.CORE_CAP_TEMPERATURE)) {
          Bridge.setTemperature(a.deviceId, a.temperature!);
        }

        if (a.temperatureFridge != null &&
            has(CoreCapability.CORE_CAP_TEMPERATURE_FRIDGE)) {
          Bridge.setTemperatureFridge(a.deviceId, a.temperatureFridge!);
        }

        if (a.temperatureFreezer != null &&
            has(CoreCapability.CORE_CAP_TEMPERATURE_FREEZER)) {
          Bridge.setTemperatureFreezer(a.deviceId, a.temperatureFreezer!);
        }

        if (a.color != null && has(CoreCapability.CORE_CAP_COLOR)) {
          Bridge.setColor(a.deviceId, a.color!);
        }

        if (a.colorTemperature != null &&
            has(CoreCapability.CORE_CAP_COLOR_TEMPERATURE)) {
          Bridge.setColorTemperature(a.deviceId, a.colorTemperature!);
        }

        if (a.time != null && has(CoreCapability.CORE_CAP_TIMESTAMP)) {
          Bridge.setTime(a.deviceId, a.time!);
        }

        if (a.lock != null && has(CoreCapability.CORE_CAP_LOCK)) {
          Bridge.setLock(a.deviceId, a.lock!);
        }

        if (a.mode != null && has(CoreCapability.CORE_CAP_MODE)) {
          Bridge.setMode(a.deviceId, a.mode!);
        }

        if (a.position != null && has(CoreCapability.CORE_CAP_POSITION)) {
          Bridge.setPosition(a.deviceId, a.position!);
        }
      }

      _showBottomSnack('Profile ${profile.name} was applied.');
      _pulseAppliedProfile(profile);
    } catch (e) {
      _showTopErrorSnack(e.toString());
    }
  }

  DeviceInfo? _firstWithCapability(int capability) {
    for (final d in devices) {
      if (d.capabilities.contains(capability)) return d;
    }
    return null;
  }

  int _topPowerHour() {
    if (_assistantPowerOnByHour.isEmpty) return 18;
    var bestHour = 18;
    var bestCount = -1;
    for (final e in _assistantPowerOnByHour.entries) {
      final hour = int.tryParse(e.key);
      if (hour == null) continue;
      if (e.value > bestCount) {
        bestCount = e.value;
        bestHour = hour.clamp(0, 23);
      }
    }
    return bestHour;
  }

  DeviceInfo? _mostUsedWithCapability(int capability) {
    DeviceInfo? best;
    var bestScore = -1;
    for (final d in devices) {
      if (!d.capabilities.contains(capability)) continue;
      final score = _assistantDeviceActivityById[d.uuid] ?? 0;
      if (score > bestScore) {
        best = d;
        bestScore = score;
      }
    }
    return best ?? _firstWithCapability(capability);
  }

  String _assistantRecommendationReasonLine1() {
    final hour = _topPowerHour();
    final hh = hour.toString().padLeft(2, '0');
    final temp = (_assistantPreferredTemp ?? 23).toStringAsFixed(0);
    final bright = (_assistantPreferredBrightness ?? 45);
    return '$hh:00 • $temp°C • $bright%';
  }

  Profile? _assistantRecommendedProfile() {
    final actions = <DeviceAction>[];

    final climate = _mostUsedWithCapability(CoreCapability.CORE_CAP_TEMPERATURE);
    if (climate != null) {
      actions.add(
        DeviceAction(
          deviceId: climate.uuid,
          power: climate.capabilities.contains(CoreCapability.CORE_CAP_POWER)
              ? true
              : null,
          temperature: _assistantPreferredTemp ?? 23,
        ),
      );
    }

    final light = _mostUsedWithCapability(CoreCapability.CORE_CAP_BRIGHTNESS) ??
        _firstWithCapability(CoreCapability.CORE_CAP_POWER);
    if (light != null) {
      actions.add(
        DeviceAction(
          deviceId: light.uuid,
          power: light.capabilities.contains(CoreCapability.CORE_CAP_POWER)
              ? true
              : null,
          brightness: light.capabilities.contains(CoreCapability.CORE_CAP_BRIGHTNESS)
              ? (_assistantPreferredBrightness ?? 38)
              : null,
        ),
      );
    }

    final curtain = _mostUsedWithCapability(CoreCapability.CORE_CAP_POSITION);
    if (curtain != null) {
      actions.add(
        DeviceAction(
          deviceId: curtain.uuid,
          position: (_assistantPreferredPosition ?? 28).toDouble(),
        ),
      );
    }

    if (actions.isEmpty) return null;
    final hour = _topPowerHour().toString().padLeft(2, '0');
    return Profile(
      name: 'AI Comfort $hour',
      actions: actions,
      icon: Icons.auto_awesome,
    );
  }

  void _addAssistantRecommendedProfile(Profile recommended) {
    var name = recommended.name;
    var index = 2;
    while (profiles.any((p) => p.name.toLowerCase() == name.toLowerCase())) {
      name = '${recommended.name} $index';
      index++;
    }

    setState(() {
      profiles.add(Profile(name: name, actions: recommended.actions, icon: recommended.icon));
    });
    _showBottomSnack('Profile $name was added.');
  }

  Widget _assistantRecommendedCard() {
    final recommended = _assistantRecommendedProfile();
    if (recommended == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              EaColor.back,
              EaColor.back.withValues(alpha: .88),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: EaColor.border),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: EaColor.fore.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.auto_awesome, color: EaColor.fore, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Assistant recommendation',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: EaText.secondary.copyWith(
                      fontSize: 11,
                      color: EaColor.textSecondary.withValues(alpha: .78),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    recommended.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: EaText.primary.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: EaColor.textPrimary,
                    ),
                  ),
                  Text(
                    _assistantRecommendationReasonLine1(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: EaText.secondary.copyWith(
                      fontSize: 12,
                      color: EaColor.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _addAssistantRecommendedProfile(recommended),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add'),
              style: OutlinedButton.styleFrom(
                foregroundColor: EaColor.fore,
                side: const BorderSide(color: EaColor.fore),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                minimumSize: const Size(86, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: EaText.secondary.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return SafeArea(
      child: Column(
        children: [
          Expanded(child: _body()),
          _assistantRecommendedCard(),
          _fab(),
        ],
      ),
    );
  }

  Widget _fab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _openEditor(),
          icon: const Icon(Icons.add),
          label: Text("New profile", style: EaText.primaryBack),
          style: ElevatedButton.styleFrom(
            backgroundColor: EaColor.fore,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (profiles.isEmpty) return _empty();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      itemCount: profiles.length,
      itemBuilder: (_, i) => _row(profiles[i]),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    EaColor.fore.withValues(alpha: .25),
                    EaColor.fore.withValues(alpha: .05),
                  ],
                ),
              ),
              child: const Icon(Icons.tune, size: 42, color: EaColor.fore),
            ),
            const SizedBox(height: 24),
            Text(
              "No profiles yet",
              style: EaText.primary.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Create profiles aligned with your mood.",
              textAlign: TextAlign.center,
              style: EaText.secondaryTranslucent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(Profile p) {
    final highlighted = _highlightedProfileName == p.name;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Stack(
        children: [
          if (highlighted)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _profileApplyPulse,
                  builder: (context, child) {
                    final t = _profileApplyPulse.value;
                    final fadeStart = 0.72;
                    final opacity = t < fadeStart
                        ? 1.0
                        : (1 - ((t - fadeStart) / (1 - fadeStart))).clamp(0.0, 1.0);
                    return CustomPaint(
                      painter: _OrbitBorderPainter(
                        progress: t,
                        opacity: opacity,
                      ),
                    );
                  },
                ),
              ),
            ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: EaColor.back,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: highlighted ? Colors.transparent : EaColor.border),
            ),
            child: Row(
              children: [
                Icon(p.icon, color: EaColor.fore, size: 26),

                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: EaText.primary),
                      Text(
                        "${p.actions.isNotEmpty ? p.actions.length : "No"} ${p.actions.length > 1 ? "actions" : "action"}",
                        style: EaText.secondary,
                      ),
                    ],
                  ),
                ),

                IconButton(
                  onPressed: () => _applyProfile(p),
                  icon: const Icon(Icons.play_arrow, color: EaColor.fore),
                ),

                IconButton(
                  onPressed: () => _openEditor(profile: p),
                  icon: const Icon(Icons.edit, size: 15, color: EaColor.fore),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrbitBorderPainter extends CustomPainter {
  final double progress;
  final double opacity;

  const _OrbitBorderPainter({required this.progress, this.opacity = 1});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(.8),
      const Radius.circular(20),
    );

    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = EaColor.fore.withValues(alpha: .24 * opacity);
    canvas.drawRRect(rrect, base);

    final metric = (Path()..addRRect(rrect)).computeMetrics().first;
    final length = metric.length;
    final segment = length * .24;
    final head = progress * length;
    final tail = head - segment;

    final active = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = EaColor.fore.withValues(alpha: opacity);

    if (tail >= 0) {
      canvas.drawPath(metric.extractPath(tail, head), active);
    } else {
      canvas.drawPath(metric.extractPath(length + tail, length), active);
      canvas.drawPath(metric.extractPath(0, head), active);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitBorderPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.opacity != opacity;
  }
}

class _ProfileEditor extends StatefulWidget {
  final List<DeviceInfo> devices;
  final Profile? profile;
  final Function(Profile) onSaved;
  final VoidCallback? onDelete;

  const _ProfileEditor({
    required this.devices,
    this.profile,
    required this.onSaved,
    this.onDelete,
  });

  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  static const double _capRowGap = 12;

  late TextEditingController nameController;
  late IconData selectedIcon;

  final List<DeviceAction> actions = [];

  final icons = [
    Icons.home,
    Icons.work,
    Icons.bed,
    Icons.ac_unit,
    Icons.gamepad,
    Icons.wine_bar,
    Icons.movie,
    Icons.music_note,
    Icons.local_cafe,
    Icons.nightlight_round,
    Icons.spa,
    Icons.security,
  ];

  double _snapStep(double value, double step) {
    if (step <= 0) return value;
    return (value / step).round() * step;
  }

  int _divisions(double min, double max, double step) {
    if (step <= 0) return 1;
    final raw = ((max - min) / step).round();
    return raw.clamp(1, 400);
  }

  String _capitalizeWords(String text) {
    return text
        .split(RegExp(r'[\s_\-]+'))
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  @override
  void initState() {
    super.initState();

    nameController = TextEditingController(text: widget.profile?.name ?? "");

    selectedIcon = widget.profile?.icon ?? Icons.home;

    if (widget.profile != null) {
      actions.addAll(widget.profile!.actions);
    }
  }

  void _addAction(DeviceInfo d) {
    if (actions.any((a) => a.deviceId == d.uuid)) return;

    final state = Bridge.getState(d.uuid);

    actions.add(
      DeviceAction(
        deviceId: d.uuid,
        power: d.capabilities.contains(CoreCapability.CORE_CAP_POWER)
            ? state.power
            : null,
        brightness: d.capabilities.contains(CoreCapability.CORE_CAP_BRIGHTNESS)
            ? state.brightness
            : null,
        temperature:
            d.capabilities.contains(CoreCapability.CORE_CAP_TEMPERATURE)
            ? state.temperature
            : null,
        temperatureFridge:
            d.capabilities.contains(CoreCapability.CORE_CAP_TEMPERATURE_FRIDGE)
            ? state.temperatureFridge
            : null,
        temperatureFreezer:
            d.capabilities.contains(CoreCapability.CORE_CAP_TEMPERATURE_FREEZER)
            ? state.temperatureFreezer
            : null,
        color: d.capabilities.contains(CoreCapability.CORE_CAP_COLOR)
            ? state.color
            : null,
        colorTemperature:
            d.capabilities.contains(CoreCapability.CORE_CAP_COLOR_TEMPERATURE)
            ? state.colorTemperature
            : null,
        time: d.capabilities.contains(CoreCapability.CORE_CAP_TIMESTAMP)
            ? state.timestamp
            : null,
        lock: d.capabilities.contains(CoreCapability.CORE_CAP_LOCK)
            ? state.lock
            : null,
        mode: d.capabilities.contains(CoreCapability.CORE_CAP_MODE)
            ? state.mode
            : null,
        position: d.capabilities.contains(CoreCapability.CORE_CAP_POSITION)
            ? state.position
            : null,
      ),
    );

    setState(() {});
  }

  void _removeAction(DeviceAction a) {
    actions.remove(a);
    setState(() {});
  }

  void _save() {
    final name = nameController.text.trim();

    if (name.isEmpty) return;

    widget.onSaved(Profile(name: name, actions: actions, icon: selectedIcon));
  }

  Future<void> _confirmDeleteProfile() async {
    if (widget.profile == null || widget.onDelete == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: EaColor.back,
          title: Text('Delete profile?', style: EaText.primary),
          content: Text(
            'This will permanently remove "${widget.profile!.name}".',
            style: EaText.secondary,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: EaText.secondary),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Delete',
                style: EaText.secondary.copyWith(color: Colors.redAccent),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      widget.onDelete?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: EaColor.back,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            tickMarkShape: SliderTickMarkShape.noTickMark,
            showValueIndicator: ShowValueIndicator.never,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _title(),

                const SizedBox(height: 18),

                _iconPicker(),

                const SizedBox(height: 20),

                _nameField(),

                const SizedBox(height: 18),

                _actions(),

                const SizedBox(height: 12),

                _devicePicker(),

                const SizedBox(height: 19),

                _footerButtons(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _title() {
    return Text(
      widget.profile == null ? "New Profile" : "Edit Profile",
      style: EaText.primary.copyWith(fontWeight: FontWeight.w600),
    );
  }

  Widget _nameField() {
    return TextField(
      controller: nameController,
      style: EaText.secondary,
      decoration: InputDecoration(
        hintText: "e.g Focus Mode, Movie Time, Relax Moment",
        hintStyle: EaText.secondaryBack,

        labelText: "Profile name",
        labelStyle: EaText.secondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: EaColor.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: EaColor.fore),
        ),
      ),
    );
  }

  Widget _iconPicker() {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: icons.map((icon) {
          final selected = icon == selectedIcon;

          return GestureDetector(
            onTap: () => setState(() => selectedIcon = icon),

            child: Container(
              margin: const EdgeInsets.only(right: 10),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: selected
                    ? EaColor.fore.withValues(alpha: .25)
                    : EaColor.back,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? EaColor.fore : EaColor.border,
                ),
              ),
              child: Icon(
                icon,
                color: selected ? EaColor.fore : EaColor.textSecondary,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _actions() {
    return widget.devices.isEmpty
        ? Text("No devices yet", style: EaText.secondaryTranslucent)
        : Column(children: actions.map(_actionCard).toList());
  }

  Widget _actionCard(DeviceAction a) {
    final d = widget.devices.firstWhere((e) => e.uuid == a.deviceId);

    final hasPower = d.capabilities.contains(CoreCapability.CORE_CAP_POWER);
    final hasBrightness = d.capabilities.contains(
      CoreCapability.CORE_CAP_BRIGHTNESS,
    );
    final hasColor = d.capabilities.contains(CoreCapability.CORE_CAP_COLOR);
    final hasTemperature = d.capabilities.contains(
      CoreCapability.CORE_CAP_TEMPERATURE,
    );
    final hasTemperatureFridge = d.capabilities.contains(
      CoreCapability.CORE_CAP_TEMPERATURE_FRIDGE,
    );
    final hasTemperatureFreezer = d.capabilities.contains(
      CoreCapability.CORE_CAP_TEMPERATURE_FREEZER,
    );
    final hasTime = d.capabilities.contains(CoreCapability.CORE_CAP_TIMESTAMP);
    final hasColorTemperature = d.capabilities.contains(
      CoreCapability.CORE_CAP_COLOR_TEMPERATURE,
    );
    final hasLock = d.capabilities.contains(CoreCapability.CORE_CAP_LOCK);
    final hasMode = d.capabilities.contains(CoreCapability.CORE_CAP_MODE);
    final hasPosition = d.capabilities.contains(
      CoreCapability.CORE_CAP_POSITION,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EaColor.back,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EaColor.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(d.name, style: EaText.primary),

              const Spacer(),

              IconButton(
                onPressed: () => _removeAction(a),
                icon: const Icon(
                  Icons.close,
                  size: 18,
                  color: EaColor.textSecondary,
                ),
              ),
            ],
          ),

          if (hasPower) _powerRow(a),

          if (hasBrightness) _brightnessRow(a, d),

          if (hasColor) _colorRow(a),

          if (hasTemperature) _temperatureRow(a, d),

          if (hasTemperatureFridge) _temperatureFridgeRow(a, d),

          if (hasTemperatureFreezer) _temperatureFreezerRow(a, d),

          if (hasTime) _timeRow(a),

          if (hasColorTemperature) _colorTemperatureRow(a, d),

          if (hasLock) _lockRow(a),

          if (hasMode) _modeRow(a, d),

          if (hasPosition) _positionRow(a),

        ],
      ),
    );
  }

  Widget _powerRow(DeviceAction a) {
    return Row(
      children: [
        const Icon(Icons.power_settings_new, size: 18, color: EaColor.fore),

        const SizedBox(width: 8),

        Text("Power", style: EaText.secondary),

        const Spacer(),

        Switch(
          activeThumbColor: EaColor.fore,
          inactiveTrackColor: EaColor.back,

          value: a.power ?? false,
          onChanged: (v) {
            setState(() => a.power = v);
          },
        ),
      ],
    );
  }

  Widget _brightnessRow(DeviceAction a, DeviceInfo d) {
    final min = Bridge.constraintMin(d.uuid, 'brightness', 0.0);
    final max = Bridge.constraintMax(d.uuid, 'brightness', 100.0);
    final step = Bridge.constraintStep(d.uuid, 'brightness', 1.0);
    final current = (a.brightness ?? min.toInt()).clamp(
      min.toInt(),
      max.toInt(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: _capRowGap),

        Row(
          children: [
            const Icon(Icons.tungsten, size: 18, color: EaColor.fore),
            const SizedBox(width: 8),
            Text("Brightness", style: EaText.secondary),

            const Spacer(),

            Text(
              "$current",
              style: EaText.secondary.copyWith(color: EaColor.fore),
            ),
            SizedBox(width: 10),
          ],
        ),

        Slider(
          min: min,
          max: max,
          divisions: _divisions(min, max, step),
          value: current.toDouble(),
          activeColor: EaColor.fore,
          inactiveColor: EaColor.secondaryBack,
          onChanged: (v) {
            final snapped = _snapStep(v, step).clamp(min, max).round();
            setState(() => a.brightness = snapped);
          },
        ),
      ],
    );
  }

  Widget _colorRow(DeviceAction a) {
    final colorValue = a.color ?? 0xFFFFFFFF;
    Color current = Color(0xFF000000 | colorValue);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: _capRowGap),

        Row(
          children: [
            const Icon(Icons.palette, size: 18, color: EaColor.fore),
            const SizedBox(width: 8),
            Text("Color", style: EaText.secondary),

            const Spacer(),

            GestureDetector(
              onTap: () {
                Color selected = current;

                showModalBottomSheet(
                  context: context,
                  backgroundColor: EaColor.background,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  builder: (_) {
                    return StatefulBuilder(
                      builder: (context, setModalState) {
                        return Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  color: selected,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
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
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: EaColor.fore,
                                  foregroundColor: EaColor.background,
                                ),

                                onPressed: () {
                                  final rgb = selected.toARGB32() & 0x00FFFFFF;
                                  setState(() => a.color = rgb);
                                  Navigator.pop(context);
                                },

                                child: const Text("Apply"),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                );
              },

              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: current,
                  shape: BoxShape.circle,
                  border: Border.all(color: EaColor.fore, width: 2),
                ),
              ),
            ),
            SizedBox(width: 10),
          ],
        ),
      ],
    );
  }

  Widget _temperatureRow(DeviceAction a, DeviceInfo d) {
    final min = Bridge.constraintMin(d.uuid, 'temperature', 16.0);
    final max = Bridge.constraintMax(d.uuid, 'temperature', 30.0);
    final step = Bridge.constraintStep(d.uuid, 'temperature', 0.5);
    final current = (a.temperature ?? min).clamp(min, max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: _capRowGap),

        Row(
          children: [
            const Icon(Icons.thermostat, size: 18, color: EaColor.fore),
            const SizedBox(width: 8),
            Text("Temperature", style: EaText.secondary),

            const Spacer(),

            Text(
              "${current.toStringAsFixed(1)} °C",
              style: EaText.secondary.copyWith(color: EaColor.fore),
            ),
            SizedBox(width: 10),
          ],
        ),

        Slider(
          min: min,
          max: max,
          divisions: _divisions(min, max, step),
          value: current,
          activeColor: EaColor.fore,
          inactiveColor: EaColor.secondaryBack,
          onChanged: (v) {
            final snapped = _snapStep(v, step).clamp(min, max);
            setState(() => a.temperature = snapped);
          },
        ),
      ],
    );
  }

  Widget _temperatureFridgeRow(DeviceAction a, DeviceInfo d) {
    final min = Bridge.constraintMin(d.uuid, 'temperature_fridge', 1.0);
    final max = Bridge.constraintMax(d.uuid, 'temperature_fridge', 8.0);
    final step = Bridge.constraintStep(d.uuid, 'temperature_fridge', 0.5);
    final current = (a.temperatureFridge ?? min).clamp(min, max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: _capRowGap),

        Row(
          children: [
            const Icon(Icons.kitchen_outlined, size: 18, color: EaColor.fore),
            const SizedBox(width: 8),
            Text("Fridge", style: EaText.secondary),

            const Spacer(),

            Text(
              "${current.toStringAsFixed(1)} °C",
              style: EaText.secondary.copyWith(color: EaColor.fore),
            ),
            SizedBox(width: 10),
          ],
        ),

        Slider(
          min: min,
          max: max,
          divisions: _divisions(min, max, step),
          value: current,
          activeColor: EaColor.fore,
          inactiveColor: EaColor.secondaryBack,
          onChanged: (v) {
            final snapped = _snapStep(v, step).clamp(min, max);
            setState(() => a.temperatureFridge = snapped);
          },
        ),
      ],
    );
  }

  Widget _temperatureFreezerRow(DeviceAction a, DeviceInfo d) {
    final min = Bridge.constraintMin(d.uuid, 'temperature_freezer', -24.0);
    final max = Bridge.constraintMax(d.uuid, 'temperature_freezer', -14.0);
    final step = Bridge.constraintStep(d.uuid, 'temperature_freezer', 0.5);
    final current = (a.temperatureFreezer ?? -18.0).clamp(min, max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: _capRowGap),

        Row(
          children: [
            const Icon(Icons.ac_unit, size: 18, color: EaColor.fore),
            const SizedBox(width: 8),
            Text("Freezer", style: EaText.secondary),

            const Spacer(),

            Text(
              "${current.toStringAsFixed(1)} °C",
              style: EaText.secondary.copyWith(color: EaColor.fore),
            ),
            SizedBox(width: 10),
          ],
        ),

        Slider(
          min: min,
          max: max,
          divisions: _divisions(min, max, step),
          value: current,
          activeColor: EaColor.fore,
          inactiveColor: EaColor.secondaryBack,
          onChanged: (v) {
            final snapped = _snapStep(v, step).clamp(min, max);
            setState(() => a.temperatureFreezer = snapped);
          },
        ),
      ],
    );
  }

  Widget _colorTemperatureRow(DeviceAction a, DeviceInfo d) {
    final min = Bridge.constraintMin(d.uuid, 'colorTemperature', 1500.0);
    final max = Bridge.constraintMax(d.uuid, 'colorTemperature', 9000.0);
    final current =
        ((a.colorTemperature ?? min.toInt()) <= 0
                ? min.toInt()
                : (a.colorTemperature ?? min.toInt()))
            .clamp(min.toInt(), max.toInt());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: _capRowGap),

        Row(
          children: [
            const Icon(Icons.tonality, size: 18, color: EaColor.fore),
            const SizedBox(width: 8),
            Text("Color temp", style: EaText.secondary),

            const Spacer(),

            Text(
              "$current K",
              style: EaText.secondary.copyWith(color: EaColor.fore),
            ),
            SizedBox(width: 10),
          ],
        ),

        Slider(
          min: min,
          max: max,
          divisions: _divisions(min, max, 100),
          value: current.toDouble(),
          activeColor: EaColor.fore,
          inactiveColor: EaColor.secondaryBack,
          onChanged: (v) {
            setState(
              () => a.colorTemperature = v.round().clamp(
                min.toInt(),
                max.toInt(),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _lockRow(DeviceAction a) {
    return Row(
      children: [
        const Icon(Icons.lock_outline, size: 18, color: EaColor.fore),

        const SizedBox(width: 8),

        Text("Lock", style: EaText.secondary),

        const Spacer(),

        Switch(
          activeThumbColor: EaColor.fore,
          inactiveTrackColor: EaColor.back,
          value: a.lock ?? false,
          onChanged: (v) => setState(() => a.lock = v),
        ),
      ],
    );
  }

  Widget _modeRow(DeviceAction a, DeviceInfo d) {
    final count = Bridge.modeCount(d.uuid);
    final min = 0.0;
    final max = (count - 1).toDouble();
    final current = (a.mode ?? 0).clamp(0, count - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: _capRowGap),

        Row(
          children: [
            const Icon(Icons.tune, size: 18, color: EaColor.fore),
            const SizedBox(width: 8),
            Text("Mode", style: EaText.secondary),

            const Spacer(),

            Text(
              _capitalizeWords(Bridge.modeName(d.uuid, current)),
              style: EaText.secondary.copyWith(color: EaColor.fore),
            ),
            SizedBox(width: 10),
          ],
        ),

        Slider(
          min: min,
          max: max,
          divisions: (count - 1).clamp(1, 20),
          value: current.toDouble(),
          activeColor: EaColor.fore,
          inactiveColor: EaColor.secondaryBack,
          onChanged: (v) {
            setState(() => a.mode = v.round().clamp(0, count - 1));
          },
        ),
      ],
    );
  }

  Widget _positionRow(DeviceAction a) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: _capRowGap),

        Row(
          children: [
            const Icon(Icons.straighten, size: 18, color: EaColor.fore),
            const SizedBox(width: 8),
            Text("Position", style: EaText.secondary),

            const Spacer(),

            Text(
              "${(a.position ?? 0).round()} %",
              style: EaText.secondary.copyWith(color: EaColor.fore),
            ),
            SizedBox(width: 10),
          ],
        ),

        Slider(
          min: 0,
          max: 100,
          divisions: 100,
          value: (a.position ?? 0).clamp(0, 100),
          activeColor: EaColor.fore,
          inactiveColor: EaColor.secondaryBack,
          onChanged: (v) {
            setState(() => a.position = v);
          },
        ),
      ],
    );
  }

  Widget _timeRow(DeviceAction a) {
    TimeOfDay? toTime(int? m) {
      if (m == null || m < 0) return null;

      final h = m ~/ 60;
      final min = m % 60;

      return TimeOfDay(hour: h, minute: min);
    }

    int toMinutes(TimeOfDay t) {
      return t.hour * 60 + t.minute;
    }

    final time = toTime(a.time ?? -1);

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
                                color: EaColor.fore, // borda ativa (adeus roxo)
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
                    setState(() => a.time = minutes);
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _devicePicker() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: widget.devices.map((d) {
        final used = actions.any((a) => a.deviceId == d.uuid);

        return OutlinedButton.icon(
          onPressed: used ? null : () => _addAction(d),

          icon: const Icon(Icons.add, size: 16),

          label: Text(d.name),

          style: OutlinedButton.styleFrom(
            foregroundColor: used ? EaColor.textSecondary : EaColor.fore,

            side: BorderSide(color: used ? EaColor.border : EaColor.fore),

            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _footerButtons() {
    if (widget.profile == null) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: EaColor.fore,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: Text("Save Profile", style: EaText.primaryBack),
        ),
      );
    }

    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: _confirmDeleteProfile,
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('Delete'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.redAccent,
            side: const BorderSide(color: Colors.redAccent),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: EaColor.fore,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: Text("Save Profile", style: EaText.primaryBack),
          ),
        ),
      ],
    );
  }
}

class RgbColorWheel extends StatefulWidget {
  final Color color;
  final ValueChanged<Color> onChanged;
  final double size;

  const RgbColorWheel({
    super.key,
    required this.color,
    required this.onChanged,
    this.size = 220,
  });

  @override
  State<RgbColorWheel> createState() => _RgbColorWheelState();
}

class _RgbColorWheelState extends State<RgbColorWheel> {
  late double hue;
  late double saturation;
  late double value;

  @override
  void initState() {
    super.initState();
    final hsv = HSVColor.fromColor(widget.color);
    hue = hsv.hue;
    saturation = hsv.saturation;
    value = hsv.value;
  }

  void _update(Offset pos) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final dx = pos.dx - center.dx;
    final dy = pos.dy - center.dy;

    final dist = sqrt(dx * dx + dy * dy);
    final radius = widget.size / 2;

    if (dist > radius) return;

    hue = (atan2(dy, dx) * 180 / pi + 360) % 360;

    saturation = (dist / radius).clamp(0.0, 1.0);

    value = 1;

    widget.onChanged(HSVColor.fromAHSV(1, hue, saturation, value).toColor());
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanDown: (d) => _update(d.localPosition),
      onPanUpdate: (d) => _update(d.localPosition),
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _HsvWheelPainter(),
      ),
    );
  }
}

class _HsvWheelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    final center = Offset(radius, radius);
    final rect = Rect.fromCircle(center: center, radius: radius);

    final paint = Paint()..style = PaintingStyle.fill;

    final shader = SweepGradient(
      colors: [
        for (var h = 0; h <= 360; h += 60)
          HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor(),
      ],
    ).createShader(rect);

    paint.shader = shader;
    canvas.drawCircle(center, radius, paint);

    final overlay = RadialGradient(
      colors: [Colors.white, Colors.transparent],
    ).createShader(rect);

    canvas.drawCircle(center, radius, Paint()..shader = overlay);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
