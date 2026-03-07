/**
 * @file feedForward.hpp
 * @author Radmann
 * @brief Feed Forward layer with SwiGLU activation and quantization support.
 *
 * Provides methods for forward computation, activation selection, weight initialization, quantization, and configuration.
 */
#pragma once
#include <vector>
#include <string>

/**
 * @class FeedForward
 * @brief Implements feedforward layer with advanced activations and quantization.
 */
class FeedForward {
public:
    /**
     * @brief Constructor for FeedForward.
     * @param dimModel Model dimension.
     */
    FeedForward(int dimModel);

    /**
     * @brief Forward pass through feedforward layer.
     * @param input Input tensor.
     * @return Output tensor after feedforward.
     */
    std::vector<float> forward(const std::vector<float>& input);

    /**
     * @brief Forward pass with SwiGLU activation.
     * @param input Input tensor.
     * @return Output tensor after SwiGLU activation.
     */
    std::vector<float> forwardSwiGLU(const std::vector<float>& input);

    /**
     * @brief Forward pass with ReLU activation.
     * @param input Input tensor.
     * @return Output tensor after ReLU activation.
     */
    std::vector<float> forwardReLU(const std::vector<float>& input);

    /**
     * @brief Applies SwiGLU activation to two values.
     * @param x Input value.
     * @param y Input value.
     * @return Activated value.
     */
    float swiglu(float x, float y);

    /**
     * @brief Applies ReLU activation to a value.
     * @param x Input value.
     * @return Activated value.
     */
    float relu(float x);

    /**
     * @brief Applies Sigmoid activation to a value.
     * @param x Input value.
     * @return Activated value.
     */
    float sigmoid(float x);
    /**
     * @brief Quantizes input tensor.
     * @param input Input tensor.
     * @return Quantized tensor.
     */
    std::vector<int> quantize(const std::vector<float>& input);

    /**
     * @brief Initializes weights from file or vector.
     * @param weights Weight vector.
     */
    void initializeWeights(const std::vector<float>& weights);

    /**
     * @brief Initializes weights from file path.
     * @param path Path to weights file.
     * @return True if initialization succeeded, false otherwise.
     */
    bool initializeWeights(const std::string& path);

    /**
     * @brief Configures layer parameters.
     * @param dimModel Model dimension.
     */
    void configure(int dimModel);

private:
    int dimModel;
    std::vector<float> weights;
    std::vector<float> bias;
    int quantizationBits;
};
