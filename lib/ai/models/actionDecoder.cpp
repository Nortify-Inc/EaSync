/**
 * @file actionDecoder.cpp
 * @author Radmann
 * @brief Implements action decoding and token-to-action conversion for the home assistant model.
 *
 * Provides advanced decoding, token-to-action conversion, validation, and compatibility with hybridModel and device routing.
 */
#include "../include/actionDecoder.hpp"
#include <sstream>
#include <map>
#include <algorithm>

/**
 * @brief Decodes a token sequence to a structured action string.
 *
 * @param tokens Token sequence.
 * @return Decoded action string (device|command|value).
 */
std::string ActionDecoder::decode(const std::vector<int>& tokens)
{
	if (tokens.empty()) return "";
	std::ostringstream oss;
	// Example: decode to device|command|value format
	int deviceId = tokens[0];
	int commandId = tokens.size() > 1 ? tokens[1] : 0;
	int value = tokens.size() > 2 ? tokens[2] : 0;
	oss << "device_" << deviceId << "|";
	oss << commandToString(commandId) << "|";
	oss << value;
	return oss.str();
}

/**
 * @brief Converts command token to string.
 *
 * @param commandId Command token.
 * @return Command string.
 */
std::string ActionDecoder::commandToString(int commandId)
{
	static const std::map<int, std::string> commandMap = {
		{1, "power_on"},
		{2, "power_off"},
		{3, "set_brightness"},
		{4, "set_color"},
		{5, "set_temperature"},
        {6, "set_fridge_temperature"},
        {7, "set_freezer_temperature"},
        {9, "set_time"},
		{10, "lock"},
		{11, "unlock"},
		{12, "set_mode"},
		{13, "set_position"},
		
	};
	auto it = commandMap.find(commandId);
	return it != commandMap.end() ? it->second : "unknown";
}

/**
 * @brief Decodes attention output tensor to token sequence.
 *
 * @param attnOut Attention output tensor.
 * @return Token sequence.
 */
std::vector<int> ActionDecoder::decodeTokens(const std::vector<float>& attnOut)
{
	std::vector<int> tokens;
	tokens.reserve(attnOut.size());
	for (float v : attnOut) tokens.push_back(static_cast<int>(std::lround(v)));
	return tokens;
}

/**
 * @brief Validates decoded action string for compatibility.
 *
 * @param actionStr Decoded action string.
 * @return True if valid, false otherwise.
 */
bool ActionDecoder::validateAction(const std::string& actionStr)
{
	// Example: check for device and command presence
	return actionStr.find("device_") == 0 && actionStr.find("|") != std::string::npos;
}

/**
 * @brief Converts action string to device, command, and value.
 *
 * @param actionStr Decoded action string.
 * @param device Output device string.
 * @param command Output command string.
 * @param value Output value integer.
 * @return True if parsing succeeded, false otherwise.
 */
bool ActionDecoder::parseAction(const std::string& actionStr,
								std::string& device,
								std::string& command,
								int& value)
{
	size_t first = actionStr.find('|');
	size_t second = actionStr.find('|', first + 1);
	if (first == std::string::npos || second == std::string::npos) return false;
	device = actionStr.substr(0, first);
	command = actionStr.substr(first + 1, second - first - 1);
	value = std::stoi(actionStr.substr(second + 1));
	return true;
}
