#pragma once
#include <torch/script.h>
#include <string>
#include <vector>

class ChatModel {
public:
    ChatModel(const std::string& modelPath, const std::string& vocabPath);
    std::string generate(const std::string& prompt);
private:
    torch::jit::script::Module model;
    std::unordered_map<std::string, int> stoi;
    std::unordered_map<int, std::string> itos;
};
