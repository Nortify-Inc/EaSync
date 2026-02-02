#pragma once
#include "event.h"

class Driver {
public:
    virtual void sendEvent(const Event& event) = 0;
    virtual void poll() {}
    virtual ~Driver() = default;
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
