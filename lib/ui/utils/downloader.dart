import '../handler.dart';

const _kModelDataUrl =
    'https://github.com/Nortify-Inc/EaSync/releases/download/v1.0.0-beta/model.onnx.data';

const _kBundledAssets = [
  'lib/ai/data/model.q4_0.bin',
  'lib/ai/data/model.quant.onnx',
  'lib/ai/data/model.onnx',
  'lib/ai/data/tokenizer.json',
];

const _kDownloadedFile = 'model.onnx.data';

enum DownloadStatus {
  checking,
  copyingAssets,
  downloading,
  initializing,
  ready,
  error,
}

class DownloadState {
  final DownloadStatus status;
  final double progress;
  final String message;

  const DownloadState({
    required this.status,
    this.progress = 0.0,
    this.message = '',
  });

  bool get isDone => status == DownloadStatus.ready;
  bool get isError => status == DownloadStatus.error;
}

class Downloader {
  static Future<Directory> _modelDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/ai_data');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static Future<void> _copyBundledAssets(Directory dir) async {
    for (final assetPath in _kBundledAssets) {
      final filename = assetPath.split('/').last;
      final dest = File('${dir.path}/$filename');
      if (dest.existsSync()) continue;
      final data = await rootBundle.load(assetPath);
      await dest.writeAsBytes(data.buffer.asUint8List(), flush: true);
    }
  }

  static Stream<double> _download(String url, File dest) async* {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final total = response.contentLength; // -1 if unknown
      int received = 0;
      final sink = dest.openWrite();
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) yield received / total;
      }
      await sink.flush();
      await sink.close();
    } finally {
      client.close(force: true);
    }
  }

  Stream<DownloadState> ensure() async* {
    yield const DownloadState(
      status: DownloadStatus.checking,
      message: 'Checking model…',
    );

    try {
      final dir = await _modelDir();
      final weightFile = File('${dir.path}/$_kDownloadedFile');

      yield const DownloadState(
        status: DownloadStatus.copyingAssets,
        message: 'Preparing assets…',
      );

      await _copyBundledAssets(dir);

      if (!weightFile.existsSync()) {
        yield const DownloadState(
          status: DownloadStatus.downloading,
          progress: 0.0,
          message: 'Downloading model (1.9 GB)…',
        );

        final tmp = File('${dir.path}/$_kDownloadedFile.tmp');

        try {
          await for (final p in _download(_kModelDataUrl, tmp)) {
            yield DownloadState(
              status: DownloadStatus.downloading,
              progress: p,
              message: 'Downloading… ${(p * 100).toStringAsFixed(1)}%',
            );
          }
          await tmp.rename(weightFile.path);
        } catch (e) {
          if (tmp.existsSync()) tmp.deleteSync();
          rethrow;
        }
      }

      yield const DownloadState(
        status: DownloadStatus.initializing,
        progress: 1.0,
        message: 'Loading model…',
      );



      final pathPtr = dir.path.toNativeUtf8();
      int? rcSet;
      try {
        rcSet = aiSetDataDir?.call(nullptr, pathPtr);
      } finally {
        malloc.free(pathPtr);
      }
      debugPrint('[Downloader] ai_set_data_dir rc=$rcSet path=${dir.path}');

      final _ = await Future<bool>(() async {
        await Future.delayed(Duration.zero);

        try {
          final rc = aiInitialize?.call(nullptr);
          debugPrint('[Downloader] ai_initialize rc=$rc');
          return rc == 0;
        } catch (e) {
          debugPrint('[Downloader] ai_initialize threw: $e');
          return false;
        }
      });
      yield const DownloadState(
        status: DownloadStatus.ready,
        progress: 1.0,
        message: 'Ready',
      );
    } catch (e) {
      yield DownloadState(status: DownloadStatus.error, message: 'Error: $e');
    }
  }

  static Future<bool> isReady() async {
    final dir = await _modelDir();
    return File('${dir.path}/$_kDownloadedFile').existsSync() &&
        File('${dir.path}/model.onnx').existsSync() &&
        File('${dir.path}/tokenizer.json').existsSync();
  }

  static Future<void> clearCache() async {
    final dir = await _modelDir();
    for (final name in [_kDownloadedFile, 'model.onnx', 'tokenizer.json']) {
      final f = File('${dir.path}/$name');
      if (f.existsSync()) f.deleteSync();
    }
  }
}
