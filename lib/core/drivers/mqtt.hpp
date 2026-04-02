#pragma once

/**
 * @file mqtt.hpp
 * @brief Declaration of the MQTT driver for EaSync state publishing and consumption.
 * @param uuid Device identifier used for MQTT topic routing.
 * @return Methods return true when the operation is accepted by the driver.
 * @author Erick Radmann
 */

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
    ~MqttDriver() override = default;

    bool init() override;

    bool connect(const std::string& uuid) override;
    bool disconnect(const std::string& uuid) override;

    void onDeviceRegistered(
        const std::string& uuid,
        const std::string& brand,
        const std::string& model
    ) override;

    void onDeviceRemoved(const std::string& uuid) override;

    bool setPower(const std::string& uuid, bool value) override;
    bool setColor(const std::string& uuid, uint32_t rgb) override;
    bool setBrightness(const std::string& uuid, uint32_t value) override;
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
    bool ensureBrokerConnection(const std::string& preferredBroker = "");

    void publishCommand(
        const std::string& uuid,
        const std::string& json,
        const std::string& topicOverride = ""
    );

    void parseState(
        const std::string& uuid,
        const std::string& payload
    );

    void notifyStateChange(
        const std::string& uuid,
        const CoreDeviceState& newState
    );

    // MQTT callbacks
    void connection_lost(const std::string& cause) override;
    void message_arrived(mqtt::const_message_ptr msg) override;
    void delivery_complete(mqtt::delivery_token_ptr tok) override;

private:
    std::mutex mutex;
    std::unordered_map<std::string, CoreDeviceState> states;
    std::unordered_map<std::string, std::string> preferredBrokerByDevice;
    std::unordered_map<std::string, std::string> preferredPrefixByDevice;

    std::unique_ptr<mqtt::async_client> client;

    bool connected = false;

    std::string brokerUrl = "tcp://localhost:1883";
    std::string clientId = "easync-client";
    std::string topicPrefix = "easync";
    mqtt::connect_options cachedConnectOptions;

    DriverEventCallback eventCallback = nullptr;
    void* eventUserData = nullptr;
};

}