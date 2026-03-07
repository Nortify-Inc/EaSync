// @file buildVocab.cpp
// @brief Constrói vocabulário do tokenizer.
#include <fstream>
#include <unordered_map>
#include <vector>
#include <string>

int main() {
    // Exemplo: ler commands.json e gerar vocab.pkl
    std::ifstream in("../data/commands.json");
    std::unordered_map<std::string, int> freq;
    // ...parse JSON e contar tokens...
    // ...salvar vocab.pkl...
    return 0;
}
