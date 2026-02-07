#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stdbool.h>


/* ============================================================
   API Version
============================================================ */

/**
 * @brief EaSync Core API version.
 */
#define EAS_API_VERSION 1


/* ============================================================
   Result Codes
============================================================ */

/**
 * @brief Return codes for all API functions.
 */
typedef enum {

    /** Operation completed successfully */
    EAS_OK = 0,

    /** Generic error */
    EAS_ERROR = -1,

    /** Resource not found */
    EAS_NOT_FOUND = -2,

    /** Resource already exists */
    EAS_ALREADY_EXISTS = -3,

    /** Invalid argument */
    EAS_INVALID_ARGUMENT = -4,

    /** Feature not supported */
    EAS_NOT_SUPPORTED = -5,

    /** Core not initialized */
    EAS_NOT_INITIALIZED = -6

} EasResult;


/* ============================================================
   Protocol Types
============================================================ */

/**
 * @brief Supported communication protocols.
 */
typedef enum {

    EAS_PROTOCOL_WIFI = 0,
    EAS_PROTOCOL_MQTT,
    EAS_PROTOCOL_ZIGBEE,
    EAS_PROTOCOL_BLE

} EasProtocol;


/* ============================================================
   Device Capabilities
============================================================ */

/**
 * @brief Supported device capabilities.
 */
typedef enum {

    EAS_CAP_POWER = 0,
    EAS_CAP_BRIGHTNESS,
    EAS_CAP_COLOR,
    EAS_CAP_TEMPERATURE,
    EAS_CAP_TIMESTAMP

} EasCapability;


/* ============================================================
   Forward Declarations
============================================================ */

/**
 * @brief Opaque core context handle.
 */
typedef struct EasCore EasCore;


/* ============================================================
   Limits
============================================================ */

#define EAS_MAX_CAPS   16
#define EAS_MAX_NAME  64
#define EAS_MAX_UUID  64


/* ============================================================
   Device Information
============================================================ */

/**
 * @brief Static device metadata.
 */
typedef struct {

    char uuid[EAS_MAX_UUID];

    char name[EAS_MAX_NAME];

    EasProtocol protocol;

    uint8_t capabilityCount;

    EasCapability capabilities[EAS_MAX_CAPS];

} EasDeviceInfo;


/* ============================================================
   Device State
============================================================ */

/**
 * @brief Runtime device state.
 *
 * Unsupported fields use sentinel values.
 */
typedef struct {

    bool power;

    int brightness;

    uint32_t color;

    float temperature;

    uint64_t timestamp;

} EasDeviceState;


/* ============================================================
   Core Lifecycle
============================================================ */

/**
 * @brief Create a new core instance.
 *
 * @return Core context or NULL.
 */
EasCore* eas_core_create(void);


/**
 * @brief Destroy core instance.
 *
 * @param core Core context.
 */
void eas_core_destroy(EasCore* core);


/**
 * @brief Initialize core.
 *
 * @param core Core context.
 *
 * @return Result code.
 */
EasResult eas_core_init(EasCore* core);


/* ============================================================
   Device Management
============================================================ */

/**
 * @brief Register device.
 *
 * @param core Core context.
 * @param uuid Unique identifier.
 * @param name Display name.
 * @param protocol Communication protocol.
 * @param caps Capability list.
 * @param capCount Capability count.
 *
 * @return Result code.
 */
EasResult eas_core_register_device(
    EasCore* core,
    const char* uuid,
    const char* name,
    EasProtocol protocol,
    const EasCapability* caps,
    uint8_t capCount
);


/**
 * @brief Remove device.
 *
 * @param core Core context.
 * @param uuid Device UUID.
 *
 * @return Result code.
 */
EasResult eas_core_remove_device(
    EasCore* core,
    const char* uuid
);


/**
 * @brief Get device metadata.
 *
 * @param core Core context.
 * @param uuid Device UUID.
 * @param outInfo Output buffer.
 *
 * @return Result code.
 */
EasResult eas_core_get_device(
    EasCore* core,
    const char* uuid,
    EasDeviceInfo* outInfo
);


/**
 * @brief List devices.
 *
 * @param core Core context.
 * @param buffer Output buffer.
 * @param maxItems Max items.
 * @param outCount Returned count.
 *
 * @return Result code.
 */
EasResult eas_core_list_devices(
    EasCore* core,
    EasDeviceInfo* buffer,
    uint32_t maxItems,
    uint32_t* outCount
);


/* ============================================================
   Capability / State
============================================================ */

/**
 * @brief Test capability.
 *
 * @param core Core context.
 * @param uuid Device UUID.
 * @param cap Capability.
 * @param outResult Output result.
 *
 * @return Result code.
 */
EasResult eas_core_has_capability(
    EasCore* core,
    const char* uuid,
    EasCapability cap,
    bool* outResult
);


/**
 * @brief Get device state.
 *
 * @param core Core context.
 * @param uuid Device UUID.
 * @param outState Output state.
 *
 * @return Result code.
 */
EasResult eas_core_get_state(
    EasCore* core,
    const char* uuid,
    EasDeviceState* outState
);


/* ============================================================
   State Setters
============================================================ */

/**
 * @brief Set power.
 *
 * @param core Core context.
 * @param uuid Device UUID.
 * @param value Power value.
 *
 * @return Result code.
 */
EasResult eas_core_set_power(
    EasCore* core,
    const char* uuid,
    bool value
);


/**
 * @brief Set brightness.
 *
 * @param core Core context.
 * @param uuid Device UUID.
 * @param value 0-100.
 *
 * @return Result code.
 */
EasResult eas_core_set_brightness(
    EasCore* core,
    const char* uuid,
    int value
);


/**
 * @brief Set color.
 *
 * @param core Core context.
 * @param uuid Device UUID.
 * @param value RGB.
 *
 * @return Result code.
 */
EasResult eas_core_set_color(
    EasCore* core,
    const char* uuid,
    uint32_t value
);


/**
 * @brief Set temperature.
 *
 * @param core Core context.
 * @param uuid Device UUID.
 * @param value Celsius.
 *
 * @return Result code.
 */
EasResult eas_core_set_temperature(
    EasCore* core,
    const char* uuid,
    float value
);


/* ============================================================
   Diagnostics
============================================================ */

/**
 * @brief Get last error.
 *
 * @param core Core context.
 *
 * @return Error string.
 */
const char* eas_core_last_error(EasCore* core);


/* ============================================================
   Events
============================================================ */

/**
 * @brief Core event types.
 */
typedef enum {

    EAS_EVENT_DEVICE_ADDED = 0,
    EAS_EVENT_DEVICE_REMOVED,
    EAS_EVENT_STATE_CHANGED,
    EAS_EVENT_ERROR

} EasEventType;


/**
 * @brief Event payload.
 */
typedef struct {

    EasEventType type;

    char uuid[EAS_MAX_UUID];

    EasDeviceState state;

    int errorCode;

} EasEvent;


/**
 * @brief Event callback.
 *
 * @param event Event descriptor.
 * @param userdata User pointer.
 */
typedef void (*EasEventCallback)(
    const EasEvent* event,
    void* userdata
);


/**
 * @brief Register event callback.
 *
 * @param core Core context.
 * @param callback Callback.
 * @param userdata User data.
 *
 * @return Result code.
 */
EasResult eas_core_set_event_callback(
    EasCore* core,
    EasEventCallback callback,
    void* userdata
);

#ifdef __cplusplus
}
#endif
