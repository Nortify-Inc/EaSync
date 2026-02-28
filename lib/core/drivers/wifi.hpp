#pragma once

#include "driver.hpp"

#include <unordered_map>
#include <mutex>
#include <string>

namespace drivers {

class WifiDriver : public Driver {

public:
    WifiDriver();
    ~WifiDriver() override = default;

    bool init() override;

    bool connect(const std::string& uuid) override;
    bool disconnect(const std::string& uuid) override;

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
    std::string resolveIpFromUuid(const std::string& uuid);

    bool httpPost(const std::string& url, const std::string& body);
    bool httpGet(const std::string& url, std::string& out);

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

    DriverEventCallback eventCallback = nullptr;
    void* eventUserData = nullptr;
};

}