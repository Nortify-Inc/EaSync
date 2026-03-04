/*!
 * @file bridge_test.dart
 * @brief Quick test script for FFI bridge operations.
 * @param No external parameters.
 * @return `void`.
 * @author Erick Radmann
 */

import 'bridge.dart';

Future<void> main() async {
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
        CoreCapability.CORE_CAP_TIMESTAMP,
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

    // Subscribe to events
    Bridge.onEvents.listen((e) {
      print(
        '[EVENT] type=${e.type} uuid=${e.uuid} power=${e.state.power} br=${e.state.brightness} color=${e.state.color} temp=${e.state.temperature} ts=${e.state.timestamp} mode=${e.state.mode} pos=${e.state.position}',
      );
    });

    // Kick a first simulate to start flow
    Bridge.simulateOnce();

    // Also trigger a few manual commands
    Bridge.setPower('lamp-001', true);
    Bridge.setBrightness('lamp-001', 80);
    Bridge.setColor('lamp-001', 0xFF000000);

    Bridge.setPower('ac-001', true);
    Bridge.setTemperature('ac-001', 22.5);
    Bridge.setTime('ac-001', DateTime.now().second + 3600);

    final discovered = await Bridge.discoverDevices();
    print('Discovered candidates: ${discovered.length}');
    if (discovered.isNotEmpty) {
      final first = discovered.first;
      final ok = await Bridge.verifyDiscoveredDevice(first);
      print(
        'First candidate verification: ${first.name} ${first.host}:${first.port} => ${ok ? 'ok' : 'failed'}',
      );
    }

    Bridge.refreshDeviceConnection('lamp-001');
    print('Health lamp-001: ${Bridge.healthLabel('lamp-001')}');

    // Keep process alive to observe events
    Future.delayed(const Duration(seconds: 10), () {
      print('Stopping after demo window');
      Bridge.destroy();
    });
  } catch (e) {
    print('Error: $e');
    Bridge.destroy();
  }
}
