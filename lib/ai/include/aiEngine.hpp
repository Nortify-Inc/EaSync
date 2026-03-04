#pragma once

#include "core.h"

#include <array>
#include <cstdint>
#include <deque>
#include <string>
#include <unordered_map>
#include <vector>

namespace easync::ai {

struct Permissions {
    bool useLocationData = true;
    bool useWeatherData = true;
    bool useUsageHistory = true;
    bool allowDeviceControl = true;
    bool allowAutoRoutines = true;
};

struct DeviceSnapshot {
    std::string uuid;
    std::string name;
    std::vector<CoreCapability> capabilities;
    CoreDeviceState state{};
    bool online = false;
};

enum class BehaviorEventType {
    AppOpen,
    PowerOn,
    ProfileApply,
    StateChange,
    Command
};

struct BehaviorEvent {
    BehaviorEventType type{};
    int hour = 0;
    uint64_t timestampMs = 0;
    std::string label;
};

class AiEngine {
public:
    void setPermissions(const Permissions& permissions);
    Permissions permissions() const;

    void observeAppOpen(uint64_t timestampMs);
    void observeProfileApply(const std::string& profileName, uint64_t timestampMs);
    void observeCommand(const std::string& input, uint64_t timestampMs);

    void recordPattern(const std::string& uuid,
                       const CoreDeviceState& previous,
                       const CoreDeviceState& next,
                       bool enabled,
                       uint64_t timestampMs);

    std::string processChat(const std::string& input,
                            const std::vector<DeviceSnapshot>& devices) const;

    std::string learningSnapshot() const;
    std::vector<std::string> annotations(size_t maxItems = 6) const;

private:
    static std::string normalize(std::string value);
    static int hourFromTimestamp(uint64_t timestampMs);
    static std::string hhmmFromHour(int hour);

    bool hasCapability(const DeviceSnapshot& device, CoreCapability capability) const;
    const DeviceSnapshot* findByName(const std::string& text,
                                     const std::vector<DeviceSnapshot>& devices) const;

    void pushEvent(BehaviorEventType type,
                   int hour,
                   uint64_t timestampMs,
                   const std::string& label);

    int strongestHour(const std::array<int, 24>& values,
                      int startHour,
                      int endHour) const;

    Permissions permissions_{};

    std::deque<BehaviorEvent> memory_{};
    static constexpr size_t kMaxMemory = 100;

    std::array<int, 24> appOpenByHour_{};
    std::array<int, 24> powerOnByHour_{};
    std::array<int, 24> profileApplyByHour_{};

    std::unordered_map<std::string, int> profileApplyCount_{};
    std::unordered_map<std::string, int> activityByDevice_{};

    double tempSum_ = 0.0;
    int tempCount_ = 0;
    double brightnessSum_ = 0.0;
    int brightnessCount_ = 0;
    double positionSum_ = 0.0;
    int positionCount_ = 0;
};

} // namespace easync::ai
