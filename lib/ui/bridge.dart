import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'dart:io';

/* ===========================================================
   LOAD LIB
=========================================================== */

final DynamicLibrary coreLib = Platform.isWindows
    ? DynamicLibrary.open('core.dll')
    : DynamicLibrary.open('libcore.so');

/* ===========================================================
   STRUCTS
=========================================================== */

base class CoreDeviceState extends Struct {
  @Bool()
  external bool power;

  @Int32()
  external int brightness;

  @Uint32()
  external int color;

  @Float()
  external double temperature;

  @Int64()
  external int timestamp;
}

base class CoreDeviceInfo extends Struct {
  @Array(64)
  external Array<Int8> uuid;

  @Array(64)
  external Array<Int8> name;

  @Int32()
  external int protocol;

  @Uint8()
  external int capabilityCount;

  @Array(8)
  external Array<Uint8> capabilities;
}

/* ===========================================================
   TYPEDEFS
=========================================================== */

typedef _coreCreateC = Pointer<Void> Function();
typedef _coreCreateDart = Pointer<Void> Function();

typedef _coreDestroyC = Void Function(Pointer<Void>);
typedef _coreDestroyDart = void Function(Pointer<Void>);

typedef _coreInitC = Int32 Function(Pointer<Void>);
typedef _coreInitDart = int Function(Pointer<Void>);

typedef _coreListDevicesC = Int32 Function(
  Pointer<Void>,
  Pointer<CoreDeviceInfo>,
  Uint32,
  Pointer<Uint32>,
);

typedef _coreListDevicesDart = int Function(
  Pointer<Void>,
  Pointer<CoreDeviceInfo>,
  int,
  Pointer<Uint32>,
);

typedef _coreGetStateC = Int32 Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<CoreDeviceState>,
);

typedef _coreGetStateDart = int Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<CoreDeviceState>,
);

typedef _coreSetPowerC = Int32 Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Bool,
);

typedef _coreSetPowerDart = int Function(
  Pointer<Void>,
  Pointer<Utf8>,
  bool,
);

/* ===========================================================
   BINDINGS
=========================================================== */

final _coreCreateDart _coreCreate =
    coreLib.lookupFunction<_coreCreateC, _coreCreateDart>('core_create');

final _coreDestroyDart _coreDestroy =
    coreLib.lookupFunction<_coreDestroyC, _coreDestroyDart>('core_destroy');

final _coreInitDart _coreInit =
    coreLib.lookupFunction<_coreInitC, _coreInitDart>('core_init');

final _coreListDevicesDart _coreListDevices =
    coreLib.lookupFunction<_coreListDevicesC, _coreListDevicesDart>(
        'core_list_devices');

final _coreGetStateDart _coreGetState =
    coreLib.lookupFunction<_coreGetStateC, _coreGetStateDart>('core_get_state');

final _coreSetPowerDart _coreSetPower =
    coreLib.lookupFunction<_coreSetPowerC, _coreSetPowerDart>('core_set_power');

/* ===========================================================
   HIGH LEVEL API
=========================================================== */

class Bridge {
  static Pointer<Void>? _ctx;

  static void init() {
    _ctx = _coreCreate();

    if (_ctx == nullptr) {
      throw Exception('Failed to create core context');
    }

    final res = _coreInit(_ctx!);

    if (res != 0) {
      throw Exception('core_init failed: $res');
    }
  }

  static void destroy() {
    if (_ctx != null) {
      _coreDestroy(_ctx!);
      _ctx = null;
    }
  }

  static List<CoreDeviceInfo> listDevices() {
    final countPtr = calloc<Uint32>();

    _coreListDevices(_ctx!, nullptr, 0, countPtr);

    final count = countPtr.value;

    final buffer = calloc<CoreDeviceInfo>(count);

    _coreListDevices(_ctx!, buffer, count, countPtr);

    final list = <CoreDeviceInfo>[];

    for (int i = 0; i < count; i++) {
      list.add(buffer[i]);
    }

    calloc.free(buffer);
    calloc.free(countPtr);

    return list;
  }

  static CoreDeviceState getState(String uuid) {
    final uuidPtr = uuid.toNativeUtf8();

    final state = calloc<CoreDeviceState>();

    final res = _coreGetState(_ctx!, uuidPtr, state);

    calloc.free(uuidPtr);

    if (res != 0) {
      calloc.free(state);
      throw Exception('getState failed: $res');
    }

    final copy = state.ref;

    calloc.free(state);

    return copy;
  }

  static void setPower(String uuid, bool value) {
    final uuidPtr = uuid.toNativeUtf8();

    final res = _coreSetPower(_ctx!, uuidPtr, value);

    calloc.free(uuidPtr);

    if (res != 0) {
      throw Exception('setPower failed: $res');
    }
  }
}
