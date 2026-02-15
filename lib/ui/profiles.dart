import 'package:flutter/material.dart';
import 'handler.dart';

/* ============================================================
   MODELS
============================================================ */

class DeviceAction {
  final String deviceId;

  bool power;
  int brightness;

  DeviceAction({
    required this.deviceId,
    this.power = false,
    this.brightness = 100,
  });
}

class Profile {
  final String name;
  final List<DeviceAction> actions;
  final IconData icon;

  Profile({required this.name, required this.actions, required this.icon});
}

/* ============================================================
   PAGE
============================================================ */

class Profiles extends StatefulWidget {
  const Profiles({super.key});

  @override
  State<Profiles> createState() => _ProfilesState();
}

class _ProfilesState extends State<Profiles> {
  final List<Profile> profiles = [];

  List<DeviceInfo> devices = [];

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  void _loadDevices() {
    try {
      devices = Bridge.listDevices();
      setState(() {});
    } catch (_) {}
  }

  void _openEditor({Profile? profile}) {
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
        );
      },
    );
  }

  void _applyProfile(Profile profile) {
    try {
      for (final a in profile.actions) {
        Bridge.setPower(a.deviceId, a.power);

        if (a.brightness >= 0) {
          Bridge.setBrightness(a.deviceId, a.brightness);
        }
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Profile applied")));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Expanded(child: _body()),
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
        child: FloatingActionButton.extended(
          heroTag: "profilesFab",
          backgroundColor: EaColor.fore,
          onPressed: () => _openEditor(),
          icon: const Icon(Icons.add, color: Colors.black),
          label: const Text(
            "New profile",
            style: TextStyle(color: Colors.black),
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
              "Create profiles aligned with your mood",
              textAlign: TextAlign.center,
              style: EaText.secondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(Profile p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EaColor.back,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: EaColor.border),
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
                Text("${p.actions.length} actions", style: EaText.secondary),
              ],
            ),
          ),

          IconButton(
            onPressed: () => _applyProfile(p),
            icon: const Icon(Icons.play_arrow, color: EaColor.fore),
          ),

          IconButton(
            onPressed: () => _openEditor(profile: p),
            icon: const Icon(Icons.edit, color: EaColor.textSecondary),
          ),
        ],
      ),
    );
  }
}

/* ============================================================
   EDITOR
============================================================ */

class _ProfileEditor extends StatefulWidget {
  final List<DeviceInfo> devices;
  final Profile? profile;
  final Function(Profile) onSaved;

  const _ProfileEditor({
    required this.devices,
    this.profile,
    required this.onSaved,
  });

  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  late TextEditingController nameController;
  late IconData selectedIcon;

  final List<DeviceAction> actions = [];

  final icons = [
    Icons.home,
    Icons.work,
    Icons.bed,
    Icons.movie,
    Icons.music_note,
    Icons.local_cafe,
    Icons.nightlight_round,
    Icons.spa,
    Icons.security,
  ];

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

    actions.add(DeviceAction(deviceId: d.uuid));

    setState(() {});
  }

  void _removeAction(DeviceAction a) {
    actions.remove(a);
    setState(() {});
  }

  void _save() {
    final name = nameController.text.trim();

    if (name.isEmpty || actions.isEmpty) return;

    widget.onSaved(Profile(name: name, actions: actions, icon: selectedIcon));
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _title(),

              const SizedBox(height: 18),

              _iconPicker(),

              const SizedBox(height: 18),

              _nameField(),

              const SizedBox(height: 18),

              _actions(),

              const SizedBox(height: 12),

              _devicePicker(),

              const SizedBox(height: 22),

              _saveButton(),
            ],
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
      style: EaText.primary,
      decoration: InputDecoration(
        helperText: "e.g Concentration, Movie Time, Relax Time",
        labelText: "Profile name",
        labelStyle: EaText.secondary,
        enabledBorder: OutlineInputBorder(
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
    if (actions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text("No devices added yet", style: EaText.secondary),
      );
    }

    return Column(children: actions.map(_actionCard).toList());
  }

  Widget _actionCard(DeviceAction a) {
    final d = widget.devices.firstWhere((e) => e.uuid == a.deviceId);

    final hasPower = d.capabilities.contains(CoreCapability.CORE_CAP_POWER);

    final hasBrightness = d.capabilities.contains(
      CoreCapability.CORE_CAP_BRIGHTNESS,
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

          if (hasBrightness) _brightnessRow(a),
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
          value: a.power,
          onChanged: (v) {
            setState(() => a.power = v);
          },
        ),
      ],
    );
  }

  Widget _brightnessRow(DeviceAction a) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),

        Row(
          children: [
            const Icon(Icons.brightness_6, size: 18, color: EaColor.fore),
            const SizedBox(width: 8),
            Text("Brightness", style: EaText.secondary),
          ],
        ),

        Slider(
          min: 0,
          max: 100,
          divisions: 100,
          value: a.brightness.toDouble(),
          activeColor: EaColor.fore,
          inactiveColor: EaColor.fore.withValues(alpha: .25),
          onChanged: (v) {
            setState(() => a.brightness = v.round());
          },
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

  Widget _saveButton() {
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
}
