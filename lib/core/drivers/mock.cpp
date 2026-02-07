#include "mock.hpp"

namespace drivers {

bool MockDriver::init() {
    return true;
}

bool MockDriver::connect(const std::string& uuid) {

    std::lock_guard<std::mutex> lock(mutex);

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


void MockDriver::disconnect(const std::string& uuid) {

    std::lock_guard<std::mutex> lock(mutex);

    states.erase(uuid);
}


bool MockDriver::setPower(
    const std::string& uuid,
    bool value
) {

    std::lock_guard<std::mutex> lock(mutex);

    if (!states.count(uuid))
        return false;

    states[uuid].power = value;

    return true;
}


bool MockDriver::setBrightness(
    const std::string& uuid,
    int value
) {

    std::lock_guard<std::mutex> lock(mutex);

    if (!states.count(uuid))
        return false;

    states[uuid].brightness = value;

    return true;
}


bool MockDriver::setColor(
    const std::string& uuid,
    uint32_t rgb
) {

    std::lock_guard<std::mutex> lock(mutex);

    if (!states.count(uuid))
        return false;

    states[uuid].color = rgb;

    return true;
}


bool MockDriver::setTemperature(
    const std::string& uuid,
    float value
) {

    std::lock_guard<std::mutex> lock(mutex);

    if (!states.count(uuid))
        return false;

    states[uuid].temperature = value;

    return true;
}


bool MockDriver::getState(
    const std::string& uuid,
    CoreDeviceState& outState
) {

    std::lock_guard<std::mutex> lock(mutex);

    if (!states.count(uuid))
        return false;

    outState = states[uuid];

    return true;
}

}
