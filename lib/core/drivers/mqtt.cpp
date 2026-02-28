#include "mqtt.hpp"

#include <iostream>
#include <sstream>

namespace drivers {

MqttDriver::MqttDriver() {
    client = std::make_unique<mqtt::async_client>(brokerUrl, clientId);
    client->set_callback(*this);
}

bool MqttDriver::init() {
    mqtt::connect_options opts;

    try {
        client->connect(opts)->wait();
        connected = true;

        client->subscribe("easync/+/state", 1)->wait();
        client->start_consuming();

        return true;
    }
    catch (...) {
        connected = false;
        return false;
    }
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

    publishCommand(uuid, ss.str());
    return true;
}

bool MqttDriver::setBrightness(const std::string& uuid, uint32_t value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!states.count(uuid))
        return false;

    std::stringstream ss;
    ss << "{ \"brightness\": " << value << " }";

    publishCommand(uuid, ss.str());
    return true;
}

bool MqttDriver::setColor(const std::string& uuid, uint32_t rgb) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!states.count(uuid))
        return false;

    std::stringstream ss;
    ss << "{ \"color\": " << rgb << " }";

    publishCommand(uuid, ss.str());
    return true;
}

bool MqttDriver::setTemperature(const std::string& uuid, float value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!states.count(uuid))
        return false;

    std::stringstream ss;
    ss << "{ \"temperature\": " << value << " }";

    publishCommand(uuid, ss.str());
    return true;
}

bool MqttDriver::setTime(const std::string& uuid, uint64_t value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!states.count(uuid))
        return false;

    std::stringstream ss;
    ss << "{ \"timestamp\": " << value << " }";

    publishCommand(uuid, ss.str());
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
    return states.count(uuid) > 0;
}

void MqttDriver::publishCommand(
    const std::string& uuid,
    const std::string& json
) {
    if (!connected)
        return;

    std::string topic = "easync/" + uuid + "/set";
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

        if ((p = payload.find("timestamp")) != std::string::npos)
            newState.timestamp =
                std::stoull(payload.substr(payload.find(":", p) + 1));

        bool changed =
            newState.power != oldState.power ||
            newState.brightness != oldState.brightness ||
            newState.color != oldState.color ||
            newState.temperature != oldState.temperature ||
            newState.timestamp != oldState.timestamp;

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