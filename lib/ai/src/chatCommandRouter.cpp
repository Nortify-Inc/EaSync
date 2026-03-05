#include "chatCommandRouter.hpp"

#include <algorithm>
#include <cctype>

namespace easync::ai {

namespace {

std::string lowerCopy(const std::string& input) {
    std::string out = input;
    std::transform(out.begin(), out.end(), out.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return out;
}

bool containsAny(const std::string& text, std::initializer_list<const char*> needles) {
    for (const char* needle : needles) {
        if (needle && text.find(needle) != std::string::npos) {
            return true;
        }
    }
    return false;
}

} // namespace

bool predictionSuggestsAction(const ChatModelPrediction& prediction) {
    if (prediction.intent == "controlDevice" || prediction.intent == "applyProfile") {
        return true;
    }

    if (prediction.predictedOperation != "none" && prediction.predictedCapability != "none") {
        return true;
    }

    if (prediction.numericValue >= 0 && prediction.predictedCapability != "none") {
        return true;
    }

    return false;
}

bool predictionSuggestsInformational(const ChatModelPrediction& prediction) {
    return prediction.intent == "listDevices" ||
           prediction.intent == "listOnline" ||
           prediction.intent == "queryStatus" ||
           prediction.intent == "outOfDomain" ||
           prediction.intent == "greeting" ||
           prediction.intent == "farewell" ||
           prediction.intent == "gratitude" ||
           prediction.intent == "smalltalk";
}

std::string augmentCommandFromPrediction(const std::string& input,
                                         const ChatModelPrediction& prediction) {
    std::string out = input;
    const std::string q = lowerCopy(input);

    if (prediction.predictedCapability == "brightness") {
        if (prediction.numericValue >= 0 && !containsAny(q, {"brightness", "brilho"})) {
            out += " brightness";
        }
    } else if (prediction.predictedCapability == "temperature" ||
               prediction.predictedCapability == "temperatureFridge" ||
               prediction.predictedCapability == "temperatureFreezer") {
        if (prediction.numericValue >= 0 && !containsAny(q, {"temperature", "temperatura", "temp", "fridge", "freezer", "geladeira", "congelador"})) {
            out += " temperature";
        }
    } else if (prediction.predictedCapability == "color") {
        if (!prediction.hexColor.empty() && !containsAny(q, {"color", "cor", "rgb", "#"})) {
            out += " color " + prediction.hexColor;
        }
    } else if (prediction.predictedCapability == "colorTemperature") {
        if (prediction.numericValue >= 0 && !containsAny(q, {"kelvin", "color temperature", "temperatura de cor"})) {
            out += " kelvin";
        }
    } else if (prediction.predictedCapability == "position") {
        if (!containsAny(q, {"position", "posicao", "open", "close", "abrir", "fechar"}) && prediction.numericValue >= 0) {
            out += " position";
        }
    } else if (prediction.predictedCapability == "lock") {
        if (!containsAny(q, {"lock", "unlock", "trancar", "destrancar", "fechadura", "tranca"})) {
            out += " lock";
        }
    } else if (prediction.predictedCapability == "power") {
        if (!containsAny(q, {"turn on", "turn off", "liga", "desliga", "power", "on", "off"})) {
            out = std::string("turn on ") + out;
        }
    }

    return out;
}

} // namespace easync::ai
