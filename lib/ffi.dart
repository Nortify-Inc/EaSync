import 'dart:ffi';
import 'package:ffi/ffi.dart';

final coreLib = DynamicLibrary.open('libcore.so');

typedef CoreEventCallbackNative = Void Function(
  Int32 deviceId,
  Int32 capability,
  Int32 value,
);

typedef CoreEventCallbackDart = void Function(
  int deviceId,
  int capability,
  int value,
);

final init = coreLib
    .lookup<NativeFunction<Void Function()>>('init')
    .asFunction<void Function()>();

final shutdown = coreLib
    .lookup<NativeFunction<Void Function()>>('shutdown')
    .asFunction<void Function()>();

final registerCallback = coreLib
    .lookup<
        NativeFunction<
            Void Function(
              Pointer<NativeFunction<CoreEventCallbackNative>>,
            )>>('registerCallback')
    .asFunction<
        void Function(
          Pointer<NativeFunction<CoreEventCallbackNative>>,
        )>();

final registerDevice = coreLib
    .lookup<
        NativeFunction<
            Int32 Function(
              Int32,
              Pointer<Utf8>,
              Int32,
              Pointer<Utf8>,
            )>>('registerDevice')
    .asFunction<
        int Function(
          int,
          Pointer<Utf8>,
          int,
          Pointer<Utf8>,
        )>();

final removeDevice = coreLib
    .lookup<
        NativeFunction<
            Void Function(
              Int32,
              Pointer<Utf8>,
            )>>('removeDevice')
    .asFunction<
        void Function(
          int,
          Pointer<Utf8>,
        )>();

final setPower = coreLib
    .lookup<
        NativeFunction<
            Void Function(
              Int32,
              Int32,
            )>>('setPower')
    .asFunction<
        void Function(
          int,
          int,
        )>();

final getPower = coreLib
    .lookup<
        NativeFunction<
            Int32 Function(
              Int32,
            )>>('getPower')
    .asFunction<int Function(int)>();

final setCapability = coreLib
    .lookup<
        NativeFunction<
            Void Function(
              Int32,
              Int32,
              Int32,
            )>>('setCapability')
    .asFunction<
        void Function(
          int,
          int,
          int,
        )>();

final hasCapability = coreLib
    .lookup<
        NativeFunction<
            Int32 Function(
              Int32,
              Int32,
            )>>('hasCapability')
    .asFunction<int Function(int, int)>();

final sendEvent = coreLib
    .lookup<
        NativeFunction<
            Int32 Function(
              Int32,
              Int32,
              Int32,
            )>>('sendEvent')
    .asFunction<int Function(int, int, int)>();

final poll = coreLib
    .lookup<NativeFunction<Void Function()>>('poll')
    .asFunction<void Function()>();

void initCore() {
  init();
}
