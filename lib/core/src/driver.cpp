#include "driver.h"
#include <iostream>
#include <curl/curl.h>
#include <mqtt/async_client.h>
#include <gattlib.h>
#include <nlohmann/json.hpp>
#include <cstring>

int WiFiDriver::sendEvent(const Event& event) {
    CURL* curl = curl_easy_init();
    if (!curl) return 1;

    std::string url = "http://" + event.address + "/set";
    nlohmann::json payload = {{"capability", event.capability}, {"value", event.value}};
    std::string payloadStr = payload.dump();

    struct curl_slist* headers = nullptr;
    headers = curl_slist_append(headers, "Content-Type: application/json");

    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, payloadStr.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);

    CURLcode res = curl_easy_perform(curl);

    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);

    return (res == CURLE_OK) ? 0 : 1;
}

int MQTTDriver::sendEvent(const Event& event) {
    try {
        const std::string broker = event.address;
        const std::string topic = "devices/" + std::to_string(event.deviceId) + "/set";
        nlohmann::json payload = {{"capability", event.capability}, {"value", event.value}};

        mqtt::async_client client(broker, "");
        mqtt::message_ptr msg = mqtt::make_message(topic, payload.dump());

        client.connect()->wait();
        client.publish(msg)->wait();
        client.disconnect()->wait();
        return 0;
    } catch (...) {
        return 1;
    }
}

int ZigbeeDriver::sendEvent(const Event& event) {
    try {
        const std::string broker = "tcp://127.0.0.1:1883";
        const std::string topic = "zigbee2mqtt/" + event.address + "/set";
        nlohmann::json payload = {{"capability", event.capability}, {"value", event.value}};

        mqtt::async_client client(broker, "");
        mqtt::message_ptr msg = mqtt::make_message(topic, payload.dump());
        client.connect()->wait();
        client.publish(msg)->wait();
        client.disconnect()->wait();
        return 0;

    } catch (...) {
        return 1;
    }
}

int BLEDriver::sendEvent(const Event& event) {
    gattlib_connection_t* conn = nullptr;
    int ret = gattlib_connect(NULL, event.address.c_str(), BDADDR_LE_PUBLIC, NULL, NULL);
    if (!ret || !conn) return 1;

    uuid_t uuid;
    gattlib_string_to_uuid("0000fff1-0000-1000-8000-00805f9b34fb",
                           std::strlen("0000fff1-0000-1000-8000-00805f9b34fb"),
                           &uuid);

    uint8_t value[4] = { static_cast<uint8_t>(event.value & 0xFF) };

    ret = gattlib_write_char_by_uuid(conn, &uuid, value, sizeof(value));
    gattlib_disconnect(conn, true);

    return (ret == 0) ? 0 : 1;
}
