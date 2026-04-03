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
#include "ble.hpp"
#include "payload_utility.hpp"

#ifdef EASYNC_ENABLE_MQTT_DRIVER
#include "mqtt.hpp"
#endif

#ifdef EASYNC_ENABLE_WIFI_DRIVER
#include "wifi.hpp"
#endif

#ifdef EASYNC_ENABLE_ZIGBEE_DRIVER
#include "zigbee.hpp"
#endif

#include <unordered_map>
#include <unordered_set>
#include <deque>
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
#include <ctime>
#include <cstdio>

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
    std::unordered_set<CoreProtocol> initializedProtocols;                         /**< Protocol drivers already initialized */
    std::mutex mutex;                                                              /**< Global mutex */
    std::string lastError;                                                         /**< Last error string */
    CoreEventCallback callback = nullptr;                                          /**< Event callback */
    void* callbackUserdata = nullptr;                                              /**< User data for callback */

    std::mutex aiAsyncMutex;
    bool aiAsyncRunning = false;
    bool aiAsyncReady = false;
    uint64_t aiAsyncToken = 0;
    std::string aiAsyncResponse;
    std::string lastReferencedDeviceUuid;

    struct UsageSample {
        std::string uuid;
        uint64_t tsMs = 0;
        CoreDeviceState state{};
    };

    std::deque<UsageSample> usageSamples;
    std::unordered_map<std::string, int> usageDeviceActivity;
    std::unordered_map<int, int> usageArrivalHour;
    std::unordered_map<std::string, CoreDeviceState> usageLastState;
    std::unordered_map<std::string, bool> usagePowerByDevice;
    double usageTempSum = 0.0;
    uint64_t usageTempCount = 0;
    double usageBrightnessSum = 0.0;
    uint64_t usageBrightnessCount = 0;
    double usagePositionSum = 0.0;
    uint64_t usagePositionCount = 0;
    bool usageAnyPowered = false;
    uint64_t usageLastPowerOffTsMs = 0;
    uint64_t usageLastRecommendationTsMs = 0;
};

static constexpr size_t kMaxUsageSamples = 4096;
static constexpr uint64_t kArrivalGapMs = 45ULL * 60ULL * 1000ULL;
static constexpr uint64_t kRecommendationCooldownMs = 40ULL * 60ULL * 1000ULL;

static uint64_t nowMs() {
    return static_cast<uint64_t>(
        std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::system_clock::now().time_since_epoch()).count());
}

static int hourOfDay(uint64_t tsMs) {
    std::time_t sec = static_cast<std::time_t>(tsMs / 1000ULL);
    std::tm localTm{};
#ifdef _WIN32
    localtime_s(&localTm, &sec);
#else
    localtime_r(&sec, &localTm);
#endif
    return localTm.tm_hour;
}

static bool stateEquals(const CoreDeviceState& a, const CoreDeviceState& b) {
    return a.power == b.power &&
           a.brightness == b.brightness &&
           a.color == b.color &&
           std::fabs(a.temperature - b.temperature) < 0.0001f &&
           std::fabs(a.temperatureFridge - b.temperatureFridge) < 0.0001f &&
           std::fabs(a.temperatureFreezer - b.temperatureFreezer) < 0.0001f &&
           a.timestamp == b.timestamp &&
           a.colorTemperature == b.colorTemperature &&
           a.lock == b.lock &&
           a.mode == b.mode &&
           std::fabs(a.position - b.position) < 0.0001f;
}

static void recordUsageSampleLocked(CoreContext* core,
                                    const std::string& uuid,
                                    const CoreDeviceState& state,
                                    bool forceCapture = false)
{
    if (!core)
        return;

    const uint64_t ts = nowMs();

    auto lastIt = core->usageLastState.find(uuid);
    if (!forceCapture && lastIt != core->usageLastState.end() && stateEquals(lastIt->second, state)) {
        return;
    }

    core->usageLastState[uuid] = state;
    core->usageDeviceActivity[uuid]++;

    CoreContext::UsageSample sample;
    sample.uuid = uuid;
    sample.tsMs = ts;
    sample.state = state;
    core->usageSamples.push_back(std::move(sample));
    while (core->usageSamples.size() > kMaxUsageSamples) {
        core->usageSamples.pop_front();
    }

    if (state.temperature >= -30.0f && state.temperature <= 50.0f) {
        core->usageTempSum += state.temperature;
        core->usageTempCount++;
    }

    if (state.brightness <= 100U) {
        core->usageBrightnessSum += static_cast<double>(state.brightness);
        core->usageBrightnessCount++;
    }

    if (state.position >= 0.0f && state.position <= 100.0f) {
        core->usagePositionSum += state.position;
        core->usagePositionCount++;
    }

    const bool wasAnyPowered = core->usageAnyPowered;
    core->usagePowerByDevice[uuid] = state.power;

    bool anyPoweredNow = false;
    for (const auto& pair : core->usagePowerByDevice) {
        if (pair.second) {
            anyPoweredNow = true;
            break;
        }
    }

    if (!wasAnyPowered && anyPoweredNow) {
        if (core->usageLastPowerOffTsMs > 0 && (ts - core->usageLastPowerOffTsMs) >= kArrivalGapMs) {
            const int h = hourOfDay(ts);
            core->usageArrivalHour[h]++;
        }
    }

    if (wasAnyPowered && !anyPoweredNow) {
        core->usageLastPowerOffTsMs = ts;
    }

    core->usageAnyPowered = anyPoweredNow;
}

static void gatherUsageStatsLocked(CoreContext* core, CoreUsageStats* outStats) {
    if (!core || !outStats)
        return;

    std::memset(outStats, 0, sizeof(CoreUsageStats));
    outStats->sampleCount = static_cast<uint32_t>(core->usageSamples.size());
    outStats->distinctDevices = static_cast<uint32_t>(core->usageDeviceActivity.size());
    outStats->predictedArrivalHour = -1;

    int bestHour = -1;
    int bestHourCount = -1;
    int totalArrivalSignals = 0;
    for (const auto& pair : core->usageArrivalHour) {
        totalArrivalSignals += pair.second;
        if (pair.second > bestHourCount) {
            bestHourCount = pair.second;
            bestHour = pair.first;
        }
    }
    outStats->predictedArrivalHour = bestHour;

    if (core->usageTempCount > 0) {
        outStats->preferredTemperature = static_cast<float>(core->usageTempSum / static_cast<double>(core->usageTempCount));
    }

    if (core->usageBrightnessCount > 0) {
        outStats->preferredBrightness = static_cast<uint32_t>(
            std::llround(core->usageBrightnessSum / static_cast<double>(core->usageBrightnessCount)));
    }

    if (core->usagePositionCount > 0) {
        outStats->preferredPosition = static_cast<float>(core->usagePositionSum / static_cast<double>(core->usagePositionCount));
    }

    std::string bestUuid;
    int bestActivity = -1;
    int totalActivity = 0;
    for (const auto& pair : core->usageDeviceActivity) {
        totalActivity += pair.second;
        if (pair.second > bestActivity) {
            bestActivity = pair.second;
            bestUuid = pair.first;
        }
    }

    if (!bestUuid.empty()) {
        std::strncpy(outStats->mostActiveUuid, bestUuid.c_str(), CORE_MAX_UUID - 1);
        outStats->mostActiveUuid[CORE_MAX_UUID - 1] = '\0';
    }

    const float baseBySamples = std::min(1.0f, static_cast<float>(outStats->sampleCount) / 120.0f);
    float arrivalWeight = 0.0f;
    if (totalArrivalSignals > 0 && bestHourCount > 0) {
        arrivalWeight = static_cast<float>(bestHourCount) / static_cast<float>(totalArrivalSignals);
    }
    float activityWeight = 0.0f;
    if (totalActivity > 0 && bestActivity > 0) {
        activityWeight = static_cast<float>(bestActivity) / static_cast<float>(totalActivity);
    }

    outStats->confidence = std::clamp((baseBySamples * 0.55f) + (arrivalWeight * 0.30f) + (activityWeight * 0.15f), 0.0f, 1.0f);
}



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
        case CORE_CAP_TEMPERATURE_FRIDGE: return "Fridge temperature";
        case CORE_CAP_TEMPERATURE_FREEZER: return "Freezer temperature";
        case CORE_CAP_COLOR_TEMP: return "Color temperature";
        case CORE_CAP_TIMESTAMP: return "Timestamp";
        case CORE_CAP_LOCK: return "Lock";
        case CORE_CAP_MODE: return "Mode";
        case CORE_CAP_POSITION: return "Position";
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

            recordUsageSampleLocked(core, uuid, newState);

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

static void captureUsageAfterWrite(CoreContext* core,
                                   const char* uuid,
                                   const std::shared_ptr<drivers::Driver>& driver)
{
    if (!core || !uuid || !driver)
        return;

    CoreDeviceState refreshed{};
    if (!driver->getState(uuid, refreshed))
        return;

    std::lock_guard<std::mutex> lock(core->mutex);
    auto it = core->devices.find(uuid);
    if (it == core->devices.end())
        return;

    it->second.state = refreshed;
    recordUsageSampleLocked(core, uuid, refreshed);
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

        #ifdef EASYNC_ENABLE_MQTT_DRIVER
        context->drivers[CORE_PROTOCOL_MQTT] =
            std::make_shared<drivers::MqttDriver>();
        #endif

        #ifdef EASYNC_ENABLE_WIFI_DRIVER
        context->drivers[CORE_PROTOCOL_WIFI] =
            std::make_shared<drivers::WifiDriver>();
        #endif

        #ifdef EASYNC_ENABLE_ZIGBEE_DRIVER
        context->drivers[CORE_PROTOCOL_ZIGBEE] =
            std::make_shared<drivers::ZigBeeDriver>();
        #endif

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

    captureUsageAfterWrite(core, uuid, driver);

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

    captureUsageAfterWrite(core, uuid, driver);

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

    captureUsageAfterWrite(core, uuid, driver);

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

    captureUsageAfterWrite(core, uuid, driver);

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

    captureUsageAfterWrite(core, uuid, driver);

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

    captureUsageAfterWrite(core, uuid, driver);

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

    captureUsageAfterWrite(core, uuid, driver);

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

    captureUsageAfterWrite(core, uuid, driver);

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

    captureUsageAfterWrite(core, uuid, driver);

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

    captureUsageAfterWrite(core, uuid, driver);

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

    captureUsageAfterWrite(core, uuid, driver);

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

        driverEventForwarder(t.uuid, refreshed, core);
    }

    return CORE_OK;
}

CoreResult core_usage_get_stats(CoreContext* core, CoreUsageStats* outStats)
{
    if (!core || !outStats) {
        setError(core, "Invalid parameters to core_usage_get_stats");
        return CORE_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(core->mutex);

    if (!core->initialized)
        return CORE_NOT_INITIALIZED;

    gatherUsageStatsLocked(core, outStats);
    return CORE_OK;
}

CoreResult core_usage_get_recommendation(CoreContext* core,
                                         CoreUsageRecommendation* outRecommendation)
{
    if (!core || !outRecommendation) {
        setError(core, "Invalid parameters to core_usage_get_recommendation");
        return CORE_INVALID_ARGUMENT;
    }

    std::memset(outRecommendation, 0, sizeof(CoreUsageRecommendation));

    std::lock_guard<std::mutex> lock(core->mutex);

    if (!core->initialized)
        return CORE_NOT_INITIALIZED;

    CoreUsageStats stats{};
    gatherUsageStatsLocked(core, &stats);

    if (stats.sampleCount < 20 || stats.confidence < 0.35f || stats.predictedArrivalHour < 0) {
        outRecommendation->available = false;
        return CORE_OK;
    }

    const uint64_t ts = nowMs();
    if (core->usageLastRecommendationTsMs > 0 &&
        (ts - core->usageLastRecommendationTsMs) < kRecommendationCooldownMs) {
        outRecommendation->available = false;
        return CORE_OK;
    }

    const int hourNow = hourOfDay(ts);
    const int h = stats.predictedArrivalHour;
    int hourDelta = std::abs(hourNow - h);
    hourDelta = std::min(hourDelta, 24 - hourDelta);

    // Suggest only around the predicted window to avoid noisy nudges.
    if (hourDelta > 1) {
        outRecommendation->available = false;
        return CORE_OK;
    }

    const int preferredTemp = static_cast<int>(std::llround(stats.preferredTemperature > 0.1f ? stats.preferredTemperature : 23.0f));
    const int preferredBright = static_cast<int>(stats.preferredBrightness > 0 ? stats.preferredBrightness : 45);

    std::string targetUuid = stats.mostActiveUuid;
    if (!targetUuid.empty()) {
        std::strncpy(outRecommendation->uuid, targetUuid.c_str(), CORE_MAX_UUID - 1);
        outRecommendation->uuid[CORE_MAX_UUID - 1] = '\0';
    }

    const int shownHour = std::clamp(h, 0, 23);
    std::snprintf(outRecommendation->title,
                  CORE_MAX_USAGE_TITLE,
                  "Routine detectada perto de %02dh",
                  shownHour);

    std::snprintf(outRecommendation->message,
                  CORE_MAX_USAGE_MESSAGE,
                  "Voce costuma chegar nesse horario. Recomendacao: manter conforto em %dC e brilho em %d%%.",
                  preferredTemp,
                  std::clamp(preferredBright, 0, 100));

    outRecommendation->recommendedHour = shownHour;
    outRecommendation->confidence = stats.confidence;
    outRecommendation->generatedAtMs = ts;
    outRecommendation->available = true;

    core->usageLastRecommendationTsMs = ts;
    return CORE_OK;
}

CoreResult core_usage_export_samples_csv(CoreContext* core,
                                         char* outBuffer,
                                         uint32_t bufferSize,
                                         uint32_t* outWritten)
{
    if (!core || !outBuffer || bufferSize == 0 || !outWritten) {
        setError(core, "Invalid parameters to core_usage_export_samples_csv");
        return CORE_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(core->mutex);

    if (!core->initialized)
        return CORE_NOT_INITIALIZED;

    std::ostringstream oss;
    oss << "ts_ms,uuid,hour_sin,hour_cos,power,brightness_norm,temp_norm,temp_fridge_norm,temp_freezer_norm,color_temp_norm,lock,mode_norm,position_norm\n";
    constexpr double kTwoPi = 6.28318530717958647692;

    for (const auto& sample : core->usageSamples) {
        const double hour = static_cast<double>(hourOfDay(sample.tsMs));
        const double angle = (kTwoPi * hour) / 24.0;
        const double hourSin = std::sin(angle);
        const double hourCos = std::cos(angle);
        const double brightnessNorm = std::clamp(static_cast<double>(sample.state.brightness) / 100.0, 0.0, 1.0);
        const double tempNorm = std::clamp((static_cast<double>(sample.state.temperature) - 16.0) / 14.0, 0.0, 1.0);
        const double tempFridgeNorm = std::clamp((static_cast<double>(sample.state.temperatureFridge) - 1.0) / 7.0, 0.0, 1.0);
        const double tempFreezerNorm = std::clamp((static_cast<double>(sample.state.temperatureFreezer) + 24.0) / 10.0, 0.0, 1.0);
        const double colorTempNorm = std::clamp((static_cast<double>(sample.state.colorTemperature) - 1500.0) / 7500.0, 0.0, 1.0);
        const double modeNorm = std::clamp(static_cast<double>(sample.state.mode) / 10.0, 0.0, 1.0);
        const double positionNorm = std::clamp(static_cast<double>(sample.state.position) / 100.0, 0.0, 1.0);

        oss << sample.tsMs << ","
            << sample.uuid << ","
            << hourSin << ","
            << hourCos << ","
            << (sample.state.power ? 1 : 0) << ","
            << brightnessNorm << ","
            << tempNorm << ","
            << tempFridgeNorm << ","
            << tempFreezerNorm << ","
            << colorTempNorm << ","
            << (sample.state.lock ? 1 : 0) << ","
            << modeNorm << ","
            << positionNorm << "\n";
    }

    const std::string csv = oss.str();
    if (csv.size() + 1 > bufferSize) {
        setError(core, "Output buffer too small for core_usage_export_samples_csv");
        return CORE_ERROR;
    }

    std::memcpy(outBuffer, csv.data(), csv.size());
    outBuffer[csv.size()] = '\0';
    *outWritten = static_cast<uint32_t>(csv.size());
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