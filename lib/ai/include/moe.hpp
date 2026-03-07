/**
 * @file moe.hpp
 * @author Radmann
 * @brief Mixture of Experts module for home assistant model.
 */
#pragma once
#include <vector>
#include <string>

/**
 * @class MoE
 * @brief Implements Mixture of Experts routing and aggregation.
 */
class MoE {
public:
    /**
     * @brief Constructor for MoE.
     * @param numExperts Number of experts.
     */
    MoE(int numExperts);

    /**
     * @brief Routes input through experts and aggregates output.
     * @param input Input tensor.
     * @return Aggregated output tensor.
     */
    std::vector<float> route(const std::vector<float>& input);

    /**
     * @brief Loads expert weights from file.
     * @param path Path to weights file.
     */
    void loadWeights(const std::string& path);

    /**
     * @brief Selects an expert based on input.
     * @param input Input tensor.
     * @return Index of selected expert.
     */
    int selectExpert(const std::vector<float>& input);

private:
    int numExperts;
    std::vector<float> expertWeights;
};