#include "tokenizer.hpp"
#include <fstream>
#include <sstream>
#include <algorithm>

/**
 * @brief Default constructor for Tokenizer.
 */
Tokenizer::Tokenizer() {}

/**
 * @brief Constructor with vocabulary path.
 */
Tokenizer::Tokenizer(const std::string& vocabPath) {
    configure(vocabPath);
}

/**
 * @brief Encodes text to token IDs.
 */
std::vector<int> Tokenizer::encode(const std::string& text) {
    std::vector<int> ids;
    std::istringstream iss(text);
    std::string token;
    while (iss >> token) {
        ids.push_back(lookup(token));
    }
    return ids;
}

/**
 * @brief Decodes token IDs to text.
 */
std::string Tokenizer::decode(const std::vector<int>& ids) {
    std::string result;
    for (int id : ids) {
        result += reverseLookup(id) + " ";
    }
    if (!result.empty()) result.pop_back();
    return result;
}

/**
 * @brief Looks up token ID.
 */
int Tokenizer::lookup(const std::string& token) {
    auto it = stoi.find(token);
    if (it != stoi.end()) return it->second;
    return -1;
}

/**
 * @brief Looks up token string.
 */
std::string Tokenizer::reverseLookup(int id) {
    auto it = itos.find(id);
    if (it != itos.end()) return it->second;
    return "<UNK>";
}

/**
 * @brief Subword encoding (stub).
 */
std::vector<int> Tokenizer::encodeSubword(const std::string& text) {
    return encode(text);
}

/**
 * @brief Text normalization (stub).
 */
std::string Tokenizer::normalize(const std::string& text) {
    std::string norm = text;
    std::transform(norm.begin(), norm.end(), norm.begin(), ::tolower);
    return norm;
}

/**
 * @brief Adds special token.
 */
void Tokenizer::addSpecialToken(const std::string& token) {
    specialTokens.push_back(token);
    int id = stoi.size();
    stoi[token] = id;
    itos[id] = token;
}

/**
 * @brief Configures tokenizer with vocabulary file.
 */
void Tokenizer::configure(const std::string& vocabPath) {
    stoi.clear();
    itos.clear();
    std::ifstream file(vocabPath);
    std::string token;
    int id = 0;
    while (std::getline(file, token)) {
        stoi[token] = id;
        itos[id] = token;
        ++id;
    }
}