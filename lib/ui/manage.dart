import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'handler.dart';

class DeviceTemplate {
  final String category;
  final String brand;
  final String model;
  final List<String> capabilities;
  final Map<String, dynamic> payloads;
  final Map<String, dynamic> constrains;

  DeviceTemplate({
    required this.category,
    required this.brand,
    required this.model,
    required this.capabilities,
    required this.payloads,
    required this.constrains,
  });

  factory DeviceTemplate.fromJson(
      String category, Map<String, dynamic> json) {
    return DeviceTemplate(
      category: category,
      brand: json["brand"],
      model: json["model"],
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
      return const Center(child: Text("Add your first device"));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      itemCount: devices.length,
      itemBuilder: (_, i) => _row(devices[i]),
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
            const Icon(Icons.devices, color: EaColor.fore),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.name, style: EaText.primary),
                  Text(d.uuid,
                      style: EaText.secondary.copyWith(fontSize: 11)),
                ],
              ),
            ),
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
  late TextEditingController searchController;

  String selectedCategory = "acs";
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
  ];

  @override
  void initState() {
    super.initState();

    nameController = TextEditingController();
    searchController = TextEditingController();

    searchController.addListener(_filterTemplates);

    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    templates = await TemplateRepository.loadCategory(selectedCategory);

    filteredTemplates = List.from(templates);
    selectedTemplate = null;

    setState(() {});
  }

  void _filterTemplates() {
    final query = searchController.text.toLowerCase();

    setState(() {
      filteredTemplates = templates.where((t) {
        final text = "${t.brand} ${t.model}".toLowerCase();
        return text.contains(query);
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
      Bridge.registerDevice(
        uuid: uuid,
        name: name,
        protocol: CoreProtocol.CORE_PROTOCOL_MOCK,
        capabilities: selectedTemplate!.capabilities
            .map(_mapCapability)
            .toList(),
      );

      widget.onSaved();
    } catch (e) {
      _showError(e.toString());
    }
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
      case "time":
        return CoreCapability.CORE_CAP_TIMESTAMP;
      default:
        return CoreCapability.CORE_CAP_POWER;
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
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

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: EaColor.back,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("New Device", style: EaText.primary),
            const SizedBox(height: 16),

            DropdownButtonFormField<String>(
              initialValue: selectedCategory,
              items: categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) async {
                selectedCategory = v!;
                await _loadTemplates();
              },
              decoration: const InputDecoration(labelText: "Category"),
            ),

            const SizedBox(height: 16),

            Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: EaColor.border),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14),
                  child: TextField(
                    controller: searchController,
                    style:
                        EaText.primary.copyWith(color: Colors.black),
                    decoration: InputDecoration(
                      hintText: "Search model...",
                      hintStyle:
                          TextStyle(color: EaColor.border),
                      border: InputBorder.none,
                      icon:
                          Icon(Icons.search, color: EaColor.border),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                if (filteredTemplates.isNotEmpty)
                  Container(
                    constraints:
                        const BoxConstraints(maxHeight: 220),
                    decoration: BoxDecoration(
                      color: EaColor.back,
                      borderRadius: BorderRadius.circular(18),
                      border:
                          Border.all(color: EaColor.border),
                    ),
                    child: ListView.builder(
                      itemCount: filteredTemplates.length,
                      itemBuilder: (_, i) {
                        final t = filteredTemplates[i];
                        final selected =
                            t == selectedTemplate;

                        return InkWell(
                          onTap: () {
                            setState(() {
                              selectedTemplate = t;
                              searchController.text =
                                  "${t.brand} ${t.model}";
                              filteredTemplates = [];
                            });
                          },
                          child: Container(
                            padding:
                                const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12),
                            decoration: BoxDecoration(
                              color: selected
                                  ? EaColor.fore.withAlpha(25)
                                  : Colors.transparent,
                              borderRadius:
                                  BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.memory,
                                    size: 18,
                                    color: EaColor.fore),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    "${t.brand} ${t.model}",
                                    style: EaText.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 16),

            TextField(
              controller: nameController,
              decoration:
                  const InputDecoration(labelText: "Device Name"),
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                child: const Text("Save"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}