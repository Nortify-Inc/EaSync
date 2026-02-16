#pragma once

#include "driver.hpp"

#include <unordered_map>
#include <mutex>
#include <string>

namespace drivers {

class WifiDriver : public Driver {
public:
    WifiDriver();

    bool init() override;

    bool connect(const std::string& uuid) override;

    bool disconnect(const std::string& uuid) override;

    bool setPower(
        const std::string& uuid,
        bool value
    ) override;

    bool setBrightness(
        const std::string& uuid,
        int value
    ) override;

    bool setColor(
        const std::string& uuid,
        uint32_t rgb
    ) override;

    bool setTemperature(
        const std::string& uuid,
        float value
    ) override;
    
    bool setTime(
        const std::string& uuid,
        uint64_t value
    ) override;
    
    bool getState(
        const std::string& uuid,
        CoreDeviceState& outState
    ) override;

    virtual bool isAvailable(
        const std::string& uuid
    ) override;

private:
    bool httpPost(
        const std::string& url,
        const std::string& body
    );

    bool httpGet(
        const std::string& url,
        std::string& out
    );

    void parseState(
        const std::string& uuid,
        const std::string& json
    );

private:
    std::mutex mutex;

    std::unordered_map<
        std::string,
        CoreDeviceState
    > states;

    std::unordered_map<
        std::string,
        std::string
    > deviceIps;
};

}
