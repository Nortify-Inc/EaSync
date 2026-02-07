/**
 * @file driver.cpp
 * @brief Driver registry and dispatcher.
 */

#include "driver.hpp"

#include <unordered_map>
#include <memory>
#include <mutex>


namespace Easync {

/* ============================================================
   Driver Registry
============================================================ */

static std::mutex gDriverMutex;

static std::unordered_map<
    CoreProtocol,
    std::unique_ptr<EaSync::Driver>
> gDrivers;


/* ============================================================
   Registration
============================================================ */

/**
 * @brief Register protocol driver.
 */
bool registerDriver(
    CoreProtocol protocol,
    std::unique_ptr<EaSync::Driver> driver
) {

    if (!driver)
        return false;

    std::lock_guard<std::mutex> lock(gDriverMutex);

    gDrivers[protocol] = std::move(driver);

    return true;
}


/**
 * @brief Get driver by protocol.
 */
EaSync::Driver* getDriver(
    CoreProtocol protocol
) {

    std::lock_guard<std::mutex> lock(gDriverMutex);

    auto it = gDrivers.find(protocol);

    if (it == gDrivers.end())
        return nullptr;

    return it->second.get();
}

} // namespace Coreync
