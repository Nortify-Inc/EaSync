#pragma once

#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

class Tokenizer {

    std::vector<int64_t> encode_chat_with_history(
        const std::string& user_message,
        const std::string& system_prompt,
        const std::string& prev_user,
        const std::string& prev_assistant) const;
        
public:
    // AgentLM tokenizer.json: 0=<|endoftext|>, 1=<|im_start|>, 2=<|im_end|>
    static constexpr int64_t TOK_EOT      = 0; // <|endoftext|>
    static constexpr int64_t TOK_IM_START = 1; // <|im_start|>
    static constexpr int64_t TOK_IM_END   = 2; // <|im_end|>

    explicit Tokenizer(const std::string& tokenizer_json_path);

    std::vector<int64_t> encode_chat(
        const std::string& user_message,
        const std::string& system_prompt = "You are a helpful assistant.") const;


    std::vector<int64_t> encode(const std::string& text) const;

    std::string decode(const std::vector<int64_t>& ids) const;

    std::string id_to_token(int64_t id) const;

    int64_t vocab_size() const { return static_cast<int64_t>(id_to_str_.size()); }

private:
    std::unordered_map<std::string, int64_t> str_to_id_;
    std::unordered_map<int64_t, std::string> id_to_str_;
    std::unordered_map<std::string, int> merge_rank_;

    std::unordered_map<uint8_t, std::string> byte_encoder_;
    std::unordered_map<std::string, uint8_t> byte_decoder_;

    void build_byte_encoder();

    std::vector<std::string> bpe(const std::string& word) const;

    std::vector<int64_t> encode_word(const std::string& word) const;

    std::vector<std::string> pretokenize(const std::string& text) const;

    void push_special(std::vector<int64_t>& ids, const std::string& tok) const;
};