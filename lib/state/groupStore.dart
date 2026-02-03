import 'package:flutter/material.dart';
import '../models/groups.dart';
import '../models/capability.dart';
import '../services/deviceRepository.dart';

class GroupStore extends ChangeNotifier {
  final DeviceRepository repository;

  GroupStore(this.repository);

  List<DeviceGroup> get groups => repository.groups;

  void createGroup(String name) {
    repository.createGroup(name);
    notifyListeners();
  }

  void deleteGroup(String groupId) {
    repository.removeGroup(groupId);
    notifyListeners();
  }

  void updateGroup(DeviceGroup group) {
    final list = repository.groups;
    final index = list.indexWhere((g) => g.id == group.id);
    if (index == -1) return;

    list[index] = group;
    repository.persistAll();
    notifyListeners();
  }

  void addDeviceToGroup(String deviceId, String groupId) {
    repository.addDeviceToGroup(groupId, deviceId);
    notifyListeners();
  }

  void removeDeviceFromGroup(String deviceId, String groupId) {
    repository.removeDeviceFromGroup(groupId, deviceId);
    notifyListeners();
  }

  void toggleGlobalControl(String groupId, bool enabled) {
    final group = groups.firstWhere((g) => g.id == groupId);

    updateGroup(
      group.copyWith(globalControl: enabled),
    );
  }

  void setGroupCapability(
    String groupId,
    CapabilityType type,
    String value,
  ) {
    final group = groups.firstWhere((g) => g.id == groupId);

    final updatedCaps = Map<CapabilityType, int>.from(group.globalCapabilities);
    updatedCaps[type] = value as int;

    updateGroup(
      group.copyWith(globalCapabilities: updatedCaps),
    );
  }

  void clearGroupCapability(String groupId, CapabilityType type) {
    final group = groups.firstWhere((g) => g.id == groupId);

    final updatedCaps = Map<CapabilityType, int>.from(group.globalCapabilities);
    updatedCaps.remove(type);

    updateGroup(
      group.copyWith(globalCapabilities: updatedCaps),
    );
  }
}
