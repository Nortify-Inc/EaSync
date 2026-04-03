import '../handler.dart';

const _kModelDataUrls = <String>[
  // Verified primary source.
  'https://media.githubusercontent.com/media/Nortify-Inc/EaSync/master/lib/ai/data/model.gguf',
  // Redirects to media host and can work as fallback.
  'https://github.com/Nortify-Inc/EaSync/raw/master/lib/ai/data/model.gguf',
];

const _kBundledAssets = <String>[];

const _kDownloadedFile = 'model.gguf';
const _kMinModelBytes = 50 * 1024 * 1024;

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
    if (_kBundledAssets.isEmpty) return;

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
    client.connectionTimeout = const Duration(seconds: 20);
    IOSink? sink;

    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(const Duration(minutes: 3));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      if (dest.existsSync()) dest.deleteSync();

      final total = response.contentLength;
      int received = 0;
      sink = dest.openWrite();

      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) yield received / total;
      }

      if (total > 0 && received < total) {
        throw Exception('Download interrupted ($received/$total bytes)');
      }

      await sink.flush();
      await sink.close();

      final size = dest.existsSync() ? dest.lengthSync() : 0;
      if (size < _kMinModelBytes) {
        throw Exception('Downloaded file is too small ($size bytes)');
      }
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client.close(force: true);
    }
  }

  static bool _looksValidModel(File file) {
    if (!file.existsSync()) return false;
    return file.lengthSync() >= _kMinModelBytes;
  }

  static Stream<double> _downloadModel(File dest) async* {
    final failures = <String>[];
    for (final url in _kModelDataUrls) {
      try {
        yield* _download(url, dest);
        return;
      } catch (e) {
        failures.add('$url -> $e');
        if (dest.existsSync()) {
          try {
            dest.deleteSync();
          } catch (_) {}
        }
      }
    }

    throw Exception('Model download failed on all URLs: ${failures.join(' | ')}');
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
        message: 'Preparing runtime…',
      );

      await _copyBundledAssets(dir);

      if (!_looksValidModel(weightFile)) {
        yield const DownloadState(
          status: DownloadStatus.downloading,
          progress: 0.0,
          message: 'Downloading model (~700 MB)…',
        );

        final tmp = File('${dir.path}/$_kDownloadedFile.tmp');

        try {
          await for (final p in _downloadModel(tmp)) {
            yield DownloadState(
              status: DownloadStatus.downloading,
              progress: p,
              message: 'Downloading… ${(p * 100).toStringAsFixed(1)}%',
            );
          }

          if (weightFile.existsSync()) weightFile.deleteSync();
          await tmp.rename(weightFile.path);

          if (!_looksValidModel(weightFile)) {
            throw Exception('Invalid model after download');
          }
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

      if (aiSetDataDir == null || aiInitialize == null) {
        throw Exception('AI runtime symbols are unavailable in this build');
      }

      final pathPtr = dir.path.toNativeUtf8();
      int rcSet;
      try {
        rcSet = aiSetDataDir!.call(nullptr, pathPtr);
      } finally {
        malloc.free(pathPtr);
      }
      debugPrint('[Downloader] ai_set_data_dir rc=$rcSet path=${dir.path}');
      if (rcSet != 0) {
        throw Exception('ai_set_data_dir failed rc=$rcSet');
      }

      final rc = aiInitialize!.call(nullptr);
      debugPrint('[Downloader] ai_initialize rc=$rc');
      if (rc != 0) {
        throw Exception('ai_initialize failed rc=$rc');
      }

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
    return _looksValidModel(File('${dir.path}/$_kDownloadedFile'));
  }

  static Future<void> clearCache() async {
    final dir = await _modelDir();
    for (final name in [_kDownloadedFile, 'model.gguf']) {
      final f = File('${dir.path}/$name');
      if (f.existsSync()) f.deleteSync();
    }
  }
}
