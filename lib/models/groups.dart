import 'capability.dart';

class DeviceGroup {
  final String id;
  final String name;
  final List<String> deviceIds;
  bool globalControl;
  final Map<CapabilityType, int> globalCapabilities;
  
  DeviceGroup({
    required this.id,
    required this.name,
    required this.deviceIds,
    required this.globalControl,
    Map<CapabilityType, int>? globalCapabilities,
  }) : globalCapabilities = globalCapabilities ?? {};

  DeviceGroup copyWith({
    String? name,
    List<String>? deviceIds,
    bool? globalControl,
    Map<CapabilityType, int>? globalCapabilities,
  }) {
    return DeviceGroup(
      id: id,
      name: name ?? this.name,
      deviceIds: deviceIds ?? List<String>.from(this.deviceIds),
      globalControl: true,
      globalCapabilities:
          globalCapabilities ?? Map<CapabilityType, int>.from(this.globalCapabilities),
    );
  }

  DeviceGroup setGlobalCapability(CapabilityType type, int value) {
    final updated = Map<CapabilityType, int>.from(globalCapabilities);
    updated[type] = value;

    return copyWith(globalCapabilities: updated);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'deviceIds': deviceIds,
        'globalCapabilities':
            globalCapabilities.map((k, v) => MapEntry(k.name, v)),
      };

  factory DeviceGroup.fromJson(Map<String, dynamic> json) {
    return DeviceGroup(
      id: json['id'],
      name: json['name'],
      deviceIds: List<String>.from(json['deviceIds']),
      globalControl: json['globalControl'],
      globalCapabilities:
          (json['globalCapabilities'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(
          CapabilityType.values.firstWhere((e) => e.name == key),
          value as int,
        ),
      ),
    );
  }
}
