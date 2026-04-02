/**
 * @file wifi.cpp
 * @brief Implementation of the Wi-Fi driver with HTTP commands for EaSync devices.
 * @param uuid Device identifier used for IP and route resolution.
 * @return Methods return true when the HTTP request succeeds.
 * @author Erick Radmann
 */

#include "wifi.hpp"
#include "payload_utility.hpp"

#include <curl/curl.h>
#include <sstream>
#include <functional>
#include <vector>
#include <algorithm>
#include <cctype>
#include <cstdlib>

namespace {

static std::string trim(const std::string& v) {
    const auto begin = v.find_first_not_of(" \t\r\n");
    if (begin == std::string::npos)
        return "";

    const auto end = v.find_last_not_of(" \t\r\n");
    return v.substr(begin, end - begin + 1);
}

static std::string normalizeEndpoint(std::string raw) {
    raw = trim(raw);
    if (raw.empty())
        return "";

    const std::string http = "http://";
    const std::string https = "https://";
    if (raw.rfind(http, 0) == 0)
        raw = raw.substr(http.size());
    else if (raw.rfind(https, 0) == 0)
        raw = raw.substr(https.size());

    auto slash = raw.find('/');
    if (slash != std::string::npos)
        raw = raw.substr(0, slash);

    return trim(raw);
}

static std::string toLower(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return value;
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

static std::string endpointToBaseUrl(const std::string& endpoint) {
    const std::string trimmed = trim(endpoint);
    if (trimmed.empty())
        return "";

    if (trimmed.rfind("http://", 0) == 0 || trimmed.rfind("https://", 0) == 0)
        return trimmed;

    return "http://" + trimmed;
}

static std::string composeHttpUrl(const std::string& baseUrl, std::string routeOrTopic) {
    if (routeOrTopic.empty())
        return "";

    routeOrTopic = trim(routeOrTopic);
    if (routeOrTopic.empty())
        return "";

    if (routeOrTopic.rfind("http://", 0) == 0 || routeOrTopic.rfind("https://", 0) == 0)
        return routeOrTopic;

    if (routeOrTopic.front() != '/')
        routeOrTopic = "/" + routeOrTopic;

    if (!baseUrl.empty() && baseUrl.back() == '/')
        return baseUrl.substr(0, baseUrl.size() - 1) + routeOrTopic;

    return baseUrl + routeOrTopic;
}

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

}

namespace drivers {

static size_t writeCallback(
    void* contents,
    size_t size,
    size_t nmemb,
    void* userp
) {
    size_t total = size * nmemb;
    std::string* str = static_cast<std::string*>(userp);
    str->append((char*)contents, total);
    return total;
}

WifiDriver::WifiDriver() {}

bool WifiDriver::init() {
    return curl_global_init(CURL_GLOBAL_ALL) == 0;
}

void WifiDriver::setEventCallback(
    DriverEventCallback cb,
    void* userData
) {
    eventCallback = cb;
    eventUserData = userData;
}

std::string WifiDriver::resolveIpFromUuid(const std::string& uuid) {
    std::hash<std::string> hasher;
    size_t h = hasher(uuid);

    uint32_t lastOctet = 10 + (h % 200);
    return "192.168.1." + std::to_string(lastOctet);
}

bool WifiDriver::connect(const std::string& uuid) {

    std::lock_guard<std::mutex> lock(mutex);

    if (states.count(uuid))
        return true;

    std::string ip;

    if (deviceIps.count(uuid) && !deviceIps[uuid].empty()) {
        ip = deviceIps[uuid];
    } else if (const char* env = std::getenv("EASYNC_WIFI_DEFAULT_ENDPOINT")) {
        ip = normalizeEndpoint(env);
    }

    if (ip.empty())
        ip = resolveIpFromUuid(uuid);

    deviceIps[uuid] = ip;
    states.emplace(uuid, CoreDeviceState{});

    return true;
}

void WifiDriver::onDeviceRegistered(
    const std::string& uuid,
    const std::string& brand,
    const std::string& model
) {
    (void)brand;

    const std::string endpoint = normalizeEndpoint(model);
    if (endpoint.empty())
        return;

    std::lock_guard<std::mutex> lock(mutex);
    deviceIps[uuid] = endpoint;
}

void WifiDriver::onDeviceRemoved(const std::string& uuid) {
    std::lock_guard<std::mutex> lock(mutex);
    deviceIps.erase(uuid);
    states.erase(uuid);
}

bool WifiDriver::disconnect(const std::string& uuid) {

    std::lock_guard<std::mutex> lock(mutex);

    states.erase(uuid);
    deviceIps.erase(uuid);

    return true;
}

bool WifiDriver::provisionWifi(
    const std::string& uuid,
    const std::string& ssid,
    const std::string& password
) {
    if (ssid.empty() || password.empty())
        return false;

    std::vector<std::string> ips;

    {
        std::lock_guard<std::mutex> lock(mutex);
        if (deviceIps.count(uuid) && !deviceIps[uuid].empty())
            ips.push_back(deviceIps[uuid]);
    }

    // Common SoftAP/default provisioning gateway addresses.
    ips.push_back("192.168.4.1");
    ips.push_back("192.168.0.1");
    ips.push_back("192.168.1.1");

    std::stringstream ss;
    ss << "{ \"ssid\": \"" << ssid << "\", \"password\": \"" << password << "\" }";

    for (const auto& ip : ips) {
        if (httpPost("http://" + ip + "/provision", ss.str()))
            return true;

        if (httpPost("http://" + ip + "/wifi/provision", ss.str()))
            return true;
    }

    return false;
}

bool WifiDriver::setPower(const std::string& uuid, bool value) {

    std::string ip;

    {
        std::lock_guard<std::mutex> lock(mutex);
        if (!states.count(uuid))
            return false;
        ip = deviceIps[uuid];
    }

    std::stringstream ss;
    ss << "{ \"power\": " << (value ? "true" : "false") << " }";

    return postCapabilityCommand(
        uuid,
        ip,
        "power",
        value ? "true" : "false",
        ss.str(),
        {"/power", "/set/power", "/device/" + uuid + "/set"}
    );
}

bool WifiDriver::setBrightness(const std::string& uuid, uint32_t value) {

    std::string ip;

    {
        std::lock_guard<std::mutex> lock(mutex);
        if (!states.count(uuid))
            return false;
        ip = deviceIps[uuid];
    }

    std::stringstream ss;
    ss << "{ \"brightness\": " << value << " }";

    return postCapabilityCommand(
        uuid,
        ip,
        "brightness",
        std::to_string(value),
        ss.str(),
        {"/brightness", "/set/brightness", "/device/" + uuid + "/set"}
    );
}

bool WifiDriver::setColor(const std::string& uuid, uint32_t rgb) {

    std::string ip;

    {
        std::lock_guard<std::mutex> lock(mutex);
        if (!states.count(uuid))
            return false;
        ip = deviceIps[uuid];
    }

    std::stringstream ss;
    ss << "{ \"color\": " << rgb << " }";

    return postCapabilityCommand(
        uuid,
        ip,
        "color",
        std::to_string(rgb),
        ss.str(),
        {"/color", "/set/color", "/device/" + uuid + "/set"}
    );
}

bool WifiDriver::setTemperature(const std::string& uuid, float value) {

    std::string ip;

    {
        std::lock_guard<std::mutex> lock(mutex);
        if (!states.count(uuid))
            return false;
        ip = deviceIps[uuid];
    }

    std::stringstream ss;
    ss << "{ \"temperature\": " << value << " }";

    return postCapabilityCommand(
        uuid,
        ip,
        "temperature",
        std::to_string(value),
        ss.str(),
        {"/temperature", "/set/temperature", "/device/" + uuid + "/set"}
    );
}

bool WifiDriver::setTemperatureFridge(const std::string& uuid, float value) {

    std::string ip;

    {
        std::lock_guard<std::mutex> lock(mutex);
        if (!states.count(uuid))
            return false;
        ip = deviceIps[uuid];
    }

    std::stringstream ss;
    ss << "{ \"temperature_fridge\": " << value << " }";

    return postCapabilityCommand(
        uuid,
        ip,
        "temperature_fridge",
        std::to_string(value),
        ss.str(),
        {
            "/temperature_fridge",
            "/temperatureFridge",
            "/set/temperature_fridge",
            "/device/" + uuid + "/set"
        }
    );
}

bool WifiDriver::setTemperatureFreezer(const std::string& uuid, float value) {

    std::string ip;

    {
        std::lock_guard<std::mutex> lock(mutex);
        if (!states.count(uuid))
            return false;
        ip = deviceIps[uuid];
    }

    std::stringstream ss;
    ss << "{ \"temperature_freezer\": " << value << " }";

    return postCapabilityCommand(
        uuid,
        ip,
        "temperature_freezer",
        std::to_string(value),
        ss.str(),
        {
            "/temperature_freezer",
            "/temperatureFreezer",
            "/set/temperature_freezer",
            "/device/" + uuid + "/set"
        }
    );
}

bool WifiDriver::setTime(const std::string& uuid, uint64_t value) {

    std::string ip;

    {
        std::lock_guard<std::mutex> lock(mutex);
        if (!states.count(uuid))
            return false;
        ip = deviceIps[uuid];
    }

    std::stringstream ss;
    ss << "{ \"timestamp\": " << value << " }";

    return postCapabilityCommand(
        uuid,
        ip,
        "time",
        std::to_string(value),
        ss.str(),
        {"/timestamp", "/time", "/set/time", "/device/" + uuid + "/set"}
    );
}

bool WifiDriver::setColorTemperature(const std::string& uuid, uint32_t value) {

    std::string ip;

    {
        std::lock_guard<std::mutex> lock(mutex);
        if (!states.count(uuid))
            return false;
        ip = deviceIps[uuid];
    }

    std::stringstream ss;
    ss << "{ \"colorTemperature\": " << value << " }";

    return postCapabilityCommand(
        uuid,
        ip,
        "colorTemperature",
        std::to_string(value),
        ss.str(),
        {
            "/colorTemperature",
            "/color_temperature",
            "/set/colorTemperature",
            "/device/" + uuid + "/set"
        }
    );
}

bool WifiDriver::setLock(const std::string& uuid, bool value) {

    std::string ip;

    {
        std::lock_guard<std::mutex> lock(mutex);
        if (!states.count(uuid))
            return false;
        ip = deviceIps[uuid];
    }

    std::stringstream ss;
    ss << "{ \"lock\": " << (value ? "true" : "false") << " }";

    return postCapabilityCommand(
        uuid,
        ip,
        "lock",
        value ? "true" : "false",
        ss.str(),
        {"/lock", "/set/lock", "/device/" + uuid + "/set"}
    );
}

bool WifiDriver::setMode(const std::string& uuid, uint32_t value) {

    std::string ip;

    {
        std::lock_guard<std::mutex> lock(mutex);
        if (!states.count(uuid))
            return false;
        ip = deviceIps[uuid];
    }

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

    return postCapabilityCommand(
        uuid,
        ip,
        "mode",
        modeValueJson,
        ss.str(),
        {"/mode", "/set/mode", "/device/" + uuid + "/set"}
    );
}

bool WifiDriver::setPosition(const std::string& uuid, float value) {

    std::string ip;

    {
        std::lock_guard<std::mutex> lock(mutex);
        if (!states.count(uuid))
            return false;
        ip = deviceIps[uuid];
    }

    std::stringstream ss;
    ss << "{ \"position\": " << value << " }";

    return postCapabilityCommand(
        uuid,
        ip,
        "position",
        std::to_string(value),
        ss.str(),
        {"/position", "/set/position", "/device/" + uuid + "/set"}
    );
}

bool WifiDriver::getState(
    const std::string& uuid,
    CoreDeviceState& outState
) {

    std::string ip;

    {
        std::lock_guard<std::mutex> lock(mutex);
        if (!states.count(uuid))
            return false;
        ip = deviceIps[uuid];
    }

    const std::string baseUrl = endpointToBaseUrl(ip);

    std::string response;
    bool ok = false;
    const std::vector<std::string> statePaths = {
        "/state",
        "/api/state",
        "/status",
        "/device/" + uuid + "/state"
    };

    for (const auto& route : statePaths) {
        response.clear();
        if (httpGet(composeHttpUrl(baseUrl, route), response)) {
            ok = true;
            break;
        }
    }

    if (ok)
        parseState(uuid, response);

    {
        std::lock_guard<std::mutex> lock(mutex);
        outState = states[uuid];
    }

    return ok;
}

bool WifiDriver::isAvailable(const std::string& uuid) {
    std::string ip;

    {
        std::lock_guard<std::mutex> lock(mutex);
        if (!states.count(uuid))
            return false;
        ip = deviceIps[uuid];
    }

    const std::string baseUrl = endpointToBaseUrl(ip);

    std::string response;
    return httpGet(composeHttpUrl(baseUrl, "/state"), response) ||
           httpGet(composeHttpUrl(baseUrl, "/api/state"), response) ||
           httpGet(composeHttpUrl(baseUrl, "/health"), response) ||
           httpGet(composeHttpUrl(baseUrl, "/"), response);
}

bool WifiDriver::postCapabilityCommand(
    const std::string& uuid,
    const std::string& endpoint,
    const std::string& capability,
    const std::string& valueJson,
    const std::string& fallbackJson,
    const std::vector<std::string>& fallbackPaths
) {
    const std::string baseUrl = endpointToBaseUrl(endpoint);
    if (baseUrl.empty())
        return false;

    auto command = buildCommandFromTemplate(uuid, capability, valueJson, fallbackJson);

    std::string payload = command.payload.empty() ? fallbackJson : command.payload;

    if (!command.topic.empty()) {
        const std::string url = composeHttpUrl(baseUrl, command.topic);
        if (!url.empty() && httpPost(url, payload))
            return true;
    }

    for (const auto& route : fallbackPaths) {
        const std::string url = composeHttpUrl(baseUrl, route);
        if (!url.empty() && httpPost(url, payload))
            return true;
    }

    return false;
}

bool WifiDriver::httpPost(
    const std::string& url,
    const std::string& body
) {
    CURL* curl = curl_easy_init();
    if (!curl)
        return false;

    struct curl_slist* headers = nullptr;
    headers = curl_slist_append(headers, "Content-Type: application/json");

    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 3L);

    CURLcode res = curl_easy_perform(curl);

    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);

    return res == CURLE_OK;
}

bool WifiDriver::httpGet(
    const std::string& url,
    std::string& out
) {
    CURL* curl = curl_easy_init();
    if (!curl)
        return false;

    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, writeCallback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &out);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 3L);

    CURLcode res = curl_easy_perform(curl);

    curl_easy_cleanup(curl);

    return res == CURLE_OK;
}

void WifiDriver::parseState(
    const std::string& uuid,
    const std::string& json
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

        if (extractRawValue(json, {"power", "state"}, raw)) {
            bool parsed = false;
            if (parseBoolValue(raw, parsed))
                newState.power = parsed;
        }

        if (extractRawValue(json, {"brightness"}, raw))
            newState.brightness = static_cast<uint32_t>(std::stoul(raw));

        if (extractRawValue(json, {"color"}, raw))
            newState.color = static_cast<uint32_t>(std::stoul(raw));

        if (extractRawValue(json, {"temperature"}, raw))
            newState.temperature = std::stof(raw);

        if (extractRawValue(json, {"temperature_fridge", "temperatureFridge"}, raw))
            newState.temperatureFridge = std::stof(raw);

        if (extractRawValue(json, {"temperature_freezer", "temperatureFreezer"}, raw))
            newState.temperatureFreezer = std::stof(raw);

        if (extractRawValue(json, {"timestamp", "time"}, raw))
            newState.timestamp = static_cast<uint64_t>(std::stoull(raw));

        if (extractRawValue(json, {"colorTemperature", "color_temperature"}, raw))
            newState.colorTemperature = static_cast<uint32_t>(std::stoul(raw));

        if (extractRawValue(json, {"lock"}, raw)) {
            bool parsed = false;
            if (parseBoolValue(raw, parsed))
                newState.lock = parsed;
        }

        if (extractRawValue(json, {"mode"}, raw)) {
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

        if (extractRawValue(json, {"position"}, raw))
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

void WifiDriver::notifyStateChange(
    const std::string& uuid,
    const CoreDeviceState& newState
) {
    if (eventCallback) {
        eventCallback(uuid, newState, eventUserData);
    }
}

}