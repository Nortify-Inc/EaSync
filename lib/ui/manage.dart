/*!
 * @file manage.dart
 * @brief Management screen for device creation, search, and removal.
 * @param device Optional device used during edit operations.
 * @return Listing widgets, forms, and management actions.
 * @author Erick Radmann
 */

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'handler.dart';

class DeviceTemplate {
  final String category;
  final String brand;
  final String model;
  final String protocol;
  final List<String> capabilities;
  final Map<String, dynamic> payloads;
  final Map<String, dynamic> constrains;

  DeviceTemplate({
    required this.category,
    required this.brand,
    required this.model,
    required this.protocol,
    required this.capabilities,
    required this.payloads,
    required this.constrains,
  });

  factory DeviceTemplate.fromJson(String category, Map<String, dynamic> json) {
    return DeviceTemplate(
      category: category,
      brand: json["brand"],
      model: json["model"],
      protocol: (json["protocol"] ?? "mock").toString(),
      capabilities: List<String>.from(json["capabilities"]),
      payloads: json["payloads"],
      constrains: json["constrains"],
    );
  }
}

/* ============================================================
   TEMPLATE REPOSITORY
============================================================ */

class TemplateRepository {
  static Future<List<DeviceTemplate>> loadCategory(String category) async {
    final raw = await rootBundle.loadString("assets/$category.json");
    final decoded = jsonDecode(raw);

    final list = decoded[category] as List;

    return list.map((e) => DeviceTemplate.fromJson(category, e)).toList();
  }
}

/* ============================================================
   MANAGE PAGE
============================================================ */

class Manage extends StatefulWidget {
  const Manage({super.key});

  @override
  State<Manage> createState() => _ManageState();
}

class _ManageState extends State<Manage> {
  List<DeviceInfo> devices = [];
  List<DeviceInfo> filteredDevices = [];
  bool loading = true;
  late final TextEditingController deviceSearchController;
  StreamSubscription<CoreEventData>? _eventSub;

  @override
  void initState() {
    super.initState();
    deviceSearchController = TextEditingController();
    deviceSearchController.addListener(_filterDevices);
    _eventSub = Bridge.onEvents.listen((event) {
      if (event.type == CoreEventType.CORE_EVENT_DEVICE_ADDED ||
          event.type == CoreEventType.CORE_EVENT_DEVICE_REMOVED) {
        _loadDevices();
      }
    });
    _loadDevices();
  }

  @override
  void dispose() {
    deviceSearchController.dispose();
    _eventSub?.cancel();
    super.dispose();
  }

  void _loadDevices() {
    setState(() => loading = true);

    try {
      final list = Bridge.listDevices();

      setState(() {
        devices = list;
        filteredDevices = list;
        loading = false;
      });
    } catch (_) {
      setState(() => loading = false);
    }
  }

  void _filterDevices() {
    final query = deviceSearchController.text.toLowerCase();

    setState(() {
      if (query.isEmpty) {
        filteredDevices = devices;
        return;
      }

      filteredDevices = devices.where((d) {
        final text = "${d.name} ${d.uuid} ${d.brand} ${d.model}".toLowerCase();
        return text.contains(query);
      }).toList();
    });
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

  void _openDeviceDetails(DeviceInfo device) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: EaColor.back,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(device.name, style: EaText.primary)),
                  IconButton(
                    onPressed: () => _confirmRemoveDevice(device),
                    icon: const Icon(Icons.delete_outline),
                    color: Colors.redAccent,
                    tooltip: 'Remove device',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'UUID',
                style: EaText.secondary.copyWith(
                  color: EaColor.fore,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                device.uuid,
                style: EaText.secondary.copyWith(
                  color: EaColor.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Protocol',
                style: EaText.secondary.copyWith(
                  color: EaColor.fore,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _protocolLabel(device.protocol),
                style: EaText.secondary.copyWith(
                  color: EaColor.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Capabilities',
                style: EaText.secondary.copyWith(color: EaColor.fore),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: device.capabilities
                    .map((c) => _chip(_capLabel(c)))
                    .toList(),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmRemoveDevice(DeviceInfo device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: EaColor.back,
          title: Text('Remove device', style: EaText.primary),
          content: Text(
            'Do you want to remove "${device.name}"?',
            style: EaText.secondary.copyWith(color: EaColor.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: EaText.secondary),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'Remove',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      Bridge.removeDevice(device.uuid);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Device removed')));
      }
      _loadDevices();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
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
          heroTag: "manageFab",
          backgroundColor: EaColor.fore,
          onPressed: () => _openEditor(),
          icon: const Icon(Icons.add, color: Colors.black),
          label: Text("Add device", style: EaText.primaryBack),
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

    if (devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_circle_outline, size: 36, color: EaColor.fore),
            const SizedBox(height: 8),
            Text("Add your first device", style: EaText.primary),
            const SizedBox(height: 4),
            Text(
              "Use the button below to create a mock device",
              style: EaText.secondaryTranslucent,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            controller: deviceSearchController,
            cursorColor: EaColor.fore,
            style: EaText.secondary.copyWith(color: EaColor.textSecondary),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, color: EaColor.fore),
              hintText: "Search devices...",
              hintStyle: EaText.secondary,
              filled: true,
              fillColor: EaColor.back,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: EaColor.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: EaColor.fore),
              ),
            ),
          ),
        ),

        Expanded(
          child: filteredDevices.isEmpty
              ? const Center(child: Text("No matching devices"))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  itemCount: filteredDevices.length,
                  itemBuilder: (_, i) => _row(filteredDevices[i]),
                ),
        ),
      ],
    );
  }

  Widget _row(DeviceInfo d) {
    return GestureDetector(
      onTap: () => _openDeviceDetails(d),
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
            const Icon(Icons.devices, color: EaColor.fore),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.name,
                    style: EaText.secondary.copyWith(
                      fontSize: 16,
                      color: EaColor.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (d.brand.trim().isNotEmpty) _chip(d.brand),
                      if (d.model.trim().isNotEmpty) _chip(d.model),
                      ...d.capabilities.map((c) => _chip(_capLabel(c))),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _protocolLabel(int protocol) {
  switch (protocol) {
    case CoreProtocol.CORE_PROTOCOL_MQTT:
      return 'MQTT';
    case CoreProtocol.CORE_PROTOCOL_WIFI:
      return 'Wi-Fi';
    case CoreProtocol.CORE_PROTOCOL_ZIGBEE:
      return 'Zigbee';
    case CoreProtocol.CORE_PROTOCOL_BLE:
      return 'BLE';
    case CoreProtocol.CORE_PROTOCOL_MOCK:
    default:
      return 'Mock';
  }
}

Widget _chip(String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: EaColor.back,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: EaColor.border),
    ),
    child: Text(text, style: EaText.secondary.copyWith(fontSize: 11)),
  );
}

String _capLabel(int cap) {
  switch (cap) {
    case CoreCapability.CORE_CAP_POWER:
      return "Power";
    case CoreCapability.CORE_CAP_BRIGHTNESS:
      return "Brightness";
    case CoreCapability.CORE_CAP_COLOR:
      return "Color";
    case CoreCapability.CORE_CAP_TEMPERATURE:
      return "Temperature";
    case CoreCapability.CORE_CAP_TEMPERATURE_FRIDGE:
      return "Fridge";
    case CoreCapability.CORE_CAP_TEMPERATURE_FREEZER:
      return "Freezer";
    case CoreCapability.CORE_CAP_TIMESTAMP:
      return "Schedule";
    case CoreCapability.CORE_CAP_COLOR_TEMPERATURE:
      return "Color Temp";
    case CoreCapability.CORE_CAP_LOCK:
      return "Lock";
    case CoreCapability.CORE_CAP_MODE:
      return "Mode";
    case CoreCapability.CORE_CAP_POSITION:
      return "Position";
    default:
      return "Unk";
  }
}

class _DeviceEditor extends StatefulWidget {
  final DeviceInfo? device;
  final VoidCallback onSaved;

  const _DeviceEditor({this.device, required this.onSaved});

  @override
  State<_DeviceEditor> createState() => _DeviceEditorState();
}

class _DeviceEditorState extends State<_DeviceEditor> {
  late TextEditingController nameController;
  late TextEditingController searchController;
  DeviceTemplate? selectedTemplate;

  List<DeviceTemplate> templates = [];
  List<DeviceTemplate> filteredTemplates = [];

  final categories = [
    "acs",
    "lamps",
    "fridges",
    "locks",
    "curtains",
    "heated_floors",
    "mocks",
  ];

  @override
  void initState() {
    super.initState();

    nameController = TextEditingController();
    searchController = TextEditingController();

    if (widget.device != null) {
      nameController.text = widget.device!.name;
    }

    searchController.addListener(_filterTemplates);

    _loadTemplates();
  }

  @override
  void dispose() {
    nameController.dispose();
    searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    final loaded = await Future.wait(
      categories.map((c) => TemplateRepository.loadCategory(c)),
    );

    templates = [for (var list in loaded) ...list];
    filteredTemplates = List.from(templates);
    selectedTemplate = null;

    setState(() {});
  }

  void _filterTemplates() {
    final query = searchController.text.toLowerCase();

    setState(() {
      filteredTemplates = templates.where((t) {
        final text = "${t.brand} ${t.model} ${t.category}".toLowerCase();
        final caps = t.capabilities.join(" ").toLowerCase();
        return text.contains(query) || caps.contains(query);
      }).toList();
    });
  }

  void _save() {
    if (selectedTemplate == null) {
      _showError("Select a model");
      return;
    }

    final name = nameController.text.trim().isEmpty
        ? "${selectedTemplate!.brand} ${selectedTemplate!.model}"
        : nameController.text.trim();

    final uuid = _generateUuid();

    try {
      final rawModes = selectedTemplate!.constrains["mode"];
      final modeLabels = rawModes is List
          ? rawModes.map((e) => e.toString()).toList()
          : null;

      Bridge.registerDevice(
        uuid: uuid,
        name: name,
        protocol: _mapProtocol(selectedTemplate!.protocol),
        capabilities: selectedTemplate!.capabilities
            .map(_mapCapability)
            .toList(),
        modeLabels: modeLabels,
        constraints: selectedTemplate!.constrains,
      );

      widget.onSaved();
    } catch (e) {
      _showError(e.toString());
    }
  }

  String _prettyCategory(String raw) {
    const names = {
      'acs': 'Air Conditioners',
      'lamps': 'Lamps',
      'fridges': 'Refrigerators',
      'locks': 'Smart Locks',
      'curtains': 'Curtains',
      'heated_floors': 'Heated Floors',
      'mocks': 'Mock Devices',
    };
    return names[raw] ??
        raw
            .split('_')
            .map(
              (w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}',
            )
            .join(' ');
  }

  int _mapCapability(String cap) {
    switch (cap) {
      case "power":
        return CoreCapability.CORE_CAP_POWER;
      case "brightness":
        return CoreCapability.CORE_CAP_BRIGHTNESS;
      case "color":
        return CoreCapability.CORE_CAP_COLOR;
      case "temperature":
        return CoreCapability.CORE_CAP_TEMPERATURE;
      case "temperature_fridge":
        return CoreCapability.CORE_CAP_TEMPERATURE_FRIDGE;
      case "temperature_freezer":
        return CoreCapability.CORE_CAP_TEMPERATURE_FREEZER;
      case "time":
        return CoreCapability.CORE_CAP_TIMESTAMP;
      case "colorTemperature":
        return CoreCapability.CORE_CAP_COLOR_TEMPERATURE;
      case "lock":
        return CoreCapability.CORE_CAP_LOCK;
      case "mode":
        return CoreCapability.CORE_CAP_MODE;
      case "position":
        return CoreCapability.CORE_CAP_POSITION;
      default:
        throw Exception("Unsupported capability: $cap");
    }
  }

  int _mapProtocol(String protocol) {
    switch (protocol.toLowerCase()) {
      case 'mqtt':
        return CoreProtocol.CORE_PROTOCOL_MQTT;
      case 'wifi':
        return CoreProtocol.CORE_PROTOCOL_WIFI;
      case 'zigbee':
        return CoreProtocol.CORE_PROTOCOL_ZIGBEE;
      case 'ble':
        return CoreProtocol.CORE_PROTOCOL_BLE;
      case 'mock':
      default:
        return CoreProtocol.CORE_PROTOCOL_MOCK;
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _generateUuid() {
    final r = Random();
    return List.generate(
      4,
      (_) => r.nextInt(0xFFFF).toRadixString(16).padLeft(4, '0'),
    ).join("-");
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.of(context).size.height * .8;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: EaColor.back,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SizedBox(
          height: maxHeight,
          child: Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("New Device", style: EaText.primary),
              const SizedBox(height: 16),

              TextField(
                controller: searchController,
                cursorColor: EaColor.fore,
                style: EaText.secondary.copyWith(color: EaColor.textSecondary),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, color: EaColor.border),
                  hintText: "Search brand, model or capability",
                  filled: true,
                  fillColor: Colors.white,
                  hintStyle: EaText.secondary.copyWith(color: Colors.black45),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: EaColor.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: EaColor.fore),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              Expanded(
                child: filteredTemplates.isEmpty
                    ? Center(
                        child: Text(
                          "No templates found",
                          style: EaText.secondaryTranslucent,
                        ),
                      )
                    : ListView.separated(
                        itemCount: filteredTemplates.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final t = filteredTemplates[i];
                          final selected = t == selectedTemplate;

                          return InkWell(
                            onTap: () {
                              setState(() => selectedTemplate = t);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: selected
                                    ? EaColor.fore.withAlpha(25)
                                    : EaColor.back,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: selected
                                      ? EaColor.fore
                                      : EaColor.border,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.memory,
                                    size: 20,
                                    color: EaColor.fore,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "${t.brand} ${t.model}",
                                          style: EaText.primary,
                                        ),
                                        Text(
                                          _prettyCategory(t.category),
                                          style: EaText.secondary,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          "Protocol: ${t.protocol.toUpperCase()}",
                                          style: EaText.secondaryTranslucent,
                                        ),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: t.capabilities
                                              .map((c) => _chip(c))
                                              .toList(),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),

              const SizedBox(height: 12),

              TextField(
                controller: nameController,
                cursorColor: EaColor.fore,
                style: EaText.secondary.copyWith(color: EaColor.textSecondary),
                decoration: InputDecoration(
                  labelText: "Device Name",
                  labelStyle: EaText.secondary,
                  filled: true,
                  fillColor: EaColor.back,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: EaColor.fore),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: EaColor.fore),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: EaColor.fore, width: 2),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EaColor.fore,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _save,
                  child: Text(
                    "Save",
                    style: EaText.primaryBack.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
