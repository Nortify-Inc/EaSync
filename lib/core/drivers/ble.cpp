#include "ble.hpp"
#include "payloadUtility.hpp"

#include <openssl/evp.h>
#include <filesystem>
#include <sstream>
#include <vector>
#include <array>
#include <iostream>
#include <iomanip>
#include <cstdlib>
#include <cstdio>
#include <memory>
#include <stdexcept>
#include <algorithm>
#include <cctype>

namespace {

static std::string execCommand(const char* cmd) {
    std::array<char, 128> buffer;
    std::string result;
    std::unique_ptr<FILE, decltype(&pclose)> pipe(popen(cmd, "r"), pclose);
    if (!pipe) {
        return "";
    }
    while (fgets(buffer.data(), buffer.size(), pipe.get()) != nullptr) {
        result += buffer.data();
    }
    return result;
}

static std::string trim(const std::string& s) {
    auto start = s.begin();
    while (start != s.end() && std::isspace(*start)) {
        start++;
    }
    auto end = s.end();
    do {
        end--;
    } while (std::distance(start, end) > 0 && std::isspace(*end));
    return std::string(start, end + 1);
}

static std::vector<uint8_t> hexToBytes(const std::string& hex) {
    std::vector<uint8_t> out;
    out.reserve(hex.size() / 2);
    for (size_t i = 0; i + 1 < hex.size(); i += 2) {
        const auto hi = static_cast<uint8_t>(std::stoul(hex.substr(i,   1), nullptr, 16));
        const auto lo = static_cast<uint8_t>(std::stoul(hex.substr(i+1, 1), nullptr, 16));
        out.push_back(static_cast<uint8_t>((hi << 4) | lo));
    }
    return out;
}

static std::vector<uint8_t> aes128CbcEncrypt(
    const std::vector<uint8_t>& key,
    const std::vector<uint8_t>& plaintext)
{
    if (key.size() != 16) return {};
    EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return {};
    const std::vector<uint8_t> iv(16, 0x00);
    std::vector<uint8_t> out(plaintext.size() + 16);
    int outLen1 = 0, outLen2 = 0;
    if (EVP_EncryptInit_ex(ctx, EVP_aes_128_cbc(), nullptr, key.data(), iv.data()) != 1 ||
        EVP_EncryptUpdate(ctx, out.data(), &outLen1, plaintext.data(),
                          static_cast<int>(plaintext.size())) != 1 ||
        EVP_EncryptFinal_ex(ctx, out.data() + outLen1, &outLen2) != 1) {
        EVP_CIPHER_CTX_free(ctx);
        return {};
    }
    EVP_CIPHER_CTX_free(ctx);
    out.resize(static_cast<size_t>(outLen1 + outLen2));
    return out;
}

static std::vector<uint8_t> aes128EcbEncrypt(
    const std::vector<uint8_t>& key,
    const std::vector<uint8_t>& plaintext)
{
    if (key.size() != 16) return {};
    EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return {};
    std::vector<uint8_t> out(plaintext.size() + 16);
    int outLen1 = 0, outLen2 = 0;
    if (EVP_EncryptInit_ex(ctx, EVP_aes_128_ecb(), nullptr, key.data(), nullptr) != 1 ||
        EVP_EncryptUpdate(ctx, out.data(), &outLen1, plaintext.data(),
                          static_cast<int>(plaintext.size())) != 1 ||
        EVP_EncryptFinal_ex(ctx, out.data() + outLen1, &outLen2) != 1) {
        EVP_CIPHER_CTX_free(ctx);
        return {};
    }
    EVP_CIPHER_CTX_free(ctx);
    out.resize(static_cast<size_t>(outLen1 + outLen2));
    return out;
}

static std::string readEnv(const std::string& key) {
    if (const char* v = std::getenv(key.c_str())) {
        return trim(v);
    }
    return "";
}

// -------------------------------------------------------------
// BlueZ D-Bus integration via busctl
// -------------------------------------------------------------

static std::string getDeviceDbusPath(const std::string& mac) {
#ifdef __ANDROID__
    (void)mac;
    return "";
#else
    std::string safeMac = mac;
    std::replace(safeMac.begin(), safeMac.end(), ':', '_');
    return "/org/bluez/hci0/dev_" + safeMac;
#endif
}

static std::string getCharacteristicDbusPath(const std::string& devPath, const std::string& charUuid) {
#ifdef __ANDROID__
    (void)devPath; (void)charUuid;
    return "";
#else
    // Query bluez for all characteristics of this device and find the matching UUID
    std::string cmd = "busctl tree org.bluez | grep " + devPath + " | grep char";
    std::string tree = execCommand(cmd.c_str());
    
    std::stringstream ss(tree);
    std::string line;
    while (std::getline(ss, line)) {
        size_t idx = line.find("/org/bluez");
        if (idx != std::string::npos) {
            std::string path = trim(line.substr(idx));
            std::string propCmd = "busctl get-property org.bluez " + path + " org.bluez.GattCharacteristic1 UUID";
            std::string prop = execCommand(propCmd.c_str());
            if (prop.find(charUuid) != std::string::npos) {
                return path;
            }
        }
    }
    return "";
#endif
}

static bool executeBleWrite(const std::string& mac, const std::string& charUuid, const std::vector<uint8_t>& data) {
#ifdef __ANDROID__
    (void)mac; (void)charUuid; (void)data;
    return false;
#else
    std::string devPath = getDeviceDbusPath(mac);
    
    // Ensure connected
    std::string connCmd = "busctl call org.bluez " + devPath + " org.bluez.Device1 Connect";
    execCommand(connCmd.c_str()); // ignores errors if already connected
    
    std::string charPath = getCharacteristicDbusPath(devPath, charUuid);
    if (charPath.empty()) return false;

    std::stringstream cmd;
    cmd << "busctl call org.bluez " << charPath << " org.bluez.GattCharacteristic1 WriteValue aya{sv} " << data.size();
    for (uint8_t b : data) {
        cmd << " " << static_cast<int>(b);
    }
    cmd << " 0";
    
    std::string res = execCommand(cmd.str().c_str());
    return res.empty() || res.find("Error") == std::string::npos;
#endif
}

// -------------------------------------------------------------
// Brand Envelopes
// -------------------------------------------------------------

static std::vector<uint8_t> buildTuyaBlePayload(const std::string& jsonPayload, const std::string& localKeyHex) {
    std::vector<uint8_t> localKey = hexToBytes(localKeyHex);
    if (localKey.size() != 16) return {};

    std::vector<uint8_t> plain(jsonPayload.begin(), jsonPayload.end());
    std::vector<uint8_t> enc = aes128EcbEncrypt(localKey, plain);

    std::vector<uint8_t> packet;
    packet.reserve(16 + enc.size());
    // Sequencer (4 bytes)
    packet.push_back(0x00); packet.push_back(0x00); packet.push_back(0x00); packet.push_back(0x00);
    // Cmd (Control = 0x000D)
    packet.push_back(0x00); packet.push_back(0x0D);
    // Length
    packet.push_back((enc.size() >> 8) & 0xFF);
    packet.push_back(enc.size() & 0xFF);
    // Encrypted Data
    packet.insert(packet.end(), enc.begin(), enc.end());
    
    // Simple CRC/Checksum (often omitted or standard CRC16 in Tuya)
    // We add 0x00 0x00 as placeholder for checksum.
    packet.push_back(0x00);
    packet.push_back(0x00);

    return packet;
}

static std::vector<uint8_t> buildMideaBlePayload(const std::string& jsonPayload, const std::string& keyHex) {
    std::vector<uint8_t> key = hexToBytes(keyHex);
    if (key.size() != 16) return {};

    std::vector<uint8_t> plain(jsonPayload.begin(), jsonPayload.end());
    std::vector<uint8_t> enc = aes128CbcEncrypt(key, plain);

    std::vector<uint8_t> packet;
    packet.push_back(0x5A);
    packet.push_back(0x5A);
    packet.push_back(static_cast<uint8_t>(enc.size() + 4));
    packet.push_back(0x01); // Type
    packet.insert(packet.end(), enc.begin(), enc.end());
    return packet;
}

} // namespace

namespace drivers {

bool BleDriver::init() {
#ifdef __ANDROID__
    adapterAvailable = true; // Assume available for now, actual check needed later
#else
    // Check if D-Bus system bus is reachable and BlueZ is active
    adapterAvailable = std::filesystem::exists("/sys/class/bluetooth") && 
                       execCommand("busctl status org.bluez").find("org.bluez") != std::string::npos;
#endif
    return adapterAvailable;
}

bool BleDriver::connect(const std::string& uuid) {
    std::lock_guard<std::mutex> lock(mutex);

    if (!adapterAvailable)
        return false;

    if (states.count(uuid))
        return true;

    // Trigger BlueZ connection via DBus
    std::string devPath = getDeviceDbusPath(uuid); // Assuming UUID is MAC
    std::string connCmd = "busctl call org.bluez " + devPath + " org.bluez.Device1 Connect";
    execCommand(connCmd.c_str());

    states.emplace(uuid, CoreDeviceState{});
    return true;
}

bool BleDriver::disconnect(const std::string& uuid) {
    std::lock_guard<std::mutex> lock(mutex);
    std::string devPath = getDeviceDbusPath(uuid);
    std::string cmd = "busctl call org.bluez " + devPath + " org.bluez.Device1 Disconnect";
    execCommand(cmd.c_str());

    states.erase(uuid);
    return true;
}

bool BleDriver::ensureConnected(const std::string& uuid) {
    if (!adapterAvailable)
        return false;
    return states.count(uuid) > 0;
}

void BleDriver::notifyStateChange(const std::string& uuid, const CoreDeviceState& newState) {
    if (eventCallback) {
        eventCallback(uuid, newState, eventUserData);
    }
}

// -------------------------------------------------------------
// Core Operations
// -------------------------------------------------------------

bool BleDriver::publishCommand(const std::string& uuid, const std::string& capability, const std::string& valueJson) {
    core::PayloadCommand cmd = core::PayloadUtility::instance().createCommand(uuid, capability, valueJson);
    if (cmd.payload.empty()) return false;

    // Detect brand based on env vars or hints. This is an approximation since BLE Driver lacks direct Brand info context.
    std::string tuyaKey = readEnv("EASYNC_TUYA_LOCAL_KEY_" + uuid);
    if (tuyaKey.empty()) tuyaKey = readEnv("EASYNC_TUYA_LOCAL_KEY");

    std::string mideaKey = readEnv("EASYNC_MIDEA_KEY_" + uuid);
    if (mideaKey.empty()) mideaKey = readEnv("EASYNC_MIDEA_KEY");

    std::vector<uint8_t> blePacket;
    std::string targetCharUuid;

    if (!tuyaKey.empty()) {
        blePacket = buildTuyaBlePayload(cmd.payload, tuyaKey);
        targetCharUuid = "00000001-0000-1000-8000-00805f9b34fb"; // Tuya Write Char
    } else if (!mideaKey.empty()) {
        blePacket = buildMideaBlePayload(cmd.payload, mideaKey);
        targetCharUuid = "00000011-0000-1000-8000-00805f9b34fb"; // Example Midea Write Char
    } else {
        // Generic BLE JSON transmission (e.g. Electrolux custom text characteristic)
        blePacket.assign(cmd.payload.begin(), cmd.payload.end());
        targetCharUuid = "00000001-0000-1000-8000-00805f9b34fb"; // Fallback write char
    }

    if (blePacket.empty()) return false;

    return executeBleWrite(uuid, targetCharUuid, blePacket);
}

bool BleDriver::setPower(const std::string& uuid, bool value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!ensureConnected(uuid)) return false;
    if (publishCommand(uuid, "power", value ? "true" : "false")) {
        states[uuid].power = value;
        notifyStateChange(uuid, states[uuid]);
        return true;
    }
    return false;
}

bool BleDriver::setBrightness(const std::string& uuid, uint32_t value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!ensureConnected(uuid)) return false;
    if (publishCommand(uuid, "brightness", std::to_string(value))) {
        states[uuid].brightness = value;
        notifyStateChange(uuid, states[uuid]);
        return true;
    }
    return false;
}

bool BleDriver::setColor(const std::string& uuid, uint32_t rgb) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!ensureConnected(uuid)) return false;
    if (publishCommand(uuid, "color", std::to_string(rgb))) {
        states[uuid].color = rgb;
        notifyStateChange(uuid, states[uuid]);
        return true;
    }
    return false;
}

bool BleDriver::setTemperature(const std::string& uuid, float value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!ensureConnected(uuid)) return false;
    if (publishCommand(uuid, "temperature", std::to_string(value))) {
        states[uuid].temperature = value;
        notifyStateChange(uuid, states[uuid]);
        return true;
    }
    return false;
}

bool BleDriver::setTemperatureFridge(const std::string& uuid, float value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!ensureConnected(uuid)) return false;
    if (publishCommand(uuid, "temperature_fridge", std::to_string(value))) {
        states[uuid].temperatureFridge = value;
        notifyStateChange(uuid, states[uuid]);
        return true;
    }
    return false;
}

bool BleDriver::setTemperatureFreezer(const std::string& uuid, float value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!ensureConnected(uuid)) return false;
    if (publishCommand(uuid, "temperature_freezer", std::to_string(value))) {
        states[uuid].temperatureFreezer = value;
        notifyStateChange(uuid, states[uuid]);
        return true;
    }
    return false;
}

bool BleDriver::setTime(const std::string& uuid, uint64_t value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!ensureConnected(uuid)) return false;
    if (publishCommand(uuid, "time", std::to_string(value))) {
        states[uuid].timestamp = value;
        notifyStateChange(uuid, states[uuid]);
        return true;
    }
    return false;
}

bool BleDriver::setColorTemperature(const std::string& uuid, uint32_t value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!ensureConnected(uuid)) return false;
    if (publishCommand(uuid, "colorTemperature", std::to_string(value))) {
        states[uuid].colorTemperature = value;
        notifyStateChange(uuid, states[uuid]);
        return true;
    }
    return false;
}

bool BleDriver::setLock(const std::string& uuid, bool value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!ensureConnected(uuid)) return false;
    if (publishCommand(uuid, "lock", value ? "true" : "false")) {
        states[uuid].lock = value;
        notifyStateChange(uuid, states[uuid]);
        return true;
    }
    return false;
}

bool BleDriver::setMode(const std::string& uuid, uint32_t value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!ensureConnected(uuid)) return false;
    if (publishCommand(uuid, "mode", std::to_string(value))) {
        states[uuid].mode = value;
        notifyStateChange(uuid, states[uuid]);
        return true;
    }
    return false;
}

bool BleDriver::setPosition(const std::string& uuid, float value) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!ensureConnected(uuid)) return false;
    if (publishCommand(uuid, "position", std::to_string(value))) {
        states[uuid].position = value;
        notifyStateChange(uuid, states[uuid]);
        return true;
    }
    return false;
}

bool BleDriver::getState(const std::string& uuid, CoreDeviceState& outState) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!ensureConnected(uuid)) return false;
    outState = states[uuid];
    return true;
}

bool BleDriver::isAvailable(const std::string& uuid) {
    std::lock_guard<std::mutex> lock(mutex);
    return adapterAvailable && states.count(uuid) > 0;
}

void BleDriver::setEventCallback(DriverEventCallback cb, void* userData) {
    std::lock_guard<std::mutex> lock(mutex);
    eventCallback = cb;
    eventUserData = userData;
}

} // namespace drivers
