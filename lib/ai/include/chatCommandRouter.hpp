#pragma once

#include "chatModelRuntime.hpp"

#include <string>

namespace easync::ai {

bool predictionSuggestsAction(const ChatModelPrediction& prediction);
bool predictionSuggestsInformational(const ChatModelPrediction& prediction);
std::string augmentCommandFromPrediction(const std::string& input,
                                         const ChatModelPrediction& prediction);

} // namespace easync::ai
