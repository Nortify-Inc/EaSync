/**
 * @file payload_utility.cpp
 * @brief Implements payload template loading and payload assembly from JSON files.
 * @param capability Capability key looked up in each template payload map.
 * @return Payload JSON strings with placeholders resolved.
 * @author Erick Radmann
 */

#include "payload_utility.hpp"

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <sstream>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace {

struct DeviceProfile {
    std::string brand;
    std::string model;
};

struct PayloadTemplate {
    std::string topic;
    std::string payloadTemplate;
};

std::mutex gMutex;
bool gLoaded = false;
std::unordered_map<std::string, DeviceProfile> gDeviceProfiles;
std::unordered_map<std::string, PayloadTemplate> gTemplates;
std::unordered_map<std::string, std::vector<std::string>> gModeOptions;

std::string toLower(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return value;
}

std::string trim(std::string value) {
    while (!value.empty() && std::isspace(static_cast<unsigned char>(value.front())))
        value.erase(value.begin());

    while (!value.empty() && std::isspace(static_cast<unsigned char>(value.back())))
        value.pop_back();

    return value;
}

std::string normalize(const std::string& value) {
    return toLower(trim(value));
}

size_t findStringEnd(const std::string& text, size_t quoteStart) {
    bool escaped = false;
    for (size_t i = quoteStart + 1; i < text.size(); ++i) {
        char ch = text[i];
        if (escaped) {
            escaped = false;
            continue;
        }
        if (ch == '\\') {
            escaped = true;
            continue;
        }
        if (ch == '"')
            return i;
    }
    return std::string::npos;
}

size_t findMatching(const std::string& text, size_t start, char openChar, char closeChar) {
    if (start >= text.size() || text[start] != openChar)
        return std::string::npos;

    int depth = 0;
    bool inString = false;
    bool escaped = false;

    for (size_t i = start; i < text.size(); ++i) {
        char ch = text[i];

        if (inString) {
            if (escaped) {
                escaped = false;
            } else if (ch == '\\') {
                escaped = true;
            } else if (ch == '"') {
                inString = false;
            }
            continue;
        }

        if (ch == '"') {
            inString = true;
            continue;
        }

        if (ch == openChar)
            depth++;
        else if (ch == closeChar) {
            depth--;
            if (depth == 0)
                return i;
        }
    }

    return std::string::npos;
}

std::string extractFieldString(const std::string& objectText, const std::string& fieldName) {
    std::string key = "\"" + fieldName + "\"";
    size_t keyPos = objectText.find(key);
    if (keyPos == std::string::npos)
        return "";

    size_t colonPos = objectText.find(':', keyPos + key.size());
    if (colonPos == std::string::npos)
        return "";

    size_t quoteStart = objectText.find('"', colonPos + 1);
    if (quoteStart == std::string::npos)
        return "";

    size_t quoteEnd = findStringEnd(objectText, quoteStart);
    if (quoteEnd == std::string::npos)
        return "";

    return objectText.substr(quoteStart + 1, quoteEnd - quoteStart - 1);
}

std::string extractFieldObject(const std::string& objectText, const std::string& fieldName) {
    std::string key = "\"" + fieldName + "\"";
    size_t keyPos = objectText.find(key);
    if (keyPos == std::string::npos)
        return "";

    size_t colonPos = objectText.find(':', keyPos + key.size());
    if (colonPos == std::string::npos)
        return "";

    size_t braceStart = objectText.find('{', colonPos + 1);
    if (braceStart == std::string::npos)
        return "";

    size_t braceEnd = findMatching(objectText, braceStart, '{', '}');
    if (braceEnd == std::string::npos)
        return "";

    return objectText.substr(braceStart, braceEnd - braceStart + 1);
}

std::string extractFieldArray(const std::string& objectText, const std::string& fieldName) {
    std::string key = "\"" + fieldName + "\"";
    size_t keyPos = objectText.find(key);
    if (keyPos == std::string::npos)
        return "";

    size_t colonPos = objectText.find(':', keyPos + key.size());
    if (colonPos == std::string::npos)
        return "";

    size_t arrStart = objectText.find('[', colonPos + 1);
    if (arrStart == std::string::npos)
        return "";

    size_t arrEnd = findMatching(objectText, arrStart, '[', ']');
    if (arrEnd == std::string::npos)
        return "";

    return objectText.substr(arrStart, arrEnd - arrStart + 1);
}

std::vector<std::string> extractArrayStrings(const std::string& arrayText) {
    std::vector<std::string> out;
    if (arrayText.empty())
        return out;

    const size_t arrStart = arrayText.find('[');
    const size_t arrEnd = arrayText.rfind(']');
    if (arrStart == std::string::npos || arrEnd == std::string::npos || arrEnd <= arrStart)
        return out;

    size_t i = arrStart + 1;
    while (i < arrEnd) {
        const size_t quoteStart = arrayText.find('"', i);
        if (quoteStart == std::string::npos || quoteStart >= arrEnd)
            break;
        const size_t quoteEnd = findStringEnd(arrayText, quoteStart);
        if (quoteEnd == std::string::npos || quoteEnd > arrEnd)
            break;

        const std::string value = trim(arrayText.substr(quoteStart + 1, quoteEnd - quoteStart - 1));
        if (!value.empty()) {
            out.push_back(value);
        }

        i = quoteEnd + 1;
    }

    return out;
}

std::vector<std::string> extractArrayObjects(const std::string& jsonText) {
    std::vector<std::string> result;

    size_t arrStart = jsonText.find('[');
    if (arrStart == std::string::npos)
        return result;

    size_t arrEnd = findMatching(jsonText, arrStart, '[', ']');
    if (arrEnd == std::string::npos)
        return result;

    size_t i = arrStart + 1;
    while (i < arrEnd) {
        size_t objStart = jsonText.find('{', i);
        if (objStart == std::string::npos || objStart >= arrEnd)
            break;

        size_t objEnd = findMatching(jsonText, objStart, '{', '}');
        if (objEnd == std::string::npos || objEnd > arrEnd)
            break;

        result.emplace_back(jsonText.substr(objStart, objEnd - objStart + 1));
        i = objEnd + 1;
    }

    return result;
}

std::string readTextFile(const std::filesystem::path& filePath) {
    std::ifstream in(filePath);
    if (!in)
        return "";

    std::ostringstream ss;
    ss << in.rdbuf();
    return ss.str();
}

std::filesystem::path findAssetsDirectory() {
    std::vector<std::filesystem::path> candidates;

    if (const char* env = std::getenv("EASYNC_ASSETS_DIR")) {
        if (*env)
            candidates.emplace_back(env);
    }

    candidates.emplace_back("assets");
    candidates.emplace_back("./assets");
    candidates.emplace_back("../assets");
    candidates.emplace_back("../../assets");

    for (const auto& p : candidates) {
        if (std::filesystem::exists(p) && std::filesystem::is_directory(p))
            return p;
    }

    return {};
}

std::string makeTemplateKey(const std::string& brand,
                            const std::string& model,
                            const std::string& capability) {
    return normalize(brand) + "|" + normalize(model) + "|" + normalize(capability);
}

std::string makeDeviceKey(const std::string& brand,
                          const std::string& model) {
    return normalize(brand) + "|" + normalize(model);
}

void replaceAll(std::string& value, const std::string& from, const std::string& to) {
    if (from.empty())
        return;

    size_t startPos = 0;
    while ((startPos = value.find(from, startPos)) != std::string::npos) {
        value.replace(startPos, from.length(), to);
        startPos += to.length();
    }
}

void loadTemplatesLocked() {
    if (gLoaded)
        return;

    const std::array<std::string, 7> files = {
        "acs.json",
        "lamps.json",
        "fridges.json",
        "locks.json",
        "curtains.json",
        "heated_floors.json",
        "mocks.json"
    };

    std::filesystem::path assetsDir = findAssetsDirectory();
    if (assetsDir.empty()) {
        gLoaded = true;
        return;
    }

    for (const auto& fileName : files) {
        const auto filePath = assetsDir / fileName;
        std::string jsonText = readTextFile(filePath);
        if (jsonText.empty())
            continue;

        for (const auto& obj : extractArrayObjects(jsonText)) {
            std::string brand = extractFieldString(obj, "brand");
            std::string model = extractFieldString(obj, "model");
            std::string payloads = extractFieldObject(obj, "payloads");
            std::string constrains = extractFieldObject(obj, "constrains");

            if (model.empty() || payloads.empty())
                continue;

            const std::array<std::string, 11> capabilities = {
                "power",
                "brightness",
                "color",
                "temperature",
                "temperature_fridge",
                "temperature_freezer",
                "time",
                "colorTemperature",
                "lock",
                "mode",
                "position"
            };

            for (const auto& cap : capabilities) {
                std::string capObj = extractFieldObject(payloads, cap);
                if (capObj.empty())
                    continue;

                std::string tpl = extractFieldObject(capObj, "template");
                std::string topic = extractFieldString(capObj, "topic");
                if (tpl.empty() && topic.empty())
                    continue;

                PayloadTemplate entry;
                entry.topic = topic;
                entry.payloadTemplate = tpl;

                gTemplates[makeTemplateKey(brand, model, cap)] = entry;
            }

            if (!constrains.empty()) {
                const std::string modeArray = extractFieldArray(constrains, "mode");
                const auto modes = extractArrayStrings(modeArray);
                if (!modes.empty()) {
                    gModeOptions[makeDeviceKey(brand, model)] = modes;
                }
            }
        }
    }

    gLoaded = true;
}

PayloadTemplate findTemplateEntry(const std::string& brand,
                                  const std::string& model,
                                  const std::string& capability) {
    auto it = gTemplates.find(makeTemplateKey(brand, model, capability));
    if (it != gTemplates.end())
        return it->second;

    std::string capNorm = normalize(capability);
    std::string modelNorm = normalize(model);

    for (const auto& pair : gTemplates) {
        const std::string suffix = "|" + modelNorm + "|" + capNorm;
        if (pair.first.size() >= suffix.size() &&
            pair.first.compare(pair.first.size() - suffix.size(), suffix.size(), suffix) == 0)
        {
            return pair.second;
        }
    }

    return PayloadTemplate{};
}

std::vector<std::string> findModeOptionsEntry(const std::string& brand,
                                              const std::string& model) {
    auto it = gModeOptions.find(makeDeviceKey(brand, model));
    if (it != gModeOptions.end()) {
        return it->second;
    }

    const std::string modelNorm = normalize(model);
    const std::string suffix = "|" + modelNorm;
    for (const auto& pair : gModeOptions) {
        if (pair.first.size() >= suffix.size() &&
            pair.first.compare(pair.first.size() - suffix.size(), suffix.size(), suffix) == 0)
        {
            return pair.second;
        }
    }

    return {};
}

core::PayloadCommand resolveCommand(PayloadTemplate entry,
                                    const std::string& uuid,
                                    const std::string& valueJson) {
    if (entry.topic.empty() && entry.payloadTemplate.empty())
        return core::PayloadCommand{};

    replaceAll(entry.payloadTemplate, "\"{value}\"", valueJson);
    replaceAll(entry.payloadTemplate, "{value}", valueJson);

    replaceAll(entry.topic, "{uuid}", uuid);
    replaceAll(entry.topic, "\"{value}\"", valueJson);
    replaceAll(entry.topic, "{value}", valueJson);

    core::PayloadCommand out;
    out.topic = entry.topic;
    out.payload = entry.payloadTemplate;
    return out;
}

} // namespace

namespace core {

PayloadUtility& PayloadUtility::instance() {
    static PayloadUtility s;
    return s;
}

void PayloadUtility::ensureLoaded() {
    std::lock_guard<std::mutex> lock(gMutex);
    loadTemplatesLocked();
}

void PayloadUtility::bindDevice(const std::string& uuid,
                                const std::string& brand,
                                const std::string& model)
{
    std::lock_guard<std::mutex> lock(gMutex);
    gDeviceProfiles[uuid] = DeviceProfile{brand, model};
}

void PayloadUtility::unbindDevice(const std::string& uuid) {
    std::lock_guard<std::mutex> lock(gMutex);
    gDeviceProfiles.erase(uuid);
}

std::string PayloadUtility::createPayload(const std::string& brand,
                                          const std::string& model,
                                          const std::string& capability,
                                          const std::string& valueJson)
{
    return createCommand(brand, model, "", capability, valueJson).payload;
}

std::string PayloadUtility::createPayload(const std::string& uuid,
                                          const std::string& capability,
                                          const std::string& valueJson)
{
    return createCommand(uuid, capability, valueJson).payload;
}

PayloadCommand PayloadUtility::createCommand(const std::string& brand,
                                             const std::string& model,
                                             const std::string& uuid,
                                             const std::string& capability,
                                             const std::string& valueJson)
{
    ensureLoaded();

    std::lock_guard<std::mutex> lock(gMutex);

    PayloadTemplate entry = findTemplateEntry(brand, model, capability);
    return resolveCommand(entry, uuid, valueJson);
}

PayloadCommand PayloadUtility::createCommand(const std::string& uuid,
                                             const std::string& capability,
                                             const std::string& valueJson)
{
    ensureLoaded();

    std::lock_guard<std::mutex> lock(gMutex);

    auto it = gDeviceProfiles.find(uuid);
    if (it == gDeviceProfiles.end())
        return PayloadCommand{};

    PayloadTemplate entry = findTemplateEntry(
        it->second.brand,
        it->second.model,
        capability
    );

    return resolveCommand(entry, uuid, valueJson);
}

std::vector<std::string> PayloadUtility::modeOptions(const std::string& brand,
                                                     const std::string& model)
{
    ensureLoaded();

    std::lock_guard<std::mutex> lock(gMutex);
    return findModeOptionsEntry(brand, model);
}

std::vector<std::string> PayloadUtility::modeOptionsForDevice(const std::string& uuid)
{
    ensureLoaded();

    std::lock_guard<std::mutex> lock(gMutex);

    auto it = gDeviceProfiles.find(uuid);
    if (it == gDeviceProfiles.end()) {
        return {};
    }

    return findModeOptionsEntry(it->second.brand, it->second.model);
}

} // namespace core
