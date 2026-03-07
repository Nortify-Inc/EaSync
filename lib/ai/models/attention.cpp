// @file attention.cpp
// @brief Multi Query Attention.
#include "../include/attention.hpp"

Attention::Attention(int heads, bool sharedKV)
    : heads(heads), sharedKV(sharedKV) {}

void Attention::compute(const std::vector<float>& queries, const std::vector<float>& keys, const std::vector<float>& values) {
    // Compute attention output (stub, real implementation required)
}

std::vector<float> Attention::multiQuery(const std::vector<float>& queries, const std::vector<float>& keys, const std::vector<float>& values) {
    // MultiQuery attention computation (stub)
    return {};
}

std::vector<float> Attention::groupedQuery(const std::vector<float>& queries, const std::vector<float>& keys, const std::vector<float>& values) {
    // GroupedQuery attention computation (stub)
    return {};
}

void Attention::setKVCache(const std::vector<float>& keys, const std::vector<float>& values) {
    kvCacheKeys = keys;
    kvCacheValues = values;
}

void Attention::clearKVCache() {
    kvCacheKeys.clear();
    kvCacheValues.clear();
}

void Attention::configure(int heads, bool sharedKV) {
    this->heads = heads;
    this->sharedKV = sharedKV;
}
