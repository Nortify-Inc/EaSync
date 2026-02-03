import 'package:flutter/material.dart';

import 'capability.dart';

class ModeAction {
  final String deviceId;
  final bool power;
  final Map<CapabilityType, int> capabilities;

  ModeAction({
    required this.deviceId,
    required this.power,
    required this.capabilities,
  });

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'power': power,
        'capabilities':
            capabilities.map((k, v) => MapEntry(k.name, v)),
      };

  factory ModeAction.fromJson(Map<String, dynamic> json) {
    return ModeAction(
      deviceId: json['deviceId'],
      power: json['power'],
      capabilities:
          (json['capabilities'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(
          CapabilityType.values.firstWhere((e) => e.name == key),
          value as int,
        ),
      ),
    );
  }
}

class Mode {
  final String id;
  final String name;
  final IconData icon;
  final List<ModeAction> actions;

  Mode({
    required this.id,
    required this.name,
    required this.icon,
    required this.actions,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'actions': actions.map((a) => a.toJson()).toList(),
      };

  factory Mode.fromJson(Map<String, dynamic> json) {
    return Mode(
      id: json['id'],
      name: json['name'],
      icon: json['icon'],
      actions: (json['actions'] as List)
          .map((e) => ModeAction.fromJson(e))
          .toList(),
    );
  }
}
