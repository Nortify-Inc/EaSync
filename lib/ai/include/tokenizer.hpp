#pragma once

/*
 * Tokenizer.hpp
 * ─────────────
 * Tokenizer BPE Qwen2 puro C++17.
 * Lê tokenizer.json (vocab + merges) e vocab.json.
 * Sem dependências externas além da stdlib.
 */

#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

class Tokenizer {
public:
    // Tokens especiais Qwen2
    static constexpr int64_t TOK_IM_START = 151644; // <|im_start|>
    static constexpr int64_t TOK_IM_END   = 151645; // <|im_end|>
    static constexpr int64_t TOK_EOS      = 151643; // <|endoftext|>

    /**
     * Carrega vocab + merges do tokenizer.json.
     * tokenizer_json_path : caminho para tokenizer.json
     */
    explicit Tokenizer(const std::string& tokenizer_json_path);

    /**
     * Aplica o chat e tokeniza.
     * system_prompt : mensagem de sistema (pode ser vazio)
     * user_message  : mensagem do usuário
     * Retorna sequência de token IDs pronta para o modelo.
     */
    std::vector<int64_t> encode_chat(
        const std::string& user_message,
        const std::string& system_prompt = "You are a helpful assistant.") const;

    /**
     * Tokeniza texto puro (sem chat template).
     */
    std::vector<int64_t> encode(const std::string& text) const;

    /**
     * Converte token IDs de volta para texto UTF-8.
     */
    std::string decode(const std::vector<int64_t>& ids) const;

    /**
     * Converte um único token ID para sua string.
     */
    std::string id_to_token(int64_t id) const;

    int64_t vocab_size() const { return static_cast<int64_t>(id_to_str_.size()); }

private:
    // vocab: string → id
    std::unordered_map<std::string, int64_t> str_to_id_;
    // vocab reverso: id → string (bytes raw, não UTF-8 display)
    std::unordered_map<int64_t, std::string> id_to_str_;
    // BPE merges: par de strings → rank (posição na lista de merges)
    std::unordered_map<std::string, int> merge_rank_;

    // Byte-level fallback: converte byte → token string (ex: 0x20 → "Ġ")
    std::unordered_map<uint8_t, std::string> byte_encoder_;
    std::unordered_map<std::string, uint8_t> byte_decoder_;

    void build_byte_encoder();

    // Aplica BPE sobre uma sequência de símbolos
    std::vector<std::string> bpe(const std::string& word) const;

    // Tokeniza um único "word" (segmento pré-tokenizado)
    std::vector<int64_t> encode_word(const std::string& word) const;

    // Pré-tokenização: split por espaços/pontuação preservando espaços
    std::vector<std::string> pretokenize(const std::string& text) const;

    // Insere token especial por string
    void push_special(std::vector<int64_t>& ids, const std::string& tok) const;
};