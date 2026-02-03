import 'capability.dart';
import 'package:uuid/uuid.dart';

enum DeviceType {
  light,
  airConditioner,
  fridge,
  curtain,
  lock,
}

final _uuid = Uuid();

class Device {
  final String id;
  final String name;
  bool power;
  final DeviceType type;
  final String model;
  final String address;
  String? groupId;
  bool followGroup;
  Map<CapabilityType, Capability> capabilities;

  Device({
    String? id,
    required this.name,
    this.power = false,
    required this.type,
    required this.model,
    required this.address,
    this.groupId,
    this.followGroup = false,
    required this.capabilities,
  }) : id = id ?? _uuid.v4();

  Device copyWith({
    bool? power,
    Map<CapabilityType, Capability>? capabilities,
    String? groupId,
    bool? followGroup}){
      return Device(
        id: id,
        name: name,
        type: type,
        model: model,
        address: address,
        power: power ?? this.power,
        capabilities: capabilities ?? this.capabilities,
        groupId: groupId ?? this.groupId,
        followGroup: followGroup ?? this.followGroup,
      );
  }

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id'].toString(),
      name: json['name'] ?? '',
      power: json['power'] ?? false,
      type: DeviceType.values[json['type'] ?? 0],
      model: json['model'] ?? '',
      address: json['address'] ?? '',
      groupId: json['groupId']?.toString(),
      followGroup: json['followGroup'] ?? false,
      capabilities: (json['capabilities'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(
              CapabilityType.values[int.parse(key)],
              Capability.fromJson(value),
            ),
          ) ??
          {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'power': power,
      'type': type.index,
      'model': model,
      'address': address,
      'groupId': groupId,
      'followGroup': followGroup,
      'capabilities': capabilities.map(
        (key, value) => MapEntry(key.index.toString(), value.toJson()),
      ),
    };
  }

  dynamic getCapability(CapabilityType type) => capabilities[type]?.value;

  void setCapability(CapabilityType type, int value, double min, double max) {
    if (capabilities.containsKey(type)) {
      capabilities[type]!.value = value;
    } else {
      capabilities[type] = Capability(type: type, value: value, min: min, max: max);
    }
  }
}