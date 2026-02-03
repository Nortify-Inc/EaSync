enum CapabilityType {
  power,
  brightness,
  temperature,
  humidity,
  lock,
  position,
}

class Capability {
  final CapabilityType type;
  final String unit;
  double min = 0.0;
  double max = 10.0;
  int value;

  Capability({
    required this.type,
    required this.value,
    required this.min,
    required this.max,
    this.unit = '',
  });

  Capability copyWith({
    CapabilityType? type,
    int? value,
    double? min,
    double? max,
    String? unit,
  }) {
    return Capability(
      type: type ?? this.type,
      value: value ?? this.value,
      min: min ?? this.min,
      max: max ?? this.max,
      unit: unit ?? this.unit,
    );
  }

  bool get isOn {
    if (type != CapabilityType.power) return false;
    return value == 1;
  }

  String get name {
    switch (type) {
      case CapabilityType.power:
        return 'Power';
      case CapabilityType.brightness:
        return 'Brightness';
      case CapabilityType.temperature:
        return 'Temperature';
      case CapabilityType.humidity:
        return 'Humidity';
      case CapabilityType.lock:
        return 'Lock';
      case CapabilityType.position:
        return 'Position';
    }
  }

  String get displayValue {
    switch (type) {
      case CapabilityType.power:
        return value == 1 ? 'On' : 'Off';

      case CapabilityType.lock:
        return value == 1 ? 'Locked' : 'Unlocked';

      case CapabilityType.brightness:
        return '$value%';

      case CapabilityType.temperature:
        return '$value$unit';

      case CapabilityType.humidity:
        return '$value%';

      case CapabilityType.position:
        return '$value%';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'value': value,
      'min': min,
      'max': max,
      'unit': unit,
    };
  }

  factory Capability.fromJson(Map<String, dynamic> json) {
    return Capability(
      type: CapabilityType.values.firstWhere(
        (e) => e.name == json['type'],
      ),
      value: json['value'],
      min: json['min'] ?? 0,
      max: json['max'] ?? 100,
      unit: json['unit'] ?? '',
    );
  }
}
