#include "chatModelRuntime.hpp"

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <filesystem>
#include <mutex>
#include <sstream>

namespace easync::ai {

namespace {

std::mutex contextMutex;
std::deque<std::string> recentTurns;
constexpr size_t maxRecentTurns = 6;

std::string trimCopy(std::string value) {
    value.erase(value.begin(), std::find_if(value.begin(), value.end(), [](unsigned char c) {
        return !std::isspace(c);
    }));
    value.erase(std::find_if(value.rbegin(), value.rend(), [](unsigned char c) {
        return !std::isspace(c);
    }).base(), value.end());
    return value;
}

std::string shellEscape(const std::string& input) {
    std::string out;
    out.reserve(input.size() + 8);
    out.push_back('\'');
    for (char c : input) {
        if (c == '\'') {
            out += "'\"'\"'";
        } else {
            out.push_back(c);
        }
    }
    out.push_back('\'');
    return out;
}

std::filesystem::path resolveScriptPath() {
    if (const char* env = std::getenv("EASYNC_CHAT_INFER_SCRIPT"); env && *env) {
        std::filesystem::path p(env);
        if (std::filesystem::exists(p)) {
            return p;
        }
    }

    const auto cwd = std::filesystem::current_path();
    const std::array<std::filesystem::path, 6> candidates = {
        cwd / "lib/ai/models/chatInferenceCli.py",
        cwd / "../lib/ai/models/chatInferenceCli.py",
        cwd / "../../lib/ai/models/chatInferenceCli.py",
        cwd / "../../../lib/ai/models/chatInferenceCli.py",
        cwd / "../easync/lib/ai/models/chatInferenceCli.py",
        cwd / "ai/models/chatInferenceCli.py",
    };

    for (const auto& c : candidates) {
        if (std::filesystem::exists(c)) {
            return c;
        }
    }

    return {};
}

std::string resolvePythonExecutable() {
    if (const char* env = std::getenv("EASYNC_CHAT_INFER_PYTHON"); env && *env) {
        return std::string(env);
    }

    const std::array<const char*, 3> candidates = {
        "/usr/bin/python3",
        "python3",
        "python",
    };

    for (const char* c : candidates) {
        if (std::string(c).find('/') != std::string::npos) {
            if (std::filesystem::exists(c)) {
                return std::string(c);
            }
            continue;
        }
        return std::string(c);
    }

    return "python3";
}

void parseLine(const std::string& line, ChatModelPrediction& out) {
    const auto pos = line.find('=');
    if (pos == std::string::npos) {
        return;
    }

    const std::string key = trimCopy(line.substr(0, pos));
    const std::string value = trimCopy(line.substr(pos + 1));

    if (key == "INTENT") {
        out.intent = value.empty() ? "unknown" : value;
    } else if (key == "STYLE") {
        out.responseStyle = value.empty() ? "minimalist" : value;
    } else if (key == "CAPABILITY") {
        out.predictedCapability = value.empty() ? "none" : value;
    } else if (key == "OPERATION") {
        out.predictedOperation = value.empty() ? "none" : value;
    } else if (key == "NUMERIC") {
        try {
            out.numericValue = value.empty() ? -1 : std::stoi(value);
        } catch (...) {
            out.numericValue = -1;
        }
    } else if (key == "RESPONSE") {
        out.generatedResponse = value;
    } else if (key == "CLARIFY") {
        std::string v = value;
        std::transform(v.begin(), v.end(), v.begin(), [](unsigned char c) {
            return static_cast<char>(std::tolower(c));
        });
        out.needsClarification = (v == "1" || v == "true" || v == "yes");
    } else if (key == "CONFIDENCE") {
        try {
            out.intentConfidence = value.empty() ? 0.0f : std::stof(value);
        } catch (...) {
            out.intentConfidence = 0.0f;
        }
    } else if (key == "TIME") {
        out.time = value;
    } else if (key == "HEX") {
        out.hexColor = value;
    }
}

} // namespace

bool runChatModelPrediction(const std::string& input, ChatModelPrediction& out) {
    const auto script = resolveScriptPath();
    if (script.empty()) {
        return false;
    }

    const std::string pythonExe = resolvePythonExecutable();

    std::string contextualInput;
    {
        std::lock_guard<std::mutex> lock(contextMutex);
        std::ostringstream oss;
        for (const auto& turn : recentTurns) {
            oss << turn << " ";
        }
        oss << input;
        contextualInput = oss.str();
    }

    const std::string cmd =
        shellEscape(pythonExe) + " " + shellEscape(script.string()) +
        " --text " + shellEscape(contextualInput) +
        " 2>/dev/null";

    std::array<char, 512> buffer{};
    std::string captured;

    FILE* pipe = popen(cmd.c_str(), "r");
    if (!pipe) {
        return false;
    }

    while (fgets(buffer.data(), static_cast<int>(buffer.size()), pipe) != nullptr) {
        captured += buffer.data();
    }

    const int rc = pclose(pipe);
    if (rc != 0 || captured.empty()) {
        return false;
    }

    std::stringstream ss(captured);
    std::string line;
    while (std::getline(ss, line)) {
        parseLine(line, out);
    }

    {
        std::lock_guard<std::mutex> lock(contextMutex);
        recentTurns.push_back(input);
        while (recentTurns.size() > maxRecentTurns) {
            recentTurns.pop_front();
        }
    }

    return true;
}

} // namespace easync::ai
