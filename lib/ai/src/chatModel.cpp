#include "../include/chatModel.hpp"
#include <fstream>
#include <nlohmann/json.hpp>
#include <sstream>

ChatModel::ChatModel(const std::string& modelPath, const std::string& vocabPath) {
    model = torch::jit::load(modelPath);
    std::ifstream f(vocabPath);
    nlohmann::json j;
    f >> j;
    for (size_t i = 0; i < j.size(); ++i) {
        stoi[j[i]] = i;
        itos[i] = j[i];
    }
}

std::string ChatModel::generate(const std::string& prompt) {
    std::vector<int> input;
    std::istringstream iss(prompt);
    std::string tok;
    while (iss >> tok) input.push_back(stoi.count(tok) ? stoi[tok] : 0);
    input.insert(input.begin(), stoi["<SOS>"]);
    std::vector<int> result = input;
    torch::Tensor inp = torch::tensor(input).unsqueeze(0);
    torch::Tensor h;
    for (int i = 0; i < 30; ++i) {
        auto out_tuple = model.forward({inp, h});
        auto out = out_tuple.toTuple()->elements()[0].toTensor();
        int next_token = out[0, -1].argmax().item<int>();
        result.push_back(next_token);
        if (itos[next_token] == "<EOS>") break;
        inp = torch::tensor({next_token}).unsqueeze(0);
    }
    std::string out;
    for (int i : result) out += itos[i] + " ";
    return out;
}
