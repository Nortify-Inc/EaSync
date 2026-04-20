/*!
 * @file profiles.dart
 * @brief Profiles screen to apply multiple batched actions to devices.
 * @param profile Selected profile for editing or execution.
 * @return Widgets and actions for profile creation and execution.
 * @author Erick Radmann
 */

import 'dart:ui';

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
  final List<Profile> profiles = [];
  List<DeviceInfo> devices = [];
  EaPlanTier _planTier = EaPlanTier.free;
  StreamSubscription<CoreEventData>? _eventSub;
  late final AnimationController _profileApplyPulse;
  Timer? _profileApplyPulseTimer;
  String? _highlightedProfileName;

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
    _loadPlanTier();
    _eventSub = Bridge.onEvents.listen((event) {
      if (event.type == CoreEventType.CORE_EVENT_DEVICE_ADDED ||
          event.type == CoreEventType.CORE_EVENT_DEVICE_REMOVED) {
        _loadDevices();
      }
    });
  }

  Future<void> _loadPlanTier() async {
    final next = await EaPlanService.instance.readTier();
    if (!mounted) return;
    setState(() => _planTier = next);
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
            style: EaText.secondary.copyWith(
              color: EaColor.textPrimary,
              fontSize: 12,
            ),
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

  void _openEditor({Profile? profile}) {
    final creating = profile == null;
    if (creating &&
        !EaPlanService.instance.canCreateProfile(_planTier, profiles.length)) {
      _showTopErrorSnack(
        EaI18n.t(context, 'Profile limit reached for your plan.'),
      );
      _openPlanOptions();
      return;
    }

    _loadDevices();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return _ProfileEditor(
          devices: devices,
          profile: profile,
          allowTemperatureControl: EaPlanService.instance.allowsTemperature(
            _planTier,
          ),
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

  void _openPlanOptions() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SubscriptionPage()),
    ).then((_) => _loadPlanTier());
  }

  void _applyProfile(Profile profile) {
    try {
      if (profile.actions.isEmpty) {
        _showBottomSnack('Profile ${profile.name} has no actions.');
        return;
      }

      final allowsTemperature = EaPlanService.instance.allowsTemperature(
        _planTier,
      );

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

        if (allowsTemperature &&
            a.temperature != null &&
            has(CoreCapability.CORE_CAP_TEMPERATURE)) {
          Bridge.setTemperature(a.deviceId, a.temperature!);
        }

        if (allowsTemperature &&
            a.temperatureFridge != null &&
            has(CoreCapability.CORE_CAP_TEMPERATURE_FRIDGE)) {
          Bridge.setTemperatureFridge(a.deviceId, a.temperatureFridge!);
        }

        if (allowsTemperature &&
            a.temperatureFreezer != null &&
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

      if (!allowsTemperature) {
        _showBottomSnack(
          EaI18n.t(context, 'Temperature control is available from Plus plan.'),
        );
      }

      Bridge.observeProfileApplied(
        profileName: profile.name,
        actionCount: profile.actions.length,
        deviceIds: profile.actions.map((a) => a.deviceId).toSet().toList(),
      );

      _showBottomSnack('Profile ${profile.name} was applied.');
      _pulseAppliedProfile(profile);
    } catch (e) {
      _showTopErrorSnack(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return SafeArea(
      child: EaFadeSlideIn(
        begin: const Offset(0, 0.015),
        duration: EaAppSettings.instance.animationsEnabled
            ? EaMotion.normal
            : Duration.zero,
        child: Column(
          children: [
            Expanded(child: _body()),
            _fab(),
          ],
        ),
      ),
    );
  }

  Widget _fab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        child: EaBlurFadeIn(
          beginBlur: 4,
          duration: const Duration(milliseconds: 220),
          child: EaGradientButtonFrame(
            borderRadius: BorderRadius.circular(12),
            child: ElevatedButton.icon(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add),
              label: Text(
                EaI18n.t(context, 'New profile'),
                style: EaText.secondary,
              ),
              style: EaButtonStyle.gradientFilled(
                context: context,
                borderRadius: BorderRadius.circular(12),
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 12,
                ),
              ),
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
      child: EaFadeSlideIn(
        duration: const Duration(milliseconds: 1000),
        child: EaBounce(
          onTap: () => _openEditor(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  // Outer Glow
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFFB155FF).withValues(alpha: 0.2),
                          Colors.transparent,
                            ],
                      ),
                    )
                  ),
                  // The Orb
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [EaColor.fore, Color(0xFFB155FF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFB155FF).withValues(alpha: 0.4),
                          blurRadius: 30,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(Icons.tune_rounded, size: 36, color: EaAdaptiveColor.surface(context)),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                EaI18n.t(context, 'No profiles yet'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: EaAdaptiveColor.bodyText(context),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 60),
                child: Text(
                  EaI18n.t(context, 'Create profiles aligned with your mood.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: EaAdaptiveColor.secondaryText(context),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
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
                        : (1 - ((t - fadeStart) / (1 - fadeStart))).clamp(
                            0.0,
                            1.0,
                          );
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
              border: Border.all(
                color: highlighted ? Colors.transparent : EaColor.border,
              ),
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
                        p.actions.isEmpty
                            ? EaI18n.t(context, 'No actions')
                            : EaI18n.t(
                                context,
                                p.actions.length == 1
                                    ? '{count} action'
                                    : '{count} actions',
                                {'count': '${p.actions.length}'},
                              ),
                        style: EaText.secondary,
                      ),
                    ],
                  ),
                ),

                EaBounce(
                  child: IconButton(
                    onPressed: () => _applyProfile(p),
                    icon: const Icon(Icons.play_arrow, color: EaColor.fore),
                  ),
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
  final bool allowTemperatureControl;
  final Function(Profile) onSaved;
  final VoidCallback? onDelete;

  const _ProfileEditor({
    required this.devices,
    this.profile,
    required this.allowTemperatureControl,
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
          title: Text(
            EaI18n.t(context, 'Delete profile?'),
            style: EaText.primary,
          ),
          content: Text(
            EaI18n.t(context, 'This will permanently remove "{name}".', {
              'name': widget.profile!.name,
            }),
            style: EaText.secondary,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(EaI18n.t(context, 'Cancel'), style: EaText.secondary),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                EaI18n.t(context, 'Delete'),
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
          color: EaAdaptiveColor.surface(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: EaAdaptiveColor.border(context)),
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
      widget.profile == null
          ? EaI18n.t(context, 'New Profile')
          : EaI18n.t(context, 'Edit Profile'),
      style: EaText.primary.copyWith(
        fontWeight: FontWeight.w600,
        color: EaAdaptiveColor.bodyText(context),
      ),
    );
  }

  Widget _nameField() {
    return TextField(
      controller: nameController,
      style: EaText.secondary.copyWith(
        color: EaAdaptiveColor.bodyText(context),
      ),
      decoration: InputDecoration(
        hintText: EaI18n.t(context, 'e.g Focus Mode, Movie Time, Relax Moment'),
        hintStyle: EaText.secondary.copyWith(
          color: EaAdaptiveColor.secondaryText(context),
        ),

        labelText: EaI18n.t(context, 'Profile name'),
        labelStyle: EaText.secondary.copyWith(
          color: EaAdaptiveColor.secondaryText(context),
        ),
        filled: true,
        fillColor: EaAdaptiveColor.field(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: EaAdaptiveColor.border(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: EaAdaptiveColor.border(context)),
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
                    : EaAdaptiveColor.field(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? EaColor.fore
                      : EaAdaptiveColor.border(context),
                ),
              ),
              child: Icon(
                icon,
                color: selected
                    ? EaColor.fore
                    : EaAdaptiveColor.secondaryText(context),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _actions() {
    return widget.devices.isEmpty
        ? Text(
            EaI18n.t(context, 'No devices yet'),
            style: EaText.secondary.copyWith(
              color: EaAdaptiveColor.secondaryText(context),
            ),
          )
        : Column(children: actions.map(_actionCard).toList());
  }

  Widget _actionCard(DeviceAction a) {
    final d = widget.devices.firstWhere((e) => e.uuid == a.deviceId);

    final hasPower = d.capabilities.contains(CoreCapability.CORE_CAP_POWER);
    final hasBrightness = d.capabilities.contains(
      CoreCapability.CORE_CAP_BRIGHTNESS,
    );
    final hasColor = d.capabilities.contains(CoreCapability.CORE_CAP_COLOR);
    final hasTemperature =
        widget.allowTemperatureControl &&
        d.capabilities.contains(CoreCapability.CORE_CAP_TEMPERATURE);
    final hasTemperatureFridge =
        widget.allowTemperatureControl &&
        d.capabilities.contains(CoreCapability.CORE_CAP_TEMPERATURE_FRIDGE);
    final hasTemperatureFreezer =
        widget.allowTemperatureControl &&
        d.capabilities.contains(CoreCapability.CORE_CAP_TEMPERATURE_FREEZER);
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

        Text(EaI18n.t(context, 'Power'), style: EaText.secondary),

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
            Text(EaI18n.t(context, 'Brightness'), style: EaText.secondary),

            const Spacer(),

            Text(
              "$current%",
              style: EaText.secondary.copyWith(color: EaColor.fore),
            ),
            const SizedBox(width: 10),
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
            Text(EaI18n.t(context, 'Color'), style: EaText.secondary),

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

                              EaGradientButtonFrame(
                                borderRadius: BorderRadius.circular(12),
                                child: ElevatedButton(
                                  style: EaButtonStyle.gradientFilled(
                                    context: context,
                                    borderRadius: BorderRadius.circular(12),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                      horizontal: 10,
                                    ),
                                  ),
                                  onPressed: () {
                                    final rgb =
                                        selected.toARGB32() & 0x00FFFFFF;
                                    setState(() => a.color = rgb);
                                    Navigator.pop(context);
                                  },
                                  child: Text(EaI18n.t(context, 'Apply')),
                                ),
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
            Text(EaI18n.t(context, 'Temperature'), style: EaText.secondary),

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
            Text(EaI18n.t(context, 'Fridge'), style: EaText.secondary),

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
            Text(EaI18n.t(context, 'Freezer'), style: EaText.secondary),

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
            Text(EaI18n.t(context, 'Color Temp'), style: EaText.secondary),

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

        Text(EaI18n.t(context, 'Lock'), style: EaText.secondary),

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
            Text(EaI18n.t(context, 'Mode'), style: EaText.secondary),

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
            Text(EaI18n.t(context, 'Position'), style: EaText.secondary),

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
            Text(EaI18n.t(context, 'Schedule'), style: EaText.secondary),
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
                    : EaI18n.t(context, 'Not set'),
                style: EaText.secondary,
              ),

              const Spacer(),

              IconButton(
                icon: const Icon(Icons.edit, size: 18, color: EaColor.fore),
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,

                    helpText: EaI18n.t(context, 'Select time'),

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
        child: EaGradientButtonFrame(
          borderRadius: BorderRadius.circular(18),
          child: ElevatedButton(
            onPressed: _save,
            style: EaButtonStyle.gradientFilled(
              context: context,
              borderRadius: BorderRadius.circular(18),
              padding: EdgeInsetsGeometry.symmetric(horizontal: 10),
            ),
            child: Text(
              EaI18n.t(context, 'Save Profile'),
              style: EaText.secondary,
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: _confirmDeleteProfile,
          icon: const Icon(Icons.delete_outline, size: 18),
          label: Text(EaI18n.t(context, 'Delete')),
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
          child: EaGradientButtonFrame(
            borderRadius: BorderRadius.circular(18),
            child: ElevatedButton(
              onPressed: _save,
              style: EaButtonStyle.gradientFilled(
                context: context,
                borderRadius: BorderRadius.circular(18),
                padding: EdgeInsetsGeometry.symmetric(horizontal: 10),
              ),
              child: Text(
                EaI18n.t(context, 'Save Profile'),
                style: EaText.secondary,
              ),
            ),
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
