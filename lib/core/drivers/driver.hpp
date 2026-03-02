#pragma once

/**
 * @file driver.hpp
 * @brief Base interface for EaSync Core device drivers.
 * @param uuid Unique device identifier used by driver operations.
 * @return Driver operation methods return true on success and false on failure.
 * @author Erick Radmann
 */

#include <string>
#include <cstdint>
#include <core.h>

using DriverEventCallback = void(*)(const std::string& uuid,
                                    const CoreDeviceState& state,
                                    void* userdata);

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
     * @brief Provision Wi-Fi credentials to a device (optional).
     *
     * Drivers that do not use Wi-Fi can keep the default behavior.
     */
    virtual bool provisionWifi(
        const std::string& uuid,
        const std::string& ssid,
        const std::string& password
    ) {
        (void)uuid;
        (void)ssid;
        (void)password;
        return false;
    }

    /**
     * @brief Optional lifecycle hook called when a device is registered.
     *
     * Drivers can use brand/model hints to configure transport endpoints.
     */
    virtual void onDeviceRegistered(
        const std::string& uuid,
        const std::string& brand,
        const std::string& model
    ) {
        (void)uuid;
        (void)brand;
        (void)model;
    }

    /**
     * @brief Optional lifecycle hook called when a device is removed.
     */
    virtual void onDeviceRemoved(const std::string& uuid) {
        (void)uuid;
    }


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
        uint32_t value
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
     * @brief Set temperature for fridge.
     */
    virtual bool setTemperatureFridge(
        const std::string& uuid,
        float value
    ) = 0;



    /**
     * @brief Set temperature for freezer.
     */
    virtual bool setTemperatureFreezer(
        const std::string& uuid,
        float value
    ) = 0;


    /**
     * @brief Set timestamp
     */
    virtual bool setTime(
        const std::string& uuid,
        uint64_t value
    ) = 0;


    /**
     * @brief Set color temperature.
     */
    virtual bool setColorTemperature(
        const std::string& uuid,
        uint32_t value
    ) = 0;  


    /**
     * @brief Set lock state.
     */
    virtual bool setLock(
        const std::string& uuid,
        bool value
    ) = 0;


    /**
    * @brief Set mode state.
    */  
    virtual bool setMode(
        const std::string& uuid,
        uint32_t value
    ) = 0;  


    /**
    * @brief Set position state.
    */  
    virtual bool setPosition(
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

    /**
     * @brief Register event callback.
     */
    virtual void setEventCallback(
        DriverEventCallback cb,
        void* userdata
    ) = 0;

};

} // namespace drivers