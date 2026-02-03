import 'package:flutter/material.dart';
import '../models/device.dart';
import '../models/capability.dart';
import '../services/deviceRepository.dart';

enum DeviceFilter {
  all,
  on,
  off,
  byType,
}

class DeviceStore extends ChangeNotifier {
  final DeviceRepository repository;

  DeviceFilter filter = DeviceFilter.all;
  DeviceType? filterType;

  DeviceStore(this.repository);

  List<Device> get devices {
    var list = repository.devices;

    switch (filter) {
      case DeviceFilter.on:
        list = list.where((d) => d.power).toList();
        break;
      case DeviceFilter.off:
        list = list.where((d) => !d.power).toList();
        break;
      case DeviceFilter.byType:
        if (filterType != null) {
          list = list.where((d) => d.type == filterType).toList();
        }
        break;
      case DeviceFilter.all:
        break;
    }

    return list;
  }

  Future<void> load() async {
    await repository.loadAll();
    notifyListeners();
  }

  void addDevice({
    required String name,
    required DeviceType type,
    required String model,
    required String address,
  }) {
    repository.createDevice(
      name: name,
      type: type,
      model: model,
      address: address,
    );
    notifyListeners();
  }

  void removeDevice(String deviceId) {
    repository.removeDevice(deviceId);
    notifyListeners();
  }

  void togglePower(String deviceId, bool value) {
    repository.togglePower(deviceId, value);
    notifyListeners();
  }

  void setCapability(
    String deviceId,
    CapabilityType type,
    int value,
  ) {
    repository.setCapability(deviceId, type, value, 1, 10);
    notifyListeners();
  }

  void setFilter(DeviceFilter newFilter, {DeviceType? type}) {
    filter = newFilter;
    filterType = type;
    notifyListeners();
  }

  void updateDevice(Device device) {
    final list = repository.devices;
    final index = list.indexWhere((d) => d.id == device.id);
    if (index == -1) return;

    list[index] = device;
    repository.persistAll();
    notifyListeners();
  }

  void reorderDevices(int oldIndex, int newIndex) {
    final list = repository.devices;
    if (newIndex > oldIndex) newIndex--;

    final device = list.removeAt(oldIndex);
    list.insert(newIndex, device);

    repository.persistAll();
    notifyListeners();
  }
}
