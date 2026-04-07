#include "engine.hpp"

#include "llama.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <functional>
#include <memory>
#include <mutex>
#include <random>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

namespace fs = std::filesystem;

namespace {

static std::string g_data_dir_override;
static std::string g_system_prompt =
    "You are Agent, an AI assistant created by Nortify Inc. "
    "Be quick and concise. Don't invent info.";

static std::mutex g_mutex;
static std::atomic<int> g_decode_every{6};
static std::atomic<int> g_max_new_tokens{2048};
static std::atomic<float> g_temperature{0.8f};
static std::atomic<int> g_top_k{40};
static std::atomic<float> g_top_p{0.95f};

static std::atomic<bool> g_backend_inited{false};

static llama_model* g_model = nullptr;
static llama_context* g_ctx = nullptr;
static const llama_vocab* g_vocab = nullptr;

struct JobState {
    std::string buf;
    size_t pos = 0;
    bool finished = false;
};

static std::mutex g_jobs_mutex;
static std::unordered_map<uint64_t, JobState> g_jobs;
static std::atomic<uint64_t> g_next_job{1};

static std::string find_data_dir() {
    if (!g_data_dir_override.empty()) {
        if (fs::exists(g_data_dir_override + "/model.gguf")) {
            return g_data_dir_override;
        }
        for (const auto& e : fs::directory_iterator(g_data_dir_override)) {
            if (e.is_regular_file() && e.path().extension() == ".gguf") {
                return g_data_dir_override;
            }
        }
    }

    if (const char* env = std::getenv("EASYNC_AI_DATA_DIR")) {
        if (env && std::strlen(env) > 0 && fs::exists(env)) {
            std::string d(env);
            if (fs::exists(d + "/model.gguf")) {
                return d;
            }
            for (const auto& e : fs::directory_iterator(d)) {
                if (e.is_regular_file() && e.path().extension() == ".gguf") {
                    return d;
                }
            }
        }
    }

    fs::path cur = fs::current_path();
    for (int i = 0; i < 10; ++i) {
        auto candidate = cur / "lib" / "ai" / "data";
        if (fs::exists(candidate / "model.gguf")) {
            return candidate.string();
        }
        if (fs::exists(candidate)) {
            for (const auto& e : fs::directory_iterator(candidate)) {
                if (e.is_regular_file() && e.path().extension() == ".gguf") {
                    return candidate.string();
                }
            }
        }
        if (!cur.has_parent_path() || cur.parent_path() == cur) {
            break;
        }
        cur = cur.parent_path();
    }

    return {};
}

static std::string find_model_path(const std::string& data_dir) {
    const std::string default_path = data_dir + "/model.gguf";
    if (fs::exists(default_path)) {
        return default_path;
    }
    for (const auto& e : fs::directory_iterator(data_dir)) {
        if (e.is_regular_file() && e.path().extension() == ".gguf") {
            return e.path().string();
        }
    }
    return {};
}

static int write_out(const std::string& s, char* buf, uint32_t len) {
    if (!buf || len == 0) return -1;
    const size_t n = std::min<size_t>(s.size(), len - 1);
    std::memcpy(buf, s.data(), n);
    buf[n] = '\0';
    return 0;
}

static uint32_t adjust_to_utf8_boundary(const std::string& s, size_t start, uint32_t to_copy) {
    if (to_copy == 0) return 0;
    size_t end = start + to_copy;
    if (end > s.size()) end = s.size();

    while (end > start) {
        unsigned char c = static_cast<unsigned char>(s[end - 1]);
        if ((c & 0xC0) != 0x80) break;
        --end;
    }

    return static_cast<uint32_t>(end - start);
}

static std::string extract_field(const std::string& json, const std::string& key) {
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
        if (esc) {
            val += c;
            esc = false;
        } else if (c == '\\') {
            esc = true;
        } else if (c == '"') {
            break;
        } else {
            val += c;
        }
    }

    return val;
}

static std::string build_chat_prompt(const std::string& user_prompt) {
    std::string p;
    p.reserve(g_system_prompt.size() + user_prompt.size() + 96);
    p += "<|im_start|>system\n";
    p += g_system_prompt;
    p += "<|im_end|>\n";
    p += "<|im_start|>user\n";
    p += user_prompt;
    p += "<|im_end|>\n";
    p += "<|im_start|>assistant\n";
    return p;
}

static std::vector<llama_token> tokenize(const std::string& text, bool add_special) {
    std::vector<llama_token> tokens(std::max<int>(128, static_cast<int>(text.size()) + 16));

    int32_t n = llama_tokenize(
        g_vocab,
        text.c_str(),
        static_cast<int32_t>(text.size()),
        tokens.data(),
        static_cast<int32_t>(tokens.size()),
        add_special,
        true);

    if (n < 0) {
        tokens.resize(static_cast<size_t>(-n));
        n = llama_tokenize(
            g_vocab,
            text.c_str(),
            static_cast<int32_t>(text.size()),
            tokens.data(),
            static_cast<int32_t>(tokens.size()),
            add_special,
            true);
    }

    if (n < 0) {
        return {};
    }

    tokens.resize(static_cast<size_t>(n));
    return tokens;
}

static bool decode_tokens(const std::vector<llama_token>& tokens) {
    if (tokens.empty()) return true;

    llama_batch batch = llama_batch_get_one(
        const_cast<llama_token*>(tokens.data()),
        static_cast<int32_t>(tokens.size()));

    return llama_decode(g_ctx, batch) == 0;
}

static std::string token_to_piece(llama_token tok) {
    std::string out;
    out.resize(256);

    int32_t n = llama_token_to_piece(
        g_vocab,
        tok,
        out.data(),
        static_cast<int32_t>(out.size()),
        0,
        false);

    if (n < 0) {
        out.resize(static_cast<size_t>(-n));
        n = llama_token_to_piece(
            g_vocab,
            tok,
            out.data(),
            static_cast<int32_t>(out.size()),
            0,
            false);
    }

    if (n <= 0) return {};
    out.resize(static_cast<size_t>(n));
    return out;
}

static llama_token sample_next_token(
    float* logits,
    int32_t n_vocab,
    float temperature,
    int top_k,
    float top_p,
    std::mt19937& rng) {

    if (!logits || n_vocab <= 0) return LLAMA_TOKEN_NULL;

    std::vector<float> scores(static_cast<size_t>(n_vocab));
    const float inv_temp = temperature > 1e-6f ? 1.0f / temperature : 1e6f;

    for (int i = 0; i < n_vocab; ++i) {
        scores[static_cast<size_t>(i)] = logits[i] * inv_temp;
    }

    std::vector<int> idx(static_cast<size_t>(n_vocab));
    for (int i = 0; i < n_vocab; ++i) idx[static_cast<size_t>(i)] = i;

    std::sort(idx.begin(), idx.end(), [&](int a, int b) {
        return scores[static_cast<size_t>(a)] > scores[static_cast<size_t>(b)];
    });

    if (top_k > 0 && top_k < n_vocab) {
        idx.resize(static_cast<size_t>(top_k));
    }

    float max_logit = -INFINITY;
    for (int id : idx) {
        max_logit = std::max(max_logit, scores[static_cast<size_t>(id)]);
    }

    std::vector<float> probs;
    probs.reserve(idx.size());
    float sum = 0.0f;
    for (int id : idx) {
        float p = std::exp(scores[static_cast<size_t>(id)] - max_logit);
        probs.push_back(p);
        sum += p;
    }

    if (sum <= 0.0f) {
        return static_cast<llama_token>(idx.front());
    }

    for (float& p : probs) p /= sum;

    if (top_p > 0.0f && top_p < 1.0f) {
        float cum = 0.0f;
        size_t keep = probs.size();
        for (size_t i = 0; i < probs.size(); ++i) {
            cum += probs[i];
            if (cum >= top_p) {
                keep = i + 1;
                break;
            }
        }
        if (keep < probs.size()) {
            idx.resize(keep);
            probs.resize(keep);
            float renorm = 0.0f;
            for (float p : probs) renorm += p;
            if (renorm > 0.0f) {
                for (float& p : probs) p /= renorm;
            }
        }
    }

    std::discrete_distribution<int> dist(probs.begin(), probs.end());
    int sampled_i = dist(rng);
    return static_cast<llama_token>(idx[static_cast<size_t>(sampled_i)]);
}

struct GenParams {
    int max_new_tokens = 4096;
    float temperature = 0.55f;
    int top_k = 48;
    float top_p = 0.90f;
};

static bool generate_text(
    const std::string& prompt,
    const GenParams& params,
    std::string& out,
    const std::function<void(const std::string&)>& on_piece) {

    out.clear();

    const std::string full_prompt = build_chat_prompt(prompt);
    std::vector<llama_token> prompt_tokens = tokenize(full_prompt, false);
    if (prompt_tokens.empty()) {
        return false;
    }

    llama_memory_clear(llama_get_memory(g_ctx), false);

    if (!decode_tokens(prompt_tokens)) {
        return false;
    }

    std::mt19937 rng(std::random_device{}());
    std::string pending;
    pending.reserve(256);

    const int32_t n_vocab = llama_vocab_n_tokens(g_vocab);

    for (int step = 0; step < params.max_new_tokens; ++step) {
        float* logits = llama_get_logits(g_ctx);
        llama_token next = sample_next_token(
            logits,
            n_vocab,
            params.temperature,
            params.top_k,
            params.top_p,
            rng);

        if (next == LLAMA_TOKEN_NULL) {
            break;
        }

        if (llama_vocab_is_eog(g_vocab, next)) {
            break;
        }

        const std::string piece = token_to_piece(next);
        if (!piece.empty()) {
            out += piece;
            pending += piece;

            if ((step + 1) % std::max(1, g_decode_every.load()) == 0) {
                on_piece(pending);
                pending.clear();
            }
        }

        llama_token one = next;
        llama_batch batch = llama_batch_get_one(&one, 1);
        if (llama_decode(g_ctx, batch) != 0) {
            break;
        }
    }

    if (!pending.empty()) {
        on_piece(pending);
    }

    return true;
}

static bool ensure_initialized() {
    if (g_model && g_ctx && g_vocab) return true;

    if (!g_backend_inited.load()) {
        llama_backend_init();
        g_backend_inited.store(true);
    }

    if (const char* env_sp = std::getenv("EASYNC_SYSTEM_PROMPT")) {
        if (std::strlen(env_sp) > 0) {
            g_system_prompt = std::string(env_sp);
            fprintf(stderr, "[LLAMA] Using system prompt from EASYNC_SYSTEM_PROMPT\n");
        }
    }

    if (const char* env_de = std::getenv("EASYNC_DECODE_EVERY")) {
        try {
            int v = std::stoi(env_de);
            if (v > 0) {
                g_decode_every.store(v);
                fprintf(stderr, "[LLAMA] Using EASYNC_DECODE_EVERY=%d\n", v);
            }
        } catch (...) {
        }
    }

    if (const char* env_mnt = std::getenv("EASYNC_MAX_NEW_TOKENS")) {
        try {
            int v = std::stoi(env_mnt);
            if (v > 0) {
                g_max_new_tokens.store(v);
                fprintf(stderr, "[LLAMA] Using EASYNC_MAX_NEW_TOKENS=%d\n", v);
            }
        } catch (...) {
        }
    }

    if (const char* env_ctx = std::getenv("EASYNC_N_CTX")) {
        try {
            int v = std::stoi(env_ctx);
            if (v >= 2048) {
                fprintf(stderr, "[LLAMA] Using EASYNC_N_CTX=%d\n", v);
            }
        } catch (...) {
        }
    }

    if (const char* env_temp = std::getenv("EASYNC_TEMPERATURE")) {
        try {
            float v = std::stof(env_temp);
            if (v >= 0.0f && v <= 2.0f) {
                g_temperature.store(v);
                fprintf(stderr, "[LLAMA] Using EASYNC_TEMPERATURE=%.3f\n", v);
            }
        } catch (...) {
        }
    }

    if (const char* env_top_k = std::getenv("EASYNC_TOP_K")) {
        try {
            int v = std::stoi(env_top_k);
            if (v > 0) {
                g_top_k.store(v);
                fprintf(stderr, "[LLAMA] Using EASYNC_TOP_K=%d\n", v);
            }
        } catch (...) {
        }
    }

    if (const char* env_top_p = std::getenv("EASYNC_TOP_P")) {
        try {
            float v = std::stof(env_top_p);
            if (v > 0.0f && v <= 1.0f) {
                g_top_p.store(v);
                fprintf(stderr, "[LLAMA] Using EASYNC_TOP_P=%.3f\n", v);
            }
        } catch (...) {
        }
    }

    const std::string data_dir = find_data_dir();
    if (data_dir.empty()) {
        fprintf(stderr, "[LLAMA] ERROR: lib/ai/data with GGUF model not found.\n");
        return false;
    }

    const std::string model_path = find_model_path(data_dir);
    if (model_path.empty()) {
        fprintf(stderr, "[LLAMA] ERROR: model.gguf not found in %s\n", data_dir.c_str());
        return false;
    }

    llama_model_params mparams = llama_model_default_params();
    mparams.n_gpu_layers = 0;
    mparams.use_mmap = true;
    mparams.use_mlock = false;

    llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx = 8192;
    if (const char* env_ctx = std::getenv("EASYNC_N_CTX")) {
        try {
            int v = std::stoi(env_ctx);
            if (v >= 2048) {
                cparams.n_ctx = static_cast<uint32_t>(v);
            }
        } catch (...) {
        }
    }
    cparams.n_batch = 512;
    cparams.n_ubatch = 256;

    const int hc = std::max(2u, std::thread::hardware_concurrency());
    cparams.n_threads = std::max(2, hc / 2);
    cparams.n_threads_batch = std::max(2, hc / 2);

    fprintf(stderr, "[LLAMA] Loading model: %s\n", model_path.c_str());
    g_model = llama_model_load_from_file(model_path.c_str(), mparams);
    if (!g_model) {
        fprintf(stderr, "[LLAMA] ERROR: llama_model_load_from_file failed\n");
        return false;
    }

    g_ctx = llama_init_from_model(g_model, cparams);
    if (!g_ctx) {
        fprintf(stderr, "[LLAMA] ERROR: llama_init_from_model failed\n");
        llama_model_free(g_model);
        g_model = nullptr;
        return false;
    }

    g_vocab = llama_model_get_vocab(g_model);
    if (!g_vocab) {
        fprintf(stderr, "[LLAMA] ERROR: llama_model_get_vocab failed\n");
        llama_free(g_ctx);
        g_ctx = nullptr;
        llama_model_free(g_model);
        g_model = nullptr;
        return false;
    }

    fprintf(stderr, "[LLAMA] Model ready. vocab=%d\n", llama_vocab_n_tokens(g_vocab));
    return true;
}

static bool run_inference(const std::string& prompt, std::string& result) {
    std::lock_guard<std::mutex> lk(g_mutex);
    if (!ensure_initialized()) return false;

    GenParams params{};
    params.max_new_tokens = g_max_new_tokens.load();
    params.temperature = g_temperature.load();
    params.top_k = g_top_k.load();
    params.top_p = g_top_p.load();
    const bool ok = generate_text(prompt, params, result, [](const std::string&) {});
    if (!ok) return false;

    return true;
}

} // namespace

int ai_initialize(void* /*ctx*/) {
    std::lock_guard<std::mutex> lk(g_mutex);
    if (g_model && g_ctx && g_vocab) {
        return 0;
    }
    fprintf(stderr, "[LLAMA] ai_initialize called\n");
    return ensure_initialized() ? 0 : -1;
}

extern "C" {

int ai_set_chat_model_script(void* /*ctx*/, const char* /*path*/) {
    return 0;
}

int ai_set_data_dir(void* /*ctx*/, const char* path) {
    if (!path) return -1;
    try {
        std::lock_guard<std::mutex> lk(g_mutex);
        g_data_dir_override = std::string(path);
        fprintf(stderr, "[LLAMA] ai_set_data_dir: %s\n", path);
        return 0;
    } catch (...) {
        return -1;
    }
}

int ai_set_system_prompt(void* /*ctx*/, const char* system_prompt) {
    if (!system_prompt) return -1;
    std::lock_guard<std::mutex> lk(g_mutex);
    g_system_prompt = std::string(system_prompt);
    return 0;
}

int ai_query(void* /*ctx*/, const char* inputJson, char* outBuf, uint32_t outLen) {
    std::string input = inputJson ? std::string(inputJson) : "";
    std::string prompt = input;
    if (!input.empty() && input.front() == '{') {
        std::string p = extract_field(input, "prompt");
        if (!p.empty()) prompt = p;
    }

    std::string result;
    if (!run_inference(prompt, result)) return -1;
    return write_out(result, outBuf, outLen);
}

int ai_process_chat(void* ctx, const char* i, char* o, uint32_t l) {
    return ai_query(ctx, i, o, l);
}

int ai_model_process_chat(void* ctx, const char* i, char* o, uint32_t l) {
    return ai_query(ctx, i, o, l);
}

int ai_execute_command(void* ctx, const char* i, char* o, uint32_t l) {
    return ai_query(ctx, i, o, l);
}

int ai_model_execute_command(void* ctx, const char* i, char* o, uint32_t l) {
    return ai_query(ctx, i, o, l);
}

int ai_query_async_start(void* /*ctx*/, const char* inputJson, uint64_t* outHandle) {
    if (!outHandle) return -1;

    std::string input = inputJson ? std::string(inputJson) : "";
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
        std::string full;
        {
            std::lock_guard<std::mutex> lk(g_mutex);
            if (!ensure_initialized()) {
                std::lock_guard<std::mutex> lk2(g_jobs_mutex);
                auto it = g_jobs.find(id);
                if (it != g_jobs.end()) it->second.finished = true;
                return;
            }

            const GenParams params{};
            GenParams tuned = params;
            tuned.max_new_tokens = g_max_new_tokens.load();
            generate_text(prompt, tuned, full, [&](const std::string& piece) {
                std::lock_guard<std::mutex> lk_jobs(g_jobs_mutex);
                auto it = g_jobs.find(id);
                if (it != g_jobs.end()) {
                    it->second.buf += piece;
                }
            });
        }

        std::lock_guard<std::mutex> lk_jobs(g_jobs_mutex);
        auto it = g_jobs.find(id);
        if (it != g_jobs.end()) {
            it->second.finished = true;
        }
    }).detach();

    *outHandle = id;
    return 0;
}

int ai_query_async_poll(void* /*ctx*/, uint64_t handle, bool* finished, char* outBuf, uint32_t outLen) {
    if (!finished) return -1;

    std::lock_guard<std::mutex> lk(g_jobs_mutex);
    auto it = g_jobs.find(handle);
    if (it == g_jobs.end()) {
        *finished = true;
        return -1;
    }

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

int ai_model_execute_command_async_start(void* ctx, const char* r, uint64_t* h) {
    return ai_query_async_start(ctx, r, h);
}

int ai_model_execute_command_async_poll(void* ctx, uint64_t h, bool* f, char* o, uint32_t l) {
    return ai_query_async_poll(ctx, h, f, o, l);
}

int ai_get_annotations(void* /*ctx*/, char* o, uint32_t l) {
    return write_out("{}", o, l);
}

int ai_learning_snapshot(void* /*ctx*/, char* o, uint32_t l) {
    return write_out("{}", o, l);
}

int ai_set_permissions(void* /*ctx*/, void* /*p*/) {
    return 0;
}

int ai_get_permissions(void* /*ctx*/, void* /*p*/) {
    return 0;
}

int ai_record_pattern(void* /*ctx*/, const char* /*p*/, uint64_t /*t*/) {
    return 0;
}

int ai_observe_app_open(void* /*ctx*/, uint64_t /*t*/) {
    return 0;
}

int ai_observe_profile_apply(void* /*ctx*/, const char* /*p*/, uint64_t /*t*/) {
    return 0;
}

int ai_set_decode_every(void* /*ctx*/, int n) {
    if (n <= 0) return -1;
    const int old = g_decode_every.load();
    if (old == n) {
        return 0;
    }
    g_decode_every.store(n);
    fprintf(stderr, "[LLAMA] ai_set_decode_every: %d\n", n);
    return 0;
}

int ai_shutdown(void* /*ctx*/) {
    std::lock_guard<std::mutex> lk(g_mutex);

    try {
        if (g_ctx) {
            llama_free(g_ctx);
            g_ctx = nullptr;
        }
        if (g_model) {
            llama_model_free(g_model);
            g_model = nullptr;
        }
        g_vocab = nullptr;

        if (g_backend_inited.load()) {
            llama_backend_free();
            g_backend_inited.store(false);
        }

        fprintf(stderr, "[LLAMA] ai_shutdown completed\n");
        return 0;
    } catch (...) {
        return -1;
    }
}

} // extern "C"
