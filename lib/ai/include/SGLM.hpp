#pragma once

#include <onnxruntime_cxx_api.h>

#include <cstdint>
#include <memory>
#include <string>
#include <vector>
#include <random>
#include <functional>

struct SGLMConfig {
    int   intra_op_threads = 4;
    int   inter_op_threads = 1;
    bool  use_gpu          = false;
    int   cuda_device_id   = 0;
    bool  verbose          = false;
};

struct SGLMGenParams {
    int   max_new_tokens = 512;
    float temperature    = 0.9f;
    int   top_k          = 40;
    float top_p          = 0.95f;
};

class SGLM {
public:
    explicit SGLM(const std::string& model_path, SGLMConfig cfg = {});
    ~SGLM() = default;

    SGLM(const SGLM&)            = delete;
    SGLM& operator=(const SGLM&) = delete;
    SGLM(SGLM&&)                 = default;
    SGLM& operator=(SGLM&&)      = default;

    std::vector<float> forward(const std::vector<int64_t>& token_ids);

    std::vector<int64_t> generate(
        const std::vector<int64_t>& prompt_ids,
        SGLMGenParams params = {});

    void generate_stream(
        const std::vector<int64_t>& prompt_ids,
        SGLMGenParams params,
        const std::function<void(int64_t)>& on_token);

    int64_t vocab_size() const { return vocab_size_; }

private:
    Ort::Env                      env_;
    std::unique_ptr<Ort::Session> session_;
    int64_t                       vocab_size_ = 0;
    std::mt19937                  rng_;
    std::string                   input_ids_name_ = "token_ids";
    std::string                   attention_mask_name_;
    bool                          has_attention_mask_ = false;
    std::string                   output_logits_name_ = "logits";

    static int64_t sample(
        std::vector<float>& logits,
        float temperature,
        int   top_k,
        float top_p,
        std::mt19937& rng);
};