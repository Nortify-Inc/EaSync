#include "aiEngine.hpp"

#include <algorithm>
#include <cmath>
#include <cctype>
#include <chrono>
#include <ctime>
#include <limits>
#include <sstream>

namespace easync::ai {

namespace {
uint64_t nowMs() {
    return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch())
        .count());
}

std::string modeLabel(uint32_t mode) {
    switch (mode) {
        case 0: return "auto";
        case 1: return "eco";
        case 2: return "turbo";
        case 3: return "sleep";
        case 4: return "comfort";
        case 5: return "focus";
        default: return "mode " + std::to_string(mode);
    }
}

std::string colorNameFromRgb(uint32_t rgbRaw) {
    const uint32_t rgb = rgbRaw & 0x00FFFFFF;
    struct NamedColor { const char* name; uint32_t rgb; };
    static const NamedColor table[] = {
        {"red", 0x00E53935}, {"green", 0x0000C853}, {"blue", 0x000066FF},
        {"yellow", 0x00FFD600}, {"orange", 0x00FB8C00}, {"purple", 0x009C27B0},
        {"pink", 0x00EC407A}, {"cyan", 0x0000BCD4}, {"white", 0x00F5F5F5},
        {"black", 0x00000000}, {"gray", 0x00808080}, {"brown", 0x008B4513},
    };

    int best = 0;
    uint64_t bestDist = std::numeric_limits<uint64_t>::max();
    const int r = static_cast<int>((rgb >> 16) & 0xFF);
    const int g = static_cast<int>((rgb >> 8) & 0xFF);
    const int b = static_cast<int>(rgb & 0xFF);

    const size_t tableCount = sizeof(table) / sizeof(table[0]);
    for (size_t i = 0; i < tableCount; ++i) {
        const int tr = static_cast<int>((table[i].rgb >> 16) & 0xFF);
        const int tg = static_cast<int>((table[i].rgb >> 8) & 0xFF);
        const int tb = static_cast<int>(table[i].rgb & 0xFF);
        const int dr = r - tr;
        const int dg = g - tg;
        const int db = b - tb;
        const uint64_t dist = static_cast<uint64_t>(dr * dr + dg * dg + db * db);
        if (dist < bestDist) {
            bestDist = dist;
            best = static_cast<int>(i);
        }
    }
    return table[best].name;
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
    const bool isGreeting = q.find("hello") != std::string::npos ||
                            q.find("hi") != std::string::npos ||
                            q.find("hey") != std::string::npos ||
                            q.find("oi") != std::string::npos ||
                            q.find("ola") != std::string::npos ||
                            q.find("olá") != std::string::npos ||
                            q.find("bom dia") != std::string::npos ||
                            q.find("boa tarde") != std::string::npos ||
                            q.find("boa noite") != std::string::npos;
    const bool isThanks = q.find("thanks") != std::string::npos ||
                          q.find("thank you") != std::string::npos ||
                          q.find("thx") != std::string::npos ||
                          q.find("obrigado") != std::string::npos ||
                          q.find("obrigada") != std::string::npos ||
                          q.find("valeu") != std::string::npos;
    const bool isHowAreYou = q.find("how are you") != std::string::npos ||
                             q.find("how's it going") != std::string::npos ||
                             q.find("how is it going") != std::string::npos ||
                             q.find("you good") != std::string::npos ||
                             q.find("tudo bem") != std::string::npos ||
                             q.find("como voce esta") != std::string::npos ||
                             q.find("como você está") != std::string::npos;
    const bool isFarewell = q.find("bye") != std::string::npos ||
                            q.find("see you") != std::string::npos ||
                            q.find("good night") != std::string::npos ||
                            q.find("talk later") != std::string::npos ||
                            q.find("tchau") != std::string::npos ||
                            q.find("ate mais") != std::string::npos ||
                            q.find("até mais") != std::string::npos;
    const bool asksTemperature = q.find("temperatura") != std::string::npos ||
                                 q.find("temperature") != std::string::npos ||
                                 q.find("tempeature") != std::string::npos ||
                                 q.find("temp") != std::string::npos ||
                                 q.find("thermo") != std::string::npos;
    const bool asksPosition = q.find("position") != std::string::npos ||
                              q.find("posicao") != std::string::npos ||
                              q.find("curtain") != std::string::npos ||
                              q.find("curtains") != std::string::npos ||
                              q.find("blind") != std::string::npos ||
                              q.find("blinds") != std::string::npos ||
                              q.find("shade") != std::string::npos ||
                              q.find("open") != std::string::npos ||
                              q.find("close") != std::string::npos;
    const bool asksBrightness = q.find("brilho") != std::string::npos ||
                                q.find("brightness") != std::string::npos;
    const bool asksPower = q.find("ligad") != std::string::npos ||
                           q.find("power") != std::string::npos ||
                           q.find(" on") != std::string::npos ||
                           q.find(" off") != std::string::npos;
    const bool asksLock = q.find("lock") != std::string::npos ||
                          q.find("unlock") != std::string::npos ||
                          q.find("tranca") != std::string::npos ||
                          q.find("fechadura") != std::string::npos;
    const bool asksMode = q.find("mode") != std::string::npos ||
                          q.find("modo") != std::string::npos;
    const bool asksColor = q.find("color") != std::string::npos ||
                           q.find("colour") != std::string::npos ||
                           q.find("cor") != std::string::npos;
    const bool asksColorTemp = q.find("color temperature") != std::string::npos ||
                               q.find("colour temperature") != std::string::npos ||
                               q.find("temperatura de cor") != std::string::npos ||
                               q.find("kelvin") != std::string::npos;
    const bool asksTime = q.find("time") != std::string::npos ||
                          q.find("timer") != std::string::npos ||
                          q.find("timestamp") != std::string::npos;
    const bool asksFreezer = q.find("freezer") != std::string::npos ||
                             q.find("congelador") != std::string::npos;
    const bool asksFridge = q.find("fridge") != std::string::npos ||
                            q.find("geladeira") != std::string::npos ||
                            q.find("refrigerator") != std::string::npos;

    if (q.empty()) {
        return "I can help with commands, device status, and behavior insights.";
    }

    if (isGreeting) {
        return "Hello. I can control devices and share possible behavior insights.";
    }

    if (isThanks) {
        return "You are welcome. Happy to help.";
    }

    if (isHowAreYou) {
        return "I am active and ready. You can ask me to control devices or check status.";
    }

    if (isFarewell) {
        return "See you soon. I will keep your devices ready.";
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

    if ((q.find("status") != std::string::npos || q.find("estado") != std::string::npos) &&
        !asksTemperature && !asksPosition && !asksBrightness && !asksPower && !asksLock && !asksMode && !asksColor && !asksColorTemp) {
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

    if (asksPower) {
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

    if (asksTemperature && target) {
        std::ostringstream oss;
        if (asksFreezer && hasCapability(*target, CORE_CAP_TEMPERATURE_FREEZER)) {
            oss << target->name << " freezer temperature is "
                << static_cast<int>(target->state.temperatureFreezer) << "°C.";
            return oss.str();
        }
        if (asksFridge && hasCapability(*target, CORE_CAP_TEMPERATURE_FRIDGE)) {
            oss << target->name << " fridge temperature is "
                << static_cast<int>(target->state.temperatureFridge) << "°C.";
            return oss.str();
        }
        if (hasCapability(*target, CORE_CAP_TEMPERATURE)) {
            oss << target->name << " temperature is " << static_cast<int>(target->state.temperature) << "°C.";
            return oss.str();
        }
        if (hasCapability(*target, CORE_CAP_TEMPERATURE_FRIDGE)) {
            oss << target->name << " fridge temperature is "
                << static_cast<int>(target->state.temperatureFridge) << "°C.";
            return oss.str();
        }
        if (hasCapability(*target, CORE_CAP_TEMPERATURE_FREEZER)) {
            oss << target->name << " freezer temperature is "
                << static_cast<int>(target->state.temperatureFreezer) << "°C.";
            return oss.str();
        }
    }

    if (asksTemperature && !target) {
        std::vector<std::string> rows;
        for (const auto& d : devices) {
            if (asksFreezer && hasCapability(d, CORE_CAP_TEMPERATURE_FREEZER)) {
                rows.push_back(d.name + " freezer " +
                               std::to_string(static_cast<int>(d.state.temperatureFreezer)) + "°C");
            } else if (asksFridge && hasCapability(d, CORE_CAP_TEMPERATURE_FRIDGE)) {
                rows.push_back(d.name + " fridge " +
                               std::to_string(static_cast<int>(d.state.temperatureFridge)) + "°C");
            } else if (hasCapability(d, CORE_CAP_TEMPERATURE)) {
                rows.push_back(d.name + " " + std::to_string(static_cast<int>(d.state.temperature)) + "°C");
            } else if (hasCapability(d, CORE_CAP_TEMPERATURE_FRIDGE)) {
                rows.push_back(d.name + " fridge " +
                               std::to_string(static_cast<int>(d.state.temperatureFridge)) + "°C");
            } else if (hasCapability(d, CORE_CAP_TEMPERATURE_FREEZER)) {
                rows.push_back(d.name + " freezer " +
                               std::to_string(static_cast<int>(d.state.temperatureFreezer)) + "°C");
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

    if (asksBrightness && target && hasCapability(*target, CORE_CAP_BRIGHTNESS)) {
        std::ostringstream oss;
        oss << target->name << " brightness is " << target->state.brightness << "%";
        return oss.str();
    }

    if (asksBrightness && !target) {
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

    if (asksPosition && target && hasCapability(*target, CORE_CAP_POSITION)) {
        std::ostringstream oss;
        const int pos = std::clamp(static_cast<int>(std::lround(target->state.position)), 0, 100);
        oss << target->name << " position is " << pos << "%";
        return oss.str();
    }

    if (asksPosition && !target) {
        std::vector<std::string> rows;
        for (const auto& d : devices) {
            if (hasCapability(d, CORE_CAP_POSITION)) {
                const int pos = std::clamp(static_cast<int>(std::lround(d.state.position)), 0, 100);
                rows.push_back(d.name + " " + std::to_string(pos) + "%");
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

    if (asksLock && target && hasCapability(*target, CORE_CAP_LOCK)) {
        return target->name + std::string(target->state.lock ? " is LOCKED." : " is UNLOCKED.");
    }

    if (asksLock && !target) {
        std::vector<std::string> rows;
        for (const auto& d : devices) {
            if (hasCapability(d, CORE_CAP_LOCK)) {
                rows.push_back(d.name + std::string(d.state.lock ? " locked" : " unlocked"));
            }
        }
        if (!rows.empty()) {
            std::ostringstream oss;
            oss << "Lock state: ";
            for (size_t i = 0; i < rows.size(); ++i) {
                if (i > 0) oss << ", ";
                oss << rows[i];
            }
            return oss.str();
        }
    }

    if (asksMode && target && hasCapability(*target, CORE_CAP_MODE)) {
        std::ostringstream oss;
        oss << target->name << " mode is " << modeLabel(target->state.mode) << ".";
        return oss.str();
    }

    if (asksColorTemp && target && hasCapability(*target, CORE_CAP_COLOR_TEMP)) {
        std::ostringstream oss;
        oss << target->name << " color temperature is " << target->state.colorTemperature << "K.";
        return oss.str();
    }

    if (asksColor && target && hasCapability(*target, CORE_CAP_COLOR)) {
        std::ostringstream oss;
        oss << target->name << " color is " << colorNameFromRgb(target->state.color) << ".";
        return oss.str();
    }

    if (asksTime && target && hasCapability(*target, CORE_CAP_TIMESTAMP)) {
        std::ostringstream oss;
        oss << target->name << " time value is " << target->state.timestamp << ".";
        return oss.str();
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

    if (text.find("curtain") != std::string::npos || text.find("curtains") != std::string::npos ||
        text.find("blind") != std::string::npos || text.find("blinds") != std::string::npos ||
        text.find("shade") != std::string::npos || text.find("cortina") != std::string::npos) {
        std::vector<const DeviceSnapshot*> curtains;
        for (const auto& d : devices) {
            if (hasCapability(d, CORE_CAP_POSITION)) {
                curtains.push_back(&d);
            }
        }
        if (curtains.size() == 1) {
            return curtains.front();
        }
    }

    if (text.find("ac") != std::string::npos || text.find("climate") != std::string::npos ||
        text.find("fridge") != std::string::npos || text.find("freezer") != std::string::npos ||
        text.find("geladeira") != std::string::npos || text.find("congelador") != std::string::npos ||
        text.find("temperature") != std::string::npos || text.find("temperatura") != std::string::npos ||
        text.find("tempeature") != std::string::npos || text.find("temp") != std::string::npos) {
        std::vector<const DeviceSnapshot*> thermal;
        for (const auto& d : devices) {
            if (hasCapability(d, CORE_CAP_TEMPERATURE) ||
                hasCapability(d, CORE_CAP_TEMPERATURE_FRIDGE) ||
                hasCapability(d, CORE_CAP_TEMPERATURE_FREEZER)) {
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
