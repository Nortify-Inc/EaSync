// @file moe.hpp
// @brief Mixture of Experts.
#pragma once
#include <vector>

class MoE {
public:
    MoE(int numExperts);
    std::vector<float> route(const std::vector<float>& input);
};
