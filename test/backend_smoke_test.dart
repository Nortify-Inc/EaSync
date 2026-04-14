import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:easync/ui/utils/bridge.dart';

const _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);
const _sharedPreferencesChannel = MethodChannel(
  'plugins.flutter.io/shared_preferences',
);

class _FakeWifiDevice {
  _FakeWifiDevice({
    required this.port,
    required this.control,
    required this.isolate,
  });

  final int port;
  final SendPort control;
  final Isolate isolate;

  String get endpoint => '127.0.0.1:$port';

  static Future<_FakeWifiDevice> start() async {
    final receive = ReceivePort();
    final isolate = await Isolate.spawn(_fakeWifiIsolateMain, receive.sendPort);

    final first = await receive.first;
    if (first is! Map) {
      isolate.kill(priority: Isolate.immediate);
      throw Exception('Invalid fake device bootstrap payload');
    }

    final port = first['port'];
    final control = first['control'];
    if (port is! int || control is! SendPort) {
      isolate.kill(priority: Isolate.immediate);
      throw Exception('Invalid fake device bootstrap fields');
    }

    return _FakeWifiDevice(port: port, control: control, isolate: isolate);
  }

  Future<void> stop() async {
    control.send('stop');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    isolate.kill(priority: Isolate.immediate);
  }
}

class _FakeMideaLanDevice {
  _FakeMideaLanDevice({
    required this.host,
    required this.httpPort,
    required this.udpPorts,
    required this.control,
    required this.isolate,
  });

  final String host;
  final int httpPort;
  final List<int> udpPorts;
  final SendPort control;
  final Isolate isolate;

  String get endpoint => '$host:$httpPort';

  static Future<_FakeMideaLanDevice> start() async {
    final receive = ReceivePort();
    final isolate = await Isolate.spawn(
      _fakeMideaLanIsolateMain,
      receive.sendPort,
    );

    final first = await receive.first;
    if (first is! Map) {
      isolate.kill(priority: Isolate.immediate);
      throw Exception('Invalid fake Midea bootstrap payload');
    }

    final host = first['host'];
    final httpPort = first['httpPort'];
    final udpPortsRaw = first['udpPorts'];
    final control = first['control'];

    if (host is! String ||
        httpPort is! int ||
        udpPortsRaw is! List ||
        control is! SendPort) {
      isolate.kill(priority: Isolate.immediate);
      throw Exception('Invalid fake Midea bootstrap fields');
    }

    final udpPorts = udpPortsRaw.whereType<int>().toList(growable: false);
    if (udpPorts.isEmpty) {
      isolate.kill(priority: Isolate.immediate);
      throw Exception('Fake Midea UDP ports not available');
    }

    return _FakeMideaLanDevice(
      host: host,
      httpPort: httpPort,
      udpPorts: udpPorts,
      control: control,
      isolate: isolate,
    );
  }

  Future<Map<String, dynamic>> stats() async {
    final reply = ReceivePort();
    control.send({'cmd': 'stats', 'replyTo': reply.sendPort});
    final raw = await reply.first;
    reply.close();

    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map(
        (key, value) => MapEntry('$key', value),
      );
    }

    throw Exception('Invalid fake Midea stats response');
  }

  Future<bool> sendDiscoveryProbe() async {
    const probe = <int>[
      0x5a, 0x5a, 0x01, 0x11, 0x48, 0x00, 0x92, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x7f, 0x75, 0xbd, 0x6b, 0x3e, 0x4f, 0x8b, 0x76,
      0x2e, 0x84, 0x9c, 0x6e, 0x57, 0x8d, 0x65, 0x90,
      0x03, 0x6e, 0x9d, 0x43, 0x42, 0xa5, 0x0f, 0x1f,
      0x56, 0x9e, 0xb8, 0xec, 0x91, 0x8e, 0x92, 0xe5,
    ];

    final socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    socket.readEventsEnabled = true;
    socket.writeEventsEnabled = false;

    try {
      for (final port in udpPorts) {
        socket.send(probe, InternetAddress.loopbackIPv4, port);
      }

      final completer = Completer<bool>();
      late final StreamSubscription<RawSocketEvent> sub;

      sub = socket.listen((event) {
        if (event != RawSocketEvent.read) return;

        while (true) {
          final dg = socket.receive();
          if (dg == null) break;
          final data = dg.data;
          final looksMidea = data.length >= 2 && data[0] == 0x5a && data[1] == 0x5a;
          if (looksMidea && !completer.isCompleted) {
            completer.complete(true);
          }
        }
      });

      final ok = await completer.future
          .timeout(const Duration(milliseconds: 900), onTimeout: () => false);
      await sub.cancel();
      return ok;
    } finally {
      socket.close();
    }
  }

  Future<void> stop() async {
    control.send('stop');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    isolate.kill(priority: Isolate.immediate);
  }
}

@pragma('vm:entry-point')
Future<void> _fakeWifiIsolateMain(SendPort bootstrapPort) async {
  final control = ReceivePort();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

  var power = false;
  var running = true;

  control.listen((message) async {
    if (message == 'stop' && running) {
      running = false;
      await server.close(force: true);
      control.close();
    }
  });

  bootstrapPort.send({'port': server.port, 'control': control.sendPort});

  await for (final request in server) {
    final path = request.uri.path;
    final method = request.method.toUpperCase();

    final isProvisionPath = <String>{
      '/provision',
      '/wifi/provision',
      '/wifi',
      '/wifi_config',
      '/config/wifi',
      '/network',
      '/network/config',
    }.contains(path);

    if (method == 'GET' && (path == '/' || path == '/health')) {
      request.response.statusCode = 200;
      await request.response.close();
      continue;
    }

    if (method == 'GET' && (path == '/state' || path == '/api/state')) {
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'power': power,
          'temperature': 22.0,
          'mode': 1,
          'position': 0,
          'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        }),
      );
      await request.response.close();
      continue;
    }

    if ((method == 'POST' || method == 'PUT') && isProvisionPath) {
      await utf8.decoder.bind(request).join();
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"ok":true}');
      await request.response.close();
      continue;
    }

    if ((method == 'POST' || method == 'PUT') &&
        (path == '/power' || path == '/set/power')) {
      final body = await utf8.decoder.bind(request).join();
      final lowered = body.toLowerCase();
      power = lowered.contains('true') ||
          lowered.contains('"1"') ||
          lowered.contains(':1');
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"ok":true}');
      await request.response.close();
      continue;
    }

    request.response.statusCode = 404;
    await request.response.close();
  }
}

@pragma('vm:entry-point')
Future<void> _fakeMideaLanIsolateMain(SendPort bootstrapPort) async {
  final control = ReceivePort();
  final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

  final udpA = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  final udpB = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);

  var running = true;
  var power = false;
  var temperatureFridge = 4.0;
  var temperatureFreezer = -18.0;
  var udpProbeCount = 0;
  var httpProvisionCount = 0;
  var httpPowerCount = 0;
  var httpStateCount = 0;

  Future<void> shutdown() async {
    if (!running) return;
    running = false;
    await http.close(force: true);
    udpA.close();
    udpB.close();
    control.close();
  }

  void attachUdpResponder(RawDatagramSocket socket) {
    socket.readEventsEnabled = true;
    socket.writeEventsEnabled = false;

    socket.listen((event) {
      if (!running || event != RawSocketEvent.read) return;

      while (true) {
        final dg = socket.receive();
        if (dg == null) break;

        final data = dg.data;
        final looksProbe =
            data.length >= 2 && data[0] == 0x5a && data[1] == 0x5a;
        if (!looksProbe) continue;

        udpProbeCount++;

        final response = List<int>.filled(72, 0);
        response[0] = 0x5a;
        response[1] = 0x5a;
        response[20] = 0x78;
        response[21] = 0x56;
        response[22] = 0x34;
        response[23] = 0x12;
        response[24] = 0x00;
        response[25] = 0x00;

        socket.send(response, dg.address, dg.port);
      }
    });
  }

  attachUdpResponder(udpA);
  attachUdpResponder(udpB);

  control.listen((message) async {
    if (message == 'stop') {
      await shutdown();
      return;
    }

    if (message is Map && message['cmd'] == 'stats') {
      final replyTo = message['replyTo'];
      if (replyTo is SendPort) {
        replyTo.send({
          'udpProbeCount': udpProbeCount,
          'httpProvisionCount': httpProvisionCount,
          'httpPowerCount': httpPowerCount,
          'httpStateCount': httpStateCount,
          'power': power,
          'temperatureFridge': temperatureFridge,
          'temperatureFreezer': temperatureFreezer,
        });
      }
    }
  });

  bootstrapPort.send({
    'host': InternetAddress.loopbackIPv4.address,
    'httpPort': http.port,
    'udpPorts': [udpA.port, udpB.port],
    'control': control.sendPort,
  });

  await for (final request in http) {
    final path = request.uri.path;
    final method = request.method.toUpperCase();

    if (method == 'GET' && (path == '/' || path == '/health')) {
      request.response.statusCode = 200;
      await request.response.close();
      continue;
    }

    if (method == 'GET' && (path == '/state' || path == '/api/state')) {
      httpStateCount++;
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'power': power,
          'temperature_fridge': temperatureFridge,
          'temperature_freezer': temperatureFreezer,
          'mode': 1,
          'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        }),
      );
      await request.response.close();
      continue;
    }

    final isProvisionPath = <String>{
      '/provision',
      '/wifi/provision',
      '/wifi',
      '/wifi_config',
      '/config/wifi',
      '/network',
      '/network/config',
    }.contains(path);

    if ((method == 'POST' || method == 'PUT') && isProvisionPath) {
      httpProvisionCount++;
      await utf8.decoder.bind(request).join();
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"ok":true}');
      await request.response.close();
      continue;
    }

    if ((method == 'POST' || method == 'PUT') &&
        (path == '/power' || path == '/set/power')) {
      httpPowerCount++;
      final body = await utf8.decoder.bind(request).join();
      final lowered = body.toLowerCase();
      power = lowered.contains('true') || lowered.contains('"1"') || lowered.contains(':1');
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"ok":true}');
      await request.response.close();
      continue;
    }

    if ((method == 'POST' || method == 'PUT') &&
        (path == '/temperature_fridge' || path == '/set/temperature_fridge')) {
      final body = await utf8.decoder.bind(request).join();
      final parsed = double.tryParse(
        RegExp(r'-?\d+(\.\d+)?').firstMatch(body)?.group(0) ?? '',
      );
      if (parsed != null) {
        temperatureFridge = parsed;
      }
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"ok":true}');
      await request.response.close();
      continue;
    }

    if ((method == 'POST' || method == 'PUT') &&
        (path == '/temperature_freezer' || path == '/set/temperature_freezer')) {
      final body = await utf8.decoder.bind(request).join();
      final parsed = double.tryParse(
        RegExp(r'-?\d+(\.\d+)?').firstMatch(body)?.group(0) ?? '',
      );
      if (parsed != null) {
        temperatureFreezer = parsed;
      }
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"ok":true}');
      await request.response.close();
      continue;
    }

    request.response.statusCode = 404;
    await request.response.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
      _secureStorageChannel,
      (call) async {
        switch (call.method) {
          case 'read':
            return null;
          case 'write':
          case 'delete':
          case 'deleteAll':
            return null;
          case 'containsKey':
            return false;
          case 'readAll':
            return <String, String>{};
          default:
            return null;
        }
      },
      );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      _sharedPreferencesChannel,
      (call) async {
        switch (call.method) {
          case 'getAll':
            return <String, Object>{};
          case 'setBool':
          case 'setInt':
          case 'setDouble':
          case 'setString':
          case 'setStringList':
          case 'remove':
          case 'clear':
            return true;
          case 'commit':
            return true;
          default:
            return null;
        }
      },
    );

    Bridge.init();
  });

  tearDownAll(() {
    Bridge.destroy();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_sharedPreferencesChannel, null);
  });

  test('smoke: mock protocol onboarding and control', () async {
    const uuid = 'smoke-mock-001';

    await Bridge.onboardDevice(
      uuid: uuid,
      name: 'Smoke Mock Device',
      protocol: CoreProtocol.CORE_PROTOCOL_MOCK,
      capabilities: const [
        CoreCapability.CORE_CAP_POWER,
        CoreCapability.CORE_CAP_BRIGHTNESS,
      ],
      brand: 'Mock',
      model: 'Smoke',
    );

    expect(Bridge.onboardingStage(uuid), OnboardingStage.ready);
    expect(Bridge.connectionState(uuid), ProtocolConnectionState.connected);

    Bridge.setPower(uuid, true);
    final st = Bridge.getState(uuid);
    expect(st.power, isTrue);

    Bridge.removeDevice(uuid);
  });

  test('smoke: simulated wifi device onboarding + provision + control', () async {
    final fake = await _FakeWifiDevice.start();
    const uuid = 'smoke-wifi-001';

    try {
      await Bridge.onboardDevice(
        uuid: uuid,
        name: 'Smoke WiFi Device',
        protocol: CoreProtocol.CORE_PROTOCOL_WIFI,
        capabilities: const [
          CoreCapability.CORE_CAP_POWER,
          CoreCapability.CORE_CAP_TEMPERATURE,
          CoreCapability.CORE_CAP_MODE,
        ],
        brand: 'Generic',
        model: fake.endpoint,
        endpoint: fake.endpoint,
        credentials: const {'token': 'dummy-token'},
        wifiSsid: 'HomeNetwork',
        wifiPassword: '123456',
      );

      expect(Bridge.onboardingStage(uuid), OnboardingStage.ready);
      expect(Bridge.connectionState(uuid), ProtocolConnectionState.connected);

      Bridge.setPower(uuid, true);
      final st = Bridge.getState(uuid);
      expect(st.power, isTrue);
    } finally {
      try {
        Bridge.removeDevice(uuid);
      } catch (_) {}
      await fake.stop();
    }
  });

  test('smoke: adaptive layer APIs', () async {
    const uuid = 'smoke-adaptive-001';

    await Bridge.onboardDevice(
      uuid: uuid,
      name: 'Adaptive Mock Device',
      protocol: CoreProtocol.CORE_PROTOCOL_MOCK,
      capabilities: const [CoreCapability.CORE_CAP_POWER],
      brand: 'Mock',
      model: 'Adaptive',
    );

    expect(Bridge.connectToDevice(uuid), isTrue);
    expect(Bridge.ensureConnected(uuid), isTrue);

    final label = Bridge.connectionStateLabel(uuid).toLowerCase();
    expect(label, contains('connected'));

    final discovered = await Bridge.discoverDevicesAdaptive(
      protocol: CoreProtocol.CORE_PROTOCOL_MOCK,
      timeoutMs: 1200,
    );
    expect(discovered, isNotNull);

    Bridge.removeDevice(uuid);
  });

  test('smoke: realistic midea-like UDP + wifi onboarding + control', () async {
    final fake = await _FakeMideaLanDevice.start();
    const uuid = 'smoke-midea-442l-001';

    try {
      final udpHandshakeOk = await fake.sendDiscoveryProbe();
      expect(udpHandshakeOk, isTrue);

      await Bridge.onboardDevice(
        uuid: uuid,
        name: 'Midea Side by Side 442L',
        protocol: CoreProtocol.CORE_PROTOCOL_WIFI,
        capabilities: const [
          CoreCapability.CORE_CAP_POWER,
          CoreCapability.CORE_CAP_TEMPERATURE_FRIDGE,
          CoreCapability.CORE_CAP_TEMPERATURE_FREEZER,
        ],
        brand: 'Midea',
        model: 'Side by Side 442L',
        endpoint: fake.endpoint,
        credentials: const {
          'token': 'smoke-token',
          'key': 'smoke-key',
        },
        wifiSsid: 'RedeLocal',
        wifiPassword: '751234679',
      );

      expect(Bridge.onboardingStage(uuid), OnboardingStage.ready);
      expect(Bridge.connectionState(uuid), ProtocolConnectionState.connected);
      expect(Bridge.wifiProvisioningState(uuid), WifiProvisioningState.online);

      Bridge.setPower(uuid, true);
      Bridge.setTemperatureFridge(uuid, 2);
      Bridge.setTemperatureFreezer(uuid, -18);

      final st = Bridge.getState(uuid);
      expect(st.power, isTrue);

      final stats = await fake.stats();
      expect((stats['udpProbeCount'] as num?) ?? 0, greaterThan(0));
      expect((stats['httpProvisionCount'] as num?) ?? 0, greaterThan(0));
      expect((stats['httpPowerCount'] as num?) ?? 0, greaterThan(0));
      expect((stats['httpStateCount'] as num?) ?? 0, greaterThan(0));
      expect((stats['temperatureFridge'] as num?)?.toDouble(), closeTo(2.0, 0.001));
      expect((stats['temperatureFreezer'] as num?)?.toDouble(), closeTo(-18.0, 0.001));
    } finally {
      try {
        Bridge.removeDevice(uuid);
      } catch (_) {}
      await fake.stop();
    }
  });
}
