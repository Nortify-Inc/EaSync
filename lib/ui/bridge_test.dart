import 'bridge.dart';

void main() {
  Bridge.init();

  try {
    Bridge.registerDevice(
      uuid: 'lamp-001',
      name: 'Living Room Lamp',
      protocol: CoreProtocol.CORE_PROTOCOL_MOCK,
      capabilities: [
        CoreCapability.CORE_CAP_POWER,
        CoreCapability.CORE_CAP_BRIGHTNESS,
        CoreCapability.CORE_CAP_COLOR,
      ],
    );

    Bridge.registerDevice(
      uuid: 'ac-001',
      name: 'Bedroom AC',
      protocol: CoreProtocol.CORE_PROTOCOL_MOCK,
      capabilities: [
        CoreCapability.CORE_CAP_POWER,
        CoreCapability.CORE_CAP_TEMPERATURE,
      ],
    );

    final devices = Bridge.listDevices();

    print('Devices:');

    for (final d in devices) {
      print('---');
      print('UUID: ${d.uuid}');
      print('Name: ${d.name}');
      print('Protocol: ${d.protocol}');
      print('Caps: ${d.capabilities}');
    }

    Bridge.setPower('lamp-001', true);
    Bridge.setBrightness('lamp-001', 80);
    Bridge.setColor('lamp-001', 0xFFAA00);

    Bridge.setPower('ac-001', true);
    Bridge.setTemperature('ac-001', 22.5);

    final lampState = Bridge.getState('lamp-001');
    final acState = Bridge.getState('ac-001');

    print('\nLamp State:');
    print('Power: ${lampState.power}');
    print('Brightness: ${lampState.brightness}');
    print('Color: ${lampState.color}');
    print('Temp: ${lampState.temperature}');
    print('Timestamp: ${lampState.timestamp}');

    print('\nAC State:');
    print('Power: ${acState.power}');
    print('Brightness: ${acState.brightness}');
    print('Color: ${acState.color}');
    print('Temp: ${acState.temperature}');
    print('Timestamp: ${acState.timestamp}');
  } catch (e) {
    print('Error: $e');
  } finally {
    Bridge.destroy();
  }
}
