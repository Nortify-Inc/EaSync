/**
 * @file zigbee.cpp
 * @brief Implementation of the ZigBee driver for zigbee2mqtt integration.
 * @param uuid Device identifier used in broker topics.
 * @return Methods return true when the command is published successfully.
 * @author Erick Radmann
 */

#include "zigbee.hpp"
#include "payload_service.hpp"

#include <sstream>

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

ZigBeeDriver::ZigBeeDriver(){
    brokerUrl = "tcp://localhost:1883";
    clientId = "core_zigbee";
}

ZigBeeDriver::~ZigBeeDriver() {
    if (client && connected) {
        client->disconnect()->wait();
    }
}

bool ZigBeeDriver::init() {

    client = std::make_unique<mqtt::async_client>(
        brokerUrl,
        clientId
    );

    client->set_callback(*this);

    mqtt::connect_options opts;

    try {
        client->connect(opts)->wait();
        client->subscribe("zigbee2mqtt/+/state", 1)->wait();
        connected = true;
        return true;
    }
    catch (...) {
        return false;
    }
}

void ZigBeeDriver::setEventCallback(
    DriverEventCallback cb,
    void* userData
) {
    eventCallback = cb;
    eventUserData = userData;
}

bool ZigBeeDriver::connect(const std::string& uuid) {

    std::lock_guard<std::mutex> lock(mutex);

    if (!connected)
        return false;

    if (states.count(uuid))
        return true;

    states.emplace(uuid, CoreDeviceState{});

    return true;
}

bool ZigBeeDriver::disconnect(const std::string& uuid) {

    std::lock_guard<std::mutex> lock(mutex);

    states.erase(uuid);

    return true;
}

void ZigBeeDriver::publishCommand(
    const std::string& uuid,
    const std::string& json,
    const std::string& topicOverride
) {
    if (!connected)
        return;

    std::string topic = topicOverride.empty()
        ? "zigbee2mqtt/" + uuid + "/set"
        : topicOverride;

    auto msg = mqtt::make_message(topic, json);
    msg->set_qos(1);

    client->publish(msg);
}

bool ZigBeeDriver::setPower(
    const std::string& uuid,
    bool value
) {
    std::stringstream ss;
    ss << "{ \"state\": \""
       << (value ? "ON" : "OFF")
       << "\" }";

    auto command = buildCommandFromTemplate(uuid, "power", value ? "1" : "0", ss.str());
    publishCommand(uuid, command.payload, command.topic);
    return true;
}

bool ZigBeeDriver::setBrightness(
    const std::string& uuid,
    uint32_t value
) {
    std::stringstream ss;
    ss << "{ \"brightness\": "
       << value
       << " }";

    auto command = buildCommandFromTemplate(uuid, "brightness", std::to_string(value), ss.str());
    publishCommand(uuid, command.payload, command.topic);
    return true;
}

bool ZigBeeDriver::setColor(
    const std::string& uuid,
    uint32_t rgb
) {
    uint32_t r = (rgb >> 16) & 0xFF;
    uint32_t g = (rgb >> 8) & 0xFF;
    uint32_t b = rgb & 0xFF;

    std::stringstream ss;
    ss << "{ \"color\": { "
       << "\"r\": " << r << ", "
       << "\"g\": " << g << ", "
       << "\"b\": " << b
       << " } }";

    auto command = buildCommandFromTemplate(uuid, "color", std::to_string(rgb), ss.str());
    publishCommand(uuid, command.payload, command.topic);
    return true;
}

bool ZigBeeDriver::setTemperature(
    const std::string& uuid,
    float value
) {
    std::stringstream ss;
    ss << "{ \"temperature\": "
       << value
       << " }";

    auto command = buildCommandFromTemplate(uuid, "temperature", std::to_string(value), ss.str());
    publishCommand(uuid, command.payload, command.topic);
    return true;
}

bool ZigBeeDriver::setTemperatureFridge(
    const std::string& uuid,
    float value
) {
    std::stringstream ss;
    ss << "{ \"temperatureFridge\": "
       << value
       << " }";

    auto command = buildCommandFromTemplate(uuid, "temperature_fridge", std::to_string(value), ss.str());
    publishCommand(uuid, command.payload, command.topic);
    return true;
}

bool ZigBeeDriver::setTemperatureFreezer(
    const std::string& uuid,
    float value
) {
    std::stringstream ss;
    ss << "{ \"temperatureFreezer\": "
       << value
       << " }";

    auto command = buildCommandFromTemplate(uuid, "temperature_freezer", std::to_string(value), ss.str());
    publishCommand(uuid, command.payload, command.topic);
    return true;
}

bool ZigBeeDriver::setTime(
    const std::string& uuid,
    uint64_t value
) {
    std::stringstream ss;
    ss << "{ \"timestamp\": "
       << value
       << " }";

    auto command = buildCommandFromTemplate(uuid, "time", std::to_string(value), ss.str());
    publishCommand(uuid, command.payload, command.topic);
    return true;
}

bool ZigBeeDriver::setColorTemperature(
    const std::string& uuid,
    uint32_t value
) {
    std::stringstream ss;
    ss << "{ \"colorTemperature\": "
       << value
       << " }";

    auto command = buildCommandFromTemplate(uuid, "colorTemperature", std::to_string(value), ss.str());
    publishCommand(uuid, command.payload, command.topic);
    return true;
}

bool ZigBeeDriver::setLock(
    const std::string& uuid,
    bool value
) {
    std::stringstream ss;
    ss << "{ \"lock\": "
       << (value ? 1 : 0)
       << " }";

    auto command = buildCommandFromTemplate(uuid, "lock", value ? "1" : "0", ss.str());
    publishCommand(uuid, command.payload, command.topic);
    return true;
}

bool ZigBeeDriver::setMode(
    const std::string& uuid,
    uint32_t value
) {
    std::stringstream ss;
    ss << "{ \"mode\": "
       << value
       << " }";

    auto command = buildCommandFromTemplate(uuid, "mode", std::to_string(value), ss.str());
    publishCommand(uuid, command.payload, command.topic);
    return true;
}

bool ZigBeeDriver::setPosition(
    const std::string& uuid,
    float value
) {
    std::stringstream ss;
    ss << "{ \"position\": "
       << value
       << " }";

    auto command = buildCommandFromTemplate(uuid, "position", std::to_string(value), ss.str());
    publishCommand(uuid, command.payload, command.topic);
    return true;
}

bool ZigBeeDriver::getState(
    const std::string& uuid,
    CoreDeviceState& outState
) {
    std::lock_guard<std::mutex> lock(mutex);

    if (!states.count(uuid))
        return false;

    outState = states[uuid];
    return true;
}

bool ZigBeeDriver::isAvailable(
    const std::string& uuid
) {
    std::lock_guard<std::mutex> lock(mutex);
    return states.count(uuid) > 0;
}

void ZigBeeDriver::connection_lost(
    const std::string& cause
) {
    connected = false;
}

void ZigBeeDriver::delivery_complete(
    mqtt::delivery_token_ptr
) {
}

void ZigBeeDriver::message_arrived(
    mqtt::const_message_ptr msg
) {

    std::string topic = msg->get_topic();
    std::string payload = msg->to_string();

    const std::string prefix = "zigbee2mqtt/";

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

void ZigBeeDriver::parseState(
    const std::string& uuid,
    const std::string& payload
) {

    CoreDeviceState newState;
    CoreDeviceState oldState;

    {
        std::lock_guard<std::mutex> lock(mutex);

        auto it = states.find(uuid);
        if (it == states.end())
            return;

        oldState = it->second;
        newState = oldState;

        size_t p;

        if ((p = payload.find("\"state\"")) != std::string::npos) {
            newState.power =
                payload.find("ON", p) != std::string::npos;
        }

        if ((p = payload.find("brightness")) != std::string::npos) {
            newState.brightness =
                std::stoi(payload.substr(payload.find(":", p) + 1));
        }

        if ((p = payload.find("\"r\"")) != std::string::npos) {

            uint32_t r = std::stoi(
                payload.substr(payload.find(":", p) + 1)
            );

            uint32_t g = std::stoi(
                payload.substr(payload.find("\"g\"") + 4)
            );

            uint32_t b = std::stoi(
                payload.substr(payload.find("\"b\"") + 4)
            );

            newState.color =
                (r << 16) | (g << 8) | b;
        }

        if ((p = payload.find("temperature")) != std::string::npos) {
            newState.temperature =
                std::stof(payload.substr(payload.find(":", p) + 1));
        }

        if ((p = payload.find("timestamp")) != std::string::npos) {
            newState.timestamp =
                std::stoull(payload.substr(payload.find(":", p) + 1));
        }

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

void ZigBeeDriver::notifyStateChange(
    const std::string& uuid,
    const CoreDeviceState& newState
) {
    if (eventCallback) {
        eventCallback(uuid, newState, eventUserData);
    }
}

}