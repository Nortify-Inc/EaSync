/*
 * @file contextEncoder.hpp
 * @author Radmann
 * @brief Context encoder for sensor and home state tokens.
 *
 * Supports advanced encoding, sensor integration, special tokens, and configuration.
 *
 * Methods:
 *   ContextEncoder() - Constructor.
 *   std::vector<int> encode(...) - Encodes sensor states.
 *   std::string encodeToken(...) - Encodes a sensor token.
 *   void configure(...) - Configures sensor types.
 *   void addSpecialToken(...) - Adds special token.
 *
 * Attributes:
 *   std::vector<std::string> sensorTypes - Supported sensor types.
 *   std::vector<std::string> specialTokens - Special tokens for context.
 */
#pragma once
#include <string>
#include <vector>

class ContextEncoder {
public:
    ContextEncoder();
    std::vector<int> encode(const std::vector<std::string>& sensorStates);
    std::string encodeToken(const std::string& sensor, const std::string& value);
    void configure(const std::vector<std::string>& sensorTypes);
    void addSpecialToken(const std::string& token);
    std::vector<std::string> sensorTypes; ///< Supported sensor types (public for access)
private:
    std::vector<std::string> specialTokens;
};
