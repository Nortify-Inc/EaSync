/**
 * @file adaptiveLayer.cpp
 * @brief Implementation of the Adaptive connection layer for EaSync Core.
 * @author Erick Radmann
 */

#include "adaptiveLayer.hpp"

#include <algorithm>
#include <random>
#include <sstream>
#include <cstring>
#include <cstdio>
#include <cctype>
#include <chrono>
#include <thread>
#include <limits>

namespace core {

AdaptiveLayer& AdaptiveLayer::instance() {
    static AdaptiveLayer instance;
    return instance;
}

bool AdaptiveLayer::init(const AdaptiveConfig& cfg) {
    std::lock_guard<std::mutex> lock(stateMutex);
    if (initialized) {
        return true;
    }

    config = cfg;
    shutdownFlag = std::make_shared<std::atomic<bool>>(false);
    initialized = true;
    return true;
}

void AdaptiveLayer::shutdown() {
    std::lock_guard<std::mutex> lock(stateMutex);
    if (!initialized) {
        return;
    }

    if (shutdownFlag) {
        *shutdownFlag = true;
    }

    for (auto& pair : drivers) {
        if (pair.second) {
            pair.second.reset();
        }
    }
    drivers.clear();
    
    connectionStates.clear();
    connectionStats.clear();
    deviceStates.clear();
    deviceProtocols.clear();
    deviceEndpoints.clear();
    deviceBrands.clear();
    deviceCredentials.clear();

    initialized = false;
}

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

// Brand-aware overload: stores brand, sets endpoint, and notifies the driver
// so it can build the right WifiVendorProfile before any provisioning call.
bool AdaptiveLayer::connect(const std::string& uuid, CoreProtocol protocol,
                             const std::string& brand, const std::string& host) {
    // Store brand before the base connect so provisionWifi can read it.
    {
        std::lock_guard<std::mutex> lock(stateMutex);
        if (!brand.empty())
            deviceBrands[uuid] = brand;
        if (!host.empty())
            deviceEndpoints[uuid] = host;
    }

    // Let the driver know about the device so it builds the VendorProfile.
    auto driver = getDriver(protocol);
    if (driver) {
        // model = host when provided (used as endpoint hint inside WifiDriver)
        driver->onDeviceRegistered(uuid, brand, host);
        if (!host.empty())
            driver->setEndpoint(uuid, host);
    }

    return connect(uuid, protocol);
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
        deviceBrands.erase(uuid);
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
    std::shared_ptr<std::atomic<bool>> flag = shutdownFlag;
    std::thread([this, uuid, protocol, delay, flag]() {
        std::this_thread::sleep_for(std::chrono::milliseconds(delay));
        if (flag && *flag) return;
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

    std::vector<DiscoveredDevice> results;

    const std::vector<std::string> ifaces = {"wlan0", "wlp2s0", "wlp3s0",
                                              "wlan1", "wlp4s0"};
    std::string scanOutput;

    for (const auto& iface : ifaces) {
        const std::string cmd = "iwlist " + iface + " scan 2>/dev/null";
        FILE* fp = popen(cmd.c_str(), "r");
        if (!fp)
            continue;

        char buf[256];
        std::string out;
        while (fgets(buf, sizeof(buf), fp))
            out += buf;
        pclose(fp);

        if (out.find("ESSID") != std::string::npos) {
            scanOutput = std::move(out);
            break;
        }
    }

    if (scanOutput.empty())
        return results;

    struct BrandRule {
        std::string keyword;   // lowercase substring to match in SSID
        std::string brand;
        std::string vendor;
        float       confidence;
    };

    const std::vector<BrandRule> rules = {
        // Midea (highest confidence — documented SSID format)
        {"midea_",     "Midea",      "Midea Group",        0.95f},
        {"msmart_",    "Midea",      "Midea Group",        0.90f},
        {"net_ac_",    "Midea",      "Midea Group",        0.88f},
        {"nethome_",   "Midea",      "Midea Group",        0.85f},
        // Samsung SmartThings
        {"samsung_",   "Samsung",    "Samsung Electronics",0.90f},
        {"smartthings","Samsung",    "Samsung Electronics",0.88f},
        {"sam_",       "Samsung",    "Samsung Electronics",0.75f},
        // LG ThinQ
        {"lge_",       "LG",         "LG Electronics",     0.92f},
        {"lg_",        "LG",         "LG Electronics",     0.85f},
        {"thinq",      "LG",         "LG Electronics",     0.90f},
        // Electrolux / AEG
        {"electrolux", "Electrolux", "Electrolux Group",   0.95f},
        {"elux_",      "Electrolux", "Electrolux Group",   0.88f},
        {"aeg_",       "AEG",        "Electrolux Group",   0.88f},
        {"wellbeing",  "Electrolux", "Electrolux Group",   0.85f},
        // Daikin
        {"daikin",     "Daikin",     "Daikin Industries",  0.95f},
        {"dkin_",      "Daikin",     "Daikin Industries",  0.88f},
        // Tuya / SmartLife
        {"smartlife",  "Tuya",       "Tuya Inc.",           0.85f},
        {"ty_",        "Tuya",       "Tuya Inc.",           0.80f},
        {"beken_",     "Tuya",       "Tuya Inc.",           0.78f},
    };

    // Iterate over ESSID lines
    std::istringstream stream(scanOutput);
    std::string line;
    while (std::getline(stream, line)) {
        const auto esPos = line.find("ESSID:\"");
        if (esPos == std::string::npos)
            continue;

        const auto nameStart = esPos + 7; // length of ESSID:"
        const auto nameEnd   = line.find('"', nameStart);
        if (nameEnd == std::string::npos)
            continue;

        const std::string ssid = line.substr(nameStart, nameEnd - nameStart);
        if (ssid.empty())
            continue;

        // Lower-case for matching
        std::string ssidLower = ssid;
        std::transform(ssidLower.begin(), ssidLower.end(),
                       ssidLower.begin(),
                       [](unsigned char c){ return static_cast<char>(std::tolower(c)); });

        for (const auto& rule : rules) {
            if (ssidLower.find(rule.keyword) == std::string::npos)
                continue;

            DiscoveredDevice dev;
            dev.uuid     = generateUuid(rule.brand);
            dev.name     = ssid;
            dev.host     = "192.168.4.1";   // Standard SoftAP default
            dev.port     = 80;
            dev.protocol = CORE_PROTOCOL_WIFI;
            dev.brand    = rule.brand;
            dev.model    = ssid;            // SSID as model hint
            dev.vendor   = rule.vendor;
            dev.confidence = rule.confidence;
            dev.hint     = "ap_ssid:" + ssid;
            dev.metadata["ssid"] = ssid;

            results.push_back(std::move(dev));
            break; // first matching rule wins
        }
    }

    return results;
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

bool AdaptiveLayer::provisionWifi(const std::string& uuid, const std::string& ssid,
                                   const std::string& password, std::string* outError) {
    if (!initialized || ssid.empty() || password.empty()) {
        if (outError)
            *outError = "Invalid SSID or password";
        return false;
    }

    // Signal provisioning started
    updateConnectionState(uuid, ConnectionState::Provisioning);
    notifyEvent({AdaptiveEventType::ProvisioningStateChanged, uuid,
                 ConnectionState::Provisioning, "Starting WiFi provisioning", 0});

    CoreProtocol protocol = CORE_PROTOCOL_WIFI;
    std::string brand;

    {
        std::lock_guard<std::mutex> lock(stateMutex);
        auto it = deviceProtocols.find(uuid);
        if (it != deviceProtocols.end())
            protocol = it->second;

        auto bIt = deviceBrands.find(uuid);
        if (bIt != deviceBrands.end())
            brand = bIt->second;
    }

    if (protocol != CORE_PROTOCOL_WIFI) {
        if (outError) *outError = "Device is not a WiFi device";
        updateConnectionState(uuid, ConnectionState::Error);
        return false;
    }

    auto driver = getDriver(CORE_PROTOCOL_WIFI);
    if (!driver) {
        if (outError) *outError = "WiFi driver not available";
        updateConnectionState(uuid, ConnectionState::Error);
        return false;
    }

    const std::string brandLower = [&brand]{
        std::string s = brand;
        std::transform(s.begin(), s.end(), s.begin(),
                       [](unsigned char c){ return static_cast<char>(std::tolower(c)); });
        return s;
    }();

    if (brandLower.find("midea") != std::string::npos) {
        // Midea LAN v3 requires token + key fetched at cloud registration.
        // If the caller already stored them via setCredential, they will
        // be picked up by WifiDriver::tryVendorTransports automatically.
        // We emit a specific event so the UI can prompt if missing.

        notifyEvent({AdaptiveEventType::ProvisioningStateChanged, uuid,
                     ConnectionState::Provisioning,
                     "midea:token_key_required", 0});

    } else if (brandLower.find("tuya") != std::string::npos) {
        // Tuya LAN provisioning uses AES 128 ECB with the device's
        // localKey (obtained from Tuya cloud at first pairing).
        // We store it as a credential so WifiDriver can forward it.
        // The Flutter layer should have called setCredential("localKey", ...)
        // before this; we just ensure it's propagated to the driver.

        const std::string stored = [&]{
            std::lock_guard<std::mutex> lock(stateMutex);
            auto cIt = deviceCredentials.find(uuid);
            if (cIt != deviceCredentials.end()) {
                auto kIt = cIt->second.find("localkey");
                if (kIt != cIt->second.end())
                    return kIt->second;
            }
            return std::string{};
        }();

        if (!stored.empty())
            driver->setCredential(uuid, "localkey", stored);

        notifyEvent({AdaptiveEventType::ProvisioningStateChanged, uuid,
                     ConnectionState::Provisioning,
                     "tuya:aes_ecb_localkey", 0});
    } else if (brandLower.find("samsung") != std::string::npos) {
        notifyEvent({AdaptiveEventType::ProvisioningStateChanged, uuid,
                     ConnectionState::Provisioning,
                     "samsung:smartthings_lan_api", 0});

    } else if (brandLower.find("lg") != std::string::npos) {
        notifyEvent({AdaptiveEventType::ProvisioningStateChanged, uuid,
                     ConnectionState::Provisioning,
                     "lg:thinq_local_api", 0});

    } else if (brandLower.find("daikin") != std::string::npos) {
        notifyEvent({AdaptiveEventType::ProvisioningStateChanged, uuid,
                     ConnectionState::Provisioning,
                     "daikin:http_basic_info", 0});

    } else if (brandLower.find("electrolux") != std::string::npos ||
               brandLower.find("aeg") != std::string::npos) {
        notifyEvent({AdaptiveEventType::ProvisioningStateChanged, uuid,
                     ConnectionState::Provisioning,
                     "electrolux:wellbeing_ap", 0});

    }

    // Delegate to WifiDriver which handles the actual HTTP exchange
    std::string error;
    const bool success = driver->provisionWifi(uuid, ssid, password, &error);

    if (!success) {
        if (outError) *outError = error;
        updateConnectionState(uuid, ConnectionState::Error);
        notifyEvent({AdaptiveEventType::ProvisioningStateChanged, uuid,
                     ConnectionState::Error, error, 0});
        return false;
    }

    // Provisioning succeeded so device should now join the user's network.
    // Emit a detailed success event so Flutter can show brand-specific
    // "connecting to your WiFi…" feedback.
    const std::string successDetail = "wifi_provisioned:brand=" + brand +
                                      ":ssid=" + ssid;
    updateConnectionState(uuid, ConnectionState::Connected);
    notifyEvent({AdaptiveEventType::ProvisioningStateChanged, uuid,
                 ConnectionState::Connected, successDetail, 0});
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

void AdaptiveLayer::setEventCallback(AdaptiveEventCallback callback) {
    eventCallback = callback;
}

void AdaptiveLayer::notifyEvent(const AdaptiveEvent& event) {
    if (eventCallback) {
        eventCallback(event);
    }
}

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

    return ss.str();
}

} // namespace core
