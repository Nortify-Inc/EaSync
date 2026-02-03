#pragma once
#include <string>
#include <vector>

enum class DeviceProtocol {
    WIFI = 0,
    MQTT = 1,
    ZIGBEE = 2,
    BLE = 3
};

enum class Capability {
    Brightness = 0,
    Color = 1,
    Temperature = 2,
    Time = 3
};

struct Device {
    int id;
    std::string name;
    int protocol;
    std::string address;
    int power = 0;
    std::vector<int> capabilities;
    std::vector<int> capabilityValues;
};
