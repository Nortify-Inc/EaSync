import 'dart:ffi';
import 'dart:io';
import 'dart:async';

import 'package:ffi/ffi.dart';

final DynamicLibrary coreLib = Platform.isWindows
    ? DynamicLibrary.open('core.dll')
    : DynamicLibrary.open('libeasync_core.so');

const String CORE_API_VERSION = "0.0.1";

const int CORE_MAX_CAPS = 16;
const int CORE_MAX_NAME = 64;
const int CORE_MAX_UUID = 64;

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
  static const int CORE_CAP_TIMESTAMP = 4;
}

class CoreEventType {
  static const int CORE_EVENT_DEVICE_ADDED = 0;
  static const int CORE_EVENT_DEVICE_REMOVED = 1;
  static const int CORE_EVENT_STATE_CHANGED = 2;
  static const int CORE_EVENT_ERROR = 3;
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

  @Uint64()
  external int timestamp;
}

base class CoreDeviceInfo extends Struct {
  @Array(CORE_MAX_UUID)
  external Array<Int8> uuid;

  @Array(CORE_MAX_NAME)
  external Array<Int8> name;

  @Int32()
  external int protocol;

  @Uint8()
  external int capabilityCount;

  @Array(CORE_MAX_CAPS)
  external Array<Int32> capabilities;
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

typedef _coreSetTimeC = Int32 Function(Pointer<Void>, Pointer<Utf8>, Uint64);
typedef _coreSetTimeDart = int Function(Pointer<Void>, Pointer<Utf8>, int);

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

final _coreSetPowerDart _coreSetPower = coreLib
    .lookupFunction<_coreSetPowerC, _coreSetPowerDart>('core_set_power');

final _coreRegisterDeviceDart _coreRegisterDevice = coreLib
    .lookupFunction<_coreRegisterDeviceC, _coreRegisterDeviceDart>(
      'core_register_device',
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

final _coreSetTimeDart _coreSetTime = coreLib
    .lookupFunction<_coreSetTimeC, _coreSetTimeDart>('core_set_time');

class DeviceInfo {
  final String uuid;
  final String name;
  final int protocol;
  final List<int> capabilities;

  DeviceInfo({
    required this.uuid,
    required this.name,
    required this.protocol,
    required this.capabilities,
  });
}

class DeviceState {
  final bool power;
  int brightness = 0;
  int color = 0xFFFFFFFF;
  double temperature = 0.0;
  int timestamp = 0;

  DeviceState({required this.power});
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

  static final StreamController<String> _stateController = StreamController.broadcast();

  static Stream<String> get onStateChanged => _stateController.stream;

  static void _ensureReady() {
    if (!_ready || _ctx == null) {
      throw Exception("Bridge not initialized. Call Bridge.init() first.");
    }
  }

  static Future<void> init() async {
    if (_ready) return;

    _ctx = _coreCreate();

    if (_ctx == nullptr || _ctx == null) {
      throw Exception('core_create failed');
    }

    final res = _coreInit(_ctx!);

    if (res != 0) {
      _throwLastError(res);
    }

    _ready = true;
  }

  static void destroy() {
    if (_ctx != null) {
      _coreDestroy(_ctx!);
      _ctx = null;
      _ready = false;
    }
  }

  static void registerDevice({
    required String uuid,
    required String name,
    required int protocol,
    required List<int> capabilities,
  }) {
    _ensureReady();

    final uuidPtr = uuid.toNativeUtf8();
    final namePtr = name.toNativeUtf8();

    final capsPtr = calloc<Int32>(capabilities.length);

    for (var i = 0; i < capabilities.length; i++) {
      capsPtr[i] = capabilities[i];
    }

    final res = _coreRegisterDevice(
      _ctx!,
      uuidPtr,
      namePtr,
      protocol,
      capsPtr,
      capabilities.length,
    );

    calloc.free(uuidPtr);
    calloc.free(namePtr);
    calloc.free(capsPtr);

    if (res != 0) {
      _throwLastError(res);
    }
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
          protocol: item.protocol,
          capabilities: caps,
        ),
      );
    }

    calloc.free(buffer);
    calloc.free(countPtr);

    return list;
  }

  static DeviceState getState(String uuid) {
    _ensureReady();

    final uuidPtr = uuid.toNativeUtf8();
    final statePtr = calloc<CoreDeviceState>();

    final res = _coreGetState(_ctx!, uuidPtr, statePtr);

    calloc.free(uuidPtr);

    if (res != 0) {
      calloc.free(statePtr);
      _throwLastError(res);
    }

    final s = statePtr.ref;

    final result = DeviceState(power: s.power);

    // Populate remaining fields so UI and tests receive full state
    try {
      result.brightness = s.brightness;
      result.color = s.color;
      result.temperature = s.temperature;
      result.timestamp = s.timestamp.toInt();
    } finally {
      calloc.free(statePtr);
    }

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
    _stateController.add(uuid);
  }
}
