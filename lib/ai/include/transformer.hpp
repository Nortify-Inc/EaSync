// @file transformer.hpp
// @brief Estrutura do transformer otimizado.
#pragma once
#include <vector>

class Transformer {
public:
    Transformer(int dimModel, int layers, int heads);
    std::vector<float> forward(const std::vector<int>& tokens);
};
