/*
 * tokenizer.cpp
 * ─────────────
 * Implementação do tokenizer BPE Qwen2.
 * Lê tokenizer.json usando um parser JSON mínimo embutido.
 */

#include "tokenizer.hpp"

#include <algorithm>
#include <cassert>
#include <climits>
#include <fstream>
#include <regex>
#include <set>
#include <sstream>
#include <stdexcept>

// ─────────────────────────────────────────────────────────────────────────────
//  Parser JSON mínimo (apenas o subconjunto necessário)
// ─────────────────────────────────────────────────────────────────────────────
namespace json_mini {

// Extrai o valor de uma chave string dentro de um objeto JSON como string raw.
// Suporta apenas o nível superficial (não recursivo).
static std::string get_string(const std::string& json, const std::string& key)
{
    std::string needle = "\"" + key + "\"";
    auto pos = json.find(needle);
    if (pos == std::string::npos) return {};
    auto colon = json.find(':', pos + needle.size());
    if (colon == std::string::npos) return {};
    auto q1 = json.find('"', colon + 1);
    if (q1 == std::string::npos) return {};
    std::string val;
    bool esc = false;
    for (size_t i = q1 + 1; i < json.size(); ++i) {
        char c = json[i];
        if (esc) { val += c; esc = false; }
        else if (c == '\\') esc = true;
        else if (c == '"') break;
        else val += c;
    }
    return val;
}

// Extrai o bloco entre a primeira ocorrência de '{' e seu '}' correspondente
// após a posição `start`.
static std::string extract_object(const std::string& json, size_t start)
{
    int depth = 0;
    size_t begin = std::string::npos;
    for (size_t i = start; i < json.size(); ++i) {
        if (json[i] == '{') {
            if (depth == 0) begin = i;
            ++depth;
        } else if (json[i] == '}') {
            --depth;
            if (depth == 0 && begin != std::string::npos)
                return json.substr(begin, i - begin + 1);
        }
    }
    return {};
}

// Extrai o array JSON após uma chave como vetor de strings (valores string).
static std::vector<std::string> get_string_array(const std::string& json,
                                                   const std::string& key)
{
    std::string needle = "\"" + key + "\"";
    auto pos = json.find(needle);
    if (pos == std::string::npos) return {};
    auto bracket = json.find('[', pos);
    if (bracket == std::string::npos) return {};

    std::vector<std::string> result;
    size_t i = bracket + 1;
    while (i < json.size()) {
        // skip whitespace
        while (i < json.size() && std::isspace((unsigned char)json[i])) ++i;
        if (json[i] == ']') break;
        if (json[i] == '"') {
            std::string val;
            bool esc = false;
            ++i;
            for (; i < json.size(); ++i) {
                char c = json[i];
                if (esc) { val += c; esc = false; }
                else if (c == '\\') esc = true;
                else if (c == '"') { ++i; break; }
                else val += c;
            }
            result.push_back(val);
        } else {
            ++i;
        }
    }
    return result;
}

// Itera sobre os pares chave-valor de um objeto JSON plano {"k":"v",...}
// e chama callback(key, value) para cada par string:string.
static void iter_string_pairs(const std::string& obj,
                               std::function<void(const std::string&,
                                                   const std::string&)> cb)
{
    size_t i = 0;
    while (i < obj.size()) {
        // Find key
        auto q1 = obj.find('"', i);
        if (q1 == std::string::npos) break;
        std::string key;
        bool esc = false;
        size_t j = q1 + 1;
        for (; j < obj.size(); ++j) {
            char c = obj[j];
            if (esc) { key += c; esc = false; }
            else if (c == '\\') esc = true;
            else if (c == '"') { ++j; break; }
            else key += c;
        }
        // Find colon
        auto colon = obj.find(':', j);
        if (colon == std::string::npos) break;
        i = colon + 1;
        // Skip whitespace
        while (i < obj.size() && std::isspace((unsigned char)obj[i])) ++i;
        if (i >= obj.size()) break;

        if (obj[i] == '"') {
            // string value
            std::string val;
            esc = false;
            ++i;
            for (; i < obj.size(); ++i) {
                char c = obj[i];
                if (esc) { val += c; esc = false; }
                else if (c == '\\') esc = true;
                else if (c == '"') { ++i; break; }
                else val += c;
            }
            cb(key, val);
        } else {
            // skip non-string value (number, bool, null, object, array)
            // find next comma or closing brace
            int depth = 0;
            for (; i < obj.size(); ++i) {
                char c = obj[i];
                if (c == '{' || c == '[') ++depth;
                else if (c == '}' || c == ']') {
                    if (depth == 0) break;
                    --depth;
                }
                else if (c == ',' && depth == 0) { ++i; break; }
            }
        }
    }
}

} // namespace json_mini

// ─────────────────────────────────────────────────────────────────────────────
//  Byte encoder/decoder (GPT-2 style)
//  Mapeia bytes 0-255 para caracteres Unicode imprimíveis.
// ─────────────────────────────────────────────────────────────────────────────
void Tokenizer::build_byte_encoder()
{
    // Bytes que já são caracteres imprimíveis ASCII
    std::vector<int> bs;
    for (int c = '!'; c <= '~'; ++c) bs.push_back(c);
    for (int c = 0xA1; c <= 0xAC; ++c) bs.push_back(c);
    for (int c = 0xAE; c <= 0xFF; ++c) bs.push_back(c);

    std::vector<int> cs = bs;
    int n = 0;
    for (int b = 0; b < 256; ++b) {
        if (std::find(bs.begin(), bs.end(), b) == bs.end()) {
            bs.push_back(b);
            cs.push_back(256 + n++);
        }
    }

    for (size_t i = 0; i < bs.size(); ++i) {
        // Encode Unicode codepoint cs[i] as UTF-8
        std::string utf8;
        int cp = cs[i];
        if (cp < 0x80) {
            utf8 += static_cast<char>(cp);
        } else if (cp < 0x800) {
            utf8 += static_cast<char>(0xC0 | (cp >> 6));
            utf8 += static_cast<char>(0x80 | (cp & 0x3F));
        } else {
            utf8 += static_cast<char>(0xE0 | (cp >> 12));
            utf8 += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
            utf8 += static_cast<char>(0x80 | (cp & 0x3F));
        }
        byte_encoder_[static_cast<uint8_t>(bs[i])] = utf8;
        byte_decoder_[utf8] = static_cast<uint8_t>(bs[i]);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Construtor: carrega tokenizer.json
// ─────────────────────────────────────────────────────────────────────────────
Tokenizer::Tokenizer(const std::string& tokenizer_json_path)
{
    build_byte_encoder();

    // Lê o arquivo inteiro
    std::ifstream f(tokenizer_json_path);
    if (!f.is_open())
        throw std::runtime_error("Tokenizer: não foi possível abrir " + tokenizer_json_path);

    std::ostringstream ss;
    ss << f.rdbuf();
    const std::string json = ss.str();

    // ── 1. Carrega vocab (model.vocab) ────────────────────────────────────
    // tokenizer.json HuggingFace: {"model": {"vocab": {"token": id, ...}, "merges": [...]}}
    auto model_pos = json.find("\"model\"");
    if (model_pos == std::string::npos)
        throw std::runtime_error("Tokenizer: campo 'model' não encontrado");

    auto model_obj = json_mini::extract_object(json, model_pos);

    // vocab object
    auto vocab_pos = model_obj.find("\"vocab\"");
    if (vocab_pos == std::string::npos)
        throw std::runtime_error("Tokenizer: campo 'vocab' não encontrado");

    auto vocab_obj = json_mini::extract_object(model_obj, vocab_pos);
    json_mini::iter_string_pairs(vocab_obj, [&](const std::string& tok, const std::string& id_str) {
        try {
            int64_t id = std::stoll(id_str);
            str_to_id_[tok] = id;
            id_to_str_[id]  = tok;
        } catch (...) {}
    });

    // ── 2. Carrega merges ─────────────────────────────────────────────────
    auto merges = json_mini::get_string_array(model_obj, "merges");
    for (int rank = 0; rank < static_cast<int>(merges.size()); ++rank)
        merge_rank_[merges[rank]] = rank;

    // ── 3. Carrega added_tokens (tokens especiais) ────────────────────────
    // Já estão no vocab, mas garante pelo campo added_tokens
    auto added_pos = json.find("\"added_tokens\"");
    if (added_pos != std::string::npos) {
        // Array de objetos: [{"id":N,"content":"...", ...}, ...]
        auto bracket = json.find('[', added_pos);
        if (bracket != std::string::npos) {
            size_t i = bracket + 1;
            while (i < json.size()) {
                while (i < json.size() && std::isspace((unsigned char)json[i])) ++i;
                if (i >= json.size() || json[i] == ']') break;
                if (json[i] == '{') {
                    auto obj = json_mini::extract_object(json, i);
                    auto content = json_mini::get_string(obj, "content");
                    auto id_str  = json_mini::get_string(obj, "id");
                    if (!content.empty() && !id_str.empty()) {
                        try {
                            int64_t id = std::stoll(id_str);
                            str_to_id_[content] = id;
                            id_to_str_[id]      = content;
                        } catch (...) {}
                    }
                    i += obj.size();
                } else {
                    ++i;
                }
            }
        }
    }

    if (str_to_id_.empty())
        throw std::runtime_error("Tokenizer: vocab vazio após carregamento");
}

// ─────────────────────────────────────────────────────────────────────────────
//  BPE
// ─────────────────────────────────────────────────────────────────────────────
std::vector<std::string> Tokenizer::bpe(const std::string& word) const
{
    // Converte cada byte do word para sua representação byte_encoder
    std::vector<std::string> symbols;
    // word é UTF-8; iteramos byte a byte
    for (unsigned char c : word) {
        auto it = byte_encoder_.find(c);
        if (it != byte_encoder_.end())
            symbols.push_back(it->second);
        else
            symbols.push_back(std::string(1, static_cast<char>(c)));
    }

    if (symbols.size() <= 1) return symbols;

    // Aplica merges iterativamente
    while (symbols.size() > 1) {
        // Encontra o par com menor rank
        int best_rank = INT_MAX;
        size_t best_i = 0;
        bool found = false;

        for (size_t i = 0; i + 1 < symbols.size(); ++i) {
            std::string pair = symbols[i] + " " + symbols[i + 1];
            auto it = merge_rank_.find(pair);
            if (it != merge_rank_.end() && it->second < best_rank) {
                best_rank = it->second;
                best_i    = i;
                found     = true;
            }
        }

        if (!found) break;

        // Funde o par
        std::string merged = symbols[best_i] + symbols[best_i + 1];
        symbols.erase(symbols.begin() + static_cast<std::ptrdiff_t>(best_i + 1));
        symbols[best_i] = merged;
    }

    return symbols;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Pré-tokenização (Qwen2 usa o mesmo padrão do GPT-2)
// ─────────────────────────────────────────────────────────────────────────────
std::vector<std::string> Tokenizer::pretokenize(const std::string& text) const
{
    // Regex do GPT-2: separa contração, letras, números e outros
    static const std::regex pat(
        R"('s|'t|'re|'ve|'m|'ll|'d| ?[[:alpha:]]+| ?[[:digit:]]+| ?[^\s[:alpha:][:digit:]]+|\s+(?!\S)|\s+)",
        std::regex::optimize
    );

    std::vector<std::string> tokens;
    auto begin = std::sregex_iterator(text.begin(), text.end(), pat);
    auto end   = std::sregex_iterator();
    for (auto it = begin; it != end; ++it)
        tokens.push_back(it->str());
    return tokens;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Encode palavra individual
// ─────────────────────────────────────────────────────────────────────────────
std::vector<int64_t> Tokenizer::encode_word(const std::string& word) const
{
    auto pieces = bpe(word);
    std::vector<int64_t> ids;
    ids.reserve(pieces.size());
    for (const auto& p : pieces) {
        auto it = str_to_id_.find(p);
        if (it != str_to_id_.end())
            ids.push_back(it->second);
        // Se não encontrou (raro), ignora — poderia usar unk mas Qwen2 não tem
    }
    return ids;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Encode texto puro
// ─────────────────────────────────────────────────────────────────────────────
std::vector<int64_t> Tokenizer::encode(const std::string& text) const
{
    std::vector<int64_t> ids;
    for (const auto& word : pretokenize(text)) {
        auto word_ids = encode_word(word);
        ids.insert(ids.end(), word_ids.begin(), word_ids.end());
    }
    return ids;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Insere token especial por string
// ─────────────────────────────────────────────────────────────────────────────
void Tokenizer::push_special(std::vector<int64_t>& ids, const std::string& tok) const
{
    auto it = str_to_id_.find(tok);
    if (it != str_to_id_.end())
        ids.push_back(it->second);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Encode com chat template Qwen2
//
//  Formato:
//    <|im_start|>system\n{system}<|im_end|>\n
//    <|im_start|>user\n{user}<|im_end|>\n
//    <|im_start|>assistant\n
// ─────────────────────────────────────────────────────────────────────────────
std::vector<int64_t> Tokenizer::encode_chat(
    const std::string& user_message,
    const std::string& system_prompt) const
{
    std::vector<int64_t> ids;
    ids.reserve(512);

    auto push_text = [&](const std::string& t) {
        auto tids = encode(t);
        ids.insert(ids.end(), tids.begin(), tids.end());
    };

    // <|im_start|>system\n
    push_special(ids, "<|im_start|>");
    push_text("system\n");
    push_text(system_prompt);
    push_special(ids, "<|im_end|>");
    push_text("\n");

    // <|im_start|>user\n
    push_special(ids, "<|im_start|>");
    push_text("user\n");
    push_text(user_message);
    push_special(ids, "<|im_end|>");
    push_text("\n");

    // <|im_start|>assistant\n  (geração começa aqui)
    push_special(ids, "<|im_start|>");
    push_text("assistant\n");

    return ids;
}

// ─────────────────────────────────────────────────────────────────────────────
//  id_to_token
// ─────────────────────────────────────────────────────────────────────────────
std::string Tokenizer::id_to_token(int64_t id) const
{
    auto it = id_to_str_.find(id);
    if (it == id_to_str_.end()) return "";
    return it->second;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Decode: IDs → UTF-8
// ─────────────────────────────────────────────────────────────────────────────
std::string Tokenizer::decode(const std::vector<int64_t>& ids) const
{
    // 1. Concatena as strings dos tokens
    std::string raw;
    for (int64_t id : ids) {
        auto it = id_to_str_.find(id);
        if (it == id_to_str_.end()) continue;
        // Pula tokens especiais na decodificação
        if (id >= 151643) continue;
        raw += it->second;
    }

    // 2. Decodifica byte-level: cada "caractere" da string raw pode ser
    //    uma sequência UTF-8 que representa um byte original.
    std::string result;
    result.reserve(raw.size());

    size_t i = 0;
    while (i < raw.size()) {
        // Tenta match de 1, 2 ou 3 bytes UTF-8 no byte_decoder_
        bool found = false;
        for (int len : {3, 2, 1}) {
            if (i + len > raw.size()) continue;
            std::string chunk = raw.substr(i, len);
            auto it = byte_decoder_.find(chunk);
            if (it != byte_decoder_.end()) {
                result += static_cast<char>(it->second);
                i += len;
                found = true;
                break;
            }
        }
        if (!found) {
            // Passa o byte diretamente (já é ASCII válido)
            result += raw[i++];
        }
    }

    return result;
}