#pragma once

#include "driver.hpp"

#include <unordered_map>
#include <mutex>
#include <string>
#include <memory>

#include <mqtt/async_client.h>

namespace drivers {

class MqttDriver : public Driver, public virtual mqtt::callback {

public:
    MqttDriver();

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

    virtual bool isAvailable(
        const std::string& uuid
    ) override;

private:
    void publishCommand(
        const std::string& uuid,
        const std::string& json
    );

    void parseState(
        const std::string& uuid,
        const std::string& payload
    );

    void connection_lost(
        const std::string& cause
    ) override;

    void message_arrived(
        mqtt::const_message_ptr msg
    ) override;

    void delivery_complete(
        mqtt::delivery_token_ptr tok
    ) override;

private:
    std::mutex mutex;

    std::unordered_map<
        std::string,
        CoreDeviceState
    > states;

    std::unique_ptr<mqtt::async_client> client;

    bool connected = false;

    std::string brokerUrl;
    std::string clientId;
};

}
