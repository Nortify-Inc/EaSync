#pragma once

#include "driver.hpp"

#include <unordered_map>
#include <mutex>

namespace EaSync {

class MockDriver : public Driver {
public:
    bool init() override;

    bool connect(const std::string& uuid) override;

    void disconnect(const std::string& uuid) override;

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

    bool getState(
        const std::string& uuid,
        CoreDeviceState& outState
    ) override;

private:
    std::mutex mutex;

    std::unordered_map<
        std::string,
        CoreDeviceState
    > states;
};

}
