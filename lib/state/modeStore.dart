import 'package:flutter/material.dart';
import '../models/mode.dart';
import '../services/deviceRepository.dart';

class ModeStore extends ChangeNotifier {
  final DeviceRepository repository;

  String? _activeModeId;

  ModeStore(this.repository);

  List<Mode> get modes => repository.modes;
  String? get activeModeId => _activeModeId;

  void createMode(String name, IconData icon) {
    repository.createMode(name, icon);
    notifyListeners();
  }

  void applyMode(String modeId) {
    _activeModeId = modeId;
    repository.applyMode(modeId);
    notifyListeners();
  }

  void clearMode() {
    _activeModeId = null;
    notifyListeners();
  }

  bool isModeActive(int modeId) {
    return _activeModeId == modeId;
  }
}
