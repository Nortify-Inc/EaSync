#include <torch/script.h>
#include <vector>
#include <string>
#include <fstream>
#include <nlohmann/json.hpp>

class Tokenizer {
public:
    Tokenizer(const std::string& vocabPath) {
        std::ifstream f(vocabPath);
        nlohmann::json j;
        f >> j;
        for (size_t i = 0; i < j.size(); ++i) {
            stoi[j[i]] = i;
            itos[i] = j[i];
        }
    }
    std::vector<int> encode(const std::string& text) {
        std::vector<int> ids;
        std::istringstream iss(text);
        std::string tok;
        while (iss >> tok) ids.push_back(stoi.count(tok) ? stoi[tok] : 0);
        return ids;
    }
    std::string decode(const std::vector<int>& ids) {
        std::string out;
        for (int i : ids) out += itos.count(i) ? itos[i] + " " : "<UNK> ";
        return out;
    }
private:
    std::unordered_map<std::string, int> stoi;
    std::unordered_map<int, std::string> itos;
};

int main(int argc, char** argv) {
    torch::jit::script::Module model = torch::jit::load("lib/ai/models/chat_model.pt");
    Tokenizer tokenizer("lib/ai/data/vocab.json");
    std::string prompt = argc > 1 ? argv[1] : "";
    std::vector<int> input = tokenizer.encode(prompt);
    input.insert(input.begin(), tokenizer.encode("<SOS>")[0]);
    std::vector<int> result = input;
    torch::Tensor inp = torch::tensor(input).unsqueeze(0);
    torch::Tensor h;
    for (int i = 0; i < 30; ++i) {
        auto out_tuple = model.forward({inp, h});
        auto out = out_tuple.toTuple()->elements()[0].toTensor();
        int next_token = out[0, -1].argmax().item<int>();
        result.push_back(next_token);
        if (tokenizer.decode({next_token}) == "<EOS> ") break;
        inp = torch::tensor({next_token}).unsqueeze(0);
    }
    std::cout << tokenizer.decode(result) << std::endl;
    return 0;
}
