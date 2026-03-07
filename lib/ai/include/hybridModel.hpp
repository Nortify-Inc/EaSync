/*
 * @file hybridModel.hpp
 * @author Radmann
 * @brief Complete architecture for the home assistant model.
 *
 * Integrates transformer, MoE, feedforward, attention, tokenizer, memory, context encoder, and action decoder.
 * Provides planning, routing, callback, and configuration interfaces.
 *
 * Methods:
 *   HybridModel(int dimModel, int layers, int heads) - Constructor.
 *   std::vector<int> generate(...) - Generates token sequence from input/context.
 *   std::string decodeAction(...) - Decodes action tokens.
 *   void loadWeights(...) - Loads model weights.
 *   void plan(...) - Planning interface.
 *   void route(...) - Routing interface.
 *   void setMemory(...) - Sets memory module.
 *   void setContextEncoder(...) - Sets context encoder.
 *   void setCallback(...) - Sets callback function.
 *   void configure(...) - Configures model parameters.
 *
 * Attributes:
 *   Transformer transformer - Transformer backbone.
 *   MoE moe - Mixture of Experts module.
 *   FeedForward feedForward - Feed Forward layer.
 *   Attention attention - Attention mechanism.
 *   Tokenizer tokenizer - Tokenizer module.
 *   Memory* memory - Memory module pointer.
 *   ContextEncoder* contextEncoder - Context encoder pointer.
 *   ActionDecoder actionDecoder - Action decoder module.
 *   void (*callback)(const std::string&) - Callback function.
 *   int dimModel, layers, heads - Model configuration.
 */
#pragma once
#include <vector>
#include <string>
#include "transformer.hpp"
#include "moe.hpp"
#include "actionDecoder.hpp"
#include "feedForward.hpp"
#include "attention.hpp"
#include "tokenizer.hpp"
#include "memory.hpp"
#include "contextEncoder.hpp"

class HybridModel {
public:
    HybridModel(int dimModel = 448, int layers = 8, int heads = 8);
    std::vector<int> generate(const std::string& input, const std::vector<std::string>& context);
    std::string decodeAction(const std::vector<int>& tokens);
    void loadWeights(const std::string& path);
    void plan(const std::vector<int>& tokens);
    void route(const std::vector<int>& tokens);
    void setMemory(Memory* memory);
    void setContextEncoder(ContextEncoder* encoder);
    void setCallback(void (*callback)(const std::string&));
    void configure(int dimModel, int layers, int heads);
private:
    Transformer transformer;
    MoE moe;
    FeedForward feedForward;
    Attention attention;
    Tokenizer tokenizer;
    Memory* memory;
    ContextEncoder* contextEncoder;
    ActionDecoder actionDecoder;
    void (*callback)(const std::string&);
    int dimModel;
    int layers;
    int heads;
};
