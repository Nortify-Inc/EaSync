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
#include "chatModelRuntime.hpp"
#include "chatCommandRouter.hpp"

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
#include <atomic>
#include <thread>

extern "C" {

static std::atomic<uint64_t> g_aiAsyncTokenCounter{1};
static thread_local bool g_suppressCoreCallbacks = false;

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

    std::mutex aiAsyncMutex;
    bool aiAsyncRunning = false;
    bool aiAsyncReady = false;
    uint64_t aiAsyncToken = 0;
    std::string aiAsyncResponse;
    std::string lastReferencedDeviceUuid;
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
    p.temperament = permissions->temperament;
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
    outPermissions->temperament = p.temperament;

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

static std::string temperamentToken(uint32_t value)
{
    switch (value) {
        case 1: return "cheerful";
        case 2: return "direct";
        case 3: return "professional";
        default: return "minimalist";
    }
}

static std::string composeModelInput(const std::string& raw,
                                     const easync::ai::Permissions& permissions)
{
    std::ostringstream oss;
    oss << "[TEMPERAMENT=" << temperamentToken(permissions.temperament) << "] ";
    oss << raw;
    return oss.str();
}

CoreResult core_ai_process_chat(CoreContext* core,
                                const char* input,
                                char* outResponse,
                                uint32_t outResponseSize)
{
    if (!core || !input || !outResponse || outResponseSize == 0)
        return CORE_INVALID_ARGUMENT;

    const std::string raw = input;
    easync::ai::ChatModelPrediction prediction;
    std::string modelInput = raw;
    {
        std::lock_guard<std::mutex> lock(core->mutex);
        modelInput = composeModelInput(raw, core->ai.permissions());
    }

    const bool modelOk = easync::ai::runChatModelPrediction(modelInput, prediction);
    std::string response = modelOk ? prediction.generatedResponse : std::string();

    if (response.size() + 1 > outResponseSize)
        return CORE_ERROR;

    std::strncpy(outResponse, response.c_str(), outResponseSize - 1);
    outResponse[outResponseSize - 1] = '\0';
    return CORE_OK;
}

CoreResult core_ai_model_process_chat(CoreContext* core,
                                      const char* input,
                                      char* outResponse,
                                      uint32_t outResponseSize)
{
    return core_ai_process_chat(core, input, outResponse, outResponseSize);
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

static bool hasAnyDigit(const std::string& text)
{
    for (char c : text) {
        if (std::isdigit(static_cast<unsigned char>(c))) {
            return true;
        }
    }
    return false;
}

static bool firstSignedInteger(const std::string& text, int& outValue)
{
    bool found = false;
    bool negative = false;
    int value = 0;

    for (size_t i = 0; i < text.size(); ++i) {
        const char c = text[i];
        if (!found) {
            if (c == '-' && i + 1 < text.size() &&
                std::isdigit(static_cast<unsigned char>(text[i + 1]))) {
                negative = true;
                found = true;
                value = 0;
                continue;
            }
            if (std::isdigit(static_cast<unsigned char>(c))) {
                found = true;
                value = c - '0';
                continue;
            }
            continue;
        }

        if (std::isdigit(static_cast<unsigned char>(c))) {
            value = value * 10 + (c - '0');
            if (value > 1000) {
                break;
            }
        } else {
            break;
        }
    }

    if (!found) {
        return false;
    }

    outValue = negative ? -value : value;
    return true;
}

static std::string normalizeModeToken(const std::string& text)
{
    std::string s = lowerCopy(text);
    for (char& c : s) {
        if (c == '_' || c == '-') {
            c = ' ';
        }
    }

    std::string out;
    out.reserve(s.size());
    bool prevSpace = false;
    for (char c : s) {
        const bool isSpace = std::isspace(static_cast<unsigned char>(c)) != 0;
        if (isSpace) {
            if (!prevSpace && !out.empty()) {
                out.push_back(' ');
            }
            prevSpace = true;
        } else {
            out.push_back(c);
            prevSpace = false;
        }
    }
    if (!out.empty() && out.back() == ' ') {
        out.pop_back();
    }

    return out;
}

static bool parseModeValueForDevice(const InternalDevice& dev,
                                    const std::string& text,
                                    int& outValue,
                                    std::string& outModeLabel)
{
    const auto options = core::PayloadUtility::instance().modeOptionsForDevice(dev.uuid);

    int numeric = 0;
    if (firstSignedInteger(text, numeric) && numeric >= 0) {
        if (options.empty()) {
            outValue = numeric;
            outModeLabel = "mode " + std::to_string(numeric);
            return true;
        }

        if (numeric < static_cast<int>(options.size())) {
            outValue = numeric;
            outModeLabel = options[static_cast<size_t>(numeric)];
            return true;
        }

        return false;
    }

    if (options.empty()) {
        return false;
    }

    const std::string q = normalizeModeToken(text);
    const std::string qCompact = [&]() {
        std::string compact;
        compact.reserve(q.size());
        for (char c : q) {
            if (!std::isspace(static_cast<unsigned char>(c))) {
                compact.push_back(c);
            }
        }
        return compact;
    }();

    for (size_t i = 0; i < options.size(); ++i) {
        const std::string candidate = normalizeModeToken(options[i]);
        if (candidate.empty()) {
            continue;
        }

        if (q.find(candidate) != std::string::npos) {
            outValue = static_cast<int>(i);
            outModeLabel = options[i];
            return true;
        }

        std::string candidateCompact;
        candidateCompact.reserve(candidate.size());
        for (char c : candidate) {
            if (!std::isspace(static_cast<unsigned char>(c))) {
                candidateCompact.push_back(c);
            }
        }

        if (!candidateCompact.empty() && qCompact.find(candidateCompact) != std::string::npos) {
            outValue = static_cast<int>(i);
            outModeLabel = options[i];
            return true;
        }
    }

    return false;
}

static bool tryParseColor(const std::string& q, uint32_t& outColor)
{
    std::string s = lowerCopy(q);

    auto set = [&](uint32_t rgb) {
        outColor = rgb & 0x00FFFFFF;
        return true;
    };

    const auto hashPos = s.find('#');
    if (hashPos != std::string::npos && hashPos + 7 <= s.size()) {
        const std::string hex = s.substr(hashPos + 1, 6);
        bool ok = true;
        for (char c : hex) {
            if (!std::isxdigit(static_cast<unsigned char>(c))) {
                ok = false;
                break;
            }
        }
        if (ok) {
            try {
                return set(static_cast<uint32_t>(std::stoul(hex, nullptr, 16)));
            } catch (...) {}
        }
    }

    const auto oxPos = s.find("0x");
    if (oxPos != std::string::npos && oxPos + 8 <= s.size()) {
        const std::string hex = s.substr(oxPos + 2, 6);
        bool ok = true;
        for (char c : hex) {
            if (!std::isxdigit(static_cast<unsigned char>(c))) {
                ok = false;
                break;
            }
        }
        if (ok) {
            try {
                return set(static_cast<uint32_t>(std::stoul(hex, nullptr, 16)));
            } catch (...) {}
        }
    }

    const auto rgbPos = s.find("rgb(");
    if (rgbPos != std::string::npos) {
        const auto endPos = s.find(')', rgbPos);
        if (endPos != std::string::npos && endPos > rgbPos + 4) {
            std::string inner = s.substr(rgbPos + 4, endPos - (rgbPos + 4));
            for (char& c : inner) {
                if (c == ',') c = ' ';
            }
            std::stringstream ss(inner);
            int r = -1, g = -1, b = -1;
            if (ss >> r >> g >> b) {
                r = std::clamp(r, 0, 255);
                g = std::clamp(g, 0, 255);
                b = std::clamp(b, 0, 255);
                return set(static_cast<uint32_t>((r << 16) | (g << 8) | b));
            }
        }
    }

    static const std::pair<const char*, uint32_t> kNamed[] = {
        {"light blue", 0x0000FFFF},
        {"dark blue", 0x000000FF},
        {"azul claro", 0x0000FFFF},
        {"azul escuro", 0x000000FF},
        {"light green", 0x0090EE90},
        {"dark green", 0x00008700},
        {"verde claro", 0x0090EE90},
        {"verde escuro", 0x00008700},
        {"light red", 0x00FF6E64},
        {"dark red", 0x00B71C1C},
        {"vermelho claro", 0x00FF6E64},
        {"vermelho escuro", 0x00B71C1C},
        {"light purple", 0x009932CC},
        {"dark purple", 0x0065117A},
        {"roxo claro", 0x009932CC},
        {"roxo escuro", 0x0065117A},
        {"light pink", 0x00FF80AB},
        {"dark pink", 0x00B0003A},
        {"rosa claro", 0x00FF80AB},
        {"rosa escuro", 0x00B0003A},
        {"light yellow", 0x00FFFF99},
        {"dark yellow", 0x00B2A100},
        {"amarelo claro", 0x00FFFF99},
        {"amarelo escuro", 0x00B2A100},
        {"light orange", 0x00FFA500},
        {"dark orange", 0x00B26A00},
        {"laranja claro", 0x00FFA500},
        {"laranja escuro", 0x00B26A00},
        {"white", 0x00F5F5F5},
        {"branco", 0x00F5F5F5},
        {"blue", 0x000066FF},
        {"azul", 0x000066FF},
        {"green", 0x0000C853},
        {"verde", 0x0000C853},
        {"red", 0x00E53935},
        {"vermelho", 0x00E53935},
        {"purple", 0x009C27B0},
        {"roxo", 0x009C27B0},
        {"pink", 0x00EC407A},
        {"rosa", 0x00EC407A},
        {"violet", 0x008A2BE2},
        {"indigo", 0x004B0082},
        {"brown", 0x008B4513},
        {"marrom", 0x008B4513},
        {"black", 0x00000000},
        {"preto", 0x00000000},
        {"gray", 0x00808080},
        {"grey", 0x00808080},
        {"cinza", 0x00808080},
        {"silver", 0x00C0C0C0},
        {"prata", 0x00C0C0C0},
        {"gold", 0x00FFD700},
        {"dourado", 0x00FFD700},
        {"yellow", 0x00FFD600},
        {"amarelo", 0x00FFD600},
        {"orange", 0x00FB8C00},
        {"laranja", 0x00FB8C00},
        {"cyan", 0x0000BCD4},
        {"ciano", 0x0000BCD4},
    };

    for (const auto& item : kNamed) {
        if (s.find(item.first) != std::string::npos) {
            return set(item.second);
        }
    }

    return false;
}

static std::vector<InternalDevice*> resolveTargets(CoreContext* core, const std::string& clause)
{
    std::vector<InternalDevice*> targets;
    const std::string q = lowerCopy(clause);

    auto pushUnique = [&](InternalDevice* dev) {
        if (!dev) return;
        for (auto* existing : targets) {
            if (existing == dev) return;
        }
        targets.push_back(dev);
    };

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
                pushUnique(&kv.second);
            }
        }
    };

    auto collectByAnyThermalCap = [&]() {
        for (auto& kv : core->devices) {
            if (hasCapability(kv.second, CORE_CAP_TEMPERATURE) ||
                hasCapability(kv.second, CORE_CAP_TEMPERATURE_FRIDGE) ||
                hasCapability(kv.second, CORE_CAP_TEMPERATURE_FREEZER)) {
                pushUnique(&kv.second);
            }
        }
    };

    if (q.find("light") != std::string::npos || q.find("lamp") != std::string::npos ||
        q.find("luz") != std::string::npos || q.find("lampada") != std::string::npos ||
        q.find("strip") != std::string::npos || q.find("led") != std::string::npos) {
        collectByCap(CORE_CAP_BRIGHTNESS);
        if (targets.empty()) {
            collectByCap(CORE_CAP_COLOR);
        }
    } else if (q.find("color") != std::string::npos || q.find("cor") != std::string::npos) {
        collectByCap(CORE_CAP_COLOR);
        if (targets.empty()) {
            collectByCap(CORE_CAP_BRIGHTNESS);
        }
    } else if (q.find("brightness") != std::string::npos || q.find("brilho") != std::string::npos) {
        collectByCap(CORE_CAP_BRIGHTNESS);
    } else if (q.find("mode") != std::string::npos || q.find("modo") != std::string::npos ||
               q.find("eco") != std::string::npos || q.find("turbo") != std::string::npos ||
               q.find("sleep") != std::string::npos || q.find("comfort") != std::string::npos ||
               q.find("auto") != std::string::npos) {
        collectByCap(CORE_CAP_MODE);
    } else if (q.find("lock") != std::string::npos || q.find("unlock") != std::string::npos ||
               q.find("door") != std::string::npos || q.find("fechadura") != std::string::npos ||
               q.find("tranca") != std::string::npos || q.find("trancar") != std::string::npos ||
               q.find("destrancar") != std::string::npos || q.find("porta") != std::string::npos) {
        collectByCap(CORE_CAP_LOCK);
    } else if (q.find("ac") != std::string::npos || q.find("climate") != std::string::npos ||
               q.find("ar") != std::string::npos || q.find("temperature") != std::string::npos ||
               q.find("temperatura") != std::string::npos || q.find("temp") != std::string::npos ||
               q.find("fridge") != std::string::npos || q.find("freezer") != std::string::npos ||
               q.find("geladeira") != std::string::npos || q.find("congelador") != std::string::npos) {
        collectByAnyThermalCap();
    } else if (q.find("curtain") != std::string::npos || q.find("blind") != std::string::npos ||
               q.find("cortina") != std::string::npos) {
        collectByCap(CORE_CAP_POSITION);
    }

    if (targets.empty() && core->devices.size() == 1) {
        targets.push_back(&core->devices.begin()->second);
    }

    if (targets.empty()) {
        const bool pronounRef = containsAny(q, {
            " it ", " it?", " its ", "its ", "this device", "that device",
            "esse dispositivo", "este dispositivo", "dele", "dela"
        });

        if (pronounRef && !core->lastReferencedDeviceUuid.empty()) {
            auto it = core->devices.find(core->lastReferencedDeviceUuid);
            if (it != core->devices.end()) {
                targets.push_back(&it->second);
            }
        }
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
        easync::ai::ChatModelPrediction prediction;
        const std::string modelInput = composeModelInput(raw, perms);
        const bool modelOk = easync::ai::runChatModelPrediction(modelInput, prediction);

        const std::string effectiveRaw = modelOk
            ? easync::ai::augmentCommandFromPrediction(raw, prediction)
            : raw;
        const std::string q = lowerCopy(effectiveRaw);

        const uint64_t nowTs = static_cast<uint64_t>(
            std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::system_clock::now().time_since_epoch()).count());
        core->ai.observeCommand(raw, nowTs);

        const bool mentionsStateDomain = containsAny(q, {
            "brightness", "brilho", "temperature", "temperatura", "temp", "tempeature", "thermo", "color", "cor",
            "position", "posicao", "ligad", "power", "online", "status", "estado",
            "lock", "unlock", "tranca", "fechadura", "mode", "modo", "kelvin", "color temperature",
            "open", "close", "abr", "fech"
        });

        const bool mentionsDeviceHint = containsAny(q, {
            "lamp", "light", "luz", "ac", "air conditioner", "climate", "fridge", "freezer",
            "geladeira", "congelador", "curtain", "blind", "cortina", "strip", "led", "lock", "door"
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
            "open", "close", "abre", "abrir", "fecha", "fechar", "lock", "unlock", "trancar", "destrancar"
        });

        const bool socialGreeting = containsAny(q, {
            "hello", "hi", "hey", "oi", "ola", "olá", "bom dia", "boa tarde", "boa noite"
        });
        const bool socialThanks = containsAny(q, {
            "thanks", "thank you", "thx", "obrigado", "obrigada", "valeu"
        });
        const bool socialFarewell = containsAny(q, {
            "bye", "see you", "good night", "talk later", "tchau", "ate mais", "até mais"
        });
        const bool socialHowAreYou = containsAny(q, {
            "how are you", "how is it going", "how's it going", "how you doing", "you good", "tudo bem", "como voce", "como você"
        });

        const bool socialOnly = !explicitAction && !mentionsStateDomain && !mentionsDeviceHint;
        if (socialOnly) {
            if (socialThanks || (modelOk && prediction.intent == "gratitude")) {
                reply = prediction.generatedResponse;
            } else if (socialFarewell || (modelOk && prediction.intent == "farewell")) {
                reply = prediction.generatedResponse;
            } else if (socialHowAreYou || (modelOk && prediction.intent == "smalltalk")) {
                reply = prediction.generatedResponse;
            } else if (socialGreeting || (modelOk && prediction.intent == "greeting")) {
                reply = prediction.generatedResponse;
            }
        }

        const bool clarificationLike = modelOk &&
            (prediction.needsClarification || prediction.intent == "ambiguous" || prediction.intentConfidence < 0.45f);
        if (reply.empty() && clarificationLike && !explicitAction && !mentionsStateDomain) {
            reply = prediction.generatedResponse;
        }

        if (!reply.empty()) {
            // Social intents should not go through command/action routing.
        } else {

        {
            auto contextTargets = resolveTargets(core, q);
            if (!contextTargets.empty()) {
                core->lastReferencedDeviceUuid = contextTargets.front()->uuid;
            }
        }

        const bool hasValueHint = hasAnyDigit(q) || containsAny(q, {
            "blue", "azul", "green", "verde", "red", "vermelho", "purple", "roxo",
            "yellow", "amarelo", "orange", "laranja", "white", "branco"
        });

        bool informationalLike = !explicitAction &&
                                 (informationalCue || questionLike ||
                                  (mentionsStateDomain && questionLike));
        bool actionLike = explicitAction ||
                          (mentionsStateDomain && hasValueHint && !informationalLike);

        bool forceChatRouting = containsAny(q, {
            "devices", "dispositivos", "dispositivo", "list", "lista", "listar",
            "status", "estado", "online", "hello", "hi", "oi", "ola", "olá", "help", "ajuda"
        }) && !explicitAction;

        if (modelOk) {
            if (easync::ai::predictionSuggestsAction(prediction)) {
                actionLike = true;
                informationalLike = false;
                forceChatRouting = false;
            } else if (!explicitAction && !hasValueHint &&
                       easync::ai::predictionSuggestsInformational(prediction)) {
                informationalLike = true;
                actionLike = false;
                forceChatRouting = true;
            }
        }

        if (forceChatRouting || !actionLike || informationalLike) {
            const auto snapshots = collectSnapshots(core);
            reply = core->ai.processChat(raw, snapshots);
        } else if (!perms.allowDeviceControl) {
            if (modelOk) {
                reply = prediction.generatedResponse;
            }
            if (reply.empty()) {
                const auto snapshots = collectSnapshots(core);
                reply = core->ai.processChat(raw, snapshots);
            }
        } else {
            enum class ActionKind {
                Unknown,
                PowerOn,
                PowerOff,
                SetTemperature,
                SetBrightness,
                SetColor,
                SetPosition,
                SetLock,
                SetMode,
                SetColorTemperature
            };

            struct ActionRecord {
                ActionKind kind = ActionKind::Unknown;
                std::string deviceName;
                int value = -1;
                std::string detail;
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
                const size_t actionsBeforeClause = actions.size();
                auto targets = resolveTargets(core, clause);
                if (targets.empty()) {
                    unresolved.push_back(clause);
                    continue;
                }

                core->lastReferencedDeviceUuid = targets.front()->uuid;

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

                    if ((clause.find("temperature") != std::string::npos || clause.find("temperatura") != std::string::npos ||
                        clause.find("temp") != std::string::npos || clause.find("tempeature") != std::string::npos ||
                        clause.find("freezer") != std::string::npos || clause.find("congelador") != std::string::npos ||
                        clause.find("fridge") != std::string::npos || clause.find("geladeira") != std::string::npos) &&
                        (hasCapability(*dev, CORE_CAP_TEMPERATURE) ||
                         hasCapability(*dev, CORE_CAP_TEMPERATURE_FRIDGE) ||
                         hasCapability(*dev, CORE_CAP_TEMPERATURE_FREEZER))) {
                        int v = 0;
                        if (firstSignedInteger(clause, v)) {
                            const std::string devName = lowerCopy(dev->name);
                            const bool coldDevice = devName.find("fridge") != std::string::npos ||
                                                    devName.find("freezer") != std::string::npos ||
                                                    devName.find("geladeira") != std::string::npos ||
                                                    devName.find("congelador") != std::string::npos;
                            const bool wantsFreezer = clause.find("freezer") != std::string::npos ||
                                                     clause.find("congelador") != std::string::npos;
                            const bool wantsFridge = clause.find("fridge") != std::string::npos ||
                                                    clause.find("geladeira") != std::string::npos ||
                                                    clause.find("refrigerator") != std::string::npos;

                            const bool hasRoomTemp = hasCapability(*dev, CORE_CAP_TEMPERATURE);
                            const bool hasFridgeTemp = hasCapability(*dev, CORE_CAP_TEMPERATURE_FRIDGE);
                            const bool hasFreezerTemp = hasCapability(*dev, CORE_CAP_TEMPERATURE_FREEZER);

                            if (hasCapability(*dev, CORE_CAP_POWER) && !dev->state.power) {
                                dev->driver->setPower(dev->uuid, true);
                                dev->state.power = true;
                            }

                            if ((wantsFreezer && hasFreezerTemp) ||
                                (v < 0 && hasFreezerTemp) ||
                                (!hasRoomTemp && !hasFridgeTemp && hasFreezerTemp)) {
                                const float t = static_cast<float>(std::clamp(v, -30, 10));
                                if (dev->driver->setTemperatureFreezer(dev->uuid, t)) {
                                    dev->state.temperatureFreezer = t;
                                    changed = true;
                                    actions.push_back("set freezer temperature " + std::to_string(static_cast<int>(t)) + "°C on " + dev->name);
                                    records.push_back({ActionKind::SetTemperature, dev->name, static_cast<int>(t)});
                                }
                            } else if ((wantsFridge && hasFridgeTemp) ||
                                       (!hasRoomTemp && hasFridgeTemp)) {
                                const float t = static_cast<float>(std::clamp(v, 1, 8));
                                if (dev->driver->setTemperatureFridge(dev->uuid, t)) {
                                    dev->state.temperatureFridge = t;
                                    changed = true;
                                    actions.push_back("set fridge temperature " + std::to_string(static_cast<int>(t)) + "°C on " + dev->name);
                                    records.push_back({ActionKind::SetTemperature, dev->name, static_cast<int>(t)});
                                }
                            } else if (hasRoomTemp) {
                                const int minT = coldDevice ? -20 : 16;
                                const int maxT = coldDevice ? 12 : 30;
                                const float t = static_cast<float>(std::clamp(v, minT, maxT));
                                if (dev->driver->setTemperature(dev->uuid, t)) {
                                    dev->state.temperature = t;
                                    changed = true;
                                    actions.push_back("set " + dev->name + " to " + std::to_string(static_cast<int>(t)) + "°C");
                                    records.push_back({ActionKind::SetTemperature, dev->name, static_cast<int>(t)});
                                }
                            }
                        }
                    }

                    if ((clause.find("brightness") != std::string::npos || clause.find("brilho") != std::string::npos) &&
                        hasCapability(*dev, CORE_CAP_BRIGHTNESS)) {
                        int v = 0;
                        if (firstSignedInteger(clause, v)) {
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
                        uint32_t c = 0;
                        if (tryParseColor(clause, c) && dev->driver->setColor(dev->uuid, c)) {
                            dev->state.color = c;
                            changed = true;
                            actions.push_back("set color on " + dev->name);
                            records.push_back({ActionKind::SetColor, dev->name, -1});
                        }
                    }

                    if ((clause.find("color temperature") != std::string::npos ||
                         clause.find("temperatura de cor") != std::string::npos ||
                         clause.find("kelvin") != std::string::npos) &&
                        hasCapability(*dev, CORE_CAP_COLOR_TEMP)) {
                        int v = 0;
                        if (firstSignedInteger(clause, v)) {
                            const int k = std::clamp(v, 1000, 9000);
                            if (dev->driver->setColorTemperature(dev->uuid, static_cast<uint32_t>(k))) {
                                dev->state.colorTemperature = static_cast<uint32_t>(k);
                                changed = true;
                                actions.push_back("set color temperature " + std::to_string(k) + "K on " + dev->name);
                                records.push_back({ActionKind::SetColorTemperature, dev->name, k});
                            }
                        }
                    }

                    if ((clause.find("lock") != std::string::npos || clause.find("tranca") != std::string::npos ||
                         clause.find("trancar") != std::string::npos || clause.find("fechadura") != std::string::npos) &&
                        hasCapability(*dev, CORE_CAP_LOCK)) {
                        const bool unlockCmd = clause.find("unlock") != std::string::npos ||
                                              clause.find("destrancar") != std::string::npos;
                        const bool lockValue = !unlockCmd;
                        if (dev->driver->setLock(dev->uuid, lockValue)) {
                            dev->state.lock = lockValue;
                            changed = true;
                            actions.push_back(std::string(lockValue ? "locked " : "unlocked ") + dev->name);
                            records.push_back({ActionKind::SetLock, dev->name, lockValue ? 1 : 0});
                        }
                    }

                    if ((clause.find("mode") != std::string::npos || clause.find("modo") != std::string::npos) &&
                        hasCapability(*dev, CORE_CAP_MODE)) {
                        int v = 0;
                        std::string modeLabel;
                        if (parseModeValueForDevice(*dev, clause, v, modeLabel) && v >= 0) {
                            if (dev->driver->setMode(dev->uuid, static_cast<uint32_t>(v))) {
                                dev->state.mode = static_cast<uint32_t>(v);
                                changed = true;
                                const std::string prettyMode = modeLabel.empty() ? ("mode " + std::to_string(v)) : modeLabel;
                                actions.push_back("set mode " + prettyMode + " on " + dev->name);
                                records.push_back({ActionKind::SetMode, dev->name, v, prettyMode});
                            }
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
                            int v = 0;
                            if (firstSignedInteger(clause, v)) {
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

                if (actions.size() == actionsBeforeClause) {
                    unresolved.push_back(clause);
                }
            }

            if (modelOk) {
                reply = prediction.generatedResponse;
            }

            if (reply.empty() && !actions.empty()) {
                std::ostringstream applied;
                for (size_t i = 0; i < actions.size(); ++i) {
                    if (i > 0) {
                        applied << "; ";
                    }
                    applied << actions[i];
                }
                reply = applied.str();
            }
        }
        }
    }

    if (!g_suppressCoreCallbacks) {
        for (const auto& item : pendingEvents) {
            if (item.cb) {
                item.cb(&item.ev, item.userdata);
            }
        }
    }

    if (reply.size() + 1 > outResponseSize)
        return CORE_ERROR;

    std::strncpy(outResponse, reply.c_str(), outResponseSize - 1);
    outResponse[outResponseSize - 1] = '\0';
    return CORE_OK;
}

CoreResult core_ai_model_execute_command(CoreContext* core,
                                         const char* input,
                                         char* outResponse,
                                         uint32_t outResponseSize)
{
    return core_ai_execute_command(core, input, outResponse, outResponseSize);
}

CoreResult core_ai_set_chat_model_script(CoreContext* core,
                                         const char* scriptPath)
{
    if (!core || !scriptPath || scriptPath[0] == '\0') {
        return CORE_INVALID_ARGUMENT;
    }

#if defined(_WIN32)
    const int rc = _putenv_s("EASYNC_CHAT_INFER_SCRIPT", scriptPath);
#else
    const int rc = setenv("EASYNC_CHAT_INFER_SCRIPT", scriptPath, 1);
#endif

    if (rc != 0) {
        return CORE_ERROR;
    }

    return CORE_OK;
}

CoreResult core_ai_model_execute_command_async_start(CoreContext* core,
                                                     const char* input,
                                                     uint64_t* outToken)
{
    if (!core || !input || !outToken) {
        return CORE_INVALID_ARGUMENT;
    }

    const std::string raw = input;
    const uint64_t token = g_aiAsyncTokenCounter.fetch_add(1);

    {
        std::lock_guard<std::mutex> lock(core->aiAsyncMutex);
        if (core->aiAsyncRunning) {
            return CORE_ERROR;
        }
        core->aiAsyncRunning = true;
        core->aiAsyncReady = false;
        core->aiAsyncToken = token;
        core->aiAsyncResponse.clear();
    }

    *outToken = token;

    std::thread([core, raw, token]() {
        char out[4096] = {0};
        const bool previousSuppress = g_suppressCoreCallbacks;
        g_suppressCoreCallbacks = true;
        CoreResult rc = core_ai_execute_command(core, raw.c_str(), out, sizeof(out));
        g_suppressCoreCallbacks = previousSuppress;
        std::string response = (rc == CORE_OK) ? std::string(out) : std::string();

        std::lock_guard<std::mutex> lock(core->aiAsyncMutex);
        if (core->aiAsyncToken == token) {
            core->aiAsyncResponse = response;
            core->aiAsyncReady = true;
            core->aiAsyncRunning = false;
        }
    }).detach();

    return CORE_OK;
}

CoreResult core_ai_model_execute_command_async_poll(CoreContext* core,
                                                    uint64_t token,
                                                    bool* outReady,
                                                    char* outResponse,
                                                    uint32_t outResponseSize)
{
    if (!core || !outReady || !outResponse || outResponseSize == 0 || token == 0) {
        return CORE_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(core->aiAsyncMutex);
    if (core->aiAsyncToken != token) {
        return CORE_NOT_FOUND;
    }

    *outReady = core->aiAsyncReady;
    if (!core->aiAsyncReady) {
        outResponse[0] = '\0';
        return CORE_OK;
    }

    if (core->aiAsyncResponse.size() + 1 > outResponseSize) {
        return CORE_ERROR;
    }

    std::strncpy(outResponse, core->aiAsyncResponse.c_str(), outResponseSize - 1);
    outResponse[outResponseSize - 1] = '\0';

    core->aiAsyncReady = false;
    core->aiAsyncToken = 0;
    core->aiAsyncResponse.clear();
    return CORE_OK;
}

}