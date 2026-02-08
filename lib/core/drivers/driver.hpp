#pragma once

#include <string>
#include <cstdint>
#include <core.h>

/**
 * @file driver.hpp
 * @brief Base interface for device drivers.
 *
 * All protocol drivers must implement this interface.
 */

namespace drivers {

/**
 * @brief Abstract device driver.
 *
 * Drivers are responsible for communicating
 * with physical or remote devices.
 */
class Driver {
public:

    virtual ~Driver() = default;


    /**
     * @brief Initialize driver.
     *
     * @return true on success.
     */
    virtual bool init() = 0;


    /**
     * @brief Connect to device.
     *
     * @param uuid Device id.
     * @return true on success.
     */
    virtual bool connect(
        const std::string& uuid
    ) = 0;


    /**
     * @brief Disconnect device.
     */
    virtual bool disconnect(
        const std::string& uuid
    ) = 0;


    /**
     * @brief Set power.
     */
    virtual bool setPower(
        const std::string& uuid,
        bool value
    ) = 0;


    /**
     * @brief Set brightness.
     */
    virtual bool setBrightness(
        const std::string& uuid,
        int value
    ) = 0;


    /**
     * @brief Set color.
     */
    virtual bool setColor(
        const std::string& uuid,
        uint32_t rgb
    ) = 0;


    /**
     * @brief Set temperature.
     */
    virtual bool setTemperature(
        const std::string& uuid,
        float value
    ) = 0;


    /**
     * @brief Read device state.
     */
    virtual bool getState(
        const std::string& uuid,
        CoreDeviceState& outState
    ) = 0;


    /**
     * @brief 
     * 
     * @param core core context runtime
     * @return boolean for driver is available to use.
     */
    virtual bool isAvailable(
        const std::string& uuid
    ) = 0;
};

} // namespace drivers
