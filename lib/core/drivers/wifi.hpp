#pragma once

/**
 * @file wifi.hpp
 * @brief Declaration of the Wi-Fi driver based on HTTP requests for EaSync devices.
 * @param uuid Device identifier used for endpoint resolution.
 * @return Methods return true when the command/request is completed.
 * @author Erick Radmann
 */

#include "driver.hpp"

#include <unordered_map>
#include <mutex>
#include <string>
#include <vector>

namespace drivers {

enum class WifiTransportKind {
    Http,
    Tcp,
    Udp,
    Mixed
};

struct WifiVendorProfile {
    WifiTransportKind transport = WifiTransportKind::Http;
    std::vector<uint16_t> ports;
    bool mideaLike = false;
};

class WifiDriver : public Driver {

public:
    WifiDriver();
    ~WifiDriver() override = default;

    bool init() override;

    bool connect(const std::string& uuid) override;
    bool disconnect(const std::string& uuid) override;
    bool provisionWifi(
        const std::string& uuid,
        const std::string& ssid,
        const std::string& password,
        std::string* outError = nullptr
    ) override;

    void onDeviceRegistered(
        const std::string& uuid,
        const std::string& brand,
        const std::string& model
    ) override;

    void onDeviceRemoved(const std::string& uuid) override;

    bool setEndpoint(
        const std::string& uuid,
        const std::string& endpoint
    ) override;

    bool setCredential(
        const std::string& uuid,
        const std::string& key,
        const std::string& value
    ) override;

    bool setPower(const std::string& uuid, bool value) override;
    bool setBrightness(const std::string& uuid, uint32_t value) override;
    bool setColor(const std::string& uuid, uint32_t rgb) override;
    bool setTemperature(const std::string& uuid, float value) override;
    bool setTemperatureFridge(const std::string& uuid, float value) override;
    bool setTemperatureFreezer(const std::string& uuid, float value) override;
    bool setTime(const std::string& uuid, uint64_t value) override;
    bool setColorTemperature(const std::string& uuid, uint32_t value) override;
    bool setLock(const std::string& uuid, bool value) override;
    bool setMode(const std::string& uuid, uint32_t value) override;
    bool setPosition(const std::string& uuid, float value) override;
    

    bool getState(const std::string& uuid, CoreDeviceState& outState) override;
    bool isAvailable(const std::string& uuid) override;

    void setEventCallback(
        DriverEventCallback cb,
        void* userData
    ) override;

private:
    WifiVendorProfile buildProfile(const std::string& brand,
                                   const std::string& model) const;

    bool tryVendorTransports(const std::string& uuid,
                             const std::string& endpoint,
                             const std::string& payload);

    bool tcpSend(const std::string& host, uint16_t port, const std::string& payload);
    bool udpSend(const std::string& host, uint16_t port, const std::string& payload);

    bool httpPost(
        const std::string& url,
        const std::string& body,
        const std::string& contentType = "application/json",
        const std::string& method = "POST",
        std::string* outTrace = nullptr,
        const std::vector<std::string>& extraHeaders = {}
    );
    bool httpGet(const std::string& url, std::string& out);

    bool postCapabilityCommand(
        const std::string& uuid,
        const std::string& endpoint,
        const std::string& capability,
        const std::string& valueJson,
        const std::string& fallbackJson,
        const std::vector<std::string>& fallbackPaths
    );

    void parseState(
        const std::string& uuid,
        const std::string& json
    );

    void notifyStateChange(
        const std::string& uuid,
        const CoreDeviceState& newState
    );

private:
    std::mutex mutex;
    std::unordered_map<std::string, CoreDeviceState> states;
    std::unordered_map<std::string, std::string> deviceIps;
    std::unordered_map<std::string, bool> deviceMideaProfile;
    std::unordered_map<std::string, WifiVendorProfile> deviceProfiles;
    std::unordered_map<std::string, std::unordered_map<std::string, std::string>> deviceCredentials;

    DriverEventCallback eventCallback = nullptr;
    void* eventUserData = nullptr;
};

}