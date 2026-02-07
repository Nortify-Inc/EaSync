/**
 * @file core.cpp
 * @brief Implementation of EaSync core system.
 *
 * Implements the internal runtime responsible for:
 * - Device registry
 * - State management
 * - Event dispatching
 * - Thread synchronization
 *
 * This layer is not exposed directly through FFI.
 */

#include "core.h"

#include <unordered_map>
#include <string>
#include <vector>
#include <mutex>
#include <cstring>


/* ============================================================
   Internal Structures
============================================================ */

/**
 * @brief Internal representation of a device.
 */
struct InternalDevice {

    /** Unique device identifier */
    std::string uuid;

    /** Human-readable name */
    std::string name;

    /** Communication protocol */
    EasProtocol protocol;

    /** Supported capabilities */
    std::vector<EasCapability> capabilities;

    /** Runtime device state */
    EasDeviceState state;
};


/**
 * @brief Core internal context.
 */
struct EasCore {

    /** Initialization flag */
    bool initialized = false;

    /** Device registry */
    std::unordered_map<std::string, InternalDevice> devices;

    /** Global mutex */
    std::mutex mutex;

    /** Last error string */
    std::string lastError;

    /** Event callback */
    EasEventCallback callback = nullptr;

    /** Userdata for callback */
    void* callbackUserdata = nullptr;
};


/* ============================================================
   Internal Helpers
============================================================ */

/**
 * @brief Store last error message.
 *
 * @param core Core context.
 * @param msg  Error message.
 */
static void setError(
    EasCore* core,
    const std::string& msg
) {
    if (core)
        core->lastError = msg;
}


/**
 * @brief Check if device supports a capability.
 *
 * @param dev Device descriptor.
 * @param cap Capability to test.
 *
 * @return true if supported.
 */
static bool hasCapability(
    const InternalDevice& dev,
    EasCapability cap
) {
    for (auto c : dev.capabilities) {
        if (c == cap)
            return true;
    }

    return false;
}


/**
 * @brief Emit event to registered callback.
 *
 * Centralized dispatcher for all core events.
 *
 * @param core Core context.
 * @param ev   Event descriptor.
 */
static void emitEvent(
    EasCore* core,
    const EasEvent& ev
) {

    if (!core)
        return;

    EasEventCallback cb = nullptr;
    void* userdata = nullptr;

    {
        std::lock_guard<std::mutex> lock(core->mutex);

        cb = core->callback;
        userdata = core->callbackUserdata;
    }

    if (cb) {
        cb(&ev, userdata);
    }
}



/**
 * @brief Initialize default state.
 *
 * @param dev Device descriptor.
 */
static void initDefaultState(
    InternalDevice& dev
) {

    dev.state.power = false;

    dev.state.brightness = -1;
    dev.state.color = 0;
    dev.state.temperature = -1.0f;
    dev.state.timestamp = 0;

    if (hasCapability(dev, EAS_CAP_BRIGHTNESS))
        dev.state.brightness = 0;

    if (hasCapability(dev, EAS_CAP_COLOR))
        dev.state.color = 0xFFFFFF;

    if (hasCapability(dev, EAS_CAP_TEMPERATURE))
        dev.state.temperature = 20.0f;
}


/* ============================================================
   Core Lifecycle
============================================================ */

/**
 * @brief Create core instance.
 *
 * @return Pointer to core context or NULL.
 */
EasCore* eas_core_create(void) {

    try {
        return new EasCore();
    }
    catch (...) {
        return nullptr;
    }
}


/**
 * @brief Destroy core instance.
 *
 * @param core Core context.
 */
void eas_core_destroy(EasCore* core) {

    if (!core)
        return;

    delete core;
}


/**
 * @brief Initialize core.
 *
 * @param core Core context.
 *
 * @return Result code.
 */
EasResult eas_core_init(EasCore* core) {

    if (!core)
        return EAS_INVALID_ARGUMENT;

    std::lock_guard<std::mutex> lock(core->mutex);

    core->initialized = true;

    core->lastError.clear();

    return EAS_OK;
}


/* ============================================================
   Device Management
============================================================ */

/**
 * @brief Register new device.
 *
 * @param core     Core context.
 * @param uuid     Device UUID.
 * @param name     Device name.
 * @param protocol Communication protocol.
 * @param caps     Capability array.
 * @param capCount Capability count.
 *
 * @return Result code.
 */
EasResult eas_core_register_device(
    EasCore* core,
    const char* uuid,
    const char* name,
    EasProtocol protocol,
    const EasCapability* caps,
    uint8_t capCount
) {

    if (!core || !uuid || !name || !caps)
        return EAS_INVALID_ARGUMENT;

    if (!core->initialized)
        return EAS_NOT_INITIALIZED;

    if (capCount > EAS_MAX_CAPS)
        return EAS_INVALID_ARGUMENT;

    std::lock_guard<std::mutex> lock(core->mutex);

    std::string id(uuid);

    if (core->devices.count(id)) {
        setError(core, "Device already exists");
        return EAS_ALREADY_EXISTS;
    }

    InternalDevice dev;

    dev.uuid = id;
    dev.name = name;
    dev.protocol = protocol;

    dev.capabilities.assign(caps, caps + capCount);

    initDefaultState(dev);

    core->devices[id] = std::move(dev);

    EasEvent ev{};
    ev.type = EAS_EVENT_DEVICE_ADDED;
    std::strncpy(ev.uuid, uuid, EAS_MAX_UUID - 1);

    emitEvent(core, ev);

    return EAS_OK;
}


/**
 * @brief Remove device.
 *
 * @param core Core context.
 * @param uuid Device UUID.
 *
 * @return Result code.
 */
EasResult eas_core_remove_device(
    EasCore* core,
    const char* uuid
) {

    if (!core || !uuid)
        return EAS_INVALID_ARGUMENT;

    if (!core->initialized)
        return EAS_NOT_INITIALIZED;

    std::lock_guard<std::mutex> lock(core->mutex);

    auto it = core->devices.find(uuid);

    if (it == core->devices.end()) {
        setError(core, "Device not found");
        return EAS_NOT_FOUND;
    }

    core->devices.erase(it);

    EasEvent ev{};
    ev.type = EAS_EVENT_DEVICE_REMOVED;
    std::strncpy(ev.uuid, uuid, EAS_MAX_UUID - 1);

    emitEvent(core, ev);

    return EAS_OK;
}


/**
 * @brief Get device info.
 *
 * @param core    Core context.
 * @param uuid    Device UUID.
 * @param outInfo Output buffer.
 *
 * @return Result code.
 */
EasResult eas_core_get_device(
    EasCore* core,
    const char* uuid,
    EasDeviceInfo* outInfo
) {

    if (!core || !uuid || !outInfo)
        return EAS_INVALID_ARGUMENT;

    if (!core->initialized)
        return EAS_NOT_INITIALIZED;

    std::lock_guard<std::mutex> lock(core->mutex);

    auto it = core->devices.find(uuid);

    if (it == core->devices.end())
        return EAS_NOT_FOUND;

    const InternalDevice& dev = it->second;

    std::memset(outInfo, 0, sizeof(EasDeviceInfo));

    std::strncpy(outInfo->uuid, dev.uuid.c_str(), EAS_MAX_UUID - 1);
    std::strncpy(outInfo->name, dev.name.c_str(), EAS_MAX_NAME - 1);

    outInfo->protocol = dev.protocol;

    outInfo->capabilityCount =
        (uint8_t)dev.capabilities.size();

    for (uint8_t i = 0; i < outInfo->capabilityCount; i++)
        outInfo->capabilities[i] = dev.capabilities[i];

    return EAS_OK;
}


/* ============================================================
   State Handling
============================================================ */

/**
 * @brief Get device state.
 *
 * @param core     Core context.
 * @param uuid     Device UUID.
 * @param outState Output state.
 *
 * @return Result code.
 */
EasResult eas_core_get_state(
    EasCore* core,
    const char* uuid,
    EasDeviceState* outState
) {

    if (!core || !uuid || !outState)
        return EAS_INVALID_ARGUMENT;

    if (!core->initialized)
        return EAS_NOT_INITIALIZED;

    std::lock_guard<std::mutex> lock(core->mutex);

    auto it = core->devices.find(uuid);

    if (it == core->devices.end())
        return EAS_NOT_FOUND;

    *outState = it->second.state;

    return EAS_OK;
}


/* ============================================================
   State Setters
============================================================ */

/**
 * @brief Set power state.
 *
 * @param core  Core context.
 * @param uuid  Device UUID.
 * @param value Power value.
 *
 * @return Result code.
 */
EasResult eas_core_set_power(
    EasCore* core,
    const char* uuid,
    bool value
) {

    if (!core || !uuid)
        return EAS_INVALID_ARGUMENT;

    std::lock_guard<std::mutex> lock(core->mutex);

    auto it = core->devices.find(uuid);

    if (it == core->devices.end())
        return EAS_NOT_FOUND;

    if (!hasCapability(it->second, EAS_CAP_POWER))
        return EAS_NOT_SUPPORTED;

    it->second.state.power = value;

    EasEvent ev{};
    ev.type = EAS_EVENT_STATE_CHANGED;
    std::strncpy(ev.uuid, uuid, EAS_MAX_UUID - 1);

    emitEvent(core, ev);

    return EAS_OK;
}


/**
 * @brief Set brightness.
 *
 * @param core  Core context.
 * @param uuid  Device UUID.
 * @param value Brightness value (0-100).
 *
 * @return Result code.
 */
EasResult eas_core_set_brightness(
    EasCore* core,
    const char* uuid,
    int value
) {

    if (!core || !uuid)
        return EAS_INVALID_ARGUMENT;

    if (value < 0 || value > 100)
        return EAS_INVALID_ARGUMENT;

    std::lock_guard<std::mutex> lock(core->mutex);

    auto it = core->devices.find(uuid);

    if (it == core->devices.end())
        return EAS_NOT_FOUND;

    if (!hasCapability(it->second, EAS_CAP_BRIGHTNESS))
        return EAS_NOT_SUPPORTED;

    it->second.state.brightness = value;

    EasEvent ev{};
    ev.type = EAS_EVENT_STATE_CHANGED;
    std::strncpy(ev.uuid, uuid, EAS_MAX_UUID - 1);

    emitEvent(core, ev);

    return EAS_OK;
}


/**
 * @brief Set color.
 *
 * @param core  Core context.
 * @param uuid  Device UUID.
 * @param value RGB color.
 *
 * @return Result code.
 */
EasResult eas_core_set_color(
    EasCore* core,
    const char* uuid,
    uint32_t value
) {

    if (!core || !uuid)
        return EAS_INVALID_ARGUMENT;

    std::lock_guard<std::mutex> lock(core->mutex);

    auto it = core->devices.find(uuid);

    if (it == core->devices.end())
        return EAS_NOT_FOUND;

    if (!hasCapability(it->second, EAS_CAP_COLOR))
        return EAS_NOT_SUPPORTED;

    it->second.state.color = value;

    EasEvent ev{};
    ev.type = EAS_EVENT_STATE_CHANGED;
    std::strncpy(ev.uuid, uuid, EAS_MAX_UUID - 1);

    emitEvent(core, ev);

    return EAS_OK;
}


/**
 * @brief Set temperature.
 *
 * @param core  Core context.
 * @param uuid  Device UUID.
 * @param value Temperature in Celsius.
 *
 * @return Result code.
 */
EasResult eas_core_set_temperature(
    EasCore* core,
    const char* uuid,
    float value
) {

    if (!core || !uuid)
        return EAS_INVALID_ARGUMENT;

    if (value < -50.0f || value > 100.0f)
        return EAS_INVALID_ARGUMENT;

    std::lock_guard<std::mutex> lock(core->mutex);

    auto it = core->devices.find(uuid);

    if (it == core->devices.end())
        return EAS_NOT_FOUND;

    if (!hasCapability(it->second, EAS_CAP_TEMPERATURE))
        return EAS_NOT_SUPPORTED;

    it->second.state.temperature = value;

    EasEvent ev{};
    ev.type = EAS_EVENT_STATE_CHANGED;
    std::strncpy(ev.uuid, uuid, EAS_MAX_UUID - 1);

    emitEvent(core, ev);

    return EAS_OK;
}


/* ============================================================
   Diagnostics / Events
============================================================ */

/**
 * @brief Get last error.
 *
 * @param core Core context.
 *
 * @return Error string.
 */
const char* eas_core_last_error(EasCore* core) {

    if (!core)
        return "Invalid core handle";

    return core->lastError.c_str();
}


/**
 * @brief Set event callback.
 *
 * @param core     Core context.
 * @param callback Event callback.
 * @param userdata User pointer.
 *
 * @return Result code.
 */
EasResult eas_core_set_event_callback(
    EasCore* core,
    EasEventCallback callback,
    void* userdata
) {

    if (!core)
        return EAS_INVALID_ARGUMENT;

    std::lock_guard<std::mutex> lock(core->mutex);

    core->callback = callback;
    core->callbackUserdata = userdata;

    return EAS_OK;
}
