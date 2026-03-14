# 🚀 EaSync

> Everything Connected. One Interface.

EaSync is a unified platform for smart device control and automation, integrating multiple protocols into a single C++ backend with a modern Flutter interface.

It includes a smart Assistant that learns real user patterns from device state changes and suggests automations/profiles based on learned behavior.

---

## 🌐 Technologies

- ![Flutter](https://img.shields.io/badge/Flutter-02569B?style=flat&logo=flutter&logoColor=white) Flutter
- ![C++](https://img.shields.io/badge/C%2B%2B-00599C?style=flat&logo=c%2B%2B&logoColor=white) C++
- ![Dart](https://img.shields.io/badge/Dart-0175C2?style=flat&logo=dart&logoColor=white) Dart
- ![CMake](https://img.shields.io/badge/CMake-064F8C?style=flat&logo=cmake&logoColor=white) CMake
- ![MQTT](https://img.shields.io/badge/MQTT-FF6F00?style=flat&logo=mqtt&logoColor=white) MQTT (Paho)
- ![Wi-Fi](https://img.shields.io/badge/Wi--Fi-29ABE2?style=flat&logo=wifi&logoColor=white) Wi-Fi (HTTP REST)
- ![ZigBee](https://img.shields.io/badge/ZigBee-FE7A20?style=flat&logo=zigbee&logoColor=white) ZigBee
- ![libcurl](https://img.shields.io/badge/libcurl-DA3434?style=flat&logo=curl&logoColor=white) libcurl
- ![pthread](https://img.shields.io/badge/POSIX_Threads-777777?style=flat&logo=linux&logoColor=white) POSIX Threads (pthread)
- ![FFI](https://img.shields.io/badge/FFI-6A1B9A?style=flat&logo=none) FFI (Dart ↔ C++)
- ![Linux](https://img.shields.io/badge/Linux-FCC624?style=flat&logo=linux&logoColor=black) Linux

---

## 💻 Languages

- ![Dart](https://img.shields.io/badge/Dart-0175C2?style=flat&logo=dart&logoColor=white) Dart
- ![C++](https://img.shields.io/badge/C%2B%2B-00599C?style=flat&logo=c%2B%2B&logoColor=white) C++
- ![CMake](https://img.shields.io/badge/CMake-064F8C?style=flat&logo=cmake&logoColor=white) CMake
- ![Bash](https://img.shields.io/badge/Bash-4EAA25?style=flat&logo=gnu-bash&logoColor=white) Bash
- ![JSON](https://img.shields.io/badge/JSON-000000?style=flat&logo=json&logoColor=white) JSON

---

## ⚡ Features

- Unified control of multiple smart devices  
- Support for MQTT, Wi-Fi/HTTP REST, and ZigBee protocols  
- Robust C++ backend with POSIX threads  
- Modern and responsive Flutter interface  
- Efficient Dart ↔ C++ communication via FFI  
- Modular: separate drivers for each device type  
- Real-time logging and state management  
- Easy extension for new devices and protocols
- AI Assistant with:
	- natural text command execution
	- Android voice command input
	- device-state Q&A (power, temperature, brightness, color, position, mode, lock)
	- pattern learning from real state changes
	- annotations based on learned usage
	- AI-driven profile recommendations based on user behavior

---

## 🗂 Project Structure

lib/  
├─ core/  
│ ├─ build/  
│ ├─ drivers/  
│ │ ├─ driver.hpp  
│ │ ├─ mock.cpp  
│ │ ├─ mock.hpp  
│ │ ├─ mqtt.cpp  
│ │ ├─ mqtt.hpp  
│ │ ├─ wifi.cpp  
│ │ ├─ wifi.hpp  
│ │ ├─ zigbee.cpp  
│ │ └─ zigbee.hpp  
│ ├─ include/  
│ │ └─ core.h  
│ └─ src/  
│ ├─ core.cpp  
│ └─ driver.cpp  
│  
├─ ui/  
│ ├─ assistant.dart  
│ ├─ bridge.dart  
│ ├─ bridge_test.dart  
│ ├─ dashboard.dart  
│ ├─ handler.dart  
│ ├─ home.dart  
│ ├─ main.dart  
│ ├─ manage.dart  
│ ├─ profiles.dart  
│ ├─ splash.dart  
│ └─ theme.dart  
│  
├─ build.sh  
└─ CMakeLists.txt  



---

## ⚙️ Installation

### 1) Backend nativo (C++) e runtime AI (separado)

O projeto agora separa o runtime de AI do core principal. O core nativo (drivers, device management) é construído em `lib/core` e produz `libeasync_core.so`. O runtime de AI (exportando as funções `ai_*`) vive em `lib/ai` e produz `libeasync_ai.so` — ambos são empacotados na APK/instalação quando configurados corretamente no Android Gradle/CMake.

Passos para compilar localmente os binários nativos (core + AI):

```bash
# Build do core + AI nativo
cd lib/
chmod +x build.sh
./build.sh


# Observação: no Android, o Gradle/CMake deve encontrar ambos os .so
# (libeasync_core.so e libeasync_ai.so) e empacotá-los em `android/app/src/main/jniLibs/`
```

### 2) Flutter dependencies

```bash
cd easync
flutter pub get
```

### 3) Run app

```bash
# Linux (desktop)
flutter run -d linux --target lib/ui/main.dart
```

Para Android (assegure que os .so nativos foram construídos e estão sendo empacotados):

```bash
flutter run -d android --target lib/ui/main.dart
```

> On Android, `libeasync_core.so` is built and packaged into the APK via
> `android/app/build.gradle.kts` + `lib/core/CMakeLists.txt`.
> The host Linux install path (`/usr/lib`) is **not** used on device.

## Recent updates (2026-03-11)

- Documented Android CMake fix for ONNX Runtime path normalization: `docs/ANDROID_BUILD_FIX.md`.

---

## 🧠 Assistant notes

- Voice recognition is currently enabled but not implemented yet for Android.
- Assistant recommendations and annotations improve over time as user/device interactions are observed.

---

## ✅ Development checks

```bash
flutter analyze
flutter test
```

## 🧱 Architecture overview

- Flutter UI layer in [lib/ui/assistant.dart](lib/ui/assistant.dart), [lib/ui/dashboard.dart](lib/ui/dashboard.dart), [lib/ui/manage.dart](lib/ui/manage.dart), [lib/ui/profiles.dart](lib/ui/profiles.dart)
- FFI bridge in [lib/ui/bridge.dart](lib/ui/bridge.dart)
- Native core and protocol drivers in [lib/core/src/core.cpp](lib/core/src/core.cpp) and [lib/core/drivers](lib/core/drivers)
- Platform runners in [linux/runner](linux/runner), [windows/runner](windows/runner), [android/app](android/app), [ios/Runner](ios/Runner)


---

## 🎙️ Assistant command examples

### Automation
- `turn on AC and set temperature 23`
- `set brightness 65 and color blue`
- `set curtains position 40`

### Device state Q&A
- `is living room lamp on?`
- `what color is kitchen lamp?`
- `what is AC temperature?`
- `curtain position?`
- `which devices are online?`

### Natural language variants
- `ela está ligada?`
- `qual a temperatura do ar?`
- `quais devices tenho?`

---

## 🧪 Testing and diagnostics

```bash
flutter test
flutter analyze
```

Useful files:
- bridge integration tests: [lib/ui/bridge_test.dart](lib/ui/bridge_test.dart)
- analysis rules: [analysis_options.yaml](analysis_options.yaml)

---

## 🛠 Troubleshooting

- If native symbols fail to load, rebuild core:

```bash
cd lib/core
./build.sh
```

- If dependencies are out of sync:

```bash
flutter clean
flutter pub get
```

- Voice commands unavailable on desktop:
	- expected behavior (voice recognition is Android-focused currently).

---

## 🗺 Roadmap

- Better room-aware disambiguation (automatic best-match by context)
- More advanced profile generation from long-term behavior
- Expanded protocol adapters and driver templates
- Cloud backup for user automation preferences
