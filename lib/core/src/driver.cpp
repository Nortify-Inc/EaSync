/**
 * @file driver.cpp
 * @brief Driver registry and dispatcher.
 * @param protocol Communication protocol used as the registration key.
 * @return Returns the found driver pointer or a boolean registration status.
 * @author Erick Radmann
 */

#include "driver.hpp"

#include <unordered_map>
#include <memory>
#include <mutex>


namespace drivers {

static std::mutex gDriverMutex;

static std::unordered_map<
    CoreProtocol,
    std::unique_ptr<drivers::Driver>
> gDrivers;

/**
 * @brief Register protocol driver.
 */
bool registerDriver(
    CoreProtocol protocol,
    std::unique_ptr<drivers::Driver> driver
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
drivers::Driver* getDriver(
    CoreProtocol protocol
) {

    std::lock_guard<std::mutex> lock(gDriverMutex);

    auto it = gDrivers.find(protocol);

    if (it == gDrivers.end())
        return nullptr;

    return it->second.get();
}

} // namespace Coreync
