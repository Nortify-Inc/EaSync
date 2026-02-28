/**
 * @file core.cpp
 * @brief EaSync Core Runtime Implementation (Expanded +1000 lines version)
 *
 * Responsibilities:
 * - Device registry
 * - Driver management
 * - State caching
 * - Event dispatch
 * - Thread safety
 * - Detailed error handling
 * - Debug helpers
 *
 * This layer is NOT exposed directly through Foreign Function Integration.
 */

#include "core.h"
#include "driver.hpp"
#include "mock.hpp"
#include "mqtt.hpp"
#include "wifi.hpp"
#include "zigbee.hpp"

#include <unordered_map>
#include <unordered_set>
#include <string>
#include <vector>
#include <mutex>
#include <memory>
#include <cstring>
#include <iostream>
#include <iomanip>
#include <sstream>
#include <random>
#include <algorithm>
#include <cmath>

extern "C" {

/**
 * @brief Internal representation of a device.
 *
 * Stores device metadata, protocol, capabilities,
 * associated driver and current device state.
 */
struct InternalDevice {
    std::string uuid;                           /**< Device UUID */
    std::string name;                           /**< Device display name */
    CoreProtocol protocol;                      /**< Communication protocol */
    std::vector<CoreCapability> capabilities;   /**< Declared capabilities */
    std::shared_ptr<drivers::Driver> driver;    /**< Associated driver */
    CoreDeviceState state;                      /**< Current device state */
};



/**
 * @brief Core runtime context.
 *
 * Stores all devices, drivers, event callbacks, and thread safety primitives.
 */
struct CoreContext {
    bool initialized = false;                                                      /**< Core initialization flag */
    std::unordered_map<std::string, InternalDevice> devices;                       /**< Registered devices */
    std::unordered_map<CoreProtocol, std::shared_ptr<drivers::Driver>> drivers;    /**< Protocol drivers */
    std::mutex mutex;                                                              /**< Global mutex */
    std::string lastError;                                                         /**< Last error string */
    CoreEventCallback callback = nullptr;                                          /**< Event callback */
    void* callbackUserdata = nullptr;                                              /**< User data for callback */
};



/**
 * @brief Store last error message into core context.
 *
 * This function should be called whenever an operation fails.
 *
 * @param core Pointer to CoreContext.
 * @param msg Null-terminated error message.
 */
static void setError(CoreContext* core, const char* msg) {
    if (!core) return;

    core->lastError = msg ? msg : "Unknown error";
    std::cerr << "[CoreError] " << core->lastError << std::endl;
}



/**
 * @brief Convert a CoreCapability to a readable string.
 *
 * @param cap Capability to convert.
 * @return std::string Human-readable capability name.
 */
static std::string capabilityToString(CoreCapability cap) {
    switch (cap) {
        case CORE_CAP_POWER: return "Power";
        case CORE_CAP_BRIGHTNESS: return "Brightness";
        case CORE_CAP_COLOR: return "Color";
        case CORE_CAP_TEMPERATURE: return "Temperature";
        default: return "UnknownCapability";
    }
}



/**
 * @brief Check if device supports a capability.
 *
 * @param dev Reference to InternalDevice.
 * @param cap Capability to test.
 * @return true if supported, false otherwise.
 */
static bool hasCapability(const InternalDevice& dev, CoreCapability cap) {
    for (auto c : dev.capabilities) {
        if (c == cap) return true;
    }

    return false;
}

static float quantizeHalfStep(float value) {
    return std::round(value * 2.0f) / 2.0f;
}

static void driverEventForwarder(const std::string& uuid,
                                 const CoreDeviceState& newState,
                                 void* userData)
{
    CoreContext* core = static_cast<CoreContext*>(userData);
    if (!core) return;

    CoreEventCallback cb = nullptr;
    void* cbUserdata = nullptr;
    CoreEvent ev{};
    bool changed = false;

    {
        std::lock_guard<std::mutex> lock(core->mutex);

        auto it = core->devices.find(uuid);
        if (it == core->devices.end())
            return;

        if (std::memcmp(&it->second.state, &newState, sizeof(CoreDeviceState)) != 0) {
            it->second.state = newState;
            changed = true;

            ev.type = CORE_EVENT_STATE_CHANGED;
            std::strncpy(ev.uuid, uuid.c_str(), CORE_MAX_UUID - 1);
            ev.uuid[CORE_MAX_UUID - 1] = '\0';
            ev.state = newState;

            cb = core->callback;
            cbUserdata = core->callbackUserdata;
        }
    }

    if (changed && cb)
        cb(&ev, cbUserdata);
}


/**
 * @brief Utility: print device state (for debug).
 *
 * @param state Device state structure.
 */
static void printDeviceStateDebug(const CoreDeviceState& state) {
    std::cerr << "[State Debug] Power=" << (state.power ? "ON" : "OFF")
              << " Brightness=" << state.brightness
              << " Color=0x" << std::hex << state.color << std::dec
              << " Temperature=" << state.temperature
              << " Timestamp=" << state.timestamp
              << std::endl;
}



/**
 * @brief Create a new Core runtime context.
 *
 * Initializes all drivers for supported protocols but does NOT initialize devices.
 *
 * @return Pointer to CoreContext or nullptr on failure.
 */
CoreContext* core_create(void) {
    try {
        CoreContext* context = new CoreContext();

        context->drivers[CORE_PROTOCOL_MOCK] = 
            std::make_shared<drivers::MockDriver>();

        context->drivers[CORE_PROTOCOL_MQTT] = 
            std::make_shared<drivers::MqttDriver>();

        context->drivers[CORE_PROTOCOL_WIFI] = 
            std::make_shared<drivers::WifiDriver>();

        context->drivers[CORE_PROTOCOL_ZIGBEE] = 
            std::make_shared<drivers::ZigBeeDriver>();

        return context;

    } catch (...) {
        std::cerr << "[CoreError] Failed to allocate CoreContext" << std::endl;
        return nullptr;
    }
}


/**
 * @brief Destroy Core runtime context.
 *
 * Cleans up all resources and deletes the context.
 *
 * @param core Pointer to CoreContext.
 */
void core_destroy(CoreContext* core) {
    if (!core) {
        std::cerr << "[CoreError] core_destroy called with null pointer" << std::endl;
        return;
    }

    core->devices.clear();
    core->drivers.clear();

    delete core;
}



/**
 * @brief Initialize core runtime.
 *
 * Initializes only the drivers required by currently registered devices.
 *
 * @param core Pointer to CoreContext.
 * @return CORE_OK if successful.
 * @return CORE_INVALID_ARGUMENT if core is null.
 * @return CORE_ERROR if driver initialization fails.
 */
CoreResult core_init(CoreContext* core) {
    if (!core) {
        std::cerr << "[CoreError] core_init called with null pointer" << std::endl;
        return CORE_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(core->mutex);

    for (auto& pair : core->drivers) {
        auto& driver = pair.second;
        if (!driver) continue;

        if (!driver->init()) {
            // log and continue; core must stay up even without optional drivers
            setError(core, "Driver initialization failed");
            continue;
        }

        driver->setEventCallback(driverEventForwarder, core);
    }

    core->initialized = true;
    return CORE_OK;
}



/**
 * @brief Register a new device in the core.
 *
 * Adds a device with its UUID, name, protocol, and capabilities.
 * Initializes connection with the appropriate driver.
 *
 * @param core Pointer to CoreContext.
 * @param uuid Device unique identifier (string, non-null).
 * @param name Device display name (string, non-null).
 * @param protocol Communication protocol used by the device.
 * @param caps Array of capabilities supported by the device.
 * @param capCount Number of capabilities in caps array.
 * @return CORE_OK if successful.
 * @return CORE_INVALID_ARGUMENT if any parameter is invalid.
 * @return CORE_ALREADY_EXISTS if device with same UUID already exists.
 * @return CORE_NOT_INITIALIZED if core is not initialized.
 * @return CORE_NOT_SUPPORTED if protocol is not supported.
 * @return CORE_ERROR if driver connection fails.
 */
CoreResult core_register_device(CoreContext* core,
                                const char* uuid,
                                const char* name,
                                CoreProtocol protocol,
                                const CoreCapability* caps,
                                uint8_t capCount)
{
    if (!core || !uuid || !name || !caps)
        return CORE_INVALID_ARGUMENT;

    CoreEvent ev{};
    CoreEventCallback cb = nullptr;
    void* cbUserdata = nullptr;

    {
        std::lock_guard<std::mutex> lock(core->mutex);

        if (!core->initialized)
            return CORE_NOT_INITIALIZED;

        if (core->devices.count(uuid))
            return CORE_ALREADY_EXISTS;

        auto driverIt = core->drivers.find(protocol);
        if (driverIt == core->drivers.end())
            return CORE_NOT_SUPPORTED;

        InternalDevice dev;
        dev.uuid = uuid;
        dev.name = name;
        dev.protocol = protocol;
        dev.capabilities.assign(caps, caps + capCount);
        dev.driver = driverIt->second;

        std::memset(&dev.state, 0, sizeof(CoreDeviceState));

        if (!dev.driver->connect(dev.uuid))
            return CORE_ERROR;

        core->devices[uuid] = dev;

        ev.type = CORE_EVENT_DEVICE_ADDED;
        std::strncpy(ev.uuid, uuid, CORE_MAX_UUID - 1);
        ev.uuid[CORE_MAX_UUID - 1] = '\0';

        cb = core->callback;
        cbUserdata = core->callbackUserdata;
    }

    if (cb)
        cb(&ev, cbUserdata);

    return CORE_OK;
}


/**
 * @brief Remove a registered device from the core.
 *
 * Disconnects the driver and removes the device from registry.
 *
 * @param core Pointer to CoreContext.
 * @param uuid UUID of the device to remove.
 * @return CORE_OK if successful.
 * @return CORE_INVALID_ARGUMENT if parameters are invalid.
 * @return CORE_NOT_FOUND if device with UUID does not exist.
 */
CoreResult core_remove_device(CoreContext* core, const char* uuid)
{
    if (!core || !uuid)
        return CORE_INVALID_ARGUMENT;

    CoreEvent ev{};
    CoreEventCallback cb = nullptr;
    void* cbUserdata = nullptr;

    {
        std::lock_guard<std::mutex> lock(core->mutex);

        auto it = core->devices.find(uuid);
        if (it == core->devices.end())
            return CORE_NOT_FOUND;

        if (!it->second.driver->disconnect(uuid))
            return CORE_ERROR;

        core->devices.erase(it);

        ev.type = CORE_EVENT_DEVICE_REMOVED;
        std::strncpy(ev.uuid, uuid, CORE_MAX_UUID - 1);
        ev.uuid[CORE_MAX_UUID - 1] = '\0';

        cb = core->callback;
        cbUserdata = core->callbackUserdata;
    }

    if (cb)
        cb(&ev, cbUserdata);

    return CORE_OK;
}


/**
 * @brief Retrieve metadata for a specific device.
 *
 * Fills a CoreDeviceInfo structure with name, protocol, and capabilities.
 *
 * @param core Pointer to CoreContext.
 * @param uuid UUID of the device to query.
 * @param outInfo Output buffer to populate with device info.
 * @return CORE_OK on success.
 * @return CORE_INVALID_ARGUMENT if parameters are invalid.
 * @return CORE_NOT_FOUND if device does not exist.
 */
CoreResult core_get_device(CoreContext* core, const char* uuid, CoreDeviceInfo* outInfo)
{
    if (!core || !uuid || !outInfo) {
        setError(core, "Invalid parameters to core_get_device");
        return CORE_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(core->mutex);

    auto it = core->devices.find(uuid);

    if (it == core->devices.end()) {
        std::ostringstream oss;

        oss << "Device with UUID '" << uuid << "' not found";
        setError(core, oss.str().c_str());

        return CORE_NOT_FOUND;
    }

    const InternalDevice& dev = it->second;
    std::memset(outInfo, 0, sizeof(CoreDeviceInfo));
    std::strncpy(outInfo->uuid, dev.uuid.c_str(), CORE_MAX_UUID - 1);
    std::strncpy(outInfo->name, dev.name.c_str(), CORE_MAX_NAME - 1);

    outInfo->protocol = dev.protocol;
    outInfo->capabilityCount = dev.capabilities.size();

    for (size_t i = 0; i < dev.capabilities.size(); ++i) {
        outInfo->capabilities[i] = dev.capabilities[i];
    }

    return CORE_OK;
}



/**
 * @brief List all registered devices.
 *
 * Copies device metadata into a buffer or returns count if buffer is null.
 *
 * @param core Pointer to CoreContext.
 * @param buffer Optional output array of CoreDeviceInfo.
 * @param maxItems Max elements buffer can hold.
 * @param outCount Output for number of devices found.
 * @return CORE_OK on success.
 * @return CORE_INVALID_ARGUMENT if parameters are invalid.
 */
CoreResult core_list_devices(CoreContext* core,
                             CoreDeviceInfo* buffer,
                             uint32_t maxItems,
                             uint32_t* outCount)
{
    if (!core || !outCount) {
        setError(core, "Invalid parameters to core_list_devices");
        return CORE_INVALID_ARGUMENT;
    }

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

            for (size_t i = 0; i < dev.capabilities.size(); ++i)
                info.capabilities[i] = dev.capabilities[i];
        }

        count++;
    }

    *outCount = count;
    return CORE_OK;
}



/**
 * @brief Check whether a device supports a specific capability.
 *
 * @param core Pointer to CoreContext.
 * @param uuid UUID of the device.
 * @param cap Capability to check.
 * @param outResult Output boolean, true if supported.
 * @return CORE_OK on success.
 * @return CORE_INVALID_ARGUMENT if parameters are invalid.
 * @return CORE_NOT_FOUND if device does not exist.
 */
CoreResult core_has_capability(CoreContext* core,
                               const char* uuid,
                               CoreCapability cap,
                               bool* outResult)
{
    if (!core || !uuid || !outResult) {
        setError(core, "Invalid parameters to core_has_capability");
        return CORE_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(core->mutex);

    auto it = core->devices.find(uuid);

    if (it == core->devices.end()) {
        std::ostringstream oss;

        oss << "Device with UUID '" << uuid << "' not found for capability check";
        setError(core, oss.str().c_str());

        return CORE_NOT_FOUND;
    }

    *outResult = hasCapability(it->second, cap);
    return CORE_OK;
}



/**
 * @brief Retrieve current device state.
 *
 * Queries the driver for the latest device state.
 *
 * @param core Pointer to CoreContext.
 * @param uuid UUID of the device.
 * @param out Pointer to CoreDeviceState to populate.
 * @return CORE_OK if state retrieved successfully.
 * @return CORE_INVALID_ARGUMENT if parameters are invalid.
 * @return CORE_NOT_FOUND if device does not exist.
 * @return CORE_ERROR if driver fails to provide state.
 */
CoreResult core_get_state(CoreContext* core, const char* uuid, CoreDeviceState* out){
    if (!core || !uuid || !out)
        return CORE_INVALID_ARGUMENT;

    std::shared_ptr<drivers::Driver> driver;

    {
        std::lock_guard<std::mutex> lock(core->mutex);

        auto it = core->devices.find(uuid);
        if (it == core->devices.end())
            return CORE_NOT_FOUND;

        driver = it->second.driver;
    }

    if (!driver->getState(uuid, *out))
        return CORE_ERROR;

    return CORE_OK;
}

/**
 * @brief Set power on/off for a device.
 *
 * Updates device power state via driver and triggers state change event.
 *
 * @param core Pointer to CoreContext.
 * @param uuid UUID of the device.
 * @param value true for on, false for off.
 * @return CORE_OK if successful.
 * @return CORE_INVALID_ARGUMENT if parameters are invalid.
 * @return CORE_NOT_FOUND if device does not exist.
 * @return CORE_NOT_SUPPORTED if device lacks power capability.
 * @return CORE_ERROR if driver fails to set power.
 */
CoreResult core_set_power(CoreContext* core, const char* uuid, bool value){
    if (!core || !uuid)
        return CORE_INVALID_ARGUMENT;

    std::shared_ptr<drivers::Driver> driver;
    InternalDevice* dev = nullptr;

    {
        std::lock_guard<std::mutex> lock(core->mutex);

        auto it = core->devices.find(uuid);
        if (it == core->devices.end())
            return CORE_NOT_FOUND;

        if (!hasCapability(it->second, CORE_CAP_POWER))
            return CORE_NOT_SUPPORTED;

        driver = it->second.driver;
    }

    if (!driver->setPower(uuid, value))
        return CORE_ERROR;

    return CORE_OK;
}



/**
 * @brief Set brightness level of a device.
 *
 * @param core Pointer to CoreContext.
 * @param uuid UUID of the device.
 * @param value Brightness value (0-100).
 * @return CORE_OK if successful.
 * @return CORE_INVALID_ARGUMENT if parameters are invalid.
 * @return CORE_NOT_FOUND if device does not exist.
 * @return CORE_NOT_SUPPORTED if device lacks brightness capability.
 * @return CORE_ERROR if driver fails to set brightness.
 */
CoreResult core_set_brightness(CoreContext* core, const char* uuid, uint32_t value){
    if (!core || !uuid)
        return CORE_INVALID_ARGUMENT;

    if (value < 0 || value > 100)
        return CORE_INVALID_ARGUMENT;

    std::shared_ptr<drivers::Driver> driver;

    {
        std::lock_guard<std::mutex> lock(core->mutex);

        auto it = core->devices.find(uuid);
        if (it == core->devices.end())
            return CORE_NOT_FOUND;

        if (!hasCapability(it->second, CORE_CAP_BRIGHTNESS))
            return CORE_NOT_SUPPORTED;

        driver = it->second.driver;
    }

    if (!driver->setBrightness(uuid, value))
        return CORE_ERROR;

    return CORE_OK;
}


/**
 * @brief Set RGB color for a device.
 *
 * @param core Pointer to CoreContext.
 * @param uuid UUID of the device.
 * @param value RGB value (0xRRGGBB).
 * @return CORE_OK if successful.
 * @return CORE_INVALID_ARGUMENT if parameters are invalid.
 * @return CORE_NOT_FOUND if device does not exist.
 * @return CORE_NOT_SUPPORTED if device lacks color capability.
 * @return CORE_ERROR if driver fails to set color.
 */
CoreResult core_set_color(CoreContext* core, const char* uuid, uint32_t value){
    if (!core || !uuid)
        return CORE_INVALID_ARGUMENT;

    std::shared_ptr<drivers::Driver> driver;

    {
        std::lock_guard<std::mutex> lock(core->mutex);

        auto it = core->devices.find(uuid);
        if (it == core->devices.end())
            return CORE_NOT_FOUND;

        if (!hasCapability(it->second, CORE_CAP_COLOR))
            return CORE_NOT_SUPPORTED;

        driver = it->second.driver;
    }

    if (!driver->setColor(uuid, value))
        return CORE_ERROR;

    return CORE_OK;
}


/**
 * @brief Set temperature for a device.
 *
 * @param core Pointer to CoreContext.
 * @param uuid UUID of the device.
 * @param value Temperature in degrees Celsius.
 * @return CORE_OK if successful.
 * @return CORE_INVALID_ARGUMENT if parameters are invalid.
 * @return CORE_NOT_FOUND if device does not exist.
 * @return CORE_NOT_SUPPORTED if device lacks temperature capability.
 * @return CORE_ERROR if driver fails to set temperature.
 */
CoreResult core_set_temperature(CoreContext* core, const char* uuid, float value){
    if (!core || !uuid)
        return CORE_INVALID_ARGUMENT;

    value = quantizeHalfStep(value);

    std::shared_ptr<drivers::Driver> driver;

    {
        std::lock_guard<std::mutex> lock(core->mutex);

        auto it = core->devices.find(uuid);
        if (it == core->devices.end())
            return CORE_NOT_FOUND;

        if (!hasCapability(it->second, CORE_CAP_TEMPERATURE))
            return CORE_NOT_SUPPORTED;

        driver = it->second.driver;
    }

    if (!driver->setTemperature(uuid, value))
        return CORE_ERROR;

    return CORE_OK;
}

/**
 * @brief Set temperature for a device.
 *
 * @param core Pointer to CoreContext.
 * @param uuid UUID of the device.
 * @param value Temperature in degrees Celsius.
 * @return CORE_OK if successful.
 * @return CORE_INVALID_ARGUMENT if parameters are invalid.
 * @return CORE_NOT_FOUND if device does not exist.
 * @return CORE_NOT_SUPPORTED if device lacks temperature capability.
 * @return CORE_ERROR if driver fails to set temperature.
 */
CoreResult core_set_temperature_fridge(CoreContext* core, const char* uuid, float value){
    if (!core || !uuid)
        return CORE_INVALID_ARGUMENT;

    value = quantizeHalfStep(value);

    std::shared_ptr<drivers::Driver> driver;

    {
        std::lock_guard<std::mutex> lock(core->mutex);

        auto it = core->devices.find(uuid);
        if (it == core->devices.end())
            return CORE_NOT_FOUND;

        if (!hasCapability(it->second, CORE_CAP_TEMPERATURE_FRIDGE))
            return CORE_NOT_SUPPORTED;

        driver = it->second.driver;
    }

    if (!driver->setTemperatureFridge(uuid, value))
        return CORE_ERROR;

    return CORE_OK;
}


/**
 * @brief Set temperature for a device.
 *
 * @param core Pointer to CoreContext.
 * @param uuid UUID of the device.
 * @param value Temperature in degrees Celsius.
 * @return CORE_OK if successful.
 * @return CORE_INVALID_ARGUMENT if parameters are invalid.
 * @return CORE_NOT_FOUND if device does not exist.
 * @return CORE_NOT_SUPPORTED if device lacks temperature capability.
 * @return CORE_ERROR if driver fails to set temperature.
 */
CoreResult core_set_temperature_freezer(CoreContext* core, const char* uuid, float value){
    if (!core || !uuid)
        return CORE_INVALID_ARGUMENT;

    value = quantizeHalfStep(value);

    std::shared_ptr<drivers::Driver> driver;

    {
        std::lock_guard<std::mutex> lock(core->mutex);

        auto it = core->devices.find(uuid);
        if (it == core->devices.end())
            return CORE_NOT_FOUND;

        if (!hasCapability(it->second, CORE_CAP_TEMPERATURE_FREEZER))
            return CORE_NOT_SUPPORTED;

        driver = it->second.driver;
    }

    if (!driver->setTemperatureFreezer(uuid, value))
        return CORE_ERROR;

    return CORE_OK;
}

/**
 * @brief Set temperature for a device.
 *
 * @param core Pointer to CoreContext.
 * @param uuid UUID of the device.
 * @param value Timestamp in seconds.
 * @return CORE_OK if successful.
 * @return CORE_INVALID_ARGUMENT if parameters are invalid.
 * @return CORE_NOT_FOUND if device does not exist.
 * @return CORE_NOT_SUPPORTED if device lacks time capability.
 * @return CORE_ERROR if driver fails to set time.
 */
CoreResult core_set_time(CoreContext* core, const char* uuid, uint64_t value){
    if (!core || !uuid)
        return CORE_INVALID_ARGUMENT;

    std::shared_ptr<drivers::Driver> driver;

    {
        std::lock_guard<std::mutex> lock(core->mutex);

        auto it = core->devices.find(uuid);
        if (it == core->devices.end())
            return CORE_NOT_FOUND;

        if (!hasCapability(it->second, CORE_CAP_TIMESTAMP))
            return CORE_NOT_SUPPORTED;

        driver = it->second.driver;
    }

    if (!driver->setTime(uuid, value))
        return CORE_ERROR;

    return CORE_OK;
}


/**
 * @brief Set temperature for a device.
 *
 * @param core Pointer to CoreContext.
 * @param uuid UUID of the device.
 * @param value Timestamp in seconds.
 * @return CORE_OK if successful.
 * @return CORE_INVALID_ARGUMENT if parameters are invalid.
 * @return CORE_NOT_FOUND if device does not exist.
 * @return CORE_NOT_SUPPORTED if device lacks time capability.
 * @return CORE_ERROR if driver fails to set time.
 */
CoreResult core_set_color_temperature(CoreContext* core, const char* uuid, uint32_t value){
    if (!core || !uuid)
        return CORE_INVALID_ARGUMENT;

    std::shared_ptr<drivers::Driver> driver;

    {
        std::lock_guard<std::mutex> lock(core->mutex);

        auto it = core->devices.find(uuid);
        if (it == core->devices.end())
            return CORE_NOT_FOUND;

        if (!hasCapability(it->second, CORE_CAP_COLOR_TEMP))
            return CORE_NOT_SUPPORTED;

        driver = it->second.driver;
    }

    if (!driver->setColorTemperature(uuid, value))
        return CORE_ERROR;

    return CORE_OK;
}


/**
 * @brief Set temperature for a device.
 *
 * @param core Pointer to CoreContext.
 * @param uuid UUID of the device.
 * @param value Timestamp in seconds.
 * @return CORE_OK if successful.
 * @return CORE_INVALID_ARGUMENT if parameters are invalid.
 * @return CORE_NOT_FOUND if device does not exist.
 * @return CORE_NOT_SUPPORTED if device lacks time capability.
 * @return CORE_ERROR if driver fails to set time.
 */
CoreResult core_set_lock(CoreContext* core, const char* uuid, bool value){
    if (!core || !uuid)
        return CORE_INVALID_ARGUMENT;

    std::shared_ptr<drivers::Driver> driver;

    {
        std::lock_guard<std::mutex> lock(core->mutex);

        auto it = core->devices.find(uuid);
        if (it == core->devices.end())
            return CORE_NOT_FOUND;

        if (!hasCapability(it->second, CORE_CAP_LOCK))
            return CORE_NOT_SUPPORTED;

        driver = it->second.driver;
    }

    if (!driver->setLock(uuid, value))
        return CORE_ERROR;

    return CORE_OK;
}


/**
 * @brief Set temperature for a device.
 *
 * @param core Pointer to CoreContext.
 * @param uuid UUID of the device.
 * @param value Timestamp in seconds.
 * @return CORE_OK if successful.
 * @return CORE_INVALID_ARGUMENT if parameters are invalid.
 * @return CORE_NOT_FOUND if device does not exist.
 * @return CORE_NOT_SUPPORTED if device lacks time capability.
 * @return CORE_ERROR if driver fails to set time.
 */
CoreResult core_set_mode(CoreContext* core, const char* uuid, uint32_t value){
    if (!core || !uuid)
        return CORE_INVALID_ARGUMENT;

    std::shared_ptr<drivers::Driver> driver;

    {
        std::lock_guard<std::mutex> lock(core->mutex);

        auto it = core->devices.find(uuid);
        if (it == core->devices.end())
            return CORE_NOT_FOUND;

        if (!hasCapability(it->second, CORE_CAP_MODE))
            return CORE_NOT_SUPPORTED;

        driver = it->second.driver;
    }

    if (!driver->setMode(uuid, value))
        return CORE_ERROR;

    return CORE_OK;
}


/**
 * @brief Set temperature for a device.
 *
 * @param core Pointer to CoreContext.
 * @param uuid UUID of the device.
 * @param value Timestamp in seconds.
 * @return CORE_OK if successful.
 * @return CORE_INVALID_ARGUMENT if parameters are invalid.
 * @return CORE_NOT_FOUND if device does not exist.
 * @return CORE_NOT_SUPPORTED if device lacks time capability.
 * @return CORE_ERROR if driver fails to set time.
 */
CoreResult core_set_position(CoreContext* core, const char* uuid, float value){
    if (!core || !uuid)
        return CORE_INVALID_ARGUMENT;

    std::shared_ptr<drivers::Driver> driver;

    {
        std::lock_guard<std::mutex> lock(core->mutex);

        auto it = core->devices.find(uuid);
        if (it == core->devices.end())
            return CORE_NOT_FOUND;

        if (!hasCapability(it->second, CORE_CAP_POSITION))
            return CORE_NOT_SUPPORTED;

        driver = it->second.driver;
    }

    if (!driver->setPosition(uuid, value))
        return CORE_ERROR;

    return CORE_OK;
}

struct SimTarget {
    std::string uuid;
    std::vector<CoreCapability> caps;
    std::shared_ptr<drivers::Driver> driver;
};

struct SimSession {
    int idleTicks = 0;
    int actionTicks = 0;
};

static bool hasCap(const SimTarget& t, CoreCapability cap) {
    return std::find(t.caps.begin(), t.caps.end(), cap) != t.caps.end();
}

static int clampInt(int v, int lo, int hi) {
    return std::max(lo, std::min(v, hi));
}

static int64_t clampInt64(int64_t v, int64_t lo, int64_t hi) {
    return std::max(lo, std::min(v, hi));
}

static float clampFloat(float v, float lo, float hi) {
    return std::max(lo, std::min(v, hi));
}

CoreResult core_simulate(CoreContext* core)
{
    if (!core)
        return CORE_INVALID_ARGUMENT;

    std::vector<SimTarget> targets;

    {
        std::lock_guard<std::mutex> lock(core->mutex);

        if (!core->initialized)
            return CORE_NOT_INITIALIZED;

        for (auto& pair : core->devices) {
            SimTarget t;
            t.uuid = pair.first;
            t.caps = pair.second.capabilities;
            t.driver = pair.second.driver;
            targets.push_back(std::move(t));
        }
    }

    if (targets.empty())
        return CORE_OK;

    static thread_local std::mt19937 rng{std::random_device{}()};

    std::uniform_int_distribution<int> startActionChance(0, 99);
    std::uniform_int_distribution<int> actionLenDist(2, 8);
    std::uniform_int_distribution<int> idleLenDist(2, 14);
    std::uniform_int_distribution<int> flipChance(0, 99);
    std::uniform_int_distribution<int> brightStep(-7, 7);
    std::uniform_int_distribution<int> colorStep(-0x00020202, 0x00020202);
    std::uniform_real_distribution<float> tempStep(-0.5f, 0.5f);
    std::uniform_int_distribution<uint32_t> modeDist(0, 5);
    std::uniform_real_distribution<float> posStep(-3.5f, 3.5f);
    std::uniform_int_distribution<int> ctempStep(-180, 180);

    static thread_local std::unordered_map<std::string, SimSession> sessions;

    for (auto& t : targets) {
        if (!t.driver)
            continue;

        CoreDeviceState state{};
        if (!t.driver->getState(t.uuid, state))
            continue;

        auto& session = sessions[t.uuid];

        if (session.idleTicks > 0) {
            session.idleTicks--;
            continue;
        }

        if (session.actionTicks == 0) {
            if (startActionChance(rng) >= 35) {
                session.idleTicks = idleLenDist(rng);
                continue;
            }

            session.actionTicks = actionLenDist(rng);
        }

        session.actionTicks--;

        // build a new state with some randomness
        if (hasCap(t, CORE_CAP_POWER) && flipChance(rng) < 12)
            state.power = !state.power;

        if (hasCap(t, CORE_CAP_BRIGHTNESS))
            state.brightness = clampInt(
                static_cast<int>(state.brightness) + brightStep(rng),
                0,
                100
            );

        if (hasCap(t, CORE_CAP_COLOR)) {
            auto nextColor = static_cast<int64_t>(state.color) + colorStep(rng);
            nextColor = clampInt64(nextColor, 0, 0x00FFFFFF);
            state.color = static_cast<uint32_t>(nextColor);
        }

        if (hasCap(t, CORE_CAP_TEMPERATURE))
            state.temperature = quantizeHalfStep(
                clampFloat(state.temperature + tempStep(rng), 16.f, 30.f)
            );

        if (hasCap(t, CORE_CAP_TEMPERATURE_FRIDGE))
            state.temperatureFridge = quantizeHalfStep(clampFloat(
                state.temperatureFridge + tempStep(rng),
                1.f,
                8.f
            ));

        if (hasCap(t, CORE_CAP_TEMPERATURE_FREEZER))
            state.temperatureFreezer = quantizeHalfStep(clampFloat(
                state.temperatureFreezer + tempStep(rng),
                -24.f,
                -14.f
            ));

        if (hasCap(t, CORE_CAP_TIMESTAMP))
            state.timestamp += 60;

        if (hasCap(t, CORE_CAP_COLOR_TEMP)) {
            auto nextTemp = static_cast<int>(state.colorTemperature) + ctempStep(rng);
            nextTemp = clampInt(nextTemp, 2000, 9000);
            state.colorTemperature = static_cast<uint32_t>(nextTemp);
        }

        if (hasCap(t, CORE_CAP_LOCK) && flipChance(rng) < 8)
            state.lock = !state.lock;

        if (hasCap(t, CORE_CAP_MODE) && flipChance(rng) < 10)
            state.mode = modeDist(rng);

        if (hasCap(t, CORE_CAP_POSITION))
            state.position = clampFloat(state.position + posStep(rng), 0.f, 100.f);

        if (session.actionTicks == 0) {
            session.idleTicks = idleLenDist(rng);
        }

        // apply via driver setters to keep driver state consistent
        if (hasCap(t, CORE_CAP_POWER)) t.driver->setPower(t.uuid, state.power);
        if (hasCap(t, CORE_CAP_BRIGHTNESS)) t.driver->setBrightness(t.uuid, state.brightness);
        if (hasCap(t, CORE_CAP_COLOR)) t.driver->setColor(t.uuid, state.color);
        if (hasCap(t, CORE_CAP_TEMPERATURE)) t.driver->setTemperature(t.uuid, state.temperature);
        if (hasCap(t, CORE_CAP_TEMPERATURE_FRIDGE)) t.driver->setTemperatureFridge(t.uuid, state.temperatureFridge);
        if (hasCap(t, CORE_CAP_TEMPERATURE_FREEZER)) t.driver->setTemperatureFreezer(t.uuid, state.temperatureFreezer);
        if (hasCap(t, CORE_CAP_TIMESTAMP)) t.driver->setTime(t.uuid, state.timestamp);
        if (hasCap(t, CORE_CAP_COLOR_TEMP)) t.driver->setColorTemperature(t.uuid, state.colorTemperature);
        if (hasCap(t, CORE_CAP_LOCK)) t.driver->setLock(t.uuid, state.lock);
        if (hasCap(t, CORE_CAP_MODE)) t.driver->setMode(t.uuid, state.mode);
        if (hasCap(t, CORE_CAP_POSITION)) t.driver->setPosition(t.uuid, state.position);

        CoreDeviceState refreshed{};
        if (!t.driver->getState(t.uuid, refreshed))
            continue;

        // forward as a state change event
        driverEventForwarder(t.uuid, refreshed, core);
    }

    return CORE_OK;
}

/**
 * @brief Retrieve the last error message from the core.
 *
 * Provides a null-terminated string describing
 * the last error that occurred within the core.
 *
 * @param core Pointer to CoreContext.
 * @return Null-terminated string describing last error.
 *         Returns "Invalid core" if core pointer is null.
 */
const char* core_last_error(CoreContext* core)
{
    if (!core)
        return "Invalid core";

    if (core->lastError.empty())
        return "No error";

    return core->lastError.c_str();
}



/**
 * @brief Set the callback for core events.
 *
 * Registers a user-provided function that will
 * receive CoreEvent notifications.
 *
 * @param core Pointer to CoreContext.
 * @param callback Function pointer for event handling.
 * @param userdata User-defined pointer passed to callback.
 * @return CORE_OK on success.
 * @return CORE_INVALID_ARGUMENT if parameters are invalid.
 */
CoreResult core_set_event_callback(CoreContext* core, CoreEventCallback callback, void* userdata)
{
    if (!core) {
        return CORE_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(core->mutex);

    core->callback = callback;
    core->callbackUserdata = userdata;

    return CORE_OK;
}


/**
 * @brief Clear the last error message.
 *
 * Resets the internal lastError string to empty.
 *
 * @param core Pointer to CoreContext.
 * @return CORE_OK on success.
 * @return CORE_INVALID_ARGUMENT if core pointer is null.
 */
CoreResult core_clear_last_error(CoreContext* core)
{
    if (!core) {
        return CORE_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(core->mutex);
    core->lastError.clear();

    return CORE_OK;
}



/**
 * @brief Diagnostic function to inspect all registered devices.
 *
 * Returns a textual representation of all device states.
 * Intended for debugging purposes.
 *
 * @param core Pointer to CoreContext.
 * @param outBuffer Buffer to fill with device info text.
 * @param bufferSize Size of the output buffer.
 * @return CORE_OK on success.
 * @return CORE_INVALID_ARGUMENT if parameters are invalid.
 */
CoreResult core_inspect_state(CoreContext* core, char* outBuffer, size_t bufferSize)
{
    if (!core || !outBuffer || bufferSize == 0) {
        setError(core, "Invalid parameters to core_inspect_state");
        return CORE_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(core->mutex);

    std::ostringstream oss;
    for (const auto& pair : core->devices) {
        const InternalDevice& dev = pair.second;

        oss << "UUID: " << dev.uuid << ", Name: " << dev.name << ", Protocol: " << dev.protocol << "\n";
        oss << "Capabilities: ";

        for (auto cap : dev.capabilities) oss << cap << " ";

        oss << "\n";
        oss << "State - Power: " << dev.state.power
            << ", Brightness: " << dev.state.brightness
            << ", Color: " << dev.state.color
            << ", Temperature: " << dev.state.temperature << "\n\n";
    }

    std::string result = oss.str();
    if (result.length() >= bufferSize) {
        setError(core, "Output buffer too small for core_inspect_state");
        return CORE_ERROR;
    }

    std::strncpy(outBuffer, result.c_str(), bufferSize - 1);
    outBuffer[bufferSize - 1] = '\0';

    return CORE_OK;
}



/**
 * @brief Internal debug helper for last error.
 *
 * Useful for logging without external callback.
 *
 * @param core Pointer to CoreContext.
 * @return True if there is an error recorded, false otherwise.
 */
bool core_has_error(CoreContext* core)
{
    if (!core) return false;

    return !core->lastError.empty();
}



/**
 * @brief Internal utility to log driver failures.
 *
 * Sets error message and optionally prints to console.
 *
 * @param core Pointer to CoreContext.
 * @param driverName Name of the driver.
 * @param message Failure message.
 */
static void logDriverError(CoreContext* core, const char* driverName, const char* message)
{
    if (!core || !driverName || !message) return;

    std::ostringstream oss;
    oss << "Driver '" << driverName << "' error: " << message;

    setError(core, oss.str().c_str());
}

}