/*
 * SGLM.cpp
 * ────────
 * Implementação do engine SGLM com ONNX Runtime.
 */

#include "SGLM.hpp"

#include <algorithm>
#include <cmath>
#include <numeric>
#include <stdexcept>

SGLM::SGLM(const std::string& model_path, SGLMConfig cfg)
    : env_(cfg.verbose ? ORT_LOGGING_LEVEL_VERBOSE : ORT_LOGGING_LEVEL_WARNING,
           "SGLM"),
      rng_(std::random_device{}())
{
    Ort::SessionOptions opts;
    opts.SetIntraOpNumThreads(cfg.intra_op_threads);
    opts.SetInterOpNumThreads(cfg.inter_op_threads);
    opts.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);

#ifdef ORT_WITH_CUDA
    if (cfg.use_gpu) {
        OrtCUDAProviderOptions cuda_opts{};
        cuda_opts.device_id = cfg.cuda_device_id;
        opts.AppendExecutionProvider_CUDA(cuda_opts);
    }
#endif

    session_ = std::make_unique<Ort::Session>(env_, model_path.c_str(), opts);

    // Output shape: [1, -1, vocab_size]
    // dim[1] é dinâmico (-1), dim[2] é fixo (151936 para Qwen2).
    // Lemos diretamente do shape estático — sem dummy forward.
    auto shape = session_->GetOutputTypeInfo(0)
                          .GetTensorTypeAndShapeInfo().GetShape();

    if (shape.size() < 3 || shape.back() <= 0)
        throw std::runtime_error("SGLM: vocab_size inválido no shape do output");

    vocab_size_ = shape.back();

    fprintf(stderr, "[SGLM] Pronto. vocab_size=%lld\n",
            static_cast<long long>(vocab_size_));
}

std::vector<float> SGLM::forward(const std::vector<int64_t>& token_ids)
{
    if (token_ids.empty())
        throw std::runtime_error("SGLM::forward: token_ids vazio");

    const int64_t T = static_cast<int64_t>(token_ids.size());
    std::array<int64_t, 2> in_shape{1, T};

    auto mem_info = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);

    Ort::Value in_tensor = Ort::Value::CreateTensor<int64_t>(
        mem_info,
        const_cast<int64_t*>(token_ids.data()),
        token_ids.size(),
        in_shape.data(), in_shape.size());

    const char* in_names[]  = {"token_ids"};
    const char* out_names[] = {"logits"};

    auto outputs = session_->Run(
        Ort::RunOptions{nullptr},
        in_names,  &in_tensor, 1,
        out_names, 1);

    const float* data   = outputs[0].GetTensorData<float>();
    const size_t offset = static_cast<size_t>(T - 1) * static_cast<size_t>(vocab_size_);

    return std::vector<float>(data + offset,
                               data + offset + static_cast<size_t>(vocab_size_));
}

int64_t SGLM::sample(
    std::vector<float>& logits,
    float temperature,
    int   top_k,
    float top_p,
    std::mt19937& rng)
{
    const size_t V = logits.size();

    for (auto& v : logits) v /= (temperature > 0.f ? temperature : 1e-6f);

    if (top_k > 0 && static_cast<size_t>(top_k) < V) {
        std::vector<float> tmp(logits);
        std::nth_element(tmp.begin(), tmp.begin() + top_k - 1,
                         tmp.end(), std::greater<float>());
        const float kth = tmp[top_k - 1];
        for (auto& v : logits)
            if (v < kth) v = -std::numeric_limits<float>::infinity();
    }

    const float maxv = *std::max_element(logits.begin(), logits.end());
    std::vector<float> probs(V);
    float sum = 0.f;
    for (size_t i = 0; i < V; ++i) {
        probs[i] = std::exp(logits[i] - maxv);
        sum += probs[i];
    }
    for (auto& p : probs) p /= sum;

    if (top_p < 1.f) {
        std::vector<size_t> idx(V);
        std::iota(idx.begin(), idx.end(), 0);
        std::sort(idx.begin(), idx.end(),
                  [&](size_t a, size_t b){ return probs[a] > probs[b]; });
        float cum = 0.f;
        for (size_t i = 0; i < V; ++i) {
            if (cum >= top_p) probs[idx[i]] = 0.f;
            else              cum += probs[idx[i]];
        }
        sum = 0.f;
        for (const auto& p : probs) sum += p;
        if (sum > 0.f) for (auto& p : probs) p /= sum;
    }

    std::discrete_distribution<int64_t> dist(probs.begin(), probs.end());
    return dist(rng);
}

std::vector<int64_t> SGLM::generate(
    const std::vector<int64_t>& prompt_ids,
    SGLMGenParams params)
{
    // Delegate to the streaming generator and collect tokens.
    std::vector<int64_t> generated;
    generated.reserve(static_cast<size_t>(params.max_new_tokens));

    generate_stream(prompt_ids, params, [&](int64_t token_id) {
        generated.push_back(token_id);
    });

    return generated;
}

void SGLM::generate_stream(
    const std::vector<int64_t>& prompt_ids,
    SGLMGenParams params,
    const std::function<void(int64_t)>& on_token)
{
    constexpr int64_t EOS1 = 151643;
    constexpr int64_t EOS2 = 151645;

    std::vector<int64_t> ids = prompt_ids;

    for (int step = 0; step < params.max_new_tokens; ++step) {
        auto next_logits = forward(ids);

        const int64_t token_id = sample(
            next_logits,
            params.temperature,
            params.top_k,
            params.top_p,
            rng_);

        if (token_id == EOS1 || token_id == EOS2) break;

        // Emit token to caller
        try {
            on_token(token_id);
        } catch (...) {}

        ids.push_back(token_id);
    }
}