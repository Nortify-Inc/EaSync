#include "wifi.hpp"

#include <curl/curl.h>
#include <sstream>
#include <iostream>

namespace drivers {

static size_t writeCallback(
    void* contents,
    size_t size,
    size_t nmemb,
    void* userp
) {

    size_t total = size * nmemb;

    std::string* str =
        static_cast<std::string*>(userp);

    str->append(
        (char*)contents,
        total
    );

    return total;
}

WifiDriver::WifiDriver() {
}

bool WifiDriver::init() {

    if (curl_global_init(CURL_GLOBAL_ALL) != 0) {
        return false;
    }

    return true;
}

bool WifiDriver::connect(
    const std::string& uuid
) {

    std::lock_guard<std::mutex> lock(mutex);

    if (states.count(uuid))
        return true;

    std::string ip = "192.168.1.100";

    deviceIps[uuid] = ip;

    CoreDeviceState st{};

    st.power = false;
    st.brightness = -1;
    st.color = 0;
    st.temperature = -1;
    st.timestamp = 0;

    states[uuid] = st;

    return true;
}

bool WifiDriver::disconnect(
    const std::string& uuid
) {

    std::lock_guard<std::mutex> lock(mutex);

    states.erase(uuid);
    deviceIps.erase(uuid);

    return true;
}

bool WifiDriver::httpPost(
    const std::string& url,
    const std::string& body
) {

    CURL* curl = curl_easy_init();

    if (!curl)
        return false;

    struct curl_slist* headers = nullptr;

    headers = curl_slist_append(
        headers,
        "Content-Type: application/json"
    );

    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 3L);

    CURLcode res =
        curl_easy_perform(curl);

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

    CURLcode res =
        curl_easy_perform(curl);

    curl_easy_cleanup(curl);

    return res == CURLE_OK;
}

bool WifiDriver::setPower(
    const std::string& uuid,
    bool value
) {

    std::lock_guard<std::mutex> lock(mutex);

    if (!states.count(uuid))
        return false;

    std::string url =
        "http://" + deviceIps[uuid] + "/power";

    std::stringstream ss;

    ss << "{ \"value\": "
       << (value ? 1 : 0)
       << " }";

    if (!httpPost(url, ss.str()))
        return false;

    states[uuid].power = value;

    return true;
}

bool WifiDriver::setBrightness(
    const std::string& uuid,
    int value
) {

    std::lock_guard<std::mutex> lock(mutex);

    if (!states.count(uuid))
        return false;

    std::string url =
        "http://" + deviceIps[uuid] + "/brightness";

    std::stringstream ss;

    ss << "{ \"value\": " << value << " }";

    if (!httpPost(url, ss.str()))
        return false;

    states[uuid].brightness = value;

    return true;
}

bool WifiDriver::setColor(
    const std::string& uuid,
    uint32_t rgb
) {

    std::lock_guard<std::mutex> lock(mutex);

    if (!states.count(uuid))
        return false;

    std::string url =
        "http://" + deviceIps[uuid] + "/color";

    std::stringstream ss;

    ss << "{ \"value\": " << rgb << " }";

    if (!httpPost(url, ss.str()))
        return false;

    states[uuid].color = rgb;

    return true;
}

bool WifiDriver::setTemperature(
    const std::string& uuid,
    float value
) {

    std::lock_guard<std::mutex> lock(mutex);

    if (!states.count(uuid))
        return false;

    std::string url =
        "http://" + deviceIps[uuid] + "/temperature";

    std::stringstream ss;

    ss << "{ \"value\": " << value << " }";

    if (!httpPost(url, ss.str()))
        return false;

    states[uuid].temperature = value;

    return true;
}

bool WifiDriver::getState(
    const std::string& uuid,
    CoreDeviceState& outState
) {

    std::lock_guard<std::mutex> lock(mutex);

    if (!states.count(uuid))
        return false;

    std::string url =
        "http://" + deviceIps[uuid] + "/state";

    std::string response;

    if (httpGet(url, response)) {
        parseState(uuid, response);
    }

    outState = states[uuid];

    return true;
}

bool WifiDriver::isAvailable(const std::string& uuid){
    return states.count(uuid);
}

void WifiDriver::parseState(
    const std::string& uuid,
    const std::string& json
) {

    auto& st = states[uuid];

    size_t p;

    if ((p = json.find("power")) != std::string::npos)
        st.power =
            std::stoi(json.substr(json.find(":", p) + 1)) != 0;

    if ((p = json.find("brightness")) != std::string::npos)
        st.brightness =
            std::stoi(json.substr(json.find(":", p) + 1));

    if ((p = json.find("color")) != std::string::npos)
        st.color =
            std::stoul(json.substr(json.find(":", p) + 1));

    if ((p = json.find("temperature")) != std::string::npos)
        st.temperature =
            std::stof(json.substr(json.find(":", p) + 1));
}

}
