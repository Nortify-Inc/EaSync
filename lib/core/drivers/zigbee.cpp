/**
 * @file zigbee.cpp
 * @brief Implementation of the ZigBee driver for zigbee2mqtt integration.
 * @param uuid Device identifier used in broker topics.
 * @return Methods return true when the command is published successfully.
 * @author Erick Radmann
 */

#include "zigbee.hpp"
#include "payloadUtility.hpp"

#include <sstream>
#include <vector>
#include <cstdlib>
#include <cstring>
#include <algorithm>
#include <cctype>

namespace {

static std::string trim(const std::string& v) {
    const auto begin = v.find_first_not_of(" \t\r\n");
    if (begin == std::string::npos)
        return "";

    const auto end = v.find_last_not_of(" \t\r\n");
    return v.substr(begin, end - begin + 1);
}

static std::string toLower(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return value;
}

static std::string normalizeBrokerUri(std::string candidate) {
    candidate = trim(candidate);
    if (candidate.empty())
        return "";

    if (candidate.rfind("tcp://", 0) == 0 ||
        candidate.rfind("ssl://", 0) == 0 ||
        candidate.rfind("ws://", 0) == 0 ||
        candidate.rfind("wss://", 0) == 0)
    {
        return candidate;
    }

    if (candidate.rfind("mqtt://", 0) == 0)
        return "tcp://" + candidate.substr(7);

    if (candidate.rfind("mqtts://", 0) == 0)
        return "ssl://" + candidate.substr(8);

    return "tcp://" + candidate;
}

static std::string inferPrefixFromBrandModel(const std::string& brand,
                                             const std::string& model,
                                             const std::string& fallback)
{
    const std::string signal = toLower(brand + " " + model);
    if (signal.find("zigbee") != std::string::npos)
        return "zigbee2mqtt";

    return fallback;
}

static std::pair<std::string, std::string> parseBrokerHint(const std::string& rawModel,
                                                            const std::string& fallbackPrefix)
{
    std::string model = trim(rawModel);
    if (model.empty())
        return {"", fallbackPrefix};

    std::string prefix = fallbackPrefix;

    const auto slash = model.find('/');
    if (slash != std::string::npos) {
        const std::string tail = trim(model.substr(slash + 1));
        if (!tail.empty())
            prefix = tail;
        model = trim(model.substr(0, slash));
    }

    return {normalizeBrokerUri(model), prefix};
}

static bool extractRawValue(const std::string& payload,
                            const std::vector<std::string>& keys,
                            std::string& outValue)
{
    for (const auto& key : keys) {
        const std::string quoted = "\"" + key + "\"";
        size_t keyPos = payload.find(quoted);
        if (keyPos == std::string::npos)
            continue;

        const size_t colon = payload.find(':', keyPos + quoted.size());
        if (colon == std::string::npos)
            continue;

        size_t start = payload.find_first_not_of(" \t\r\n", colon + 1);
        if (start == std::string::npos)
            continue;

        if (payload[start] == '"') {
            const size_t endQuote = payload.find('"', start + 1);
            if (endQuote == std::string::npos)
                continue;

            outValue = payload.substr(start + 1, endQuote - start - 1);
            return true;
        }

        const size_t tokenEnd = payload.find_first_of(",}\r\n", start);
        if (tokenEnd == std::string::npos)
            outValue = trim(payload.substr(start));
        else
            outValue = trim(payload.substr(start, tokenEnd - start));

        if (!outValue.empty())
            return true;
    }

    return false;
}

static bool parseBoolValue(const std::string& raw, bool& outValue) {
    const std::string lower = toLower(trim(raw));

    if (lower == "1" || lower == "true" || lower == "on" || lower == "lock") {
        outValue = true;
        return true;
    }

    if (lower == "0" || lower == "false" || lower == "off" || lower == "unlock") {
        outValue = false;
        return true;
    }

    return false;
}

} // namespace

namespace drivers {

static core::PayloadCommand buildCommandFromTemplate(
    const std::string& uuid,
    const std::string& capability,
    const std::string& valueJson,
    const std::string& fallbackJson
) {
    core::PayloadCommand fromTemplate = core::PayloadUtility::instance().createCommand(
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
    cachedConnectOptions = mqtt::connect_options();
    cachedConnectOptions.set_clean_session(true);
    cachedConnectOptions.set_automatic_reconnect(true);

    if (const char* prefix = std::getenv("EASYNC_ZIGBEE_TOPIC_PREFIX")) {
        const std::string candidate = trim(prefix);
        if (!candidate.empty())
            topicPrefix = candidate;
    }

    if (const char* user = std::getenv("EASYNC_ZIGBEE_USERNAME")) {
        const std::string username = trim(user);
        if (!username.empty())
            cachedConnectOptions.set_user_name(username);
    }

    if (const char* pass = std::getenv("EASYNC_ZIGBEE_PASSWORD")) {
        cachedConnectOptions.set_password(pass);
    }

    return ensureBrokerConnection();
}

void ZigBeeDriver::onDeviceRegistered(
    const std::string& uuid,
    const std::string& brand,
    const std::string& model
) {
    const auto [brokerHint, prefixHint] = parseBrokerHint(
        model,
        inferPrefixFromBrandModel(brand, model, topicPrefix)
    );

    std::lock_guard<std::mutex> lock(mutex);
    if (!brokerHint.empty())
        preferredBrokerByDevice[uuid] = brokerHint;
    if (!prefixHint.empty())
        preferredPrefixByDevice[uuid] = prefixHint;
}

void ZigBeeDriver::onDeviceRemoved(const std::string& uuid) {
    std::lock_guard<std::mutex> lock(mutex);
    preferredBrokerByDevice.erase(uuid);
    preferredPrefixByDevice.erase(uuid);
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

    auto prefixIt = preferredPrefixByDevice.find(uuid);
    if (prefixIt != preferredPrefixByDevice.end() && !prefixIt->second.empty())
        topicPrefix = prefixIt->second;

    std::string preferredBroker;
    auto brokerIt = preferredBrokerByDevice.find(uuid);
    if (brokerIt != preferredBrokerByDevice.end())
        preferredBroker = brokerIt->second;

    if (!ensureBrokerConnection(preferredBroker))
        return false;

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

bool ZigBeeDriver::ensureBrokerConnection(const std::string& preferredBroker) {
    std::vector<std::string> candidates;

    if (!preferredBroker.empty())
        candidates.push_back(preferredBroker);

    if (const char* env = std::getenv("EASYNC_ZIGBEE_BROKER")) {
        if (std::strlen(env) > 0)
            candidates.emplace_back(normalizeBrokerUri(env));
    }

    candidates.push_back(normalizeBrokerUri(brokerUrl));
    candidates.push_back("tcp://127.0.0.1:1883");
    candidates.push_back("tcp://mosquitto:1883");
    candidates.push_back("tcp://homeassistant.local:1883");
    candidates.push_back("tcp://192.168.1.1:1883");
    candidates.push_back("ssl://homeassistant.local:8883");
    candidates.push_back("ssl://192.168.1.1:8883");

    std::sort(candidates.begin(), candidates.end());
    candidates.erase(std::unique(candidates.begin(), candidates.end()), candidates.end());

    const bool forceTls =
        (std::getenv("EASYNC_ZIGBEE_TLS") != nullptr &&
         std::string(std::getenv("EASYNC_ZIGBEE_TLS")) == "1");

    for (const auto& candidate : candidates) {
        if (connected && client && candidate == brokerUrl)
            return true;

        try {
            auto nextClient = std::make_unique<mqtt::async_client>(candidate, clientId);
            nextClient->set_callback(*this);

            mqtt::connect_options localOpts = cachedConnectOptions;
            const bool candidateTls = candidate.rfind("ssl://", 0) == 0;

            if (forceTls || candidateTls) {
                mqtt::ssl_options ssl;

                if (const char* ca = std::getenv("EASYNC_ZIGBEE_CA_CERT")) {
                    if (std::strlen(ca) > 0)
                        ssl.set_trust_store(ca);
                }

                localOpts.set_ssl(ssl);
            }

            nextClient->connect(localOpts)->wait();
            nextClient->subscribe(topicPrefix + "/+/state", 1)->wait();
            nextClient->subscribe(topicPrefix + "/+", 1)->wait();

            if (client && connected) {
                try {
                    client->disconnect()->wait();
                } catch (...) {
                }
            }

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

bool ZigBeeDriver::publishCommand(
    const std::string& uuid,
    const std::string& json,
    const std::string& topicOverride
) {
    if (!connected || !client)
        return false;

    std::string topic = topicOverride.empty()
        ? topicPrefix + "/" + uuid + "/set"
        : topicOverride;

    auto msg = mqtt::make_message(topic, json);
    msg->set_qos(1);

    try {
        client->publish(msg);
        return true;
    } catch (...) {
        return false;
    }
}

bool ZigBeeDriver::setPower(
    const std::string& uuid,
    bool value
) {
    if (!isAvailable(uuid))
        return false;

    std::stringstream ss;
    ss << "{ \"state\": \""
       << (value ? "ON" : "OFF")
       << "\" }";

    auto command = buildCommandFromTemplate(uuid, "power", value ? "true" : "false", ss.str());
    return publishCommand(uuid, command.payload, command.topic);
}

bool ZigBeeDriver::setBrightness(
    const std::string& uuid,
    uint32_t value
) {
    if (!isAvailable(uuid))
        return false;

    std::stringstream ss;
    ss << "{ \"brightness\": "
       << value
       << " }";

    auto command = buildCommandFromTemplate(uuid, "brightness", std::to_string(value), ss.str());
    return publishCommand(uuid, command.payload, command.topic);
}

bool ZigBeeDriver::setColor(
    const std::string& uuid,
    uint32_t rgb
) {
    if (!isAvailable(uuid))
        return false;

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
    return publishCommand(uuid, command.payload, command.topic);
}

bool ZigBeeDriver::setTemperature(
    const std::string& uuid,
    float value
) {
    if (!isAvailable(uuid))
        return false;

    std::stringstream ss;
    ss << "{ \"temperature\": "
       << value
       << " }";

    auto command = buildCommandFromTemplate(uuid, "temperature", std::to_string(value), ss.str());
    return publishCommand(uuid, command.payload, command.topic);
}

bool ZigBeeDriver::setTemperatureFridge(
    const std::string& uuid,
    float value
) {
    if (!isAvailable(uuid))
        return false;

    std::stringstream ss;
    ss << "{ \"temperature_fridge\": "
       << value
       << " }";

    auto command = buildCommandFromTemplate(uuid, "temperature_fridge", std::to_string(value), ss.str());
    return publishCommand(uuid, command.payload, command.topic);
}

bool ZigBeeDriver::setTemperatureFreezer(
    const std::string& uuid,
    float value
) {
    if (!isAvailable(uuid))
        return false;

    std::stringstream ss;
    ss << "{ \"temperature_freezer\": "
       << value
       << " }";

    auto command = buildCommandFromTemplate(uuid, "temperature_freezer", std::to_string(value), ss.str());
    return publishCommand(uuid, command.payload, command.topic);
}

bool ZigBeeDriver::setTime(
    const std::string& uuid,
    uint64_t value
) {
    if (!isAvailable(uuid))
        return false;

    std::stringstream ss;
    ss << "{ \"timestamp\": "
       << value
       << " }";

    auto command = buildCommandFromTemplate(uuid, "time", std::to_string(value), ss.str());
    return publishCommand(uuid, command.payload, command.topic);
}

bool ZigBeeDriver::setColorTemperature(
    const std::string& uuid,
    uint32_t value
) {
    if (!isAvailable(uuid))
        return false;

    std::stringstream ss;
    ss << "{ \"colorTemperature\": "
       << value
       << " }";

    auto command = buildCommandFromTemplate(uuid, "colorTemperature", std::to_string(value), ss.str());
    return publishCommand(uuid, command.payload, command.topic);
}

bool ZigBeeDriver::setLock(
    const std::string& uuid,
    bool value
) {
    if (!isAvailable(uuid))
        return false;

    std::stringstream ss;
    ss << "{ \"lock\": " << (value ? "true" : "false") << " }";

    auto command = buildCommandFromTemplate(uuid, "lock", value ? "true" : "false", ss.str());
    return publishCommand(uuid, command.payload, command.topic);
}

bool ZigBeeDriver::setMode(
    const std::string& uuid,
    uint32_t value
) {
    if (!isAvailable(uuid))
        return false;

    const auto modeOptions = core::PayloadUtility::instance().modeOptionsForDevice(uuid);
    const bool hasLabel = value < modeOptions.size();

    const std::string modeValueJson = hasLabel
        ? ("\"" + modeOptions[value] + "\"")
        : std::to_string(value);

    std::stringstream ss;
    if (hasLabel)
        ss << "{ \"mode\": \"" << modeOptions[value] << "\" }";
    else
        ss << "{ \"mode\": " << value << " }";

    auto command = buildCommandFromTemplate(uuid, "mode", modeValueJson, ss.str());
    return publishCommand(uuid, command.payload, command.topic);
}

bool ZigBeeDriver::setPosition(
    const std::string& uuid,
    float value
) {
    if (!isAvailable(uuid))
        return false;

    std::stringstream ss;
    ss << "{ \"position\": "
       << value
       << " }";

    auto command = buildCommandFromTemplate(uuid, "position", std::to_string(value), ss.str());
    return publishCommand(uuid, command.payload, command.topic);
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
    return connected && states.count(uuid) > 0;
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

    const std::string prefix = topicPrefix + "/";

    if (topic.rfind(prefix, 0) != 0)
        return;

    std::string rest = topic.substr(prefix.size());

    auto pos = rest.find('/');

    std::string uuid;
    std::string type;
    if (pos == std::string::npos) {
        uuid = rest;
        type = "";
    } else {
        uuid = rest.substr(0, pos);
        type = rest.substr(pos + 1);
    }

    if (type != "state" && !type.empty())
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

        std::string raw;

        if (extractRawValue(payload, {"state", "power"}, raw)) {
            bool parsed = false;
            if (parseBoolValue(raw, parsed))
                newState.power = parsed;
        }

        if (extractRawValue(payload, {"brightness"}, raw)) {
            try { newState.brightness = static_cast<uint32_t>(std::stoul(raw)); } catch (...) {}
        }

        std::string rRaw;
        std::string gRaw;
        std::string bRaw;
        if (extractRawValue(payload, {"r"}, rRaw) &&
            extractRawValue(payload, {"g"}, gRaw) &&
            extractRawValue(payload, {"b"}, bRaw))
        {
            try {
                const uint32_t r = static_cast<uint32_t>(std::stoul(rRaw));
                const uint32_t g = static_cast<uint32_t>(std::stoul(gRaw));
                const uint32_t b = static_cast<uint32_t>(std::stoul(bRaw));
                newState.color = (r << 16) | (g << 8) | b;
            } catch (...) {}
        }

        if (extractRawValue(payload, {"temperature"}, raw)) {
            try { newState.temperature = std::stof(raw); } catch (...) {}
        }

        if (extractRawValue(payload, {"temperature_fridge", "temperatureFridge"}, raw)) {
            try { newState.temperatureFridge = std::stof(raw); } catch (...) {}
        }

        if (extractRawValue(payload, {"temperature_freezer", "temperatureFreezer"}, raw)) {
            try { newState.temperatureFreezer = std::stof(raw); } catch (...) {}
        }

        if (extractRawValue(payload, {"timestamp", "time"}, raw)) {
            try { newState.timestamp = static_cast<uint64_t>(std::stoull(raw)); } catch (...) {}
        }

        if (extractRawValue(payload, {"colorTemperature", "color_temperature"}, raw)) {
            try { newState.colorTemperature = static_cast<uint32_t>(std::stoul(raw)); } catch (...) {}
        }

        if (extractRawValue(payload, {"lock"}, raw)) {
            bool parsed = false;
            if (parseBoolValue(raw, parsed))
                newState.lock = parsed;
        }

        if (extractRawValue(payload, {"mode"}, raw)) {
            const auto options = core::PayloadUtility::instance().modeOptionsForDevice(uuid);
            const std::string lowered = toLower(trim(raw));

            bool parsedNumeric = false;
            try {
                newState.mode = static_cast<uint32_t>(std::stoul(lowered));
                parsedNumeric = true;
            } catch (...) {
                parsedNumeric = false;
            }

            if (!parsedNumeric) {
                for (size_t i = 0; i < options.size(); ++i) {
                    if (toLower(options[i]) == lowered) {
                        newState.mode = static_cast<uint32_t>(i);
                        break;
                    }
                }
            }
        }

        if (extractRawValue(payload, {"position"}, raw))
            newState.position = std::stof(raw);

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

void ZigBeeDriver::notifyStateChange(
    const std::string& uuid,
    const CoreDeviceState& newState
) {
    if (eventCallback) {
        eventCallback(uuid, newState, eventUserData);
    }
}

}