// Minimal AI engine public header for EaSync (stubs)
#pragma once

#include <string>

namespace easync {
namespace ai {

class AiEngine {
public:
    // Handle a generic JSON request and return a JSON response string.
    // Request format (stringified JSON):
    // { "type": "interaction"|"check"|"set", "payload": {...}, "meta": {...} }
    static std::string handleRequest(const std::string& jsonRequest);
};

} // namespace ai
} // namespace easync
