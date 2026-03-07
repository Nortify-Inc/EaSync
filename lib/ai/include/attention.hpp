/**
 * @file attention.hpp
 * @author Radmann
 * @brief Optimized attention mechanism for edge inference.
 *
 * Provides MultiQuery and GroupedQuery attention, KV cache management, and dynamic configuration.
 */
#pragma once
#include <vector>
#include <string>
#include <utility>

/**
 * @class Attention
 * @brief Implements multi-query, grouped-query, and KV cache attention mechanisms.
 */
class Attention {
public:
    /**
     * @brief Constructor for Attention.
     * @param heads Number of attention heads.
     * @param sharedKV Whether keys/values are shared across heads.
     */
    Attention(int heads, bool sharedKV);

    /**
     * @brief Computes attention output.
     * @param queries Query tensor.
     * @param keys Key tensor.
     * @param values Value tensor.
     */
    void compute(const std::vector<float>& queries,
                const std::vector<float>& keys,
                const std::vector<float>& values);

    /**
     * @brief MultiQuery attention computation.
     * @param query Query tensor.
     * @param key Key tensor.
     * @param value Value tensor.
     * @return Output tensor after attention.
     */
    std::vector<float> multiQuery(const std::vector<float>& query,
                                 const std::vector<float>& key,
                                 const std::vector<float>& value);

    /**
     * @brief GroupedQuery attention computation.
     * @param queries List of query tensors.
     * @param keys List of key tensors.
     * @param values List of value tensors.
     * @return Output tensor after grouped attention.
     */
    std::vector<float> groupedQuery(const std::vector<std::vector<float>>& queries,
                                   const std::vector<std::vector<float>>& keys,
                                   const std::vector<std::vector<float>>& values);

    /**
     * @brief Sets KV cache for fast inference.
     * @param keys Cached keys.
     * @param values Cached values.
     */
    void setKVCache(const std::vector<float>& keys,
                   const std::vector<float>& values);

    /**
     * @brief Clears KV cache.
     */
    void clearKVCache();

    /**
     * @brief Configures attention parameters.
     * @param heads Number of attention heads.
     * @param sharedKV Whether keys/values are shared across heads.
     */
    void configure(int heads, bool sharedKV);

private:
    int heads;
    bool sharedKV;
    std::vector<float> kvCacheKeys;
    std::vector<float> kvCacheValues;
    std::vector<std::pair<std::vector<float>, std::vector<float>>> kvCache; ///< Key-value cache for advanced attention
};
