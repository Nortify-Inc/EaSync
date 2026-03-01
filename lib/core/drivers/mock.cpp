/**
 * @file mock.cpp
 * @brief Implementation of the simulated driver for testing and event emulation.
 * @param uuid Identifier of the simulated device.
 * @return Methods return true when local state is updated.
 * @author Erick Radmann
 */

#include "mock.hpp"

#include <thread>
#include <chrono>
#include <atomic>
#include <cmath>

namespace drivers {

MockDriver::~MockDriver() {
    stopSimulation();
}

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
    std::lock_guard<std::mutex> lock(mutex);
    eventCallback = cb;
    eventUserData = userData;
}

void MockDriver::startSimulation() {
    if (running.load()) return;
    running.store(true);
    simulationThread = std::thread([this]() { simulationLoop(); });
}

void MockDriver::stopSimulation() {
    if (!running.load()) return;
    running.store(false);
    if (simulationThread.joinable()) {
        simulationThread.join();
    }
}

void MockDriver::simulationLoop() {
    using namespace std::chrono_literals;

    while (running.load()) {
        std::this_thread::sleep_for(500ms);

        std::string uuid;
        CoreDeviceState next{};

        {
            std::lock_guard<std::mutex> lock(mutex);

            if (states.empty())
                continue;

            auto it = states.begin();
            uuid = it->first;
            next = it->second;

            // simple toggles to emulate external change
            next.power = !next.power;
            next.brightness = (next.brightness + 10) % 101;
            next.color ^= 0x00000F0F; // small color shift
            next.temperature += 0.5f;
            next.temperatureFridge += 0.2f;
            next.temperatureFreezer -= 0.2f;
            next.timestamp += 60;
            next.colorTemperature = (next.colorTemperature + 100) % 9001;
            next.lock = !next.lock;
            next.mode = (next.mode + 1) % 6;
            next.position = std::fmod(next.position + 5.0, 101.0);
        }

        simulateExternalStateChange(uuid, next);
    }
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
            oldState.temperatureFridge == newState.temperatureFridge &&
            oldState.temperatureFreezer == newState.temperatureFreezer &&
            oldState.timestamp == newState.timestamp &&
            oldState.colorTemperature == newState.colorTemperature &&
            oldState.lock == newState.lock &&
            oldState.mode == newState.mode &&
            oldState.position == newState.position)
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