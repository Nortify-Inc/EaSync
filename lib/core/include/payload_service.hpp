#pragma once

/**
 * @file payload_service.hpp
 * @brief Payload template service used by protocol drivers.
 * @param capability Capability key (for example: power, temperature, mode).
 * @return JSON payload strings assembled from template files.
 * @author Erick Radmann
 */

#include <string>

namespace core {

struct PayloadCommand {
    std::string topic;
    std::string payload;
};

class PayloadService {
public:
    static PayloadService& instance();

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

private:
    PayloadService() = default;
    PayloadService(const PayloadService&) = delete;
    PayloadService& operator=(const PayloadService&) = delete;

    void ensureLoaded();
};

} // namespace core
