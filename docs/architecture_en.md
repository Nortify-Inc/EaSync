# EaSync Project Architecture (English)

> Recent updates (2026-03-11): ONNX INT8 quantization helper added (`lib/ai/tools/quantize_model.py`), Q4/GPTQ guidance (`docs/Q4_GPTQ.md`), and Android build CMake fixes documented in `docs/ANDROID_BUILD_FIX.md`.

---

## 1. Overview
EaSync is a modular, intelligent home automation platform. It combines a modern Flutter UI, a robust native C++ core, and AI modules for device control, automation, pattern learning, and a virtual assistant. The project is designed for flexibility, security, extensibility, and easy integration.

---

## 2. Folder Structure

```
Project Root
├── assets/           # Device templates, images, mocks, configs
│   ├── acs.json      # Air conditioner template
│   ├── curtains.json # Curtains template
│   ├── fridges.json  # Fridge template
│   ├── heated_floors.json # Heated floors template
│   ├── lamps.json    # Lamp template
│   ├── locks.json    # Lock template
│   ├── mocks.json    # Device mock
│   └── images/       # Device images
├── lib/
│   ├── ai/           # Artificial Intelligence
│   │   ├── include/  # C++ headers (models, tokenizer, MoE, etc)
│   │   ├── models/   # Model implementations, scripts, tokenizer
│   │   ├── utils/    # Utility scripts (dataset, vocab)
│   │   ├── data/     # Vocabulary, commands, interactions
│   │   └── src/      # AI engine (chatModelRuntime.cpp)
│   ├── core/         # Native C++ core
│   │   ├── include/  # Core headers
│   │   ├── src/      # Core implementation
│   │   ├── drivers/  # Protocol drivers (BLE, WiFi, Zigbee, MQTT, Mock)
│   │   └── build/    # Build artifacts
│   └── ui/           # Flutter UI
│       ├── widgets/  # Reusable visual components
│       └── ...       # Pages: dashboard, manage, assistant, profiles, etc
├── docs/             # Documentation
│   ├── architecture_en.md
│   └── ...           # Other docs
├── android/, ios/, linux/, macos/, windows/, web/  # Platforms
```

---

## 3. Data Flow & Communication

### Device Templates & Discovery
- JSON templates are loaded from `assets/`.
- User registers/discovers devices via UI (`manage.dart`).
- UI calls `Bridge.registerDevice()` (Dart), which triggers the C++ core.
- Core validates, registers, and returns status/events.

#### Example Template
```json
{
  "name": "Lamp",
  "capabilities": ["on", "off", "dim"],
  "constrains": {"max_brightness": 100}
}
```

### Device Communication
- Native drivers implement protocols (BLE, WiFi, Zigbee, MQTT).
- Core manages connections, events, commands, telemetry.
- Events are propagated to Flutter via FFI (`bridge.dart`).

#### Main Flow Diagram
```
[Flutter UI] <-> [Bridge FFI] <-> [C++ Core] <-> [Drivers] <-> [Devices]
      |                |
      |                +---> [AI C++/Python] <-> [Scripts/Models]
      |
      +---> [Local Persistence]
```

### Assistant & AI
- User commands are sent from UI (`assistant.dart`) to `Bridge.aiExecuteCommandAsync()`.
- C++ core can trigger Python scripts for inference (`chatInferenceCli.py`).
- Results are returned to Flutter and shown to the user.

#### Example Command
> "Turn on the living room light and set brightness to 50%"

### Pattern Learning
- Usage patterns are saved in Flutter (`SharedPreferences`) and synced with the core.
- Functions like `Bridge.aiRecordPattern()` and `Bridge.aiObserveProfileApply()` ensure persistence and telemetry.

---

## 4. Module Details

### Flutter UI (`lib/ui`)
- **main.dart**: Entry point, initializes Bridge.
- **bridge.dart**: FFI interface, connects Dart to C++ core.
- **dashboard.dart, manage.dart, profiles.dart, assistant.dart**: Main pages.
- **handler.dart**: Exports shared modules.
- **widgets/**: Reusable visual components.

#### UI Flow Example
1. User accesses dashboard.
2. UI shows device status.
3. On "Add device", UI loads templates and calls Bridge.

### C++ Core (`lib/core`)
- **core.h / core.cpp**: Native API, device/event management.
- **drivers/**: Protocol implementations (BLE, WiFi, Zigbee, MQTT, Mock).
- **CMakeLists.txt**: Build configuration.

#### Drivers
- **ble.cpp**: Bluetooth Low Energy communication.
- **wifi.cpp**: WiFi communication.
- **zigbee.cpp**: Zigbee communication.
- **mqtt.cpp**: MQTT communication.
- **mock.cpp**: Device simulation.

### AI (`lib/ai`)
- **chatModelRuntime.cpp**: Inference engine.
- **models/**: Tokenizer, attention, feedforward, MoE, transformer, etc.
- **train_and_export.py**: Model training/export.
- **chatInferenceCli.py**: Python inference script.
- **data/**: Vocabulary, commands, interactions.

#### AI Flow Example
1. User sends voice command.
2. UI calls Bridge → C++ core → Python script.
3. Python script processes, returns response.
4. UI displays result.

---

## 5. FFI (Dart ↔ C++)
- Bridge centralizes all Dart/C++ calls.
- FFI signatures maintained in `bridge.dart` and `core.h`.
- Events, commands, responses are serialized/deserialized.
- Compatibility ensured by enums, structs, contracts.

#### FFI Example
- `Bridge.registerDevice()` → C++: `core_register_device()`
- `Bridge.aiExecuteCommandAsync()` → C++: `core_ai_execute_command_async()`
 - `Bridge.aiExecuteCommandAsync()` → AI runtime (separate): `ai_query_async_start()` / `ai_query_async_poll()` (exports in `libeasync_ai.so`)

Note: The AI/runtime APIs were split out of the main core — device management remains in `libeasync_core` (core_*) while model/AI functions live in a separate native library (`libeasync_ai`) with `ai_*` exports. `bridge.dart` opens both libraries and forwards calls accordingly.

---

## 6. Drivers & Protocols
- Each protocol has a dedicated driver (BLE, WiFi, Zigbee, MQTT).
- Drivers implement discovery, connection, send/receive data.
- Mock driver allows testing without hardware.
- Drivers are easily extensible: implement interface, register in core.

#### Typical Driver Interface
```cpp
class Driver {
public:
    virtual bool connect(const std::string& address) = 0;
    virtual bool send(const std::vector<uint8_t>& data) = 0;
    virtual std::vector<uint8_t> receive() = 0;
    virtual void disconnect() = 0;
};
```

---

## 7. AI & Models
- Models implemented in C++ and Python.
- Tokenizer, Attention, FeedForward, MoE, Transformer, etc.
- Python scripts for training/inference.
- Vocabulary and commands in `data/`.
- Training can be local or cloud.

#### Model Example
```cpp
class Transformer {
public:
    Transformer(int numLayers);
    std::vector<float> forward(const std::vector<float>& input);
    // ...
};
```

#### Tokenizer Example
```cpp
#include "tokenizer.hpp"
Tokenizer tokenizer("vocab.txt");
std::vector<int> ids = tokenizer.encode("turn on light");
std::string text = tokenizer.decode(ids);
```

#### MoE (Mixture of Experts)
- Dynamic routing of inputs to experts.
- Aggregates outputs.

---

## 8. Persistence & Telemetry
- Flutter uses `SharedPreferences` for local data.
- C++ core can save data to files or sync with UI.
- Usage, events, patterns are logged for AI.

#### Persistence Example
- User sets lighting routine.
- UI saves routine in `SharedPreferences`.
- Bridge syncs with core.

---

## 9. Development Workflows
- **Native build:** `cd lib/core && ./build.sh`
- **Flutter dependencies:** `flutter pub get`
- **Run app:** `flutter run -d linux --target lib/ui/main.dart`
- **Testing & analysis:** `flutter analyze`, `flutter test`
- **AI training:** `python3 lib/ai/models/train_and_export.py`

#### Tips
- Always run `flutter analyze` before commit.
- Use mock driver for hardware-free tests.
- Document new drivers/models.
- Use dataset scripts to expand vocabulary.
- Test FFI integration after core changes.

---

## 10. Conventions, Patterns & Security
- Docblocks in all files (`@file`, `@brief`, etc).
- Enum/constant names match core originals.
- Do not bypass Bridge for native calls.
- Asset schema fields kept as original.
- Drivers isolated by protocol.
- Centralized FFI interface.
- Python scripts can be updated without recompiling core.
- Modular UI, easy to expand.
- Access control/authentication via drivers or UI.
- Logging/telemetry for traceability.
- Unit/integration tests.

#### Docblock Example
```cpp
/**
 * @file transformer.hpp
 * @author Radmann
 * @brief Transformer model for AI.
 */
```

---

## 11. Critical File References
- `lib/ui/bridge.dart`: FFI contract, device/AI orchestration.
- `lib/core/include/core.h` & `lib/core/src/core.cpp`: Native API.
- `lib/ui/manage.dart`: Device registration/discovery.
- `lib/ui/assistant.dart`: Assistant UX & telemetry.
- `lib/ai/src/chatModelRuntime.cpp` & `lib/ai/models/chatInferenceCli.py`: Python inference boundary.

---

## 12. Use Cases & Examples

### Routine Automation
- User sets lighting routine for 6pm.
- UI saves routine.
- Core executes routine automatically.

### Voice Control
- User says: "Lock the front door".
- Assistant interprets, triggers lock driver.

### New Device Integration
- Developer implements driver for presence sensor.
- Registers driver in core.
- UI shows sensor status.

---

## 13. APIs, Contracts & Integrations

### FFI API
- Contracts in `bridge.dart` and `core.h`.
- Methods: register, command, query, telemetry.

### Driver API
- Standard interface for drivers.
- Methods: connect, send, receive, disconnect.

### AI API
- Tokenizer, inference, training.
- Python & C++ scripts.

---

## 14. Advanced Tips & Best Practices
- Use logs to track events.
- Implement unit tests for drivers/models.
- Document every new feature.
- Use mocks for hardware-free tests.
- Expand AI vocabulary as new devices are added.
- Use visual themes for UI customization.
- Ensure security in network drivers.
- Use telemetry to improve AI.

---

## 15. Contribution, Contact & Community
- Documentation/examples in `docs/`.
- Follow docblock/architecture standards.
- Pull requests/suggestions welcome.
- Always document new modules, drivers, models.
- Use clear, explanatory comments.
- Test all integrations before production.
- Join the EaSync community.

---

## 16. References & Resources
- [Flutter](https://flutter.dev/)
- [C++](https://isocpp.org/)
- [MQTT](https://mqtt.org/)
- [Zigbee](https://zigbeealliance.org/)
- [Python](https://python.org/)
- [SharedPreferences Flutter](https://pub.dev/packages/shared_preferences)

---

_EaSync: Smart, modular, extensible, and easy-to-integrate home automation._

---

# Appendix: Code Examples & Diagrams

## Tokenizer Example (C++)
```cpp
#include "tokenizer.hpp"
Tokenizer tokenizer("vocab.txt");
std::vector<int> ids = tokenizer.encode("turn on light");
std::string text = tokenizer.decode(ids);
```

## BLE Driver Example
```cpp
#include "ble.hpp"
BLEDriver ble;
ble.connect("AA:BB:CC:DD:EE:FF");
ble.send({0x01, 0x02});
std::vector<uint8_t> resp = ble.receive();
ble.disconnect();
```

## Bridge FFI Example (Dart)
```dart
final result = await Bridge.registerDevice(template);
if (result.success) {
  print("Device registered!");
}
```

## Full Flow Diagram
```
[User] → [Flutter UI] → [Bridge] → [C++ Core] → [Driver] → [Device]
           ↘︎ [AI C++/Python] ↙︎
           ↘︎ [Local Persistence] ↙︎
```

## Docblock Example
```cpp
/**
 * @file feedForward.hpp
 * @author Radmann
 * @brief Feedforward layer for transformer model.
 */
```

## Telemetry Example
```cpp
void logEvent(const std::string& event) {
    std::ofstream log("telemetry.log", std::ios::app);
    log << event << std::endl;
}
```

## Unit Test Example
```cpp
#include "gtest/gtest.h"
TEST(DriverTest, ConnectTest) {
    Driver d;
    ASSERT_TRUE(d.connect("127.0.0.1"));
}
```

---

# End of Documentation
