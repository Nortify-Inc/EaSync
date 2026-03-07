// @file intentClassifier.cpp
// @brief Classificador rápido de intenção.
#include <string>
#include <vector>

class IntentClassifier {
public:
    IntentClassifier();
    std::string classify(const std::string& input);
};

IntentClassifier::IntentClassifier() {}
std::string IntentClassifier::classify(const std::string& input) {
    // ...classificação...
    return "device_control";
}
