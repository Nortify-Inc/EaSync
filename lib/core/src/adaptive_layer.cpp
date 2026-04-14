/**
 * @file adaptive_layer.cpp
 * @brief Implementation of the Adaptive connection layer for EaSync Core.
 * @author Erick Radmann
 */

#include "adaptive_layer.hpp"

#include <algorithm>
#include <random>
#include <sstream>
#include <cstring>
#include <chrono>
#include <thread>
#include <limits>

namespace core {

// ============================================================
// Singleton
// ============================================================

AdaptiveLayer& AdaptiveLayer::instance() {
    static AdaptiveLayer instance;
    return instance;
}

// ============================================================
// Initialization
// ============================================================

bool AdaptiveLayer::init(const AdaptiveConfig& cfg) {
    if (initialized) {
        return true;
    }

    config = cfg;
    initialized = true;
    return true;
}

void AdaptiveLayer::shutdown() {
    std::lock_guard<std::mutex> lock(stateMutex);

    // Disconnect all devices
    for (auto& [uuid, state] : connectionStates) {
        auto protoIt = deviceProtocols.find(uuid);
        if (protoIt != deviceProtocols.end()) {
            auto driverIt = drivers.find(protoIt->second);
            if (driverIt != drivers.end()) {
                driverIt->second->disconnect(uuid);
            }
        }
    }

    connectionStates.clear();
    connectionStats.clear();
    deviceStates.clear();
    deviceProtocols.clear();
    deviceEndpoints.clear();
    deviceCredentials.clear();

    initialized = false;
}

// ============================================================
// Driver Registration
// ============================================================

void AdaptiveLayer::registerDriver(CoreProtocol protocol,
                                    std::shared_ptr<drivers::Driver> driver) {
    std::lock_guard<std::mutex> lock(stateMutex);
    drivers[protocol] = driver;
}

std::shared_ptr<drivers::Driver> AdaptiveLayer::getDriver(CoreProtocol protocol) {
    std::lock_guard<std::mutex> lock(stateMutex);
    auto it = drivers.find(protocol);
    if (it != drivers.end()) {
        return it->second;
    }
    return nullptr;
}

// ============================================================
// Connection Management
// ============================================================

bool AdaptiveLayer::connect(const std::string& uuid, CoreProtocol protocol) {
    if (!initialized) {
        return false;
    }

    auto driver = getDriver(protocol);
    if (!driver) {
        notifyEvent({AdaptiveEventType::Error, uuid, ConnectionState::Error,
                     "Driver not found for protocol", static_cast<int>(protocol)});
        return false;
    }

    updateConnectionState(uuid, ConnectionState::Connecting);

    if (!driver->connect(uuid)) {
        updateConnectionState(uuid, ConnectionState::Error);
        notifyEvent({AdaptiveEventType::Error, uuid, ConnectionState::Error,
                     "Failed to connect device", 0});
        return false;
    }

    // Initialize state
    {
        std::lock_guard<std::mutex> lock(stateMutex);
        deviceProtocols[uuid] = protocol;

        CoreDeviceState initialState{};
        std::memset(&initialState, 0, sizeof(CoreDeviceState));
        deviceStates[uuid] = initialState;

        auto& stats = connectionStats[uuid];
        stats.reconnectAttempts = 0;
        stats.consecutiveFailures = 0;
        stats.lastConnectedAt = static_cast<uint64_t>(
            std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::system_clock::now().time_since_epoch()).count());
        stats.everConnected = true;
    }

    updateConnectionState(uuid, ConnectionState::Connected);
    notifyEvent({AdaptiveEventType::ConnectionStateChanged, uuid,
                 ConnectionState::Connected, "Connected successfully", 0});
    return true;
}

bool AdaptiveLayer::disconnect(const std::string& uuid) {
    if (!initialized) {
        return false;
    }

    CoreProtocol protocol;
    {
        std::lock_guard<std::mutex> lock(stateMutex);
        auto it = deviceProtocols.find(uuid);
        if (it == deviceProtocols.end()) {
            return false;
        }
        protocol = it->second;
    }

    auto driver = getDriver(protocol);
    if (driver) {
        driver->disconnect(uuid);
        driver->onDeviceRemoved(uuid);
    }

    updateConnectionState(uuid, ConnectionState::Disconnected);

    {
        std::lock_guard<std::mutex> lock(stateMutex);
        auto statsIt = connectionStats.find(uuid);
        if (statsIt != connectionStats.end()) {
            statsIt->second.lastDisconnectedAt = static_cast<uint64_t>(
                std::chrono::duration_cast<std::chrono::milliseconds>(
                    std::chrono::system_clock::now().time_since_epoch()).count());
        }
    }

    notifyEvent({AdaptiveEventType::ConnectionStateChanged, uuid,
                 ConnectionState::Disconnected, "Disconnected", 0});
    return true;
}

bool AdaptiveLayer::ensureConnected(const std::string& uuid) {
    if (!initialized) {
        return false;
    }

    auto state = getConnectionState(uuid);
    if (state == ConnectionState::Connected) {
        return true;
    }

    CoreProtocol protocol;
    {
        std::lock_guard<std::mutex> lock(stateMutex);
        auto it = deviceProtocols.find(uuid);
        if (it == deviceProtocols.end()) {
            return false;
        }
        protocol = it->second;
    }

    // Attempt reconnection
    updateConnectionState(uuid, ConnectionState::Reconnecting);

    if (connect(uuid, protocol)) {
        return true;
    }

    // Schedule reconnect cycle
    startReconnectCycle(uuid, protocol);
    return false;
}

void AdaptiveLayer::startReconnectCycle(const std::string& uuid, CoreProtocol protocol) {
    uint32_t attempts = 0;
    uint64_t delay = 0;

    {
        std::lock_guard<std::mutex> lock(stateMutex);

        auto& stats = connectionStats[uuid];
        if (stats.reconnectAttempts >= config.maxReconnectAttempts) {
            attempts = stats.reconnectAttempts;
        } else {
            stats.reconnectAttempts++;
            stats.consecutiveFailures++;
            attempts = stats.reconnectAttempts;

            // Exponential backoff
            delay = static_cast<uint64_t>(config.reconnectDelay.count()) *
                    (1ULL << std::min(attempts, 5u));
            delay = std::min(delay, static_cast<uint64_t>(config.reconnectMaxDelay.count()));
        }
    }

    if (attempts >= config.maxReconnectAttempts && delay == 0) {
        updateConnectionState(uuid, ConnectionState::Error);
        notifyEvent({AdaptiveEventType::Error, uuid, ConnectionState::Error,
                     "Max reconnect attempts reached", 0});
        return;
    }

    // Schedule reconnect (in production, use a proper timer)
    std::thread([this, uuid, protocol, delay]() {
        std::this_thread::sleep_for(std::chrono::milliseconds(delay));
        connect(uuid, protocol);
    }).detach();
}

ConnectionState AdaptiveLayer::getConnectionState(const std::string& uuid) {
    std::lock_guard<std::mutex> lock(stateMutex);
    auto it = connectionStates.find(uuid);
    if (it != connectionStates.end()) {
        return it->second;
    }
    return ConnectionState::Disconnected;
}

ConnectionStats AdaptiveLayer::getConnectionStats(const std::string& uuid) {
    std::lock_guard<std::mutex> lock(stateMutex);
    auto it = connectionStats.find(uuid);
    if (it != connectionStats.end()) {
        return it->second;
    }
    return ConnectionStats{};
}

bool AdaptiveLayer::setEndpoint(const std::string& uuid, const std::string& endpoint) {
    if (!initialized || endpoint.empty()) {
        return false;
    }

    std::lock_guard<std::mutex> lock(stateMutex);

    auto protoIt = deviceProtocols.find(uuid);
    if (protoIt == deviceProtocols.end()) {
        return false;
    }

    deviceEndpoints[uuid] = endpoint;

    auto driver = drivers.find(protoIt->second);
    if (driver != drivers.end()) {
        return driver->second->setEndpoint(uuid, endpoint);
    }
    return true;
}

bool AdaptiveLayer::setCredential(const std::string& uuid, const std::string& key,
                                   const std::string& value) {
    if (!initialized || key.empty()) {
        return false;
    }

    std::lock_guard<std::mutex> lock(stateMutex);

    auto protoIt = deviceProtocols.find(uuid);
    if (protoIt == deviceProtocols.end()) {
        return false;
    }

    deviceCredentials[uuid][key] = value;

    auto driver = drivers.find(protoIt->second);
    if (driver != drivers.end()) {
        return driver->second->setCredential(uuid, key, value);
    }
    return true;
}

void AdaptiveLayer::updateConnectionState(const std::string& uuid, ConnectionState state) {
    {
        std::lock_guard<std::mutex> lock(stateMutex);
        connectionStates[uuid] = state;
    }
    notifyEvent({AdaptiveEventType::ConnectionStateChanged, uuid, state, "", 0});
}

// ============================================================
// Discovery
// ============================================================

std::vector<DiscoveredDevice> AdaptiveLayer::discover(CoreProtocol protocol, int timeoutMs) {
    std::vector<DiscoveredDevice> results;

    switch (protocol) {
        case CORE_PROTOCOL_MQTT:
            results = discoverMqtt(timeoutMs);
            break;
        case CORE_PROTOCOL_WIFI:
            results = discoverWifi(timeoutMs);
            break;
        case CORE_PROTOCOL_BLE:
            results = discoverBle(timeoutMs);
            break;
        case CORE_PROTOCOL_ZIGBEE:
            results = discoverZigbee(timeoutMs);
            break;
        case CORE_PROTOCOL_MOCK:
        default:
            // Discover all protocols
            {
                auto mqtt = discoverMqtt(timeoutMs / 4);
                results.insert(results.end(), mqtt.begin(), mqtt.end());

                auto wifi = discoverWifi(timeoutMs / 4);
                results.insert(results.end(), wifi.begin(), wifi.end());

                auto ble = discoverBle(timeoutMs / 4);
                results.insert(results.end(), ble.begin(), ble.end());

                auto zigbee = discoverZigbee(timeoutMs / 4);
                results.insert(results.end(), zigbee.begin(), zigbee.end());
            }
            break;
    }

    // Notify discovery events
    for (const auto& device : results) {
        notifyEvent({AdaptiveEventType::DeviceDiscovered, device.uuid,
                     ConnectionState::Disconnected, device.vendor, 0});
    }

    return results;
}

std::vector<DiscoveredDevice> AdaptiveLayer::discoverMqtt(int timeoutMs) {
    std::vector<DiscoveredDevice> results;
    (void)timeoutMs; // MQTT discovery requires broker connection

    // MQTT devices are typically known beforehand via broker topics
    // This would require actual MQTT subscription to discovery topics
    return results;
}

std::vector<DiscoveredDevice> AdaptiveLayer::discoverWifi(int timeoutMs) {
    (void)timeoutMs;
    // Real Wi-Fi probing is handled in Dart (Bridge.discoverDevices),
    // so avoid returning synthetic hosts here.
    return {};
}

std::vector<DiscoveredDevice> AdaptiveLayer::discoverBle(int timeoutMs) {
    std::vector<DiscoveredDevice> results;

    // BLE discovery via platform-specific APIs
    // Linux: BlueZ D-Bus
    // macOS/iOS: CoreBluetooth
    // Windows: WinRT Bluetooth
    // Android: BluetoothLeScanner (via Flutter)

    (void)timeoutMs;

    // Placeholder - actual implementation requires platform integration
    return results;
}

std::vector<DiscoveredDevice> AdaptiveLayer::discoverZigbee(int timeoutMs) {
    std::vector<DiscoveredDevice> results;
    (void)timeoutMs;

    // Zigbee discovery via zigbee2mqtt or similar bridge
    // Would require MQTT subscription to zigbee2mqtt/bridge/devices
    return results;
}

bool AdaptiveLayer::startDiscovery(CoreProtocol protocol,
                                    std::function<void(const DiscoveredDevice&)> callback) {
    std::lock_guard<std::mutex> lock(discoveryMutex);

    if (discoveryRunning.count(protocol) && discoveryRunning[protocol]) {
        return false;
    }

    discoveryRunning[protocol] = true;
    discoveryCallbacks[protocol] = callback;

    // Start background discovery thread
    std::thread([this, protocol]() {
        const int scanIntervalMs = static_cast<int>(config.scanInterval.count());

        while (true) {
            {
                std::lock_guard<std::mutex> lock(discoveryMutex);
                if (!discoveryRunning.count(protocol) || !discoveryRunning[protocol]) {
                    break;
                }
            }

            auto devices = discover(protocol, static_cast<int>(config.discoveryTimeout.count()));

            for (const auto& device : devices) {
                std::lock_guard<std::mutex> lock(discoveryMutex);
                if (discoveryCallbacks.count(protocol) && discoveryCallbacks[protocol]) {
                    discoveryCallbacks[protocol](device);
                }
            }

            std::this_thread::sleep_for(std::chrono::milliseconds(scanIntervalMs));
        }
    }).detach();

    return true;
}

void AdaptiveLayer::stopDiscovery(CoreProtocol protocol) {
    std::lock_guard<std::mutex> lock(discoveryMutex);
    discoveryRunning[protocol] = false;
    discoveryCallbacks.erase(protocol);
}

// ============================================================
// Provisioning
// ============================================================

bool AdaptiveLayer::provisionWifi(const std::string& uuid, const std::string& ssid,
                                   const std::string& password, std::string* outError) {
    if (!initialized || ssid.empty() || password.empty()) {
        if (outError) {
            *outError = "Invalid SSID or password";
        }
        return false;
    }

    updateConnectionState(uuid, ConnectionState::Provisioning);

    CoreProtocol protocol;
    {
        std::lock_guard<std::mutex> lock(stateMutex);
        auto it = deviceProtocols.find(uuid);
        if (it == deviceProtocols.end()) {
            if (outError) *outError = "Device not found";
            updateConnectionState(uuid, ConnectionState::Error);
            return false;
        }
        protocol = it->second;
    }

    if (protocol != CORE_PROTOCOL_WIFI) {
        if (outError) *outError = "Device is not a WiFi device";
        updateConnectionState(uuid, ConnectionState::Error);
        return false;
    }

    auto driver = getDriver(protocol);
    if (!driver) {
        if (outError) *outError = "WiFi driver not available";
        updateConnectionState(uuid, ConnectionState::Error);
        return false;
    }

    std::string error;
    bool success = driver->provisionWifi(uuid, ssid, password, &error);

    if (!success) {
        if (outError) *outError = error;
        updateConnectionState(uuid, ConnectionState::Error);
        notifyEvent({AdaptiveEventType::ProvisioningStateChanged, uuid,
                     ConnectionState::Error, error, 0});
        return false;
    }

    updateConnectionState(uuid, ConnectionState::Connected);
    notifyEvent({AdaptiveEventType::ProvisioningStateChanged, uuid,
                 ConnectionState::Connected, "WiFi provisioned successfully", 0});
    return true;
}

std::string AdaptiveLayer::getProvisioningState(const std::string& uuid) {
    auto state = getConnectionState(uuid);

    switch (state) {
        case ConnectionState::Disconnected:
            return "unprovisioned";
        case ConnectionState::Provisioning:
            return "provisioning";
        case ConnectionState::Connecting:
            return "ap_connected";
        case ConnectionState::Connected:
            return "online";
        case ConnectionState::Reconnecting:
            return "reconnecting";
        case ConnectionState::Error:
            return "failed";
        default:
            return "unknown";
    }
}

// ============================================================
// State Management
// ============================================================

bool AdaptiveLayer::getState(const std::string& uuid, CoreDeviceState& outState) {
    if (!initialized) {
        return false;
    }

    CoreProtocol protocol = CORE_PROTOCOL_MOCK;
    CoreDeviceState cachedState{};
    bool hasCachedState = false;

    {
        std::lock_guard<std::mutex> lock(stateMutex);

        auto it = deviceStates.find(uuid);
        if (it != deviceStates.end()) {
            cachedState = it->second;
            hasCachedState = true;
        }

        auto protoIt = deviceProtocols.find(uuid);
        if (protoIt != deviceProtocols.end()) {
            protocol = protoIt->second;
        } else if (!hasCachedState) {
            return false;
        }
    }

    auto driver = getDriver(protocol);
    if (driver) {
        CoreDeviceState freshState{};
        if (driver->getState(uuid, freshState)) {
            std::lock_guard<std::mutex> lock(stateMutex);
            deviceStates[uuid] = freshState;
            outState = freshState;
            return true;
        }
    }

    if (hasCachedState) {
        outState = cachedState;
        return true;
    }

    return false;
}

void AdaptiveLayer::setState(const std::string& uuid, const CoreDeviceState& state) {
    std::lock_guard<std::mutex> lock(stateMutex);
    deviceStates[uuid] = state;
}

bool AdaptiveLayer::isAvailable(const std::string& uuid) {
    if (!initialized) {
        return false;
    }

    std::lock_guard<std::mutex> lock(stateMutex);

    auto protoIt = deviceProtocols.find(uuid);
    if (protoIt == deviceProtocols.end()) {
        return false;
    }

    auto driverIt = drivers.find(protoIt->second);
    if (driverIt != drivers.end() && driverIt->second) {
        return driverIt->second->isAvailable(uuid);
    }

    return false;
}

// ============================================================
// Control Commands
// ============================================================

bool AdaptiveLayer::sendCommand(const std::string& uuid, const std::string& capability,
                                 const std::string& value) {
    if (!initialized) {
        return false;
    }

    // Ensure connected before sending command
    if (!ensureConnected(uuid)) {
        return false;
    }

    CoreProtocol protocol;
    {
        std::lock_guard<std::mutex> lock(stateMutex);
        auto it = deviceProtocols.find(uuid);
        if (it == deviceProtocols.end()) {
            return false;
        }
        protocol = it->second;
    }

    auto driver = getDriver(protocol);
    if (!driver) {
        return false;
    }

    bool success = false;

    const auto parseBool = [&](bool& out) {
        if (value == "true" || value == "1" || value == "on" || value == "lock") {
            out = true;
            return true;
        }
        if (value == "false" || value == "0" || value == "off" || value == "unlock") {
            out = false;
            return true;
        }
        return false;
    };

    const auto parseUint32 = [&](uint32_t& out) {
        try {
            const unsigned long parsed = std::stoul(value);
            if (parsed > static_cast<unsigned long>(std::numeric_limits<uint32_t>::max()))
                return false;
            out = static_cast<uint32_t>(parsed);
            return true;
        } catch (...) {
            return false;
        }
    };

    const auto parseUint64 = [&](uint64_t& out) {
        try {
            out = static_cast<uint64_t>(std::stoull(value));
            return true;
        } catch (...) {
            return false;
        }
    };

    const auto parseFloat = [&](float& out) {
        try {
            out = std::stof(value);
            return true;
        } catch (...) {
            return false;
        }
    };

    if (capability == "power") {
        bool v = false;
        success = parseBool(v) && driver->setPower(uuid, v);
    } else if (capability == "brightness") {
        uint32_t v = 0;
        success = parseUint32(v) && driver->setBrightness(uuid, v);
    } else if (capability == "color") {
        uint32_t v = 0;
        success = parseUint32(v) && driver->setColor(uuid, v);
    } else if (capability == "temperature") {
        float v = 0.0f;
        success = parseFloat(v) && driver->setTemperature(uuid, v);
    } else if (capability == "temperature_fridge") {
        float v = 0.0f;
        success = parseFloat(v) && driver->setTemperatureFridge(uuid, v);
    } else if (capability == "temperature_freezer") {
        float v = 0.0f;
        success = parseFloat(v) && driver->setTemperatureFreezer(uuid, v);
    } else if (capability == "time" || capability == "timestamp") {
        uint64_t v = 0;
        success = parseUint64(v) && driver->setTime(uuid, v);
    } else if (capability == "color_temperature") {
        uint32_t v = 0;
        success = parseUint32(v) && driver->setColorTemperature(uuid, v);
    } else if (capability == "lock") {
        bool v = false;
        success = parseBool(v) && driver->setLock(uuid, v);
    } else if (capability == "mode") {
        uint32_t v = 0;
        success = parseUint32(v) && driver->setMode(uuid, v);
    } else if (capability == "position") {
        float v = 0.0f;
        success = parseFloat(v) && driver->setPosition(uuid, v);
    }

    if (success) {
        // Update cached state
        auto stateIt = deviceStates.find(uuid);
        if (stateIt != deviceStates.end()) {
            // Refresh state from driver
            CoreDeviceState newState;
            if (driver->getState(uuid, newState)) {
                deviceStates[uuid] = newState;
            }
        }
    }

    return success;
}

// ============================================================
// Event Handling
// ============================================================

void AdaptiveLayer::setEventCallback(AdaptiveEventCallback callback) {
    eventCallback = callback;
}

void AdaptiveLayer::notifyEvent(const AdaptiveEvent& event) {
    if (eventCallback) {
        eventCallback(event);
    }
}

// ============================================================
// Utilities
// ============================================================

std::string AdaptiveLayer::generateUuid(const std::string& hint) {
    static std::random_device rd;
    static std::mt19937 gen(rd());
    static std::uniform_int_distribution<> dis(0, 15);
    static std::uniform_int_distribution<> dis2(8, 11);

    std::stringstream ss;
    ss << std::hex;

    for (int i = 0; i < 8; i++) ss << dis(gen);
    ss << "-";
    for (int i = 0; i < 4; i++) ss << dis(gen);
    ss << "-4";
    for (int i = 0; i < 3; i++) ss << dis(gen);
    ss << "-";
    ss << dis2(gen);
    for (int i = 0; i < 3; i++) ss << dis(gen);
    ss << "-";
    for (int i = 0; i < 12; i++) ss << dis(gen);

    std::string prefix = hint.empty() ? "dev" : hint;
    return prefix + "-" + ss.str();
}

} // namespace core
