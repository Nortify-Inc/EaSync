#include "aiEngine.hpp"

#include <algorithm>
#include <cmath>
#include <cctype>
#include <sstream>
#include <chrono>

namespace easync::ai {

void AiEngine::setPermissions(const Permissions& permissions) {
    permissions_ = permissions;
}

Permissions AiEngine::permissions() const {
    return permissions_;
}

std::string AiEngine::normalize(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return value;
}

int AiEngine::hourFromTimestamp(uint64_t timestampMs) {
    const std::time_t ts = static_cast<std::time_t>(timestampMs / 1000ULL);
    std::tm tm{};
#if defined(_WIN32)
    localtime_s(&tm, &ts);
#else
    localtime_r(&ts, &tm);
#endif
    return std::clamp(tm.tm_hour, 0, 23);
}

std::string AiEngine::join(const std::vector<std::string>& items, const char* sep) {
    std::ostringstream oss;
    for (size_t i = 0; i < items.size(); ++i) {
        if (i > 0) {
            oss << sep;
        }
        oss << items[i];
    }
    return oss.str();
}

void AiEngine::pushEvent(BehaviorEventType type,
                         int hour,
                         uint64_t timestampMs,
                         const std::string& label) {
    memory_.push_back({type, std::clamp(hour, 0, 23), timestampMs, label});
    while (memory_.size() > maxMemory) {
        memory_.pop_front();
    }
}

bool AiEngine::hasCapability(const DeviceSnapshot& device, CoreCapability capability) const {
    for (auto cap : device.capabilities) {
        if (cap == capability) {
            return true;
        }
    }
    return false;
}

const DeviceSnapshot* AiEngine::findByName(const std::string& text,
                                           const std::vector<DeviceSnapshot>& devices) const {
    for (const auto& d : devices) {
        if (!d.name.empty() && text.find(normalize(d.name)) != std::string::npos) {
            return &d;
        }
    }
    return nullptr;
}

int AiEngine::strongestHour(const std::array<int, 24>& values,
                            int startHour,
                            int endHour) const {
    auto inRange = [&](int h) {
        if (startHour <= endHour) {
            return h >= startHour && h <= endHour;
        }
        return h >= startHour || h <= endHour;
    };

    int bestHour = -1;
    int bestValue = 0;
    for (int h = 0; h < 24; ++h) {
        if (!inRange(h)) {
            continue;
        }
        if (values[h] > bestValue) {
            bestValue = values[h];
            bestHour = h;
        }
    }
    return bestHour;
}

void AiEngine::observeAppOpen(uint64_t timestampMs) {
    const int h = hourFromTimestamp(timestampMs);
    appOpenByHour_[h]++;
    pushEvent(BehaviorEventType::appOpen, h, timestampMs, "app");
}

void AiEngine::observeProfileApply(const std::string& profileName, uint64_t timestampMs) {
    const int h = hourFromTimestamp(timestampMs);
    profileApplyByHour_[h]++;
    const std::string normalized = normalize(profileName);
    if (!normalized.empty()) {
        profileApplyCount_[normalized]++;
    }
    pushEvent(BehaviorEventType::profileApply, h, timestampMs, normalized);
}

void AiEngine::observeCommand(const std::string& input, uint64_t timestampMs) {
    pushEvent(BehaviorEventType::command, hourFromTimestamp(timestampMs), timestampMs, normalize(input));
}

void AiEngine::recordPattern(const std::string& uuid,
                             const CoreDeviceState& previous,
                             const CoreDeviceState& next,
                             bool enabled,
                             uint64_t timestampMs) {
    if (!enabled || uuid.empty()) {
        return;
    }

    bool changed = previous.power != next.power;
    if (!previous.power && next.power) {
        const int h = hourFromTimestamp(timestampMs);
        powerOnByHour_[h]++;
        pushEvent(BehaviorEventType::powerOn, h, timestampMs, uuid);
    }

    if (previous.brightness != next.brightness) {
        changed = true;
        brightnessSum_ += static_cast<double>(next.brightness);
        brightnessCount_++;
    }

    if (std::abs(previous.temperature - next.temperature) >= 0.3f) {
        changed = true;
        tempSum_ += static_cast<double>(next.temperature);
        tempCount_++;
    }

    if (std::abs(previous.position - next.position) >= 1.0f) {
        changed = true;
        positionSum_ += static_cast<double>(next.position);
        positionCount_++;
    }

    if (!changed) {
        return;
    }

    activityByDevice_[uuid] = activityByDevice_[uuid] + 1;
    pushEvent(BehaviorEventType::stateChange, hourFromTimestamp(timestampMs), timestampMs, uuid);
}

std::string AiEngine::processChat(const std::string& input,
                                  const std::vector<DeviceSnapshot>& devices) const {
    const std::string q = normalize(input);

    if (q.find("list") != std::string::npos || q.find("devices") != std::string::npos ||
        q.find("dispositivos") != std::string::npos) {
        std::vector<std::string> names;
        names.reserve(devices.size());
        for (const auto& d : devices) {
            names.push_back(d.name);
        }
        return std::string("devices:") + join(names, "|");
    }

    if (q.find("online") != std::string::npos) {
        std::vector<std::string> names;
        for (const auto& d : devices) {
            if (d.online) {
                names.push_back(d.name);
            }
        }
        return std::string("online:") + join(names, "|");
    }

    const DeviceSnapshot* target = findByName(q, devices);
    if (!target) {
        return "";
    }

    if (q.find("temperature") != std::string::npos || q.find("temperatura") != std::string::npos ||
        q.find("temp") != std::string::npos) {
        std::ostringstream oss;
        if (hasCapability(*target, CORE_CAP_TEMPERATURE)) {
            oss << "state:" << target->name << ";temperature=" << target->state.temperature;
            return oss.str();
        }
        if (hasCapability(*target, CORE_CAP_TEMPERATURE_FRIDGE)) {
            oss << "state:" << target->name << ";temperatureFridge=" << target->state.temperatureFridge;
            return oss.str();
        }
        if (hasCapability(*target, CORE_CAP_TEMPERATURE_FREEZER)) {
            oss << "state:" << target->name << ";temperatureFreezer=" << target->state.temperatureFreezer;
            return oss.str();
        }
    }

    if (q.find("brightness") != std::string::npos || q.find("brilho") != std::string::npos) {
        std::ostringstream oss;
        oss << "state:" << target->name << ";brightness=" << target->state.brightness;
        return oss.str();
    }

    if (q.find("position") != std::string::npos || q.find("posicao") != std::string::npos ||
        q.find("open") != std::string::npos || q.find("close") != std::string::npos) {
        std::ostringstream oss;
        oss << "state:" << target->name << ";position=" << target->state.position;
        return oss.str();
    }

    if (q.find("lock") != std::string::npos || q.find("unlock") != std::string::npos ||
        q.find("fechadura") != std::string::npos || q.find("tranca") != std::string::npos) {
        std::ostringstream oss;
        oss << "state:" << target->name << ";lock=" << (target->state.lock ? 1 : 0);
        return oss.str();
    }

    if (q.find("mode") != std::string::npos || q.find("modo") != std::string::npos) {
        std::ostringstream oss;
        oss << "state:" << target->name << ";mode=" << target->state.mode;
        return oss.str();
    }

    if (q.find("status") != std::string::npos || q.find("estado") != std::string::npos) {
        std::ostringstream oss;
        oss << "state:" << target->name
            << ";power=" << (target->state.power ? 1 : 0)
            << ";brightness=" << target->state.brightness
            << ";temperature=" << target->state.temperature
            << ";position=" << target->state.position
            << ";mode=" << target->state.mode
            << ";lock=" << (target->state.lock ? 1 : 0);
        return oss.str();
    }

    return "";
}

std::string AiEngine::learningSnapshot() const {
    std::ostringstream oss;
    const int arrival = strongestHour(powerOnByHour_, 17, 23);
    const int wake = strongestHour(appOpenByHour_, 5, 11);
    oss << "learning:";
    if (arrival >= 0) {
        oss << "arrivalHour=" << arrival << ";";
    }
    if (wake >= 0) {
        oss << "wakeHour=" << wake << ";";
    }
    if (tempCount_ > 0) {
        oss << "preferredTemp=" << (tempSum_ / static_cast<double>(tempCount_)) << ";";
    }
    if (brightnessCount_ > 0) {
        oss << "preferredBrightness=" << (brightnessSum_ / static_cast<double>(brightnessCount_)) << ";";
    }
    if (positionCount_ > 0) {
        oss << "preferredPosition=" << (positionSum_ / static_cast<double>(positionCount_)) << ";";
    }
    return oss.str();
}

std::vector<std::string> AiEngine::annotations(size_t maxItems) const {
    std::vector<std::string> out;

    const int arrival = strongestHour(powerOnByHour_, 17, 23);
    const int wake = strongestHour(appOpenByHour_, 5, 11);

    if (arrival >= 0) {
        out.push_back("arrivalHour=" + std::to_string(arrival));
    }
    if (wake >= 0) {
        out.push_back("wakeHour=" + std::to_string(wake));
    }
    if (tempCount_ > 0) {
        out.push_back("preferredTemp=" + std::to_string(tempSum_ / static_cast<double>(tempCount_)));
    }
    if (brightnessCount_ > 0) {
        out.push_back("preferredBrightness=" + std::to_string(brightnessSum_ / static_cast<double>(brightnessCount_)));
    }

    if (out.size() > maxItems) {
        out.resize(maxItems);
    }

    return out;
}

} // namespace easync::ai
