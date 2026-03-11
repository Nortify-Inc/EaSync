// ignore_for_file: no_leading_underscores_for_local_identifiers

/*!
 * @file bridge.dart
 * @brief FFI layer between Flutter and the EaSync Core native library.
 * @param uuid Device identifier used in control calls.
 * @return Public methods return states/lists or throw exceptions on failures.
 * @author Erick Radmann
 */

import '../handler.dart';

String _loadedCoreLibraryPath = 'libeasync_core.so';

DynamicLibrary _openCoreLibrary() {
  if (Platform.isWindows) {
    _loadedCoreLibraryPath = 'core.dll';
    return DynamicLibrary.open('core.dll');
  }

  if (Platform.isLinux) {
    final executableDir = File(Platform.resolvedExecutable).parent.path;
    final cwd = Directory.current.path;
    DynamicLibrary? firstLoadable;

    List<String> projectRootCandidates(String from) {
      final out = <String>[];
      var dir = Directory(from);
      for (var i = 0; i < 10; i++) {
        final pubspec = File('${dir.path}/pubspec.yaml');
        if (pubspec.existsSync()) {
          out.add('${dir.path}/lib/core/build/libeasync_core.so');
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
      return out;
    }

    final dynamicCandidates = <String>{
      ...projectRootCandidates(cwd),
      ...projectRootCandidates(executableDir),
    };

    final candidates = <String>[
      ...dynamicCandidates,
      '$cwd/lib/core/build/libeasync_core.so',
      '$executableDir/lib/libeasync_core.so',
      '$cwd/build/linux/x64/debug/bundle/lib/libeasync_core.so',
      '$cwd/build/linux/x64/release/bundle/lib/libeasync_core.so',
      '/usr/lib/libeasync_core.so',
      '/usr/local/lib/libeasync_core.so',
    ];

    for (final path in candidates) {
      if (!File(path).existsSync()) continue;

      try {
        final lib = DynamicLibrary.open(path);
        firstLoadable ??= lib;
      } catch (_) {}
    }

    if (firstLoadable != null) {
      _loadedCoreLibraryPath = 'fallback-first-loadable';
      return firstLoadable;
    }
  }

  _loadedCoreLibraryPath = 'libeasync_core.so';

  return DynamicLibrary.open('libeasync_core.so');
}

final DynamicLibrary coreLib = _openCoreLibrary();

DynamicLibrary _openAiLibrary() {
  if (Platform.isWindows) {
    return DynamicLibrary.open('ai.dll');
  }

  if (Platform.isLinux) {
    final executableDir = File(Platform.resolvedExecutable).parent.path;
    final cwd = Directory.current.path;

    final candidates = <String>[
      '$cwd/lib/ai/build/libeasync_ai.so',
      '$executableDir/lib/libeasync_ai.so',
      '$cwd/build/linux/x64/debug/bundle/lib/libeasync_ai.so',
      '$cwd/build/linux/x64/release/bundle/lib/libeasync_ai.so',
      '/usr/lib/libeasync_ai.so',
      '/usr/local/lib/libeasync_ai.so',
    ];

    for (final path in candidates) {
      try {
        if (!File(path).existsSync()) continue;
        final lib = DynamicLibrary.open(path);
        return lib;
      } catch (_) {}
    }
  }

  return DynamicLibrary.open('libeasync_ai.so');
}

final DynamicLibrary aiLib = _openAiLibrary();

// Sanitize chunks received from native code to remove leading replacement
// characters or control bytes that may arise from partial/invalid UTF-8.
String _sanitizeChunk(String s) {
  if (s.isEmpty) return s;
  // Remove leading Unicode replacement characters (U+FFFD)
  s = s.replaceFirst(RegExp(r'^\uFFFD+'), '');
  // Remove leading ASCII control chars except common whitespace (tab/newline)
  s = s.replaceFirst(RegExp(r'^[\x00-\x08\x0B\x0C\x0E-\x1F]+'), '');
  return s;
}

typedef _aiQueryC =
    Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Int8>, Uint32);
typedef _aiQueryDart =
    int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Int8>, int);

final _aiQuery = aiLib.lookupFunction<_aiQueryC, _aiQueryDart>('ai_query');

String aiQuery(String prompt) {
  final input = prompt;
  final inPtr = input.toNativeUtf8();
  const outLen = 8192;
  final outBuf = malloc.allocate<Int8>(outLen);
  try {
    print(
      '[Bridge] aiQuery: prompt="${prompt.length > 120 ? "${prompt.substring(0, 120)}..." : prompt}"',
    );
    final rc = _aiQuery(nullptr, inPtr, outBuf, outLen);
    print('[Bridge] aiQuery: rc=$rc');
    if (rc != 0) {
      print('[Bridge] aiQuery: native returned error rc=$rc');
      return '';
    }
    final res = outBuf.cast<Utf8>().toDartString();
    print('[Bridge] aiQuery: result_len=${res.length}');
    return res;
  } finally {
    malloc.free(inPtr);
    malloc.free(outBuf);
  }
}

typedef _aiQueryStartC =
    Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint64>);
typedef _aiQueryStartDart =
    int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint64>);

typedef _aiQueryPollC =
    Int32 Function(
      Pointer<Void>,
      Uint64,
      Pointer<Uint8>,
      Pointer<Int8>,
      Uint32,
    );
typedef _aiQueryPollDart =
    int Function(Pointer<Void>, int, Pointer<Uint8>, Pointer<Int8>, int);

final _aiQueryStart = aiLib.lookupFunction<_aiQueryStartC, _aiQueryStartDart>(
  'ai_query_async_start',
);
final _aiQueryPoll = aiLib.lookupFunction<_aiQueryPollC, _aiQueryPollDart>(
  'ai_query_async_poll',
);

typedef _aiInitializeC = Int32 Function(Pointer<Void>);
typedef _aiInitializeDart = int Function(Pointer<Void>);

final aiInitialize = (() {
  try {
    return aiLib.lookupFunction<_aiInitializeC, _aiInitializeDart>(
      'ai_initialize',
    );
  } catch (_) {
    return null;
  }
})();

typedef _aiSetDataDirC = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _aiSetDataDirDart = int Function(Pointer<Void>, Pointer<Utf8>);

final aiSetDataDir = (() {
  try {
    return aiLib.lookupFunction<_aiSetDataDirC, _aiSetDataDirDart>(
      'ai_set_data_dir',
    );
  } catch (_) {
    return null;
  }
})();

Future<String> _ensureAiAssetsCopied() async {
  final manifest = await rootBundle.loadString('AssetManifest.json');
  final Map<String, dynamic> map = manifest.isNotEmpty
      ? Map<String, dynamic>.from(jsonDecode(manifest))
      : {};
  final entries = map.keys.where((k) => k.startsWith('lib/ai/data/')).toList();

  if (entries.isEmpty) return '';

  final support = await getApplicationSupportDirectory();
  final outDir = Directory('${support.path}/ai_data');

  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  for (final assetPath in entries) {
    final rel = assetPath.substring('lib/ai/data/'.length);
    final outFile = File('${outDir.path}/$rel');
    if (outFile.existsSync()) continue;
    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      outFile.parent.createSync(recursive: true);
      await outFile.writeAsBytes(bytes, flush: true);
    } catch (e) {
      print('[Bridge] _ensureAiAssetsCopied failed for $assetPath: $e');
    }
  }

  return outDir.path;
}

Future<String> aiQueryAsync(String prompt, {int pollIntervalMs = 60}) async {
  final inPtr = prompt.toNativeUtf8();
  final handlePtr = malloc.allocate<Uint64>(sizeOf<Uint64>());
  try {
    print(
      '[Bridge] aiQueryAsync: starting prompt="${prompt.length > 120 ? "${prompt.substring(0, 120)}..." : prompt}"',
    );
    final rc = _aiQueryStart(nullptr, inPtr, handlePtr);

    print('[Bridge] aiQueryAsync: start rc=$rc');

    if (rc != 0) {
      print('[Bridge] aiQueryAsync: start failed rc=$rc');
      return '';
    }

    final handle = handlePtr.value;

    print('[Bridge] aiQueryAsync: handle=$handle');

    final outLen = 8192;
    final outBuf = malloc.allocate<Int8>(outLen);
    final finishedFlag = malloc.allocate<Uint8>(1);

    try {
      while (true) {
        final pollRc = _aiQueryPoll(
          nullptr,
          handle,
          finishedFlag,
          outBuf,
          outLen,
        );
        print(
          '[Bridge] aiQueryAsync: pollRc=$pollRc finished=${finishedFlag.value}',
        );
        if (pollRc == 0) {
          final res = outBuf.cast<Utf8>().toDartString();
          print('[Bridge] aiQueryAsync: got result len=${res.length}');
          return res;
        }
        // not ready yet: sleep and retry
        await Future.delayed(Duration(milliseconds: pollIntervalMs));
      }
    } finally {
      malloc.free(outBuf);
      malloc.free(finishedFlag);
    }
  } finally {
    malloc.free(inPtr);
    malloc.free(handlePtr);
  }
}

// Run the AI query inside a separate isolate to avoid blocking the main UI isolate.
Stream<String> aiQueryStream(String prompt, {int pollIntervalMs = 50}) {
  final controller = StreamController<String>();
  final rp = ReceivePort();

  rp.listen((dynamic msg) {
    try {
      if (msg is Map) {
        if (msg.containsKey('chunk')) {
          final c = msg['chunk'];
          if (c is String) controller.add(c);
        }
        if (msg.containsKey('done')) {
          controller.close();
        }
      }
    } catch (_) {}
  });

  Isolate.spawn(_aiQueryIsolateEntry, [rp.sendPort, prompt, pollIntervalMs]);

  controller.onCancel = () {
    try {
      rp.close();
    } catch (_) {}
  };

  return controller.stream;
}

// Entry point executed in the spawned isolate. Opens the AI dynamic library locally
// and performs the same async start/poll loop, sending chunk maps back to main.
Future<void> _aiQueryIsolateEntry(dynamic message) async {
  final args = message as List<dynamic>;
  final SendPort reply = args[0] as SendPort;
  final String prompt = (args.length > 1 && args[1] != null)
      ? args[1] as String
      : '';
  final int pollIntervalMs = (args.length > 2 && args[2] != null)
      ? args[2] as int
      : 150;

  try {
    final lib = DynamicLibrary.open('libeasync_ai.so');

    final _aiQueryStartLocal = lib
        .lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint64>),
          int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint64>)
        >('ai_query_async_start');

    final _aiQueryPollLocal = lib
        .lookupFunction<
          Int32 Function(
            Pointer<Void>,
            Uint64,
            Pointer<Uint8>,
            Pointer<Int8>,
            Uint32,
          ),
          int Function(Pointer<Void>, int, Pointer<Uint8>, Pointer<Int8>, int)
        >('ai_query_async_poll');

    final inPtr = prompt.toNativeUtf8();
    final handlePtr = malloc.allocate<Uint64>(sizeOf<Uint64>());
    try {
      final rc = _aiQueryStartLocal(nullptr, inPtr, handlePtr);
      if (rc != 0) {
        reply.send({'chunk': ''});
        reply.send({'done': true});
        return;
      }
      final handle = handlePtr.value;
      final outLen = 8192;
      final outBuf = malloc.allocate<Int8>(outLen);
      final finishedFlag = malloc.allocate<Uint8>(1);
      try {
        while (true) {
          final pollRc = _aiQueryPollLocal(
            nullptr,
            handle,
            finishedFlag,
            outBuf,
            outLen,
          );
          final resRaw = outBuf.cast<Utf8>().toDartString();
          final res = _sanitizeChunk(resRaw);
          if (pollRc == 1) {
            reply.send({'chunk': res});
            // continue streaming
            await Future.delayed(Duration(milliseconds: pollIntervalMs));
            continue;
          }
          if (pollRc == 0) {
            // final chunk
            reply.send({'chunk': res});
            reply.send({'done': true});
            return;
          }
          // not ready: wait
          await Future.delayed(Duration(milliseconds: pollIntervalMs));
        }
      } finally {
        malloc.free(outBuf);
        malloc.free(finishedFlag);
      }
    } finally {
      malloc.free(inPtr);
      malloc.free(handlePtr);
    }
  } catch (_) {
    try {
      reply.send({'chunk': ''});
      reply.send({'done': true});
    } catch (_) {}
  }
}

const String CORE_API_VERSION = "0.0.1";

const int CORE_MAX_CAPS = 16;
const int CORE_MAX_NAME = 64;
const int CORE_MAX_UUID = 64;
const int CORE_MAX_BRAND = 16;
const int CORE_MAX_MODEL = 32;

class CoreResult {
  static const int CORE_OK = 0;
  static const int CORE_ERROR = -1;
  static const int CORE_NOT_FOUND = -2;
  static const int CORE_ALREADY_EXISTS = -3;
  static const int CORE_INVALID_ARGUMENT = -4;
  static const int CORE_NOT_SUPPORTED = -5;
  static const int CORE_NOT_INITIALIZED = -6;
  static const int CORE_PROTOCOL_UNAVAILABLE = -7;
}

class CoreProtocol {
  static const int CORE_PROTOCOL_MOCK = 0;
  static const int CORE_PROTOCOL_MQTT = 1;
  static const int CORE_PROTOCOL_WIFI = 2;
  static const int CORE_PROTOCOL_ZIGBEE = 3;
  static const int CORE_PROTOCOL_BLE = 4;
}

class CoreCapability {
  static const int CORE_CAP_POWER = 0;
  static const int CORE_CAP_BRIGHTNESS = 1;
  static const int CORE_CAP_COLOR = 2;
  static const int CORE_CAP_TEMPERATURE = 3;
  static const int CORE_CAP_TEMPERATURE_FRIDGE = 4;
  static const int CORE_CAP_TEMPERATURE_FREEZER = 5;
  static const int CORE_CAP_TIMESTAMP = 6;
  static const int CORE_CAP_COLOR_TEMPERATURE = 7;
  static const int CORE_CAP_LOCK = 8;
  static const int CORE_CAP_MODE = 9;
  static const int CORE_CAP_POSITION = 10;
}

class CoreEventType {
  static const int CORE_EVENT_DEVICE_ADDED = 0;
  static const int CORE_EVENT_DEVICE_REMOVED = 1;
  static const int CORE_EVENT_STATE_CHANGED = 2;
  static const int CORE_EVENT_ERROR = 3;
}

base class CoreEventNative extends Struct {
  @Int32()
  external int type;

  @Array(CORE_MAX_UUID)
  external Array<Int8> uuid;

  external CoreDeviceState state;

  @Int32()
  external int errorCode;
}

base class CoreDeviceState extends Struct {
  @Bool()
  external bool power;

  @Int32()
  external int brightness;

  @Uint32()
  external int color;

  @Float()
  external double temperature;

  @Float()
  external double temperatureFridge;

  @Float()
  external double temperatureFreezer;

  @Uint64()
  external int timestamp;

  @Uint32()
  external int colorTemperature;

  @Bool()
  external bool lock;

  @Uint32()
  external int mode;

  @Float()
  external double position;
}

base class CoreDeviceInfo extends Struct {
  @Array(CORE_MAX_UUID)
  external Array<Int8> uuid;

  @Array(CORE_MAX_NAME)
  external Array<Int8> name;

  @Array(CORE_MAX_BRAND)
  external Array<Int8> brand;

  @Array(CORE_MAX_MODEL)
  external Array<Int8> model;

  @Int32()
  external int protocol;

  @Uint8()
  external int capabilityCount;

  @Array(CORE_MAX_CAPS)
  external Array<Int32> capabilities;
}

base class CoreAiPermissionsNative extends Struct {
  @Bool()
  external bool useLocationData;

  @Bool()
  external bool useWeatherData;

  @Bool()
  external bool useUsageHistory;

  @Bool()
  external bool allowDeviceControl;

  @Bool()
  external bool allowAutoRoutines;

  @Uint32()
  external int temperament;
}

typedef _coreCreateC = Pointer<Void> Function();
typedef _coreCreateDart = Pointer<Void> Function();

typedef _coreDestroyC = Void Function(Pointer<Void>);
typedef _coreDestroyDart = void Function(Pointer<Void>);

typedef _coreInitC = Int32 Function(Pointer<Void>);
typedef _coreInitDart = int Function(Pointer<Void>);

typedef _coreLastErrorC = Pointer<Utf8> Function(Pointer<Void>);
typedef _coreLastErrorDart = Pointer<Utf8> Function(Pointer<Void>);

typedef _coreListDevicesC =
    Int32 Function(
      Pointer<Void>,
      Pointer<CoreDeviceInfo>,
      Uint32,
      Pointer<Uint32>,
    );

typedef _coreListDevicesDart =
    int Function(Pointer<Void>, Pointer<CoreDeviceInfo>, int, Pointer<Uint32>);

typedef _coreGetStateC =
    Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<CoreDeviceState>);

typedef _coreGetStateDart =
    int Function(Pointer<Void>, Pointer<Utf8>, Pointer<CoreDeviceState>);

typedef _coreIsDeviceAvailableC =
    Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Bool>);
typedef _coreIsDeviceAvailableDart =
    int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Bool>);

typedef _coreRegisterDeviceC =
    Int32 Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Int32,
      Pointer<Int32>,
      Uint8,
    );

typedef _coreRegisterDeviceDart =
    int Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      int,
      Pointer<Int32>,
      int,
    );

typedef _coreRegisterDeviceExC =
    Int32 Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Int32,
      Pointer<Int32>,
      Uint8,
    );

typedef _coreRegisterDeviceExDart =
    int Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      int,
      Pointer<Int32>,
      int,
    );

typedef _coreRemoveDeviceC = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _coreRemoveDeviceDart = int Function(Pointer<Void>, Pointer<Utf8>);

typedef _coreSetPowerC = Int32 Function(Pointer<Void>, Pointer<Utf8>, Bool);
typedef _coreSetPowerDart = int Function(Pointer<Void>, Pointer<Utf8>, bool);

typedef _coreSetBrightnessC =
    Int32 Function(Pointer<Void>, Pointer<Utf8>, Int32);
typedef _coreSetBrightnessDart =
    int Function(Pointer<Void>, Pointer<Utf8>, int);

typedef _coreSetColorC = Int32 Function(Pointer<Void>, Pointer<Utf8>, Uint32);
typedef _coreSetColorDart = int Function(Pointer<Void>, Pointer<Utf8>, int);

typedef _coreSetTemperatureC =
    Int32 Function(Pointer<Void>, Pointer<Utf8>, Float);
typedef _coreSetTemperatureDart =
    int Function(Pointer<Void>, Pointer<Utf8>, double);

typedef _coreSetTemperatureFridgeC =
    Int32 Function(Pointer<Void>, Pointer<Utf8>, Float);
typedef _coreSetTemperatureFridgeDart =
    int Function(Pointer<Void>, Pointer<Utf8>, double);

typedef _coreSetTemperatureFreezerC =
    Int32 Function(Pointer<Void>, Pointer<Utf8>, Float);
typedef _coreSetTemperatureFreezerDart =
    int Function(Pointer<Void>, Pointer<Utf8>, double);

typedef _coreSetTimeC = Int32 Function(Pointer<Void>, Pointer<Utf8>, Uint64);
typedef _coreSetTimeDart = int Function(Pointer<Void>, Pointer<Utf8>, int);

typedef _coreSetColorTemperatureC =
    Int32 Function(Pointer<Void>, Pointer<Utf8>, Uint32);
typedef _coreSetColorTemperatureDart =
    int Function(Pointer<Void>, Pointer<Utf8>, int);

typedef _coreSetLockC = Int32 Function(Pointer<Void>, Pointer<Utf8>, Bool);
typedef _coreSetLockDart = int Function(Pointer<Void>, Pointer<Utf8>, bool);

typedef _coreSetModeC = Int32 Function(Pointer<Void>, Pointer<Utf8>, Uint32);
typedef _coreSetModeDart = int Function(Pointer<Void>, Pointer<Utf8>, int);

typedef _coreSetPositionC = Int32 Function(Pointer<Void>, Pointer<Utf8>, Float);
typedef _coreSetPositionDart =
    int Function(Pointer<Void>, Pointer<Utf8>, double);

typedef _coreProvisionWifiC =
    Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _coreProvisionWifiDart =
    int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);

typedef _coreSimulateC = Int32 Function(Pointer<Void>);
typedef _coreSimulateDart = int Function(Pointer<Void>);

typedef _coreEventTrampolineC =
    Void Function(Pointer<CoreEventNative>, Pointer<Void>);

typedef _coreSetEventCallbackC =
    Int32 Function(
      Pointer<Void>,
      Pointer<NativeFunction<_coreEventTrampolineC>>,
      Pointer<Void>,
    );

typedef _coreSetEventCallbackDart =
    int Function(
      Pointer<Void>,
      Pointer<NativeFunction<_coreEventTrampolineC>>,
      Pointer<Void>,
    );

final _coreCreateDart _coreCreate = coreLib
    .lookupFunction<_coreCreateC, _coreCreateDart>('core_create');

final _coreDestroyDart _coreDestroy = coreLib
    .lookupFunction<_coreDestroyC, _coreDestroyDart>('core_destroy');

final _coreInitDart _coreInit = coreLib
    .lookupFunction<_coreInitC, _coreInitDart>('core_init');

final _coreLastErrorDart _coreLastError = coreLib
    .lookupFunction<_coreLastErrorC, _coreLastErrorDart>('core_last_error');

final _coreListDevicesDart _coreListDevices = coreLib
    .lookupFunction<_coreListDevicesC, _coreListDevicesDart>(
      'core_list_devices',
    );

final _coreGetStateDart _coreGetState = coreLib
    .lookupFunction<_coreGetStateC, _coreGetStateDart>('core_get_state');

final _coreIsDeviceAvailableDart? _coreIsDeviceAvailable = (() {
  try {
    return coreLib
        .lookupFunction<_coreIsDeviceAvailableC, _coreIsDeviceAvailableDart>(
          'core_is_device_available',
        );
  } catch (_) {
    return null;
  }
})();

final _coreSetPowerDart _coreSetPower = coreLib
    .lookupFunction<_coreSetPowerC, _coreSetPowerDart>('core_set_power');

final _coreRegisterDeviceDart _coreRegisterDevice = coreLib
    .lookupFunction<_coreRegisterDeviceC, _coreRegisterDeviceDart>(
      'core_register_device',
    );

final _coreRegisterDeviceExDart? _coreRegisterDeviceEx = (() {
  try {
    return coreLib
        .lookupFunction<_coreRegisterDeviceExC, _coreRegisterDeviceExDart>(
          'core_register_device_ex',
        );
  } catch (_) {
    return null;
  }
})();

final _coreRemoveDeviceDart _coreRemoveDevice = coreLib
    .lookupFunction<_coreRemoveDeviceC, _coreRemoveDeviceDart>(
      'core_remove_device',
    );

final _coreSetBrightnessDart _coreSetBrightness = coreLib
    .lookupFunction<_coreSetBrightnessC, _coreSetBrightnessDart>(
      'core_set_brightness',
    );

final _coreSetColorDart _coreSetColor = coreLib
    .lookupFunction<_coreSetColorC, _coreSetColorDart>('core_set_color');

final _coreSetTemperatureDart _coreSetTemperature = coreLib
    .lookupFunction<_coreSetTemperatureC, _coreSetTemperatureDart>(
      'core_set_temperature',
    );

final _coreSetTemperatureFridgeDart _coreSetTemperatureFridge = coreLib
    .lookupFunction<_coreSetTemperatureFridgeC, _coreSetTemperatureFridgeDart>(
      'core_set_temperature_fridge',
    );

final _coreSetTemperatureFreezerDart _coreSetTemperatureFreezer = coreLib
    .lookupFunction<
      _coreSetTemperatureFreezerC,
      _coreSetTemperatureFreezerDart
    >('core_set_temperature_freezer');

final _coreSetTimeDart _coreSetTime = coreLib
    .lookupFunction<_coreSetTimeC, _coreSetTimeDart>('core_set_time');

final _coreSetColorTemperatureDart _coreSetColorTemperature = coreLib
    .lookupFunction<_coreSetColorTemperatureC, _coreSetColorTemperatureDart>(
      'core_set_color_temperature',
    );

final _coreSetLockDart _coreSetLock = coreLib
    .lookupFunction<_coreSetLockC, _coreSetLockDart>('core_set_lock');

final _coreSetModeDart _coreSetMode = coreLib
    .lookupFunction<_coreSetModeC, _coreSetModeDart>('core_set_mode');

final _coreSetPositionDart _coreSetPosition = coreLib
    .lookupFunction<_coreSetPositionC, _coreSetPositionDart>(
      'core_set_position',
    );

final _coreProvisionWifiDart? _coreProvisionWifi = (() {
  try {
    return coreLib.lookupFunction<_coreProvisionWifiC, _coreProvisionWifiDart>(
      'core_provision_wifi',
    );
  } catch (_) {
    return null;
  }
})();

final _coreSetEventCallbackDart _coreSetEventCallback = coreLib
    .lookupFunction<_coreSetEventCallbackC, _coreSetEventCallbackDart>(
      'core_set_event_callback',
    );

final _coreSimulateDart _coreSimulate = coreLib
    .lookupFunction<_coreSimulateC, _coreSimulateDart>('core_simulate');

class DeviceInfo {
  final String uuid;
  final String name;
  final String brand;
  final String model;
  final int protocol;
  final List<int> capabilities;

  DeviceInfo({
    required this.uuid,
    required this.name,
    required this.brand,
    required this.model,
    required this.protocol,
    required this.capabilities,
  });
}

class DeviceState {
  final bool power;
  int brightness = 0;
  int color = 0xFFFFFFFF;
  double temperature = 0.0;
  double temperatureFridge = 0.0;
  double temperatureFreezer = 0.0;
  int timestamp = 0;
  int colorTemperature = 0;
  bool lock = false;
  int mode = 0;
  double position = 0.0;

  DeviceState({required this.power});
}

class CoreEventData {
  final int type;
  final String uuid;
  final DeviceState state;
  final int errorCode;

  CoreEventData({
    required this.type,
    required this.uuid,
    required this.state,
    required this.errorCode,
  });
}

class DiscoveredDevice {
  final IconData icon;
  final String id;
  final String name;
  final int protocol;
  final String host;
  final int port;
  final String hint;
  final double confidence;
  final String vendor;

  DiscoveredDevice({
    required this.icon,
    required this.id,
    required this.name,
    required this.protocol,
    required this.host,
    required this.port,
    required this.hint,
    required this.confidence,
    this.vendor = 'generic',
  });
}

class DeviceConnectionHealth {
  final DateTime? lastSeen;
  final int lastLatencyMs;
  final int consecutiveFailures;
  final int totalFailures;

  const DeviceConnectionHealth({
    required this.lastSeen,
    required this.lastLatencyMs,
    required this.consecutiveFailures,
    required this.totalFailures,
  });
}

class BridgeDiagnosticEntry {
  final DateTime timestamp;
  final String category;
  final String message;
  final String? uuid;

  BridgeDiagnosticEntry({
    required this.timestamp,
    required this.category,
    required this.message,
    this.uuid,
  });
}

class WifiProvisioningState {
  static const String unprovisioned = 'unprovisioned';
  static const String apConnected = 'ap_connected';
  static const String homeWifiSent = 'home_wifi_sent';
  static const String online = 'online';
  static const String failed = 'failed';
}

class ProtocolConnectionState {
  static const String unknown = 'unknown';
  static const String connecting = 'connecting';
  static const String connected = 'connected';
  static const String disconnected = 'disconnected';
  static const String failed = 'failed';
}

class AiPermissions {
  final bool useLocationData;
  final bool useWeatherData;
  final bool useUsageHistory;
  final bool allowDeviceControl;
  final bool allowAutoRoutines;
  final int temperament;

  const AiPermissions({
    required this.useLocationData,
    required this.useWeatherData,
    required this.useUsageHistory,
    required this.allowDeviceControl,
    required this.allowAutoRoutines,
    this.temperament = 0,
  });
}

String _readFixedString(Array<Int8> array, int maxLen) {
  final bytes = <int>[];

  for (var i = 0; i < maxLen; i++) {
    final v = array[i];

    if (v == 0) break;

    bytes.add(v);
  }

  return String.fromCharCodes(bytes);
}

Never _throwLastError(int code) {
  final err = _coreLastError(Bridge._ctx!);

  final msg = err == nullptr ? 'Unknown error' : err.toDartString();

  throw Exception('Core error $code: $msg');
}

class Bridge {
  static bool _ready = false;
  static bool get isReady => _ready;

  static Pointer<Void>? _ctx;

  static final Map<String, DeviceState> _stateCache = {};
  static final Map<String, List<String>> _modeLabelsByDevice = {};
  static final Map<String, Map<String, dynamic>> _constraintsByDevice = {};
  static final Map<String, String> _assetByDevice = {};
  static final Map<String, String> _wifiProvisioningByDevice = {};
  static final Map<String, String> _wifiSsidByDevice = {};
  static final Map<String, String> _protocolConnectionByDevice = {};
  static final Map<String, int> _protocolByDevice = {};
  static final Map<String, String> _endpointByDevice = {};
  static final Map<String, DeviceConnectionHealth> _healthByDevice = {};
  static final List<BridgeDiagnosticEntry> _diagnostics = [];

  static final StreamController<String> _stateController =
      StreamController.broadcast();

  static final StreamController<CoreEventData> _eventController =
      StreamController.broadcast();

  static Pointer<NativeFunction<_coreEventTrampolineC>>? _eventCallbackPointer;

  static Timer? _simulateTimer;
  static Timer? _reconnectTimer;
  static bool _simulating = false;
  static final bool _enableAutoSimulation =
      (Platform.environment['EASYNC_ENABLE_SIMULATION'] == '1');

  static Stream<String> get onStateChanged => _stateController.stream;

  static Stream<CoreEventData> get onEvents => _eventController.stream;

  static void _log(String category, String message, {String? uuid}) {
    _diagnostics.add(
      BridgeDiagnosticEntry(
        timestamp: DateTime.now(),
        category: category,
        message: message,
        uuid: uuid,
      ),
    );

    if (_diagnostics.length > 500) {
      _diagnostics.removeRange(0, _diagnostics.length - 500);
    }
  }

  static DeviceState _cloneState(DeviceState s) {
    final clone = DeviceState(power: s.power);
    clone.brightness = s.brightness;
    clone.color = s.color;
    clone.temperature = s.temperature;
    clone.temperatureFridge = s.temperatureFridge;
    clone.temperatureFreezer = s.temperatureFreezer;
    clone.timestamp = s.timestamp;
    clone.colorTemperature = s.colorTemperature;
    clone.lock = s.lock;
    clone.mode = s.mode;
    clone.position = s.position;
    return clone;
  }

  static void _invalidateState(String uuid) {
    _stateCache.remove(uuid);
  }

  static void _startSimulationLoop() {
    _simulateTimer ??= Timer.periodic(const Duration(milliseconds: 800), (
      _,
    ) async {
      if (_simulating || !_ready) return;
      _simulating = true;

      try {
        final devices = listDevices();
        final hasOnlyMockDevices =
            devices.isNotEmpty &&
            devices.every((d) => d.protocol == CoreProtocol.CORE_PROTOCOL_MOCK);

        if (!hasOnlyMockDevices) {
          return;
        }

        final res = _coreSimulate(_ctx!);
        if (res != 0) {
          _throwLastError(res);
        }
      } catch (_) {
        // ignore simulation errors to keep loop alive
      } finally {
        _simulating = false;
      }
    });
  }

  static void _startReconnectLoop() {
    _reconnectTimer ??= Timer.periodic(const Duration(seconds: 6), (_) {
      if (!_ready) return;

      final uuids = _protocolByDevice.keys.toList();
      for (final uuid in uuids) {
        final protocol = _protocolByDevice[uuid];
        if (protocol == null || protocol == CoreProtocol.CORE_PROTOCOL_MOCK) {
          continue;
        }

        final current = connectionState(uuid);
        if (current == ProtocolConnectionState.connected) continue;

        try {
          establishProtocolConnection(uuid: uuid, protocol: protocol);
        } catch (_) {
          // keep retrying in background
        }
      }
    });
  }

  static void _ensureReady() {
    if (!_ready || _ctx == null) {
      throw Exception("Bridge not initialized. Call Bridge.init() first.");
    }
  }

  static Future<void> init() async {
    if (_ready) return;

    _log('core', 'Initializing bridge');
    _log('core', 'Native library candidate loaded: $_loadedCoreLibraryPath');

    _ctx = _coreCreate();

    if (_ctx == nullptr || _ctx == null) {
      _log('core', 'core_create failed');
      throw Exception('core_create failed');
    }

    final res = _coreInit(_ctx!);

    if (res != 0) {
      _log('core', 'core_init failed with code $res');
      _throwLastError(res);
    }

    _eventCallbackPointer ??= Pointer.fromFunction<_coreEventTrampolineC>(
      _onCoreEvent,
    );

    final cbRes = _coreSetEventCallback(_ctx!, _eventCallbackPointer!, nullptr);

    if (cbRes != 0) {
      _log('core', 'core_set_event_callback failed with code $cbRes');
      _throwLastError(cbRes);
    }

    _modelReadyCompleter ??= Completer<void>();

    if (aiInitialize != null) {
      Future<void>(() async {
        try {
          try {
            final aiDir = await _ensureAiAssetsCopied();
            if (aiDir.isNotEmpty && aiSetDataDir != null) {
              final p = aiDir.toNativeUtf8();
              try {
                final rcSet = aiSetDataDir!(nullptr, p);
                _log('core', 'ai_set_data_dir rc=$rcSet path=$aiDir');
              } finally {
                malloc.free(p);
              }
            }
          } catch (e) {
            _log('core', 'ai asset copy failed: $e');
          }

          _log('core', 'Preloading AI model...');

          final rc = aiInitialize!(_ctx!);

          _log('core', 'ai_initialize returned $rc');
        } catch (e) {
          _log('core', 'ai_initialize failed: $e');
        } finally {
          if (!(_modelReadyCompleter?.isCompleted ?? true))
            _modelReadyCompleter?.complete();
        }
      });
    } else {
      // No ai_initialize exported; mark ready immediately.
      if (!(_modelReadyCompleter?.isCompleted ?? true))
        _modelReadyCompleter?.complete();
    }

    if (_enableAutoSimulation) {
      _startSimulationLoop();
    }
    _startReconnectLoop();

    _ready = true;
    _log('core', 'Bridge ready');
  }

  static void destroy() {
    _log('core', 'Destroying bridge');
    _simulateTimer?.cancel();
    _simulateTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stateCache.clear();
    _modeLabelsByDevice.clear();
    _constraintsByDevice.clear();
    _assetByDevice.clear();
    _wifiProvisioningByDevice.clear();
    _wifiSsidByDevice.clear();
    _protocolConnectionByDevice.clear();
    _protocolByDevice.clear();
    _endpointByDevice.clear();
    _healthByDevice.clear();

    if (_ctx != null) {
      _coreDestroy(_ctx!);
      _ctx = null;
      _ready = false;
    }
  }

  static Completer<void>? _modelReadyCompleter;
  static Future<void> get modelReady async {
    if (_modelReadyCompleter == null) return Future<void>.value();
    return _modelReadyCompleter!.future;
  }

  static void registerDevice({
    required String uuid,
    required String name,
    required int protocol,
    required List<int> capabilities,
    String? brand,
    String? model,
    List<String>? modeLabels,
    Map<String, dynamic>? constraints,
    String? assetPath,
  }) {
    _ensureReady();
    _log('device', 'Registering device $name', uuid: uuid);

    final uuidPtr = uuid.toNativeUtf8();
    final namePtr = name.toNativeUtf8();
    final brandPtr = (brand ?? '').toNativeUtf8();
    final modelPtr = (model ?? '').toNativeUtf8();

    final capsPtr = calloc<Int32>(capabilities.length);

    for (var i = 0; i < capabilities.length; i++) {
      capsPtr[i] = capabilities[i];
    }

    final res = _coreRegisterDeviceEx != null
        ? _coreRegisterDeviceEx!(
            _ctx!,
            uuidPtr,
            namePtr,
            brandPtr,
            modelPtr,
            protocol,
            capsPtr,
            capabilities.length,
          )
        : _coreRegisterDevice(
            _ctx!,
            uuidPtr,
            namePtr,
            protocol,
            capsPtr,
            capabilities.length,
          );

    calloc.free(uuidPtr);
    calloc.free(namePtr);
    calloc.free(brandPtr);
    calloc.free(modelPtr);
    calloc.free(capsPtr);

    if (res != 0) {
      _log('device', 'Register failed with code $res', uuid: uuid);
      _throwLastError(res);
    }

    if (modeLabels != null && modeLabels.isNotEmpty) {
      _modeLabelsByDevice[uuid] = modeLabels;
    }

    if (constraints != null && constraints.isNotEmpty) {
      _constraintsByDevice[uuid] = Map<String, dynamic>.from(constraints);

      if ((modeLabels == null || modeLabels.isEmpty) &&
          constraints['mode'] is List) {
        _modeLabelsByDevice[uuid] = (constraints['mode'] as List)
            .map((e) => e.toString())
            .toList();
      }
    }

    if (assetPath != null && assetPath.trim().isNotEmpty) {
      _assetByDevice[uuid] = assetPath.trim();
    }

    if (protocol == CoreProtocol.CORE_PROTOCOL_WIFI) {
      _wifiProvisioningByDevice[uuid] = WifiProvisioningState.unprovisioned;
    }

    _protocolByDevice[uuid] = protocol;

    final endpointCandidate = _extractEndpointCandidate(model);
    if (endpointCandidate != null) {
      _endpointByDevice[uuid] = endpointCandidate;
    }

    _healthByDevice[uuid] = const DeviceConnectionHealth(
      lastSeen: null,
      lastLatencyMs: -1,
      consecutiveFailures: 0,
      totalFailures: 0,
    );

    _protocolConnectionByDevice[uuid] =
        protocol == CoreProtocol.CORE_PROTOCOL_MOCK
        ? ProtocolConnectionState.connected
        : ProtocolConnectionState.connecting;

    if (protocol != CoreProtocol.CORE_PROTOCOL_WIFI) {
      refreshDeviceConnection(uuid);
    }

    _log('device', 'Device registered', uuid: uuid);
  }

  static void removeDevice(String uuid) {
    _ensureReady();
    _log('device', 'Removing device', uuid: uuid);

    final uuidPtr = uuid.toNativeUtf8();
    final res = _coreRemoveDevice(_ctx!, uuidPtr);

    calloc.free(uuidPtr);

    if (res != 0) {
      _log('device', 'Remove failed with code $res', uuid: uuid);
      _throwLastError(res);
    }

    _invalidateState(uuid);
    _modeLabelsByDevice.remove(uuid);
    _constraintsByDevice.remove(uuid);
    _assetByDevice.remove(uuid);
    _wifiProvisioningByDevice.remove(uuid);
    _wifiSsidByDevice.remove(uuid);
    _protocolConnectionByDevice.remove(uuid);
    _protocolByDevice.remove(uuid);
    _endpointByDevice.remove(uuid);
    _healthByDevice.remove(uuid);
    _log('device', 'Device removed', uuid: uuid);
  }

  static void _restoreStateSnapshot(
    String uuid,
    List<int> capabilities,
    DeviceState state,
  ) {
    if (capabilities.contains(CoreCapability.CORE_CAP_POWER)) {
      try {
        setPower(uuid, state.power);
      } catch (_) {}
    }
    if (capabilities.contains(CoreCapability.CORE_CAP_BRIGHTNESS)) {
      try {
        setBrightness(uuid, state.brightness);
      } catch (_) {}
    }
    if (capabilities.contains(CoreCapability.CORE_CAP_COLOR)) {
      try {
        setColor(uuid, state.color);
      } catch (_) {}
    }
    if (capabilities.contains(CoreCapability.CORE_CAP_TEMPERATURE)) {
      try {
        setTemperature(uuid, state.temperature);
      } catch (_) {}
    }
    if (capabilities.contains(CoreCapability.CORE_CAP_TEMPERATURE_FRIDGE)) {
      try {
        setTemperatureFridge(uuid, state.temperatureFridge);
      } catch (_) {}
    }
    if (capabilities.contains(CoreCapability.CORE_CAP_TEMPERATURE_FREEZER)) {
      try {
        setTemperatureFreezer(uuid, state.temperatureFreezer);
      } catch (_) {}
    }
    if (capabilities.contains(CoreCapability.CORE_CAP_TIMESTAMP)) {
      try {
        setTime(uuid, state.timestamp);
      } catch (_) {}
    }
    if (capabilities.contains(CoreCapability.CORE_CAP_COLOR_TEMPERATURE)) {
      try {
        setColorTemperature(uuid, state.colorTemperature);
      } catch (_) {}
    }
    if (capabilities.contains(CoreCapability.CORE_CAP_LOCK)) {
      try {
        setLock(uuid, state.lock);
      } catch (_) {}
    }
    if (capabilities.contains(CoreCapability.CORE_CAP_MODE)) {
      try {
        setMode(uuid, state.mode);
      } catch (_) {}
    }
    if (capabilities.contains(CoreCapability.CORE_CAP_POSITION)) {
      try {
        setPosition(uuid, state.position);
      } catch (_) {}
    }
  }

  static void renameDevice(String uuid, String nickname) {
    _ensureReady();

    final newName = nickname.trim();
    if (newName.isEmpty) {
      throw Exception('Nickname cannot be empty.');
    }

    final devices = listDevices();
    DeviceInfo? current;
    for (final d in devices) {
      if (d.uuid == uuid) {
        current = d;
        break;
      }
    }

    if (current == null) {
      throw Exception('Device not found for rename.');
    }

    if (current.name.trim() == newName) {
      return;
    }

    final modeLabels = _modeLabelsByDevice[uuid] == null
        ? null
        : List<String>.from(_modeLabelsByDevice[uuid]!);
    final constraints = _constraintsByDevice[uuid] == null
        ? null
        : Map<String, dynamic>.from(_constraintsByDevice[uuid]!);
    final assetPath = _assetByDevice[uuid];
    final wifiProvisioning = _wifiProvisioningByDevice[uuid];
    final wifiSsid = _wifiSsidByDevice[uuid];
    final protocolConnection = _protocolConnectionByDevice[uuid];
    final endpoint = _endpointByDevice[uuid];
    final health = _healthByDevice[uuid];

    DeviceState? snapshot;
    try {
      snapshot = getState(uuid);
    } catch (_) {
      snapshot = _stateCache[uuid] == null
          ? null
          : _cloneState(_stateCache[uuid]!);
    }

    removeDevice(uuid);

    registerDevice(
      uuid: uuid,
      name: newName,
      protocol: current.protocol,
      capabilities: List<int>.from(current.capabilities),
      brand: current.brand,
      model: current.model,
      modeLabels: modeLabels,
      constraints: constraints,
      assetPath: assetPath,
    );

    if (wifiProvisioning != null) {
      _wifiProvisioningByDevice[uuid] = wifiProvisioning;
    }
    if (wifiSsid != null) {
      _wifiSsidByDevice[uuid] = wifiSsid;
    }
    if (endpoint != null) {
      _endpointByDevice[uuid] = endpoint;
    }
    if (health != null) {
      _healthByDevice[uuid] = health;
    }

    if (current.protocol != CoreProtocol.CORE_PROTOCOL_MOCK) {
      try {
        establishProtocolConnection(uuid: uuid, protocol: current.protocol);
      } catch (_) {}
    }

    if (snapshot != null) {
      _restoreStateSnapshot(uuid, current.capabilities, snapshot);
    }

    if (protocolConnection != null) {
      _protocolConnectionByDevice[uuid] = protocolConnection;
    }

    _log('device', 'Device renamed to "$newName"', uuid: uuid);
  }

  static String? _extractEndpointCandidate(String? model) {
    if (model == null) return null;
    final value = model.trim();
    if (value.isEmpty) return null;

    final withoutHttp = value.replaceFirst(
      RegExp(r'^https?://', caseSensitive: false),
      '',
    );
    final hostPort = withoutHttp.split('/').first.trim();

    if (hostPort.isEmpty) return null;
    if (!hostPort.contains('.') && !hostPort.contains(':')) return null;
    return hostPort;
  }

  static String? endpointForDevice(String uuid) => _endpointByDevice[uuid];

  static void setDeviceEndpoint(String uuid, String endpoint) {
    final normalized = endpoint.trim();
    if (normalized.isEmpty) return;
    _endpointByDevice[uuid] = normalized;
  }

  static DeviceConnectionHealth health(String uuid) {
    return _healthByDevice[uuid] ??
        const DeviceConnectionHealth(
          lastSeen: null,
          lastLatencyMs: -1,
          consecutiveFailures: 0,
          totalFailures: 0,
        );
  }

  static String healthLabel(String uuid) {
    final h = health(uuid);
    if (h.lastSeen == null) {
      return 'Never seen';
    }

    final latency = h.lastLatencyMs >= 0 ? '${h.lastLatencyMs} ms' : 'n/a';
    final failures = h.consecutiveFailures > 0
        ? ' • failures ${h.consecutiveFailures}'
        : '';
    return 'Seen • $latency$failures';
  }

  static void markWifiApConnected(String uuid) {
    _wifiProvisioningByDevice[uuid] = WifiProvisioningState.apConnected;
  }

  static void markWifiCredentialsSent(String uuid, {required String ssid}) {
    _wifiProvisioningByDevice[uuid] = WifiProvisioningState.homeWifiSent;
    _wifiSsidByDevice[uuid] = ssid.trim();
  }

  static Future<void> provisionWifi({
    required String uuid,
    required String ssid,
    required String password,
  }) async {
    _ensureReady();
    _log('wifi', 'Starting Wi-Fi provisioning', uuid: uuid);

    final ssidTrimmed = ssid.trim();
    if (ssidTrimmed.isEmpty || password.trim().isEmpty) {
      throw Exception('Wi-Fi credentials are required.');
    }

    markWifiApConnected(uuid);

    if (_coreProvisionWifi == null) {
      markWifiCredentialsSent(uuid, ssid: ssidTrimmed);
      _log('wifi', 'Provision API unavailable', uuid: uuid);
      throw Exception(
        'Core provisioning API unavailable. Rebuild native core.',
      );
    }

    final uuidPtr = uuid.toNativeUtf8();
    final ssidPtr = ssidTrimmed.toNativeUtf8();
    final passwordPtr = password.toNativeUtf8();

    final res = _coreProvisionWifi!(_ctx!, uuidPtr, ssidPtr, passwordPtr);

    calloc.free(uuidPtr);
    calloc.free(ssidPtr);
    calloc.free(passwordPtr);

    if (res != 0) {
      markWifiFailed(uuid);
      _protocolConnectionByDevice[uuid] = ProtocolConnectionState.failed;
      _log('wifi', 'Provision failed with code $res', uuid: uuid);
      _throwLastError(res);
    }

    markWifiCredentialsSent(uuid, ssid: ssidTrimmed);

    var connected = false;
    for (var i = 0; i < 5; i++) {
      await Future.delayed(const Duration(seconds: 2));
      connected = refreshDeviceConnection(uuid);
      if (connected) break;
    }

    if (!connected) {
      markWifiFailed(uuid);
      _protocolConnectionByDevice[uuid] = ProtocolConnectionState.failed;
      _log(
        'wifi',
        'Provision submitted but device did not come online',
        uuid: uuid,
      );
      throw Exception('Provisioning sent, but device is still offline.');
    }

    markWifiOnline(uuid);
    _protocolConnectionByDevice[uuid] = ProtocolConnectionState.connected;
    _log('wifi', 'Provision succeeded and device is online', uuid: uuid);
  }

  static void markWifiOnline(String uuid) {
    _wifiProvisioningByDevice[uuid] = WifiProvisioningState.online;
  }

  static void markWifiFailed(String uuid) {
    _wifiProvisioningByDevice[uuid] = WifiProvisioningState.failed;
  }

  static String wifiProvisioningState(String uuid) {
    return _wifiProvisioningByDevice[uuid] ??
        WifiProvisioningState.unprovisioned;
  }

  static String? wifiProvisioningSsid(String uuid) {
    return _wifiSsidByDevice[uuid];
  }

  static String wifiProvisioningLabel(String uuid) {
    switch (wifiProvisioningState(uuid)) {
      case WifiProvisioningState.apConnected:
        return 'AP connected';
      case WifiProvisioningState.homeWifiSent:
        return 'Home Wi-Fi sent';
      case WifiProvisioningState.online:
        return 'Online';
      case WifiProvisioningState.failed:
        return 'Provision failed';
      case WifiProvisioningState.unprovisioned:
      default:
        return 'Needs provisioning';
    }
  }

  static bool isDeviceAvailable(String uuid) {
    _ensureReady();

    if (_coreIsDeviceAvailable == null) {
      return true;
    }

    final uuidPtr = uuid.toNativeUtf8();
    final outAvailable = calloc<Bool>();

    final res = _coreIsDeviceAvailable!(_ctx!, uuidPtr, outAvailable);

    calloc.free(uuidPtr);

    if (res != 0) {
      calloc.free(outAvailable);
      _throwLastError(res);
    }

    final available = outAvailable.value;
    calloc.free(outAvailable);
    return available;
  }

  static bool refreshDeviceConnection(String uuid) {
    final start = DateTime.now();
    try {
      final available = isDeviceAvailable(uuid);
      _protocolConnectionByDevice[uuid] = available
          ? ProtocolConnectionState.connected
          : ProtocolConnectionState.disconnected;

      final current = health(uuid);
      final latency = DateTime.now().difference(start).inMilliseconds;

      _healthByDevice[uuid] = DeviceConnectionHealth(
        lastSeen: available ? DateTime.now() : current.lastSeen,
        lastLatencyMs: latency,
        consecutiveFailures: available ? 0 : current.consecutiveFailures + 1,
        totalFailures: available
            ? current.totalFailures
            : current.totalFailures + 1,
      );

      return available;
    } catch (_) {
      _protocolConnectionByDevice[uuid] = ProtocolConnectionState.failed;
      final current = health(uuid);
      _healthByDevice[uuid] = DeviceConnectionHealth(
        lastSeen: current.lastSeen,
        lastLatencyMs: -1,
        consecutiveFailures: current.consecutiveFailures + 1,
        totalFailures: current.totalFailures + 1,
      );
      _log('connection', 'Connection refresh failed', uuid: uuid);
      return false;
    }
  }

  static Future<bool> verifyDiscoveredDevice(DiscoveredDevice d) async {
    if (d.protocol == CoreProtocol.CORE_PROTOCOL_BLE) {
      return _hasLocalBleAdapter();
    }

    if (d.protocol == CoreProtocol.CORE_PROTOCOL_WIFI) {
      return await _checkHttp(d.host, '/state', port: d.port) ||
          await _checkHttp(d.host, '/provision', port: d.port) ||
          await _checkHttp(d.host, '/', port: d.port);
    }

    if (d.protocol == CoreProtocol.CORE_PROTOCOL_MQTT ||
        d.protocol == CoreProtocol.CORE_PROTOCOL_ZIGBEE) {
      return _checkTcp(d.host, d.port);
    }

    return false;
  }

  static String connectionState(String uuid) {
    return _protocolConnectionByDevice[uuid] ?? ProtocolConnectionState.unknown;
  }

  static String connectionLabel(String uuid) {
    switch (connectionState(uuid)) {
      case ProtocolConnectionState.connecting:
        return 'Connecting';
      case ProtocolConnectionState.connected:
        return 'Connected';
      case ProtocolConnectionState.disconnected:
        return 'Disconnected';
      case ProtocolConnectionState.failed:
        return 'Connection failed';
      case ProtocolConnectionState.unknown:
      default:
        return 'Connection unknown';
    }
  }

  static bool establishProtocolConnection({
    required String uuid,
    required int protocol,
  }) {
    if (protocol == CoreProtocol.CORE_PROTOCOL_MOCK) {
      _protocolConnectionByDevice[uuid] = ProtocolConnectionState.connected;
      return true;
    }

    if (protocol == CoreProtocol.CORE_PROTOCOL_WIFI) {
      final provisioned =
          wifiProvisioningState(uuid) == WifiProvisioningState.online;
      final ok = provisioned && refreshDeviceConnection(uuid);
      _protocolConnectionByDevice[uuid] = ok
          ? ProtocolConnectionState.connected
          : ProtocolConnectionState.disconnected;
      return ok;
    }

    return refreshDeviceConnection(uuid);
  }

  static Future<bool> _checkTcp(String host, int port) async {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 700),
      );
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _checkHttp(
    String host,
    String path, {
    int port = 80,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    try {
      final req = await client.getUrl(Uri.parse('http://$host:$port$path'));
      final res = await req.close().timeout(const Duration(seconds: 1));
      await res.drain();
      return res.statusCode >= 200 && res.statusCode < 500;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static Future<List<String>> _candidateLanHosts() async {
    final hosts = <String>{
      '192.168.4.1',
      '192.168.0.1',
      '192.168.1.1',
      '192.168.1.2',
      '192.168.1.10',
      '192.168.1.20',
      '192.168.1.30',
      '192.168.1.50',
      '192.168.1.100',
      'homeassistant.local',
      'mosquitto',
      'mqtt.local',
      'zigbee2mqtt.local',
    };

    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length != 4) continue;
          final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
          final current = int.tryParse(parts[3]);

          hosts.add('$prefix.1');
          hosts.add('$prefix.2');
          hosts.add('$prefix.10');
          hosts.add('$prefix.20');
          hosts.add('$prefix.30');
          hosts.add('$prefix.50');
          hosts.add('$prefix.100');

          if (current != null) {
            for (int i = -2; i <= 2; i++) {
              final octet = current + i;
              if (octet > 0 && octet < 255) {
                hosts.add('$prefix.$octet');
              }
            }
          }
        }
      }
    } catch (_) {}

    return hosts.toList();
  }

  static Future<List<T>> _runBatched<T>(
    List<Future<T> Function()> tasks, {
    int batchSize = 18,
  }) async {
    final out = <T>[];

    for (var i = 0; i < tasks.length; i += batchSize) {
      final end = (i + batchSize) > tasks.length
          ? tasks.length
          : (i + batchSize);
      final chunk = tasks.sublist(i, end).map((t) => t());
      out.addAll(await Future.wait(chunk));
    }

    return out;
  }

  static Future<bool> _hasLocalBleAdapter() async {
    Future<bool> contains(String exe, List<String> args, Pattern p) async {
      try {
        final result = await Process.run(
          exe,
          args,
          runInShell: true,
        ).timeout(const Duration(milliseconds: 1200));

        if (result.exitCode != 0) return false;
        final text = '${result.stdout}\n${result.stderr}'.toLowerCase();
        return text.contains(p);
      } catch (_) {
        return false;
      }
    }

    return await contains('bluetoothctl', ['show'], 'controller') ||
        await contains('hciconfig', [], 'hci');
  }

  static Future<List<DiscoveredDevice>> _probeHost(String host) async {
    final results = <DiscoveredDevice>[];

    const mqttPorts = [1883, 8883, 1884, 9001];
    const wifiHttpPorts = [80, 8080, 8081];
    const wifiPaths = [
      '/provision',
      '/wifi/provision',
      '/state',
      '/api/state',
      '/status',
      '/health',
      '/',
    ];

    final mqttChecks = await Future.wait(
      mqttPorts.map((p) async => MapEntry(p, await _checkTcp(host, p))),
    );

    for (final check in mqttChecks.where((e) => e.value)) {
      final port = check.key;
      final secure = port == 8883;

      results.add(
        DiscoveredDevice(
          icon: Icons.compare_arrows_rounded,
          id: 'mqtt:$host:$port',
          name: 'MQTT Broker ($host)',
          protocol: CoreProtocol.CORE_PROTOCOL_MQTT,
          host: host,
          port: port,
          hint: secure
              ? 'MQTT TLS broker detected on port $port'
              : 'MQTT broker detected on port $port',
          confidence: secure ? 0.90 : 0.86,
          vendor: host.contains('homeassistant') ? 'home-assistant' : 'generic',
        ),
      );

      if (port == 1883 || port == 8883) {
        results.add(
          DiscoveredDevice(
            icon: Icons.rotate_90_degrees_cw_rounded,
            id: 'zigbee:$host:$port',
            name: 'Zigbee Gateway ($host)',
            protocol: CoreProtocol.CORE_PROTOCOL_ZIGBEE,
            host: host,
            port: port,
            hint: 'Potential ZigBee2MQTT gateway via MQTT:$port',
            confidence: port == 8883 ? 0.74 : 0.70,
            vendor: 'zigbee2mqtt',
          ),
        );
      }
    }

    final wifiTasks = <Future<bool>>[];
    for (final port in wifiHttpPorts) {
      for (final path in wifiPaths) {
        wifiTasks.add(_checkHttp(host, path, port: port));
      }
    }

    final wifiHits = await Future.wait(wifiTasks);
    if (wifiHits.any((ok) => ok)) {
      final port = wifiHttpPorts.firstWhere(
        (p) => p == 80 || p == 8080,
        orElse: () => 80,
      );
      results.add(
        DiscoveredDevice(
          icon: Icons.wifi_rounded,
          id: 'wifi:$host:$port',
          name: 'Wi-Fi Device ($host)',
          protocol: CoreProtocol.CORE_PROTOCOL_WIFI,
          host: host,
          port: port,
          hint: 'HTTP/device endpoint detected',
          confidence: 0.75,
          vendor: host.contains('midea') ? 'midea' : 'generic',
        ),
      );
    }

    return results;
  }

  static Future<List<DiscoveredDevice>> discoverDevices() async {
    _log('discovery', 'Starting network discovery');
    final discovered = <DiscoveredDevice>[];
    final seen = <String>{};

    final hosts = await _candidateLanHosts();

    final probeTasks = hosts
        .map<Future<List<DiscoveredDevice>> Function()>(
          (host) =>
              () => _probeHost(host),
        )
        .toList();

    final hostResults = await _runBatched(probeTasks, batchSize: 20);

    for (final list in hostResults) {
      for (final item in list) {
        if (seen.add(item.id)) {
          discovered.add(item);
        }
      }
    }

    final hasBleAdapter = await _hasLocalBleAdapter();
    if (hasBleAdapter) {
      final ble = DiscoveredDevice(
        icon: Icons.bluetooth_rounded,
        id: 'ble:local:0',
        name: 'Nearby BLE devices',
        protocol: CoreProtocol.CORE_PROTOCOL_BLE,
        host: 'local',
        port: 0,
        hint: 'Local BLE adapter detected',
        confidence: 0.62,
        vendor: 'generic',
      );

      if (seen.add(ble.id)) {
        discovered.add(ble);
      }
    }

    discovered.sort((a, b) => b.confidence.compareTo(a.confidence));

    _log(
      'discovery',
      'Discovery finished with ${discovered.length} candidates',
    );
    return discovered;
  }

  static List<BridgeDiagnosticEntry> diagnostics({
    String? uuid,
    int limit = 120,
  }) {
    final reversed = _diagnostics.reversed
        .where((entry) {
          if (uuid == null || uuid.trim().isEmpty) return true;
          return entry.uuid == uuid;
        })
        .take(limit)
        .toList();

    return reversed.reversed.toList();
  }

  static void clearDiagnostics({String? uuid}) {
    if (uuid == null || uuid.trim().isEmpty) {
      _diagnostics.clear();
      return;
    }

    _diagnostics.removeWhere((entry) => entry.uuid == uuid);
  }

  static String? deviceAsset(String uuid) {
    return _assetByDevice[uuid];
  }

  static void setDeviceAsset(String uuid, String? assetPath) {
    if (assetPath == null || assetPath.trim().isEmpty) return;
    _assetByDevice[uuid] = assetPath.trim();
  }

  static String modeName(String uuid, int modeIndex) {
    final labels = _modeLabelsByDevice[uuid];
    if (labels == null || labels.isEmpty) {
      return "Mode $modeIndex";
    }

    final idx = modeIndex.clamp(0, labels.length - 1);
    final raw = labels[idx];
    return raw
        .replaceAll('_', ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  static int modeCount(String uuid) {
    final labels = _modeLabelsByDevice[uuid];
    if (labels == null || labels.isEmpty) return 6;
    return labels.length;
  }

  static double _constraintNumber(
    String uuid,
    String key,
    String field,
    double fallback,
  ) {
    final constraints = _constraintsByDevice[uuid];
    if (constraints == null) return fallback;

    final value = constraints[key];
    if (value is! Map) return fallback;

    final numValue = value[field];
    if (numValue is num) return numValue.toDouble();

    return fallback;
  }

  static double constraintMin(String uuid, String key, double fallback) {
    return _constraintNumber(uuid, key, 'min', fallback);
  }

  static double constraintMax(String uuid, String key, double fallback) {
    return _constraintNumber(uuid, key, 'max', fallback);
  }

  static double constraintStep(String uuid, String key, double fallback) {
    return _constraintNumber(uuid, key, 'step', fallback);
  }

  static List<DeviceInfo> listDevices() {
    _ensureReady();

    final countPtr = calloc<Uint32>();

    final first = _coreListDevices(_ctx!, nullptr, 0, countPtr);

    if (first != 0) {
      calloc.free(countPtr);
      _throwLastError(first);
    }

    final count = countPtr.value;

    final buffer = calloc<CoreDeviceInfo>(count);

    final second = _coreListDevices(_ctx!, buffer, count, countPtr);

    if (second != 0) {
      calloc.free(buffer);
      calloc.free(countPtr);
      _throwLastError(second);
    }

    final list = <DeviceInfo>[];

    for (var i = 0; i < count; i++) {
      final item = buffer[i];

      final caps = <int>[];

      for (var j = 0; j < item.capabilityCount; j++) {
        caps.add(item.capabilities[j]);
      }

      list.add(
        DeviceInfo(
          uuid: _readFixedString(item.uuid, CORE_MAX_UUID),
          name: _readFixedString(item.name, CORE_MAX_NAME),
          brand: _readFixedString(item.brand, CORE_MAX_BRAND),
          model: _readFixedString(item.model, CORE_MAX_MODEL),
          protocol: item.protocol,
          capabilities: caps,
        ),
      );

      _protocolByDevice[_readFixedString(item.uuid, CORE_MAX_UUID)] =
          item.protocol;
    }

    calloc.free(buffer);
    calloc.free(countPtr);

    return list;
  }

  static DeviceState getState(String uuid) {
    _ensureReady();

    final cached = _stateCache[uuid];
    if (cached != null) return _cloneState(cached);

    final result = _fetchState(uuid);
    _stateCache[uuid] = result;

    return _cloneState(result);
  }

  static DeviceState _fetchState(String uuid) {
    _ensureReady();

    final uuidPtr = uuid.toNativeUtf8();
    final statePtr = calloc<CoreDeviceState>();

    final res = _coreGetState(_ctx!, uuidPtr, statePtr);

    calloc.free(uuidPtr);

    if (res != 0) {
      calloc.free(statePtr);
      _throwLastError(res);
    }

    final result = _mapState(statePtr.ref);

    calloc.free(statePtr);

    return result;
  }

  static DeviceState _mapState(CoreDeviceState s) {
    final result = DeviceState(power: s.power);

    result.brightness = s.brightness;
    result.color = s.color;
    result.temperature = s.temperature;
    result.temperatureFridge = s.temperatureFridge;
    result.temperatureFreezer = s.temperatureFreezer;
    result.timestamp = s.timestamp.toInt();
    result.colorTemperature = s.colorTemperature;
    result.lock = s.lock;
    result.mode = s.mode;
    result.position = s.position;

    return result;
  }

  static void setPower(String uuid, bool value) {
    _ensureReady();

    final uuidPtr = uuid.toNativeUtf8();

    final res = _coreSetPower(_ctx!, uuidPtr, value);

    calloc.free(uuidPtr);

    if (res != 0) {
      _throwLastError(res);
    }
    _invalidateState(uuid);
    _stateController.add(uuid);
  }

  static void setBrightness(String uuid, int value) {
    _ensureReady();

    final uuidPtr = uuid.toNativeUtf8();

    final res = _coreSetBrightness(_ctx!, uuidPtr, value);

    calloc.free(uuidPtr);

    if (res != 0) {
      _throwLastError(res);
    }
    _invalidateState(uuid);
    _stateController.add(uuid);
  }

  static void setColor(String uuid, int value) {
    _ensureReady();

    final uuidPtr = uuid.toNativeUtf8();

    final res = _coreSetColor(_ctx!, uuidPtr, value);

    calloc.free(uuidPtr);

    if (res != 0) {
      _throwLastError(res);
    }
    _invalidateState(uuid);
    _stateController.add(uuid);
  }

  static void setTemperature(String uuid, double value) {
    _ensureReady();

    final uuidPtr = uuid.toNativeUtf8();

    final res = _coreSetTemperature(_ctx!, uuidPtr, value);

    calloc.free(uuidPtr);

    if (res != 0) {
      _throwLastError(res);
    }
    _invalidateState(uuid);
    _stateController.add(uuid);
  }

  static void setTemperatureFridge(String uuid, double value) {
    _ensureReady();

    final uuidPtr = uuid.toNativeUtf8();

    final res = _coreSetTemperatureFridge(_ctx!, uuidPtr, value);

    calloc.free(uuidPtr);

    if (res != 0) {
      _throwLastError(res);
    }
    _invalidateState(uuid);
    _stateController.add(uuid);
  }

  static void setTemperatureFreezer(String uuid, double value) {
    _ensureReady();

    final uuidPtr = uuid.toNativeUtf8();

    final res = _coreSetTemperatureFreezer(_ctx!, uuidPtr, value);

    calloc.free(uuidPtr);

    if (res != 0) {
      _throwLastError(res);
    }
    _invalidateState(uuid);
    _stateController.add(uuid);
  }

  static void setTime(String uuid, int value) {
    _ensureReady();

    final uuidPtr = uuid.toNativeUtf8();

    final res = _coreSetTime(_ctx!, uuidPtr, value);

    calloc.free(uuidPtr);

    if (res != 0) {
      _throwLastError(res);
    }
    _invalidateState(uuid);
    _stateController.add(uuid);
  }

  static void setColorTemperature(String uuid, int value) {
    _ensureReady();

    final uuidPtr = uuid.toNativeUtf8();

    final res = _coreSetColorTemperature(_ctx!, uuidPtr, value);

    calloc.free(uuidPtr);

    if (res != 0) {
      _throwLastError(res);
    }
    _invalidateState(uuid);
    _stateController.add(uuid);
  }

  static void setLock(String uuid, bool value) {
    _ensureReady();

    final uuidPtr = uuid.toNativeUtf8();

    final res = _coreSetLock(_ctx!, uuidPtr, value);

    calloc.free(uuidPtr);

    if (res != 0) {
      _throwLastError(res);
    }
    _invalidateState(uuid);
    _stateController.add(uuid);
  }

  static void setMode(String uuid, int value) {
    _ensureReady();

    final uuidPtr = uuid.toNativeUtf8();

    final res = _coreSetMode(_ctx!, uuidPtr, value);

    calloc.free(uuidPtr);

    if (res != 0) {
      _throwLastError(res);
    }
    _invalidateState(uuid);
    _stateController.add(uuid);
  }

  static void setPosition(String uuid, double value) {
    _ensureReady();

    final uuidPtr = uuid.toNativeUtf8();

    final res = _coreSetPosition(_ctx!, uuidPtr, value);

    calloc.free(uuidPtr);

    if (res != 0) {
      _throwLastError(res);
    }
    _invalidateState(uuid);
    _stateController.add(uuid);
  }

  static void simulateOnce() {
    _ensureReady();
    final res = _coreSimulate(_ctx!);
    if (res != 0) {
      _throwLastError(res);
    }
  }

  static void _onCoreEvent(
    Pointer<CoreEventNative> eventPtr,
    Pointer<Void> userData,
  ) {
    try {
      final e = eventPtr.ref;
      final uuid = _readFixedString(e.uuid, CORE_MAX_UUID);
      final mappedState = _mapState(e.state);

      final data = CoreEventData(
        type: e.type,
        uuid: uuid,
        state: mappedState,
        errorCode: e.errorCode,
      );

      _log(
        'event',
        'Core event type=${e.type} error=${e.errorCode}',
        uuid: uuid.isEmpty ? null : uuid,
      );

      _eventController.add(data);

      if (e.type == CoreEventType.CORE_EVENT_STATE_CHANGED) {
        _stateCache[uuid] = mappedState;
        _protocolConnectionByDevice[uuid] = ProtocolConnectionState.connected;
        _stateController.add(uuid);
      } else if (e.type == CoreEventType.CORE_EVENT_DEVICE_REMOVED) {
        _invalidateState(uuid);
        _modeLabelsByDevice.remove(uuid);
        _constraintsByDevice.remove(uuid);
        _assetByDevice.remove(uuid);
        _wifiProvisioningByDevice.remove(uuid);
        _wifiSsidByDevice.remove(uuid);
        _protocolConnectionByDevice.remove(uuid);
        _protocolByDevice.remove(uuid);
      }
    } catch (_) {}
  }
}
