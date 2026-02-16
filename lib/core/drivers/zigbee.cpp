#include "zigbee.hpp"

#include <sstream>
#include <iostream>

namespace drivers {

ZigBeeDriver::ZigBeeDriver(
    const std::string& brokerUrl,
    const std::string& clientId
)
    : brokerUrl(brokerUrl),
      clientId(clientId)
{
}

ZigBeeDriver::~ZigBeeDriver() {
    if (client && connected) {
        client->disconnect()->wait();
    }
}

bool ZigBeeDriver::init() {

    client = std::make_unique<
        mqtt::async_client
    >(brokerUrl, clientId);

    client->set_callback(*this);

    mqtt::connect_options opts;

    try {

        client->connect(opts)->wait();

        client->subscribe(
            "zigbee2mqtt/+/state",
            1
        )->wait();

        connected = true;

        return true;

    } catch (...) {

        return false;
    }
}


bool ZigBeeDriver::connect(
    const std::string& uuid
) {

    std::lock_guard<std::mutex> lock(mutex);

    if (!connected)
        return false;

    std::string topic =
        "zigbee2mqtt/" + uuid;

    try {

        client->subscribe(topic, 1)->wait();

        return true;

    } catch (...) {

        return false;
    }
}


bool ZigBeeDriver::disconnect(
    const std::string& uuid
) {

    std::lock_guard<std::mutex> lock(mutex);

    std::string topic =
        "zigbee2mqtt/" + uuid;

    try {

        client->unsubscribe(topic)->wait();

        states.erase(uuid);

        return true;

    } catch (...) {

        return false;
    }
}


void ZigBeeDriver::publishCommand(
    const std::string& uuid,
    const std::string& json
) {

    if (!connected)
        return;

    std::string topic =
        "zigbee2mqtt/" + uuid + "/set";

    auto msg = mqtt::make_message(
        topic,
        json
    );

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

    publishCommand(uuid, ss.str());

    return true;
}


bool ZigBeeDriver::setBrightness(
    const std::string& uuid,
    int value
) {

    std::stringstream ss;

    ss << "{ \"brightness\": "
       << value
       << " }";

    publishCommand(uuid, ss.str());

    return true;
}


bool ZigBeeDriver::setColor(
    const std::string& uuid,
    uint32_t rgb
) {

    int r = (rgb >> 16) & 0xFF;
    int g = (rgb >> 8) & 0xFF;
    int b = rgb & 0xFF;

    std::stringstream ss;

    ss << "{ \"color\": { "
       << "\"r\": " << r << ", "
       << "\"g\": " << g << ", "
       << "\"b\": " << b
       << " } }";

    publishCommand(uuid, ss.str());

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

    publishCommand(uuid, ss.str());

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

    publishCommand(uuid, ss.str());

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

    return states.count(uuid);
}


/* MQTT callbacks */

void ZigBeeDriver::connection_lost(
    const std::string& cause
) {

    connected = false;

    std::cerr
        << "ZigBee MQTT lost: "
        << cause << "\n";
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

    std::string rest =
        topic.substr(prefix.size());

    std::string uuid = rest;

    parseState(uuid, payload);
}


void ZigBeeDriver::parseState(
    const std::string& uuid,
    const std::string& payload
) {

    std::lock_guard<std::mutex> lock(mutex);

    CoreDeviceState st{};

    size_t p;


    if ((p = payload.find("\"state\"")) != std::string::npos) {

        auto v =
            payload.substr(
                payload.find(":", p) + 1
            );

        st.power =
            v.find("ON") != std::string::npos;
    }


    if ((p = payload.find("brightness")) != std::string::npos) {

        st.brightness =
            std::stoi(
                payload.substr(
                    payload.find(":", p) + 1
                )
            );
    }


    if ((p = payload.find("\"r\"")) != std::string::npos) {

        int r = std::stoi(
            payload.substr(
                payload.find(":", p) + 1
            )
        );

        int g = std::stoi(
            payload.substr(
                payload.find("\"g\"") + 4
            )
        );

        int b = std::stoi(
            payload.substr(
                payload.find("\"b\"") + 4
            )
        );

        st.color =
            (r << 16) | (g << 8) | b;
    }


    if ((p = payload.find("temperature")) != std::string::npos) {

        st.temperature =
            std::stof(
                payload.substr(
                    payload.find(":", p) + 1
                )
            );
    }


    if ((p = payload.find("timestamp")) != std::string::npos) {

        st.timestamp =
            std::stoull(
                payload.substr(
                    payload.find(":", p) + 1
                )
            );
    }


    states[uuid] = st;
}

}
