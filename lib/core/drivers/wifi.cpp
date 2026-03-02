/**
 * @file wifi.cpp
 * @brief Implementation of the Wi-Fi driver with HTTP commands for EaSync devices.
 * @param uuid Device identifier used for IP and route resolution.
 * @return Methods return true when the HTTP request succeeds.
 * @author Erick Radmann
 */

#include "wifi.hpp"

#include <curl/curl.h>
#include <sstream>
#include <functional>
#include <vector>

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

    std::string ip = resolveIpFromUuid(uuid);

    deviceIps[uuid] = ip;
    states.emplace(uuid, CoreDeviceState{});

    return true;
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
        if (deviceIps.count(uuid))
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
    ss << "{ \"value\": " << (value ? 1 : 0) << " }";

    return httpPost("http://" + ip + "/power", ss.str());
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
    ss << "{ \"value\": " << value << " }";

    return httpPost("http://" + ip + "/brightness", ss.str());
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
    ss << "{ \"value\": " << rgb << " }";

    return httpPost("http://" + ip + "/color", ss.str());
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
    ss << "{ \"value\": " << value << " }";

    return httpPost("http://" + ip + "/temperature", ss.str());
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
    ss << "{ \"value\": " << value << " }";

    return httpPost("http://" + ip + "/temperatureFridge", ss.str());
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
    ss << "{ \"value\": " << value << " }";

    return httpPost("http://" + ip + "/temperatureFreezer", ss.str());
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
    ss << "{ \"value\": " << value << " }";

    return httpPost("http://" + ip + "/timestamp", ss.str());
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
    ss << "{ \"value\": " << value << " }";

    return httpPost("http://" + ip + "/colorTemperature", ss.str());
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
    ss << "{ \"value\": " << (value ? 1 : 0) << " }";

    return httpPost("http://" + ip + "/lock", ss.str());
}

bool WifiDriver::setMode(const std::string& uuid, uint32_t value) {

    std::string ip;

    {
        std::lock_guard<std::mutex> lock(mutex);
        if (!states.count(uuid))
            return false;
        ip = deviceIps[uuid];
    }

    std::stringstream ss;
    ss << "{ \"value\": " << value << " }";

    return httpPost("http://" + ip + "/mode", ss.str());
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
    ss << "{ \"value\": " << value << " }";

    return httpPost("http://" + ip + "/position", ss.str());
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

    std::string response;
    const bool ok = httpGet("http://" + ip + "/state", response);
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

    std::string response;
    return httpGet("http://" + ip + "/state", response);
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

        size_t p;

        if ((p = json.find("power")) != std::string::npos)
            newState.power =
                std::stoi(json.substr(json.find(":", p) + 1)) != 0;

        if ((p = json.find("brightness")) != std::string::npos)
            newState.brightness =
                std::stoi(json.substr(json.find(":", p) + 1));

        if ((p = json.find("color")) != std::string::npos)
            newState.color =
                std::stoul(json.substr(json.find(":", p) + 1));

        if ((p = json.find("temperature")) != std::string::npos)
            newState.temperature =
                std::stof(json.substr(json.find(":", p) + 1));

        if ((p = json.find("timestamp")) != std::string::npos)
            newState.timestamp =
                std::stoull(json.substr(json.find(":", p) + 1));

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

void WifiDriver::notifyStateChange(
    const std::string& uuid,
    const CoreDeviceState& newState
) {
    if (eventCallback) {
        eventCallback(uuid, newState, eventUserData);
    }
}

}