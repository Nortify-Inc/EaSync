import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PersistenceService {
  static const _autoSaveKey = 'autoSaveEnabled';
  static const _animationsKey = 'animationsEnabled';

  static const _modesKey = 'modes';
  static const _groupsKey = 'groups';
  static const _devicesKey = 'devices';

  bool _autoSaveEnabled = true;
  bool _animationsEnabled = true;

  bool get autoSaveEnabled => _autoSaveEnabled;
  bool get animationsEnabled => _animationsEnabled;

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();

    _autoSaveEnabled = _prefs.getBool(_autoSaveKey) ?? true;
    _animationsEnabled = _prefs.getBool(_animationsKey) ?? true;
  }

  Future<void> setAutoSave(bool value) async {
    _autoSaveEnabled = value;
    await _prefs.setBool(_autoSaveKey, value);
  }

  Future<void> setAnimations(bool value) async {
    _animationsEnabled = value;
    await _prefs.setBool(_animationsKey, value);
  }

  Future<void> saveModes(List<dynamic> modes) async {
    final data = jsonEncode(modes.map((m) => m.toJson()).toList());
    await _prefs.setString(_modesKey, data);
  }

  Future<void> saveGroups(List<dynamic> groups) async {
    final data = jsonEncode(groups.map((g) => g.toJson()).toList());
    await _prefs.setString(_groupsKey, data);
  }

  Future<void> saveDevices(List<dynamic> devices) async {
    final data = jsonEncode(devices.map((d) => d.toJson()).toList());
    await _prefs.setString(_devicesKey, data);
  }

  List<T> loadModes<T>(T Function(Map<String, dynamic>) fromJson) {
    final raw = _prefs.getString(_modesKey);
    if (raw == null) return [];

    final list = jsonDecode(raw) as List;
    return list.map((e) => fromJson(e)).toList();
  }

  List<T> loadGroups<T>(T Function(Map<String, dynamic>) fromJson) {
    final raw = _prefs.getString(_groupsKey);
    if (raw == null) return [];

    final list = jsonDecode(raw) as List;
    return list.map((e) => fromJson(e)).toList();
  }

  List<T> loadDevices<T>(T Function(Map<String, dynamic>) fromJson) {
  final raw = _prefs.getString(_devicesKey);
  if (raw == null) return [];

  final list = jsonDecode(raw) as List;
  return list.map((e) => fromJson(e as Map<String, dynamic>)).toList();
}
}
