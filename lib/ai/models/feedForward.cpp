/**
 * @file feedForward.cpp
 * @author Radmann
 * @brief Implements feedforward layer with SwiGLU, ReLU, quantization, and weight initialization.
 */
#include "../include/feedForward.hpp"
#include <cmath>
#include <fstream>
#include <sstream>

/**
 * @brief Constructor for FeedForward.
 * @param dimModel Model dimension.
 */
FeedForward::FeedForward(int dimModel)
	: dimModel(dimModel), quantizationBits(8)
{
	weights.resize(dimModel, 0.1f);
	bias.resize(dimModel, 0.0f);
}

/**
 * @brief Forward pass through feedforward layer.
 * @param input Input tensor.
 * @return Output tensor after feedforward.
 */
std::vector<float> FeedForward::forward(const std::vector<float>& input)
{
	std::vector<float> out(input.size());
	for (size_t i = 0; i < input.size(); ++i)
		out[i] = relu(input[i] * weights[i] + bias[i]);
	return out;
}

/**
 * @brief Forward pass with SwiGLU activation.
 * @param input Input tensor.
 * @return Output tensor after SwiGLU activation.
 */
std::vector<float> FeedForward::forwardSwiGLU(const std::vector<float>& input)
{
	std::vector<float> out(input.size());
	for (size_t i = 0; i < input.size(); ++i)
		out[i] = swiglu(input[i], bias[i]);
	return out;
}

/**
 * @brief Forward pass with ReLU activation.
 * @param input Input tensor.
 * @return Output tensor after ReLU activation.
 */
std::vector<float> FeedForward::forwardReLU(const std::vector<float>& input)
{
	std::vector<float> out(input.size());
	for (size_t i = 0; i < input.size(); ++i)
		out[i] = relu(input[i]);
	return out;
}

/**
 * @brief Applies SwiGLU activation to two values.
 * @param x Input value.
 * @param y Input value.
 * @return Activated value.
 */
float FeedForward::swiglu(float x, float y)
{
	return x * sigmoid(y);
}

/**
 * @brief Applies ReLU activation to a value.
 * @param x Input value.
 * @return Activated value.
 */
float FeedForward::relu(float x)
{
	return x > 0 ? x : 0;
}

/**
 * @brief Applies sigmoid activation to a value.
 * @param x Input value.
 * @return Activated value.
 */
float FeedForward::sigmoid(float x)
{
	return 1.0f / (1.0f + std::exp(-x));
}

/**
 * @brief Quantizes input tensor.
 * @param input Input tensor.
 * @return Quantized tensor.
 */
std::vector<int> FeedForward::quantize(const std::vector<float>& input)
{
	std::vector<int> out(input.size());
	float scale = (1 << quantizationBits) - 1;
	for (size_t i = 0; i < input.size(); ++i)
		out[i] = static_cast<int>(input[i] * scale);
	return out;
}

/**
 * @brief Initializes weights from vector.
 * @param w Weight vector.
 */
void FeedForward::initializeWeights(const std::vector<float>& w)
{
	weights = w;
	bias.resize(w.size(), 0.0f);
}

/**
 * @brief Initializes weights from file path.
 * @param path Path to weights file.
 * @return True if initialization succeeded, false otherwise.
 */
bool FeedForward::initializeWeights(const std::string& path)
{
	std::ifstream file(path);
	if (!file.is_open()) return false;
	weights.clear();
	bias.clear();
	std::string line;
	while (std::getline(file, line)) {
		std::istringstream iss(line);
		float w, b;
		if (!(iss >> w >> b)) continue;
		weights.push_back(w);
		bias.push_back(b);
	}
	return !weights.empty();
}

/**
 * @brief Configures layer parameters.
 * @param dimModel Model dimension.
 */
void FeedForward::configure(int dimModel)
{
	this->dimModel = dimModel;
	weights.resize(dimModel, 0.1f);
	bias.resize(dimModel, 0.0f);
}
