/*
 * @file toolRouter.hpp
 * @author Radmann
 * @brief Interface for device command execution and routing.
 *
 * Provides methods to execute, map, validate, and query device actions.
 * Supports configuration for device types and status retrieval.
 *
 * Methods:
 *   ToolRouter() - Constructor.
 *   std::string execute(const std::string& action) - Executes a device action command.
 *   std::string mapAction(const std::string& action) - Maps a natural language action to a device command.
 *   bool validate(const std::string& action) - Validates if the action is allowed for the device.
 *   void configure(const std::vector<std::string>& deviceTypes) - Configures supported device types.
 *   std::string getStatus(const std::string& device) - Retrieves the current status of a device.
 *
 * Attributes:
 *   std::vector<std::string> deviceTypes - List of supported device types for routing and validation.
 */
#pragma once
#include <string>
#include <vector>

class ToolRouter {
public:
    ToolRouter();
    std::string execute(const std::string& action);
    std::string mapAction(const std::string& action);
    bool validate(const std::string& action);
    void configure(const std::vector<std::string>& deviceTypes);
    std::string getStatus(const std::string& device);
private:
    std::vector<std::string> deviceTypes;
};
