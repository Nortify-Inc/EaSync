## Correção do build Android (ORT_ROOT / ONNX Runtime)

- Problema: durante o build Android o compilador NDK/Clang não encontrava o header `onnxruntime_cxx_api.h` apesar dos headers estarem em
  `lib/thirdParty/onnxruntime-android-1.20.1/headers`. Isso aconteceu porque o CMake recebeu um `ORT_ROOT` com segmentos relativos
  (ex.: `../../...`) que resultaram num caminho não resolvido/ignorado pelo compilador.

- Solução aplicada em `lib/CMakeLists.txt`:
  - Normalizei `ORT_ROOT` usando `get_filename_component(... REALPATH)` para obter o caminho absoluto.
  - Normalizei `ORT_INCLUDE` e `ORT_LIB` com `REALPATH` para garantir includes absolutos ao NDK.
  - Se o `ORT_ROOT` fornecido não existir, caio para o caminho de fallback do repositório: `lib/thirdParty/onnxruntime-android-1.20.1`.

- Efeito: o CMake passou a expor corretamente o include directory para o NDK, eliminando o erro de "file not found" e o build Android
  (`flutter build apk` / `flutter run`) completou com sucesso produzindo `build/app/outputs/flutter-apk/app-debug.apk`.

- Observações:
  - Se desejar forçar outro `onnxruntime` use `-DORT_ROOT=/caminho/para/onnxruntime` ou a variável de ambiente `ORT_ROOT`.
  - Mantive a detecção tolerante para não abortar o configure caso a .so final precise ser empacotada manualmente em `jniLibs`.

Comandos úteis:

```bash
# rebuildar e testar APK
flutter clean
flutter build apk -t lib/ui/main.dart --debug --no-shrink -v

# instalar manualmente no dispositivo (alternativa ao `flutter run` install step)
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb logcat -d | tail -n 200
```

Arquivo alterado: `lib/CMakeLists.txt` (normalização de paths e fallback).
