#include "ble.hpp"

#include <filesystem>

namespace drivers {

bool BleDriver::init() {
    // Linux BlueZ adapters usually appear as /sys/class/bluetooth/hciX.
    adapterAvailable = std::filesystem::exists("/sys/class/bluetooth");
    return adapterAvailable;
}

bool BleDriver::connect(const std::string& uuid) {
    std::lock_guard<std::mutex> lock(mutex);

    if (!adapterAvailable)
        return false;

    if (states.count(uuid))
        return true;

    states.emplace(uuid, CoreDeviceState{});
    return true;
}

bool BleDriver::disconnect(const std::string& uuid) {
    std::lock_guard<std::mutex> lock(mutex);
    states.erase(uuid);
    return true;
}

bool BleDriver::ensureConnected(const std::string& uuid) {
    if (!adapterAvailable)
        return false;
    return states.count(uuid) > 0;
}

void BleDriver::notifyStateChange(const std::string& uuid, const CoreDeviceState& newState) {
    if (eventCallback) {
        eventCallback(uuid, newState, eventUserData);
    }
}

bool BleDriver::setPower(const std::string& uuid, bool value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!ensureConnected(uuid)) return false;
    states[uuid].power = value;
    notifyStateChange(uuid, states[uuid]);
    return true;
}

bool BleDriver::setBrightness(const std::string& uuid, uint32_t value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!ensureConnected(uuid)) return false;
    states[uuid].brightness = value;
    notifyStateChange(uuid, states[uuid]);
    return true;
}

bool BleDriver::setColor(const std::string& uuid, uint32_t rgb) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!ensureConnected(uuid)) return false;
    states[uuid].color = rgb;
    notifyStateChange(uuid, states[uuid]);
    return true;
}

bool BleDriver::setTemperature(const std::string& uuid, float value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!ensureConnected(uuid)) return false;
    states[uuid].temperature = value;
    notifyStateChange(uuid, states[uuid]);
    return true;
}

bool BleDriver::setTemperatureFridge(const std::string& uuid, float value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!ensureConnected(uuid)) return false;
    states[uuid].temperatureFridge = value;
    notifyStateChange(uuid, states[uuid]);
    return true;
}

bool BleDriver::setTemperatureFreezer(const std::string& uuid, float value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!ensureConnected(uuid)) return false;
    states[uuid].temperatureFreezer = value;
    notifyStateChange(uuid, states[uuid]);
    return true;
}

bool BleDriver::setTime(const std::string& uuid, uint64_t value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!ensureConnected(uuid)) return false;
    states[uuid].timestamp = value;
    notifyStateChange(uuid, states[uuid]);
    return true;
}

bool BleDriver::setColorTemperature(const std::string& uuid, uint32_t value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!ensureConnected(uuid)) return false;
    states[uuid].colorTemperature = value;
    notifyStateChange(uuid, states[uuid]);
    return true;
}

bool BleDriver::setLock(const std::string& uuid, bool value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!ensureConnected(uuid)) return false;
    states[uuid].lock = value;
    notifyStateChange(uuid, states[uuid]);
    return true;
}

bool BleDriver::setMode(const std::string& uuid, uint32_t value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!ensureConnected(uuid)) return false;
    states[uuid].mode = value;
    notifyStateChange(uuid, states[uuid]);
    return true;
}

bool BleDriver::setPosition(const std::string& uuid, float value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!ensureConnected(uuid)) return false;
    states[uuid].position = value;
    notifyStateChange(uuid, states[uuid]);
    return true;
}

bool BleDriver::getState(const std::string& uuid, CoreDeviceState& outState) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!ensureConnected(uuid)) return false;
    outState = states[uuid];
    return true;
}

bool BleDriver::isAvailable(const std::string& uuid) {
    std::lock_guard<std::mutex> lock(mutex);
    return adapterAvailable && states.count(uuid) > 0;
}

void BleDriver::setEventCallback(DriverEventCallback cb, void* userData) {
    std::lock_guard<std::mutex> lock(mutex);
    eventCallback = cb;
    eventUserData = userData;
}

} // namespace drivers
