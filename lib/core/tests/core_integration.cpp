#include <cassert>
#include <iostream>
#include <cstring>

#include "driver.hpp"
#include "mock.hpp"
#include <core.h>

static void onEvent(
    const CoreEvent* ev,
    void* userdata
) {
    if (!ev) return;

    switch (ev->type) {

        case CORE_EVENT_DEVICE_ADDED:
            std::cout << "[EVENT] Device added: "
                      << ev->uuid << "\n";
            break;

        case CORE_EVENT_STATE_CHANGED:
            std::cout << "[EVENT] State changed: "
                      << ev->uuid << "\n";
            break;

        case CORE_EVENT_ERROR:
            std::cout << "[EVENT] Error: "
                      << ev->errorCode << "\n";
            break;

        default:
            break;
    }
}

int main() {

    CoreContext* core = core_create();
    assert(core);

    CoreResult res;

    res = core_init(core);
    assert(res == CORE_OK);

    core_set_event_callback(core, onEvent, nullptr);

    /* Capabilities */

    CoreCapability caps[] = {
        CORE_CAP_POWER,
        CORE_CAP_BRIGHTNESS,
        CORE_CAP_COLOR
    };

    /* Register device */

    res = core_register_device(
        core,
        "lamp-001",
        "Desk Lamp",
        CORE_PROTOCOL_WIFI,
        caps,
        3
    );

    assert(res == CORE_OK);

    /* Get info */

    CoreDeviceInfo info;

    res = core_get_device(
        core,
        "lamp-001",
        &info
    );

    assert(res == CORE_OK);
    assert(std::strcmp(info.name, "Desk Lamp") == 0);

    /* Set power */

    res = core_set_power(core, "lamp-001", true);
    assert(res == CORE_OK);

    /* Set brightness */

    res = core_set_brightness(core, "lamp-001", 80);
    assert(res == CORE_OK);

    /* Read state */

    CoreDeviceState state;

    res = core_get_state(
        core,
        "lamp-001",
        &state
    );

    assert(res == CORE_OK);
    assert(state.power == true);
    assert(state.brightness == 80);

    /* Remove */

    res = core_remove_device(core, "lamp-001");
    assert(res == CORE_OK);

    core_destroy(core);

    std::cout << "\nALL TESTS PASSED\n";

    return 0;
}
