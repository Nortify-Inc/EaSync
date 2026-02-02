#include "core.h"
#include <vector>
#include <string>
#include <mutex>

struct Device {
    int id;
    std::string name;
    int protocol;
    std::string address;
    int power = 0;
    std::vector<int> capabilities;
    std::vector<int> capabilityValues;
};

static std::vector<Device> devices;
static CoreEventCallback globalCallback = nullptr;
static std::mutex devicesMutex;

void init() {
    std::lock_guard<std::mutex> lock(devicesMutex);
    for (auto& device : devices) {
        if (globalCallback) globalCallback(device.id, 0, device.power);
        for (size_t i = 0; i < device.capabilities.size(); ++i) {
            if (globalCallback) globalCallback(device.id, device.capabilities[i], device.capabilityValues[i]);
        }
    }
}

void shutdown() {
    std::lock_guard<std::mutex> lock(devicesMutex);
    devices.clear();
    globalCallback = nullptr;
}

void registerCallback(CoreEventCallback callback) {
    globalCallback = callback;
}

int registerDevice(int deviceId, char* name, int protocol, const char* address) {
    std::lock_guard<std::mutex> lock(devicesMutex);
    Device device;
    device.id = deviceId;
    device.name = name ? std::string(name) : "";
    device.protocol = protocol;
    device.address = address ? std::string(address) : "";
    device.capabilities = {1, 2}; 
    device.capabilityValues = {0, 0};
    devices.push_back(device);
    return device.id;
}

void removeDevice(int deviceId, char* name) {
    std::lock_guard<std::mutex> lock(devicesMutex);
    for (auto it = devices.begin(); it != devices.end(); ++it) {
        bool match = false;
        if (deviceId >= 0) match = (it->id == deviceId);
        else if (name) match = (it->name == std::string(name));
        if (match) {
            devices.erase(it);
            return;
        }
    }
}

void setPower(int deviceId, int state) {
    std::lock_guard<std::mutex> lock(devicesMutex);
    for (auto& device : devices) {
        if (device.id == deviceId) {
            device.power = state;
            if (globalCallback) globalCallback(device.id, 0, device.power);
            return;
        }
    }
}

int getPower(int deviceId) {
    std::lock_guard<std::mutex> lock(devicesMutex);
    for (auto& device : devices) {
        if (device.id == deviceId) return device.power;
    }
    return -1; 
}

void setCapability(int deviceId, int capability, int value) {
    std::lock_guard<std::mutex> lock(devicesMutex);
    for (auto& device : devices) {
        if (device.id == deviceId) {
            for (size_t i = 0; i < device.capabilities.size(); ++i) {
                if (device.capabilities[i] == capability) {
                    device.capabilityValues[i] = value;
                    if (globalCallback) globalCallback(device.id, capability, value);
                    return;
                }
            }
        }
    }
}

int hasCapability(int deviceId, int capability) {
    std::lock_guard<std::mutex> lock(devicesMutex);
    for (auto& device : devices) {
        if (device.id == deviceId) {
            for (int cap : device.capabilities) {
                if (cap == capability) return 1;
            }
        }
    }
    return 0;
}

int sendEvent(int deviceId, int capability, int value) {
    if (globalCallback) {
        globalCallback(deviceId, capability, value);
        return 0;
    }
    return 1;
}

void poll() {
    std::lock_guard<std::mutex> lock(devicesMutex);
    for (auto& device : devices) {
        if (globalCallback) globalCallback(device.id, 0, device.power);
        for (size_t i = 0; i < device.capabilities.size(); ++i) {
            if (globalCallback) globalCallback(device.id, device.capabilities[i], device.capabilityValues[i]);
        }
    }
}
