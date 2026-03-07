/*
 * @file attention.hpp
 * @author Radmann
 * @brief Optimized attention mechanism for edge inference.
 *
 * Provides MultiQuery and GroupedQuery attention, KV cache management, and dynamic configuration.
 *
 * Methods:
 *   Attention(int heads, bool sharedKV) - Constructor.
 *   void compute(const std::vector<float>& queries, const std::vector<float>& keys, const std::vector<float>& values) - Computes attention output.
 *   std::vector<float> multiQuery(...) - MultiQuery attention computation.
 *   std::vector<float> groupedQuery(...) - GroupedQuery attention computation.
 *   void setKVCache(...) - Sets KV cache for fast inference.
 *   void clearKVCache() - Clears KV cache.
 *   void configure(int heads, bool sharedKV) - Configures attention parameters.
 *
 * Attributes:
 *   int heads - Number of attention heads.
 *   bool sharedKV - Whether keys/values are shared across heads.
 *   std::vector<float> kvCacheKeys - Cached keys.
 *   std::vector<float> kvCacheValues - Cached values.
 */
#pragma once
#include <vector>
#include <string>
#include <unordered_map>

class Attention {
public:
    Attention(int heads, bool sharedKV);
    void compute(const std::vector<float>& queries, const std::vector<float>& keys, const std::vector<float>& values);
    std::vector<float> multiQuery(const std::vector<float>& queries, const std::vector<float>& keys, const std::vector<float>& values);
    std::vector<float> groupedQuery(const std::vector<float>& queries, const std::vector<float>& keys, const std::vector<float>& values);
    void setKVCache(const std::vector<float>& keys, const std::vector<float>& values);
    void clearKVCache();
    void configure(int heads, bool sharedKV);
private:
    int heads;
    bool sharedKV;
    std::vector<float> kvCacheKeys;
    std::vector<float> kvCacheValues;
};
