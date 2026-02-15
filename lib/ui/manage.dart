import 'dart:math';
import 'package:flutter/material.dart';

import 'handler.dart';

class Manage extends StatefulWidget {
  const Manage({super.key});

  @override
  State<Manage> createState() => _ManageState();
}

class _ManageState extends State<Manage> {
  List<DeviceInfo> devices = [];

  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  void _loadDevices() {
    setState(() => loading = true);

    try {
      final list = Bridge.listDevices();

      setState(() {
        devices = list;
        loading = false;
      });
    } catch (_) {
      setState(() => loading = false);
    }
  }

  void _openEditor({DeviceInfo? device}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return _DeviceEditor(
          device: device,
          onSaved: () {
            _loadDevices();
            Navigator.pop(context);
          },
        );
      },
    );
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
          heroTag: "manageFab",
          backgroundColor: EaColor.fore,
          onPressed: () => _openEditor(),
          icon: const Icon(Icons.add, color: Colors.black),
          label: const Text(
            "Add device",
            style: TextStyle(color: Colors.black),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: EaColor.fore),
      );
    }

    if (devices.isEmpty) return _emptyState();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      itemCount: devices.length,
      itemBuilder: (_, i) => _row(devices[i]),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    EaColor.fore.withValues(alpha: .25),
                    EaColor.fore.withValues(alpha: .08),
                  ],
                ),
              ),
              child: const Icon(
                Icons.devices_other,
                size: 40,
                color: EaColor.fore,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "No devices yet",
              style: EaText.primary.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: EaColor.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Add your first device to get started",
              textAlign: TextAlign.center,
              style: EaText.secondary.copyWith(color: EaColor.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(DeviceInfo d) {
    return GestureDetector(
      onTap: () => _openEditor(device: d),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: EaColor.back,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: EaColor.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: EaColor.fore.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.devices, color: EaColor.fore),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.name,
                    style: EaText.primary.copyWith(color: EaColor.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    d.uuid,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: EaText.secondary.copyWith(
                      fontSize: 11,
                      color: EaColor.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: EaColor.textSecondary),
          ],
        ),
      ),
    );
  }
}

/* ============================================================
   EDITOR
============================================================ */

class _DeviceEditor extends StatefulWidget {
  final DeviceInfo? device;
  final VoidCallback onSaved;

  const _DeviceEditor({this.device, required this.onSaved});

  @override
  State<_DeviceEditor> createState() => _DeviceEditorState();
}

class _DeviceEditorState extends State<_DeviceEditor> {
  late TextEditingController nameController;

  final Set<int> caps = {};

  @override
  void initState() {
    super.initState();

    nameController = TextEditingController(text: widget.device?.name ?? "");

    if (widget.device != null) {
      caps.addAll(widget.device!.capabilities);
    }
  }

  void _save() {
    final name = nameController.text.trim();

    if (name.isEmpty) {
      _showError("Name is required");
      return;
    }

    if (caps.isEmpty) {
      _showError("Select at least one capability");
      return;
    }

    final uuid = widget.device?.uuid ?? _generateUuid();

    try {
      Bridge.registerDevice(
        uuid: uuid,
        name: name,
        protocol: CoreProtocol.CORE_PROTOCOL_MOCK,
        capabilities: caps.toList(),
      );

      widget.onSaved();
    } catch (e) {
      _showError(e.toString());
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  String _generateUuid() {
    final r = Random();

    return List.generate(
      4,
      (_) => r.nextInt(0xFFFF).toRadixString(16).padLeft(4, '0'),
    ).join("-");
  }

  Widget _capChip(String label, int cap) {
    final active = caps.contains(cap);

    return GestureDetector(
      onTap: () {
        setState(() {
          active ? caps.remove(cap) : caps.add(cap);
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? EaColor.fore.withValues(alpha: .25) : EaColor.back,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? EaColor.fore : EaColor.border),
        ),
        child: Text(
          label,
          style: EaText.secondary.copyWith(
            color: active ? EaColor.fore : EaColor.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _caps() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _capChip("Power", CoreCapability.CORE_CAP_POWER),
        _capChip("Brightness", CoreCapability.CORE_CAP_BRIGHTNESS),
        _capChip("Color", CoreCapability.CORE_CAP_COLOR),
        _capChip("Temp", CoreCapability.CORE_CAP_TEMPERATURE),
        _capChip("Time", CoreCapability.CORE_CAP_TIMESTAMP),
      ],
    );
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 4,
              width: 44,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: EaColor.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),

            Text(
              widget.device == null ? "New Device" : "Edit Device",
              style: EaText.primary.copyWith(
                fontWeight: FontWeight.w600,
                color: EaColor.textPrimary,
              ),
            ),

            const SizedBox(height: 18),

            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: "Device name",
                labelStyle: const TextStyle(color: Colors.white70),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),

            const SizedBox(height: 18),

            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Capabilities",
                style: EaText.secondary.copyWith(
                  fontWeight: FontWeight.w600,
                  color: EaColor.textSecondary,
                ),
              ),
            ),

            const SizedBox(height: 8),

            _caps(),

            const SizedBox(height: 22),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: EaColor.fore,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: const Text("Save Device"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
