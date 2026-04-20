/**
 * @file wifi.cpp
 * @brief Implementation of the Wi-Fi driver with HTTP commands for EaSync devices.
 * @param uuid Device identifier used for IP and route resolution.
 * @return Methods return true when the HTTP request succeeds.
 * @author Erick Radmann
 */

#include "wifi.hpp"
#include "payloadUtility.hpp"

#include <curl/curl.h>
#include <openssl/evp.h>
#include <sstream>
#include <functional>
#include <vector>
#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <chrono>
#include <unordered_set>
#include <array>
#include <fstream>

#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <fcntl.h>
#include <unistd.h>

namespace {

// ============================================================
// Crypto helpers
// ============================================================

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

static std::string bytesToBase64(const std::vector<uint8_t>& data) {
    static const char* kChars =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    std::string out;
    int i = 0;
    uint8_t c3[3], c4[4];
    size_t pos = 0, len = data.size();
    while (len--) {
        c3[i++] = data[pos++];
        if (i == 3) {
            c4[0] = (c3[0] & 0xfc) >> 2;
            c4[1] = ((c3[0] & 0x03) << 4) | ((c3[1] & 0xf0) >> 4);
            c4[2] = ((c3[1] & 0x0f) << 2) | ((c3[2] & 0xc0) >> 6);
            c4[3] =   c3[2] & 0x3f;
            for (int j = 0; j < 4; ++j) out += kChars[c4[j]];
            i = 0;
        }
    }
    if (i) {
        for (int j = i; j < 3; ++j) c3[j] = 0;
        c4[0] = (c3[0] & 0xfc) >> 2;
        c4[1] = ((c3[0] & 0x03) << 4) | ((c3[1] & 0xf0) >> 4);
        c4[2] = ((c3[1] & 0x0f) << 2) | ((c3[2] & 0xc0) >> 6);
        for (int j = 0; j < i + 1; ++j) out += kChars[c4[j]];
        while (i++ < 3) out += '=';
    }
    return out;
}

// AES-128-CBC with zero IV (Midea LAN v3)
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

// AES-128-ECB (Tuya LAN v3 – no IV)
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

// RFC 3986 percent-encoding
static std::string urlEncode(const std::string& s) {
    static const char kHex[] = "0123456789ABCDEF";
    std::string out;
    out.reserve(s.size() * 3);
    for (const unsigned char c : s) {
        if (std::isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~')
            out += static_cast<char>(c);
        else {
            out += '%';
            out += kHex[(c >> 4) & 0x0F];
            out += kHex[c & 0x0F];
        }
    }
    return out;
}

static std::string trim(const std::string& v) {
    const auto begin = v.find_first_not_of(" \t\r\n");
    if (begin == std::string::npos)
        return "";

    const auto end = v.find_last_not_of(" \t\r\n");
    return v.substr(begin, end - begin + 1);
}

static bool isLikelyHostToken(const std::string& value) {
    if (value.empty())
        return false;

    for (const unsigned char c : value) {
        if (std::isspace(c))
            return false;

        const bool ok = std::isalnum(c) || c == '.' || c == ':' || c == '-' || c == '_';
        if (!ok)
            return false;
    }

    return true;
}

static std::string normalizeEndpoint(std::string raw) {
    raw = trim(raw);
    if (raw.empty())
        return "";

    const std::string http = "http://";
    const std::string https = "https://";
    if (raw.rfind(http, 0) == 0)
        raw = raw.substr(http.size());
    else if (raw.rfind(https, 0) == 0)
        raw = raw.substr(https.size());

    auto slash = raw.find('/');
    if (slash != std::string::npos)
        raw = raw.substr(0, slash);

    raw = trim(raw);
    if (!isLikelyHostToken(raw))
        return "";

    return raw;
}

static std::string toLower(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return value;
}


static bool parseUint32Safe(const std::string& raw, uint32_t& outValue) {
    try {
        const unsigned long parsed = std::stoul(trim(raw));
        if (parsed > static_cast<unsigned long>(UINT32_MAX))
            return false;
        outValue = static_cast<uint32_t>(parsed);
        return true;
    } catch (...) {
        return false;
    }
}

static bool parseUint64Safe(const std::string& raw, uint64_t& outValue) {
    try {
        outValue = static_cast<uint64_t>(std::stoull(trim(raw)));
        return true;
    } catch (...) {
        return false;
    }
}

static bool parseFloatSafe(const std::string& raw, float& outValue) {
    try {
        outValue = std::stof(trim(raw));
        return true;
    } catch (...) {
        return false;
    }
}

static bool isMideaLike(const std::string& value) {
    const std::string lower = toLower(value);
    return lower.find("midea") != std::string::npos ||
           lower.find("msmart") != std::string::npos ||
           lower.find("nethome") != std::string::npos ||
           lower.find("net_ac") != std::string::npos;
}

static bool looksLikeMideaDiscoveryResponse(const std::vector<uint8_t>& packet) {
    if (packet.size() >= 2) {
        if (packet[0] == 0x5a && packet[1] == 0x5a)
            return true;
        if (packet[0] == 0x83 && packet[1] == 0x70)
            return true;
    }

    if (packet.size() >= 10) {
        if (packet[8] == 0x5a && packet[9] == 0x5a)
            return true;
    }

    return false;
}

static bool probeMideaDiscoveryAt(const std::string& host) {
    const std::array<uint8_t, 72> kMideaBroadcastMsg = {
        0x5a, 0x5a, 0x01, 0x11, 0x48, 0x00, 0x92, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x7f, 0x75, 0xbd, 0x6b, 0x3e, 0x4f, 0x8b, 0x76,
        0x2e, 0x84, 0x9c, 0x6e, 0x57, 0x8d, 0x65, 0x90,
        0x03, 0x6e, 0x9d, 0x43, 0x42, 0xa5, 0x0f, 0x1f,
        0x56, 0x9e, 0xb8, 0xec, 0x91, 0x8e, 0x92, 0xe5,
    };

    sockaddr_in dstAddr{};
    dstAddr.sin_family = AF_INET;
    if (inet_pton(AF_INET, host.c_str(), &dstAddr.sin_addr) != 1)
        return false;

    const std::array<int, 2> ports = {6445, 20086};
    for (int port : ports) {
        const int sock = socket(AF_INET, SOCK_DGRAM, 0);
        if (sock < 0)
            continue;

        timeval timeout{};
        timeout.tv_sec = 0;
        timeout.tv_usec = 180000;
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));

        dstAddr.sin_port = htons(static_cast<uint16_t>(port));
        const auto sent = sendto(
            sock,
            reinterpret_cast<const char*>(kMideaBroadcastMsg.data()),
            kMideaBroadcastMsg.size(),
            0,
            reinterpret_cast<sockaddr*>(&dstAddr),
            sizeof(dstAddr)
        );

        if (sent >= 0) {
            std::vector<uint8_t> recvBuf(512);
            sockaddr_in srcAddr{};
            socklen_t srcLen = sizeof(srcAddr);

            const auto received = recvfrom(
                sock,
                reinterpret_cast<char*>(recvBuf.data()),
                recvBuf.size(),
                0,
                reinterpret_cast<sockaddr*>(&srcAddr),
                &srcLen
            );

            close(sock);

            if (received > 0) {
                recvBuf.resize(static_cast<size_t>(received));
                if (looksLikeMideaDiscoveryResponse(recvBuf))
                    return true;
            }
        } else {
            close(sock);
        }
    }

    return false;
}

// ============================================================
// Samsung SmartThings
// ============================================================

static bool isSamsungLike(const std::string& value) {
    const std::string lower = toLower(value);
    return lower.find("samsung") != std::string::npos ||
           lower.find("smarthings") != std::string::npos ||  // common typo in SSIDs
           lower.find("smartthings") != std::string::npos ||
           lower.find("samsung_") != std::string::npos ||
           lower.find("sam_") != std::string::npos;
}

static bool looksLikeSamsungDiscoveryResponse(const std::vector<uint8_t>& packet) {
    // SmartThings LAN API returns JSON; a minimal positive signal is any
    // non-empty response on the control port.
    if (packet.size() >= 4 &&
        packet[0] == '{')   // JSON object opener
        return true;
    // SSDP notify from SmartThings hub begins with "NOTIFY" or "HTTP/1.1"
    const std::string s(packet.begin(), packet.end());
    return s.find("SmartThings") != std::string::npos ||
           s.find("SAMSUNG") != std::string::npos ||
           s.find("samsung") != std::string::npos;
}

static bool probeSamsungDiscoveryAt(const std::string& host) {
    // Samsung SmartThings hub listens on 55000 (LAN API).
    const std::array<uint16_t, 1> ports = {55000};

    for (uint16_t port : ports) {
        int sock = socket(AF_INET, SOCK_STREAM, 0);
        if (sock < 0)
            continue;

        timeval timeout{};
        timeout.tv_sec  = 0;
        timeout.tv_usec = 250000;
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

        sockaddr_in addr{};
        addr.sin_family = AF_INET;
        addr.sin_port   = htons(port);
        if (inet_pton(AF_INET, host.c_str(), &addr.sin_addr) != 1) {
            close(sock);
            continue;
        }

        if (::connect(sock, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) == 0) {
            // Send a minimal HTTP GET for the SmartThings LAN API info endpoint
            const std::string req =
                "GET /api/v1/hub HTTP/1.0\r\n"
                "Host: " + host + "\r\n"
                "Connection: close\r\n\r\n";
            send(sock, req.data(), req.size(), 0);

            std::vector<uint8_t> buf(512);
            const auto received = recv(sock, reinterpret_cast<char*>(buf.data()), buf.size(), 0);
            close(sock);

            if (received > 0) {
                buf.resize(static_cast<size_t>(received));
                if (looksLikeSamsungDiscoveryResponse(buf))
                    return true;
            }
        } else {
            close(sock);
        }
    }
    return false;
}

// ============================================================
// LG ThinQ
// ============================================================

static bool isLGLike(const std::string& value) {
    const std::string lower = toLower(value);
    return lower.find("lge_") != std::string::npos ||
           lower.find("lg_") != std::string::npos  ||
           lower.find("thinq") != std::string::npos ||
           lower.find("lg-") != std::string::npos;
}

static bool looksLikeLGDiscoveryResponse(const std::vector<uint8_t>& packet) {
    if (packet.size() < 4)
        return false;
    // LG ThinQ local API returns JSON with "result" or "returnCd"
    const std::string s(packet.begin(), packet.end());
    return s.find("returnCd") != std::string::npos ||
           s.find("result")   != std::string::npos ||
           s.find("thinq")    != std::string::npos ||
           s.find("LGE")      != std::string::npos;
}

static bool probeLGDiscoveryAt(const std::string& host) {
    // LG ThinQ local API: TCP 6444 (same port range as some Midea devices)
    // and a secondary HTTP endpoint on port 2878.
    const std::array<uint16_t, 2> ports = {6444, 2878};
    for (uint16_t port : ports) {
        const int sock = socket(AF_INET, SOCK_STREAM, 0);
        if (sock < 0)
            continue;

        timeval timeout{};
        timeout.tv_sec  = 0;
        timeout.tv_usec = 250000;
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

        sockaddr_in addr{};
        addr.sin_family = AF_INET;
        addr.sin_port   = htons(port);
        if (inet_pton(AF_INET, host.c_str(), &addr.sin_addr) != 1) {
            close(sock);
            continue;
        }

        if (::connect(sock, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) == 0) {
            const std::string req =
                "GET /DeviceInfo.xml HTTP/1.0\r\n"
                "Host: " + host + "\r\n"
                "Connection: close\r\n\r\n";
            send(sock, req.data(), req.size(), 0);

            std::vector<uint8_t> buf(512);
            const auto received = recv(sock, reinterpret_cast<char*>(buf.data()), buf.size(), 0);
            close(sock);

            if (received > 0) {
                buf.resize(static_cast<size_t>(received));
                if (looksLikeLGDiscoveryResponse(buf))
                    return true;
            }
        } else {
            close(sock);
        }
    }
    return false;
}

// ============================================================
// Electrolux / AEG / Frigidaire
// ============================================================

static bool isElectroluxLike(const std::string& value) {
    const std::string lower = toLower(value);
    return lower.find("electrolux") != std::string::npos ||
           lower.find("elux_") != std::string::npos ||
           lower.find("aeg_") != std::string::npos  ||
           lower.find("frigidaire") != std::string::npos ||
           lower.find("wellbeing") != std::string::npos;
}

static bool looksLikeElectroluxDiscoveryResponse(const std::vector<uint8_t>& packet) {
    if (packet.size() < 4)
        return false;
    const std::string s(packet.begin(), packet.end());
    return s.find("Electrolux") != std::string::npos ||
           s.find("electrolux") != std::string::npos ||
           s.find("AEG")        != std::string::npos ||
           s.find("wellbeing")  != std::string::npos ||
           // Generic positive: any 2xx HTTP response on the AP setup page
           (s.find("HTTP/1.") != std::string::npos && s.find("200") != std::string::npos);
}

static bool probeElectroluxDiscoveryAt(const std::string& host) {
    // Electrolux connected appliances expose a provisioning HTTP server on port 80
    // under /elux or /setup during AP mode.
    const std::array<uint16_t, 2> ports = {80, 8080};
    for (uint16_t port : ports) {
        const int sock = socket(AF_INET, SOCK_STREAM, 0);
        if (sock < 0)
            continue;

        timeval timeout{};
        timeout.tv_sec  = 0;
        timeout.tv_usec = 250000;
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

        sockaddr_in addr{};
        addr.sin_family = AF_INET;
        addr.sin_port   = htons(port);
        if (inet_pton(AF_INET, host.c_str(), &addr.sin_addr) != 1) {
            close(sock);
            continue;
        }

        if (::connect(sock, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) == 0) {
            const std::string req =
                "GET /elux/info HTTP/1.0\r\n"
                "Host: " + host + "\r\n"
                "Connection: close\r\n\r\n";
            send(sock, req.data(), req.size(), 0);

            std::vector<uint8_t> buf(512);
            const auto received = recv(sock, reinterpret_cast<char*>(buf.data()), buf.size(), 0);
            close(sock);

            if (received > 0) {
                buf.resize(static_cast<size_t>(received));
                if (looksLikeElectroluxDiscoveryResponse(buf))
                    return true;
            }
        } else {
            close(sock);
        }
    }
    return false;
}

// ============================================================
// Daikin
// ============================================================

static bool isDaikinLike(const std::string& value) {
    const std::string lower = toLower(value);
    return lower.find("daikin") != std::string::npos ||
           lower.find("dkin_") != std::string::npos  ||
           lower.find("daikin_") != std::string::npos;
}

static bool looksLikeDaikinDiscoveryResponse(const std::vector<uint8_t>& packet) {
    if (packet.size() < 4)
        return false;
    // Daikin's local HTTP API returns key=value strings like
    // "ret=OK,type=aircon,..."
    const std::string s(packet.begin(), packet.end());
    return s.find("ret=OK") != std::string::npos ||
           s.find("type=aircon") != std::string::npos ||
           s.find("daikin") != std::string::npos ||
           s.find("Daikin") != std::string::npos;
}

static bool probeDaikinDiscoveryAt(const std::string& host) {
    // Daikin adapters expose a plain HTTP server on port 80.
    // The canonical discovery endpoint is GET /common/basic_info
    const int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0)
        return false;

    timeval timeout{};
    timeout.tv_sec  = 0;
    timeout.tv_usec = 300000;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port   = htons(80);
    if (inet_pton(AF_INET, host.c_str(), &addr.sin_addr) != 1) {
        close(sock);
        return false;
    }

    if (::connect(sock, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) != 0) {
        close(sock);
        return false;
    }

    const std::string req =
        "GET /common/basic_info HTTP/1.0\r\n"
        "Host: " + host + "\r\n"
        "Connection: close\r\n\r\n";
    send(sock, req.data(), req.size(), 0);

    std::vector<uint8_t> buf(512);
    const auto received = recv(sock, reinterpret_cast<char*>(buf.data()), buf.size(), 0);
    close(sock);

    if (received > 0) {
        buf.resize(static_cast<size_t>(received));
        return looksLikeDaikinDiscoveryResponse(buf);
    }
    return false;
}

// ============================================================
// Tuya (generic — SmartLife / eWeLink-style)
// ============================================================

static bool isTuyaLike(const std::string& value) {
    const std::string lower = toLower(value);
    return lower.find("tuya") != std::string::npos  ||
           lower.find("smartlife") != std::string::npos ||
           lower.find("smart_life") != std::string::npos ||
           lower.find("beken_") != std::string::npos ||
           lower.find("ty_") != std::string::npos;
}

static bool looksLikeTuyaDiscoveryResponse(const std::vector<uint8_t>& packet) {
    if (packet.size() < 16)
        return false;
    // Tuya LAN protocol v3.x starts with a fixed 4-byte prefix 0x000055AA
    if (packet[0] == 0x00 && packet[1] == 0x00 &&
        packet[2] == 0x55 && packet[3] == 0xAA)
        return true;
    // Older v1 responses contain plain JSON with "devId"
    const std::string s(packet.begin(), packet.end());
    return s.find("devId") != std::string::npos ||
           s.find("gwId")  != std::string::npos;
}

static bool probeTuyaDiscoveryAt(const std::string& host) {
    const std::array<uint16_t, 1> ports = {6667}; // Try Tuya v3 first with encrypted payload

    const std::vector<uint8_t> localKey = {0x00}; // Real key should come from credentials, mock for discovery fallback

    // Tuya LAN v1/v2 discovery ping: 0x000055AA + header
    const std::vector<uint8_t> kTuyaPingPlain = {
        0x00, 0x00, 0x55, 0xAA,   // prefix
        0x00, 0x00, 0x00, 0x00,   // seq
        0x00, 0x00, 0x00, 0x12,   // cmd HEART_BEAT (0x09) — use ping cmd
        0x00, 0x00, 0x00, 0x0C,   // data length
        0x00, 0x00, 0xAA, 0x55,   // suffix
    };
    
    // Encrypt for v3
    std::vector<uint8_t> kTuyaPing = aes128EcbEncrypt(localKey, kTuyaPingPlain);
    if (kTuyaPing.empty()) {
        kTuyaPing = kTuyaPingPlain;
    }

    sockaddr_in dstAddr{};
    dstAddr.sin_family = AF_INET;
    if (inet_pton(AF_INET, host.c_str(), &dstAddr.sin_addr) != 1)
        return false;

    for (uint16_t port : ports) {
        const int sock = socket(AF_INET, SOCK_DGRAM, 0);
        if (sock < 0)
            continue;

        timeval timeout{};
        timeout.tv_sec  = 0;
        timeout.tv_usec = 200000;
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));

        dstAddr.sin_port = htons(port);
        sendto(sock,
               reinterpret_cast<const char*>(kTuyaPing.data()),
               kTuyaPing.size(),
               0,
               reinterpret_cast<sockaddr*>(&dstAddr),
               sizeof(dstAddr));

        std::vector<uint8_t> buf(256);
        sockaddr_in srcAddr{};
        socklen_t srcLen = sizeof(srcAddr);
        const auto received = recvfrom(sock,
                                       reinterpret_cast<char*>(buf.data()),
                                       buf.size(), 0,
                                       reinterpret_cast<sockaddr*>(&srcAddr),
                                       &srcLen);
        close(sock);

        if (received > 0) {
            buf.resize(static_cast<size_t>(received));
            if (looksLikeTuyaDiscoveryResponse(buf))
                return true;
        }
    }
    return false;
}

static bool isPrivateIPv4Octets(uint8_t o1, uint8_t o2) {

    if (o1 == 10)
        return true;
    if (o1 == 172 && o2 >= 16 && o2 <= 31)
        return true;
    if (o1 == 192 && o2 == 168)
        return true;
    return false;
}

static std::string routeWordToIPv4String(uint32_t routeWord) {
    const uint8_t o1 = static_cast<uint8_t>(routeWord & 0xFF);
    const uint8_t o2 = static_cast<uint8_t>((routeWord >> 8) & 0xFF);
    const uint8_t o3 = static_cast<uint8_t>((routeWord >> 16) & 0xFF);
    const uint8_t o4 = static_cast<uint8_t>((routeWord >> 24) & 0xFF);

    std::ostringstream ss;
    ss << static_cast<int>(o1) << "."
       << static_cast<int>(o2) << "."
       << static_cast<int>(o3) << "."
       << static_cast<int>(o4);
    return ss.str();
}

static std::vector<std::string> lookupProvisionCandidatesFromRoutes() {
    std::vector<std::string> out;

    std::ifstream routeFile("/proc/net/route");
    if (routeFile) {
        std::string line;
        std::getline(routeFile, line); // header

        while (std::getline(routeFile, line)) {
            std::istringstream iss(line);

            std::string iface;
            std::string destinationHex;
            std::string gatewayHex;
            std::string flagsHex;

            if (!(iss >> iface >> destinationHex >> gatewayHex >> flagsHex))
                continue;

            if (destinationHex != "00000000")
                continue;

            unsigned long gateway = 0;
            unsigned long flags = 0;
            try {
                gateway = std::stoul(gatewayHex, nullptr, 16);
                flags = std::stoul(flagsHex, nullptr, 16);
            } catch (...) {
                continue;
            }

            if ((flags & 0x2UL) == 0) // RTF_GATEWAY
                continue;
            if (gateway == 0)
                continue;

            const uint32_t gatewayRouteWord = static_cast<uint32_t>(gateway);
            const uint8_t gwO1 = static_cast<uint8_t>(gatewayRouteWord & 0xFF);
            const uint8_t gwO2 = static_cast<uint8_t>((gatewayRouteWord >> 8) & 0xFF);
            if (!isPrivateIPv4Octets(gwO1, gwO2))
                continue;

            out.push_back(routeWordToIPv4String(gatewayRouteWord));
        }
    }

    ifaddrs* ifaddr = nullptr;
    if (getifaddrs(&ifaddr) == 0 && ifaddr != nullptr) {
        for (ifaddrs* cur = ifaddr; cur != nullptr; cur = cur->ifa_next) {
            if (!cur->ifa_addr)
                continue;
            if (cur->ifa_addr->sa_family != AF_INET)
                continue;
            if ((cur->ifa_flags & IFF_LOOPBACK) != 0)
                continue;

            const sockaddr_in* sin = reinterpret_cast<const sockaddr_in*>(cur->ifa_addr);
            const uint32_t ip = ntohl(sin->sin_addr.s_addr);

            const uint8_t o1 = static_cast<uint8_t>((ip >> 24) & 0xFF);
            const uint8_t o2 = static_cast<uint8_t>((ip >> 16) & 0xFF);
            const uint8_t o3 = static_cast<uint8_t>((ip >> 8) & 0xFF);

            if (!isPrivateIPv4Octets(o1, o2))
                continue;

            std::ostringstream gw1;
            gw1 << static_cast<int>(o1) << "."
                << static_cast<int>(o2) << "."
                << static_cast<int>(o3) << ".1";
            out.push_back(gw1.str());

            std::ostringstream gw254;
            gw254 << static_cast<int>(o1) << "."
                  << static_cast<int>(o2) << "."
                  << static_cast<int>(o3) << ".254";
            out.push_back(gw254.str());
        }

        freeifaddrs(ifaddr);
    }

    return out;
}

static bool tcpPortReachable(const std::string& host, uint16_t port, int timeoutMs) {
    const int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0)
        return false;

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    if (inet_pton(AF_INET, host.c_str(), &addr.sin_addr) != 1) {
        close(sock);
        return false;
    }

    const int flags = fcntl(sock, F_GETFL, 0);
    if (flags >= 0)
        fcntl(sock, F_SETFL, flags | O_NONBLOCK);

    const int connectRes = ::connect(sock, reinterpret_cast<sockaddr*>(&addr), sizeof(addr));
    if (connectRes == 0) {
        close(sock);
        return true;
    }

    if (errno != EINPROGRESS) {
        close(sock);
        return false;
    }

    fd_set writeSet;
    FD_ZERO(&writeSet);
    FD_SET(sock, &writeSet);

    timeval tv{};
    tv.tv_sec = timeoutMs / 1000;
    tv.tv_usec = (timeoutMs % 1000) * 1000;

    const int sel = select(sock + 1, nullptr, &writeSet, nullptr, &tv);
    if (sel <= 0) {
        close(sock);
        return false;
    }

    int soError = 0;
    socklen_t len = sizeof(soError);
    getsockopt(sock, SOL_SOCKET, SO_ERROR, &soError, &len);
    close(sock);

    return soError == 0;
}

static std::string uuidToEnvSuffix(const std::string& uuid) {
    std::string out;
    out.reserve(uuid.size());
    for (const unsigned char c : uuid) {
        if (std::isalnum(c)) {
            out.push_back(static_cast<char>(std::toupper(c)));
        } else {
            out.push_back('_');
        }
    }
    return out;
}

static std::string readEnv(const std::string& key) {
    if (const char* v = std::getenv(key.c_str())) {
        return trim(v);
    }
    return "";
}

static std::string makeMideaCredentialEnvelope(const std::string& payload,
                                               const std::string& token,
                                               const std::string& key)
{
    std::vector<uint8_t> keyBytes = hexToBytes(key);
    std::vector<uint8_t> plainBytes(payload.begin(), payload.end());
    std::vector<uint8_t> encrypted = aes128CbcEncrypt(keyBytes, plainBytes);

    if (encrypted.empty()) {
        // Fallback or error case (should ideally not happen with valid key)
        encrypted = plainBytes;
    }

    std::stringstream ss;
    ss << "{"
       << "\"protocol\":\"midea_lan_v3\"," 
       << "\"token\":\"" << token << "\"," 
       << "\"key\":\"" << key << "\"," 
       << "\"payload\":\"" << bytesToBase64(encrypted) << "\""
       << "}";
    return ss.str();
}

static bool extractRawValue(const std::string& payload,
                            const std::vector<std::string>& keys,
                            std::string& outValue)
{
    for (const auto& key : keys) {
        const std::string quoted = "\"" + key + "\"";
        size_t keyPos = payload.find(quoted);
        if (keyPos == std::string::npos)
            continue;

        const size_t colon = payload.find(':', keyPos + quoted.size());
        if (colon == std::string::npos)
            continue;

        size_t start = payload.find_first_not_of(" \t\r\n", colon + 1);
        if (start == std::string::npos)
            continue;

        if (payload[start] == '"') {
            const size_t endQuote = payload.find('"', start + 1);
            if (endQuote == std::string::npos)
                continue;

            outValue = payload.substr(start + 1, endQuote - start - 1);
            return true;
        }

        const size_t tokenEnd = payload.find_first_of(",}\r\n", start);
        if (tokenEnd == std::string::npos)
            outValue = trim(payload.substr(start));
        else
            outValue = trim(payload.substr(start, tokenEnd - start));

        if (!outValue.empty())
            return true;
    }

    return false;
}

static bool parseBoolValue(const std::string& raw, bool& outValue) {
    const std::string lower = toLower(trim(raw));

    if (lower == "1" || lower == "true" || lower == "on" || lower == "lock") {
        outValue = true;
        return true;
    }

    if (lower == "0" || lower == "false" || lower == "off" || lower == "unlock") {
        outValue = false;
        return true;
    }

    return false;
}

static std::string endpointToBaseUrl(const std::string& endpoint) {
    const std::string trimmed = trim(endpoint);
    if (trimmed.empty())
        return "";

    if (trimmed.rfind("http://", 0) == 0 || trimmed.rfind("https://", 0) == 0)
        return trimmed;

    return "http://" + trimmed;
}

static std::string composeHttpUrl(const std::string& baseUrl, std::string routeOrTopic) {
    if (routeOrTopic.empty())
        return "";

    routeOrTopic = trim(routeOrTopic);
    if (routeOrTopic.empty())
        return "";

    if (routeOrTopic.rfind("http://", 0) == 0 || routeOrTopic.rfind("https://", 0) == 0)
        return routeOrTopic;

    if (routeOrTopic.front() != '/')
        routeOrTopic = "/" + routeOrTopic;

    if (!baseUrl.empty() && baseUrl.back() == '/')
        return baseUrl.substr(0, baseUrl.size() - 1) + routeOrTopic;

    return baseUrl + routeOrTopic;
}

static core::PayloadCommand buildCommandFromTemplate(
    const std::string& uuid,
    const std::string& capability,
    const std::string& valueJson,
    const std::string& fallbackJson
) {
    core::PayloadCommand fromTemplate = core::PayloadUtility::instance().createCommand(
        uuid,
        capability,
        valueJson
    );

    if (!fromTemplate.payload.empty() || !fromTemplate.topic.empty())
        return fromTemplate;

    core::PayloadCommand fallback;
    fallback.payload = fallbackJson;
    return fallback;
}

}

namespace drivers {

static size_t writeCallback(
    void* contents,
    size_t size,
    size_t nmemb,
    void* userp
) {
    size_t total = size * nmemb;
    std::string* str = static_cast<std::string*>(userp);
    str->append((char*)contents, total);
    return total;
}

WifiDriver::WifiDriver() {}

bool WifiDriver::init() {
    return curl_global_init(CURL_GLOBAL_ALL) == 0;
}

void WifiDriver::setEventCallback(
    DriverEventCallback cb,
    void* userData
) {
    eventCallback = cb;
    eventUserData = userData;
}

bool WifiDriver::connect(const std::string& uuid) {

    std::lock_guard<std::mutex> lock(mutex);

    if (states.count(uuid))
        return true;

    std::string ip;

    if (deviceIps.count(uuid) && !deviceIps[uuid].empty()) {
        ip = deviceIps[uuid];
    } else if (const char* env = std::getenv("EASYNC_WIFI_DEFAULT_ENDPOINT")) {
        ip = normalizeEndpoint(env);
    }

    deviceIps[uuid] = ip;
    states.emplace(uuid, CoreDeviceState{});

    return true;
}

void WifiDriver::onDeviceRegistered(
    const std::string& uuid,
    const std::string& brand,
    const std::string& model
) {
    const bool isMidea = isMideaLike(brand) || isMideaLike(model);
    const WifiVendorProfile profile = buildProfile(brand, model);
    const std::string endpoint = normalizeEndpoint(model);
    std::lock_guard<std::mutex> lock(mutex);
    deviceMideaProfile[uuid] = isMidea;
    deviceProfiles[uuid] = profile;
    if (!endpoint.empty())
        deviceIps[uuid] = endpoint;
}

void WifiDriver::onDeviceRemoved(const std::string& uuid) {
    std::lock_guard<std::mutex> lock(mutex);
    deviceIps.erase(uuid);
    states.erase(uuid);
    deviceMideaProfile.erase(uuid);
    deviceProfiles.erase(uuid);
    deviceCredentials.erase(uuid);
}

bool WifiDriver::setEndpoint(
    const std::string& uuid,
    const std::string& endpoint
) {
    const std::string normalized = normalizeEndpoint(endpoint);
    if (normalized.empty())
        return false;

    std::lock_guard<std::mutex> lock(mutex);
    if (!states.count(uuid))
        return false;

    deviceIps[uuid] = normalized;
    return true;
}

bool WifiDriver::setCredential(
    const std::string& uuid,
    const std::string& key,
    const std::string& value
) {
    const std::string k = toLower(trim(key));
    if (k.empty())
        return false;

    std::lock_guard<std::mutex> lock(mutex);
    if (!states.count(uuid))
        return false;

    deviceCredentials[uuid][k] = trim(value);
    return true;
}

bool WifiDriver::disconnect(const std::string& uuid) {

    std::lock_guard<std::mutex> lock(mutex);

    states.erase(uuid);
    deviceIps.erase(uuid);
    deviceMideaProfile.erase(uuid);
    deviceProfiles.erase(uuid);
    deviceCredentials.erase(uuid);

    return true;
}

WifiVendorProfile WifiDriver::buildProfile(const std::string& brand,
                                           const std::string& model) const
{
    WifiVendorProfile profile;

    const std::string b = toLower(brand);
    const std::string m = toLower(model);

    auto setHttp = [&profile](std::initializer_list<uint16_t> ports = {80, 8080, 8081}) {
        profile.transport = WifiTransportKind::Http;
        profile.ports.assign(ports.begin(), ports.end());
    };

    setHttp();

    if (isMideaLike(brand) || isMideaLike(model)) {
        profile.transport = WifiTransportKind::Mixed;
        profile.ports = {6444, 6445, 20086, 80, 8080};
        profile.mideaLike = true;
        return profile;
    }

    if (b.find("lifx") != std::string::npos) {
        profile.transport = WifiTransportKind::Udp;
        profile.ports = {56700};
        return profile;
    }

    // Tuya / SmartLife / eWeLink
    if (isTuyaLike(brand) || isTuyaLike(model)) {
        profile.transport = WifiTransportKind::Mixed;
        profile.ports = {6666, 6667, 6668, 6669, 80, 443};
        return profile;
    }

    // Samsung SmartThings
    if (brand == "Samsung" || isSamsungLike(model)) {
        profile.ports = {55000, 80, 443};
        profile.transport = WifiTransportKind::Mixed;
    } else if (brand == "LG" || isLGLike(model)) {
        profile.ports = {2000, 80, 443};
        profile.transport = WifiTransportKind::Http;
        return profile;
    }

    // Daikin
    if (isDaikinLike(brand) || isDaikinLike(model)) {
        profile.transport = WifiTransportKind::Http;
        profile.ports = {80, 30050};
        return profile;
    }

    // Electrolux / AEG / Frigidaire
    if (isElectroluxLike(brand) || isElectroluxLike(model)) {
        profile.transport = WifiTransportKind::Http;
        profile.ports = {80, 8080};
        return profile;
    }

    // Remaining known brands — generic Mixed HTTP
    if (b.find("nuki") != std::string::npos ||
        b.find("august") != std::string::npos ||
        b.find("schlage") != std::string::npos ||
        b.find("warmup") != std::string::npos ||
        b.find("heatmiser") != std::string::npos ||
        b.find("devi") != std::string::npos ||
        b.find("netatmo") != std::string::npos ||
        b.find("google nest") != std::string::npos ||
        b.find("mitsubishi") != std::string::npos ||
        b.find("gree") != std::string::npos ||
        b.find("panasonic") != std::string::npos ||
        b.find("bosch") != std::string::npos ||
        b.find("whirlpool") != std::string::npos ||
        b.find("tp-link") != std::string::npos ||
        b.find("yeelight") != std::string::npos ||
        b.find("eve") != std::string::npos ||
        b.find("somfy") != std::string::npos ||
        m.find("thermostat") != std::string::npos) {
        profile.transport = WifiTransportKind::Mixed;
        profile.ports = {80, 8080, 8081, 443};
        return profile;
    }

    return profile;
}

bool WifiDriver::tcpSend(const std::string& host, uint16_t port, const std::string& payload) {
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0)
        return false;

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    if (inet_pton(AF_INET, host.c_str(), &addr.sin_addr) != 1) {
        close(sock);
        return false;
    }

    timeval timeout{};
    timeout.tv_sec = 0;
    timeout.tv_usec = 450000;
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));

    if (::connect(sock, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) != 0) {
        close(sock);
        return false;
    }

    size_t totalSent = 0;
    bool success = true;
    while (totalSent < payload.size()) {
        const ssize_t sent = send(sock, payload.data() + totalSent, payload.size() - totalSent, 0);
        if (sent <= 0) {
            success = false;
            break;
        }
        totalSent += static_cast<size_t>(sent);
    }
    
    close(sock);
    return success;
}

bool WifiDriver::udpSend(const std::string& host, uint16_t port, const std::string& payload) {
    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0)
        return false;

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    if (inet_pton(AF_INET, host.c_str(), &addr.sin_addr) != 1) {
        close(sock);
        return false;
    }

    const ssize_t sent = sendto(
        sock,
        payload.data(),
        payload.size(),
        0,
        reinterpret_cast<sockaddr*>(&addr),
        sizeof(addr)
    );
    close(sock);
    return sent == static_cast<ssize_t>(payload.size());
}

bool WifiDriver::tryVendorTransports(const std::string& uuid,
                                     const std::string& endpoint,
                                     const std::string& payload)
{
    WifiVendorProfile profile;
    std::unordered_map<std::string, std::string> credentials;
    {
        std::lock_guard<std::mutex> lock(mutex);
        auto it = deviceProfiles.find(uuid);
        if (it == deviceProfiles.end())
            return false;
        profile = it->second;

        auto credIt = deviceCredentials.find(uuid);
        if (credIt != deviceCredentials.end())
            credentials = credIt->second;
    }

    const std::string host = normalizeEndpoint(endpoint);
    if (host.empty())
        return false;

    if (profile.ports.empty())
        return false;

    if (profile.mideaLike) {
        std::string token;
        std::string key;

        auto itToken = credentials.find("token");
        auto itKey = credentials.find("key");
        if (itToken != credentials.end()) token = trim(itToken->second);
        if (itKey != credentials.end()) key = trim(itKey->second);

        const std::string uuidSuffix = uuidToEnvSuffix(uuid);
        if (token.empty()) token = readEnv("EASYNC_MIDEA_TOKEN_" + uuidSuffix);
        if (key.empty()) key = readEnv("EASYNC_MIDEA_KEY_" + uuidSuffix);
        if (token.empty()) token = readEnv("EASYNC_MIDEA_TOKEN");
        if (key.empty()) key = readEnv("EASYNC_MIDEA_KEY");

        if (!token.empty() && !key.empty()) {
            const std::string enveloped = makeMideaCredentialEnvelope(payload, token, key);
            if (tcpSend(host, 6444, enveloped) || tcpSend(host, 6445, enveloped))
                return true;
        }
    }

    const auto tryTcpPorts = [&]() {
        for (const auto port : profile.ports) {
            if (tcpSend(host, port, payload))
                return true;
        }
        return false;
    };

    const auto tryUdpPorts = [&]() {
        for (const auto port : profile.ports) {
            if (udpSend(host, port, payload))
                return true;
        }
        return false;
    };

    switch (profile.transport) {
        case WifiTransportKind::Tcp:
            return tryTcpPorts();
        case WifiTransportKind::Udp:
            return tryUdpPorts();
        case WifiTransportKind::Mixed:
            return tryTcpPorts() || tryUdpPorts();
        case WifiTransportKind::Http:
        default:
            return false;
    }
}

bool WifiDriver::provisionWifi(
    const std::string& uuid,
    const std::string& ssid,
    const std::string& password,
    std::string* outError
) {
    if (ssid.empty()) {
        if (outError)
            *outError = "SSID is empty";
        return false;
    }

    std::vector<std::string> ips;
    bool mideaProfile = false;
    WifiVendorProfile vendorProfile;

    {
        std::lock_guard<std::mutex> lock(mutex);
        if (deviceIps.count(uuid) && !deviceIps[uuid].empty()) {
            const std::string normalized = normalizeEndpoint(deviceIps[uuid]);
            if (!normalized.empty())
                ips.push_back(normalized);
        }
        mideaProfile = deviceMideaProfile.count(uuid) ? deviceMideaProfile[uuid] : false;
        auto profIt = deviceProfiles.find(uuid);
        if (profIt != deviceProfiles.end())
            vendorProfile = profIt->second;
    }

    if (const char* env = std::getenv("EASYNC_WIFI_PROVISION_ENDPOINT")) {
        const std::string normalized = normalizeEndpoint(env);
        if (!normalized.empty())
            ips.push_back(normalized);
    }

    const auto routeCandidates = lookupProvisionCandidatesFromRoutes();
    ips.insert(ips.end(), routeCandidates.begin(), routeCandidates.end());

    // Keep known SoftAP defaults as low-priority fallback candidates even when route lookup succeeds.
    ips.push_back("192.168.4.1");
    ips.push_back("192.168.8.1");
    ips.push_back("192.168.10.1");
    ips.push_back("192.168.0.1");
    ips.push_back("192.168.1.1");
    ips.push_back("10.0.0.1");
    ips.push_back("10.10.100.254");

    std::vector<std::string> orderedIps;
    orderedIps.reserve(ips.size());
    std::unordered_set<std::string> seenIps;

    for (const auto& ip : ips) {
        if (ip.empty())
            continue;
        if (seenIps.insert(ip).second)
            orderedIps.push_back(ip);
    }

    ips = std::move(orderedIps);

    // ----------------------------------------------------------
    // Probe candidate IPs with the brand-specific discovery
    // protocol to float responsive hosts to the front.
    // ----------------------------------------------------------
    {
        using ProbeFunc = bool(*)(const std::string&);
        ProbeFunc probeFunc = nullptr;

        // Derive the right probe from the port fingerprint in vendorProfile.
        bool hasSamsungPort = false, hasLGPort = false,
             hasDaikinPort = false,  hasTuyaPort = false;
        for (uint16_t p : vendorProfile.ports) {
            if (p == 55000)              hasSamsungPort = true;
            if (p == 2000)               hasLGPort      = true;
            if (p == 30050)              hasDaikinPort  = true;
            if (p == 6666 || p == 6667)  hasTuyaPort    = true;
        }

        if      (mideaProfile)    probeFunc = probeMideaDiscoveryAt;
        else if (hasSamsungPort)  probeFunc = probeSamsungDiscoveryAt;
        else if (hasLGPort)       probeFunc = probeLGDiscoveryAt;
        else if (hasDaikinPort)   probeFunc = probeDaikinDiscoveryAt;
        else if (hasTuyaPort)     probeFunc = probeTuyaDiscoveryAt;
        // Electrolux uses port 80 which overlaps generics — probe is skipped;
        // probeElectroluxDiscoveryAt is called implicitly via the HTTP loop.

        if (probeFunc) {
            std::vector<std::string> responsive;
            std::vector<std::string> others;
            responsive.reserve(ips.size());
            others.reserve(ips.size());
            for (const auto& ip : ips) {
                if (probeFunc(ip))
                    responsive.push_back(ip);
                else
                    others.push_back(ip);
            }
            if (!responsive.empty()) {
                responsive.insert(responsive.end(), others.begin(), others.end());
                ips = std::move(responsive);
            }
        }
    }

    // ----------------------------------------------------------
    // Build provisioning route list — brand-specific routes first
    // ----------------------------------------------------------
    std::vector<std::string> routes;

    // Daikin: /common/set_wifi_setting  (port 30050 in profile = Daikin)
    {
        bool hasDaikin = false;
        for (uint16_t p : vendorProfile.ports) if (p == 30050) { hasDaikin = true; break; }
        if (hasDaikin) {
            routes.push_back("/common/set_wifi_setting");
            routes.push_back("/aircon/set_control_info");
        }
    }
    // Samsung SmartThings
    if ([&]{ for (uint16_t p : vendorProfile.ports) if (p == 55000) return true; return false; }()) {
        routes.push_back("/api/v1/wifi");
        routes.push_back("/api/v1/setup/wifi");
    }
    // LG ThinQ
    if ([&]{ for (uint16_t p : vendorProfile.ports) if (p == 2000) return true; return false; }()) {
        routes.push_back("/deviceControl");
        routes.push_back("/device/wifi");
    }
    // Electrolux
    routes.push_back("/elux/wifi");
    routes.push_back("/setup/wifi");
    // Generic fallbacks
    routes.push_back("/provision");
    routes.push_back("/wifi/provision");
    routes.push_back("/wifi");
    routes.push_back("/wifi_config");
    routes.push_back("/config/wifi");
    routes.push_back("/network");
    routes.push_back("/network/config");
    routes.push_back("/goform/DeviceConfig");
    routes.push_back("/cgi-bin/luci");

    std::vector<std::string> payloads;
    {
        std::stringstream ss;
        ss << "{ \"ssid\": \"" << ssid << "\", \"password\": \"" << password << "\" }";
        payloads.push_back(ss.str());
    }
    {
        std::stringstream ss;
        ss << "{ \"ssid\": \"" << ssid << "\", \"pass\": \"" << password << "\" }";
        payloads.push_back(ss.str());
    }
    {
        std::stringstream ss;
        ss << "{ \"wifi_ssid\": \"" << ssid << "\", \"wifi_password\": \"" << password << "\" }";
        payloads.push_back(ss.str());
    }
    {
        std::stringstream ss;
        ss << "{ \"network\": { \"ssid\": \"" << ssid
           << "\", \"password\": \"" << password << "\" } }";
        payloads.push_back(ss.str());
    }
    {
        std::stringstream ss;
        ss << "{ \"sta_ssid\": \"" << ssid << "\", \"sta_password\": \"" << password << "\" }";
        payloads.push_back(ss.str());
    }
    {
        std::stringstream ss;
        ss << "{ \"ap\": { \"ssid\": \"" << ssid
           << "\", \"password\": \"" << password << "\" } }";
        payloads.push_back(ss.str());
    }

    std::vector<std::string> formPayloads;
    {
        std::stringstream ss;
        ss << "ssid=" << urlEncode(ssid) << "&password=" << urlEncode(password);
        formPayloads.push_back(ss.str());
    }
    {
        std::stringstream ss;
        ss << "wifi_ssid=" << urlEncode(ssid) << "&wifi_password=" << urlEncode(password);
        formPayloads.push_back(ss.str());
    }

    std::string lastAttempt;
    std::vector<std::string> attemptedEndpoints;
    attemptedEndpoints.reserve(ips.size());
    const auto start = std::chrono::steady_clock::now();
    const auto deadline = start + std::chrono::seconds(8);
    int globalBudget = 40;
    bool globalExhausted = false;

    for (const auto& ip : ips) {
        const std::string baseUrl = endpointToBaseUrl(ip);
        if (baseUrl.empty())
            continue;

        attemptedEndpoints.push_back(ip);

        const bool endpointReachable =
            tcpPortReachable(ip, 80, 450) ||
            tcpPortReachable(ip, 8080, 450) ||
            tcpPortReachable(ip, 443, 450);

        int endpointBudget = endpointReachable ? 12 : 4;
        bool endpointExhausted = false;

        std::vector<std::string> headers;
        bool isSamsungProfile = false;
        for (uint16_t p : vendorProfile.ports) {
            if (p == 55000) { isSamsungProfile = true; break; }
        }
        if (isSamsungProfile) {
            std::string patToken = readEnv("EASYNC_SAMSUNG_PAT");
            if (!patToken.empty()) {
                headers.push_back("Authorization: Bearer " + patToken);
            }
        }

        for (const auto& route : routes) {
            const std::string url = composeHttpUrl(baseUrl, route);
            if (url.empty())
                continue;

            for (const auto& payload : payloads) {
                if (std::chrono::steady_clock::now() >= deadline || globalBudget <= 0) {
                    globalExhausted = true;
                    break;
                }
                if (endpointBudget <= 0) {
                    endpointExhausted = true;
                    break;
                }
                globalBudget--;
                endpointBudget--;

                lastAttempt = "POST " + url + " (json)";
                std::string trace;
                if (httpPost(url, payload, "application/json", "POST", &trace, headers))
                    return true;
                if (!trace.empty())
                    lastAttempt += " -> " + trace;

                if (std::chrono::steady_clock::now() >= deadline || globalBudget <= 0) {
                    globalExhausted = true;
                    break;
                }
                if (endpointBudget <= 0) {
                    endpointExhausted = true;
                    break;
                }
                globalBudget--;
                endpointBudget--;

                lastAttempt = "PUT " + url + " (json)";
                trace.clear();
                if (httpPost(url, payload, "application/json", "PUT", &trace, headers))
                    return true;
                if (!trace.empty())
                    lastAttempt += " -> " + trace;
            }

            if (globalExhausted || endpointExhausted)
                break;

            for (const auto& payload : formPayloads) {
                if (std::chrono::steady_clock::now() >= deadline || globalBudget <= 0) {
                    globalExhausted = true;
                    break;
                }
                if (endpointBudget <= 0) {
                    endpointExhausted = true;
                    break;
                }
                globalBudget--;
                endpointBudget--;

                lastAttempt = "POST " + url + " (form)";
                std::string trace;
                if (httpPost(
                        url,
                        payload,
                        "application/x-www-form-urlencoded",
                        "POST",
                        &trace,
                        headers
                    )) {
                    return true;
                }
                if (!trace.empty())
                    lastAttempt += " -> " + trace;

                if (std::chrono::steady_clock::now() >= deadline || globalBudget <= 0) {
                    globalExhausted = true;
                    break;
                }
                if (endpointBudget <= 0) {
                    endpointExhausted = true;
                    break;
                }
                globalBudget--;
                endpointBudget--;

                lastAttempt = "PUT " + url + " (form)";
                trace.clear();
                if (httpPost(
                        url,
                        payload,
                        "application/x-www-form-urlencoded",
                        "PUT",
                        &trace,
                        headers
                    )) {
                    return true;
                }
                if (!trace.empty())
                    lastAttempt += " -> " + trace;
            }

            if (globalExhausted || endpointExhausted)
                break;
        }

        if (globalExhausted)
            break;
    }

    if (outError) {
        if (globalExhausted)
            *outError = "Provisioning attempt budget exceeded. Last attempt: " + lastAttempt;
        else if (!lastAttempt.empty())
            *outError = "No provisioning endpoint accepted credentials. Last attempt: " + lastAttempt;
        else {
            std::ostringstream ss;
            ss << "No valid provisioning endpoint candidate found";
            if (!attemptedEndpoints.empty()) {
                ss << ". Candidates: ";
                for (size_t i = 0; i < attemptedEndpoints.size(); ++i) {
                    if (i != 0)
                        ss << ", ";
                    ss << attemptedEndpoints[i];
                }
            }
            *outError = ss.str();
        }
    }

    return false;
}

bool WifiDriver::setPower(const std::string& uuid, bool value) {

    std::string ip;

    {
        std::lock_guard<std::mutex> lock(mutex);
        if (!states.count(uuid))
            return false;
        ip = deviceIps[uuid];
    }

    std::stringstream ss;
    ss << "{ \"power\": " << (value ? "true" : "false") << " }";

    return postCapabilityCommand(
        uuid,
        ip,
        "power",
        value ? "true" : "false",
        ss.str(),
        {"/power", "/set/power", "/device/" + uuid + "/set"}
    );
}

bool WifiDriver::setBrightness(const std::string& uuid, uint32_t value) {

    std::string ip;

    {
        std::lock_guard<std::mutex> lock(mutex);
        if (!states.count(uuid))
            return false;
        ip = deviceIps[uuid];
    }

    std::stringstream ss;
    ss << "{ \"brightness\": " << value << " }";

    return postCapabilityCommand(
        uuid,
        ip,
        "brightness",
        std::to_string(value),
        ss.str(),
        {"/brightness", "/set/brightness", "/device/" + uuid + "/set"}
    );
}

bool WifiDriver::setColor(const std::string& uuid, uint32_t rgb) {

    std::string ip;

    {
        std::lock_guard<std::mutex> lock(mutex);
        if (!states.count(uuid))
            return false;
        ip = deviceIps[uuid];
    }

    std::stringstream ss;
    ss << "{ \"color\": " << rgb << " }";

    return postCapabilityCommand(
        uuid,
        ip,
        "color",
        std::to_string(rgb),
        ss.str(),
        {"/color", "/set/color", "/device/" + uuid + "/set"}
    );
}

bool WifiDriver::setTemperature(const std::string& uuid, float value) {

    std::string ip;

    {
        std::lock_guard<std::mutex> lock(mutex);
        if (!states.count(uuid))
            return false;
        ip = deviceIps[uuid];
    }

    std::stringstream ss;
    ss << "{ \"temperature\": " << value << " }";

    return postCapabilityCommand(
        uuid,
        ip,
        "temperature",
        std::to_string(value),
        ss.str(),
        {"/temperature", "/set/temperature", "/device/" + uuid + "/set"}
    );
}

bool WifiDriver::setTemperatureFridge(const std::string& uuid, float value) {

    std::string ip;

    {
        std::lock_guard<std::mutex> lock(mutex);
        if (!states.count(uuid))
            return false;
        ip = deviceIps[uuid];
    }

    std::stringstream ss;
    ss << "{ \"temperature_fridge\": " << value << " }";

    return postCapabilityCommand(
        uuid,
        ip,
        "temperature_fridge",
        std::to_string(value),
        ss.str(),
        {
            "/temperature_fridge",
            "/temperatureFridge",
            "/set/temperature_fridge",
            "/device/" + uuid + "/set"
        }
    );
}

bool WifiDriver::setTemperatureFreezer(const std::string& uuid, float value) {

    std::string ip;

    {
        std::lock_guard<std::mutex> lock(mutex);
        if (!states.count(uuid))
            return false;
        ip = deviceIps[uuid];
    }

    std::stringstream ss;
    ss << "{ \"temperature_freezer\": " << value << " }";

    return postCapabilityCommand(
        uuid,
        ip,
        "temperature_freezer",
        std::to_string(value),
        ss.str(),
        {
            "/temperature_freezer",
            "/temperatureFreezer",
            "/set/temperature_freezer",
            "/device/" + uuid + "/set"
        }
    );
}

bool WifiDriver::setTime(const std::string& uuid, uint64_t value) {

    std::string ip;

    {
        std::lock_guard<std::mutex> lock(mutex);
        if (!states.count(uuid))
            return false;
        ip = deviceIps[uuid];
    }

    std::stringstream ss;
    ss << "{ \"timestamp\": " << value << " }";

    return postCapabilityCommand(
        uuid,
        ip,
        "time",
        std::to_string(value),
        ss.str(),
        {"/timestamp", "/time", "/set/time", "/device/" + uuid + "/set"}
    );
}

bool WifiDriver::setColorTemperature(const std::string& uuid, uint32_t value) {

    std::string ip;

    {
        std::lock_guard<std::mutex> lock(mutex);
        if (!states.count(uuid))
            return false;
        ip = deviceIps[uuid];
    }

    std::stringstream ss;
    ss << "{ \"colorTemperature\": " << value << " }";

    return postCapabilityCommand(
        uuid,
        ip,
        "colorTemperature",
        std::to_string(value),
        ss.str(),
        {
            "/colorTemperature",
            "/color_temperature",
            "/set/colorTemperature",
            "/device/" + uuid + "/set"
        }
    );
}

bool WifiDriver::setLock(const std::string& uuid, bool value) {

    std::string ip;

    {
        std::lock_guard<std::mutex> lock(mutex);
        if (!states.count(uuid))
            return false;
        ip = deviceIps[uuid];
    }

    std::stringstream ss;
    ss << "{ \"lock\": " << (value ? "true" : "false") << " }";

    return postCapabilityCommand(
        uuid,
        ip,
        "lock",
        value ? "true" : "false",
        ss.str(),
        {"/lock", "/set/lock", "/device/" + uuid + "/set"}
    );
}

bool WifiDriver::setMode(const std::string& uuid, uint32_t value) {

    std::string ip;

    {
        std::lock_guard<std::mutex> lock(mutex);
        if (!states.count(uuid))
            return false;
        ip = deviceIps[uuid];
    }

    const auto modeOptions = core::PayloadUtility::instance().modeOptionsForDevice(uuid);
    const bool hasLabel = value < modeOptions.size();
    const std::string modeValueJson = hasLabel
        ? ("\"" + modeOptions[value] + "\"")
        : std::to_string(value);

    std::stringstream ss;
    if (hasLabel)
        ss << "{ \"mode\": \"" << modeOptions[value] << "\" }";
    else
        ss << "{ \"mode\": " << value << " }";

    return postCapabilityCommand(
        uuid,
        ip,
        "mode",
        modeValueJson,
        ss.str(),
        {"/mode", "/set/mode", "/device/" + uuid + "/set"}
    );
}

bool WifiDriver::setPosition(const std::string& uuid, float value) {

    std::string ip;

    {
        std::lock_guard<std::mutex> lock(mutex);
        if (!states.count(uuid))
            return false;
        ip = deviceIps[uuid];
    }

    std::stringstream ss;
    ss << "{ \"position\": " << value << " }";

    return postCapabilityCommand(
        uuid,
        ip,
        "position",
        std::to_string(value),
        ss.str(),
        {"/position", "/set/position", "/device/" + uuid + "/set"}
    );
}

bool WifiDriver::getState(
    const std::string& uuid,
    CoreDeviceState& outState
) {

    std::string ip;

    {
        std::lock_guard<std::mutex> lock(mutex);
        if (!states.count(uuid))
            return false;
        ip = deviceIps[uuid];
    }

    const std::string baseUrl = endpointToBaseUrl(ip);

    std::string response;
    bool ok = false;
    const std::vector<std::string> statePaths = {
        "/state",
        "/api/state",
        "/status",
        "/device/" + uuid + "/state"
    };

    for (const auto& route : statePaths) {
        response.clear();
        if (httpGet(composeHttpUrl(baseUrl, route), response)) {
            ok = true;
            break;
        }
    }

    if (ok)
        parseState(uuid, response);

    {
        std::lock_guard<std::mutex> lock(mutex);
        outState = states[uuid];
    }

    return ok;
}

bool WifiDriver::isAvailable(const std::string& uuid) {
    std::string ip;

    {
        std::lock_guard<std::mutex> lock(mutex);
        if (!states.count(uuid))
            return false;
        ip = deviceIps[uuid];
    }

    const std::string baseUrl = endpointToBaseUrl(ip);

    std::string response;
    return httpGet(composeHttpUrl(baseUrl, "/state"), response) ||
           httpGet(composeHttpUrl(baseUrl, "/api/state"), response) ||
           httpGet(composeHttpUrl(baseUrl, "/health"), response) ||
           httpGet(composeHttpUrl(baseUrl, "/"), response);
}

bool WifiDriver::postCapabilityCommand(
    const std::string& uuid,
    const std::string& endpoint,
    const std::string& capability,
    const std::string& valueJson,
    const std::string& fallbackJson,
    const std::vector<std::string>& fallbackPaths
) {
    const std::string baseUrl = endpointToBaseUrl(endpoint);
    if (baseUrl.empty())
        return false;

    auto command = buildCommandFromTemplate(uuid, capability, valueJson, fallbackJson);

    std::string payload = command.payload.empty() ? fallbackJson : command.payload;
    const std::string method = command.method.empty() ? "POST" : command.method;
    const std::string contentType = command.contentType.empty()
        ? "application/json"
        : command.contentType;

    if (!command.topic.empty()) {
        const std::string url = composeHttpUrl(baseUrl, command.topic);
        if (!url.empty() && httpPost(url, payload, contentType, method))
            return true;
    }

    for (const auto& route : fallbackPaths) {
        const std::string url = composeHttpUrl(baseUrl, route);
        if (!url.empty() && httpPost(url, payload))
            return true;
    }

    if (tryVendorTransports(uuid, endpoint, payload))
        return true;

    return false;
}

bool WifiDriver::httpPost(
    const std::string& url,
    const std::string& body,
    const std::string& contentType,
    const std::string& method,
    std::string* outTrace,
    const std::vector<std::string>& extraHeaders
) {
    CURL* curl = curl_easy_init();
    if (!curl)
        return false;

    struct curl_slist* headers = nullptr;
    const std::string contentTypeHeader = "Content-Type: " + contentType;
    headers = curl_slist_append(headers, contentTypeHeader.c_str());
    headers = curl_slist_append(headers, "Accept: application/json, text/plain, */*");
    for (const auto& header : extraHeaders) {
        headers = curl_slist_append(headers, header.c_str());
    }

    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "EaSync/1.0 (Provisioning)");
    if (!method.empty() && method != "POST")
        curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, method.c_str());
    curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT_MS, 350L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, 1200L);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);

    char errorBuffer[CURL_ERROR_SIZE];
    errorBuffer[0] = '\0';
    curl_easy_setopt(curl, CURLOPT_ERRORBUFFER, errorBuffer);

    CURLcode res = curl_easy_perform(curl);

    long statusCode = 0;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &statusCode);

    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);

    if (res != CURLE_OK) {
        if (outTrace) {
            if (errorBuffer[0] != '\0')
                *outTrace = std::string("curl=") + errorBuffer;
            else
                *outTrace = std::string("curl=") + curl_easy_strerror(res);
        }
        return false;
    }

    if (outTrace) {
        *outTrace = "http=" + std::to_string(statusCode);
    }

    return statusCode >= 200 && statusCode < 300;
}

bool WifiDriver::httpGet(
    const std::string& url,
    std::string& out
) {
    CURL* curl = curl_easy_init();
    if (!curl)
        return false;

    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, writeCallback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &out);
    curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT_MS, 350L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, 900L);

    CURLcode res = curl_easy_perform(curl);

    long statusCode = 0;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &statusCode);

    curl_easy_cleanup(curl);

    if (res != CURLE_OK)
        return false;

    return statusCode >= 200 && statusCode < 500;
}

void WifiDriver::parseState(
    const std::string& uuid,
    const std::string& json
) {

    CoreDeviceState newState;
    CoreDeviceState oldState;

    {
        std::lock_guard<std::mutex> lock(mutex);

        auto it = states.find(uuid);
        if (it == states.end())
            return;

        oldState = it->second;
        newState = oldState;

        std::string raw;

        if (extractRawValue(json, {"power", "state"}, raw)) {
            bool parsed = false;
            if (parseBoolValue(raw, parsed))
                newState.power = parsed;
        }

        if (extractRawValue(json, {"brightness"}, raw)) {
            uint32_t parsed = 0;
            if (parseUint32Safe(raw, parsed))
                newState.brightness = parsed;
        }

        if (extractRawValue(json, {"color"}, raw)) {
            uint32_t parsed = 0;
            if (parseUint32Safe(raw, parsed))
                newState.color = parsed;
        }

        if (extractRawValue(json, {"temperature"}, raw)) {
            float parsed = 0.0f;
            if (parseFloatSafe(raw, parsed))
                newState.temperature = parsed;
        }

        if (extractRawValue(json, {"temperature_fridge", "temperatureFridge"}, raw)) {
            float parsed = 0.0f;
            if (parseFloatSafe(raw, parsed))
                newState.temperatureFridge = parsed;
        }

        if (extractRawValue(json, {"temperature_freezer", "temperatureFreezer"}, raw)) {
            float parsed = 0.0f;
            if (parseFloatSafe(raw, parsed))
                newState.temperatureFreezer = parsed;
        }

        if (extractRawValue(json, {"timestamp", "time"}, raw)) {
            uint64_t parsed = 0;
            if (parseUint64Safe(raw, parsed))
                newState.timestamp = parsed;
        }

        if (extractRawValue(json, {"colorTemperature", "color_temperature"}, raw)) {
            uint32_t parsed = 0;
            if (parseUint32Safe(raw, parsed))
                newState.colorTemperature = parsed;
        }

        if (extractRawValue(json, {"lock"}, raw)) {
            bool parsed = false;
            if (parseBoolValue(raw, parsed))
                newState.lock = parsed;
        }

        if (extractRawValue(json, {"mode"}, raw)) {
            const auto options = core::PayloadUtility::instance().modeOptionsForDevice(uuid);
            const std::string lowered = toLower(trim(raw));

            bool parsedNumeric = parseUint32Safe(lowered, newState.mode);

            if (!parsedNumeric) {
                for (size_t i = 0; i < options.size(); ++i) {
                    if (toLower(options[i]) == lowered) {
                        newState.mode = static_cast<uint32_t>(i);
                        break;
                    }
                }
            }
        }

        if (extractRawValue(json, {"position"}, raw)) {
            float parsed = 0.0f;
            if (parseFloatSafe(raw, parsed))
                newState.position = parsed;
        }

        bool changed =
            newState.power != oldState.power ||
            newState.brightness != oldState.brightness ||
            newState.color != oldState.color ||
            newState.temperature != oldState.temperature ||
            newState.temperatureFridge != oldState.temperatureFridge ||
            newState.temperatureFreezer != oldState.temperatureFreezer ||
            newState.timestamp != oldState.timestamp ||
            newState.colorTemperature != oldState.colorTemperature ||
            newState.lock != oldState.lock ||
            newState.mode != oldState.mode ||
            newState.position != oldState.position;

        if (!changed)
            return;

        it->second = newState;
    }

    notifyStateChange(uuid, newState);
}

void WifiDriver::notifyStateChange(
    const std::string& uuid,
    const CoreDeviceState& newState
) {
    if (eventCallback) {
        eventCallback(uuid, newState, eventUserData);
    }
}

}