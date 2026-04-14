// ignore_for_file: no_leading_underscores_for_local_identifiers

/*!
 * @file bridge.dart
 * @brief FFI layer between Flutter and the EaSync Core native library.
 * @param uuid Device identifier used in control calls.
 * @return Public methods return states/lists or throw exceptions on failures.
 * @author Erick Radmann
 */

import '../handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart' as crypto;

String _loadedCoreLibraryPath = 'libeasync_core.so';

DynamicLibrary _openCoreLibrary() {
  if (Platform.isWindows) {
    _loadedCoreLibraryPath = 'core.dll';
    return DynamicLibrary.open('core.dll');
  }

  if (Platform.isLinux) {
    final executableDir = File(Platform.resolvedExecutable).parent.path;
    final cwd = Directory.current.path;

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
        _loadedCoreLibraryPath = path;
        return lib;
      } catch (_) {}
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

String _readCStringSafe(Pointer<Int8> outBuf, int outLen) {
  if (outLen <= 0) return '';
  final bytes = outBuf.cast<Uint8>().asTypedList(outLen);
  var end = 0;
  while (end < bytes.length && bytes[end] != 0) {
    end++;
  }
  if (end == 0) return '';
  return utf8.decode(bytes.sublist(0, end), allowMalformed: true);
}

Uint8List _readCStringBytes(Pointer<Int8> outBuf, int outLen) {
  if (outLen <= 0) return Uint8List(0);
  final bytes = outBuf.cast<Uint8>().asTypedList(outLen);
  var end = 0;
  while (end < bytes.length && bytes[end] != 0) {
    end++;
  }
  if (end == 0) return Uint8List(0);
  return Uint8List.fromList(bytes.sublist(0, end));
}

int _utf8SafePrefixLength(List<int> data) {
  if (data.isEmpty) return 0;

  // Try full payload first. If it fails, trim up to 3 trailing bytes,
  // which is enough to recover from a split UTF-8 code point across chunks.
  final maxTrim = data.length < 3 ? data.length : 3;
  for (var trim = 0; trim <= maxTrim; trim++) {
    final len = data.length - trim;
    if (len <= 0) continue;
    try {
      utf8.decode(data.sublist(0, len), allowMalformed: false);
      return len;
    } catch (_) {}
  }

  // If decoding still fails, do not keep unbounded junk in pending buffer.
  return data.length;
}

class _Utf8ChunkDecoder {
  final List<int> _pending = <int>[];

  String decode(Uint8List bytes) {
    if (bytes.isEmpty && _pending.isEmpty) return '';

    final merged = <int>[..._pending, ...bytes];
    _pending.clear();

    final prefixLen = _utf8SafePrefixLength(merged);
    if (prefixLen <= 0) {
      _pending.addAll(merged);
      return '';
    }

    final ready = merged.sublist(0, prefixLen);
    if (prefixLen < merged.length) {
      _pending.addAll(merged.sublist(prefixLen));
    }

    try {
      return utf8.decode(ready, allowMalformed: false);
    } catch (_) {
      return utf8.decode(ready, allowMalformed: true);
    }
  }

  String flush() {
    if (_pending.isEmpty) return '';
    final out = utf8.decode(_pending, allowMalformed: true);
    _pending.clear();
    return out;
  }
}

typedef _aiQueryC =
    Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Int8>, Uint32);
typedef _aiQueryDart =
    int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Int8>, int);

final _aiQuery = aiLib.lookupFunction<_aiQueryC, _aiQueryDart>('ai_query');

String aiQuery(String prompt) {
  final input = prompt;
  final inPtr = input.toNativeUtf8();
  const outLen = 65536;
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
    final res = _readCStringSafe(outBuf, outLen);
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

typedef _aiSetDecodeEveryC = Int32 Function(Pointer<Void>, Int32);
typedef _aiSetDecodeEveryDart = int Function(Pointer<Void>, int);

typedef _aiSetSystemPromptC = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _aiSetSystemPromptDart = int Function(Pointer<Void>, Pointer<Utf8>);

final aiSetDecodeEvery = (() {
  try {
    return aiLib.lookupFunction<_aiSetDecodeEveryC, _aiSetDecodeEveryDart>(
      'ai_set_decode_every',
    );
  } catch (_) {
    return null;
  }
})();

final aiSetSystemPrompt = (() {
  try {
    return aiLib.lookupFunction<_aiSetSystemPromptC, _aiSetSystemPromptDart>(
      'ai_set_system_prompt',
    );
  } catch (_) {
    return null;
  }
})();

const String _kAiSystemPrompt =
    "You are Agent, an AI assistant created by Nortify Inc. "
    "Be quick and concise. Don't invent info.";

void _configureAiSystemPrompt() {
  if (aiSetSystemPrompt == null) return;
  final ptr = _kAiSystemPrompt.toNativeUtf8();
  try {
    final rc = aiSetSystemPrompt!(nullptr, ptr);
    print('[Bridge] ai_set_system_prompt rc=$rc');
  } catch (e) {
    print('[Bridge] ai_set_system_prompt failed: $e');
  } finally {
    malloc.free(ptr);
  }
}

bool _aiRuntimeReady = false;
Future<void>? _aiRuntimeInitFuture;

String? _findGgufInDir(String path) {
  try {
    final dir = Directory(path);
    if (!dir.existsSync()) return null;
    for (final e in dir.listSync(followLinks: false)) {
      if (e is File && e.path.toLowerCase().endsWith('.gguf')) {
        return e.path;
      }
    }
  } catch (_) {}
  return null;
}

Future<String> _prepareAiRuntime() async {
  if (_aiRuntimeReady) return '';

  if (_aiRuntimeInitFuture != null) {
    await _aiRuntimeInitFuture;
    return '';
  }

  String selectedDir = '';
  const requireSidecar = false;

  _aiRuntimeInitFuture = () async {
    selectedDir = await _ensureAiAssetsCopied(requireSidecar: requireSidecar);

    if (selectedDir.isNotEmpty &&
        !_aiDataDirLooksReady(selectedDir, requireSidecar: requireSidecar)) {
      print('[Bridge] Copied AI dir is incomplete: $selectedDir');
      selectedDir = '';
    }

    if (selectedDir.isEmpty) {
      selectedDir = _findLocalAiDataDir(requireSidecar: requireSidecar);
      if (selectedDir.isNotEmpty) {
        print('[Bridge] Using local AI data dir: $selectedDir');
      }
    }

    if (selectedDir.isEmpty) {
      throw Exception('AI data files missing. Required: model.gguf');
    }

    if (selectedDir.isNotEmpty && aiSetDataDir != null) {
      final dirPtr = selectedDir.toNativeUtf8();
      try {
        final rc = aiSetDataDir!(nullptr, dirPtr);
        print('[Bridge] ai_set_data_dir rc=$rc path=$selectedDir');
        if (rc != 0) {
          throw Exception('ai_set_data_dir failed rc=$rc path=$selectedDir');
        }
      } finally {
        malloc.free(dirPtr);
      }
    }

    _configureAiSystemPrompt();

    if (aiInitialize != null) {
      final rc = aiInitialize!(nullptr);
      print('[Bridge] ai_initialize rc=$rc');
      if (rc != 0) {
        throw Exception('ai_initialize failed rc=$rc');
      }
    }

    _aiRuntimeReady = true;
  }();

  try {
    await _aiRuntimeInitFuture;
  } finally {
    _aiRuntimeInitFuture = null;
  }

  return selectedDir;
}

bool _aiDataDirLooksReady(String path, {required bool requireSidecar}) {
  final fixed = File('$path/model.gguf').existsSync();
  if (fixed) return true;
  return _findGgufInDir(path) != null;
}

String _findLocalAiDataDir({required bool requireSidecar}) {
  try {
    final cwd = Directory.current;
    Directory dir = cwd;

    for (var i = 0; i < 10; i++) {
      final candidate = Directory('${dir.path}/lib/ai/data');
      final model = File('${candidate.path}/model.gguf');
      final anyGguf = _findGgufInDir(candidate.path) != null;

      if (candidate.existsSync() && (model.existsSync() || anyGguf)) {
        return candidate.path;
      }

      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
  } catch (_) {}

  return '';
}

Future<String> _ensureAiAssetsCopied({required bool requireSidecar}) async {
  List<String> entries = const <String>[];

  final support = await getApplicationSupportDirectory();
  final outDir = Directory('${support.path}/ai_data');

  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  // Downloader may have already saved the model in this directory.
  if (_aiDataDirLooksReady(outDir.path, requireSidecar: requireSidecar)) {
    return outDir.path;
  }

  try {
    final manifest = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> map = manifest.isNotEmpty
        ? Map<String, dynamic>.from(jsonDecode(manifest))
        : {};
    entries = map.keys.where((k) => k.startsWith('lib/ai/data/')).toList();
  } catch (e) {
    print('[Bridge] AssetManifest.json unavailable: $e');
  }

  if (entries.isEmpty) return '';

  var copiedAny = false;
  for (final assetPath in entries) {
    final rel = assetPath.substring('lib/ai/data/'.length);
    final outFile = File('${outDir.path}/$rel');
    if (outFile.existsSync()) {
      copiedAny = true;
      continue;
    }
    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      outFile.parent.createSync(recursive: true);
      await outFile.writeAsBytes(bytes, flush: true);
      copiedAny = true;
    } catch (e) {
      print('[Bridge] _ensureAiAssetsCopied failed for $assetPath: $e');
    }
  }

  if (!copiedAny) return '';
  if (!_aiDataDirLooksReady(outDir.path, requireSidecar: requireSidecar)) {
    return '';
  }

  return outDir.path;
}

Future<String> aiQueryAsync(String prompt, {int pollIntervalMs = 60}) async {
  await _prepareAiRuntime();

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

    final outLen = 65536;
    final outBuf = malloc.allocate<Int8>(outLen);
    final finishedFlag = malloc.allocate<Uint8>(1);
    final decoder = _Utf8ChunkDecoder();

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
          final res = decoder.decode(_readCStringBytes(outBuf, outLen));
          final tail = decoder.flush();
          final out = '$res$tail';
          print('[Bridge] aiQueryAsync: got result len=${out.length}');
          return out;
        }
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

Stream<String> aiQueryStream(String prompt, {int pollIntervalMs = 12}) {
  if (Platform.isAndroid) {
    return _aiQueryStreamMain(prompt, pollIntervalMs: pollIntervalMs);
  }

  final controller = StreamController<String>();
  final rp = ReceivePort();

  rp.listen((dynamic msg) {
    try {
      if (msg is Map) {
        if (msg.containsKey('chunk')) {
          final c = msg['chunk'];
          if (c is String) controller.add(c);
        }
        if (msg.containsKey('error')) {
          final e = msg['error'];
          controller.addError(e is String ? e : 'AI stream error');
        }
        if (msg.containsKey('done')) {
          controller.close();
        }
      }
    } catch (_) {}
  });

  Future<void>(() async {
    try {
      final dataDir = await _prepareAiRuntime();
      await Isolate.spawn(_aiQueryIsolateEntry, [
        rp.sendPort,
        prompt,
        pollIntervalMs,
        dataDir,
      ]);
    } catch (e, st) {
      print('[Bridge] Isolate.spawn failed: $e\n$st');
      controller.addError('AI isolate spawn failed');
      await controller.close();
    }
  });

  controller.onCancel = () {
    try {
      rp.close();
    } catch (_) {}
  };

  return controller.stream;
}

Stream<String> _aiQueryStreamMain(String prompt, {int pollIntervalMs = 12}) {
  final controller = StreamController<String>();

  Future<void>(() async {
    final decoder = _Utf8ChunkDecoder();
    final inPtr = prompt.toNativeUtf8();
    final handlePtr = malloc.allocate<Uint64>(sizeOf<Uint64>());
    try {
      await _prepareAiRuntime();

      final rc = _aiQueryStart(nullptr, inPtr, handlePtr);
      print('[Bridge] aiQueryStream(main): start rc=$rc');
      if (rc != 0) {
        controller.addError('AI async start failed (rc=$rc)');
        await controller.close();
        return;
      }

      final handle = handlePtr.value;
      final outLen = 65536;
      final outBuf = malloc.allocate<Int8>(outLen);
      final finishedFlag = malloc.allocate<Uint8>(1);

      var hasFirstChunk = false;
      var adaptivePollMs = 8;

      try {
        while (true) {
          final pollRc = _aiQueryPoll(
            nullptr,
            handle,
            finishedFlag,
            outBuf,
            outLen,
          );

          final resRaw = decoder.decode(_readCStringBytes(outBuf, outLen));
          final res = _sanitizeChunk(resRaw);

          if (res.isNotEmpty && !hasFirstChunk) {
            hasFirstChunk = true;
            adaptivePollMs = pollIntervalMs.clamp(4, 20);
          }

          if (pollRc == 1) {
            if (res.isNotEmpty) controller.add(res);
            await Future.delayed(Duration(milliseconds: adaptivePollMs));
            continue;
          }

          if (pollRc == 0) {
            if (res.isNotEmpty) controller.add(res);
            final tail = _sanitizeChunk(decoder.flush());
            if (tail.isNotEmpty) controller.add(tail);
            await controller.close();
            return;
          }

          await Future.delayed(Duration(milliseconds: adaptivePollMs));
        }
      } finally {
        malloc.free(outBuf);
        malloc.free(finishedFlag);
      }
    } catch (e, st) {
      print('[Bridge] aiQueryStream(main) failed: $e\n$st');
      controller.addError('AI stream failed');
      await controller.close();
    } finally {
      malloc.free(inPtr);
      malloc.free(handlePtr);
    }
  });

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
      : 80;
  final String dataDir = (args.length > 3 && args[3] != null)
      ? args[3] as String
      : '';

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

    int Function(Pointer<Void>, Pointer<Utf8>)? _aiSetDataDirLocal;
    try {
      _aiSetDataDirLocal = lib
          .lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Utf8>),
            int Function(Pointer<Void>, Pointer<Utf8>)
          >('ai_set_data_dir');
    } catch (_) {}

    int Function(Pointer<Void>)? _aiInitializeLocal;
    try {
      _aiInitializeLocal = lib
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('ai_initialize');
    } catch (_) {}

    int Function(Pointer<Void>, Pointer<Utf8>)? _aiSetSystemPromptLocal;
    try {
      _aiSetSystemPromptLocal = lib
          .lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Utf8>),
            int Function(Pointer<Void>, Pointer<Utf8>)
          >('ai_set_system_prompt');
    } catch (_) {}

    if (dataDir.isNotEmpty && _aiSetDataDirLocal != null) {
      final dirPtr = dataDir.toNativeUtf8();
      try {
        _aiSetDataDirLocal(nullptr, dirPtr);
      } finally {
        malloc.free(dirPtr);
      }
    }

    if (_aiInitializeLocal != null) {
      if (_aiSetSystemPromptLocal != null) {
        final sp = _kAiSystemPrompt.toNativeUtf8();
        try {
          _aiSetSystemPromptLocal(nullptr, sp);
        } finally {
          malloc.free(sp);
        }
      }
      _aiInitializeLocal(nullptr);
    }

    final inPtr = prompt.toNativeUtf8();
    final handlePtr = malloc.allocate<Uint64>(sizeOf<Uint64>());
    try {
      final decoder = _Utf8ChunkDecoder();
      final rc = _aiQueryStartLocal(nullptr, inPtr, handlePtr);
      if (rc != 0) {
        reply.send({'error': 'AI async start failed (rc=$rc)'});
        reply.send({'done': true});
        return;
      }
      final handle = handlePtr.value;
      final outLen = 65536;
      final outBuf = malloc.allocate<Int8>(outLen);
      final finishedFlag = malloc.allocate<Uint8>(1);
      var hasFirstChunk = false;
      var adaptivePollMs = 8;
      try {
        while (true) {
          final pollRc = _aiQueryPollLocal(
            nullptr,
            handle,
            finishedFlag,
            outBuf,
            outLen,
          );
          final resRaw = decoder.decode(_readCStringBytes(outBuf, outLen));
          final res = _sanitizeChunk(resRaw);

          if (res.isNotEmpty && !hasFirstChunk) {
            hasFirstChunk = true;
            adaptivePollMs = pollIntervalMs.clamp(4, 20);
          }

          if (pollRc == 1) {
            if (res.isNotEmpty) {
              reply.send({'chunk': res});
            }
            // continue streaming
            await Future.delayed(Duration(milliseconds: adaptivePollMs));
            continue;
          }
          if (pollRc == 0) {
            // final chunk
            if (res.isNotEmpty) {
              reply.send({'chunk': res});
            }
            final tail = _sanitizeChunk(decoder.flush());
            if (tail.isNotEmpty) {
              reply.send({'chunk': tail});
            }
            reply.send({'done': true});
            return;
          }
          // not ready: wait
          await Future.delayed(Duration(milliseconds: adaptivePollMs));
        }
      } finally {
        malloc.free(outBuf);
        malloc.free(finishedFlag);
      }
    } finally {
      malloc.free(inPtr);
      malloc.free(handlePtr);
    }
  } catch (e, st) {
    print('[Bridge] isolate generation failed: $e\n$st');
    try {
      reply.send({'error': 'AI isolate generation failed'});
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
const int CORE_MAX_USAGE_TITLE = 96;
const int CORE_MAX_USAGE_MESSAGE = 192;

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

base class CoreUsageStatsNative extends Struct {
  @Uint32()
  external int sampleCount;

  @Uint32()
  external int distinctDevices;

  @Int32()
  external int predictedArrivalHour;

  @Float()
  external double preferredTemperature;

  @Uint32()
  external int preferredBrightness;

  @Float()
  external double preferredPosition;

  @Array(CORE_MAX_UUID)
  external Array<Int8> mostActiveUuid;

  @Float()
  external double confidence;
}

base class CoreUsageRecommendationNative extends Struct {
  @Bool()
  external bool available;

  @Array(CORE_MAX_USAGE_TITLE)
  external Array<Int8> title;

  @Array(CORE_MAX_USAGE_MESSAGE)
  external Array<Int8> message;

  @Array(CORE_MAX_UUID)
  external Array<Int8> uuid;

  @Int32()
  external int recommendedHour;

  @Float()
  external double confidence;

  @Uint64()
  external int generatedAtMs;
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

typedef _coreSetDeviceEndpointC =
  Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _coreSetDeviceEndpointDart =
  int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);

typedef _coreSetDeviceCredentialC =
  Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _coreSetDeviceCredentialDart =
  int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);

typedef _coreSimulateC = Int32 Function(Pointer<Void>);
typedef _coreSimulateDart = int Function(Pointer<Void>);

typedef _coreUsageGetStatsC =
    Int32 Function(Pointer<Void>, Pointer<CoreUsageStatsNative>);
typedef _coreUsageGetStatsDart =
    int Function(Pointer<Void>, Pointer<CoreUsageStatsNative>);

typedef _coreUsageGetRecommendationC =
    Int32 Function(Pointer<Void>, Pointer<CoreUsageRecommendationNative>);
typedef _coreUsageGetRecommendationDart =
    int Function(Pointer<Void>, Pointer<CoreUsageRecommendationNative>);

typedef _coreUsageObserveFrontendJsonC =
    Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _coreUsageObserveFrontendJsonDart =
    int Function(Pointer<Void>, Pointer<Utf8>);

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

// AdaptiveLayer FFI bindings
typedef _coreEstablishConnectionC = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _coreEstablishConnectionDart = int Function(Pointer<Void>, Pointer<Utf8>);

typedef _coreEnsureConnectedC = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _coreEnsureConnectedDart = int Function(Pointer<Void>, Pointer<Utf8>);

typedef _coreDisconnectDeviceC = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _coreDisconnectDeviceDart = int Function(Pointer<Void>, Pointer<Utf8>);

typedef _coreGetConnectionStateC = Int32 Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Int8>,
  Uint32,
);
typedef _coreGetConnectionStateDart = int Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Int8>,
  int,
);

typedef _coreDiscoverDevicesC = Int32 Function(
  Pointer<Void>,
  Int32,
  Int32,
  Pointer<Int8>,
  Uint32,
  Pointer<Uint32>,
);
typedef _coreDiscoverDevicesDart = int Function(
  Pointer<Void>,
  int,
  int,
  Pointer<Int8>,
  int,
  Pointer<Uint32>,
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

final _coreSetDeviceEndpointDart? _coreSetDeviceEndpoint = (() {
  try {
    return coreLib
        .lookupFunction<_coreSetDeviceEndpointC, _coreSetDeviceEndpointDart>(
          'core_set_device_endpoint',
        );
  } catch (_) {
    return null;
  }
})();

final _coreSetDeviceCredentialDart? _coreSetDeviceCredential = (() {
  try {
    return coreLib
        .lookupFunction<_coreSetDeviceCredentialC, _coreSetDeviceCredentialDart>(
          'core_set_device_credential',
        );
  } catch (_) {
    return null;
  }
})();

// AdaptiveLayer bindings
final _coreEstablishConnectionDart? _coreEstablishConnection = (() {
  try {
    return coreLib.lookupFunction<
      _coreEstablishConnectionC,
      _coreEstablishConnectionDart
    >('core_establish_connection');
  } catch (_) {
    return null;
  }
})();

final _coreEnsureConnectedDart? _coreEnsureConnected = (() {
  try {
    return coreLib.lookupFunction<
      _coreEnsureConnectedC,
      _coreEnsureConnectedDart
    >('core_ensure_connected');
  } catch (_) {
    return null;
  }
})();

final _coreDisconnectDeviceDart? _coreDisconnectDevice = (() {
  try {
    return coreLib.lookupFunction<
      _coreDisconnectDeviceC,
      _coreDisconnectDeviceDart
    >('core_disconnect_device');
  } catch (_) {
    return null;
  }
})();

final _coreGetConnectionStateDart? _coreGetConnectionState = (() {
  try {
    return coreLib.lookupFunction<
      _coreGetConnectionStateC,
      _coreGetConnectionStateDart
    >('core_get_connection_state');
  } catch (_) {
    return null;
  }
})();

final _coreDiscoverDevicesDart? _coreDiscoverDevices = (() {
  try {
    return coreLib.lookupFunction<
      _coreDiscoverDevicesC,
      _coreDiscoverDevicesDart
    >('core_discover_devices');
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

final _coreUsageGetStatsDart? _coreUsageGetStats = (() {
  try {
    return coreLib.lookupFunction<_coreUsageGetStatsC, _coreUsageGetStatsDart>(
      'core_usage_get_stats',
    );
  } catch (_) {
    return null;
  }
})();

final _coreUsageGetRecommendationDart? _coreUsageGetRecommendation = (() {
  try {
    return coreLib.lookupFunction<
      _coreUsageGetRecommendationC,
      _coreUsageGetRecommendationDart
    >('core_usage_get_recommendation');
  } catch (_) {
    return null;
  }
})();

final _coreUsageObserveFrontendJsonDart? _coreUsageObserveFrontendJson = (() {
  try {
    return coreLib.lookupFunction<
      _coreUsageObserveFrontendJsonC,
      _coreUsageObserveFrontendJsonDart
    >('core_usage_observe_frontend_json');
  } catch (_) {
    return null;
  }
})();

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

class UsageStats {
  final int sampleCount;
  final int distinctDevices;
  final int predictedArrivalHour;
  final double preferredTemperature;
  final int preferredBrightness;
  final double preferredPosition;
  final String mostActiveUuid;
  final double confidence;

  const UsageStats({
    required this.sampleCount,
    required this.distinctDevices,
    required this.predictedArrivalHour,
    required this.preferredTemperature,
    required this.preferredBrightness,
    required this.preferredPosition,
    required this.mostActiveUuid,
    required this.confidence,
  });
}

class UsageRecommendation {
  final String title;
  final String message;
  final String uuid;
  final int recommendedHour;
  final double confidence;
  final DateTime generatedAt;

  const UsageRecommendation({
    required this.title,
    required this.message,
    required this.uuid,
    required this.recommendedHour,
    required this.confidence,
    required this.generatedAt,
  });

  String get signature =>
      '$title|$message|$uuid|$recommendedHour|${confidence.toStringAsFixed(2)}';
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
  final Map<String, dynamic> metadata;

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
    this.metadata = const {},
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

class OnboardingStage {
  static const String unknown = 'unknown';
  static const String registering = 'registering';
  static const String configuring = 'configuring';
  static const String provisioning = 'provisioning';
  static const String connecting = 'connecting';
  static const String ready = 'ready';
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

  final nativeMsg = err == nullptr ? '' : err.toDartString().trim();
  final msg = (nativeMsg.isEmpty || nativeMsg.toLowerCase() == 'no error')
      ? _coreFallbackMessage(code)
      : nativeMsg;

  throw Exception('Core error $code: $msg');
}

String _coreFallbackMessage(int code) {
  switch (code) {
    case CoreResult.CORE_NOT_SUPPORTED:
    case 5:
      return 'Protocol not supported by current native core build.';
    case CoreResult.CORE_PROTOCOL_UNAVAILABLE:
    case 7:
      return 'Protocol driver unavailable. Rebuild native core with required drivers.';
    case CoreResult.CORE_NOT_INITIALIZED:
    case 6:
      return 'Core is not initialized.';
    case CoreResult.CORE_ALREADY_EXISTS:
    case 3:
      return 'Device already exists.';
    case CoreResult.CORE_INVALID_ARGUMENT:
    case 4:
      return 'Invalid arguments for this core operation.';
    case CoreResult.CORE_NOT_FOUND:
    case 2:
      return 'Requested device/resource was not found.';
    case CoreResult.CORE_ERROR:
    case 1:
      return 'Generic core operation failure.';
    default:
      return 'Unknown core error.';
  }
}

class Bridge {
  static const String _kAiNotes = 'assistant.ai.notes.v1';

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
  static final Map<String, String> _onboardingStageByDevice = {};
  static final Map<String, String> _onboardingErrorByDevice = {};
  static final Map<String, int> _mideaApplianceIdByHost = {};
  static final Map<String, String> _mideaTokenByDevice = {};
  static final Map<String, String> _mideaKeyByDevice = {};
  static final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  static const String _mideaAppId = '1010';
  static const String _mideaClientType = '1';
  static const String _mideaFormat = '2';
  static const String _mideaLanguage = 'en_US';
  static const String _mideaSrc = '1010';
  static const String _mideaSignKey = 'xhdiwjnchekd4d512chdjx5d8e4c394D2D7S';
  static const String _mideaLoginKey = 'ac21b9f9cbfe4ca5a88562ef25e2b768';
  static const String _mideaApiBase =
      'https://mp-prod.appsmb.com/mas/v5/app/proxy?alias=';

  static String _mideaStampNow() {
    final now = DateTime.now().toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  static String _mideaSign(String endpoint, Map<String, String> payload) {
    final uri = Uri.parse('$_mideaApiBase$endpoint');
    final sortedEntries = payload.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final query = Uri(queryParameters: {
      for (final e in sortedEntries) e.key: e.value,
    }).query;

    final decoded = Uri.decodeQueryComponent(query.replaceAll('+', '%20'));
    final source = '${uri.path}$decoded$_mideaSignKey';
    return crypto.sha256.convert(utf8.encode(source)).toString();
  }

  static String _mideaEncryptPassword(String loginId, String password) {
    final first = crypto.sha256.convert(utf8.encode(password)).toString();
    final second = '$loginId$first$_mideaLoginKey';
    return crypto.sha256.convert(utf8.encode(second)).toString();
  }

  static String _mideaUdpIdFromInt(int id, {required Endian endian}) {
    final bb = ByteData(8);
    bb.setUint64(0, id, endian);
    final bytes = bb.buffer.asUint8List(0, 6);

    final digest = crypto.sha256.convert(bytes).bytes;
    final out = List<int>.filled(16, 0);
    for (var i = 0; i < 16; i++) {
      out[i] = digest[i] ^ digest[i + 16];
    }
    final b = StringBuffer();
    for (final v in out) {
      b.write(v.toRadixString(16).padLeft(2, '0'));
    }
    return b.toString();
  }

  static Future<Map<String, dynamic>?> _mideaApiRequest(
    String endpoint,
    Map<String, String> args, {
    String? sessionId,
  }) async {
    final payload = <String, String>{
      'appId': _mideaAppId,
      'format': _mideaFormat,
      'clientType': _mideaClientType,
      'language': _mideaLanguage,
      'src': _mideaSrc,
      'stamp': _mideaStampNow(),
      ...args,
    };
    if (sessionId != null && sessionId.isNotEmpty) {
      payload['sessionId'] = sessionId;
    }
    payload['sign'] = _mideaSign(endpoint, payload);

    final uri = Uri.parse('$_mideaApiBase$endpoint');
    final res = await http
        .post(uri, body: payload)
        .timeout(const Duration(seconds: 8));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      return null;
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) return null;
    return decoded;
  }

  static Map<String, dynamic>? _unwrapMideaResult(Map<String, dynamic>? root) {
    if (root == null) return null;

    final data = root['data'];
    if (data is Map<String, dynamic>) {
      final result = data['result'];
      if (result is Map<String, dynamic>) return result;
      return data;
    }

    final result = root['result'];
    if (result is Map<String, dynamic>) return result;
    return root;
  }

  static Future<void> _autoAcquireMideaCredentials({
    required String uuid,
    required String host,
    String? brand,
    String? model,
  }) async {
    final b = (brand ?? '').toLowerCase();
    final m = (model ?? '').toLowerCase();
    final isMidea = b.contains('midea') || m.contains('midea') || m.contains('nethome');
    if (!isMidea) return;

    if (_mideaTokenByDevice.containsKey(uuid) && _mideaKeyByDevice.containsKey(uuid)) {
      setDeviceCredential(uuid: uuid, key: 'token', value: _mideaTokenByDevice[uuid]!);
      setDeviceCredential(uuid: uuid, key: 'key', value: _mideaKeyByDevice[uuid]!);
      return;
    }

    final cachedToken = (await _secureStorage.read(key: 'vendor.midea.$uuid.token'))?.trim() ?? '';
    final cachedKey = (await _secureStorage.read(key: 'vendor.midea.$uuid.key'))?.trim() ?? '';
    if (cachedToken.isNotEmpty && cachedKey.isNotEmpty) {
      _mideaTokenByDevice[uuid] = cachedToken;
      _mideaKeyByDevice[uuid] = cachedKey;
      setDeviceCredential(uuid: uuid, key: 'token', value: cachedToken);
      setDeviceCredential(uuid: uuid, key: 'key', value: cachedKey);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final email = (prefs.getString('account.auth.email') ?? '').trim();
    final password = (await _secureStorage.read(key: 'account.password'))?.trim() ?? '';
    if (email.isEmpty || password.isEmpty) {
      return;
    }

    final applianceId = _mideaApplianceIdByHost[host];
    if (applianceId == null || applianceId <= 0) {
      return;
    }

    final loginIdRoot = await _mideaApiRequest(
      '/v1/user/login/id/get',
      {'loginAccount': email},
    );
    final loginIdData = _unwrapMideaResult(loginIdRoot);
    final loginId = (loginIdData?['loginId'] ?? '').toString().trim();
    if (loginId.isEmpty) return;

    final encryptedPassword = _mideaEncryptPassword(loginId, password);
    final loginRoot = await _mideaApiRequest(
      '/v1/user/login',
      {
        'loginAccount': email,
        'password': encryptedPassword,
      },
    );
    final loginData = _unwrapMideaResult(loginRoot);
    final sessionId = (loginData?['sessionId'] ?? '').toString().trim();
    if (sessionId.isEmpty) return;

    final udpIds = <String>{
      _mideaUdpIdFromInt(applianceId, endian: Endian.little),
      _mideaUdpIdFromInt(applianceId, endian: Endian.big),
    };

    for (final udpId in udpIds) {
      final tokenRoot = await _mideaApiRequest(
        '/v1/iot/secure/getToken',
        {'udpid': udpId},
        sessionId: sessionId,
      );
      final tokenData = _unwrapMideaResult(tokenRoot);
      final tokenList = tokenData?['tokenlist'];
      if (tokenList is! List) continue;

      for (final item in tokenList) {
        if (item is! Map) continue;
        final token = (item['token'] ?? '').toString().trim();
        final key = (item['key'] ?? '').toString().trim();
        if (token.isEmpty || key.isEmpty) continue;

        _mideaTokenByDevice[uuid] = token;
        _mideaKeyByDevice[uuid] = key;
        await _secureStorage.write(key: 'vendor.midea.$uuid.token', value: token);
        await _secureStorage.write(key: 'vendor.midea.$uuid.key', value: key);
        setDeviceCredential(uuid: uuid, key: 'token', value: token);
        setDeviceCredential(uuid: uuid, key: 'key', value: key);
        return;
      }
    }
  }
  static final Map<String, DeviceConnectionHealth> _healthByDevice = {};
  static final List<BridgeDiagnosticEntry> _diagnostics = [];

  static void _setOnboardingStage(
    String uuid,
    String stage, {
    String? error,
  }) {
    _onboardingStageByDevice[uuid] = stage;
    if (error != null && error.trim().isNotEmpty) {
      _onboardingErrorByDevice[uuid] = error.trim();
    } else if (stage != OnboardingStage.failed) {
      _onboardingErrorByDevice.remove(uuid);
    }

    _observeFrontendLearningEvent(
      'onboarding_stage',
      uuid: uuid,
      payload: {'stage': stage, 'error': _onboardingErrorByDevice[uuid]},
    );
    _log('onboarding', 'Stage -> $stage', uuid: uuid);
  }

  static String onboardingStage(String uuid) {
    return _onboardingStageByDevice[uuid] ?? OnboardingStage.unknown;
  }

  static String? onboardingError(String uuid) {
    final err = _onboardingErrorByDevice[uuid]?.trim() ?? '';
    return err.isEmpty ? null : err;
  }

  static String onboardingLabel(String uuid) {
    switch (onboardingStage(uuid)) {
      case OnboardingStage.registering:
        return 'Registering';
      case OnboardingStage.configuring:
        return 'Configuring';
      case OnboardingStage.provisioning:
        return 'Provisioning';
      case OnboardingStage.connecting:
        return 'Connecting';
      case OnboardingStage.ready:
        return 'Ready';
      case OnboardingStage.failed:
        return 'Failed';
      case OnboardingStage.unknown:
      default:
        return 'Unknown';
    }
  }

  static final StreamController<String> _stateController =
      StreamController.broadcast();

  static final StreamController<CoreEventData> _eventController =
      StreamController.broadcast();

  static final StreamController<Map<String, dynamic>>
  _frontendLearningEventController = StreamController.broadcast();

  static Pointer<NativeFunction<_coreEventTrampolineC>>? _eventCallbackPointer;

  static Timer? _simulateTimer;
  static Timer? _reconnectTimer;
  static bool _simulating = false;
  static final bool _enableAutoSimulation =
      (Platform.environment['EASYNC_ENABLE_SIMULATION'] == '1');

  static Stream<String> get onStateChanged => _stateController.stream;

  static Stream<CoreEventData> get onEvents => _eventController.stream;

  static Stream<Map<String, dynamic>> get onFrontendLearningEvents =>
      _frontendLearningEventController.stream;

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

  static void _requireRemoteControlPermission() {
    if (!EaAppSettings.instance.remoteCanControl) {
      throw Exception('Remote policy blocks device control on this instance.');
    }
  }

  static void _requireRemoteModifyPermission() {
    if (!EaAppSettings.instance.remoteCanModify) {
      throw Exception(
        'Remote policy blocks configuration changes on this instance.',
      );
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
          _log('core', 'Preloading AI model...');
          final aiDir = await _prepareAiRuntime();
          _log('core', 'AI runtime prepared at $aiDir');
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
    _onboardingStageByDevice.clear();
    _onboardingErrorByDevice.clear();
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

  static void _seedWifiCredentialsFromEnv({
    required String uuid,
    String? brand,
    String? model,
  }) {
    final b = (brand ?? '').toLowerCase();
    final m = (model ?? '').toLowerCase();
    final isMidea = b.contains('midea') || m.contains('midea') || m.contains('nethome');
    if (!isMidea) return;

    final env = Platform.environment;
    final suffix = uuid.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_').toUpperCase();

    final token = (env['EASYNC_MIDEA_TOKEN_$suffix'] ?? env['EASYNC_MIDEA_TOKEN'] ?? '').trim();
    final key = (env['EASYNC_MIDEA_KEY_$suffix'] ?? env['EASYNC_MIDEA_KEY'] ?? '').trim();

    if (token.isNotEmpty) {
      setDeviceCredential(uuid: uuid, key: 'token', value: token);
    }
    if (key.isNotEmpty) {
      setDeviceCredential(uuid: uuid, key: 'key', value: key);
    }
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
    _requireRemoteModifyPermission();
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
      _seedWifiCredentialsFromEnv(uuid: uuid, brand: brand, model: model);
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

    _observeFrontendLearningEvent(
      'device_registered',
      uuid: uuid,
      payload: {'protocol': protocol, 'capabilityCount': capabilities.length},
    );

    _log('device', 'Device registered', uuid: uuid);
  }

  static Future<void> onboardDevice({
    required String uuid,
    required String name,
    required int protocol,
    required List<int> capabilities,
    String? brand,
    String? model,
    List<String>? modeLabels,
    Map<String, dynamic>? constraints,
    String? assetPath,
    String? endpoint,
    Map<String, String>? credentials,
    String? wifiSsid,
    String? wifiPassword,
    bool rollbackOnFailure = true,
  }) async {
    var registered = false;
    _setOnboardingStage(uuid, OnboardingStage.registering);

    try {
      registerDevice(
        uuid: uuid,
        name: name,
        protocol: protocol,
        capabilities: capabilities,
        brand: brand,
        model: model,
        modeLabels: modeLabels,
        constraints: constraints,
        assetPath: assetPath,
      );
      registered = true;

      _setOnboardingStage(uuid, OnboardingStage.configuring);

      final endpointValue = endpoint?.trim() ?? '';
      if (endpointValue.isNotEmpty) {
        setDeviceEndpoint(uuid, endpointValue);
      }

      if (credentials != null && credentials.isNotEmpty) {
        for (final entry in credentials.entries) {
          final k = entry.key.trim();
          if (k.isEmpty) continue;
          setDeviceCredential(uuid: uuid, key: k, value: entry.value);
        }
      }

      if (protocol == CoreProtocol.CORE_PROTOCOL_WIFI) {
        final ssid = wifiSsid?.trim() ?? '';
        final pass = wifiPassword ?? '';

        if (ssid.isNotEmpty && pass.trim().isNotEmpty) {
          _setOnboardingStage(uuid, OnboardingStage.provisioning);
          await provisionWifi(uuid: uuid, ssid: ssid, password: pass);
        }

        _setOnboardingStage(uuid, OnboardingStage.connecting);
        var connected = false;
        for (var attempt = 0; attempt < 10; attempt++) {
          connected = refreshDeviceConnection(uuid);
          if (!connected) {
            connected = await _rebindWifiEndpointFromDiscovery(uuid);
          }
          if (!connected) {
            connected = establishProtocolConnection(uuid: uuid, protocol: protocol);
          }
          if (connected) break;
          await Future.delayed(const Duration(milliseconds: 1200));
        }

        if (!connected) {
          throw Exception('Device did not come online after Wi-Fi onboarding.');
        }
        _setOnboardingStage(uuid, OnboardingStage.ready);
        return;
      }

      _setOnboardingStage(uuid, OnboardingStage.connecting);
      var connected = false;
      for (var attempt = 0; attempt < 6; attempt++) {
        connected = establishProtocolConnection(uuid: uuid, protocol: protocol);
        if (connected) break;
        await Future.delayed(const Duration(milliseconds: 700));
      }

      if (!connected) {
        throw Exception('Protocol connection failed during onboarding.');
      }

      _setOnboardingStage(uuid, OnboardingStage.ready);
    } catch (e) {
      final errorText = e.toString();
      _setOnboardingStage(uuid, OnboardingStage.failed, error: errorText);

      if (rollbackOnFailure && registered) {
        try {
          removeDevice(uuid);
        } catch (_) {}

        // Preserve last onboarding failure for diagnostics even after rollback.
        _onboardingStageByDevice[uuid] = OnboardingStage.failed;
        _onboardingErrorByDevice[uuid] = errorText;
      }
      rethrow;
    }
  }

  static void removeDevice(String uuid) {
    _ensureReady();
    _requireRemoteModifyPermission();
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
    _onboardingStageByDevice.remove(uuid);
    _onboardingErrorByDevice.remove(uuid);
    _healthByDevice.remove(uuid);
    _observeFrontendLearningEvent('device_removed', uuid: uuid);
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

    if (_coreSetDeviceEndpoint == null || _ctx == null) {
      return;
    }

    final uuidPtr = uuid.toNativeUtf8();
    final endpointPtr = normalized.toNativeUtf8();
    try {
      final res = _coreSetDeviceEndpoint!(_ctx!, uuidPtr, endpointPtr);
      if (res != 0) {
        _log('wifi', 'Endpoint update rejected with code $res', uuid: uuid);
      }
    } finally {
      calloc.free(uuidPtr);
      calloc.free(endpointPtr);
    }

    final host = normalized.split(':').first.trim();
    DeviceInfo? info;
    try {
      info = listDevices().firstWhere((d) => d.uuid == uuid);
    } catch (_) {
      info = null;
    }
    final lowerBrand = info?.brand.toLowerCase() ?? '';
    final lowerModel = info?.model.toLowerCase() ?? '';
    final mideaLike = lowerBrand.contains('midea') ||
        lowerModel.contains('midea') ||
        lowerModel.contains('nethome') ||
        lowerModel.contains('msmart');

    if (host.isNotEmpty &&
        info != null &&
        info.protocol == CoreProtocol.CORE_PROTOCOL_WIFI &&
        mideaLike) {
      Future<void>(() async {
        await _autoAcquireMideaCredentials(
          uuid: uuid,
          host: host,
          brand: info?.brand,
          model: info?.model,
        );
      });
    }
  }

  static bool setDeviceCredential({
    required String uuid,
    required String key,
    required String value,
  }) {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty) return false;

    if (_coreSetDeviceCredential == null || _ctx == null) {
      return false;
    }

    final uuidPtr = uuid.toNativeUtf8();
    final keyPtr = normalizedKey.toNativeUtf8();
    final valuePtr = value.trim().toNativeUtf8();

    try {
      final res = _coreSetDeviceCredential!(_ctx!, uuidPtr, keyPtr, valuePtr);
      if (res != 0) {
        _log('wifi', 'Credential update rejected with code $res', uuid: uuid);
      }
      return res == 0;
    } finally {
      calloc.free(uuidPtr);
      calloc.free(keyPtr);
      calloc.free(valuePtr);
    }
  }

  static Future<bool> _rebindWifiEndpointFromDiscovery(String uuid) async {
    final found = await discoverDevices();
    final wifi = found
        .where((d) => d.protocol == CoreProtocol.CORE_PROTOCOL_WIFI)
        .toList();

    if (wifi.isEmpty) return false;

    wifi.sort((a, b) {
      final aMidea = a.vendor.toLowerCase().contains('midea') ? 1 : 0;
      final bMidea = b.vendor.toLowerCase().contains('midea') ? 1 : 0;
      if (aMidea != bMidea) return bMidea.compareTo(aMidea);
      return b.confidence.compareTo(a.confidence);
    });

    for (final candidate in wifi.take(6)) {
      setDeviceEndpoint(uuid, '${candidate.host}:${candidate.port}');
      if (refreshDeviceConnection(uuid)) {
        return true;
      }
    }

    return false;
  }

  static Future<List<String>> _guessSoftApGateways() async {
    final out = <String>[];
    final dynamicFirst = <String>[];

    void addUnique(String value) {
      final v = value.trim();
      if (v.isEmpty) return;
      if (!out.contains(v)) out.add(v);
    }

    void addDynamic(String value) {
      final v = value.trim();
      if (v.isEmpty) return;
      if (!dynamicFirst.contains(v)) dynamicFirst.add(v);
    }

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

          // If currently connected to a SoftAP-like private subnet,
          // prioritize that subnet gateway before generic defaults.
          if ((parts[0] == '192' && parts[1] == '168') || parts[0] == '10') {
            addDynamic('$prefix.1');
            addDynamic('$prefix.254');
          }
        }
      }
    } catch (_) {}

    for (final v in dynamicFirst) {
      addUnique(v);
    }

    // Then append common appliance SoftAP gateways.
    addUnique('192.168.4.1');
    addUnique('192.168.8.1');
    addUnique('192.168.10.1');
    addUnique('192.168.0.1');
    addUnique('192.168.1.1');
    addUnique('10.10.100.254');
    addUnique('10.0.0.1');

    return out;
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
    _requireRemoteModifyPermission();
    _log('wifi', 'Starting Wi-Fi provisioning', uuid: uuid);

    final ssidTrimmed = ssid.trim();
    if (ssidTrimmed.isEmpty || password.trim().isEmpty) {
      throw Exception('Wi-Fi credentials are required.');
    }

    markWifiApConnected(uuid);

    final guessedGateways = await _guessSoftApGateways();
    if (guessedGateways.isNotEmpty) {
      setDeviceEndpoint(uuid, guessedGateways.first);
    }

    if (_coreProvisionWifi == null) {
      markWifiCredentialsSent(uuid, ssid: ssidTrimmed);
      _log('wifi', 'Provision API unavailable', uuid: uuid);
      throw Exception(
        'Core provisioning API unavailable. Rebuild native core.',
      );
    }

    final provision = _coreProvisionWifi;
    final ctx = _ctx;
    if (provision == null || ctx == null || ctx == nullptr) {
      markWifiFailed(uuid);
      _protocolConnectionByDevice[uuid] = ProtocolConnectionState.failed;
      throw Exception('Core provisioning context unavailable.');
    }

    final uuidPtr = uuid.toNativeUtf8();
    final ssidPtr = ssidTrimmed.toNativeUtf8();
    final passwordPtr = password.toNativeUtf8();

    int res = CoreResult.CORE_ERROR;
    String provisionError = '';
    try {
      res = provision(ctx, uuidPtr, ssidPtr, passwordPtr);
      final errPtr = _coreLastError(ctx);
      provisionError = errPtr == nullptr ? '' : errPtr.toDartString().trim();
    } finally {
      calloc.free(uuidPtr);
      calloc.free(ssidPtr);
      calloc.free(passwordPtr);
    }

    if (res != 0) {
      markWifiFailed(uuid);
      _protocolConnectionByDevice[uuid] = ProtocolConnectionState.failed;
      _log('wifi', 'Provision failed with code $res', uuid: uuid);
      if (provisionError.isNotEmpty &&
          provisionError.toLowerCase() != 'no error') {
        throw Exception('Core error $res: $provisionError');
      }
      _throwLastError(res);
    }

    markWifiCredentialsSent(uuid, ssid: ssidTrimmed);
    _protocolConnectionByDevice[uuid] = ProtocolConnectionState.connecting;

    var connected = false;
    for (var i = 0; i < 5; i++) {
      await Future.delayed(const Duration(seconds: 2));
      connected = refreshDeviceConnection(uuid);
      if (!connected && i >= 1) {
        connected = await _rebindWifiEndpointFromDiscovery(uuid);
      }
      if (connected) break;
    }

    if (!connected) {
      _protocolConnectionByDevice[uuid] = ProtocolConnectionState.connecting;
      _log(
        'wifi',
        'Provision submitted; waiting for AP->LAN transition',
        uuid: uuid,
      );
      return;
    }

    markWifiOnline(uuid);
    _protocolConnectionByDevice[uuid] = ProtocolConnectionState.connected;
    _observeFrontendLearningEvent(
      'wifi_provisioned',
      uuid: uuid,
      payload: {'ssid': ssidTrimmed},
    );
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
      var available = isDeviceAvailable(uuid);
      if (!available && _coreEnsureConnected != null) {
        available = ensureConnected(uuid) && isDeviceAvailable(uuid);
      }
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
      if (d.vendor.toLowerCase().contains('midea')) {
        return await _checkTcp(d.host, 6444) || await _checkTcp(d.host, 6445);
      }
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
      final ok = provisioned && (ensureConnected(uuid) || refreshDeviceConnection(uuid));
      _protocolConnectionByDevice[uuid] = ok
          ? ProtocolConnectionState.connected
          : ProtocolConnectionState.disconnected;
      return ok;
    }

    if (connectToDevice(uuid)) {
      return refreshDeviceConnection(uuid);
    }

    return ensureConnected(uuid) || refreshDeviceConnection(uuid);
  }

  // ============================================================
  // AdaptiveLayer Integration
  // ============================================================

  /// Establish connection to a device using AdaptiveLayer.
  static bool connectToDevice(String uuid) {
    final ctx = _ctx;
    if (ctx == null || _coreEstablishConnection == null) return false;

    final uuidPtr = uuid.toNativeUtf8();
    try {
      final rc = _coreEstablishConnection!(ctx, uuidPtr);
      return rc == 0;
    } finally {
      malloc.free(uuidPtr);
    }
  }

  /// Ensure device is connected, reconnecting if needed.
  static bool ensureConnected(String uuid) {
    final ctx = _ctx;
    if (ctx == null || _coreEnsureConnected == null) return false;

    final uuidPtr = uuid.toNativeUtf8();
    try {
      final rc = _coreEnsureConnected!(ctx, uuidPtr);
      return rc == 0;
    } finally {
      malloc.free(uuidPtr);
    }
  }

  /// Disconnect from a device.
  static bool disconnectDevice(String uuid) {
    final ctx = _ctx;
    if (ctx == null || _coreDisconnectDevice == null) return false;

    final uuidPtr = uuid.toNativeUtf8();
    try {
      final rc = _coreDisconnectDevice!(ctx, uuidPtr);
      return rc == 0;
    } finally {
      malloc.free(uuidPtr);
    }
  }

  /// Get connection state label for a device.
  static String connectionStateLabel(String uuid) {
    final ctx = _ctx;
    if (ctx == null || _coreGetConnectionState == null) {
      return _protocolConnectionByDevice[uuid] ?? 'unknown';
    }

    const outLen = 64;
    final outBuf = malloc.allocate<Int8>(outLen);
    final uuidPtr = uuid.toNativeUtf8();

    try {
      final rc = _coreGetConnectionState!(ctx, uuidPtr, outBuf, outLen);
      if (rc != 0) {
        return _protocolConnectionByDevice[uuid] ?? 'unknown';
      }
      return _readCStringSafe(outBuf, outLen);
    } finally {
      malloc.free(uuidPtr);
      malloc.free(outBuf);
    }
  }

  /// Discover devices using native AdaptiveLayer backend.
  static Future<List<DiscoveredDevice>> discoverDevicesAdaptive({
    int protocol = CoreProtocol.CORE_PROTOCOL_MOCK,
    int timeoutMs = 5000,
  }) async {
    final ctx = _ctx;
    if (ctx == null || _coreDiscoverDevices == null) {
      return [];
    }

    const outLen = 131072; // 128KB
    final outBuf = malloc.allocate<Int8>(outLen);
    final outWrittenPtr = malloc.allocate<Uint32>(sizeOf<Uint32>());

    try {
      final rc = _coreDiscoverDevices!(
        ctx,
        protocol,
        timeoutMs,
        outBuf,
        outLen,
        outWrittenPtr,
      );

      if (rc != 0) {
        return [];
      }

      final outWritten = outWrittenPtr.value;
      final jsonStr = _readCStringSafe(outBuf, outWritten);

      try {
        final decoded = jsonDecode(jsonStr);
        if (decoded is! List) return [];

        return decoded.whereType<Map>().map((e) {
          final m = e.cast<String, dynamic>();
          final host = (m['host'] ?? '').toString();
          final port = (m['port'] is num) ? (m['port'] as num).toInt() : 0;
          final proto = (m['protocol'] is num)
            ? (m['protocol'] as num).toInt()
            : CoreProtocol.CORE_PROTOCOL_MOCK;
          return DiscoveredDevice(
          icon: proto == CoreProtocol.CORE_PROTOCOL_WIFI
            ? Icons.wifi_rounded
            : proto == CoreProtocol.CORE_PROTOCOL_BLE
              ? Icons.bluetooth_rounded
              : proto == CoreProtocol.CORE_PROTOCOL_ZIGBEE
                ? Icons.rotate_90_degrees_cw_rounded
                : Icons.sensors_rounded,
          id: (m['uuid'] ?? '').toString().isNotEmpty
            ? (m['uuid'] ?? '').toString()
            : '$proto:$host:$port',
          name: (m['name'] ?? 'Discovered Device').toString(),
          protocol: proto,
          host: host,
          port: port,
          hint: (m['hint'] ?? '').toString(),
          confidence: (m['confidence'] is num)
            ? (m['confidence'] as num).toDouble()
            : 0.5,
          vendor: (m['vendor'] ?? 'generic').toString(),
          metadata: const {},
          );
        }).toList();
      } catch (e) {
        print('[Bridge] discoverDevices JSON parse error: $e');
        return [];
      }
    } finally {
      malloc.free(outBuf);
      malloc.free(outWrittenPtr);
    }
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

  static bool _looksLikeMideaDiscoveryPacket(Uint8List payload) {
    if (payload.length >= 2) {
      if (payload[0] == 0x5a && payload[1] == 0x5a) return true;
      if (payload[0] == 0x83 && payload[1] == 0x70) return true;
    }

    if (payload.length >= 10) {
      if (payload[8] == 0x5a && payload[9] == 0x5a) return true;
    }

    return false;
  }

  static int? _extractMideaApplianceId(Uint8List payload) {
    if (payload.length < 26) return null;

    int? parseAt(Uint8List bytes, int offset) {
      if (offset + 6 > bytes.length) return null;
      final b = bytes.sublist(offset, offset + 6);
      var id = 0;
      for (var i = 0; i < 6; i++) {
        id |= (b[i] & 0xff) << (8 * i);
      }
      return id > 0 ? id : null;
    }

    // V2/V3 discovery usually carries appliance ID at [20..26] LE.
    final direct = parseAt(payload, 20);
    if (direct != null) return direct;

    // Some packets prepend 8-byte 8370 framing before the 5A5A body.
    if (payload.length > 34 && payload[8] == 0x5a && payload[9] == 0x5a) {
      final sliced = payload.sublist(8);
      return parseAt(sliced, 20);
    }

    return null;
  }

  static Future<Set<String>> _candidateBroadcastAddrs() async {
    final out = <String>{'255.255.255.255'};

    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length != 4) continue;
          out.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
        }
      }
    } catch (_) {}

    return out;
  }

  static Future<List<DiscoveredDevice>> _discoverMideaLanDevices() async {
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

    final found = <String, DiscoveredDevice>{};
    final broadcasts = await _candidateBroadcastAddrs();

    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? sub;

    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
      ).timeout(const Duration(milliseconds: 450));

      socket.broadcastEnabled = true;

      final done = Completer<void>();
      sub = socket.listen((event) {
        if (event != RawSocketEvent.read) return;

        while (true) {
          final dg = socket?.receive();
          if (dg == null) break;

          if (!_looksLikeMideaDiscoveryPacket(dg.data)) continue;

          final host = dg.address.address;
          final applianceId = _extractMideaApplianceId(dg.data);
          if (applianceId != null) {
            _mideaApplianceIdByHost[host] = applianceId;
          }
          final id = 'wifi-midea:$host:6444';
          found[id] = DiscoveredDevice(
            icon: Icons.kitchen_rounded,
            id: id,
            name: 'Midea LAN Device ($host)',
            protocol: CoreProtocol.CORE_PROTOCOL_WIFI,
            host: host,
            port: 6444,
            hint: 'Midea discovery response received (UDP 6445/20086)',
            confidence: 0.97,
            vendor: 'midea',
            metadata: applianceId == null
                ? const {}
                : {'mideaApplianceId': applianceId},
          );
        }
      });

      for (final b in broadcasts) {
        final addr = InternetAddress.tryParse(b);
        if (addr == null) continue;
        socket.send(probe, addr, 6445);
        socket.send(probe, addr, 20086);
      }

      Future.delayed(const Duration(milliseconds: 900), () {
        if (!done.isCompleted) done.complete();
      });

      await done.future;
    } catch (_) {
      // Best-effort discovery path.
    } finally {
      await sub?.cancel();
      socket?.close();
    }

    return found.values.toList();
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
    const mideaTcpPorts = [6444, 6445];
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

    final mideaChecks = await Future.wait(
      mideaTcpPorts.map((p) async => MapEntry(p, await _checkTcp(host, p))),
    );

    if (mideaChecks.any((e) => e.value)) {
      results.add(
        DiscoveredDevice(
          icon: Icons.kitchen_rounded,
          id: 'wifi-midea:$host:6444',
          name: 'Midea LAN Device ($host)',
          protocol: CoreProtocol.CORE_PROTOCOL_WIFI,
          host: host,
          port: 6444,
          hint: 'Midea LAN service detected (TCP 6444/6445)',
          confidence: 0.92,
          vendor: 'midea',
        ),
      );
    }

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
          vendor: mideaChecks.any((e) => e.value) || host.contains('midea')
              ? 'midea'
              : 'generic',
        ),
      );
    }

    return results;
  }

  static Future<List<DiscoveredDevice>> discoverDevices() async {
    _log('discovery', 'Starting network discovery');
    final discovered = <DiscoveredDevice>[];
    final seen = <String>{};

    final midea = await _discoverMideaLanDevices();
    for (final d in midea) {
      if (seen.add(d.id)) discovered.add(d);
    }

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
    _requireRemoteControlPermission();

    final uuidPtr = uuid.toNativeUtf8();

    final res = _coreSetPower(_ctx!, uuidPtr, value);

    calloc.free(uuidPtr);

    if (res != 0) {
      _throwLastError(res);
    }
    _invalidateState(uuid);
    _stateController.add(uuid);
    _observeFrontendLearningEvent(
      'device_control',
      uuid: uuid,
      payload: {'capability': 'power', 'value': value},
    );
  }

  static void setBrightness(String uuid, int value) {
    _ensureReady();
    _requireRemoteControlPermission();

    final uuidPtr = uuid.toNativeUtf8();

    final res = _coreSetBrightness(_ctx!, uuidPtr, value);

    calloc.free(uuidPtr);

    if (res != 0) {
      _throwLastError(res);
    }
    _invalidateState(uuid);
    _stateController.add(uuid);
    _observeFrontendLearningEvent(
      'device_control',
      uuid: uuid,
      payload: {'capability': 'brightness', 'value': value},
    );
  }

  static void setColor(String uuid, int value) {
    _ensureReady();
    _requireRemoteControlPermission();

    final uuidPtr = uuid.toNativeUtf8();

    final res = _coreSetColor(_ctx!, uuidPtr, value);

    calloc.free(uuidPtr);

    if (res != 0) {
      _throwLastError(res);
    }
    _invalidateState(uuid);
    _stateController.add(uuid);
    _observeFrontendLearningEvent(
      'device_control',
      uuid: uuid,
      payload: {'capability': 'color', 'value': value},
    );
  }

  static void setTemperature(String uuid, double value) {
    _ensureReady();
    _requireRemoteControlPermission();

    final uuidPtr = uuid.toNativeUtf8();

    final res = _coreSetTemperature(_ctx!, uuidPtr, value);

    calloc.free(uuidPtr);

    if (res != 0) {
      _throwLastError(res);
    }
    _invalidateState(uuid);
    _stateController.add(uuid);
    _observeFrontendLearningEvent(
      'device_control',
      uuid: uuid,
      payload: {'capability': 'temperature', 'value': value},
    );
  }

  static void setTemperatureFridge(String uuid, double value) {
    _ensureReady();
    _requireRemoteControlPermission();

    final uuidPtr = uuid.toNativeUtf8();

    final res = _coreSetTemperatureFridge(_ctx!, uuidPtr, value);

    calloc.free(uuidPtr);

    if (res != 0) {
      _throwLastError(res);
    }
    _invalidateState(uuid);
    _stateController.add(uuid);
    _observeFrontendLearningEvent(
      'device_control',
      uuid: uuid,
      payload: {'capability': 'temperature_fridge', 'value': value},
    );
  }

  static void setTemperatureFreezer(String uuid, double value) {
    _ensureReady();
    _requireRemoteControlPermission();

    final uuidPtr = uuid.toNativeUtf8();

    final res = _coreSetTemperatureFreezer(_ctx!, uuidPtr, value);

    calloc.free(uuidPtr);

    if (res != 0) {
      _throwLastError(res);
    }
    _invalidateState(uuid);
    _stateController.add(uuid);
    _observeFrontendLearningEvent(
      'device_control',
      uuid: uuid,
      payload: {'capability': 'temperature_freezer', 'value': value},
    );
  }

  static void setTime(String uuid, int value) {
    _ensureReady();
    _requireRemoteControlPermission();

    final uuidPtr = uuid.toNativeUtf8();

    final res = _coreSetTime(_ctx!, uuidPtr, value);

    calloc.free(uuidPtr);

    if (res != 0) {
      _throwLastError(res);
    }
    _invalidateState(uuid);
    _stateController.add(uuid);
    _observeFrontendLearningEvent(
      'device_control',
      uuid: uuid,
      payload: {'capability': 'timestamp', 'value': value},
    );
  }

  static void setColorTemperature(String uuid, int value) {
    _ensureReady();
    _requireRemoteControlPermission();

    final uuidPtr = uuid.toNativeUtf8();

    final res = _coreSetColorTemperature(_ctx!, uuidPtr, value);

    calloc.free(uuidPtr);

    if (res != 0) {
      _throwLastError(res);
    }
    _invalidateState(uuid);
    _stateController.add(uuid);
    _observeFrontendLearningEvent(
      'device_control',
      uuid: uuid,
      payload: {'capability': 'color_temperature', 'value': value},
    );
  }

  static void setLock(String uuid, bool value) {
    _ensureReady();
    _requireRemoteControlPermission();

    final uuidPtr = uuid.toNativeUtf8();

    final res = _coreSetLock(_ctx!, uuidPtr, value);

    calloc.free(uuidPtr);

    if (res != 0) {
      _throwLastError(res);
    }
    _invalidateState(uuid);
    _stateController.add(uuid);
    _observeFrontendLearningEvent(
      'device_control',
      uuid: uuid,
      payload: {'capability': 'lock', 'value': value},
    );
  }

  static void setMode(String uuid, int value) {
    _ensureReady();
    _requireRemoteControlPermission();

    final uuidPtr = uuid.toNativeUtf8();

    final res = _coreSetMode(_ctx!, uuidPtr, value);

    calloc.free(uuidPtr);

    if (res != 0) {
      _throwLastError(res);
    }
    _invalidateState(uuid);
    _stateController.add(uuid);
    _observeFrontendLearningEvent(
      'device_control',
      uuid: uuid,
      payload: {'capability': 'mode', 'value': value},
    );
  }

  static void setPosition(String uuid, double value) {
    _ensureReady();
    _requireRemoteControlPermission();

    final uuidPtr = uuid.toNativeUtf8();

    final res = _coreSetPosition(_ctx!, uuidPtr, value);

    calloc.free(uuidPtr);

    if (res != 0) {
      _throwLastError(res);
    }
    _invalidateState(uuid);
    _stateController.add(uuid);
    _observeFrontendLearningEvent(
      'device_control',
      uuid: uuid,
      payload: {'capability': 'position', 'value': value},
    );
  }

  static void simulateOnce() {
    _ensureReady();
    final res = _coreSimulate(_ctx!);
    if (res != 0) {
      _throwLastError(res);
    }
  }

  static UsageStats? usageStats() {
    _ensureReady();
    if (_coreUsageGetStats == null) return null;

    final out = calloc<CoreUsageStatsNative>();
    try {
      final rc = _coreUsageGetStats!(_ctx!, out);
      if (rc != 0) {
        _throwLastError(rc);
      }

      final raw = out.ref;
      return UsageStats(
        sampleCount: raw.sampleCount,
        distinctDevices: raw.distinctDevices,
        predictedArrivalHour: raw.predictedArrivalHour,
        preferredTemperature: raw.preferredTemperature,
        preferredBrightness: raw.preferredBrightness,
        preferredPosition: raw.preferredPosition,
        mostActiveUuid: _readFixedString(raw.mostActiveUuid, CORE_MAX_UUID),
        confidence: raw.confidence,
      );
    } finally {
      calloc.free(out);
    }
  }

  static UsageRecommendation? usageRecommendation() {
    _ensureReady();
    if (_coreUsageGetRecommendation == null) return null;

    final out = calloc<CoreUsageRecommendationNative>();
    try {
      final rc = _coreUsageGetRecommendation!(_ctx!, out);
      if (rc != 0) {
        _throwLastError(rc);
      }

      final raw = out.ref;
      if (!raw.available) return null;

      return UsageRecommendation(
        title: _readFixedString(raw.title, CORE_MAX_USAGE_TITLE),
        message: _readFixedString(raw.message, CORE_MAX_USAGE_MESSAGE),
        uuid: _readFixedString(raw.uuid, CORE_MAX_UUID),
        recommendedHour: raw.recommendedHour,
        confidence: raw.confidence,
        generatedAt: DateTime.fromMillisecondsSinceEpoch(raw.generatedAtMs),
      );
    } finally {
      calloc.free(out);
    }
  }

  static bool sendFrontendLearningEvent(Map<String, dynamic> event) {
    _ensureReady();
    if (_coreUsageObserveFrontendJson == null) return false;

    final payload = jsonEncode(event);
    final payloadPtr = payload.toNativeUtf8();
    try {
      final rc = _coreUsageObserveFrontendJson!(_ctx!, payloadPtr);
      if (rc != 0) {
        _throwLastError(rc);
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      calloc.free(payloadPtr);
    }
  }

  static void _observeFrontendLearningEvent(
    String type, {
    String? uuid,
    Map<String, dynamic>? payload,
  }) {
    final topLevelCapability = type == 'device_control'
        ? (payload?['capability'] ?? '').toString().trim()
        : '';

    final event = <String, dynamic>{
      'type': type,
      'atMs': DateTime.now().millisecondsSinceEpoch,
      if (uuid != null && uuid.trim().isNotEmpty) 'uuid': uuid,
      if (topLevelCapability.isNotEmpty) 'capability': topLevelCapability,
      if (payload != null && payload.isNotEmpty) 'payload': payload,
    };
    _frontendLearningEventController.add(event);

    _appendAiNoteFromFrontendEvent(type, uuid: uuid, payload: payload);

    if (!_shouldForwardLearningEvent(type, payload)) {
      return;
    }

    final settings = EaAppSettings.instance;
    if (!settings.telemetryEnabled || !settings.aiUseUsageHistory) {
      return;
    }
    sendFrontendLearningEvent(event);
  }

  static bool _shouldForwardLearningEvent(
    String type,
    Map<String, dynamic>? payload,
  ) {
    if (type == 'profile_applied' ||
        type == 'recommendation_shown' ||
        type == 'recommendation_accepted' ||
        type == 'recommendation_dismissed') {
      return true;
    }

    if (type != 'device_control') return false;

    final capability = (payload?['capability'] ?? '').toString().trim();
    if (capability.isEmpty) return false;

    return capability == 'temperature' ||
        capability == 'brightness' ||
        capability == 'color' ||
        capability == 'color_temperature' ||
        capability == 'position';
  }

  static Future<void> _appendAiNoteFromFrontendEvent(
    String type, {
    String? uuid,
    Map<String, dynamic>? payload,
  }) async {
    String? kind;
    String? title;
    String? message;

    if (type == 'profile_applied') {
      final profileName = (payload?['name'] ?? '').toString().trim();
      final actions = payload?['actionCount'];
      if (profileName.isEmpty) return;
      kind = 'profile_applied';
      title = 'Profile applied';
      message = '$profileName (${actions ?? 0} actions)';
    }

    if (kind == null || title == null || message == null) return;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAiNotes);
    final now = DateTime.now().millisecondsSinceEpoch;
    final nextEntry = <String, dynamic>{
      'id': '$now',
      'kind': kind,
      'title': title,
      'message': message,
      'createdAtMs': now,
    };

    final list = <Map<String, dynamic>>[];
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          list.addAll(
            decoded
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList(),
          );
        }
      } catch (_) {}
    }

    final nextSignature = '$kind|$title|$message';
    if (list.isNotEmpty) {
      final first = list.first;
      final sig =
          '${first['kind'] ?? ''}|${first['title'] ?? ''}|${first['message'] ?? ''}';
      if (sig == nextSignature) {
        return;
      }
    }

    list.insert(0, nextEntry);
    if (list.length > 120) {
      list.removeRange(120, list.length);
    }

    await prefs.setString(_kAiNotes, jsonEncode(list));
  }

  static void observeProfileApplied({
    required String profileName,
    required int actionCount,
    required List<String> deviceIds,
  }) {
    final normalizedName = profileName.trim();
    if (normalizedName.isEmpty) return;

    _observeFrontendLearningEvent(
      'profile_applied',
      payload: {
        'name': normalizedName,
        'actionCount': actionCount,
        'deviceCount': deviceIds.length,
        'deviceIds': deviceIds,
      },
    );
  }

  static void observeAppOpen({
    required String source,
    required bool aiEnabled,
  }) {
    _observeFrontendLearningEvent(
      'app_open',
      payload: {'source': source, 'aiEnabled': aiEnabled},
    );
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
