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

typedef _coreSimulateC = Int32 Function(Pointer<Void>);
typedef _coreSimulateDart = int Function(Pointer<Void>);

typedef _coreEventTrampolineC = Void Function(
  Pointer<CoreEventNative>,
  Pointer<Void>,
);

typedef _coreSetEventCallbackC = Int32 Function(
  Pointer<Void>,
  Pointer<NativeFunction<_coreEventTrampolineC>>,
  Pointer<Void>,
);

typedef _coreSetEventCallbackDart = int Function(
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

  static final StreamController<String> _stateController =
      StreamController.broadcast();

  static final StreamController<CoreEventData> _eventController =
      StreamController.broadcast();

  static Pointer<NativeFunction<_coreEventTrampolineC>>?
      _eventCallbackPointer;

    static Timer? _simulateTimer;
    static bool _simulating = false;

  static Stream<String> get onStateChanged => _stateController.stream;

  static Stream<CoreEventData> get onEvents => _eventController.stream;

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
    _simulateTimer ??=
        Timer.periodic(const Duration(milliseconds: 800), (_) async {
      if (_simulating || !_ready) return;
      _simulating = true;

      try {
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

    _eventCallbackPointer ??=
        Pointer.fromFunction<_coreEventTrampolineC>(_onCoreEvent);

    final cbRes = _coreSetEventCallback(
      _ctx!,
      _eventCallbackPointer!,
      nullptr,
    );

    if (cbRes != 0) {
      _throwLastError(cbRes);
    }

    _startSimulationLoop();

    _ready = true;
  }

  static void destroy() {
    _simulateTimer?.cancel();
    _simulateTimer = null;

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
          brand: _readFixedString(item.brand, CORE_MAX_BRAND),
          model: _readFixedString(item.model, CORE_MAX_MODEL),
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

      _eventController.add(data);

      if (e.type == CoreEventType.CORE_EVENT_STATE_CHANGED) {
        _stateCache[uuid] = mappedState;
        _stateController.add(uuid);
      } else if (e.type == CoreEventType.CORE_EVENT_DEVICE_REMOVED) {
        _invalidateState(uuid);
      }
    } catch (_) {
      // swallow errors to avoid crashing native callback
    }
  }
}
