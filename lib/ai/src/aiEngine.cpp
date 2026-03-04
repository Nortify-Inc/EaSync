#include "aiEngine.hpp"

#include <algorithm>
#include <cmath>
#include <cctype>
#include <chrono>
#include <ctime>
#include <sstream>

namespace easync::ai {

namespace {
uint64_t nowMs() {
    return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch())
        .count());
}
} // namespace

void AiEngine::setPermissions(const Permissions& permissions) {
    permissions_ = permissions;
}

Permissions AiEngine::permissions() const {
    return permissions_;
}

void AiEngine::observeAppOpen(uint64_t timestampMs) {
    const int h = hourFromTimestamp(timestampMs);
    appOpenByHour_[h]++;
    pushEvent(BehaviorEventType::AppOpen, h, timestampMs, "app_open");
}

void AiEngine::observeProfileApply(const std::string& profileName, uint64_t timestampMs) {
    const int h = hourFromTimestamp(timestampMs);
    profileApplyByHour_[h]++;

    const std::string normalized = normalize(profileName);
    if (!normalized.empty()) {
        profileApplyCount_[normalized]++;
    }

    pushEvent(BehaviorEventType::ProfileApply, h, timestampMs, normalized);
}

void AiEngine::observeCommand(const std::string& input, uint64_t timestampMs) {
    pushEvent(BehaviorEventType::Command,
              hourFromTimestamp(timestampMs),
              timestampMs,
              normalize(input));
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
        pushEvent(BehaviorEventType::PowerOn, h, timestampMs, uuid);
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
    pushEvent(BehaviorEventType::StateChange,
              hourFromTimestamp(timestampMs),
              timestampMs,
              uuid);
}

std::string AiEngine::processChat(const std::string& input,
                                  const std::vector<DeviceSnapshot>& devices) const {
    const std::string q = normalize(input);
    const bool asksTemperature = q.find("temperatura") != std::string::npos ||
                                 q.find("temperature") != std::string::npos ||
                                 q.find("tempeature") != std::string::npos ||
                                 q.find("temp") != std::string::npos ||
                                 q.find("thermo") != std::string::npos;

    if (q.empty()) {
        return "I can help with commands, device status, and behavior insights.";
    }

    if (q.find("hello") != std::string::npos || q.find("oi") != std::string::npos ||
        q.find("hi") != std::string::npos || q.find("ola") != std::string::npos ||
        q.find("olá") != std::string::npos) {
        return "Hello. I can control devices and share possible behavior insights.";
    }

    if (devices.empty()) {
        return "No devices are currently available.";
    }

    if (q.find("list") != std::string::npos || q.find("lista") != std::string::npos ||
        q.find("listar") != std::string::npos || q.find("devices") != std::string::npos ||
        q.find("device") != std::string::npos ||
        q.find("dispositivo") != std::string::npos || q.find("dispositivos") != std::string::npos) {
        std::ostringstream oss;
        oss << "Devices (" << devices.size() << "): ";
        for (size_t i = 0; i < devices.size(); ++i) {
            if (i > 0) {
                oss << ", ";
            }
            oss << devices[i].name;
        }
        return oss.str();
    }

    if (q.find("insight") != std::string::npos ||
        q.find("learn") != std::string::npos ||
        q.find("pattern") != std::string::npos ||
        q.find("annotation") != std::string::npos ||
        q.find("rotina") != std::string::npos) {
        return learningSnapshot();
    }

    if (q.find("online") != std::string::npos || q.find("ativos") != std::string::npos) {
        std::vector<std::string> online;
        for (const auto& d : devices) {
            if (d.online) {
                online.push_back(d.name);
            }
        }

        if (online.empty()) {
            return "No devices are currently online.";
        }

        std::ostringstream oss;
        oss << "Online devices (" << online.size() << "): ";
        for (size_t i = 0; i < online.size(); ++i) {
            if (i > 0) {
                oss << ", ";
            }
            oss << online[i];
        }
        return oss.str();
    }

    if (q.find("status") != std::string::npos || q.find("estado") != std::string::npos) {
        int onCount = 0;
        int onlineCount = 0;
        for (const auto& d : devices) {
            if (d.state.power) onCount++;
            if (d.online) onlineCount++;
        }
        std::ostringstream oss;
        oss << "Status summary: " << onCount << " of " << devices.size()
            << " devices are ON, and " << onlineCount << " are online.";
        return oss.str();
    }

    const DeviceSnapshot* target = findByName(q, devices);

    if (q.find("ligad") != std::string::npos || q.find("power") != std::string::npos ||
        q.find("on") != std::string::npos || q.find("off") != std::string::npos) {
        if (!target) {
            int onCount = 0;
            for (const auto& d : devices) {
                if (d.state.power) onCount++;
            }
            std::ostringstream oss;
            oss << onCount << " of " << devices.size() << " devices are ON.";
            return oss.str();
        }

        const bool isQuestion = q.find('?') != std::string::npos ||
                                q.find("is ") != std::string::npos ||
                                q.find("turned on") != std::string::npos ||
                                q.find("ligado") != std::string::npos ||
                                q.find("ligada") != std::string::npos;

        if (isQuestion) {
            if (target->state.power) {
                return "Yes. " + target->name + " is ON.";
            }
            return "No. " + target->name + " is OFF at this moment.";
        }

        return target->name + std::string(target->state.power ? " is ON." : " is OFF.");
    }

    if (asksTemperature && target && hasCapability(*target, CORE_CAP_TEMPERATURE)) {
        std::ostringstream oss;
        oss << target->name << " temperature is " << static_cast<int>(target->state.temperature) << "°C.";
        return oss.str();
    }

    if (asksTemperature && !target) {
        std::vector<std::string> rows;
        for (const auto& d : devices) {
            if (hasCapability(d, CORE_CAP_TEMPERATURE)) {
                rows.push_back(d.name + " " + std::to_string(static_cast<int>(d.state.temperature)) + "°C");
            }
        }
        if (!rows.empty()) {
            std::ostringstream oss;
            oss << "Temperature: ";
            for (size_t i = 0; i < rows.size(); ++i) {
                if (i > 0) oss << ", ";
                oss << rows[i];
            }
            return oss.str();
        }
    }

    if ((q.find("brilho") != std::string::npos || q.find("brightness") != std::string::npos) &&
        target && hasCapability(*target, CORE_CAP_BRIGHTNESS)) {
        std::ostringstream oss;
        oss << target->name << " brightness is " << target->state.brightness << "%";
        return oss.str();
    }

    if ((q.find("brilho") != std::string::npos || q.find("brightness") != std::string::npos) &&
        !target) {
        std::vector<std::string> rows;
        for (const auto& d : devices) {
            if (hasCapability(d, CORE_CAP_BRIGHTNESS)) {
                rows.push_back(d.name + " " + std::to_string(d.state.brightness) + "%");
            }
        }
        if (!rows.empty()) {
            std::ostringstream oss;
            oss << "Brightness: ";
            for (size_t i = 0; i < rows.size(); ++i) {
                if (i > 0) oss << ", ";
                oss << rows[i];
            }
            return oss.str();
        }
    }

    if ((q.find("posicao") != std::string::npos || q.find("position") != std::string::npos ||
         q.find("open") != std::string::npos || q.find("close") != std::string::npos) &&
        target && hasCapability(*target, CORE_CAP_POSITION)) {
        std::ostringstream oss;
        oss << target->name << " position is " << static_cast<int>(target->state.position) << "%";
        return oss.str();
    }

    if ((q.find("posicao") != std::string::npos || q.find("position") != std::string::npos ||
         q.find("open") != std::string::npos || q.find("close") != std::string::npos) &&
        !target) {
        std::vector<std::string> rows;
        for (const auto& d : devices) {
            if (hasCapability(d, CORE_CAP_POSITION)) {
                rows.push_back(d.name + " " + std::to_string(static_cast<int>(d.state.position)) + "%");
            }
        }
        if (!rows.empty()) {
            std::ostringstream oss;
            oss << "Position: ";
            for (size_t i = 0; i < rows.size(); ++i) {
                if (i > 0) oss << ", ";
                oss << rows[i];
            }
            return oss.str();
        }
    }

    if (!target) {
        return "I can help with status, device list, online devices, and behavior insights.";
    }

    return "I can report status, online devices and possible behavior insights.";
}

std::string AiEngine::learningSnapshot() const {
    const auto insights = annotations(8);
    if (insights.empty()) {
        return "I am still learning your behavior. Keep using app, devices and profiles.";
    }

    std::ostringstream oss;
    for (size_t i = 0; i < insights.size(); ++i) {
        if (i > 0) {
            oss << ' ';
        }
        oss << insights[i];
    }
    return oss.str();
}

std::vector<std::string> AiEngine::annotations(size_t maxItems) const {
    std::vector<std::string> out;

    const int possibleArrival = strongestHour(powerOnByHour_, 17, 23);
    const int possibleWake = strongestHour(appOpenByHour_, 5, 11);
    const int possibleSleep = strongestHour(appOpenByHour_, 21, 2);

    if (possibleArrival >= 0) {
        out.push_back("Possibly arriving home around " + hhmmFromHour(possibleArrival) +
                      " based on evening power-on activity.");
    }

    if (possibleWake >= 0) {
        out.push_back("Possibly waking up or starting the day around " + hhmmFromHour(possibleWake) +
                      " based on morning app usage.");
    }

    if (possibleSleep >= 0) {
        out.push_back("Possibly going to sleep around " + hhmmFromHour(possibleSleep) +
                      " based on late-night app activity.");
    }

    int gameCount = 0;
    for (const auto& item : profileApplyCount_) {
        if (item.first.find("game") != std::string::npos ||
            item.first.find("jogo") != std::string::npos) {
            gameCount += item.second;
        }
    }

    if (gameCount > 0) {
        const int gameHour = strongestHour(profileApplyByHour_, 18, 2);
        if (gameHour >= 0) {
            out.push_back("Possibly gaming in the evening around " + hhmmFromHour(gameHour) +
                          " because game-related profiles are often applied then.");
        } else {
            out.push_back("Possibly gaming during evening/night based on game-related profile usage.");
        }
    }

    if (tempCount_ > 2) {
        std::ostringstream oss;
        oss << "Possibly preferring comfort temperature near "
            << static_cast<int>(tempSum_ / tempCount_) << "°C.";
        out.push_back(oss.str());
    }

    if (brightnessCount_ > 2) {
        std::ostringstream oss;
        oss << "Possibly preferring brightness near "
            << static_cast<int>(brightnessSum_ / brightnessCount_) << "% in recent usage.";
        out.push_back(oss.str());
    }

    if (positionCount_ > 2) {
        std::ostringstream oss;
        oss << "Possibly preferring curtain position near "
            << static_cast<int>(positionSum_ / positionCount_) << "% in recent routines.";
        out.push_back(oss.str());
    }

    if (out.size() > maxItems) {
        out.resize(maxItems);
    }

    return out;
}

std::string AiEngine::normalize(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return value;
}

int AiEngine::hourFromTimestamp(uint64_t timestampMs) {
    if (timestampMs == 0) {
        timestampMs = nowMs();
    }

    const std::time_t secs = static_cast<std::time_t>(timestampMs / 1000ULL);
    std::tm tmValue{};
#if defined(_WIN32)
    localtime_s(&tmValue, &secs);
#else
    localtime_r(&secs, &tmValue);
#endif
    return tmValue.tm_hour;
}

std::string AiEngine::hhmmFromHour(int hour) {
    if (hour < 0) {
        return "unknown";
    }
    std::ostringstream oss;
    if (hour < 10) {
        oss << '0';
    }
    oss << hour << ":00";
    return oss.str();
}

bool AiEngine::hasCapability(const DeviceSnapshot& device, CoreCapability capability) const {
    return std::find(device.capabilities.begin(), device.capabilities.end(), capability) !=
           device.capabilities.end();
}

const DeviceSnapshot* AiEngine::findByName(const std::string& text,
                                           const std::vector<DeviceSnapshot>& devices) const {
    for (const auto& d : devices) {
        const std::string name = normalize(d.name);
        if (!name.empty() && text.find(name) != std::string::npos) {
            return &d;
        }
    }

    if (text.find("lamp") != std::string::npos || text.find("light") != std::string::npos ||
        text.find("luz") != std::string::npos) {
        std::vector<const DeviceSnapshot*> lights;
        for (const auto& d : devices) {
            if (hasCapability(d, CORE_CAP_BRIGHTNESS) || hasCapability(d, CORE_CAP_COLOR)) {
                lights.push_back(&d);
            }
        }
        if (lights.size() == 1) {
            return lights.front();
        }
    }

    if (text.find("ac") != std::string::npos || text.find("climate") != std::string::npos ||
        text.find("fridge") != std::string::npos || text.find("freezer") != std::string::npos ||
        text.find("geladeira") != std::string::npos || text.find("congelador") != std::string::npos ||
        text.find("temperature") != std::string::npos || text.find("temperatura") != std::string::npos ||
        text.find("tempeature") != std::string::npos || text.find("temp") != std::string::npos) {
        std::vector<const DeviceSnapshot*> thermal;
        for (const auto& d : devices) {
            if (hasCapability(d, CORE_CAP_TEMPERATURE)) {
                thermal.push_back(&d);
            }
        }
        if (thermal.size() == 1) {
            return thermal.front();
        }
    }

    if (devices.size() == 1) {
        return &devices.front();
    }

    return nullptr;
}

void AiEngine::pushEvent(BehaviorEventType type,
                         int hour,
                         uint64_t timestampMs,
                         const std::string& label) {
    BehaviorEvent ev;
    ev.type = type;
    ev.hour = hour;
    ev.timestampMs = timestampMs == 0 ? nowMs() : timestampMs;
    ev.label = label;

    memory_.push_back(ev);
    while (memory_.size() > kMaxMemory) {
        memory_.pop_front();
    }
}

int AiEngine::strongestHour(const std::array<int, 24>& values,
                            int startHour,
                            int endHour) const {
    int bestHour = -1;
    int bestCount = 0;

    auto inWindow = [&](int h) {
        if (startHour <= endHour) {
            return h >= startHour && h <= endHour;
        }
        return h >= startHour || h <= endHour;
    };

    for (int h = 0; h < 24; ++h) {
        if (!inWindow(h)) {
            continue;
        }
        if (values[h] > bestCount) {
            bestCount = values[h];
            bestHour = h;
        }
    }

    return bestHour;
}

} // namespace easync::ai
