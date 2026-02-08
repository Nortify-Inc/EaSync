#include <iostream>
#include <cstring>

#include <core.h>

static void printDeviceInfo(const CoreDeviceInfo& info) {
    std::cout << "\n[DEVICE INFO]\n";
    std::cout << "UUID: " << info.uuid << "\n";
    std::cout << "Name: " << info.name << "\n";
    std::cout << "Protocol: " << info.protocol << "\n";
    std::cout << "Capabilities: ";
    for (int i = 0; i < info.capabilityCount; i++) {
        std::cout << info.capabilities[i] << " ";
    }
    std::cout << "\n";
}

static void printState(const CoreDeviceState& s) {
    std::cout << "\n[DEVICE STATE]\n";
    std::cout << "Power: " << (s.power ? "ON" : "OFF") << "\n";
    std::cout << "Brightness: " << s.brightness << "\n";
    std::cout << "Color: 0x" << std::hex << s.color << std::dec << "\n";
    std::cout << "Temperature: " << s.temperature << "\n";
    std::cout << "Timestamp: " << s.timestamp << "\n";
}

static void onEvent(const CoreEvent* ev, void* userdata) {
    if (!ev) return;

    std::cout << "\n[EVENT] ";

    switch (ev->type) {
        case CORE_EVENT_DEVICE_ADDED:
            std::cout << "DEVICE_ADDED: ";
            break;
        case CORE_EVENT_STATE_CHANGED:
            std::cout << "STATE_CHANGED: ";
            break;
        case CORE_EVENT_DEVICE_REMOVED:
            std::cout << "DEVICE_REMOVED: ";
            break;
        case CORE_EVENT_ERROR:
            std::cout << "ERROR: ";
            break;
        default:
            std::cout << "UNKNOWN: ";
            break;
    }

    std::cout << ev->uuid << "\n";
}

static void inspectState(CoreContext* core, const char* uuid) {
    CoreDeviceState st{};
    CoreResult res = core_get_state(core, uuid, &st);
    if (res != CORE_OK) {
        std::cerr << "[ERROR] core_get_state failed -> lastError: "
                  << (core ? core_last_error(core) : "null core") << "\n";
    }
    printState(st);
}

static void checkResult(CoreContext* core, CoreResult res, const char* msg) {
    if (res != CORE_OK) {
        exit(1);
    }
}

int main() {

    std::cout << "=== EaSync Core Integration Test ===\n";

    CoreContext* core = core_create();
    if (!core) {
        std::cerr << "[ERROR] core_create failed\n";
        return 1;
    }

    CoreResult res = core_init(core);
    checkResult(core, res, "core_init");

    core_set_event_callback(core, onEvent, nullptr);

    /* Capabilities */
    CoreCapability caps[] = {
        CORE_CAP_POWER,
        CORE_CAP_BRIGHTNESS,
        CORE_CAP_COLOR
    };

    /* Register */
    std::cout << "\nRegistering device...\n";
    res = core_register_device(
        core,
        "lamp-001",
        "Kitchen Main Lamp",
        CORE_PROTOCOL_MOCK,
        caps,
        3
    );
    checkResult(core, res, "register_device");

    /* Info */
    CoreDeviceInfo info{};
    res = core_get_device(core, "lamp-001", &info);
    checkResult(core, res, "get_device");

    printDeviceInfo(info);

    /* Initial State */
    std::cout << "\nInitial state:\n";
    inspectState(core, "lamp-001");

    /* Power */
    std::cout << "\nSetting power ON...\n";
    res = core_set_power(core, "lamp-001", true);
    checkResult(core, res, "set_power");

    inspectState(core, "lamp-001");

    /* Brightness */
    std::cout << "\nSetting brightness to 80...\n";
    res = core_set_brightness(core, "lamp-001", 80);
    checkResult(core, res, "set_brightness");

    inspectState(core, "lamp-001");

    /* Color */
    std::cout << "\nSetting color to magenta...\n";
    res = core_set_color(core, "lamp-001", 0xFF00FF);
    checkResult(core, res, "set_color");

    inspectState(core, "lamp-001");

    /* Invalid Brightness */
    std::cout << "\nTrying invalid brightness...\n";
    res = core_set_brightness(core, "lamp-001", 200);
    if (res != CORE_INVALID_ARGUMENT) {
        std::cout << "[ERROR] set_brightness with invalid value did not return CORE_INVALID_ARGUMENT -> lastError: "
                  << (core ? core_last_error(core) : "null core") << "\n";
    }

    inspectState(core, "lamp-001");

    /* Remove */
    std::cout << "\nRemoving device...\n";
    res = core_remove_device(core, "lamp-001");
    checkResult(core, res, "remove_device");

    /* Access after remove */
    CoreDeviceState st{};
    res = core_get_state(core, "lamp-001", &st);
    if (res != CORE_NOT_FOUND) {
        std::cout << "[ERROR] get_state after remove did not return CORE_NOT_FOUND -> lastError: "
                  << (core ? core_last_error(core) : "null core") << "\n";
    }

    core_destroy(core);

    std::cout << "\n=== TESTS FINISHED ===\n";
    return 0;
}
