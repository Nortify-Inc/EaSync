How to run `bridge_test` as a pure Dart script

This project is a Flutter app, but `bridge` is plain Dart using `dart:ffi` and `dart:io`.

If you want to run the test as a standalone Dart CLI (no Flutter runner), use the included `bin/bridge_test.dart`.

Examples:

# If `libeasync_core.so` is in the repo under `lib/core/build` (adjust path as needed):
LD_LIBRARY_PATH=lib/core/build dart run bin/bridge_test.dart

# Or if the .so is in the current directory:
LD_LIBRARY_PATH=. dart run bin/bridge_test.dart

Notes:
- The `Gdk-Message` and "Connected to the VM Service" messages appear when using `flutter run` and are expected for the Flutter runner. Running with `dart run` will not invoke the Flutter runner.
- Ensure `libeasync_core.so` is the correct architecture (linux x64) and is accessible via `LD_LIBRARY_PATH` or in the working directory.
