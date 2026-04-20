#pragma once

/**
 * @file payloadUtility.hpp
 * @brief Payload template utility used by protocol drivers.
 * @param capability Capability key (for example: power, temperature, mode).
 * @return JSON payload strings assembled from template files.
 * @author Erick Radmann
 */

#include <string>
#include <vector>

namespace core {

struct PayloadCommand {
    std::string topic;
    std::string payload;
    std::string method;
    std::string contentType;
};

class PayloadUtility {
public:
    static PayloadUtility& instance();

    void bindDevice(const std::string& uuid,
                    const std::string& brand,
                    const std::string& model);

    void unbindDevice(const std::string& uuid);

    std::string createPayload(const std::string& uuid,
                              const std::string& capability,
                              const std::string& valueJson);

    std::string createPayload(const std::string& brand,
                              const std::string& model,
                              const std::string& capability,
                              const std::string& valueJson);

    PayloadCommand createCommand(const std::string& uuid,
                                 const std::string& capability,
                                 const std::string& valueJson);

    PayloadCommand createCommand(const std::string& brand,
                                 const std::string& model,
                                 const std::string& uuid,
                                 const std::string& capability,
                                 const std::string& valueJson);

    std::vector<std::string> modeOptions(const std::string& brand,
                                         const std::string& model);

    std::vector<std::string> modeOptionsForDevice(const std::string& uuid);

private:
    PayloadUtility() = default;
    PayloadUtility(const PayloadUtility&) = delete;
    PayloadUtility& operator=(const PayloadUtility&) = delete;

    void ensureLoaded();
};

} // namespace core
