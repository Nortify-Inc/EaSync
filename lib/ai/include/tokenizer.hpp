/*
 * @file tokenizer.hpp
 * @author Radmann
 * @brief Tokenizer module for text encoding and decoding.
 *
 * Supports subword encoding, normalization, special tokens, and vocabulary management.
 *
 * Methods:
 *   Tokenizer(const std::string& vocabPath) - Constructor.
 *   std::vector<int> encode(const std::string& text) - Encodes text to token IDs.
 *   std::string decode(const std::vector<int>& ids) - Decodes token IDs to text.
 *   int lookup(const std::string& token) - Looks up token ID.
 *   std::string reverseLookup(int id) - Looks up token string.
 *   std::vector<int> encodeSubword(...) - Subword encoding.
 *   std::string normalize(...) - Text normalization.
 *   void addSpecialToken(...) - Adds special token.
 *   void configure(...) - Configures tokenizer.
 *
 * Attributes:
 *   std::unordered_map<std::string, int> stoi - Token to ID map.
 *   std::unordered_map<int, std::string> itos - ID to token map.
 *   std::vector<std::string> specialTokens - List of special tokens.
 */
#pragma once
#include <string>
#include <vector>
#include <unordered_map>

class Tokenizer {
public:
    Tokenizer(const std::string& vocabPath);
    std::vector<int> encode(const std::string& text);
    std::string decode(const std::vector<int>& ids);
    int lookup(const std::string& token);
    std::string reverseLookup(int id);
    std::vector<int> encodeSubword(const std::string& text);
    std::string normalize(const std::string& text);
    void addSpecialToken(const std::string& token);
    void configure(const std::string& vocabPath);
private:
    std::unordered_map<std::string, int> stoi;
    std::unordered_map<int, std::string> itos;
    std::vector<std::string> specialTokens;
};
