#include "ble.hpp"

#include <cstring>
#include <iostream>

namespace drivers {

static const char* MAIN_SERVICE_UUID =
    "12345678-1234-5678-1234-56789abcdef0";

bool BleDriver::init() {
    return true;
}

/* ---------------------------------- */
/* Connect */
/* ---------------------------------- */

bool BleDriver::connect(const std::string& mac) {

    std::lock_guard<std::mutex> lock(mutex);

    if (connections.count(mac))
        return true;

    gattlib_connection_t* conn = nullptr;

    int ret = gattlib_connect(
        nullptr,
        mac.c_str(),
        GATTLIB_CONNECTION_OPTIONS_LEGACY_DEFAULT,
        nullptr,
        nullptr
    );

    if (ret != GATTLIB_SUCCESS || !conn)
        return false;

    connections[mac] = conn;

    CoreDeviceState st{};
    st.power = false;
    st.brightness = 0;
    st.color = 0;
    st.temperature = 20.0f;
    st.timestamp = 0;

    states[mac] = st;

    if (!discoverCharacteristics(mac)) {
        disconnect(mac);
        return false;
    }

    return true;
}


/* ---------------------------------- */
/* Disconnect */
/* ---------------------------------- */

bool BleDriver::disconnect(
    const std::string& mac
) {

    std::lock_guard<std::mutex> lock(mutex);

    if (!connections.count(mac))
        return true;

    int conn = gattlib_disconnect(
        connections[mac],
        true
    );

    connections.erase(mac);
    characteristics.erase(mac);
    states.erase(mac);


    if(!conn == GATTLIB_SUCCESS);
        return false;

    return true;
}

/* ---------------------------------- */
/* Discovery */
/* ---------------------------------- */

static bool endsWith(
    const std::string& str,
    const std::string& suffix
) {
    if (str.size() < suffix.size())
        return false;

    return std::equal(
        suffix.rbegin(),
        suffix.rend(),
        str.rbegin()
    );
}

bool BleDriver::discoverCharacteristics(
    const std::string& mac
) {

    auto it = connections.find(mac);

    if (it == connections.end())
        return false;

    gattlib_connection_t* conn = it->second;

    gattlib_primary_service_t* services;
    int serviceCount;

    int ret = gattlib_discover_primary(
        conn,
        &services,
        &serviceCount
    );

    if (ret != GATTLIB_SUCCESS)
        return false;

    bool found = false;

    for (int i = 0; i < serviceCount; i++) {

        char uuidStr[40];

        gattlib_uuid_to_string(
            &services[i].uuid,
            uuidStr,
            sizeof(uuidStr)
        );

        if (std::string(uuidStr) != MAIN_SERVICE_UUID)
            continue;

        found = true;

        gattlib_characteristic_t* chars;
        int charCount;

        ret = gattlib_discover_char(
            conn,
            &chars,
            &charCount
        );

        if (ret != GATTLIB_SUCCESS)
            continue;

        auto& map = characteristics[mac];

        for (int j = 0; j < charCount; j++) {

            char cUuid[40];

            gattlib_uuid_to_string(
                &chars[j].uuid,
                cUuid,
                sizeof(cUuid)
            );

            std::string s(cUuid);
            
            if (endsWith(s, "f1"))
                map["power"] = chars[j].uuid;

            else if (endsWith(s, "f2"))
                map["brightness"] = chars[j].uuid;

            else if (endsWith(s, "f3"))
                map["color"] = chars[j].uuid;
                

            else if (endsWith(s, "f4"))
                map["temperature"] = chars[j].uuid;
        }

        free(chars);
    }

    free(services);

    return found;
}

/* ---------------------------------- */
/* Setters */
/* ---------------------------------- */

bool BleDriver::setPower(
    const std::string& mac,
    bool value
) {

    std::lock_guard<std::mutex> lock(mutex);

    if (!connections.count(mac))
        return false;

    if (!characteristics[mac].count("power"))
        return false;

    uint8_t v = value ? 1 : 0;

    int ret = gattlib_write_char_by_uuid(
        connections[mac],
        &characteristics[mac]["power"],
        &v,
        sizeof(v)
    );

    if (ret != GATTLIB_SUCCESS)
        return false;

    states[mac].power = value;

    return true;
}


bool BleDriver::setBrightness(
    const std::string& mac,
    int value
) {

    std::lock_guard<std::mutex> lock(mutex);

    if (!connections.count(mac))
        return false;

    if (!characteristics[mac].count("brightness"))
        return false;

    uint8_t v = value;

    int ret = gattlib_write_char_by_uuid(
        connections[mac],
        &characteristics[mac]["brightness"],
        &v,
        sizeof(v)
    );

    if (ret != GATTLIB_SUCCESS)
        return false;

    states[mac].brightness = value;

    return true;
}


bool BleDriver::setColor(
    const std::string& mac,
    uint32_t rgb
) {

    std::lock_guard<std::mutex> lock(mutex);

    if (!connections.count(mac))
        return false;

    if (!characteristics[mac].count("color"))
        return false;

    uint32_t v = rgb;

    int ret = gattlib_write_char_by_uuid(
        connections[mac],
        &characteristics[mac]["color"],
        &v,
        sizeof(v)
    );

    if (ret != GATTLIB_SUCCESS)
        return false;

    states[mac].color = rgb;

    return true;
}


bool BleDriver::setTemperature(
    const std::string& mac,
    float value
) {

    std::lock_guard<std::mutex> lock(mutex);

    if (!connections.count(mac))
        return false;

    if (!characteristics[mac].count("temperature"))
        return false;

    float v = value;

    int ret = gattlib_write_char_by_uuid(
        connections[mac],
        &characteristics[mac]["temperature"],
        &v,
        sizeof(v)
    );

    if (ret != GATTLIB_SUCCESS)
        return false;

    states[mac].temperature = value;

    return true;
}

/* ---------------------------------- */
/* Get State */
/* ---------------------------------- */

bool BleDriver::getState(
    const std::string& mac,
    CoreDeviceState& outState
) {

    std::lock_guard<std::mutex> lock(mutex);

    if (!states.count(mac))
        return false;

    outState = states[mac];

    return true;
}

bool BleDriver::isAvailable(const std::string& uuid) {
    std::lock_guard<std::mutex> lock(mutex);

    auto it = connections.find(uuid);

    if (it == connections.end())
        return false;

    return it->second != nullptr;


}

}
