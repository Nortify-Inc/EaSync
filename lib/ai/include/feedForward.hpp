/*
 * @file feedForward.hpp
 * @author Radmann
 * @brief Feed Forward layer with SwiGLU activation and quantization support.
 *
 * Provides methods for forward computation, activation selection, weight initialization, and quantization.
 *
 * Methods:
 *   FeedForward(int dimModel) - Constructor.
 *   std::vector<float> forward(const std::vector<float>& input) - Forward pass.
 *   std::vector<float> forwardSwiGLU(...) - SwiGLU activation forward.
 *   std::vector<float> forwardReLU(...) - ReLU activation forward.
 *   void quantize(int bits) - Quantizes weights.
 *   void initializeWeights(...) - Initializes weights.
 *   void configure(int dimModel) - Configures layer parameters.
 *
 * Attributes:
 *   int dimModel - Model dimension.
 *   std::vector<float> weights - Layer weights.
 *   int quantizationBits - Quantization bit width.
 */
#pragma once
#include <vector>
#include <string>

class FeedForward {
public:
    FeedForward(int dimModel);
    std::vector<float> forward(const std::vector<float>& input);
    std::vector<float> forwardSwiGLU(const std::vector<float>& input);
    std::vector<float> forwardReLU(const std::vector<float>& input);
    void quantize(int bits);
    void initializeWeights(const std::vector<float>& weights);
    void configure(int dimModel);
private:
    int dimModel;
    std::vector<float> weights;
    int quantizationBits;
};
