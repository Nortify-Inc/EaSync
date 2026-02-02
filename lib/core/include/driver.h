#pragma once
#include <string>
#include "event.h"

class Driver {
public:
    virtual ~Driver() = default;
    virtual int sendEvent(const Event& event) = 0;
};

class MQTTDriver : public Driver {
public:
    int sendEvent(const Event& event) override;
};

class WiFiDriver : public Driver {
public:
    int sendEvent(const Event& event) override;
};

class BLEDriver : public Driver {
public:
    int sendEvent(const Event& event) override;
};

class ZigbeeDriver : public Driver {
public:
    int sendEvent(const Event& event) override;
};
