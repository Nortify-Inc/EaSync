#pragma once

/**
 * @file zigbee.hpp
 * @brief Declaration of the ZigBee driver integrated through an MQTT broker.
 * @param uuid ZigBee device identifier mapped on the broker.
 * @return Methods return true when the command is sent/processed.
 * @author Erick Radmann
 */

#include "driver.hpp"

#include <mqtt/async_client.h>
#include <unordered_map>
#include <mutex>
#include <string>
#include <memory>

namespace drivers {

class ZigBeeDriver :
    public Driver,
    public virtual mqtt::callback
{
public:

    ZigBeeDriver();

    ~ZigBeeDriver() override;

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

    void connection_lost(const std::string& cause) override;
    void message_arrived(mqtt::const_message_ptr msg) override;
    void delivery_complete(mqtt::delivery_token_ptr token) override;

private:

    void publishCommand(
        const std::string& uuid,
        const std::string& json
    );

    void parseState(
        const std::string& uuid,
        const std::string& payload
    );

    void notifyStateChange(
        const std::string& uuid,
        const CoreDeviceState& newState
    );

private:

    std::unique_ptr<mqtt::async_client> client;

    std::string brokerUrl;
    std::string clientId;

    bool connected = false;

    std::mutex mutex;

    std::unordered_map<std::string, CoreDeviceState> states;

    DriverEventCallback eventCallback = nullptr;
    void* eventUserData = nullptr;
};

}