/*
 * @file actionDecoder.hpp
 * @author Radmann
 * @brief Action decoder for parsing and validating structured actions.
 *
 * Supports advanced parsing, validation, device integration, and configuration.
 *
 * Methods:
 *   ActionDecoder() - Constructor.
 *   std::string decode(const std::vector<int>& tokens) - Decodes action tokens.
 *   std::string decodeToken(int tokenId) - Decodes a single token.
 *   bool validate(const std::string& action) - Validates action.
 *   void configure(const std::vector<std::string>& deviceTypes) - Configures device types.
 *
 * Attributes:
 *   std::vector<std::string> deviceTypes - Supported device types.
 */
#pragma once
#include <vector>
#include <string>

class ActionDecoder {
public:
    ActionDecoder();
    std::string decode(const std::vector<int>& tokens);
    std::string decodeToken(int tokenId);
    bool validate(const std::string& action);
    void configure(const std::vector<std::string>& deviceTypes);
private:
    std::vector<std::string> deviceTypes;
};
