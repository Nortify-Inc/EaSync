#include "engine.hpp"

#include <chrono>
#include <cstdint>
#include <iostream>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

namespace {

struct Args {
    std::string data_dir;
    int decode_every = 4;
    bool sync_mode = false;
};

Args parse_args(int argc, char** argv) {
    Args args;
    for (int i = 1; i < argc; ++i) {
        const std::string cur = argv[i];
        if (cur == "--sync") {
            args.sync_mode = true;
        } else if (cur == "--data-dir" && i + 1 < argc) {
            args.data_dir = argv[++i];
        } else if (cur == "--decode-every" && i + 1 < argc) {
            args.decode_every = std::max(1, std::stoi(argv[++i]));
        }
    }
    return args;
}

int estimate_tokens(const std::string& text) {
    std::istringstream iss(text);
    int count = 0;
    std::string word;
    while (iss >> word) {
        ++count;
    }
    return count;
}

void run_sync_once(const std::string& prompt) {
    std::vector<char> out(8192, '\0');
    const auto t0 = std::chrono::steady_clock::now();
    const int rc = ai_query(nullptr, prompt.c_str(), out.data(), static_cast<uint32_t>(out.size()));
    const auto t1 = std::chrono::steady_clock::now();
    const auto total_ms = std::chrono::duration_cast<std::chrono::milliseconds>(t1 - t0).count();

    if (rc != 0) {
        std::cout << "[error] ai_query rc=" << rc << "\n";
        return;
    }

    const std::string text(out.data());
    const int tokens = estimate_tokens(text);
    const double secs = std::max(0.001, static_cast<double>(total_ms) / 1000.0);
    std::cout << text << "\n";
    std::cout << "\n[metrics] mode=sync total_ms=" << total_ms
              << " chars=" << text.size()
              << " tok_est=" << tokens
              << " chars_per_s=" << (text.size() / secs)
              << " tok_per_s=" << (tokens / secs)
              << "\n";
}

void run_stream_once(const std::string& prompt) {
    uint64_t handle = 0;
    const auto t0 = std::chrono::steady_clock::now();
    const int rc_start = ai_query_async_start(nullptr, prompt.c_str(), &handle);
    if (rc_start != 0) {
        std::cout << "[error] ai_query_async_start rc=" << rc_start << "\n";
        return;
    }

    std::vector<char> out(8192, '\0');
    bool finished = false;
    std::string full;
    bool got_first_chunk = false;
    int64_t ttft_ms = -1;

    while (!finished) {
        const int rc_poll = ai_query_async_poll(
            nullptr,
            handle,
            &finished,
            out.data(),
            static_cast<uint32_t>(out.size()));

        if (rc_poll < 0) {
            std::cout << "\n[error] ai_query_async_poll rc=" << rc_poll << "\n";
            return;
        }

        const std::string chunk(out.data());
        if (!chunk.empty()) {
            if (!got_first_chunk) {
                got_first_chunk = true;
                const auto now = std::chrono::steady_clock::now();
                ttft_ms = std::chrono::duration_cast<std::chrono::milliseconds>(now - t0).count();
            }
            full += chunk;
            std::cout << chunk << std::flush;
        }

        if (!finished) {
            std::this_thread::sleep_for(std::chrono::milliseconds(8));
        }
    }

    const auto t1 = std::chrono::steady_clock::now();
    const auto total_ms = std::chrono::duration_cast<std::chrono::milliseconds>(t1 - t0).count();
    const int tokens = estimate_tokens(full);
    const double secs = std::max(0.001, static_cast<double>(total_ms) / 1000.0);

    std::cout << "\n\n[metrics] mode=stream total_ms=" << total_ms
              << " ttft_ms=" << ttft_ms
              << " chars=" << full.size()
              << " tok_est=" << tokens
              << " chars_per_s=" << (full.size() / secs)
              << " tok_per_s=" << (tokens / secs)
              << "\n";
}

} // namespace

int main(int argc, char** argv) {
    const Args args = parse_args(argc, argv);

    if (!args.data_dir.empty()) {
        const int rc = ai_set_data_dir(nullptr, args.data_dir.c_str());
        if (rc != 0) {
            std::cerr << "[fatal] ai_set_data_dir rc=" << rc << "\n";
            return 2;
        }
    }

    ai_set_decode_every(nullptr, args.decode_every);

    const int rc_init = ai_initialize(nullptr);
    if (rc_init != 0) {
        std::cerr << "[fatal] ai_initialize rc=" << rc_init << "\n";
        return 3;
    }

    std::cout << "EaSync native chat benchmark\n";
    std::cout << "mode=" << (args.sync_mode ? "sync" : "stream")
              << " decode_every=" << args.decode_every << "\n";
    if (!args.data_dir.empty()) {
        std::cout << "data_dir=" << args.data_dir << "\n";
    }
    std::cout << "Type /exit to quit.\n\n";

    std::string line;
    while (true) {
        std::cout << "you> " << std::flush;
        if (!std::getline(std::cin, line)) {
            break;
        }
        if (line == "/exit" || line == "/quit") {
            break;
        }
        if (line.empty()) {
            continue;
        }

        std::cout << "ai> " << std::flush;
        if (args.sync_mode) {
            run_sync_once(line);
        } else {
            run_stream_once(line);
        }
        std::cout << "\n";
    }

    ai_shutdown(nullptr);
    return 0;
}
