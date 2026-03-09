// ai/src/engine.cpp
// Implementation of C API that runs `service.py` as a subprocess to serve
// model inference. Outputs are returned via provided buffers.

#include "../include/engine.hpp"
#include <string>
#include <cstring>
#include <mutex>
#include <unordered_map>
#include <atomic>
#include <vector>
#include <cstdio>
#include <cstdlib>
#include <array>

static std::string g_runner_path = "./lib/ai/src/service.py";

static std::mutex g_jobs_mutex;
static std::unordered_map<uint64_t, std::string> g_jobs;
static std::atomic<uint64_t> g_next_job{1};

static int write_out(const std::string &s, char *outBuf, uint32_t outLen) {
    if (!outBuf || outLen == 0) return -1;
    const size_t toCopy = std::min<size_t>(s.size(), (size_t)outLen - 1);
    std::memcpy(outBuf, s.data(), toCopy);
    outBuf[toCopy] = '\0';
    return 0;
}

static std::string escapeArg(const std::string &in) {
    std::string out;
    out.reserve(in.size());
    for (char c : in) {
        if (c == '"') out += "\\\"";
        else out += c;
    }
    return out;
}

// Run the python runner with --prompt "..." and capture stdout
static bool run_runner_capture(const std::string &prompt, std::string &out) {
    const char *python = std::getenv("EASYNC_CHAT_INFER_PYTHON");
    std::string cmd;
    if (python && std::strlen(python) > 0) cmd = std::string(python) + " ";
    else cmd = "python3 ";

    const char *env_runner = std::getenv("EASYNC_CHAT_INFER_SCRIPT");
    std::string runner = env_runner && std::strlen(env_runner) ? std::string(env_runner) : g_runner_path;

    std::string esc = escapeArg(prompt);
    cmd += runner + " --prompt \"" + esc + "\" --max_tokens 64";

    std::array<char, 4096> buffer;
    out.clear();
    FILE *pipe = popen(cmd.c_str(), "r");
    if (!pipe) return false;
    while (fgets(buffer.data(), buffer.size(), pipe) != nullptr) {
        out += buffer.data();
    }
    int rc = pclose(pipe);
    (void)rc;
    // trim
    while (!out.empty() && (out.back() == '\n' || out.back() == '\r')) out.pop_back();
    return true;
}

extern "C" {

int ai_process_chat(void *ctx, const char *inputJson, char *outBuf, uint32_t outLen) {
    std::string input = inputJson ? inputJson : "";
    std::string prompt = input;
    // very small parsing: try to find "prompt":"..."
    auto pos = input.find("\"prompt\"");
    if (pos != std::string::npos) {
        auto colon = input.find(':', pos);
        if (colon != std::string::npos) {
            auto q1 = input.find('"', colon);
            if (q1 != std::string::npos) {
                auto q2 = input.find('"', q1 + 1);
                if (q2 != std::string::npos) {
                    prompt = input.substr(q1 + 1, q2 - q1 - 1);
                }
            }
        }
    }

    std::string result;
    if (!run_runner_capture(prompt, result)) {
        return -1;
    }

    return write_out(result, outBuf, outLen);
}

int ai_model_process_chat(void *ctx, const char *inputJson, char *outBuf, uint32_t outLen) {
    return ai_process_chat(ctx, inputJson, outBuf, outLen);
}

int ai_execute_command(void *ctx, const char *reqJson, char *outBuf, uint32_t outLen) {
    return ai_process_chat(ctx, reqJson, outBuf, outLen);
}

int ai_model_execute_command(void *ctx, const char *reqJson, char *outBuf, uint32_t outLen) {
    return ai_process_chat(ctx, reqJson, outBuf, outLen);
}

int ai_set_chat_model_script(void *ctx, const char *scriptPath) {
    if (!scriptPath) return -1;
    g_runner_path = std::string(scriptPath);
    return 0;
}

int ai_model_execute_command_async_start(void *ctx, const char *reqJson, uint64_t *outHandle) {
    if (!outHandle) return -1;
    std::string req = reqJson ? reqJson : "";
    std::string result;
    if (!run_runner_capture(req, result)) return -1;
    uint64_t id = g_next_job.fetch_add(1);
    {
        std::lock_guard<std::mutex> lk(g_jobs_mutex);
        g_jobs[id] = result;
    }
    *outHandle = id;
    return 0;
}

int ai_model_execute_command_async_poll(void *ctx, uint64_t handle, bool *finished, char *outBuf, uint32_t outLen) {
    if (!finished) return -1;
    std::string resp;
    {
        std::lock_guard<std::mutex> lk(g_jobs_mutex);
        auto it = g_jobs.find(handle);
        if (it == g_jobs.end()) {
            *finished = true;
            return -1;
        }
        resp = it->second;
        g_jobs.erase(it);
    }
    *finished = true;
    return write_out(resp, outBuf, outLen);
}

int ai_get_annotations(void *ctx, char *outBuf, uint32_t outLen) {
    const std::string r = "{\"annotations\": []}";
    return write_out(r, outBuf, outLen);
}

int ai_learning_snapshot(void *ctx, char *outBuf, uint32_t outLen) {
    const std::string r = "{\"snapshot\": \"ok\"}";
    return write_out(r, outBuf, outLen);
}

int ai_set_permissions(void *ctx, void *perms) { (void)ctx; (void)perms; return 0; }
int ai_get_permissions(void *ctx, void *perms) { (void)ctx; (void)perms; return 0; }
int ai_record_pattern(void *ctx, const char *payload, uint64_t timestamp) { (void)ctx; (void)payload; (void)timestamp; return 0; }
int ai_observe_app_open(void *ctx, uint64_t timestamp) { (void)ctx; (void)timestamp; return 0; }
int ai_observe_profile_apply(void *ctx, const char *profile, uint64_t timestamp) { (void)ctx; (void)profile; (void)timestamp; return 0; }

} // extern "C"
