#pragma once

#include "driver.hpp"

#include <unordered_map>
#include <string>
#include <mutex>

#include <gattlib.h>

namespace drivers {

class BleDriver : public Driver {
public:
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

    bool getState(
        const std::string& uuid,
        CoreDeviceState& outState
    ) override;

    bool isAvailable(
        const std::string& uuid
    ) override;

private:
    bool discoverCharacteristics(
        const std::string& mac
    );

private:
    std::mutex mutex;

    std::unordered_map<
        std::string,
        gattlib_connection_t*
    > connections;

    std::unordered_map<
        std::string,
        std::unordered_map<
            std::string,
            uuid_t
        >
    > characteristics;

    std::unordered_map<
        std::string,
        CoreDeviceState
    > states;
};

}
