#include <string>
#include <vector>
#include <functional>
#include "../include/moe.hpp"

/**
 * @brief Constructor for MoE.
 * @param numExperts Number of experts.
 */
MoE::MoE(int numExperts)
    : numExperts(numExperts)
{
    expertWeights.resize(numExperts, 1.0f);
}

/**
 * @brief Routes input through experts and aggregates output.
 * @param input Input tensor.
 * @return Aggregated output tensor.
 */
std::vector<float> MoE::route(const std::vector<float>& input)
{
    std::vector<float> out(input.size(), 0.0f);
    for (int e = 0; e < numExperts; ++e) {
        float weight = expertWeights[e];
        for (size_t i = 0; i < input.size(); ++i)
            out[i] += input[i] * weight / numExperts;
    }
    return out;
}

/**
 * @brief Loads expert weights from file.
 * @param path Path to weights file.
 */
void MoE::loadWeights(const std::string& path)
{
    // Example: load weights from file
    for (auto& w : expertWeights) w = 1.0f;
}

/**
 * @brief Selects expert based on input tensor.
 * @param input Input tensor.
 * @return Selected expert index.
 */
int MoE::selectExpert(const std::vector<float>& input)
{
    // Example: select expert based on sum of input values
    float sum = 0.0f;
    for (float v : input) sum += v;
    return static_cast<int>(std::abs(sum)) % numExperts;
}
/**
 * @file moe.cpp
 * @author Radmann
 * @brief Implements Mixture of Experts routing for the home assistant model.
 */
#include "../include/moe.hpp"
#include <cmath>
#include <algorithm>

/**
 * @brief Constructor for MoE.
 * @param numExperts Number of experts.
 */
MoE::MoE(int numExperts)
    : numExperts(numExperts)
{
    // Initialize expert weights
    expertWeights.resize(numExperts, 1.0f);
}

/**
 * @brief Routes input through experts and aggregates output.
 * @param input Input tensor.
 * @return Aggregated output tensor.
 */
std::vector<float> MoE::route(const std::vector<float>& input)
{
    std::vector<float> out(input.size(), 0.0f);
    for (int e = 0; e < numExperts; ++e) {
        float weight = expertWeights[e];
        for (size_t i = 0; i < input.size(); ++i)
            out[i] += input[i] * weight / numExperts;
    }
    return out;
}
