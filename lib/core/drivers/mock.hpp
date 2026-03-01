#pragma once

/**
 * @file mock.hpp
 * @brief Declaration of the simulated driver used for EaSync device testing.
 * @param uuid Identifier of the device managed by the mock driver.
 * @return Control methods return true when the operation is applied.
 * @author Erick Radmann
 */

#include "driver.hpp"

#include <unordered_map>
#include <atomic>
#include <mutex>
#include <thread>
#include <string>

namespace drivers {

class MockDriver : public Driver {
public:
    MockDriver() = default;
    ~MockDriver() override;

    bool init() override;

    bool connect(const std::string& uuid) override;
    bool disconnect(const std::string& uuid) override;

    bool setPower(const std::string& uuid, bool value) override;
    bool setBrightness(const std::string& uuid, uint32_t value) override;
    bool setColor(const std::string& uuid, uint32_t rgb) override;
    bool setTemperature(const std::string& uuid, float value) override;
    bool setTemperatureFridge(const std::string& uuid, float value) override;
    bool setTemperatureFreezer(const std::string& uuid, float value) override;
    bool setTime(const std::string& uuid, uint64_t value) override;
    bool setColorTemperature(const std::string& uuid, uint32_t value) override;
    bool setLock(const std::string& uuid, bool value) override;
    bool setMode(const std::string& uuid, uint32_t value) override;
    bool setPosition(const std::string& uuid, float value) override;
    
    bool getState(const std::string& uuid, CoreDeviceState& outState) override;
    bool isAvailable(const std::string& uuid) override;

    void setEventCallback(
        DriverEventCallback cb,
        void* userData
    ) override;

    void simulateExternalStateChange(
        const std::string& uuid,
        const CoreDeviceState& newState
    );

private:
    void startSimulation();
    void stopSimulation();
    void simulationLoop();

    void notifyStateChange(
        const std::string& uuid,
        const CoreDeviceState& newState
    );

private:
    std::mutex mutex;
    std::unordered_map<std::string, CoreDeviceState> states;

    std::atomic<bool> running{false};
    std::thread simulationThread;

    DriverEventCallback eventCallback = nullptr;
    void* eventUserData = nullptr;
};

}