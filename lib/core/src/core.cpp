/**
 * @file core.cpp
 * @brief EaSync Core Runtime Implementation (Expanded +1000 lines version)
 * @param core Pointer to the runtime context used by C API functions.
 * @return API functions return CoreResult values or valid pointers per operation.
 * @author Erick Radmann
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
#include "ble.hpp"
#include "payload_utility.hpp"
#include "aiEngine.hpp"

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
#include <cctype>
#include <chrono>

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
    std::string brand;                          /**< Device brand */
    std::string model;                          /**< Device model */
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
    std::unordered_set<CoreProtocol> initializedProtocols;                          /**< Protocol drivers already initialized */
    std::mutex mutex;                                                              /**< Global mutex */
    std::string lastError;                                                         /**< Last error string */
    CoreEventCallback callback = nullptr;                                          /**< Event callback */
    void* callbackUserdata = nullptr;                                              /**< User data for callback */
    easync::ai::AiEngine ai;                                                       /**< Native AI backend */
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

static void driverEventForwarder(const std::string& uuid,
                                 const CoreDeviceState& newState,
                                 void* userData);


/**
 * @brief Convert a CoreProtocol to a readable string.
 *
 * @param protocol Protocol to convert.
 * @return std::string Human-readable protocol name.
 */
static std::string protocolToString(CoreProtocol protocol) {
    switch (protocol) {
        case CORE_PROTOCOL_MOCK: return "MOCK";
        case CORE_PROTOCOL_MQTT: return "MQTT";
        case CORE_PROTOCOL_WIFI: return "WIFI";
        case CORE_PROTOCOL_ZIGBEE: return "ZIGBEE";
        case CORE_PROTOCOL_BLE: return "BLE";
        default: return "UNKNOWN_PROTOCOL";
    }
}


/**
 * @brief Ensure protocol driver is initialized before use.
 *
 * @param core Pointer to CoreContext.
 * @param protocol Protocol of the target driver.
 * @param driver Driver instance for the protocol.
 * @return true when driver is ready for use.
 */
static bool ensureDriverInitialized(CoreContext* core,
                                    CoreProtocol protocol,
                                    const std::shared_ptr<drivers::Driver>& driver)
{
    if (!core || !driver)
        return false;

    if (core->initializedProtocols.count(protocol))
        return true;

    if (!driver->init()) {
        std::ostringstream oss;
        oss << "Protocol driver unavailable: " << protocolToString(protocol);
        setError(core, oss.str().c_str());
        return false;
    }

    driver->setEventCallback(driverEventForwarder, core);
    core->initializedProtocols.insert(protocol);

    return true;
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

static bool isHalfStep(float value) {
    float scaled = value * 2.0f;
    return std::fabs(scaled - std::round(scaled)) < 0.0001f;
}

static std::vector<easync::ai::DeviceSnapshot> collectSnapshots(CoreContext* core)
{
    std::vector<easync::ai::DeviceSnapshot> out;
    if (!core) {
        return out;
    }

    out.reserve(core->devices.size());
    for (const auto& kv : core->devices) {
        const InternalDevice& dev = kv.second;

        easync::ai::DeviceSnapshot snapshot;
        snapshot.uuid = dev.uuid;
        snapshot.name = dev.name;
        snapshot.state = dev.state;
        snapshot.capabilities = dev.capabilities;
        snapshot.online = dev.driver ? dev.driver->isAvailable(dev.uuid) : false;

        out.push_back(snapshot);
    }

    return out;
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
            const CoreDeviceState previous = it->second.state;
            it->second.state = newState;
            changed = true;

            const uint64_t nowTs = static_cast<uint64_t>(
                std::chrono::duration_cast<std::chrono::milliseconds>(
                    std::chrono::system_clock::now().time_since_epoch()).count());
            const auto p = core->ai.permissions();
            core->ai.recordPattern(uuid, previous, newState, p.useUsageHistory, nowTs);

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

        context->drivers[CORE_PROTOCOL_BLE] =
            std::make_shared<drivers::BleDriver>();

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

    for (const auto& pair : core->devices) {
        core::PayloadUtility::instance().unbindDevice(pair.first);
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

    auto mockIt = core->drivers.find(CORE_PROTOCOL_MOCK);
    if (mockIt != core->drivers.end()) {
        if (!ensureDriverInitialized(core, CORE_PROTOCOL_MOCK, mockIt->second))
            return CORE_ERROR;
    }

    core->lastError.clear();
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
CoreResult core_register_device_ex(CoreContext* core,
                                   const char* uuid,
                                   const char* name,
                                   const char* brand,
                                   const char* model,
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
        dev.brand = brand ? brand : "";
        dev.model = model ? model : "";
        dev.protocol = protocol;
        dev.capabilities.assign(caps, caps + capCount);
        dev.driver = driverIt->second;

        if (!ensureDriverInitialized(core, protocol, dev.driver))
            return CORE_PROTOCOL_UNAVAILABLE;

        std::memset(&dev.state, 0, sizeof(CoreDeviceState));

        dev.driver->onDeviceRegistered(dev.uuid, dev.brand, dev.model);

        if (!dev.driver->connect(dev.uuid))
            return CORE_ERROR;

        core->devices[uuid] = dev;
        core::PayloadUtility::instance().bindDevice(dev.uuid, dev.brand, dev.model);

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


CoreResult core_register_device(CoreContext* core,
                                const char* uuid,
                                const char* name,
                                CoreProtocol protocol,
                                const CoreCapability* caps,
                                uint8_t capCount)
{
    return core_register_device_ex(
        core,
        uuid,
        name,
        "",
        "",
        protocol,
        caps,
        capCount
    );
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
    if (!core || !uuid) {
        setError(core, "Invalid parameters to core_remove_device");
        return CORE_INVALID_ARGUMENT;
    }

    CoreEvent ev{};
    CoreEventCallback cb = nullptr;
    void* cbUserdata = nullptr;

    {
        std::lock_guard<std::mutex> lock(core->mutex);

        if (!core->initialized) {
            setError(core, "Core not initialized");
            return CORE_NOT_INITIALIZED;
        }

        auto it = core->devices.find(uuid);
        if (it == core->devices.end()) {
            setError(core, "Device not found");
            return CORE_NOT_FOUND;
        }

        // Removal from registry is authoritative for backend state.
        // Driver disconnection is best-effort to avoid leaving stale entries
        // when transport is down/unavailable.
        if (it->second.driver) {
            (void)it->second.driver->disconnect(uuid);
            it->second.driver->onDeviceRemoved(uuid);
        }

        core::PayloadUtility::instance().unbindDevice(uuid);

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
    std::strncpy(outInfo->band, dev.brand.c_str(), CORE_MAX_BRAND - 1);
    std::strncpy(outInfo->model, dev.model.c_str(), CORE_MAX_MODEL - 1);

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
            std::strncpy(info.band, dev.brand.c_str(), CORE_MAX_BRAND - 1);
            std::strncpy(info.model, dev.model.c_str(), CORE_MAX_MODEL - 1);

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

CoreResult core_is_device_available(
    CoreContext* core,
    const char* uuid,
    bool* outAvailable
){
    if (!core || !uuid || !outAvailable) {
        setError(core, "Invalid parameters to core_is_device_available");
        return CORE_INVALID_ARGUMENT;
    }

    std::shared_ptr<drivers::Driver> driver;

    {
        std::lock_guard<std::mutex> lock(core->mutex);

        if (!core->initialized)
            return CORE_NOT_INITIALIZED;

        auto it = core->devices.find(uuid);
        if (it == core->devices.end())
            return CORE_NOT_FOUND;

        driver = it->second.driver;
    }

    if (!driver) {
        *outAvailable = false;
        return CORE_ERROR;
    }

    *outAvailable = driver->isAvailable(uuid);
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

    if (!isHalfStep(value)) {
        setError(core, "Temperature must be in .0 or .5 steps");
        return CORE_INVALID_ARGUMENT;
    }

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

    if (!isHalfStep(value)) {
        setError(core, "Fridge temperature must be in .0 or .5 steps");
        return CORE_INVALID_ARGUMENT;
    }

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

    if (!isHalfStep(value)) {
        setError(core, "Freezer temperature must be in .0 or .5 steps");
        return CORE_INVALID_ARGUMENT;
    }

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

CoreResult core_provision_wifi(
    CoreContext* core,
    const char* uuid,
    const char* ssid,
    const char* password
){
    if (!core || !uuid || !ssid || !password) {
        setError(core, "Invalid parameters to core_provision_wifi");
        return CORE_INVALID_ARGUMENT;
    }

    if (std::strlen(ssid) == 0 || std::strlen(password) < 8) {
        setError(core, "Invalid Wi-Fi credentials");
        return CORE_INVALID_ARGUMENT;
    }

    std::shared_ptr<drivers::Driver> driver;

    {
        std::lock_guard<std::mutex> lock(core->mutex);

        if (!core->initialized)
            return CORE_NOT_INITIALIZED;

        auto it = core->devices.find(uuid);
        if (it == core->devices.end())
            return CORE_NOT_FOUND;

        if (it->second.protocol != CORE_PROTOCOL_WIFI) {
            setError(core, "Wi-Fi provisioning is only supported for Wi-Fi devices");
            return CORE_NOT_SUPPORTED;
        }

        driver = it->second.driver;
    }

    if (!driver || !driver->provisionWifi(uuid, ssid, password)) {
        setError(core, "Failed to provision Wi-Fi credentials");
        return CORE_ERROR;
    }

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
    std::uniform_int_distribution<int> actionLenDist(1, 4);
    std::uniform_int_distribution<int> idleLenDist(4, 22);
    std::uniform_int_distribution<int> flipChance(0, 99);
    std::uniform_int_distribution<int> brightStep(-12, 12);
    std::uniform_int_distribution<int> colorStep(-0x00050505, 0x00050505);
    std::uniform_int_distribution<int> tempJumpMag(3, 5);
    std::uniform_int_distribution<int> tempDir(0, 1);
    std::uniform_int_distribution<uint32_t> modeDist(0, 5);
    std::uniform_real_distribution<float> posStep(-8.f, 8.f);
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

        std::vector<CoreCapability> actionCaps;
        if (hasCap(t, CORE_CAP_POWER)) actionCaps.push_back(CORE_CAP_POWER);
        if (hasCap(t, CORE_CAP_BRIGHTNESS)) actionCaps.push_back(CORE_CAP_BRIGHTNESS);
        if (hasCap(t, CORE_CAP_COLOR)) actionCaps.push_back(CORE_CAP_COLOR);
        if (hasCap(t, CORE_CAP_TEMPERATURE)) actionCaps.push_back(CORE_CAP_TEMPERATURE);
        if (hasCap(t, CORE_CAP_TEMPERATURE_FRIDGE)) actionCaps.push_back(CORE_CAP_TEMPERATURE_FRIDGE);
        if (hasCap(t, CORE_CAP_TEMPERATURE_FREEZER)) actionCaps.push_back(CORE_CAP_TEMPERATURE_FREEZER);
        if (hasCap(t, CORE_CAP_TIMESTAMP) && flipChance(rng) < 8)
            actionCaps.push_back(CORE_CAP_TIMESTAMP);
        if (hasCap(t, CORE_CAP_COLOR_TEMP)) actionCaps.push_back(CORE_CAP_COLOR_TEMP);
        if (hasCap(t, CORE_CAP_LOCK)) actionCaps.push_back(CORE_CAP_LOCK);
        if (hasCap(t, CORE_CAP_POSITION)) actionCaps.push_back(CORE_CAP_POSITION);
        if (hasCap(t, CORE_CAP_MODE) && flipChance(rng) < 12) actionCaps.push_back(CORE_CAP_MODE);

        if (actionCaps.empty()) {
            if (session.actionTicks == 0) session.idleTicks = idleLenDist(rng);
            continue;
        }

        std::uniform_int_distribution<size_t> capDist(0, actionCaps.size() - 1);
        auto selected = actionCaps[capDist(rng)];

        bool changed = false;
        bool applied = true;

        switch (selected) {
            case CORE_CAP_POWER:
                state.power = !state.power;
                applied = t.driver->setPower(t.uuid, state.power);
                changed = true;
                break;

            case CORE_CAP_BRIGHTNESS:
                state.brightness = clampInt(static_cast<int>(state.brightness) + brightStep(rng), 0, 100);
                applied = t.driver->setBrightness(t.uuid, state.brightness);
                changed = true;
                break;

            case CORE_CAP_COLOR: {
                auto nextColor = static_cast<int64_t>(state.color) + colorStep(rng);
                nextColor = clampInt64(nextColor, 0, 0x00FFFFFF);
                state.color = static_cast<uint32_t>(nextColor);
                applied = t.driver->setColor(t.uuid, state.color);
                changed = true;
                break;
            }

            case CORE_CAP_TEMPERATURE: {
                float jump = static_cast<float>(tempJumpMag(rng)) * (tempDir(rng) == 0 ? -1.f : 1.f);
                state.temperature = quantizeHalfStep(clampFloat(state.temperature + jump, 16.f, 30.f));
                applied = t.driver->setTemperature(t.uuid, state.temperature);
                changed = true;
                break;
            }

            case CORE_CAP_TEMPERATURE_FRIDGE: {
                float jump = static_cast<float>(tempJumpMag(rng)) * (tempDir(rng) == 0 ? -1.f : 1.f);
                state.temperatureFridge = quantizeHalfStep(clampFloat(state.temperatureFridge + jump, 1.f, 8.f));
                applied = t.driver->setTemperatureFridge(t.uuid, state.temperatureFridge);
                changed = true;
                break;
            }

            case CORE_CAP_TEMPERATURE_FREEZER: {
                float jump = static_cast<float>(tempJumpMag(rng)) * (tempDir(rng) == 0 ? -1.f : 1.f);
                state.temperatureFreezer = quantizeHalfStep(clampFloat(state.temperatureFreezer + jump, -24.f, -14.f));
                applied = t.driver->setTemperatureFreezer(t.uuid, state.temperatureFreezer);
                changed = true;
                break;
            }

            case CORE_CAP_TIMESTAMP:
                state.timestamp += 60;
                applied = t.driver->setTime(t.uuid, state.timestamp);
                changed = true;
                break;

            case CORE_CAP_COLOR_TEMP: {
                auto nextTemp = static_cast<int>(state.colorTemperature) + ctempStep(rng);
                nextTemp = clampInt(nextTemp, 2000, 9000);
                state.colorTemperature = static_cast<uint32_t>(nextTemp);
                applied = t.driver->setColorTemperature(t.uuid, state.colorTemperature);
                changed = true;
                break;
            }

            case CORE_CAP_LOCK:
                state.lock = !state.lock;
                applied = t.driver->setLock(t.uuid, state.lock);
                changed = true;
                break;

            case CORE_CAP_MODE:
                state.mode = modeDist(rng);
                applied = t.driver->setMode(t.uuid, state.mode);
                changed = true;
                break;

            case CORE_CAP_POSITION:
                state.position = clampFloat(state.position + posStep(rng), 0.f, 100.f);
                applied = t.driver->setPosition(t.uuid, state.position);
                changed = true;
                break;

            default:
                break;
        }

        if (session.actionTicks == 0) {
            session.idleTicks = idleLenDist(rng);
        }

        if (!changed || !applied)
            continue;

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

CoreResult core_ai_set_permissions(CoreContext* core, const CoreAiPermissions* permissions)
{
    if (!core || !permissions)
        return CORE_INVALID_ARGUMENT;

    std::lock_guard<std::mutex> lock(core->mutex);

    easync::ai::Permissions p;
    p.useLocationData = permissions->useLocationData;
    p.useWeatherData = permissions->useWeatherData;
    p.useUsageHistory = permissions->useUsageHistory;
    p.allowDeviceControl = permissions->allowDeviceControl;
    p.allowAutoRoutines = permissions->allowAutoRoutines;
    core->ai.setPermissions(p);

    return CORE_OK;
}

CoreResult core_ai_get_permissions(CoreContext* core, CoreAiPermissions* outPermissions)
{
    if (!core || !outPermissions)
        return CORE_INVALID_ARGUMENT;

    std::lock_guard<std::mutex> lock(core->mutex);
    const easync::ai::Permissions p = core->ai.permissions();

    outPermissions->useLocationData = p.useLocationData;
    outPermissions->useWeatherData = p.useWeatherData;
    outPermissions->useUsageHistory = p.useUsageHistory;
    outPermissions->allowDeviceControl = p.allowDeviceControl;
    outPermissions->allowAutoRoutines = p.allowAutoRoutines;

    return CORE_OK;
}

CoreResult core_ai_record_pattern(CoreContext* core,
                                  const char* uuid,
                                  const CoreDeviceState* previous,
                                  const CoreDeviceState* next)
{
    if (!core || !uuid || !previous || !next)
        return CORE_INVALID_ARGUMENT;

    std::lock_guard<std::mutex> lock(core->mutex);
    const auto p = core->ai.permissions();
    const uint64_t nowTs = static_cast<uint64_t>(
        std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::system_clock::now().time_since_epoch()).count());
    core->ai.recordPattern(uuid, *previous, *next, p.useUsageHistory, nowTs);
    return CORE_OK;
}

CoreResult core_ai_observe_app_open(CoreContext* core, uint64_t timestampMs)
{
    if (!core)
        return CORE_INVALID_ARGUMENT;

    std::lock_guard<std::mutex> lock(core->mutex);
    core->ai.observeAppOpen(timestampMs);
    return CORE_OK;
}

CoreResult core_ai_observe_profile_apply(CoreContext* core,
                                         const char* profileName,
                                         uint64_t timestampMs)
{
    if (!core || !profileName)
        return CORE_INVALID_ARGUMENT;

    std::lock_guard<std::mutex> lock(core->mutex);
    core->ai.observeProfileApply(profileName, timestampMs);
    return CORE_OK;
}

CoreResult core_ai_process_chat(CoreContext* core,
                                const char* input,
                                char* outResponse,
                                uint32_t outResponseSize)
{
    if (!core || !input || !outResponse || outResponseSize == 0)
        return CORE_INVALID_ARGUMENT;

    std::string response;
    {
        std::lock_guard<std::mutex> lock(core->mutex);
        const auto snapshots = collectSnapshots(core);
        response = core->ai.processChat(input, snapshots);
    }

    if (response.size() + 1 > outResponseSize)
        return CORE_ERROR;

    std::strncpy(outResponse, response.c_str(), outResponseSize - 1);
    outResponse[outResponseSize - 1] = '\0';
    return CORE_OK;
}

CoreResult core_ai_learning_snapshot(CoreContext* core,
                                     char* outSummary,
                                     uint32_t outSummarySize)
{
    if (!core || !outSummary || outSummarySize == 0)
        return CORE_INVALID_ARGUMENT;

    std::string summary;
    {
        std::lock_guard<std::mutex> lock(core->mutex);
        summary = core->ai.learningSnapshot();
    }

    if (summary.size() + 1 > outSummarySize)
        return CORE_ERROR;

    std::strncpy(outSummary, summary.c_str(), outSummarySize - 1);
    outSummary[outSummarySize - 1] = '\0';
    return CORE_OK;
}

CoreResult core_ai_get_annotations(CoreContext* core,
                                   char* outAnnotations,
                                   uint32_t outAnnotationsSize)
{
    if (!core || !outAnnotations || outAnnotationsSize == 0)
        return CORE_INVALID_ARGUMENT;

    std::string packed;
    {
        std::lock_guard<std::mutex> lock(core->mutex);
        const auto items = core->ai.annotations(8);
        std::ostringstream oss;
        for (size_t i = 0; i < items.size(); ++i) {
            if (i > 0) {
                oss << "\n";
            }
            oss << items[i];
        }
        packed = oss.str();
    }

    if (packed.size() + 1 > outAnnotationsSize)
        return CORE_ERROR;

    std::strncpy(outAnnotations, packed.c_str(), outAnnotationsSize - 1);
    outAnnotations[outAnnotationsSize - 1] = '\0';
    return CORE_OK;
}

static std::string lowerCopy(const std::string& input)
{
    std::string s = input;
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return s;
}

static bool containsAny(const std::string& text,
                        std::initializer_list<const char*> needles)
{
    for (const char* needle : needles) {
        if (needle && text.find(needle) != std::string::npos) {
            return true;
        }
    }
    return false;
}

static int firstInteger(const std::string& text)
{
    int value = -1;
    bool found = false;
    for (char c : text) {
        if (std::isdigit(static_cast<unsigned char>(c))) {
            if (!found) {
                value = 0;
                found = true;
            }
            value = value * 10 + (c - '0');
            if (value > 1000) {
                break;
            }
        } else if (found) {
            break;
        }
    }
    return found ? value : -1;
}

static uint32_t namedColor(const std::string& q)
{
    if (q.find("blue") != std::string::npos || q.find("azul") != std::string::npos) return 0x0066AAFF;
    if (q.find("green") != std::string::npos || q.find("verde") != std::string::npos) return 0x0016A34A;
    if (q.find("red") != std::string::npos || q.find("vermelho") != std::string::npos) return 0x00E53935;
    if (q.find("purple") != std::string::npos || q.find("roxo") != std::string::npos) return 0x009C27B0;
    if (q.find("yellow") != std::string::npos || q.find("amarelo") != std::string::npos) return 0x00FFD600;
    if (q.find("orange") != std::string::npos || q.find("laranja") != std::string::npos) return 0x00FB8C00;
    if (q.find("white") != std::string::npos || q.find("branco") != std::string::npos) return 0x00F5F5F5;
    return 0x0066AAFF;
}

static std::vector<InternalDevice*> resolveTargets(CoreContext* core, const std::string& clause)
{
    std::vector<InternalDevice*> targets;
    const std::string q = lowerCopy(clause);

    for (auto& kv : core->devices) {
        std::string name = lowerCopy(kv.second.name);
        std::string brand = lowerCopy(kv.second.brand);
        std::string model = lowerCopy(kv.second.model);
        if ((!name.empty() && q.find(name) != std::string::npos) ||
            (!brand.empty() && q.find(brand) != std::string::npos) ||
            (!model.empty() && q.find(model) != std::string::npos)) {
            targets.push_back(&kv.second);
        }
    }

    if (!targets.empty()) {
        return targets;
    }

    auto collectByCap = [&](CoreCapability cap) {
        for (auto& kv : core->devices) {
            if (hasCapability(kv.second, cap)) {
                targets.push_back(&kv.second);
            }
        }
    };

    if (q.find("light") != std::string::npos || q.find("lamp") != std::string::npos ||
        q.find("luz") != std::string::npos || q.find("lampada") != std::string::npos) {
        collectByCap(CORE_CAP_BRIGHTNESS);
        if (targets.empty()) {
            collectByCap(CORE_CAP_COLOR);
        }
    } else if (q.find("ac") != std::string::npos || q.find("climate") != std::string::npos ||
               q.find("ar") != std::string::npos || q.find("temperature") != std::string::npos) {
        collectByCap(CORE_CAP_TEMPERATURE);
    } else if (q.find("curtain") != std::string::npos || q.find("blind") != std::string::npos ||
               q.find("cortina") != std::string::npos) {
        collectByCap(CORE_CAP_POSITION);
    }

    if (targets.empty() && core->devices.size() == 1) {
        targets.push_back(&core->devices.begin()->second);
    }

    return targets;
}

CoreResult core_ai_execute_command(CoreContext* core,
                                   const char* input,
                                   char* outResponse,
                                   uint32_t outResponseSize)
{
    if (!core || !input || !outResponse || outResponseSize == 0)
        return CORE_INVALID_ARGUMENT;

    struct PendingDispatch {
        CoreEvent ev;
        CoreEventCallback cb;
        void* userdata;
    };

    std::vector<PendingDispatch> pendingEvents;
    std::string reply;

    {
        std::lock_guard<std::mutex> lock(core->mutex);
        const auto perms = core->ai.permissions();
        const std::string raw = input;
        const std::string q = lowerCopy(raw);

        const uint64_t nowTs = static_cast<uint64_t>(
            std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::system_clock::now().time_since_epoch()).count());
        core->ai.observeCommand(raw, nowTs);

        const bool mentionsStateDomain = containsAny(q, {
            "brightness", "brilho", "temperature", "temperatura", "color", "cor",
            "position", "posicao", "ligad", "power", "online", "status", "estado",
            "open", "close", "abr", "fech"
        });

        const bool questionLike = q.find('?') != std::string::npos || containsAny(q, {
            "what", "which", "how", "quanto", "qual", "quais", "como", "status", "estado"
        });

        const bool informationalCue = containsAny(q, {
            "diz", "diga", "fale", "informe", "mostra", "mostrar", "me fala", "me diga",
            "quero saber", "lista", "listar", "list", "devices", "dispositivos", "dispositivo",
            "status", "estado", "online", "hello", "hi", "oi", "ola", "olá", "ajuda", "help"
        });

        const bool explicitAction = containsAny(q, {
            "turn on", "turn off", "liga", "desliga", "set", "ajusta", "mude", "defina",
            "apply", "aplica", "increase", "decrease", "aumenta", "diminui", "reduz",
            "abre", "abrir", "fecha", "fechar"
        });

        const bool hasValueHint = firstInteger(q) >= 0 || containsAny(q, {
            "blue", "azul", "green", "verde", "red", "vermelho", "purple", "roxo",
            "yellow", "amarelo", "orange", "laranja", "white", "branco"
        });

        const bool informationalLike = informationalCue || (questionLike && !explicitAction) ||
                                       (mentionsStateDomain && questionLike);
        const bool actionLike = explicitAction ||
                                (mentionsStateDomain && hasValueHint && !informationalLike);

        if (!actionLike || informationalLike) {
            const auto snapshots = collectSnapshots(core);
            reply = core->ai.processChat(raw, snapshots);
        } else if (!perms.allowDeviceControl) {
            reply = "Device control is disabled in assistant permissions.";
        } else {
            enum class ActionKind {
                Unknown,
                PowerOn,
                PowerOff,
                SetTemperature,
                SetBrightness,
                SetColor,
                SetPosition
            };

            struct ActionRecord {
                ActionKind kind = ActionKind::Unknown;
                std::string deviceName;
                int value = -1;
            };

            std::vector<std::string> actions;
            std::vector<ActionRecord> records;
            std::vector<std::string> unresolved;

            std::string normalized = q;
            size_t pos = 0;
            while ((pos = normalized.find(" and ", pos)) != std::string::npos) {
                normalized.replace(pos, 5, ";");
                pos += 1;
            }

            std::stringstream ss(normalized);
            std::string clause;
            while (std::getline(ss, clause, ';')) {
                if (clause.empty()) continue;
                auto targets = resolveTargets(core, clause);
                if (targets.empty()) {
                    unresolved.push_back(clause);
                    continue;
                }

                for (auto* dev : targets) {
                    CoreDeviceState before = dev->state;
                    bool changed = false;

                    if ((clause.find("turn on") != std::string::npos || clause.find("liga") != std::string::npos) &&
                        hasCapability(*dev, CORE_CAP_POWER)) {
                        if (dev->driver->setPower(dev->uuid, true)) {
                            dev->state.power = true;
                            changed = true;
                            actions.push_back("turned on " + dev->name);
                            records.push_back({ActionKind::PowerOn, dev->name, 1});
                        }
                    }

                    if ((clause.find("turn off") != std::string::npos || clause.find("desliga") != std::string::npos) &&
                        hasCapability(*dev, CORE_CAP_POWER)) {
                        if (dev->driver->setPower(dev->uuid, false)) {
                            dev->state.power = false;
                            changed = true;
                            actions.push_back("turned off " + dev->name);
                            records.push_back({ActionKind::PowerOff, dev->name, 0});
                        }
                    }

                    if ((clause.find("temperature") != std::string::npos || clause.find("temperatura") != std::string::npos) &&
                        hasCapability(*dev, CORE_CAP_TEMPERATURE)) {
                        const int v = firstInteger(clause);
                        if (v >= 0) {
                            const float t = static_cast<float>(std::clamp(v, 16, 30));
                            if (hasCapability(*dev, CORE_CAP_POWER) && !dev->state.power) {
                                dev->driver->setPower(dev->uuid, true);
                                dev->state.power = true;
                            }
                            if (dev->driver->setTemperature(dev->uuid, t)) {
                                dev->state.temperature = t;
                                changed = true;
                                actions.push_back("set " + dev->name + " to " + std::to_string(static_cast<int>(t)) + "°C");
                                records.push_back({ActionKind::SetTemperature, dev->name, static_cast<int>(t)});
                            }
                        }
                    }

                    if ((clause.find("brightness") != std::string::npos || clause.find("brilho") != std::string::npos) &&
                        hasCapability(*dev, CORE_CAP_BRIGHTNESS)) {
                        const int v = firstInteger(clause);
                        if (v >= 0) {
                            const uint32_t b = static_cast<uint32_t>(std::clamp(v, 0, 100));
                            if (dev->driver->setBrightness(dev->uuid, b)) {
                                dev->state.brightness = b;
                                changed = true;
                                actions.push_back("set brightness " + std::to_string(b) + "% on " + dev->name);
                                records.push_back({ActionKind::SetBrightness, dev->name, static_cast<int>(b)});
                            }
                        }
                    }

                    if ((clause.find("color") != std::string::npos || clause.find("cor") != std::string::npos) &&
                        hasCapability(*dev, CORE_CAP_COLOR)) {
                        const uint32_t c = namedColor(clause);
                        if (dev->driver->setColor(dev->uuid, c)) {
                            dev->state.color = c;
                            changed = true;
                            actions.push_back("set color on " + dev->name);
                            records.push_back({ActionKind::SetColor, dev->name, -1});
                        }
                    }

                    if ((clause.find("position") != std::string::npos || clause.find("posicao") != std::string::npos ||
                         clause.find("open") != std::string::npos || clause.find("close") != std::string::npos) &&
                        hasCapability(*dev, CORE_CAP_POSITION)) {
                        float p = dev->state.position;
                        if (clause.find("open") != std::string::npos) {
                            p = 100.f;
                        } else if (clause.find("close") != std::string::npos) {
                            p = 0.f;
                        } else {
                            const int v = firstInteger(clause);
                            if (v >= 0) {
                                p = static_cast<float>(std::clamp(v, 0, 100));
                            }
                        }
                        if (dev->driver->setPosition(dev->uuid, p)) {
                            dev->state.position = p;
                            changed = true;
                            actions.push_back("set position " + std::to_string(static_cast<int>(p)) + "% on " + dev->name);
                            records.push_back({ActionKind::SetPosition, dev->name, static_cast<int>(p)});
                        }
                    }

                    if (changed) {
                        const auto pp = core->ai.permissions();
                        core->ai.recordPattern(dev->uuid, before, dev->state, pp.useUsageHistory, nowTs);

                        CoreEvent ev{};
                        ev.type = CORE_EVENT_STATE_CHANGED;
                        std::strncpy(ev.uuid, dev->uuid.c_str(), CORE_MAX_UUID - 1);
                        ev.uuid[CORE_MAX_UUID - 1] = '\0';
                        ev.state = dev->state;
                        pendingEvents.push_back({ev, core->callback, core->callbackUserdata});
                    }
                }
            }

            if (!actions.empty()) {
                if (records.size() == 1) {
                    const auto& r = records.front();
                    if (r.kind == ActionKind::SetTemperature && r.value >= 0) {
                        reply = "Sure! Now " + r.deviceName + " is running at " + std::to_string(r.value) + "°C.";
                    } else if (r.kind == ActionKind::PowerOn) {
                        reply = "Done. " + r.deviceName + " is ON now.";
                    } else if (r.kind == ActionKind::PowerOff) {
                        reply = "Done. " + r.deviceName + " is OFF now.";
                    } else if (r.kind == ActionKind::SetBrightness && r.value >= 0) {
                        reply = "Sure! " + r.deviceName + " brightness is now " + std::to_string(r.value) + "%.";
                    } else if (r.kind == ActionKind::SetPosition && r.value >= 0) {
                        reply = "Sure! " + r.deviceName + " position is now " + std::to_string(r.value) + "%.";
                    }
                }

                if (reply.empty()) {
                    std::ostringstream oss;
                    oss << "Done: ";
                    for (size_t i = 0; i < actions.size(); ++i) {
                        if (i > 0) oss << ", ";
                        oss << actions[i];
                    }
                    if (!unresolved.empty()) {
                        oss << ". Some clauses were not resolved.";
                    }
                    reply = oss.str();
                }
            } else if (!unresolved.empty()) {
                reply = "I could not map this command to known devices or capabilities.";
            } else {
                reply = "No actionable changes were detected for this command.";
            }
        }
    }

    for (const auto& item : pendingEvents) {
        if (item.cb) {
            item.cb(&item.ev, item.userdata);
        }
    }

    if (reply.empty()) {
        reply = "I could not process this command.";
    }

    if (reply.size() + 1 > outResponseSize)
        return CORE_ERROR;

    std::strncpy(outResponse, reply.c_str(), outResponseSize - 1);
    outResponse[outResponseSize - 1] = '\0';
    return CORE_OK;
}

}