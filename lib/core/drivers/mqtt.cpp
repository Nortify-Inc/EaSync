#include "mqtt.hpp"

#include <iostream>
#include <sstream>

namespace drivers {

MqttDriver::MqttDriver(
){

    client = std::make_unique<
        mqtt::async_client
    >(brokerUrl, clientId);

    client->set_callback(*this);
}

bool MqttDriver::init() {

    mqtt::connect_options opts;

    try {

        client->connect(opts)->wait();
        connected = true;

        client->subscribe("easync/+/state", 1)->wait();

        return true;

    } catch (...) {
        return false;
    }
}

bool MqttDriver::connect(
    const std::string& uuid
) {

    std::lock_guard<std::mutex> lock(mutex);

    if (!connected)
        return false;

    if (states.count(uuid))
        return true;

    CoreDeviceState st{};
    st.power = false;
    st.brightness = 0;
    st.color = 0;
    st.temperature = 0.0f;
    st.timestamp = 0;

    states[uuid] = st;

    return true;
}

bool MqttDriver::disconnect(
    const std::string& uuid
) {

    std::lock_guard<std::mutex> lock(mutex);

    states.erase(uuid);

    return true;
}

void MqttDriver::publishCommand(
    const std::string& uuid,
    const std::string& json
) {

    if (!connected)
        return;

    std::string topic =
        "easync/" + uuid + "/cmd";

    auto msg = mqtt::make_message(
        topic,
        json
    );

    msg->set_qos(1);

    client->publish(msg);
}

bool MqttDriver::setPower(
    const std::string& uuid,
    bool value
) {

    std::lock_guard<std::mutex> lock(mutex);

    if (!states.count(uuid))
        return false;

    std::stringstream ss;

    ss << "{ \"power\": "
       << (value ? 1 : 0)
       << " }";

    publishCommand(uuid, ss.str());

    states[uuid].power = value;

    return true;
}

bool MqttDriver::setBrightness(
    const std::string& uuid,
    int value
) {

    std::lock_guard<std::mutex> lock(mutex);

    if (!states.count(uuid))
        return false;

    std::stringstream ss;

    ss << "{ \"brightness\": "
       << value
       << " }";

    publishCommand(uuid, ss.str());

    states[uuid].brightness = value;

    return true;
}

bool MqttDriver::setColor(
    const std::string& uuid,
    uint32_t rgb
) {

    std::lock_guard<std::mutex> lock(mutex);

    if (!states.count(uuid))
        return false;

    std::stringstream ss;

    ss << "{ \"color\": "
       << rgb
       << " }";

    publishCommand(uuid, ss.str());

    states[uuid].color = rgb;

    return true;
}

bool MqttDriver::setTemperature(
    const std::string& uuid,
    float value
) {

    std::lock_guard<std::mutex> lock(mutex);

    if (!states.count(uuid))
        return false;

    std::stringstream ss;

    ss << "{ \"temperature\": "
       << value
       << " }";

    publishCommand(uuid, ss.str());

    states[uuid].temperature = value;

    return true;
}

bool MqttDriver::setTime(
    const std::string& uuid,
    uint64_t value
) {

    std::lock_guard<std::mutex> lock(mutex);

    if (!states.count(uuid))
        return false;

    std::stringstream ss;

    ss << "{ \"timestamp\": "
       << value
       << " }";

    publishCommand(uuid, ss.str());

    states[uuid].timestamp = value;

    return true;
}

bool MqttDriver::getState(
    const std::string& uuid,
    CoreDeviceState& outState
) {

    std::lock_guard<std::mutex> lock(mutex);

    if (!states.count(uuid))
        return false;

    outState = states[uuid];

    return true;
}

bool MqttDriver::isAvailable(const std::string& uuid){
    return states.count(uuid);
}

void MqttDriver::connection_lost(
    const std::string& cause
) {

    connected = false;

    std::cerr
        << "MQTT lost: "
        << cause << "\n";
}

void MqttDriver::message_arrived(
    mqtt::const_message_ptr msg
) {

    std::string topic = msg->get_topic();
    std::string payload = msg->to_string();

    const std::string prefix = "easync/";

    if (topic.rfind(prefix, 0) != 0)
        return;

    std::string rest =
        topic.substr(prefix.size());

    auto pos = rest.find('/');

    if (pos == std::string::npos)
        return;

    std::string uuid =
        rest.substr(0, pos);

    std::string type =
        rest.substr(pos + 1);

    if (type != "state")
        return;

    parseState(uuid, payload);
}

void MqttDriver::delivery_complete(
    mqtt::delivery_token_ptr
) {
}

void MqttDriver::parseState(
    const std::string& uuid,
    const std::string& payload
) {

    std::lock_guard<std::mutex> lock(mutex);

    auto& st = states[uuid];

    size_t p;

    if ((p = payload.find("power")) != std::string::npos)
        st.power =
            std::stoi(payload.substr(payload.find(":", p) + 1)) != 0;

    if ((p = payload.find("brightness")) != std::string::npos)
        st.brightness =
            std::stoi(payload.substr(payload.find(":", p) + 1));

    if ((p = payload.find("color")) != std::string::npos)
        st.color =
            std::stoul(payload.substr(payload.find(":", p) + 1));

    if ((p = payload.find("temperature")) != std::string::npos)
        st.temperature =
            std::stof(payload.substr(payload.find(":", p) + 1));
}

}