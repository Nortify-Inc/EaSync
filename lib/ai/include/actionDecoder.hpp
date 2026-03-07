/**
 * @file actionDecoder.hpp
 * @author Radmann
 * @brief Action decoder for parsing, validating, and converting structured actions.
 *
 * Supports advanced parsing, validation, device integration, token conversion, and configuration.
 */
#pragma once
#include <vector>
#include <string>
#include <math.h>

/**
 * @class ActionDecoder
 * @brief Decodes, validates, and parses action tokens for device control.
 */
class ActionDecoder {
public:
    /**
     * @brief Constructor for ActionDecoder.
     */
    ActionDecoder();

    /**
     * @brief Decodes a token sequence to a structured action string.
     * @param tokens Token sequence.
     * @return Decoded action string.
     */
    std::string decode(const std::vector<int>& tokens);

    /**
     * @brief Decodes a single token to string.
     * @param tokenId Token identifier.
     * @return Decoded token string.
     */
    std::string decodeToken(int tokenId);

    /**
     * @brief Converts command token to string.
     * @param commandId Command token.
     * @return Command string.
     */
    std::string commandToString(int commandId);

    /**
     * @brief Decodes attention output tensor to token sequence.
     * @param attnOut Attention output tensor.
     * @return Token sequence.
     */
    std::vector<int> decodeTokens(const std::vector<float>& attnOut);

    /**
     * @brief Validates decoded action string for compatibility.
     * @param actionStr Decoded action string.
     * @return True if valid, false otherwise.
     */
    bool validateAction(const std::string& actionStr);

    /**
     * @brief Parses action string to device, command, and value.
     * @param actionStr Decoded action string.
     * @param device Output device string.
     * @param command Output command string.
     * @param value Output value integer.
     * @return True if parsing succeeded, false otherwise.
     */
    bool parseAction(const std::string& actionStr,
                    std::string& device,
                    std::string& command,
                    int& value);

    /**
     * @brief Configures supported device types.
     * @param deviceTypes List of device types.
     */
    void configure(const std::vector<std::string>& deviceTypes);

private:
    std::vector<std::string> deviceTypes;
};
