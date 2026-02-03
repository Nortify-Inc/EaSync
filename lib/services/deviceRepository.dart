import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/device.dart';
import '../models/groups.dart';
import '../models/mode.dart';
import '../models/capability.dart';
import 'capabilityResolver.dart';
import '../main.dart';

final _uuid = Uuid();

class DeviceRepository {
  final List<Device> _devices = [];
  final List<DeviceGroup> _groups = [];
  final List<Mode> _modes = [];

  DeviceRepository(persistenceService);

  List<Device> get devices => List.unmodifiable(_devices);
  List<DeviceGroup> get groups => List.unmodifiable(_groups);
  List<Mode> get modes => List.unmodifiable(_modes);

  Device createDevice({
    required String name,
    required DeviceType type,
    required String model,
    required String address,
  }) {
    final device = Device(
      name: name,
      type: type,
      model: model,
      address: address,
      capabilities: CapabilityResolver.resolve(type),
    );

    _devices.add(device);
    persistAll();
    return device;
  }

  void removeDevice(String deviceId) {
    _devices.removeWhere((d) => d.id == deviceId);
    persistAll();
  }

  void togglePower(String deviceId, bool value) {
    final device = _devices.firstWhere((d) => d.id == deviceId);
    device.power = value;
    persistAll();
  }

  void setCapability(String deviceId, CapabilityType type, int value, double min, double max) {
    final device = _devices.firstWhere((d) => d.id == deviceId);
    device.setCapability(type, value, min, max);
    persistAll();
  }

  DeviceGroup createGroup(String name) {
    final group = DeviceGroup(
      id: _uuid.v4(),
      name: name,
      deviceIds: [],
      globalControl: true,
    );
    _groups.add(group);
    persistAll();
    return group;
  }

  void removeGroup(String groupId) {
    _groups.removeWhere((g) => g.id == groupId);

    for (final device in _devices) {
      if (device.groupId == groupId) {
        device.groupId = null;
        device.followGroup = false;
      }
    }
    persistAll();
  }

  void addDeviceToGroup(String groupId, String deviceId) {
    final group = _groups.firstWhere((g) => g.id == groupId);

    if (!group.deviceIds.contains(deviceId)) {
      group.deviceIds.add(deviceId);
      persistAll();
    }
  }

  void removeDeviceFromGroup(String groupId, String deviceId) {
    final group = _groups.firstWhere((g) => g.id == groupId);
    group.deviceIds.remove(deviceId);
    persistAll();
  }

  void setGroupCapability(String groupId, CapabilityType type, int value, double min, double max) {
    final group = _groups.firstWhere((g) => g.id == groupId);
    group.setGlobalCapability(type, value);

    for (final device in _devices) {
      if (device.groupId == groupId && device.followGroup) {
        device.setCapability(type, value, min, max);
      }
    }

    persistAll();
  }

  Mode createMode(String name, IconData icon) {
    final actions = _devices.map((device) {
      return ModeAction(
        deviceId: device.id,
        power: device.power,
        capabilities: device.capabilities.map(
          (k, v) => MapEntry(k, v.value),
        ),
      );
    }).toList();

    final mode = Mode(
      id: _uuid.v4(),
      name: name,
      icon: icon,
      actions: actions,
    );

    _modes.add(mode);
    persistAll();
    return mode;
  }

  void applyMode(String modeId) {
    final mode = _modes.firstWhere((m) => m.id == modeId);

    for (final action in mode.actions) {
      final device = _devices.firstWhere((d) => d.id == action.deviceId);
      device.power = action.power;

      action.capabilities.forEach((type, value) {
        device.setCapability(type, value, 1, 10);
      });
    }

    persistAll();
  }

  Future<void> loadAll() async {
    final devicesData = persistenceService.loadDevices<Device>(Device.fromJson);
    final groupsData = persistenceService.loadGroups<DeviceGroup>(DeviceGroup.fromJson);
    final modesData = persistenceService.loadModes<Mode>(Mode.fromJson);

    _devices
      ..clear()
      ..addAll(devicesData);

    _groups
      ..clear()
      ..addAll(groupsData);

    _modes
      ..clear()
      ..addAll(modesData);
  }

  Future<void> persistAll() async {
    await persistenceService.saveDevices(_devices.map((d) => d.toJson()).toList());
    await persistenceService.saveGroups(_groups.map((g) => g.toJson()).toList());
    await persistenceService.saveModes(_modes.map((m) => m.toJson()).toList());
  }
}
