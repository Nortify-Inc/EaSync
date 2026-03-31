#include "engine.hpp"
#include "SGLM.hpp"
#include "tokenizer.hpp"

#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <memory>
#include <mutex>
#include <thread>
#include <string>
#include <unordered_map>

namespace fs = std::filesystem;

static std::string g_data_dir_override;

static std::string find_data_dir()
{
    if (!g_data_dir_override.empty() && fs::exists(g_data_dir_override + "/model.onnx"))
        return g_data_dir_override;

    if (const char* env = std::getenv("EASYNC_AI_DATA_DIR"))
        if (env && std::strlen(env) > 0 && fs::exists(env))
            return std::string(env);

    fs::path cur = fs::current_path();

    for (int i = 0; i < 10; ++i) {
        auto candidate = cur / "lib" / "ai" / "data";

        if (fs::exists(candidate / "model.onnx"))
            return candidate.string();

        if (!cur.has_parent_path() || cur.parent_path() == cur) 
            break;

        cur = cur.parent_path();
    }

    const std::string fixed = "./lib/ai/data";

    if (fs::exists(fixed + "/model.onnx"))
        return fixed;

    return {};
}

static std::string                g_system_prompt = "You are an AI created by Nortify Inc. Be quick, direct and simple. If unsure, say you don't know. Don't invent info";
static std::unique_ptr<SGLM>      g_model;
static std::unique_ptr<Tokenizer> g_tokenizer;
static std::mutex                 g_mutex;
    static std::atomic<int>       g_decode_every{1};

struct JobState {
    std::string buf;
    size_t pos = 0;
    bool finished = false;
};

static std::mutex                              g_jobs_mutex;
static std::unordered_map<uint64_t, JobState>  g_jobs;
static std::atomic<uint64_t>                   g_next_job{1};

static int write_out(const std::string& s, char* buf, uint32_t len)
{
    if (!buf || len == 0) return -1;
    const size_t n = std::min<size_t>(s.size(), len - 1);
    std::memcpy(buf, s.data(), n);
    buf[n] = '\0';
    return 0;
}

static uint32_t adjust_to_utf8_boundary(const std::string &s, size_t start, uint32_t toCopy)
{
    if (toCopy == 0) return 0;
    size_t end = start + toCopy;
    if (end > s.size()) end = s.size();

    while (end > start) {
        unsigned char c = static_cast<unsigned char>(s[end - 1]);
        if ((c & 0xC0) != 0x80) break;
        --end;
    }

    return static_cast<uint32_t>(end - start);
}

static std::string extract_field(const std::string& json, const std::string& key)
{
    if (json.empty() || json.front() != '{') return json;

    const std::string needle = "\"" + key + "\"";
    auto pos = json.find(needle);

    if (pos == std::string::npos) return {};

    auto colon = json.find(':', pos);

    if (colon == std::string::npos) return {};

    auto q1 = json.find('"', colon + 1);

    if (q1 == std::string::npos) return {};

    std::string val;
    bool esc = false;

    for (size_t i = q1 + 1; i < json.size(); ++i) {
        char c = json[i];
        if (esc){ 
            val += c; 
            esc = false; 
        }
        else if (c == '\\') 
            esc = true;

        else if (c == '"')  
            break;

        else val += c;
    }

    return val;
}

static bool ensure_initialized()
{
    if (g_model && g_tokenizer) return true;
    
    if (const char* env_sp = std::getenv("EASYNC_SYSTEM_PROMPT")) {
        if (std::strlen(env_sp) > 0) {
            std::lock_guard<std::mutex> lk(g_mutex);
            g_system_prompt = std::string(env_sp);
            fprintf(stderr, "[SGLM] Using system prompt from EASYNC_SYSTEM_PROMPT\n");
        }
    }
    if (const char* env_de = std::getenv("EASYNC_DECODE_EVERY")) {
        try {
            int v = std::stoi(env_de);
            if (v > 0) {
                g_decode_every.store(v);
                fprintf(stderr, "[SGLM] Using EASYNC_DECODE_EVERY=%d\n", v);
            }
        } catch (...) {}
    }
    const std::string data_dir = find_data_dir();
    if (data_dir.empty()) {
        fprintf(stderr, "[SGLM] ERROR: lib/ai/data not found.\n");
        return false;
    }

    const std::string model_path     = data_dir + "/model.onnx";
    const std::string tokenizer_path = data_dir + "/tokenizer.json";

    if (!g_tokenizer) {
        if (!fs::exists(tokenizer_path)) {
            fprintf(stderr, "[SGLM] ERROR: tokenizer.json not found %s\n",
                    data_dir.c_str());
            return false;
        }
        try {
            fprintf(stderr, "[SGLM] Loading tokenizer: %s\n", tokenizer_path.c_str());
            g_tokenizer = std::make_unique<Tokenizer>(tokenizer_path);
            fprintf(stderr, "[SGLM] Tokenizer OK. vocab=%lld\n",
                    static_cast<long long>(g_tokenizer->vocab_size()));

        } catch (const std::exception& e) {
            fprintf(stderr, "[SGLM] ERROR: Failed to load tokenizer: %s\n", e.what());
            return false;
        }
    }

    if (!g_model) {
        if (!fs::exists(model_path)) {
            fprintf(stderr, "[SGLM] ERROR: model.onnx not found in %s\n",
                    data_dir.c_str());
            return false;
        }
        try {
            fprintf(stderr, "[SGLM] Loading model: %s\n", model_path.c_str());
            SGLMConfig cfg;
            cfg.intra_op_threads = 2;
            g_model = std::make_unique<SGLM>(model_path, cfg);
            fprintf(stderr, "[SGLM] Modelo OK. vocab=%lld\n",
                    static_cast<long long>(g_model->vocab_size()));
        } catch (const std::exception& e) {
            fprintf(stderr, "[SGLM] Falha modelo: %s\n", e.what());
            return false;
        }
    }

    return true;
}

static bool run_inference(const std::string& prompt, std::string& result)
{
    std::lock_guard<std::mutex> lk(g_mutex);
    if (!ensure_initialized()) return false;

    auto ids = g_tokenizer->encode_chat(prompt, g_system_prompt);
    if (ids.empty()) { fprintf(stderr, "[SGLM] Tokenização vazia.\n"); return false; }

    fprintf(stderr, "[SGLM] Prompt: %zu tokens\n", ids.size());

    SGLMGenParams params;
    params.max_new_tokens = 512;
    params.temperature    = 0.9f;
    params.top_k          = 40;
    params.top_p          = 0.95f;

    std::vector<int64_t> generated;
    try {
        generated = g_model->generate(ids, params);
    } catch (const std::exception& e) {
        fprintf(stderr, "[SGLM] Error: %s\n", e.what());
        return false;
    }

    fprintf(stderr, "[SGLM] Generated: %zu tokens\n", generated.size());
    result = g_tokenizer->decode(generated);
    return true;
}

int ai_initialize(void* /*ctx*/)
{
    fprintf(stderr, "[SGLM] ai_initialize called\n");
    if (ensure_initialized()) return 0;
    return -1;
}

extern "C" {


int ai_set_chat_model_script(void* /*ctx*/, const char* /*path*/)
{
    return 0;
}

int ai_set_data_dir(void* /*ctx*/, const char* path)
{
    if (!path) return -1;
    try {
        std::lock_guard<std::mutex> lk(g_mutex);
        g_data_dir_override = std::string(path);
        fprintf(stderr, "[SGLM] ai_set_data_dir: %s\n", path);
        return 0;
    } catch (...) {
        return -1;
    }
}

int ai_set_system_prompt(void* /*ctx*/, const char* system_prompt)
{
    if (!system_prompt) return -1;
    std::lock_guard<std::mutex> lk(g_mutex);
    g_system_prompt = std::string(system_prompt);
    return 0;
}


int ai_query(void* /*ctx*/, const char* inputJson, char* outBuf, uint32_t outLen)
{
    std::string input  = inputJson ? std::string(inputJson) : "";
    std::string prompt = input;
    if (!input.empty() && input.front() == '{') {
        std::string p = extract_field(input, "prompt");
        if (!p.empty()) prompt = p;
    }
    std::string result;
    if (!run_inference(prompt, result)) return -1;
    return write_out(result, outBuf, outLen);
}

int ai_process_chat(void* ctx, const char* i, char* o, uint32_t l)            { return ai_query(ctx, i, o, l); }
int ai_model_process_chat(void* ctx, const char* i, char* o, uint32_t l)      { return ai_query(ctx, i, o, l); }
int ai_execute_command(void* ctx, const char* i, char* o, uint32_t l)         { return ai_query(ctx, i, o, l); }
int ai_model_execute_command(void* ctx, const char* i, char* o, uint32_t l)   { return ai_query(ctx, i, o, l); }


int ai_query_async_start(void* /*ctx*/, const char* inputJson, uint64_t* outHandle)
{
    if (!outHandle) return -1;

    std::string input  = inputJson ? std::string(inputJson) : "";
    std::string prompt = input;

    if (!input.empty() && input.front() == '{') {
        std::string p = extract_field(input, "prompt");
        if (!p.empty()) prompt = p;
    }

    const uint64_t id = g_next_job.fetch_add(1);
    {
        std::lock_guard<std::mutex> lk(g_jobs_mutex);
        g_jobs.emplace(id, JobState{});
    }

    std::thread([id, prompt]() {
        std::vector<int64_t> ids;
        {
            std::lock_guard<std::mutex> lk(g_mutex);

            if (!ensure_initialized()) {
                    fprintf(stderr, "[SGLM] ai_query_async_start: ensure_initialized() failed\n");

                    std::lock_guard<std::mutex> lk2(g_jobs_mutex);
                    auto it = g_jobs.find(id);

                    if (it != g_jobs.end()) it->second.finished = true;

                    return;
            }
            ids = g_tokenizer->encode_chat(prompt, g_system_prompt);
        }

        if (ids.empty()) {
                fprintf(stderr, "[SGLM] ai_query_async_start: tokenizer produced empty ids (prompt len=%zu)\n", prompt.size());
                std::lock_guard<std::mutex> lk(g_jobs_mutex);

                auto it = g_jobs.find(id);
                if (it != g_jobs.end()) it->second.finished = true;

                return;
        }

        SGLMGenParams params;
        params.max_new_tokens = 512;
        params.temperature = 0.7f;
        params.top_k = 40;
        params.top_p = 0.9f;

        std::vector<int64_t> generated;
        generated.reserve(static_cast<size_t>(params.max_new_tokens));

        int token_counter = 0;

        auto on_token = [&](int64_t token_id) {
            generated.push_back(token_id);
            ++token_counter;

            int de = g_decode_every.load();

            if (de <= 0) 
                de = 4;

            if (token_counter % de == 0) {
                std::string cur = g_tokenizer->decode(generated);
                std::lock_guard<std::mutex> lk(g_jobs_mutex);

                auto it = g_jobs.find(id);

                if (it != g_jobs.end()) {
                    std::string &old = it->second.buf;

                    if (!old.empty() && cur.size() >= old.size() && cur.rfind(old, 0) == 0) {
                        old.append(cur.substr(old.size()));

                    } else {
                        old = cur;
                        it->second.pos = 0;
                    }
                }
            }
        };

        try {
            g_model->generate_stream(ids, params, on_token);

        } catch (const std::exception& e) {
            fprintf(stderr, "[SGLM] ai_query_async_start: generate_stream exception: %s\n", e.what());
            std::lock_guard<std::mutex> lk(g_jobs_mutex);

            auto it = g_jobs.find(id);
            if (it != g_jobs.end()) it->second.buf += "\n[model error]";
        }

        {
            std::lock_guard<std::mutex> lk2(g_jobs_mutex);
            auto it2 = g_jobs.find(id);

            if (it2 != g_jobs.end()) {
                try {
                    std::string finalDec = g_tokenizer->decode(generated);
                    std::string &old = it2->second.buf;

                    if (!old.empty() && finalDec.size() >= old.size() && finalDec.rfind(old, 0) == 0) {
                        old.append(finalDec.substr(old.size()));

                    } else {
                        old = finalDec;
                        it2->second.pos = 0;

                    }

                } catch (...) {}

                it2->second.finished = true;
            }
        }
    }).detach();

    *outHandle = id;
    return 0;
}

int ai_query_async_poll(void* /*ctx*/, uint64_t handle, bool* finished,
                         char* outBuf, uint32_t outLen)
{
    if (!finished) return -1;

    std::lock_guard<std::mutex> lk(g_jobs_mutex);
    auto it = g_jobs.find(handle);
    if (it == g_jobs.end()) { *finished = true; return -1; }

    JobState& job = it->second;

    const size_t available = (job.buf.size() > job.pos) ? (job.buf.size() - job.pos) : 0;

    if (available == 0) {
        if (job.finished) {
            *finished = true;
            if (outBuf && outLen > 0) outBuf[0] = '\0';
            g_jobs.erase(it);

            return 0;
        }

        *finished = false;
        if (outBuf && outLen > 0) outBuf[0] = '\0';

        return 1;
    }

    const uint32_t maxCopy = (outLen > 0) ? (outLen - 1) : 0;
    uint32_t toCopy = static_cast<uint32_t>(std::min<size_t>(available, maxCopy));
    toCopy = adjust_to_utf8_boundary(job.buf, job.pos, toCopy);

    if (toCopy > 0) {
        std::memcpy(outBuf, job.buf.data() + job.pos, toCopy);
    }

    outBuf[toCopy] = '\0';
    job.pos += toCopy;

    if (job.finished && job.pos >= job.buf.size()) {
        *finished = true;
        g_jobs.erase(it);
        return 0;
    }

    *finished = false;
    return 1;
}

int ai_model_execute_command_async_start(void* ctx, const char* r, uint64_t* h) { return ai_query_async_start(ctx, r, h); }
int ai_model_execute_command_async_poll(void* ctx, uint64_t h, bool* f, char* o, uint32_t l) { return ai_query_async_poll(ctx, h, f, o, l); }


int ai_get_annotations(void* /*ctx*/, char* o, uint32_t l)              { return write_out("{}", o, l); }
int ai_learning_snapshot(void* /*ctx*/, char* o, uint32_t l)            { return write_out("{}", o, l); }
int ai_set_permissions(void* /*ctx*/, void* /*p*/)                      { return 0; }
int ai_get_permissions(void* /*ctx*/, void* /*p*/)                      { return 0; }
int ai_record_pattern(void* /*ctx*/, const char* /*p*/, uint64_t /*t*/) { return 0; }
int ai_observe_app_open(void* /*ctx*/, uint64_t /*t*/)                  { return 0; }
int ai_observe_profile_apply(void* /*ctx*/, const char* /*p*/, uint64_t /*t*/) { return 0; }

int ai_set_decode_every(void* /*ctx*/, int n)
{
    if (n <= 0) return -1;
    g_decode_every.store(n);
    fprintf(stderr, "[SGLM] ai_set_decode_every: %d\n", n);
    return 0;
}

int ai_shutdown(void* /*ctx*/)
{
    std::lock_guard<std::mutex> lk(g_mutex);
    try {
        g_model.reset();
        g_tokenizer.reset();

        fprintf(stderr, "[SGLM] ai_shutdown completed\n");
        return 0;
        
    } catch (...) {
        return -1;
    }
}

} // extern "C"