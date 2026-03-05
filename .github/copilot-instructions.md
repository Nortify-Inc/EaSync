# Copilot instructions for EaSync

## Project architecture (read this first)
- EaSync is a Flutter UI + native C++ core project connected through FFI.
- Flutter entrypoint is `lib/ui/main.dart` (not `lib/main.dart`). `main()` calls `Bridge.init()` before rendering.
- The Dart/C++ boundary is centralized in `lib/ui/bridge.dart`. Keep FFI signatures in sync with `lib/core/include/core.h` and exported symbols in `lib/core/src/core.cpp`.
- Native core is built as `libeasync_core.so` from `lib/core/CMakeLists.txt`; drivers are protocol-specific under `lib/core/drivers/*.cpp`.
- UI pages (`lib/ui/dashboard.dart`, `lib/ui/manage.dart`, `lib/ui/profiles.dart`, `lib/ui/assistant.dart`) should use `Bridge` APIs rather than re-implementing transport logic.

## Data flow and responsibilities
- Device templates and constraints come from JSON assets (`assets/*.json`), loaded via `TemplateRepository` in `lib/ui/manage.dart`.
- Device lifecycle flow: template/discovery -> `Bridge.registerDevice()` -> optional `Bridge.establishProtocolConnection()` -> events on `Bridge.onEvents`.
- AI assistant flow: UI command in `assistant.dart` -> `Bridge.aiExecuteCommandAsync()` -> C++ AI engine/router -> optional Python model inference script.
- Pattern learning is persisted in Flutter local storage (`SharedPreferences`) and echoed to core through `Bridge.aiRecordPattern()` / `Bridge.aiObserveProfileApply()`.

## Native + AI integration details
- C++ core links MQTT/cURL/pthread and includes AI engine sources in the same shared library (`lib/core/CMakeLists.txt`).
- Chat inference script discovery happens in both Dart and C++:
  - Dart sets script path when available via `_configureChatInferenceScriptIfAvailable()`.
  - C++ runtime resolves Python and script with env overrides.
- Useful env vars for AI debugging:
  - `EASYNC_CHAT_INFER_SCRIPT` (explicit path to `chatInferenceCli.py`)
  - `EASYNC_CHAT_INFER_PYTHON` (python executable)

## Developer workflows (project-specific)
- Build native core first: `cd lib/core && ./build.sh`
- Flutter deps: `flutter pub get`
- Run app with explicit target: `flutter run -d linux --target lib/ui/main.dart`
- Static checks used in repo docs: `flutter analyze` and `flutter test`
- AI model scripts live in `lib/ai/models/`:
  - train: `python3 lib/ai/models/trainChatModel.py`
  - eval: `python3 lib/ai/models/evaluateChatModel.py`

## Conventions to follow when editing
- Keep existing docblock style (`@file`, `@brief`, etc.) in Dart/C++/scripts.
- Prefer updating `lib/ui/handler.dart` exports if adding new shared UI modules.
- Respect existing capability/protocol enums and naming from `core.h` and `bridge.dart` constants.
- Keep compatibility behavior in `bridge.dart` (new async AI symbols + legacy fallbacks).
- Preserve asset schema field names as-is (including existing `constrains` spelling used by UI/template parsing).
- Do not bypass `Bridge` with direct platform calls in UI code.

## High-impact files for orientation
- `lib/ui/bridge.dart` (FFI contract, library loading, device/AI orchestration)
- `lib/core/include/core.h` and `lib/core/src/core.cpp` (native API + behavior)
- `lib/ui/manage.dart` (template-driven registration/discovery)
- `lib/ui/assistant.dart` (assistant UX + behavior telemetry)
- `lib/ai/src/chatModelRuntime.cpp` and `lib/ai/models/chatInferenceCli.py` (Python inference boundary)
