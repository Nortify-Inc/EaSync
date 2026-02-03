import '../models/capability.dart';
import '../models/device.dart';

class CapabilityResolver {
  static Map<CapabilityType, Capability> resolve(DeviceType type) {
    switch (type) {
      case DeviceType.light:
        return {
          CapabilityType.power:
              Capability(type: CapabilityType.power, value: 0, min: 1, max: 10),
          CapabilityType.brightness:
              Capability(type: CapabilityType.brightness, value: 50, min: 1, max: 10),
        };

      case DeviceType.airConditioner:
        return {
          CapabilityType.power:
              Capability(type: CapabilityType.power, value: 0, min: 1, max: 10),
          CapabilityType.temperature:
              Capability(type: CapabilityType.temperature, value: 22, min: 16, max: 30),
        };

      case DeviceType.fridge:
        return {
          CapabilityType.temperature:
              Capability(type: CapabilityType.temperature, value: 4, min: 1, max: 10),
        };

      case DeviceType.curtain:
        return {
          CapabilityType.position:
              Capability(type: CapabilityType.position, value: 0, min: 1, max: 10),
        };

      case DeviceType.lock:
        return {
          CapabilityType.lock:
              Capability(type: CapabilityType.lock, value: 1, min: 1, max: 10),
        };
    }
  }
}
