/**
 * @file mqtt.cpp
 * @brief Implementation of the MQTT driver for command publishing and state reading.
 * @param uuid Device identifier represented in MQTT topics.
 * @return Methods return true when the operation is accepted by the driver.
 * @author Erick Radmann
 */

#include "mqtt.hpp"
#include "payload_service.hpp"

#include <iostream>
#include <sstream>
#include <vector>
#include <cstdlib>
#include <cstring>

namespace drivers {

static core::PayloadCommand buildCommandFromTemplate(
    const std::string& uuid,
    const std::string& capability,
    const std::string& valueJson,
    const std::string& fallbackJson
) {
    core::PayloadCommand fromTemplate = core::PayloadService::instance().createCommand(
        uuid,
        capability,
        valueJson
    );

    if (!fromTemplate.payload.empty() || !fromTemplate.topic.empty())
        return fromTemplate;

    core::PayloadCommand fallback;
    fallback.payload = fallbackJson;
    return fallback;
}

MqttDriver::MqttDriver() {}

bool MqttDriver::init() {
    std::vector<std::string> candidates;

    if (const char* env = std::getenv("EASYNC_MQTT_BROKER")) {
        if (std::strlen(env) > 0)
            candidates.emplace_back(env);
    }

    candidates.push_back(brokerUrl);
    candidates.push_back("tcp://127.0.0.1:1883");
    candidates.push_back("tcp://mosquitto:1883");
    candidates.push_back("tcp://homeassistant.local:1883");
    candidates.push_back("tcp://192.168.1.1:1883");
    candidates.push_back("ssl://homeassistant.local:8883");
    candidates.push_back("ssl://192.168.1.1:8883");

    mqtt::connect_options opts;
    const bool forceTls =
        (std::getenv("EASYNC_MQTT_TLS") != nullptr &&
         std::string(std::getenv("EASYNC_MQTT_TLS")) == "1");

    for (const auto& candidate : candidates) {
        try {
            auto nextClient = std::make_unique<mqtt::async_client>(candidate, clientId);
            nextClient->set_callback(*this);

            mqtt::connect_options localOpts = opts;
            const bool candidateTls = candidate.rfind("ssl://", 0) == 0;

            if (forceTls || candidateTls) {
                mqtt::ssl_options ssl;

                if (const char* ca = std::getenv("EASYNC_MQTT_CA_CERT")) {
                    if (std::strlen(ca) > 0)
                        ssl.set_trust_store(ca);
                }

                localOpts.set_ssl(ssl);
            }

            nextClient->connect(localOpts)->wait();
            nextClient->subscribe("easync/+/state", 1)->wait();
            nextClient->start_consuming();

            brokerUrl = candidate;
            client = std::move(nextClient);
            connected = true;
            return true;
        }
        catch (...) {
            connected = false;
        }
    }

    return false;
}

void MqttDriver::setEventCallback(
    DriverEventCallback cb,
    void* userData
) {
    eventCallback = cb;
    eventUserData = userData;
}

bool MqttDriver::connect(const std::string& uuid) {
    std::lock_guard<std::mutex> lock(mutex);

    if (!connected)
        return false;

    if (states.count(uuid))
        return true;

    states.emplace(uuid, CoreDeviceState{});
    return true;
}

bool MqttDriver::disconnect(const std::string& uuid) {
    std::lock_guard<std::mutex> lock(mutex);
    states.erase(uuid);
    return true;
}

bool MqttDriver::setPower(const std::string& uuid, bool value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!states.count(uuid))
        return false;

    std::stringstream ss;
    ss << "{ \"power\": " << (value ? 1 : 0) << " }";

    auto command = buildCommandFromTemplate(uuid, "power", value ? "1" : "0", ss.str());
    publishCommand(uuid, command.payload, command.topic);
    return true;
}

bool MqttDriver::setBrightness(const std::string& uuid, uint32_t value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!states.count(uuid))
        return false;

    std::stringstream ss;
    ss << "{ \"brightness\": " << value << " }";

    auto command = buildCommandFromTemplate(uuid, "brightness", std::to_string(value), ss.str());
    publishCommand(uuid, command.payload, command.topic);
    return true;
}

bool MqttDriver::setColor(const std::string& uuid, uint32_t rgb) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!states.count(uuid))
        return false;

    std::stringstream ss;
    ss << "{ \"color\": " << rgb << " }";

    auto command = buildCommandFromTemplate(uuid, "color", std::to_string(rgb), ss.str());
    publishCommand(uuid, command.payload, command.topic);
    return true;
}

bool MqttDriver::setTemperature(const std::string& uuid, float value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!states.count(uuid))
        return false;

    std::stringstream ss;
    ss << "{ \"temperature\": " << value << " }";

    auto command = buildCommandFromTemplate(uuid, "temperature", std::to_string(value), ss.str());
    publishCommand(uuid, command.payload, command.topic);
    return true;
}

bool MqttDriver::setTemperatureFridge(const std::string& uuid, float value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!states.count(uuid))
        return false;

    std::stringstream ss;
    ss << "{ \"temperature_fridge\": " << value << " }";

    auto command = buildCommandFromTemplate(uuid, "temperature_fridge", std::to_string(value), ss.str());
    publishCommand(uuid, command.payload, command.topic);
    return true;
}

bool MqttDriver::setTemperatureFreezer(const std::string& uuid, float value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!states.count(uuid))
        return false;

    std::stringstream ss;
    ss << "{ \"temperature_freezer\": " << value << " }";

    auto command = buildCommandFromTemplate(uuid, "temperature_freezer", std::to_string(value), ss.str());
    publishCommand(uuid, command.payload, command.topic);
    return true;
}

bool MqttDriver::setTime(const std::string& uuid, uint64_t value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!states.count(uuid))
        return false;

    std::stringstream ss;
    ss << "{ \"timestamp\": " << value << " }";

    auto command = buildCommandFromTemplate(uuid, "time", std::to_string(value), ss.str());
    publishCommand(uuid, command.payload, command.topic);
    return true;
}

bool MqttDriver::setColorTemperature(const std::string& uuid, uint32_t value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!states.count(uuid))
        return false;

    std::stringstream ss;
    ss << "{ \"colorTemperature\": " << value << " }";

    auto command = buildCommandFromTemplate(uuid, "colorTemperature", std::to_string(value), ss.str());
    publishCommand(uuid, command.payload, command.topic);
    return true;
}

bool MqttDriver::setLock(const std::string& uuid, bool value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!states.count(uuid))
        return false;

    std::stringstream ss;
    ss << "{ \"lock\": " << (value ? 1 : 0) << " }";

    auto command = buildCommandFromTemplate(uuid, "lock", value ? "1" : "0", ss.str());
    publishCommand(uuid, command.payload, command.topic);
    return true;
}

bool MqttDriver::setMode(const std::string& uuid, uint32_t value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!states.count(uuid))
        return false;

    std::stringstream ss;
    ss << "{ \"mode\": " << value << " }";

    auto command = buildCommandFromTemplate(uuid, "mode", std::to_string(value), ss.str());
    publishCommand(uuid, command.payload, command.topic);
    return true;
}

bool MqttDriver::setPosition(const std::string& uuid, float value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!states.count(uuid))
        return false;

    std::stringstream ss;
    ss << "{ \"position\": " << value << " }";

    auto command = buildCommandFromTemplate(uuid, "position", std::to_string(value), ss.str());
    publishCommand(uuid, command.payload, command.topic);
    return true;
}

bool MqttDriver::getState(const std::string& uuid, CoreDeviceState& outState) {
    std::lock_guard<std::mutex> lock(mutex);

    auto it = states.find(uuid);
    if (it == states.end())
        return false;

    outState = it->second;
    return true;
}

bool MqttDriver::isAvailable(const std::string& uuid) {
    std::lock_guard<std::mutex> lock(mutex);
    return connected && states.count(uuid) > 0;
}

void MqttDriver::publishCommand(
    const std::string& uuid,
    const std::string& json,
    const std::string& topicOverride
) {
    if (!connected || !client)
        return;

    std::string topic = topicOverride.empty()
        ? "easync/" + uuid + "/set"
        : topicOverride;
    auto msg = mqtt::make_message(topic, json);
    msg->set_qos(1);

    try {
        client->publish(msg);
    }
    catch (...) {
        std::cerr << "MQTT publish failed\n";
    }
}

void MqttDriver::connection_lost(const std::string& cause) {
    connected = false;
    std::cerr << "MQTT lost: " << cause << "\n";
}

void MqttDriver::message_arrived(mqtt::const_message_ptr msg) {
    std::string topic = msg->get_topic();
    std::string payload = msg->to_string();

    const std::string prefix = "easync/";

    if (topic.rfind(prefix, 0) != 0)
        return;

    std::string rest = topic.substr(prefix.size());
    auto pos = rest.find('/');

    if (pos == std::string::npos)
        return;

    std::string uuid = rest.substr(0, pos);
    std::string type = rest.substr(pos + 1);

    if (type != "state")
        return;

    parseState(uuid, payload);
}

void MqttDriver::delivery_complete(mqtt::delivery_token_ptr) {
}

void MqttDriver::parseState(
    const std::string& uuid,
    const std::string& payload
) {
    CoreDeviceState newState;
    CoreDeviceState oldState;

    {
        std::lock_guard<std::mutex> lock(mutex);

        auto it = states.find(uuid);
        if (it == states.end())
            return; // ignore unknown device

        oldState = it->second;
        newState = oldState;

        size_t p;

        if ((p = payload.find("power")) != std::string::npos)
            newState.power =
                std::stoi(payload.substr(payload.find(":", p) + 1)) != 0;

        if ((p = payload.find("brightness")) != std::string::npos)
            newState.brightness =
                std::stoi(payload.substr(payload.find(":", p) + 1));

        if ((p = payload.find("color")) != std::string::npos)
            newState.color =
                std::stoul(payload.substr(payload.find(":", p) + 1));

        if ((p = payload.find("temperature")) != std::string::npos)
            newState.temperature =
                std::stof(payload.substr(payload.find(":", p) + 1));

        if ((p = payload.find("temperature_fridge")) != std::string::npos)
            newState.temperatureFridge =
                std::stof(payload.substr(payload.find(":", p) + 1));

        if ((p = payload.find("temperature_freezer")) != std::string::npos)
            newState.temperatureFreezer =
                std::stof(payload.substr(payload.find(":", p) + 1));

        if ((p = payload.find("timestamp")) != std::string::npos)
            newState.timestamp =
                std::stoull(payload.substr(payload.find(":", p) + 1));

        if ((p = payload.find("colorTemperature")) != std::string::npos)
            newState.colorTemperature =
                std::stoul(payload.substr(payload.find(":", p) + 1));

        if ((p = payload.find("lock")) != std::string::npos)
            newState.lock =
                std::stoi(payload.substr(payload.find(":", p) + 1)) != 0;

        if ((p = payload.find("mode")) != std::string::npos)
            newState.mode =
                std::stoul(payload.substr(payload.find(":", p) + 1));

        if ((p = payload.find("position")) != std::string::npos)
            newState.position =
                std::stof(payload.substr(payload.find(":", p) + 1));

        bool changed =
            newState.power != oldState.power ||
            newState.brightness != oldState.brightness ||
            newState.color != oldState.color ||
            newState.temperature != oldState.temperature ||
            newState.temperatureFridge != oldState.temperatureFridge ||
            newState.temperatureFreezer != oldState.temperatureFreezer ||
            newState.timestamp != oldState.timestamp ||
            newState.colorTemperature != oldState.colorTemperature ||
            newState.lock != oldState.lock ||
            newState.mode != oldState.mode ||
            newState.position != oldState.position;

        if (!changed)
            return;

        it->second = newState;
    }

    notifyStateChange(uuid, newState);
}

void MqttDriver::notifyStateChange(
    const std::string& uuid,
    const CoreDeviceState& newState
) {
    if (eventCallback) {
        eventCallback(uuid, newState, eventUserData);
    }
}

}