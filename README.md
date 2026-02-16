# 🚀 EaSync

> Everything Connected. One Interface.

EaSync is a unified platform for smart device control and automation, integrating multiple protocols into a single C++ backend with a modern Flutter interface.

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

### Backend (C++)

```bash
cd easync/lib/core
./build.sh

```