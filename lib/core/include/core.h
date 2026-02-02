#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*CoreEventCallback)(
    int deviceId,
    int capability,
    int value
);

void init();

void shutdown();

void registerCallback(CoreEventCallback callback);

int registerDevice(
    int deviceId,
    char* name,
    int protocol, 
    const char* address
);

void removeDevice(
    int deviceId,
    char* name
);

void setPower(
    int deviceId, 
    int state);

int getPower(
    int deviceId
);

void setCapability(
    int deviceId, 
    int capability, 
    int value
);

int hasCapability(
    int deviceId, 
    int capability
);

int sendEvent(
    int deviceId, 
    int capability, 
    int value
);

void poll();

#ifdef __cplusplus
}
#endif
