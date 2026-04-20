#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stdbool.h>

/**
 * @brief Core public API version.
 */
#define CORE_API_VERSION "0.0.5"


/**
 * @brief Return codes for all API functions.
 */
typedef enum {

    /** Operation completed successfully */
    CORE_OK = 0,

    /** Generic error */
    CORE_ERROR = -1,

    /** Resource not found */
    CORE_NOT_FOUND = -2,

    /** Resource already exists */
    CORE_ALREADY_EXISTS = -3,

    /** Invalid argument */
    CORE_INVALID_ARGUMENT = -4,

    /** Feature not supported */
    CORE_NOT_SUPPORTED = -5,

    /** Core not initialized */
    CORE_NOT_INITIALIZED = -6,

    /** Core protocol not supported */
    CORE_PROTOCOL_UNAVAILABLE = -7

} CoreResult;


/**
 * @brief Supported communication protocols.
 */
typedef enum {
    CORE_PROTOCOL_MOCK = 0,
    CORE_PROTOCOL_MQTT,
    CORE_PROTOCOL_WIFI,
    CORE_PROTOCOL_ZIGBEE,
    CORE_PROTOCOL_BLE

} CoreProtocol;


/**
 * @brief Supported device capabilities.
 */
typedef enum {

    CORE_CAP_POWER = 0,
    CORE_CAP_BRIGHTNESS,
    CORE_CAP_COLOR,
    CORE_CAP_TEMPERATURE,
    CORE_CAP_TEMPERATURE_FRIDGE,
    CORE_CAP_TEMPERATURE_FREEZER,
    CORE_CAP_TIMESTAMP, 
    CORE_CAP_COLOR_TEMP,
    CORE_CAP_LOCK,
    CORE_CAP_MODE,
    CORE_CAP_POSITION


} CoreCapability;


/**
 * @brief Opaque core context.
 */
typedef struct CoreContext CoreContext;


#define CORE_MAX_CAPS  16
#define CORE_MAX_NAME  64
#define CORE_MAX_UUID  64
#define CORE_MAX_BRAND 16
#define CORE_MAX_MODEL 32
#define CORE_MAX_USAGE_TITLE 96
#define CORE_MAX_USAGE_MESSAGE 192


/**
 * @brief Static device metadata.
 */
typedef struct {

    /** Unique device identifier */
    char uuid[CORE_MAX_UUID];

    /** Human-defineable name */
    char name[CORE_MAX_NAME];

    /** Brand of device */
    char brand[CORE_MAX_BRAND];

    /** Model of device */
    char model[CORE_MAX_MODEL];

    /** Communication protocol */
    CoreProtocol protocol;

    /** Number of supported capabilities */
    uint8_t capabilityCount;

    /** Capability list */
    CoreCapability capabilities[CORE_MAX_CAPS];

} CoreDeviceInfo;


/**
 * @brief Runtime device state.
 *
 * Unsupported fields use sentinel values.
 */
typedef struct {

    /** Power state */
    bool power;

    /** Brightness (0-100, -1 = unsupported) */
    uint32_t brightness;

    /** RGB color (0xRRGGBB, 0 = unsupported) */
    uint32_t color;

    /** Temperature in Celsius (-1 = unsupported) */
    float temperature;

    /** Temperature to fridge in Celsius (-1 = unsupported) */
    float temperatureFridge;

    /** Temperature in Celsius (-1 = unsupported) */
    float temperatureFreezer;

    /** Last update timestamp (unix ms, 0 = unsupported) */
    uint64_t timestamp;

    /**Color temperature to supported lamps*/
    uint32_t colorTemperature;

    /** Lock state */
    bool lock;

    /** Mode state */
    uint32_t mode;

    /** Position value (-1 = unsupported) */
    float position;
    
} CoreDeviceState;

/**
 * @brief AI permissions consumed by backend engine.
 */
typedef struct {
    bool useLocationData;
    bool useWeatherData;
    bool useUsageHistory;
    bool allowDeviceControl;
    bool allowAutoRoutines;
    uint32_t temperament;
} CoreAiPermissions;


/**
 * @brief Aggregated usage stats learned by the core utility.
 */
typedef struct {
    uint32_t sampleCount;
    uint32_t distinctDevices;
    int32_t predictedArrivalHour;
    float preferredTemperature;
    uint32_t preferredBrightness;
    float preferredPosition;
    char mostActiveUuid[CORE_MAX_UUID];
    float confidence;
} CoreUsageStats;


/**
 * @brief Runtime recommendation produced by usage utility.
 */
typedef struct {
    bool available;
    char title[CORE_MAX_USAGE_TITLE];
    char message[CORE_MAX_USAGE_MESSAGE];
    char uuid[CORE_MAX_UUID];
    int32_t recommendedHour;
    float confidence;
    uint64_t generatedAtMs;
} CoreUsageRecommendation;


/**
 * @brief Create a new core instance.
 *
 * @return Core context or NULL on failure.
 */
CoreContext* core_create(void);


/**
 * @brief Destroy core instance.
 *
 * @param core Core context.
 */
void core_destroy(CoreContext* core);


/**
 * @brief Initialize core.
 *
 * Must be called before any other function.
 *
 * @param core Core context.
 *
 * @return Result code.
 */
CoreResult core_init(CoreContext* core);


/**
 * @brief Register a new device.
 *
 * @param core     Core context.
 * @param uuid     Unique device identifier.
 * @param name     Display name.
 * @param protocol Communication protocol.
 * @param caps     Capability list.
 * @param capCount Number of capabilities.
 *
 * @return Result code.
 */
CoreResult core_register_device(
    CoreContext* core,
    const char* uuid,
    const char* name,
    CoreProtocol protocol,
    const CoreCapability* caps,
    uint8_t capCount
);


/**
 * @brief Register a new device with explicit brand and model.
 *
 * @param core     Core context.
 * @param uuid     Unique device identifier.
 * @param name     Display name.
 * @param brand    Device brand.
 * @param model    Device model.
 * @param protocol Communication protocol.
 * @param caps     Capability list.
 * @param capCount Number of capabilities.
 *
 * @return Result code.
 */
CoreResult core_register_device_ex(
    CoreContext* core,
    const char* uuid,
    const char* name,
    const char* brand,
    const char* model,
    CoreProtocol protocol,
    const CoreCapability* caps,
    uint8_t capCount
);


/**
 * @brief Remove a device.
 *
 * @param core Core context.
 * @param uuid Device UUID.
 *
 * @return Result code.
 */
CoreResult core_remove_device(
    CoreContext* core,
    const char* uuid
);


/**
 * @brief Retrieve device metadata.
 *
 * @param core    Core context.
 * @param uuid    Device UUID.
 * @param outInfo Output buffer.
 *
 * @return Result code.
 */
CoreResult core_get_device(
    CoreContext* core,
    const char* uuid,
    CoreDeviceInfo* outInfo
);


/**
 * @brief List registered devices.
 *
 * @param core     Core context.
 * @param buffer   Output array.
 * @param maxItems Maximum number of items.
 * @param outCount Returned count.
 *
 * @return Result code.
 */
CoreResult core_list_devices(
    CoreContext* core,
    CoreDeviceInfo* buffer,
    uint32_t maxItems,
    uint32_t* outCount
);

/**
 * @brief Check if device supports capability.
 *
 * @param core      Core context.
 * @param uuid      Device UUID.
 * @param cap       Capability.
 * @param outResult Output result.
 *
 * @return Result code.
 */
CoreResult core_has_capability(
    CoreContext* core,
    const char* uuid,
    CoreCapability cap,
    bool* outResult
);


/**
 * @brief Get current device state.
 *
 * @param core     Core context.
 * @param uuid     Device UUID.
 * @param outState Output buffer.
 *
 * @return Result code.
 */
CoreResult core_get_state(
    CoreContext* core,
    const char* uuid,
    CoreDeviceState* outState
);

/**
 * @brief Check whether a registered device is currently available.
 */
CoreResult core_is_device_available(
    CoreContext* core,
    const char* uuid,
    bool* outAvailable
);


/**
 * @brief Set power state.
 */
CoreResult core_set_power(
    CoreContext* core,
    const char* uuid,
    bool value
);


/**
 * @brief Set brightness level.
 */
CoreResult core_set_brightness(
    CoreContext* core,
    const char* uuid,
    uint32_t value
);


/**
 * @brief Set color value.
 */
CoreResult core_set_color(
    CoreContext* core,
    const char* uuid,
    uint32_t value
);


/**
 * @brief Set temperature value.
 */
CoreResult core_set_temperature(
    CoreContext* core,
    const char* uuid,
    float value
);


/**
 * @brief Set temperature for fridge.
 */
CoreResult core_set_temperature_fridge(
    CoreContext* core,
    const char* uuid,   
    float value
);


/**
 * @brief Set temperature for freezer.
 */
CoreResult core_set_temperature_freezer(
    CoreContext* core,
    const char* uuid,
    float value
);


/**
 * @brief Set timestamp value.
 */
CoreResult core_set_time(
    CoreContext* core,
    const char* uuid,
    uint64_t value
);


/**
 * @brief Set color warmth value.
 */
CoreResult core_set_color_temperature(
    CoreContext* core,
    const char* uuid,
    uint32_t value
);


/**
 * @brief Set lock state.
 */
CoreResult core_set_lock(
    CoreContext* core,
    const char* uuid,
    bool value
);



/**
 * @brief Set mode state.
 */
CoreResult core_set_mode(   
    CoreContext* core,
    const char* uuid,
    uint32_t value
);


/**
 * @brief Set position value.
 */
CoreResult core_set_position(
    CoreContext* core,
    const char* uuid,
    float value
);

/**
 * @brief Send Wi-Fi credentials to a Wi-Fi device.
 */
CoreResult core_provision_wifi(
    CoreContext* core,
    const char* uuid,
    const char* ssid,
    const char* password
);

/**
 * @brief Update device endpoint (host[:port]) for protocol drivers.
 */
CoreResult core_set_device_endpoint(
    CoreContext* core,
    const char* uuid,
    const char* endpoint
);

/**
 * @brief Set a dynamic per-device credential/property (e.g. token/key).
 */
CoreResult core_set_device_credential(
    CoreContext* core,
    const char* uuid,
    const char* key,
    const char* value
);

/**
 * @brief Establish connection to a device (via AdaptiveLayer).
 */
CoreResult core_establish_connection(
    CoreContext* core,
    const char* uuid
);

/**
 * @brief Ensure device is connected, reconnecting if needed.
 */
CoreResult core_ensure_connected(
    CoreContext* core,
    const char* uuid
);

/**
 * @brief Disconnect from a device.
 */
CoreResult core_disconnect_device(
    CoreContext* core,
    const char* uuid
);

/**
 * @brief Get device connection state label.
 */
CoreResult core_get_connection_state(
    CoreContext* core,
    const char* uuid,
    char* outBuffer,
    uint32_t bufferSize
);

/**
 * @brief Discover devices on the network.
 */
CoreResult core_discover_devices(
    CoreContext* core,
    CoreProtocol protocol,
    int timeoutMs,
    char* outBuffer,
    uint32_t bufferSize,
    uint32_t* outWritten
);

/**
 * @brief Simulate external state changes for all devices.
 *
 * Generates random values for supported capabilities and dispatches
 * STATE_CHANGED events so consumers can observe UI updates.
 */
CoreResult core_simulate(CoreContext* core);


/**
 * @brief Return learned usage stats from core utility.
 */
CoreResult core_usage_get_stats(
    CoreContext* core,
    CoreUsageStats* outStats
);


/**
 * @brief Return a recommendation generated from learned usage patterns.
 */
CoreResult core_usage_get_recommendation(
    CoreContext* core,
    CoreUsageRecommendation* outRecommendation
);


/**
 * @brief Export normalized observation vectors as CSV for ML pipelines.
 */
CoreResult core_usage_export_samples_csv(
    CoreContext* core,
    char* outBuffer,
    uint32_t bufferSize,
    uint32_t* outWritten
);


/**
 * @brief Observe frontend-generated learning events encoded as JSON.
 *
 * The payload is intentionally lightweight and tolerant; unsupported event
 * formats are ignored and return CORE_OK to keep ingestion non-blocking.
 */
CoreResult core_usage_observe_frontend_json(
    CoreContext* core,
    const char* eventJson
);



/**
 * @brief Get last error message.
 *
 * @param core Core context.
 *
 * @return Null-terminated string.
 */
const char* core_last_error(CoreContext* core);


/**
 * @brief Core event types.
 */
typedef enum {

    CORE_EVENT_DEVICE_ADDED = 0,
    CORE_EVENT_DEVICE_REMOVED,
    CORE_EVENT_STATE_CHANGED,
    CORE_EVENT_ERROR

} CoreEventType;


/**
 * @brief Event payload.
 */
typedef struct {

    /** Event type */
    CoreEventType type;

    /** Device UUID (if applicable) */
    char uuid[CORE_MAX_UUID];

    /** Current device state (STATE_CHANGED) */
    CoreDeviceState state;

    /** Error code (ERROR event) */
    int errorCode;

} CoreEvent;


/**
 * @brief Event callback function.
 *
 * @param event    Event descriptor.
 * @param userdata User pointer.
 */
typedef void (*CoreEventCallback)(
    const CoreEvent* event,
    void* userdata
);


/**
 * @brief Register event callback.
 *
 * @param core     Core context.
 * @param callback Callback function.
 * @param userdata User data.
 *
 * @return Result code.
 */
CoreResult core_set_event_callback(
    CoreContext* core,
    CoreEventCallback callback,
    void* userdata
);

#ifdef __cplusplus
}

#endif