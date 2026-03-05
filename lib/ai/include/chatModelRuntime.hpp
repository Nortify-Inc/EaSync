#pragma once

#include <string>

namespace easync::ai {

struct ChatModelPrediction {
    std::string intent = "unknown";
    std::string responseStyle = "minimalist";
    std::string predictedCapability = "none";
    std::string predictedOperation = "none";
    std::string generatedResponse;
    bool needsClarification = false;
    float intentConfidence = 0.0f;
    int numericValue = -1;
    std::string time;
    std::string hexColor;
};

bool runChatModelPrediction(const std::string& input, ChatModelPrediction& out);

} // namespace easync::ai
