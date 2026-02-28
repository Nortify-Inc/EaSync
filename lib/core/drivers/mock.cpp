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
    st.color = 0xFFFFFFFF;
    st.temperature = 0.0f;
    st.timestamp = 0;

    states[uuid] = st;
    return true;
}

bool MockDriver::disconnect(const std::string& uuid) {
    std::lock_guard<std::mutex> lock(mutex);
    states.erase(uuid);
    return true;
}

bool MockDriver::setPower(const std::string& uuid, bool value) {
    std::lock_guard<std::mutex> lock(mutex);

    if (!states.count(uuid))
        return false;

    states[uuid].power = value;
    return true;
}

bool MockDriver::setBrightness(const std::string& uuid, uint32_t value) {
    std::lock_guard<std::mutex> lock(mutex);

    if (!states.count(uuid))
        return false;

    states[uuid].brightness = value;
    return true;
}

bool MockDriver::setColor(const std::string& uuid, uint32_t rgb) {
    std::lock_guard<std::mutex> lock(mutex);

    if (!states.count(uuid))
        return false;

    states[uuid].color = rgb;
    return true;
}

bool MockDriver::setTemperature(const std::string& uuid, float value) {
    std::lock_guard<std::mutex> lock(mutex);

    if (!states.count(uuid))
        return false;

    states[uuid].temperature = value;
    return true;
}

bool MockDriver::setTemperatureFridge(const std::string& uuid, float value) {
    std::lock_guard<std::mutex> lock(mutex);

    if (!states.count(uuid))
        return false;

    states[uuid].temperatureFridge = value;
    return true;
}

bool MockDriver::setTemperatureFreezer(const std::string& uuid, float value) {
    std::lock_guard<std::mutex> lock(mutex);

    if (!states.count(uuid))
        return false;

    states[uuid].temperatureFreezer = value;
    return true;
}

bool MockDriver::setTime(const std::string& uuid, uint64_t value) {
    std::lock_guard<std::mutex> lock(mutex);

    if (!states.count(uuid))
        return false;

    states[uuid].timestamp = value;
    return true;
}

bool MockDriver::setColorTemperature(const std::string& uuid, uint32_t value) {
    std::lock_guard<std::mutex> lock(mutex);

    if (!states.count(uuid))
        return false;

    states[uuid].colorTemperature = value;
    return true;
}

bool MockDriver::setLock(const std::string& uuid, bool value) {
    std::lock_guard<std::mutex> lock(mutex);

    if (!states.count(uuid))
        return false;

    states[uuid].lock = value;
    return true;
}

bool MockDriver::setMode(const std::string& uuid, uint32_t value) {
    std::lock_guard<std::mutex> lock(mutex);

    if (!states.count(uuid))
        return false;

    states[uuid].mode = value;
    return true;
}

bool MockDriver::setPosition(const std::string& uuid, float value) {
    std::lock_guard<std::mutex> lock(mutex);

    if (!states.count(uuid))
        return false;

    states[uuid].position = value;
    return true;
}

bool MockDriver::getState(const std::string& uuid, CoreDeviceState& outState) {
    std::lock_guard<std::mutex> lock(mutex);

    if (!states.count(uuid))
        return false;

    outState = states[uuid];
    return true;
}

bool MockDriver::isAvailable(const std::string& uuid) {
    std::lock_guard<std::mutex> lock(mutex);
    return states.count(uuid) > 0;
}

void MockDriver::setEventCallback(
    DriverEventCallback cb,
    void* userData
) {
    eventCallback = cb;
    eventUserData = userData;
}

void MockDriver::simulateExternalStateChange(
    const std::string& uuid,
    const CoreDeviceState& newState
) {
    CoreDeviceState oldState;

    {
        std::lock_guard<std::mutex> lock(mutex);

        if (!states.count(uuid))
            return;

        oldState = states[uuid];

        if (oldState.power == newState.power &&
            oldState.brightness == newState.brightness &&
            oldState.color == newState.color &&
            oldState.temperature == newState.temperature &&
            oldState.timestamp == newState.timestamp)
            return;

        states[uuid] = newState;
    }

    notifyStateChange(uuid, newState);
}

void MockDriver::notifyStateChange(
    const std::string& uuid,
    const CoreDeviceState& newState
) {
    if (eventCallback) {
        eventCallback(uuid, newState, eventUserData);
    }
}

}