/**
 * @file core.cpp
 * @brief EaSync Core Runtime Implementation.
 *
 * Responsibilities:
 * - Device registry
 * - Driver management
 * - State caching
 * - Event dispatch
 * - Thread safety
 *
 * This layer is NOT exposed directly through Foreign Function Integration.
 */

#include "core.h"
#include "driver.hpp"
#include "mock.hpp"

#include <unordered_map>
#include <string>
#include <vector>
#include <mutex>
#include <memory>
#include <cstring>


extern "C" {

/* ============================================================
   Internal Structures
   ============================================================ */

/**
 * @brief Internal representation of a device.
 */
struct InternalDevice {

    std::string uuid;

    std::string name;

    CoreProtocol protocol;

    std::vector<CoreCapability> capabilities;

    std::shared_ptr<EaSync::Driver> driver;

    CoreDeviceState state;
};


/**
 * @brief Core runtime context.
 */
struct CoreContext {

    bool initialized = false;

    std::unordered_map<std::string, InternalDevice> devices;

    std::unordered_map<
        CoreProtocol,
        std::shared_ptr<EaSync::MockDriver>
    > drivers;

    std::mutex mutex;

    std::string lastError;

    CoreEventCallback callback = nullptr;

    void* callbackUserdata = nullptr;
};

/* ============================================================
   Internal Helpers
   ============================================================ */

/**
 * @brief Store last error message.
 *
 * @param core Core context.
 * @param msg  Null-terminated error message.
 */
static void setError(
    CoreContext* core,
    const char* msg
) {

    if (!core)
        return;

    core->lastError = msg ? msg : "";
}


/**
 * @brief Check if device supports a capability.
 *
 * @param dev Device descriptor.
 * @param cap Capability to test.
 *
 * @return true if supported, false otherwise.
 */
static bool hasCapability(
    const InternalDevice& dev,
    CoreCapability cap
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
 * @param core Core context.
 * @param ev   Event payload.
 */
static void emitEvent(
    CoreContext* core,
    const CoreEvent& ev
) {
    if (!core)
        return;

    CoreEventCallback cb = core->callback;
    void* userdata = core->callbackUserdata;

    if (cb)
        cb(&ev, userdata);
}


/* ============================================================
   Core Lifecycle
   ============================================================ */

/**
 * @brief Create a new core runtime.
 *
 * @return Pointer to CoreContext or NULL on failure.
 */
CoreContext* core_create(void) {

    try {

        CoreContext* ctx = new CoreContext();

        ctx->drivers[CORE_PROTOCOL_WIFI] =
            std::make_shared<EaSync::MockDriver>();

        ctx->drivers[CORE_PROTOCOL_BLE] =
            std::make_shared<EaSync::MockDriver>();

        return ctx;
    }
    catch (...) {
        return nullptr;
    }
}


/**
 * @brief Destroy core runtime.
 *
 * @param core Core context.
 */
void core_destroy(CoreContext* core) {

    if (!core)
        return;

    delete core;
}


/**
 * @brief Initialize runtime and drivers.
 *
 * @param core Core context.
 *
 * @return CORE_OK on success.
 */
CoreResult core_init(CoreContext* core) {

    if (!core)
        return CORE_INVALID_ARGUMENT;

    std::lock_guard<std::mutex> lock(core->mutex);

    for (auto& pair : core->drivers) {

        if (!pair.second->init()) {

            setError(core, "Driver initialization failed");

            return CORE_ERROR;
        }
    }

    core->initialized = true;

    return CORE_OK;
}


/* ============================================================
   Device Management
   ============================================================ */

/**
 * @brief Register a new device.
 *
 * @param core      Core context.
 * @param uuid      Device unique identifier.
 * @param name      Device name.
 * @param protocol  Communication protocol.
 * @param caps      Capability array.
 * @param capCount  Number of capabilities.
 *
 * @return CoreResult status.
 */
CoreResult core_register_device(
    CoreContext* core,
    const char* uuid,
    const char* name,
    CoreProtocol protocol,
    const CoreCapability* caps,
    uint8_t capCount
) {

    if (!core || !uuid || !name || !caps)
        return CORE_INVALID_ARGUMENT;

    if (!core->initialized)
        return CORE_NOT_INITIALIZED;

    if (capCount > CORE_MAX_CAPS)
        return CORE_INVALID_ARGUMENT;

    std::lock_guard<std::mutex> lock(core->mutex);

    if (core->devices.count(uuid))
        return CORE_ALREADY_EXISTS;

    if (!core->drivers.count(protocol))
        return CORE_NOT_SUPPORTED;

    InternalDevice dev;

    dev.uuid = uuid;
    dev.name = name;
    dev.protocol = protocol;

    dev.capabilities.assign(
        caps,
        caps + capCount
    );

    dev.driver = core->drivers[protocol];

    std::memset(&dev.state, 0, sizeof(CoreDeviceState));

    if (!dev.driver->connect(dev.uuid)) {

        setError(core, "Driver connection failed");

        return CORE_ERROR;
    }

    core->devices[dev.uuid] = dev;

    CoreEvent ev{};
    ev.type = CORE_EVENT_DEVICE_ADDED;

    std::strncpy(
        ev.uuid,
        uuid,
        CORE_MAX_UUID - 1
    );

    emitEvent(core, ev);

    return CORE_OK;
}


/**
 * @brief Retrieve static device metadata.
 *
 * Fills a CoreDeviceInfo structure with the registered
 * device information, including capabilities and protocol.
 *
 * @param core    Core context.
 * @param uuid    Device UUID.
 * @param outInfo Output buffer for device info.
 *
 * @return CORE_OK on success.
 * @return CORE_INVALID_ARGUMENT if parameters are invalid.
 * @return CORE_NOT_FOUND if device does not exist.
 */
CoreResult core_get_device(
    CoreContext* core,
    const char* uuid,
    CoreDeviceInfo* outInfo
) {

    if (!core || !uuid || !outInfo)
        return CORE_INVALID_ARGUMENT;

    std::lock_guard<std::mutex> lock(core->mutex);

    auto it = core->devices.find(uuid);

    if (it == core->devices.end())
        return CORE_NOT_FOUND;

    const InternalDevice& dev = it->second;

    std::memset(outInfo, 0, sizeof(CoreDeviceInfo));

    std::strncpy(outInfo->uuid, dev.uuid.c_str(), CORE_MAX_UUID - 1);
    std::strncpy(outInfo->name, dev.name.c_str(), CORE_MAX_NAME - 1);

    outInfo->protocol = dev.protocol;
    outInfo->capabilityCount = dev.capabilities.size();

    for (size_t i = 0; i < dev.capabilities.size(); i++) {
        outInfo->capabilities[i] = dev.capabilities[i];
    }

    return CORE_OK;
}


/**
 * @brief List all registered devices.
 *
 * Copies registered device metadata into the provided buffer.
 * If buffer is NULL, only the device count is returned.
 *
 * @param core     Core context.
 * @param buffer   Output array (may be NULL).
 * @param maxItems Maximum number of items in buffer.
 * @param outCount Number of devices found.
 *
 * @return CORE_OK on success.
 * @return CORE_INVALID_ARGUMENT if parameters are invalid.
 */
CoreResult core_list_devices(
    CoreContext* core,
    CoreDeviceInfo* buffer,
    uint32_t maxItems,
    uint32_t* outCount
) {

    if (!core || !outCount)
        return CORE_INVALID_ARGUMENT;

    std::lock_guard<std::mutex> lock(core->mutex);

    uint32_t count = 0;

    for (auto& pair : core->devices) {

        if (buffer && count < maxItems) {

            const InternalDevice& dev = pair.second;
            CoreDeviceInfo& info = buffer[count];

            std::memset(&info, 0, sizeof(CoreDeviceInfo));

            std::strncpy(info.uuid, dev.uuid.c_str(), CORE_MAX_UUID - 1);
            std::strncpy(info.name, dev.name.c_str(), CORE_MAX_NAME - 1);

            info.protocol = dev.protocol;
            info.capabilityCount = dev.capabilities.size();

            for (size_t i = 0; i < dev.capabilities.size(); i++) {
                info.capabilities[i] = dev.capabilities[i];
            }
        }

        count++;
    }

    *outCount = count;

    return CORE_OK;
}


/**
 * @brief Check if a device supports a capability.
 *
 * Verifies whether the specified device declares
 * support for a given capability.
 *
 * @param core      Core context.
 * @param uuid      Device UUID.
 * @param cap       Capability to test.
 * @param outResult Output result (true if supported).
 *
 * @return CORE_OK on success.
 * @return CORE_INVALID_ARGUMENT if parameters are invalid.
 * @return CORE_NOT_FOUND if device does not exist.
 */
CoreResult core_has_capability(
    CoreContext* core,
    const char* uuid,
    CoreCapability cap,
    bool* outResult
) {

    if (!core || !uuid || !outResult)
        return CORE_INVALID_ARGUMENT;

    std::lock_guard<std::mutex> lock(core->mutex);

    auto it = core->devices.find(uuid);

    if (it == core->devices.end())
        return CORE_NOT_FOUND;

    *outResult = hasCapability(it->second, cap);

    return CORE_OK;
}


/**
 * @brief Remove a registered device.
 *
 * @param core Core context.
 * @param uuid Device identifier.
 *
 * @return CoreResult status.
 */
CoreResult core_remove_device(
    CoreContext* core,
    const char* uuid
) {

    if (!core || !uuid)
        return CORE_INVALID_ARGUMENT;

    std::lock_guard<std::mutex> lock(core->mutex);

    auto it = core->devices.find(uuid);

    if (it == core->devices.end())
        return CORE_NOT_FOUND;

    it->second.driver->disconnect(uuid);

    core->devices.erase(it);

    CoreEvent ev{};
    ev.type = CORE_EVENT_DEVICE_REMOVED;

    std::strncpy(
        ev.uuid,
        uuid,
        CORE_MAX_UUID - 1
    );

    emitEvent(core, ev);

    return CORE_OK;
}


/* ============================================================
   State
   ============================================================ */

/**
 * @brief Get current device state.
 *
 * @param core     Core context.
 * @param uuid     Device identifier.
 * @param outState Output state structure.
 *
 * @return CoreResult status.
 */
CoreResult core_get_state(
    CoreContext* core,
    const char* uuid,
    CoreDeviceState* out
) {
    if (!core || !uuid || !out)
        return CORE_INVALID_ARGUMENT;

    std::lock_guard<std::mutex> lock(core->mutex);

    auto it = core->devices.find(uuid);

    if (it == core->devices.end())
        return CORE_NOT_FOUND;

    if (!it->second.driver->getState(uuid, *out))
        return CORE_ERROR;

    return CORE_OK;
}


/* ============================================================
   State Setters
   ============================================================ */

/**
 * @brief Set power state.
 */
CoreResult core_set_power(
    CoreContext* core,
    const char* uuid,
    bool value
) {

    if (!core || !uuid)
        return CORE_INVALID_ARGUMENT;

    std::lock_guard<std::mutex> lock(core->mutex);

    auto it = core->devices.find(uuid);

    if (it == core->devices.end())
        return CORE_NOT_FOUND;

    if (!hasCapability(it->second, CORE_CAP_POWER))
        return CORE_NOT_SUPPORTED;

    if (!it->second.driver->setPower(uuid, value))
        return CORE_ERROR;

        it->second.driver->getState(uuid, it->second.state);

    CoreEvent ev{};
    ev.type = CORE_EVENT_STATE_CHANGED;
    strncpy(ev.uuid, uuid, CORE_MAX_UUID-1);
    ev.state = it->second.state;

    emitEvent(core, ev);

    return CORE_OK;
}


/**
 * @brief Set brightness level.
 */
CoreResult core_set_brightness(
    CoreContext* core,
    const char* uuid,
    int value
) {
    if (!core || !uuid)
        return CORE_INVALID_ARGUMENT;

    if (value < 0 || value > 100)
        return CORE_INVALID_ARGUMENT;

    std::lock_guard<std::mutex> lock(core->mutex);

    auto it = core->devices.find(uuid);

    if (it == core->devices.end())
        return CORE_NOT_FOUND;

    if (!hasCapability(it->second, CORE_CAP_BRIGHTNESS))
        return CORE_NOT_SUPPORTED;

    if (!it->second.driver->setBrightness(uuid, value))
        return CORE_ERROR;

        it->second.driver->getState(uuid, it->second.state);

    CoreEvent ev{};
    ev.type = CORE_EVENT_STATE_CHANGED;
    strncpy(ev.uuid, uuid, CORE_MAX_UUID-1);
    ev.state = it->second.state;

    emitEvent(core, ev);

    return CORE_OK;
}


/**
 * @brief Set RGB color.
 */
CoreResult core_set_color(
    CoreContext* core,
    const char* uuid,
    uint32_t value
) {

    if (!core || !uuid)
        return CORE_INVALID_ARGUMENT;

    std::lock_guard<std::mutex> lock(core->mutex);

    auto it = core->devices.find(uuid);

    if (it == core->devices.end())
        return CORE_NOT_FOUND;

    if (!hasCapability(it->second, CORE_CAP_COLOR))
        return CORE_NOT_SUPPORTED;

    if (!it->second.driver->setColor(uuid, value))
        return CORE_ERROR;

        it->second.driver->getState(uuid, it->second.state);

    CoreEvent ev{};
    ev.type = CORE_EVENT_STATE_CHANGED;
    strncpy(ev.uuid, uuid, CORE_MAX_UUID-1);
    ev.state = it->second.state;

    emitEvent(core, ev);
    return CORE_OK;
}


/**
 * @brief Set temperature.
 */
CoreResult core_set_temperature(
    CoreContext* core,
    const char* uuid,
    float value
) {

    if (!core || !uuid)
        return CORE_INVALID_ARGUMENT;

    std::lock_guard<std::mutex> lock(core->mutex);

    auto it = core->devices.find(uuid);

    if (it == core->devices.end())
        return CORE_NOT_FOUND;

    if (!hasCapability(it->second, CORE_CAP_TEMPERATURE))
        return CORE_NOT_SUPPORTED;

    if (!it->second.driver->setTemperature(uuid, value))
        return CORE_ERROR;

    CoreEvent ev{};
    ev.type = CORE_EVENT_STATE_CHANGED;
    strncpy(ev.uuid, uuid, CORE_MAX_UUID-1);
    ev.state = it->second.state;

    emitEvent(core, ev);

    return CORE_OK;
}


/* ============================================================
   Diagnostics / Events
   ============================================================ */

/**
 * @brief Get last error message.
 *
 * @param core Core context.
 *
 * @return Null-terminated error string.
 */
const char* core_last_error(CoreContext* core) {

    if (!core)
        return "Invalid core";

    return core->lastError.c_str();
}


/**
 * @brief Register event callback.
 *
 * @param core     Core context.
 * @param callback Callback function.
 * @param userdata User-defined pointer.
 *
 * @return CoreResult status.
 */
CoreResult core_set_event_callback(
    CoreContext* core,
    CoreEventCallback callback,
    void* userdata
) {

    if (!core)
        return CORE_INVALID_ARGUMENT;

    std::lock_guard<std::mutex> lock(core->mutex);

    core->callback = callback;
    core->callbackUserdata = userdata;

    return CORE_OK;
}

} // extern "C"
