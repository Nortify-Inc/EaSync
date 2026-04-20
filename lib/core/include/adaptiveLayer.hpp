#pragma once

/**
 * @file adaptiveLayer.hpp
 * @brief Adaptive connection layer for EaSync Core.
 *
 * Provides automatic connection management, device discovery,
 * and unified state handling across all protocols.
 *
 * @author Erick Radmann
 */

#include "core.h"
#include "driver.hpp"

#include <string>
#include <vector>
#include <memory>
#include <unordered_map>
#include <mutex>
#include <functional>
#include <chrono>

namespace core {

/**
 * @brief Connection states for a device.
 */
enum class ConnectionState {
    Disconnected,
    Connecting,
    Connected,
    Reconnecting,
    Error,
    Provisioning
};

/**
 * @brief Discovered device information.
 */
struct DiscoveredDevice {
    std::string uuid;
    std::string name;
    std::string host;
    uint16_t port;
    CoreProtocol protocol;
    std::string brand;
    std::string model;
    std::string vendor;
    float confidence;
    std::unordered_map<std::string, std::string> metadata;
    std::string hint;
};

/**
 * @brief Connection statistics.
 */
struct ConnectionStats {
    uint64_t lastConnectedAt{0};
    uint64_t lastDisconnectedAt{0};
    uint64_t lastStatePollAt{0};
    uint32_t reconnectAttempts{0};
    uint32_t consecutiveFailures{0};
    uint64_t averageLatencyMs{0};
    bool everConnected{false};
};

/**
 * @brief Adaptive connection configuration.
 */
struct AdaptiveConfig {
    // Connection timeouts
    std::chrono::milliseconds connectTimeout{8000};
    std::chrono::milliseconds reconnectDelay{2000};
    std::chrono::milliseconds reconnectMaxDelay{30000};
    uint32_t maxReconnectAttempts{5};

    // Discovery
    std::chrono::milliseconds discoveryTimeout{5000};
    std::chrono::milliseconds scanInterval{10000};

    // State polling
    std::chrono::milliseconds statePollInterval{5000};
    bool autoPollState{true};

    // WiFi provisioning
    std::chrono::milliseconds provisionTimeout{15000};
    std::vector<std::string> provisionEndpoints{
        "192.168.4.1",
        "192.168.8.1",
        "192.168.10.1",
        "192.168.0.1",
        "192.168.1.1",
        "10.0.0.1"
    };

    // BLE
    std::chrono::milliseconds bleScanTimeout{10000};
    std::chrono::milliseconds bleConnectTimeout{5000};
};

/**
 * @brief Event types for AdaptiveLayer.
 */
enum class AdaptiveEventType {
    DeviceDiscovered,
    DeviceLost,
    ConnectionStateChanged,
    ProvisioningStateChanged,
    Error
};

/**
 * @brief Event data.
 */
struct AdaptiveEvent {
    AdaptiveEventType type;
    std::string uuid;
    ConnectionState connectionState;
    std::string details;
    int errorCode{0};
};

/**
 * @brief Event callback type.
 */
using AdaptiveEventCallback = std::function<void(const AdaptiveEvent&)>;

/**
 * @brief Main adaptive connection layer.
 *
 * Manages device connections, discovery, and state synchronization
 * across all supported protocols (WiFi, BLE, MQTT, ZigBee).
 */
class AdaptiveLayer {
public:
    /**
     * @brief Get singleton instance.
     */
    static AdaptiveLayer& instance();

    /**
     * @brief Initialize adaptive layer.
     * @param config Configuration options.
     * @return true on success.
     */
    bool init(const AdaptiveConfig& config = AdaptiveConfig{});

    /**
     * @brief Shutdown adaptive layer.
     */
    void shutdown();

    /**
     * @brief Check if initialized.
     */
    bool isInitialized() const { return initialized; }

    /**
     * @brief Get shutdown flag for async cancellation.
     */
    std::shared_ptr<std::atomic<bool>> getShutdownFlag() const { return shutdownFlag; }

    // ============================================================
    // Connection Management
    // ============================================================

    /**
     * @brief Connect to a device.
     * @param uuid Device UUID.
     * @param protocol Protocol to use.
     * @return true if connection initiated successfully.
     */
    bool connect(const std::string& uuid, CoreProtocol protocol);
    bool connect(const std::string& uuid, CoreProtocol protocol,
                 const std::string& brand, const std::string& host = "");

    /**
     * @brief Disconnect from a device.
     * @param uuid Device UUID.
     * @return true if disconnected.
     */
    bool disconnect(const std::string& uuid);

    /**
     * @brief Ensure device is connected, reconnecting if needed.
     * @param uuid Device UUID.
     * @return true if connected after call.
     */
    bool ensureConnected(const std::string& uuid);

    /**
     * @brief Get connection state for a device.
     * @param uuid Device UUID.
     * @return Current connection state.
     */
    ConnectionState getConnectionState(const std::string& uuid);

    /**
     * @brief Get connection statistics.
     * @param uuid Device UUID.
     * @return Connection statistics.
     */
    ConnectionStats getConnectionStats(const std::string& uuid);

    /**
     * @brief Set endpoint for a device.
     * @param uuid Device UUID.
     * @param endpoint Host:port or URL.
     * @return true on success.
     */
    bool setEndpoint(const std::string& uuid, const std::string& endpoint);

    /**
     * @brief Set credential for a device.
     * @param uuid Device UUID.
     * @param key Credential key.
     * @param value Credential value.
     * @return true on success.
     */
    bool setCredential(const std::string& uuid, const std::string& key,
                       const std::string& value);

    // ============================================================
    // Discovery
    // ============================================================

    /**
     * @brief Discover devices on the network.
     * @param protocol Protocol to scan (CORE_PROTOCOL_MOCK for all).
     * @param timeoutMs Scan timeout in milliseconds.
     * @return List of discovered devices.
     */
    std::vector<DiscoveredDevice> discover(CoreProtocol protocol, int timeoutMs);

    /**
     * @brief Start background discovery.
     * @param protocol Protocol to scan.
     * @param callback Callback for discovered devices.
     * @return true if started.
     */
    bool startDiscovery(CoreProtocol protocol,
                        std::function<void(const DiscoveredDevice&)> callback);

    /**
     * @brief Stop background discovery.
     * @param protocol Protocol to stop.
     */
    void stopDiscovery(CoreProtocol protocol);

    // ============================================================
    // Provisioning
    // ============================================================

    /**
     * @brief Provision WiFi credentials to a device.
     * @param uuid Device UUID.
     * @param ssid WiFi SSID.
     * @param password WiFi password.
     * @param outError Optional error output.
     * @return true on success.
     */
    bool provisionWifi(const std::string& uuid, const std::string& ssid,
                       const std::string& password, std::string* outError = nullptr);

    /**
     * @brief Get provisioning state.
     * @param uuid Device UUID.
     * @return Provisioning state label.
     */
    std::string getProvisioningState(const std::string& uuid);

    // ============================================================
    // State Management
    // ============================================================

    /**
     * @brief Get device state.
     * @param uuid Device UUID.
     * @param outState Output state buffer.
     * @return true on success.
     */
    bool getState(const std::string& uuid, CoreDeviceState& outState);

    /**
     * @brief Set device state (internal use).
     * @param uuid Device UUID.
     * @param state New state.
     */
    void setState(const std::string& uuid, const CoreDeviceState& state);

    /**
     * @brief Check if device is available.
     * @param uuid Device UUID.
     * @return true if available.
     */
    bool isAvailable(const std::string& uuid);

    // ============================================================
    // Control Commands
    // ============================================================

    /**
     * @brief Send control command to device.
     * @param uuid Device UUID.
     * @param capability Capability name.
     * @param value Value as JSON string.
     * @return true on success.
     */
    bool sendCommand(const std::string& uuid, const std::string& capability,
                     const std::string& value);

    // ============================================================
    // Event Handling
    // ============================================================

    /**
     * @brief Set event callback.
     * @param callback Callback function.
     */
    void setEventCallback(AdaptiveEventCallback callback);

    // ============================================================
    // Driver Registration (internal)
    // ============================================================

    /**
     * @brief Register a driver for a protocol.
     * @param protocol Protocol.
     * @param driver Driver instance.
     */
    void registerDriver(CoreProtocol protocol,
                        std::shared_ptr<drivers::Driver> driver);

    /**
     * @brief Get driver for protocol.
     * @param protocol Protocol.
     * @return Driver instance or nullptr.
     */
    std::shared_ptr<drivers::Driver> getDriver(CoreProtocol protocol);

private:
    AdaptiveLayer() = default;
    ~AdaptiveLayer() = default;
    AdaptiveLayer(const AdaptiveLayer&) = delete;
    AdaptiveLayer& operator=(const AdaptiveLayer&) = delete;

    // Internal helpers
    void updateConnectionState(const std::string& uuid, ConnectionState state);
    void notifyEvent(const AdaptiveEvent& event);
    void startReconnectCycle(const std::string& uuid, CoreProtocol protocol);
    std::string generateUuid(const std::string& hint = "");

    // Discovery helpers
    std::vector<DiscoveredDevice> discoverMqtt(int timeoutMs);
    std::vector<DiscoveredDevice> discoverWifi(int timeoutMs);
    std::vector<DiscoveredDevice> discoverBle(int timeoutMs);
    std::vector<DiscoveredDevice> discoverZigbee(int timeoutMs);

    // State
    bool initialized = false;
    AdaptiveConfig config;

    // Drivers
    std::unordered_map<CoreProtocol, std::shared_ptr<drivers::Driver>> drivers;

    // Connection states
    std::mutex stateMutex;
    std::unordered_map<std::string, ConnectionState> connectionStates;
    std::unordered_map<std::string, ConnectionStats> connectionStats;
    std::unordered_map<std::string, CoreDeviceState> deviceStates;
    std::unordered_map<std::string, CoreProtocol> deviceProtocols;
    std::unordered_map<std::string, std::string> deviceEndpoints;
    std::unordered_map<std::string, std::string> deviceBrands;   ///< brand per uuid
    std::unordered_map<std::string, std::unordered_map<std::string, std::string>> deviceCredentials;

    // Discovery
    std::mutex discoveryMutex;
    std::unordered_map<CoreProtocol, bool> discoveryRunning;
    std::unordered_map<CoreProtocol, std::function<void(const DiscoveredDevice&)>> discoveryCallbacks;

    // Events
    AdaptiveEventCallback eventCallback;

    std::shared_ptr<std::atomic<bool>> shutdownFlag;
};

} // namespace core
