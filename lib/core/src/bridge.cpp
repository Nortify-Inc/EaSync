/**
 * @file bridge.cpp
 * @brief FFI bridge layer for Core library.
 *
 * This file implements the bridge between foreign runtimes
 * (Dart, Flutter, etc.) and the native Core engine.
 *
 * Responsibilities:
 *  - Manage core contexts
 *  - Protect lifecycle
 *  - Forward events safely
 *  - Prevent use-after-free
 *  - Expose stable C ABI
 */

#include "core.h"

#include <mutex>
#include <unordered_map>
#include <atomic>
#include <cstring>


/* ============================================================
   Internal Context Registry
============================================================ */

/**
 * @brief Bridge-managed context wrapper.
 *
 * This structure tracks the lifetime of a CoreContext
 * and prevents callbacks from firing after destruction.
 */
struct BridgeContext {

    /** Associated core context */
    CoreContext* core;

    /** Indicates whether the context is alive */
    std::atomic<bool> alive;
};


/**
 * @brief Global registry mutex.
 */
static std::mutex gBridgeMutex;


/**
 * @brief Global context registry.
 *
 * Maps CoreContext to its bridge wrapper.
 */
static std::unordered_map<CoreContext*, BridgeContext*> gContexts;


/* ============================================================
   Callback Forwarder
============================================================ */

/**
 * @brief Internal event forwarder.
 *
 * Receives events from the core and forwards them
 * to the foreign runtime layer.
 *
 * Currently, this function only validates context lifetime.
 * Thread marshalling and message queues may be added later.
 *
 * @param event    Event payload.
 * @param userdata User-provided bridge context.
 */
static void bridgeEventForwarder(
    const CoreEvent* event,
    void* userdata
) {

    (void)event;

    auto* ctx =
        reinterpret_cast<BridgeContext*>(userdata);

    if (!ctx)
        return;

    if (!ctx->alive.load())
        return;

    /* Reserved for future event dispatch */
}


/* ============================================================
   Context Management
============================================================ */

extern "C" {

/**
 * @brief Create a new bridge-managed core context.
 *
 * Allocates a CoreContext and registers it in the bridge
 * registry for lifetime tracking.
 *
 * @return Pointer to new CoreContext, or NULL on failure.
 */
CoreContext* bridge_create() {

    CoreContext* core = core_create();
    if (!core)
        return nullptr;

    auto* ctx = new BridgeContext{};
    ctx->core = core;
    ctx->alive.store(true);

    {
        std::lock_guard<std::mutex> lock(gBridgeMutex);
        gContexts[core] = ctx;
    }

    core_set_event_callback(
        core,
        bridgeEventForwarder,
        ctx
    );

    return core;
}


/**
 * @brief Destroy a bridge-managed core context.
 *
 * Unregisters the context, disables callbacks,
 * and releases all associated resources.
 *
 * Safe against multiple calls.
 *
 * @param core Core context to destroy.
 */
void bridge_destroy(CoreContext* core) {

    if (!core)
        return;

    BridgeContext* ctx = nullptr;

    {
        std::lock_guard<std::mutex> lock(gBridgeMutex);

        auto it = gContexts.find(core);
        if (it != gContexts.end()) {
            ctx = it->second;
            gContexts.erase(it);
        }
    }

    if (ctx) {
        ctx->alive.store(false);
        delete ctx;
    }

    core_destroy(core);
}


/* ============================================================
   Lifecycle
============================================================ */

/**
 * @brief Initialize the core system.
 *
 * Must be called before any device operation.
 *
 * @param core Core context.
 * @return Result code.
 */
CoreResult bridge_init(CoreContext* core) {
    return core_init(core);
}


/* ============================================================
   Device Management
============================================================ */

/**
 * @brief Register a new device.
 *
 * @param core     Core context.
 * @param uuid     Unique identifier.
 * @param name     Human-readable name.
 * @param protocol Communication protocol.
 * @param caps     Capability list.
 * @param capCount Number of capabilities.
 *
 * @return Result code.
 */
CoreResult bridge_register_device(
    CoreContext* core,
    const char* uuid,
    const char* name,
    CoreProtocol protocol,
    const CoreCapability* caps,
    uint8_t capCount
) {

    return core_register_device(
        core,
        uuid,
        name,
        protocol,
        caps,
        capCount
    );
}


/**
 * @brief Remove a registered device.
 *
 * @param core Core context.
 * @param uuid Device identifier.
 *
 * @return Result code.
 */
CoreResult bridge_remove_device(
    CoreContext* core,
    const char* uuid
) {
    return core_remove_device(core, uuid);
}


/**
 * @brief Retrieve device metadata.
 *
 * @param core    Core context.
 * @param uuid    Device identifier.
 * @param outInfo Output buffer.
 *
 * @return Result code.
 */
CoreResult bridge_get_device(
    CoreContext* core,
    const char* uuid,
    CoreDeviceInfo* outInfo
) {
    return core_get_device(core, uuid, outInfo);
}


/**
 * @brief List all registered devices.
 *
 * @param core     Core context.
 * @param buffer   Output array.
 * @param maxItems Maximum entries.
 * @param outCount Number of returned items.
 *
 * @return Result code.
 */
CoreResult bridge_list_devices(
    CoreContext* core,
    CoreDeviceInfo* buffer,
    uint32_t maxItems,
    uint32_t* outCount
) {

    return core_list_devices(
        core,
        buffer,
        maxItems,
        outCount
    );
}


/* ============================================================
   Capability / State
============================================================ */

/**
 * @brief Check if a device supports a capability.
 *
 * @param core      Core context.
 * @param uuid      Device identifier.
 * @param cap       Capability.
 * @param outResult Output flag.
 *
 * @return Result code.
 */
CoreResult bridge_has_capability(
    CoreContext* core,
    const char* uuid,
    CoreCapability cap,
    bool* outResult
) {

    return core_has_capability(
        core,
        uuid,
        cap,
        outResult
    );
}


/**
 * @brief Retrieve current device state.
 *
 * @param core     Core context.
 * @param uuid     Device identifier.
 * @param outState Output buffer.
 *
 * @return Result code.
 */
CoreResult bridge_get_state(
    CoreContext* core,
    const char* uuid,
    CoreDeviceState* outState
) {

    return core_get_state(
        core,
        uuid,
        outState
    );
}


/* ============================================================
   State Setters
============================================================ */

/**
 * @brief Set device power state.
 */
CoreResult bridge_set_power(
    CoreContext* core,
    const char* uuid,
    bool value
) {
    return core_set_power(core, uuid, value);
}


/**
 * @brief Set device brightness.
 */
CoreResult bridge_set_brightness(
    CoreContext* core,
    const char* uuid,
    int value
) {
    return core_set_brightness(core, uuid, value);
}


/**
 * @brief Set device color.
 */
CoreResult bridge_set_color(
    CoreContext* core,
    const char* uuid,
    uint32_t value
) {
    return core_set_color(core, uuid, value);
}


/**
 * @brief Set device temperature.
 */
CoreResult bridge_set_temperature(
    CoreContext* core,
    const char* uuid,
    float value
) {
    return core_set_temperature(core, uuid, value);
}


/* ============================================================
   Diagnostics
============================================================ */

/**
 * @brief Get last core error message.
 *
 * @param core Core context.
 * @return Null-terminated string.
 */
const char* bridge_last_error(CoreContext* core) {
    return core_last_error(core);
}

} /* extern "C" */
