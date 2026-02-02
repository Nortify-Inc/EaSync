import 'dart:ffi';
import 'package:ffi/ffi.dart';

final coreLib = DynamicLibrary.open('libcore.so');

final initCore = coreLib
    .lookup<NativeFunction<Void Function()>>('initCore')
    .asFunction<void Function()>();

final addTodo = coreLib
    .lookup<NativeFunction<Int32 Function(Pointer<Utf8>)>>('addTodo')
    .asFunction<int Function(Pointer<Utf8>)>();

final removeTodo = coreLib
    .lookup<NativeFunction<Void Function(Int32)>>('removeTodo')
    .asFunction<void Function(int)>();

final toggleTodo = coreLib
    .lookup<NativeFunction<Void Function(Int32)>>('toggleTodo')
    .asFunction<void Function(int)>();

final getTodoCount = coreLib
    .lookup<NativeFunction<Int32 Function()>>('getTodoCount')
    .asFunction<int Function()>();

final getTodo = coreLib
    .lookup<NativeFunction<Pointer<Utf8> Function(Int32)>>('getTodo')
    .asFunction<Pointer<Utf8> Function(int)>();
