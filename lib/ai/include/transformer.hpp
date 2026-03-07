/**
 * @file transformer.hpp
 * @author Radmann
 * @brief Optimized transformer backbone for home assistant model.
 */
#pragma once
#include <vector>

/**
 * @class Transformer
 * @brief Implements transformer backbone for sequence modeling.
 */
class Transformer {
public:
    /**
     * @brief Constructor for Transformer.
     * @param dimModel Model dimension.
     * @param layers Number of layers.
     * @param heads Number of attention heads.
     */
    Transformer(int dimModel, int layers, int heads);

    /**
     * @brief Forward pass through transformer.
     * @param tokens Input token sequence.
     * @param ctxTokens Context token sequence.
     * @return Output tensor.
     */
    std::vector<float> forward(const std::vector<int>& tokens, const std::vector<int>& ctxTokens);

    /**
     * @brief Loads transformer weights from file.
     * @param path Path to weights file.
     */
    void loadWeights(const std::string& path);

    /**
     * @brief Configures transformer parameters.
     * @param dimModel Model dimension.
     * @param layers Number of layers.
     * @param heads Number of attention heads.
     */
    void configure(int dimModel, int layers, int heads);
private:
    int dimModel;
    int layers;
    int heads;
    std::vector<float> weights;
};
