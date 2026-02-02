#pragma once
#include <string>
#include <vector>

enum class DeviceProtocol {
    MQTT = 0,
    ZIGBEE = 1,
    BLE = 2
};

enum class Capability {
    Brightness = 0,
    Color = 1,
    Temperature = 2,
    Time = 3
};

struct Device {
    int id;
    char* name;
    DeviceProtocol protocol;
    std::string address;
    std::vector<Capability> capabilities;
};
